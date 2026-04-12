// lib/widget_handler.dart

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class WidgetHandler {
  static const platform = MethodChannel('com.example.nutrition/widget');
  
  // 使用 GlobalKey 來控制導航，不需要 context
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // 初始化監聽器
  static void init() {
    // 監聽來自 Android 原生端的呼叫 (當 App 在背景時點擊小工具)
    platform.setMethodCallHandler((call) async {
      if (call.method == "onUpdateRoute") {
        _handleNavigation(call.arguments);
      }
    });
  }

  // 檢查啟動時是否有帶入路由 (當 App 徹底關閉時點擊小工具)
  static Future<void> checkInitialRoute() async {
    try {
      final String? initialRoute = await platform.invokeMethod('getInitialRoute');
      if (initialRoute != null) {
        // 延遲一下確保 Navigator 已經準備好
        Future.delayed(Duration(milliseconds: 500), () {
          _handleNavigation(initialRoute);
        });
      }
    } catch (e) {
      debugPrint("取得初始路由失敗: $e");
    }
  }

  ///統一處理跳轉邏輯
  static void _handleNavigation(String? route) {
    if (route == null || route.isEmpty) return;

    // 根據你 OpenCamera.kt 傳過來的字串進行判斷
    // 假設 OpenCamera.kt 傳的是 "camera_page"
    // 而你的 routes.dart 定義的是 "/camera"
    String targetRoute = "/$route"; 

    debugPrint("小工具觸發跳轉至: $targetRoute");
    
    // 使用 navigatorKey 進行跳轉
    // pushNamedAndRemoveUntil 可以確保跳轉時清理堆疊，或者單純用 pushNamed
    navigatorKey.currentState?.pushNamed(targetRoute);
  }
}