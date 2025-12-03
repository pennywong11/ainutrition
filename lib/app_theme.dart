// lib/app_theme.dart

import 'package:flutter/material.dart';

class AppTheme {
  // 主題顏色自行放這裡或另外抽
  static const Color primaryDeep = Color(0xFFA5C5C2);
  static const Color primaryLight = Color(0xFFF2FDF9);

  static ThemeData theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryDeep,
    ).copyWith(
      primary: primaryDeep,
      surface: Colors.white,
      background: primaryLight,
    ),
  scaffoldBackgroundColor: primaryLight,

    appBarTheme: const AppBarTheme(
      backgroundColor: primaryDeep,
      foregroundColor: Colors.white,
      elevation: 0,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryDeep,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),

    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
