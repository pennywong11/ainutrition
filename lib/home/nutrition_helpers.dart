// nutrition_helpers.dart
// 餐別圖示/顏色設定、型別轉換、餐別判斷、營養計算等工具函式

import 'package:flutter/material.dart';

// ── 常數 ────────────────────────────────────────────────────────────────────

/// 各餐別對應的 icon / 顏色設定
const Map<String, _MealMeta> kMealMeta = {
  '早餐': _MealMeta(Icons.wb_twilight,    Colors.amber),          // amber
  '午餐': _MealMeta(Icons.wb_sunny,       Colors.orangeAccent),          // orange[400]
  '晚餐': _MealMeta(Icons.nights_stay,    Colors.indigoAccent),          // indigoAccent
  '點心': _MealMeta(Icons.cookie,         Colors.pinkAccent),          // pinkAccent
};

class _MealMeta {
  final IconData icon;
  final Color color;
  const _MealMeta(this.icon, this.color);
}

// ── 型別轉換 ─────────────────────────────────────────────────────────────────

/// 將 Firestore 回傳的任意型別安全轉成 double
double parseToDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

// ── 餐別判斷 ─────────────────────────────────────────────────────────────────

/// 根據時間自動判斷餐別
///   05–10: 早餐, 11–13: 午餐, 14–16: 點心, 17–20: 晚餐, 其他: 點心
String mealTypeByTime(DateTime time) {
  final h = time.hour;
  if (h >= 5  && h < 11) return '早餐';
  if (h >= 11 && h < 14) return '午餐';
  if (h >= 14 && h < 17) return '點心';
  if (h >= 17 && h < 21) return '晚餐';
  return '點心';
}

// ── 營養計算 ─────────────────────────────────────────────────────────────────

/// BMR + TDEE → 個人化每日目標
class NutritionTargets {
  final double calories;
  final double protein;  // g
  final double carbs;    // g
  final double fat;      // g

  const NutritionTargets({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  /// 預設值（尚未設定個人資料時使用）
  factory NutritionTargets.defaults() => const NutritionTargets(
        calories: 2000,
        protein:  60,
        carbs:    300,
        fat:      60,
      );
}

/// 根據性別/年齡/身高/體重計算個人化目標
///
/// 熱量比例：蛋白質 12 %、碳水 60 %、脂肪 27 %
/// 活動係數：1.2（久坐）
NutritionTargets calculateTargets({
  required String gender,
  required int    age,
  required double height, // cm
  required double weight, // kg
}) {
  final bool isMale = gender == '男性' || gender == '男' ||
      gender.toLowerCase() == 'male';

  final double bmr = isMale
      ? (10 * weight) + (6.25 * height) - (5 * age) + 5
      : (10 * weight) + (6.25 * height) - (5 * age) - 161;

  final double tdee = bmr * 1.2;

  return NutritionTargets(
    calories: tdee,
    protein:  (tdee * 0.12) / 4,
    carbs:    (tdee * 0.60) / 4,
    fat:      (tdee * 0.27) / 9,
  );
}

// ── 每日攝取合計 ──────────────────────────────────────────────────────────────

/// 暫存「今日總營養素」，由 FoodItem 列表加總而來
class DailyTotals {
  double calories = 0;
  double protein  = 0;
  double carbs    = 0;
  double fat      = 0;

  /// 各大量營養素換算成熱量後的總和
  double get macroCalories => (protein * 4) + (carbs * 4) + (fat * 9);

  double get proteinCalorieFraction =>
      macroCalories == 0 ? 0 : (protein * 4) / macroCalories;

  double get carbCalorieFraction =>
      macroCalories == 0 ? 0 : (carbs * 4) / macroCalories;

  double get fatCalorieFraction =>
      macroCalories == 0 ? 0 : (fat * 9) / macroCalories;
}