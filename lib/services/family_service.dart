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

    // 將邀請碼存入 'invites' 集合
    await _db.collection('invites').doc(code).set({
      'owner_uid': user.uid,
      'owner_email': user.email ?? "匿名使用者", // 處理匿名登入沒有 email 的情況
      'created_at': FieldValue.serverTimestamp(),
    });

    return code; // 回傳給 UI 顯示
  }

  // --------------------------------------------------------
  // 2. 輸入邀請碼並綁定 (修正版：使用 batch.set 解決新用戶問題)
  // --------------------------------------------------------
  Future<Map<String, dynamic>> joinFamily(String inputCode) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("尚未登入");

    // A. 查詢這個邀請碼是否存在
    var inviteDoc = await _db.collection('invites').doc(inputCode).get();

    if (!inviteDoc.exists) {
      throw Exception("無效的邀請碼");
    }

    String targetUid = inviteDoc.data()!['owner_uid'];
    String targetEmail = inviteDoc.data()!['owner_email'];

    // 如果自己加自己，擋掉
    if (targetUid == user.uid) {
      throw Exception("不能加入自己為家庭成員");
    }

    try {
      // 使用 Batch (批次寫入) 取代 Transaction，對於建立新文件較穩定
      WriteBatch batch = _db.batch();

      // B. 更新對方的資料 (阿嬤)：把我的 UID 加入她的 allowed_viewers
      DocumentReference targetUserRef = _db.collection('users').doc(targetUid);
      // 🟢 關鍵修正：使用 set + merge: true，防止對方文件不存在時報錯
      batch.set(targetUserRef, {
        'allowed_viewers': FieldValue.arrayUnion([user.uid]),
      }, SetOptions(merge: true));

      // C. 更新我的資料 (孫子)：把對方加入我的 watching_list
      DocumentReference myUserRef = _db.collection('users').doc(user.uid);
      // 🟢 關鍵修正：使用 set + merge: true，自動建立新使用者的文件
      batch.set(myUserRef, {
        'watching_list': FieldValue.arrayUnion([
          {
            'uid': targetUid,
            'name': targetEmail.contains('@')
                ? targetEmail.split('@')[0]
                : targetEmail, // 簡單處理名字
            'role': '家人',
            'added_at': DateTime.now().toIso8601String(),
          },
        ]),
      }, SetOptions(merge: true));

      // D. 刪除邀請碼 (確保只能用一次)
      DocumentReference inviteRef = _db.collection('invites').doc(inputCode);
      batch.delete(inviteRef);

      // 提交變更
      await batch.commit();

      return {'success': true, 'targetName': targetEmail};
    } catch (e) {
      print("綁定錯誤詳細資訊: $e");
      throw Exception("綁定失敗: $e");
    }
  }

  // --------------------------------------------------------
  // 🟢 3. 新增功能：解除綁定 (移除家人)
  // --------------------------------------------------------
  Future<void> unbindFamily(Map<String, dynamic> targetMember) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("尚未登入");

    String targetUid = targetMember['uid'];

    try {
      WriteBatch batch = _db.batch();

      // A. 從我的 watching_list 移除這個家人
      DocumentReference myUserRef = _db.collection('users').doc(user.uid);

      // 先讀取最新的資料
      var mySnapshot = await myUserRef.get();
      if (mySnapshot.exists) {
        List<dynamic> currentList = mySnapshot.get('watching_list') ?? [];
        // 過濾掉要刪除的 UID
        List<dynamic> newList = currentList
            .where((item) => item['uid'] != targetUid)
            .toList();
        batch.update(myUserRef, {'watching_list': newList});
      }

      // B. 從對方的 allowed_viewers 移除我的 UID，對方就不會再開放權限給我
      DocumentReference targetUserRef = _db.collection('users').doc(targetUid);
      batch.update(targetUserRef, {
        'allowed_viewers': FieldValue.arrayRemove([user.uid]),
      });

      // 提交變更
      await batch.commit();
    } catch (e) {
      print("解除綁定失敗: $e");
      throw Exception("解除綁定失敗，請檢查網路或權限");
    }
  }

  // --------------------------------------------------------
  // 4. 取得我的家人清單 (用於切換視角 UI)
  // --------------------------------------------------------
  Stream<DocumentSnapshot> getMyFamilyList() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    return _db.collection('users').doc(user.uid).snapshots();
  }
}
