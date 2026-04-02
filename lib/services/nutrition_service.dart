import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';

// 1. 定義資料模型
class FoodItem {
  final String id;
  final String name;
  final String commonName; // 俗名
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double sodium;

  FoodItem({
    required this.id,
    required this.name,
    required this.commonName,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.sodium,
  });

  // 這是負責把 CSV 的「一行」轉成「物件」的工廠
  // 請確認這裡的順序跟你的 Excel/CSV 欄位順序是一樣的！
  factory FoodItem.fromCsv(List<dynamic> row) {
    return FoodItem(
      id: row[0].toString(), // 第1欄: 整合編號
      name: row[1].toString(), // 第2欄: 樣品名稱
      commonName: row[2].toString(), // 第3欄: 俗名
      // 數值部分用 tryParse 避免轉型失敗當機
      calories: double.tryParse(row[3].toString()) ?? 0.0, // 第4欄: 熱量
      protein: double.tryParse(row[4].toString()) ?? 0.0, // 第5欄: 粗蛋白
      fat: double.tryParse(row[5].toString()) ?? 0.0, // 第6欄: 粗脂肪
      carbs: double.tryParse(row[6].toString()) ?? 0.0, // 第7欄: 碳水
      sodium: double.tryParse(row[7].toString()) ?? 0.0, // 第8欄: 鈉
    );
  }
}

// 2. 建立服務類別
class NutritionService {
  List<FoodItem> _foodDatabase = [];

  // 讀取 CSV 檔案
  Future<void> loadCsvData() async {
    try {
      // 讀取檔案內容
      final rawData = await rootBundle.loadString('assets/data/nutrition.csv');

      // 轉換 CSV
      List<List<dynamic>> csvTable = const CsvToListConverter().convert(
        rawData,
      );

      // 如果有標題列(Header)，記得要移除第一行
      if (csvTable.isNotEmpty) {
        // 檢查第一行是不是標題，如果是文字標題就移除
        // 這裡預設直接移除第一行
        csvTable.removeAt(0);
      }

      // 轉換成 List<FoodItem>
      _foodDatabase = csvTable.map((row) => FoodItem.fromCsv(row)).toList();

      print("✅ 資料庫載入成功！共 ${_foodDatabase.length} 筆資料");
    } catch (e) {
      print("❌ 資料庫讀取失敗: $e");
    }
  }

  // 搜尋功能 (回傳 List，因為可能搜到好幾筆)
  List<FoodItem> searchFood(String query) {
    if (_foodDatabase.isEmpty) return [];

    // 簡單模糊搜尋：名稱或俗名包含關鍵字
    return _foodDatabase.where((food) {
      return food.name.contains(query) || food.commonName.contains(query);
    }).toList();
  }
}
