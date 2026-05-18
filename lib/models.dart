// lib/model.dart
import 'package:cloud_firestore/cloud_firestore.dart'; // 引入Firestore資料庫功能

// 報表數據結構
class ReportData {
  final String period;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final int totalMeals;
  final double totalWeight;
  final Map<String, double> dailyAverages;
  final List<MapEntry<DateTime, double>> topCalorieDays;
  final String aiFeedback;

  ReportData({
    required this.period,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    required this.totalMeals,
    required this.totalWeight,
    required this.dailyAverages,
    required this.topCalorieDays,
    required this.aiFeedback,
  });
}

class FoodItem {
  String id;
  DocumentReference? reference;
  String name;
  String calories;
  String imagePath;
  String grams;
  String protein;
  String carbs;
  String fat;
  List<Ingredient> ingredients;
  String remark;
  String aiSuggestion;
  String mealType;
  DateTime? createdAt; // 新增：建立時間

  FoodItem({
    this.reference,
    required this.id,
    required this.name,
    required this.calories,
    required this.imagePath,
    this.grams = '0',
    this.protein = '0',
    this.carbs = '0',
    this.fat = '0',
    required this.ingredients,
    this.remark = '',
    this.aiSuggestion = '',
    this.mealType = '',
    this.createdAt,
  });
}

// 每個"食材"的資料結構
class Ingredient {
  final String? id;
  final String name;
  final double grams;
  final double calories;
  final double carbs;
  final double protein;
  final double fat;

  bool isDeleted = false; // 軟刪除標記

  Ingredient({
    this.id,
    required this.name,
    required this.grams,
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  Ingredient copy() {
    var newIngredient = Ingredient(
      id: this.id,
      name: this.name,
      grams: this.grams,
      calories: this.calories,
      carbs: this.carbs,
      protein: this.protein,
      fat: this.fat,
    );
    // 複製目前的刪除狀態 (通常初始是 false)
    newIngredient.isDeleted = this.isDeleted;
    return newIngredient;
  }
}

