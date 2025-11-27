// lib/routes.dart
import 'package:flutter/material.dart';
import 'history_page.dart';
import 'analysisfood.dart';
import 'auth.dart';

final Map<String, WidgetBuilder> appRoutes = {
  '/': (context) => const NutritionHomePage(), // 主畫面
  '/auth': (context) => const AuthPage(), // 登入/註冊頁
  //'/settings': (context) => const SettingsPage(), // 設定頁
  //'/admin': (context) => const AdminPage(),       // 管理頁
  '/analysis': (context) => const NutritionAnalyzer(), // 分析頁
};
