// lib/app_mode.dart
import 'package:flutter/material.dart';

/// App 顯示模式
enum AppModeType {
  normal, // 一般模式
  simple, // 簡單模式（大字 / 簡化 UI）
}

class AppMode extends ChangeNotifier {
  AppModeType _mode = AppModeType.normal;

  // 目前模式
  AppModeType get mode => _mode;

  // 是否為簡單模式（方便直接判斷用）
  bool get isSimple => _mode == AppModeType.simple;

  // 切換模式（normal <-> simple）
  void toggle() {
    _mode = _mode == AppModeType.normal
        ? AppModeType.simple
        : AppModeType.normal;
    notifyListeners();
  }

  // 手動設定模式
  void setMode(AppModeType mode) {
    _mode = mode;
    notifyListeners();
  }
}