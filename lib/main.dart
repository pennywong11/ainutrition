import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_theme.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notifications/notification_handler.dart';
import 'widget_handler.dart';
import 'routes.dart';
import 'package:provider/provider.dart';
import 'home/app_mode.dart';

// 全局變數，用於儲存當前登入的使用者資訊
User? currentUser;

// final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 負責初始化 Firebase Auth，並確保使用固定的匿名 UID
Future<void> _initializeAuth() async {
  // 1. 檢查是否有現有的使用者登入狀態
  currentUser = FirebaseAuth.instance.currentUser;

  // 2. 如果沒有，則執行匿名登入，並取得新的 UID
  if (currentUser == null) {
    try {
      final userCredential = await FirebaseAuth.instance.signInAnonymously();
      currentUser = userCredential.user;
      print('=== 偵測到未登入，執行匿名登入，UID: ${currentUser!.uid} ===');
    } on FirebaseAuthException catch (e) {
      print('匿名登入失敗: ${e.code}');
      // 這裡可以處理錯誤，例如給予使用者提示
    }
  } else {
    // 3. 如果有現有使用者，直接使用，確保每次測試 UID 都是固定的
    print('=== 找到現有使用者UID: ${currentUser!.uid} ===');
  }
}

// 背景訊息處理
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("背景收到訊息: ${message.data}");
}

Future<void> main() async {
  // 1. 確保 Widgets 繫結初始化，允許在 runApp 之前進行非同步操作
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 載入環境變數 (.env)
  try {
    await dotenv.load(fileName: ".env");
    print("環境變數載入成功！");
  } catch (e) {
    print("環境變數載入失敗: $e");
  }

  // 3. 初始化 Firebase 核心服務
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  //FirebaseFirestore.instance.settings = const Settings(
  //  localCacheSettings: PersistentCacheSettings(), // 預設即開啟離線持久化與無上限快取
  //);
  // 4. 初始化身份驗證 (確保在 App 運行前登入完成)
  await _initializeAuth();
  // 5. 初始化通知處理器（包含 FCM 和本地通知）
  await NotificationHandler.init();
  // 註冊背景訊息 handler
  FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);
  // 6. 桌面小工具初始化
  WidgetHandler.init();
  //await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  //final userCredential = await FirebaseAuth.instance.signInAnonymously();
  //print('匿名使用者登入成功，UID: ${userCredential.user?.uid}');
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppMode())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'aiNutrition',
      theme: AppTheme.theme,
      initialRoute: '/', // 預設進入模式選擇頁
      routes: appRoutes,
      navigatorKey: WidgetHandler.navigatorKey, // 設定全局導航鍵
      debugShowCheckedModeBanner: false, // 隱藏右上角的DEBUG標籤
    );
  }
}
