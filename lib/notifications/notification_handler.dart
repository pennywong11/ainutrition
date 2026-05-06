// lib/notifications/notification_handler.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_repository.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class NotificationHandler {
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  // 初始化
  static Future<void> init() async {
    await _initLocalNotification();
    await _initFCM(); 
    _initFCMListener();
  }

  // 本地通知初始化
  static Future<void> _initLocalNotification() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _localNotifications.initialize(settings);
  }

  static Future<void> _initFCM() async {
    final messaging = FirebaseMessaging.instance;

    // 請求通知權限
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint("未允許通知權限");
      return;
    }
    debugPrint("允許通知權限");

    // 取得 Token
    String? token;
    try {
      if (kIsWeb) {
        final vapidKey = dotenv.env['VAPID_KEY'];

        if (vapidKey == null || vapidKey.isEmpty) {
          debugPrint("VAPID_KEY 未設定");
          return;
        }

        token = await messaging.getToken(
          vapidKey: vapidKey,
        );
      } else {
        token = await messaging.getToken();
      }
    } catch (e) {
      debugPrint("取得 token 錯誤: $e");
      return;
    }

    if (token == null) {
      debugPrint("取得 FCM Token 失敗");
      return;
    }

    debugPrint("FCM Token: $token");
    
    // 訂閱主題
    // await FirebaseMessaging.instance.subscribeToTopic("all");

    // 註冊裝置（存 Firestore）
    await _saveToken(token);

    // Token 更新監聽
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint("Token 更新: $newToken");
      await _saveToken(newToken);
    });
  }

  // 儲存 token
  static Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint("未登入，不儲存 token");
      return;
    }

    await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("tokens")
        .doc(token)
        .set({
      "token": token,
      "platform": kIsWeb ? "web" : defaultTargetPlatform.name,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint("token 已儲存");
  }

  // CM 監聽
  static void _initFCMListener() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final title = message.notification?.title ?? message.data['title'];
    final body = message.notification?.body ?? message.data['body'];

    if (title == null || body == null) return;

    // 👉 前景一定手動顯示
    await _localNotifications.show(
      title.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'default_channel',
          'Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );

    await NotificationRepository.saveFromFCM(message);
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) async {
    // 點擊通知進來（可做導頁）
    await NotificationRepository.saveFromFCM(message);
  });
}

  static Future<String?> getFcmToken() async {
    return await FirebaseMessaging.instance.getToken();
  }
}