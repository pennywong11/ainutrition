// lib/notifications/notification_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return AppNotification(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      read: data['read'] ?? false,
    );
  }
}

class NotificationRepository {
  static final _db = FirebaseFirestore.instance;

  // TODO: 未讀數量
  static Stream<int> unreadCountStream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  // 今日通知
  static Stream<List<AppNotification>> todayNotificationsStream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final startOfToday = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
        )
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map(AppNotification.fromFirestore).toList(),
        );
  }

  // 所有通知
  static Stream<List<AppNotification>> allNotificationsStream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map(AppNotification.fromFirestore).toList(),
        );
  }

  // 標記單筆已讀
  static Future<void> markAsRead(String notificationId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  // 標記全部已讀
  static Future<void> markAllAsRead() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();

    final batch = _db.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  // 從 FCM 訊息儲存通知到 Firestore
  static Future<void> saveFromFCM(RemoteMessage message) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final title = message.notification?.title ?? '通知';
    final body = message.notification?.body ?? '';
    final data = message.data; // 可選，未來要用再說

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .add({
      'title': title,
      'body': body,
      'data': data,            
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
