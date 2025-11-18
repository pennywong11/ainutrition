// lib/firebase_service.dart
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // 確保使用匿名登入
  Future<User?> _ensureAnonymousUser() async {
    User? user = _auth.currentUser;
    if (user == null) {
      final credential = await _auth.signInAnonymously();
      user = credential.user;
    }
    return user;
  }

  // 儲存餐點紀錄
  Future<void> saveMealRecord({
    required Map<String, dynamic> analysis,
    required List<Map<String, dynamic>> ingredients,
    File? imageFile,
  }) async {
    final user = await _ensureAnonymousUser();
    if (user == null) throw Exception('無法登入 Firebase');

    String? imageUrl;
    if (imageFile != null) {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}';
      final ref = _storage.ref().child('meal_images/${user.uid}/$fileName');
      await ref.putFile(imageFile);
      imageUrl = await ref.getDownloadURL();
    }

    final docRef = _firestore.collection('meal_records').doc();
    await docRef.set({
      'user_id': user.uid,
      'analysis': analysis,
      'ingredients': ingredients,
      'image_url': imageUrl,
      'created_at': FieldValue.serverTimestamp(),
    });
  }
}
