import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FamilyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --------------------------------------------------------
  // 1. 產生邀請碼
  // --------------------------------------------------------
  Future<String> generateInviteCode() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("尚未登入");

    String code = (1000 + Random().nextInt(9000)).toString();
    DateTime expireTime = DateTime.now().add(const Duration(minutes: 10));

    await _db.collection('invites').doc(code).set({
      'owner_uid': user.uid,
      'owner_email': user.email ?? "未知使用者",
      'created_at': FieldValue.serverTimestamp(),
      'expires_at': Timestamp.fromDate(expireTime),
    });

    return code;
  }

  // 取消邀請碼 (主動刪除 Firestore 中的邀請碼)
  Future<void> cancelInviteCode(String code) async {
    await _db.collection('invites').doc(code).delete();
  }

  // --------------------------------------------------------
  // 2. 輸入邀請碼並綁定
  // --------------------------------------------------------
  Future<Map<String, dynamic>> joinFamily(String inputCode) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("尚未登入");

    DocumentSnapshot snapshot;
    try {
      snapshot = await _db.collection('invites').doc(inputCode).get();
    } catch (e) {
      // 🟢 修改：攔截 Firebase 的權限錯誤 (Permission Denied)
      // 當輸入不存在的邀請碼，Firestore 規則阻擋時會觸發這個錯誤
      if (e.toString().contains('permission-denied')) {
        throw Exception("該邀請碼無效或不存在");
      }
      throw Exception("驗證失敗，請確認邀請碼是否正確");
    }

    // 🟢 檢查是否存在
    if (!snapshot.exists) throw Exception("該邀請碼無效或不存在");

    final data = snapshot.data() as Map<String, dynamic>;
    Timestamp expiresAt = data['expires_at'];

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
          'viewers_info': FieldValue.arrayUnion([
            {
              'uid': user.uid,
              'name': user.email?.split('@')[0] ?? '未知',
              'role': '家人',
            },
          ]),
        });

        // B. 更新我的追蹤清單
        DocumentReference myUserRef = _db.collection('users').doc(user.uid);
        transaction.update(myUserRef, {
          'watching_list': FieldValue.arrayUnion([
            {
              'uid': targetUid,
              'name': targetEmail.split('@')[0],
              'role': '家人',
              'added_at': DateTime.now().toIso8601String(),
            },
          ]),
        });

        // C. 刪除邀請碼
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
  // 4. 解除綁定邏輯 (我不想看別人了)
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
      var targetSnapshot = await targetUserRef.get();
      if (targetSnapshot.exists) {
        var data = targetSnapshot.data() as Map<String, dynamic>?;
        List<dynamic> currentViewers =
            data != null && data.containsKey('viewers_info')
            ? data['viewers_info']
            : [];
        List<dynamic> newViewers = currentViewers
            .where((item) => item['uid'] != user.uid)
            .toList();

        batch.update(targetUserRef, {
          'allowed_viewers': FieldValue.arrayRemove([user.uid]),
          'viewers_info': newViewers,
        });
      }

      await batch.commit();
    } catch (e) {
      throw Exception("解除綁定失敗: $e");
    }
  }

  // --------------------------------------------------------
  // 5. 撤銷權限邏輯 (踢掉正在看我的人)
  // --------------------------------------------------------
  Future<void> removeViewer(Map<String, dynamic> viewer) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("尚未登入");

    String viewerUid = viewer['uid'];

    try {
      WriteBatch batch = _db.batch();

      // A. 從我的 allowed_viewers 與 viewers_info 移除對方
      DocumentReference myRef = _db.collection('users').doc(user.uid);
      var mySnapshot = await myRef.get();
      if (mySnapshot.exists) {
        List<dynamic> currentViewers = mySnapshot.get('viewers_info') ?? [];
        List<dynamic> newViewers = currentViewers
            .where((item) => item['uid'] != viewerUid)
            .toList();
        batch.update(myRef, {
          'allowed_viewers': FieldValue.arrayRemove([viewerUid]),
          'viewers_info': newViewers,
        });
      }

      // B. 從對方的 watching_list 移除我
      DocumentReference viewerRef = _db.collection('users').doc(viewerUid);
      var viewerSnapshot = await viewerRef.get();
      if (viewerSnapshot.exists) {
        List<dynamic> currentList = viewerSnapshot.get('watching_list') ?? [];
        List<dynamic> newList = currentList
            .where((item) => item['uid'] != user.uid)
            .toList();
        batch.update(viewerRef, {'watching_list': newList});
      }

      await batch.commit();
    } catch (e) {
      throw Exception("撤銷權限失敗: $e");
    }
  }
}
