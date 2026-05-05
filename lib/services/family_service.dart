import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FamilyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --------------------------------------------------------
  // 1. 產生邀請碼 (由被照顧者/長輩操作)
  // --------------------------------------------------------
  Future<String> generateInviteCode() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("尚未登入");

    // 產生 4 位數隨機碼 (1000 ~ 9999)
    String code = (1000 + Random().nextInt(9000)).toString();

    // 設定 10 分鐘後過期
    DateTime expireTime = DateTime.now().add(const Duration(minutes: 10));

    await _db.collection('invites').doc(code).set({
      'owner_uid': user.uid,
      'owner_email': user.email ?? "未知使用者",
      'created_at': FieldValue.serverTimestamp(),
      'expires_at': Timestamp.fromDate(expireTime),
    });

    return code;
  }

  // --------------------------------------------------------
  // 2. 輸入邀請碼並綁定
  // --------------------------------------------------------
  Future<Map<String, dynamic>> joinFamily(String inputCode) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("尚未登入");

    var snapshot = await _db.collection('invites').doc(inputCode).get();

    if (!snapshot.exists) throw Exception("無效的邀請碼");

    final data = snapshot.data()!;
    Timestamp expiresAt = data['expires_at'];

    // 檢查是否過期
    if (DateTime.now().isAfter(expiresAt.toDate())) {
      await _db.collection('invites').doc(inputCode).delete();
      throw Exception("該邀請碼已過期");
    }

    String targetUid = data['owner_uid'];
    String targetEmail = data['owner_email'];

    if (targetUid == user.uid) throw Exception("不能加入自己為家庭成員");

    try {
      await _db.runTransaction((transaction) async {
        // A. 更新長輩的允許查看者清單
        DocumentReference targetUserRef = _db
            .collection('users')
            .doc(targetUid);
        transaction.update(targetUserRef, {
          'allowed_viewers': FieldValue.arrayUnion([user.uid]),
        });

        // B. 更新我的追蹤清單
        DocumentReference myUserRef = _db.collection('users').doc(user.uid);
        transaction.update(myUserRef, {
          'watching_list': FieldValue.arrayUnion([
            {
              'uid': targetUid,
              'name': targetEmail.contains('@')
                  ? targetEmail.split('@')[0]
                  : targetEmail,
              'role': '家人',
              'added_at': DateTime.now().toIso8601String(),
            },
          ]),
        });

        // C. 刪除邀請碼 (確保一次性使用)
        DocumentReference inviteRef = _db.collection('invites').doc(inputCode);
        transaction.delete(inviteRef);
      });

      return {'success': true, 'targetName': targetEmail};
    } catch (e) {
      throw Exception("綁定失敗: $e");
    }
  }

  // --------------------------------------------------------
  // 3. 取得家人清單流
  // --------------------------------------------------------
  Stream<DocumentSnapshot> getMyFamilyList() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db.collection('users').doc(user.uid).snapshots();
  }

  // --------------------------------------------------------
  // 4. 解除綁定邏輯
  // --------------------------------------------------------
  Future<void> unbindFamily(Map<String, dynamic> targetMember) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("尚未登入");

    String targetUid = targetMember['uid'];

    try {
      WriteBatch batch = _db.batch();

      // A. 從我的 watching_list 移除
      DocumentReference myUserRef = _db.collection('users').doc(user.uid);
      var mySnapshot = await myUserRef.get();
      if (mySnapshot.exists) {
        List<dynamic> currentList = mySnapshot.get('watching_list') ?? [];
        List<dynamic> newList = currentList
            .where((item) => item['uid'] != targetUid)
            .toList();
        batch.update(myUserRef, {'watching_list': newList});
      }

      // B. 從對方的 allowed_viewers 移除
      DocumentReference targetUserRef = _db.collection('users').doc(targetUid);
      batch.update(targetUserRef, {
        'allowed_viewers': FieldValue.arrayRemove([user.uid]),
      });

      await batch.commit();
    } catch (e) {
      throw Exception("解除綁定失敗: $e");
    }
  }
}
