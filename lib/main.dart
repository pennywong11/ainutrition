//import 'package:flutter/material.dart';
//import 'package:firebase_core/firebase_core.dart';
//import 'package:firebase_auth/firebase_auth.dart';
//import 'firebase_options.dart'; // 假設這是您的專案名稱
//import 'auth.dart';
//import 'analysisfood.dart'; // 引入您的分析頁面

//Future<void> main() async {
//WidgetsFlutterBinding.ensureInitialized();
// 初始化 Firebase
//await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
//runApp(const MyApp());
//}

//class MyApp extends StatelessWidget {
//const MyApp({super.key});

//@override
//Widget build(BuildContext context) {
//return MaterialApp(
//title: 'Nutrition Analyzer',
//theme: ThemeData(primarySwatch: Colors.blue),

// 這裡定義所有頁面的命名路由 (Named Routes)
//routes: {
//'/auth': (context) => const AuthPage(), // 認證頁面 (登入/註冊)
//'/analysis': (context) => const NutritionAnalyzerApp(), // 您的上傳分析頁面
//},

// 設定應用程式的初始頁面 (Initial Route)
// 使用 StreamBuilder 判斷用戶是否登入，決定初始要顯示哪個畫面
//home: StreamBuilder<User?>(
//stream: FirebaseAuth.instance.authStateChanges(),
//builder: (context, snapshot) {
//if (snapshot.connectionState == ConnectionState.waiting) {
//return const Center(child: CircularProgressIndicator());
//}

// 如果用戶已登入，直接導向分析頁
//if (snapshot.hasData) {
//return const NutritionAnalyzerApp();
//}
// 如果用戶未登入，導向認證頁
//else {
//return const AuthPage();
//}
//},
//),
//);
//}
//}

// lib/main.dart
import 'routes.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_theme.dart';

// 全局變數，用於儲存當前登入的使用者資訊
User? currentUser;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  //await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  //final userCredential = await FirebaseAuth.instance.signInAnonymously();
  //print('匿名使用者登入成功，UID: ${userCredential.user?.uid}');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Auth Demo',
      theme: AppTheme.theme,
      initialRoute: '/',
      routes: appRoutes,
    );
  }
}
