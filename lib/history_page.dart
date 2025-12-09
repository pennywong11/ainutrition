// 匯入 Flutter 的 Material UI 函式庫
import 'package:flutter/material.dart';
import 'dart:async'; // 管理StreamSubscription(監聽器的開關)
import 'package:fl_chart/fl_chart.dart'; //圓餅圖套件
import 'package:firebase_core/firebase_core.dart'; //Firebase核心
import 'package:cloud_firestore/cloud_firestore.dart'; // 引入Firestore資料庫功能
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert'; // 添加這行，為了 base64Decode
import 'dart:typed_data'; // 添加這行，為了 Uint8List

// ----------------------------------------------
// 資料模型區(Models)：定義資料的樣子
// ----------------------------------------------

// 每個"食物"的資料結構
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
}

// 用來暫存"今日總營養素"的小工具類別
class _DailyTotals {
  double calories = 0;
  double protein = 0;
  double carbs = 0;
  double fat = 0;
}

// ----------------------------------------------
// 首頁(儀表板+列表)
// ----------------------------------------------

class NutritionHomePage extends StatefulWidget {
  const NutritionHomePage({super.key});

  @override
  State<NutritionHomePage> createState() => _NutritionHomePageState();
}

class _NutritionHomePageState extends State<NutritionHomePage> {
  // 狀態變數
  late DateTime _selectedDate; 
  StreamSubscription? _foodSubscription;

  bool _isGoalSet = false;

  double _targetCalories = 2000;
  double _targetProtein = 60;
  double _targetCarbs = 300;
  double _targetFat = 60;

  List<FoodItem> _foodList = [];
  bool _isLoading = true; 

  // 檢查使用者資料完整性
  Future<void> _checkUserDataStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          final data = doc.data();
          bool isComplete = data != null &&
              data['gender'] != null &&
              data['age'] != null &&
              data['height'] != null &&
              data['weight'] != null;

          if (mounted) {
            setState(() {
              _isGoalSet = isComplete;
            });
          }
          if (isComplete) {
            try {
              String gender = data!['gender'].toString();
              int age = int.tryParse(data['age'].toString()) ?? 25;
              double height = double.tryParse(data['height'].toString()) ?? 160;
              double weight = double.tryParse(data['weight'].toString()) ?? 50;

              _calculatePersonalizedTargets(gender, age, height, weight);
            } catch (e) {
              print("計算營養目標時發生錯誤: $e");
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _isGoalSet = false;
            });
          }
        }
      } catch (e) {
        print("檢查使用者資料失敗: $e");
      }
    }
  }

  // --- 根據個人資料計算 BMR 與 TDEE ---
  void _calculatePersonalizedTargets(
      String gender, int age, double height, double weight) {
    
    double bmr = 0;
    // 1. 計算 BMR (基礎代謝率)
    if (gender == '男性' || gender == '男' || gender.toLowerCase() == 'male') {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }

    // 2. 計算 TDEE (個人每日總熱量需求)
    // 這是 "個人化" 的部分，因為不同年齡體重算出來的 bmr 不同
    double tdee = bmr * 1.2; 

    // 3. 設定營養素比例
    // 蛋白質 12%, 脂肪 27%, 碳水 60%
    double proteinRatio = 0.12; 
    double fatRatio = 0.27; 
    double carbsRatio = 0.60; 

    if (mounted) {
      setState(() {
        _targetCalories = tdee;
        // 4. 計算各營養素的目標克數
        // 蛋白質目標 (g) = (總熱量 * 12%) / 4
        _targetProtein = (_targetCalories * proteinRatio) / 4;
        // 碳水目標 (g) = (總熱量 * 60%) / 4
        _targetCarbs = (_targetCalories * carbsRatio) / 4;
        // 脂肪目標 (g) = (總熱量 * 27%) / 9
        _targetFat = (_targetCalories * fatRatio) / 9;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();

    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user == null) {
        print("系統：偵測到登出，正在清除畫面資料...");
        _foodSubscription?.cancel();
        if (mounted) {
          setState(() {
            _foodList.clear(); 
            _isGoalSet = false; 
            _targetCalories = 2050; 
            _isLoading = false; 
          });
        }
      } else {
        print("系統：偵測到使用者 ID: ${user.uid}，開始讀取資料...");
        _listenToFirebaseData();
        _checkUserDataStatus();
      }
    });

    _checkLoginAndListen();
  }

  Future<void> _checkLoginAndListen() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        print("系統：初次檢查無使用者，正在進行匿名登入...");
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        print("系統：登入失敗: $e");
      }
    }
  }

  void _listenToFirebaseData() {
    _foodSubscription?.cancel();
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserUid == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final DateTime startOfDay = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0);
    final DateTime endOfDay = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59, 999);

    _foodSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserUid)
        .collection('analysis_records')
        .where('created_at', isGreaterThanOrEqualTo: startOfDay)
        .where('created_at', isLessThanOrEqualTo: endOfDay)
        .orderBy('created_at', descending: true)
        .snapshots()
        .listen(
      (snapshot) async {
        List<FoodItem> newFoodList = [];
        try {
          for (var doc in snapshot.docs) {
            var data = doc.data();
            String foodName = data['食物名'] ?? '未命名';
            if (foodName == 'string' || foodName == '未命名') continue;

            String docId = doc.id;
            String suggestion = data['AI分析建議'] ?? '';
            String imgUrl = data['圖片_base64'] ?? data['圖片網址'] ?? '';
            String mealType = (data['meal_type'] ?? '').toString();  

            if (mealType.isEmpty) {
               // 嘗試讀取 created_at，如果是 null 則用現在時間
               Timestamp? createdAt = data['created_at'];
               DateTime time = createdAt != null ? createdAt.toDate() : DateTime.now();
               // 呼叫剛剛寫好的函式來自動填入
               mealType = _getMealTypeByTime(time);
            }

            List<Ingredient> ingredientsList = [];
            double totalGrams = 0;
            double totalCalories = 0;
            double totalProtein = 0;
            double totalCarbs = 0;
            double totalFat = 0;

            try {
              var ingredientSnapshot =
                  await doc.reference.collection('ingredients').get();

              for (var ingDoc in ingredientSnapshot.docs) {
                var ingData = ingDoc.data();
                double g = _parseToDouble(ingData['重量(g)']);
                double cal = _parseToDouble(ingData['熱量(kcal)']);
                double p = _parseToDouble(ingData['蛋白質(g)']);
                double c = _parseToDouble(ingData['碳水化合物(g)']);
                double f = _parseToDouble(ingData['脂肪(g)']);
                String name = ingData['食材名'] ?? '未知食材';

                totalGrams += g;
                totalCalories += cal;
                totalProtein += p;
                totalCarbs += c;
                totalFat += f;

                ingredientsList.add(
                  Ingredient(
                    id: ingDoc.id,
                    name: name,
                    grams: g,
                    calories: cal,
                    carbs: c,
                    protein: p,
                    fat: f,
                  ),
                );
              }
            } catch (e) {
              print("讀取食材錯誤: $e");
            }

            newFoodList.add(
              FoodItem(
                reference: doc.reference,
                id: docId,
                name: foodName,
                calories: '${totalCalories.toStringAsFixed(0)} 大卡',
                imagePath: imgUrl,
                grams: totalGrams.toStringAsFixed(1),
                protein: totalProtein.toStringAsFixed(1),
                carbs: totalCarbs.toStringAsFixed(1),
                fat: totalFat.toStringAsFixed(1),
                ingredients: ingredientsList,
                remark: data['備註'] ?? '',
                aiSuggestion: suggestion,
                mealType: mealType,
              ),
            );
          }
        } catch (e) {
          print("處理資料錯誤: $e");
        }

        if (mounted) {
          setState(() {
            _foodList = newFoodList;
            _isLoading = false;
          });
        }
      },
      onError: (error) {
        print("Firebase 查詢錯誤: $error");
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  double _parseToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // 根據時間自動判斷是哪一餐
  String _getMealTypeByTime(DateTime time) {
    int hour = time.hour;
    if (hour >= 5 && hour < 11) {
      return '早餐'; // 05:00 ~ 10:59
    } else if (hour >= 11 && hour < 14) {
      return '午餐'; // 11:00 ~ 13:59
    } else if (hour >= 14 && hour < 17) {
      return '點心'; // 14:00 ~ 16:59
    } else if (hour >= 17 && hour < 21) {
      return '晚餐'; // 17:00 ~ 20:59
    } else {
      return '點心'; // 其他時間（宵夜）歸類為點心
    }
  }

  _DailyTotals _calculateCurrentTotals() {
    final totals = _DailyTotals();
    for (final item in _foodList) {
      final calString = item.calories.replaceAll(' 大卡', '');
      totals.calories += double.tryParse(calString) ?? 0;
      totals.protein += double.tryParse(item.protein) ?? 0;
      totals.carbs += double.tryParse(item.carbs) ?? 0;
      totals.fat += double.tryParse(item.fat) ?? 0;
    }
    return totals;
  }

  Future<void> _navigateToSettings() async {
    // 等待設定頁面關閉
    await Navigator.pushNamed(context, '/settings');

    // 無論回傳什麼，只要從設定頁回來，就檢查一次狀態
    if (mounted) {
      print("從設定頁返回，正在重新檢查資料完整性...");
      await _checkUserDataStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color.fromARGB(255, 157, 198, 194),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 25.0), // 增加右邊距，讓它看起來往左移
            child: IconButton(
              onPressed: () async {
                await _navigateToSettings();
              },
              icon: const Icon(Icons.settings),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDecoratedContainer(_buildLeftColumn(context, true)),
                      const SizedBox(height: 16),
                      _buildRightColumn(context),
                    ],
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildDecoratedContainer(
                        _buildLeftColumn(context, false)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildRightColumn(context)),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: Container(
        margin: const EdgeInsets.only(
          right: 20, 
          bottom: 25, 
        ),
        child: FloatingActionButton.small(
          elevation: 4,
          backgroundColor: const Color.fromARGB(255, 157, 198, 194),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add, size: 20),
          onPressed: () async {
            final result = await Navigator.pushNamed(context, '/analysis');

            // 如果回傳 true，代表有新增資料
            if (result == true) {
              if (mounted) {
                setState(() {
                  _selectedDate = DateTime.now();
                  _isLoading = true;
                });
                _listenToFirebaseData();
              }
            }
          },
        ),
      ),
    );
  }

  // 統一的容器裝飾風格
  Widget _buildDecoratedContainer(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  // 左邊UI
  Widget _buildLeftColumn(BuildContext context, bool isMobile) {
    final _DailyTotals currentTotals = _calculateCurrentTotals();
    final double calPercent =
        (currentTotals.calories / _targetCalories).clamp(0, 1);
    final double proteinPercent =
        (currentTotals.protein / _targetProtein).clamp(0, 1);
    final double carbPercent = (currentTotals.carbs / _targetCarbs).clamp(0, 1);
    final double fatPercent = (currentTotals.fat / _targetFat).clamp(0, 1);

    final double proteinCalories = currentTotals.protein * 4;
    final double carbCalories = currentTotals.carbs * 4;
    final double fatCalories = currentTotals.fat * 9;
    final double totalMacroCalories =
        proteinCalories + carbCalories + fatCalories;
    
    final double proteinRingPercent = totalMacroCalories == 0
        ? 0
        : proteinCalories / totalMacroCalories;
    final double carbRingPercent =
        totalMacroCalories == 0 ? 0 : carbCalories / totalMacroCalories;
    final double fatRingPercent =
        totalMacroCalories == 0 ? 0 : fatCalories / totalMacroCalories;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "${_selectedDate.year}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.day.toString().padLeft(2, '0')}",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.calendar_month_outlined,
                    color: Colors.grey[700],
                  ),
                  onPressed: () async {
                    final DateTime now = DateTime.now();
                    final DateTime fiveYearsAgo = DateTime(
                      now.year - 5, now.month, now.day,
                    );

                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate:
                          _selectedDate.isAfter(now) ? now : _selectedDate,
                      firstDate: fiveYearsAgo,
                      lastDate: now,
                    );

                    if (picked != null && picked != _selectedDate) {
                      setState(() {
                        _selectedDate = picked;
                        _isLoading = true; 
                      });
                      _listenToFirebaseData();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),

            Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 0,
                        centerSpaceRadius: 70,
                        sections: [
                          PieChartSectionData(
                            color: Color.fromARGB(255, 117, 181, 233),
                            value: proteinRingPercent * 100,
                            radius: 30,
                            showTitle: false,
                          ),
                          PieChartSectionData(
                            color: Color.fromARGB(255, 132, 202, 206),
                            value: carbRingPercent * 100,
                            radius: 30,
                            showTitle: false,
                          ),
                          PieChartSectionData(
                            color: Color.fromARGB(255, 245, 190, 118),
                            value: fatRingPercent * 100,
                            radius: 30,
                            showTitle: false,
                          ),
                          PieChartSectionData(
                            color: Colors.grey[200],
                            value: totalMacroCalories == 0
                                ? 100
                                : (100 -
                                        (proteinRingPercent +
                                                carbRingPercent +
                                                fatRingPercent) *
                                            100)
                                    .clamp(0, 100),
                            radius: 30,
                            showTitle: false,
                          ),
                        ],
                      ),
                    ),
                    Center(
                      child: totalMacroCalories == 0
                          ? Text(
                              '尚未攝取\n(0%)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 14,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('蛋白質: ${(proteinRingPercent * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
                                Text('碳水: ${(carbRingPercent * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
                                Text('脂肪: ${(fatRingPercent * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '成人每日建議營養攝取量',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!_isGoalSet) ...[
                        const SizedBox(height: 8), 
                        Align(
                          alignment: Alignment.centerLeft, 
                          child: _buildSetGoalButton(),
                        ),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '成人每日建議營養攝取量',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!_isGoalSet) ...[
                        const SizedBox(width: 8),
                        _buildSetGoalButton(),
                      ],
                    ],
                  ),

            const SizedBox(height: 15),

            // 1. 熱量條 (維持不變)
            _buildNutrientBar(
              '熱量 (Calories)', 
              const Color(0xFFE96A60), 
              calPercent,
              targetValue: _targetCalories, // 傳入目標值供顯示
              unit: 'kcal',
            ),
            const SizedBox(height: 15),

            // 2. 蛋白質條 (顯示熱量)
            _buildNutrientBar(
              '蛋白質 (Protein)',
              const Color.fromARGB(255, 117, 181, 233), 
              proteinPercent,
              targetValue: _targetProtein * 4, // 公克 * 4 = 熱量
              unit: 'kcal',
            ),
            const SizedBox(height: 15),

            // 3. 碳水化合物條 (顯示熱量)
            _buildNutrientBar(
              '碳水化合物 (Carbs)',
              const Color.fromARGB(255, 132, 202, 206), 
              carbPercent,
              targetValue: _targetCarbs * 4, // 公克 * 4 = 熱量
              unit: 'kcal',
            ),
            const SizedBox(height: 15),

            // 4. 脂肪條 (顯示熱量)
            _buildNutrientBar(
              '脂肪 (Fat)', 
              const Color.fromARGB(255, 245, 190, 118), 
              fatPercent,
              targetValue: _targetFat * 9, // 公克 * 9 = 熱量
              unit: 'kcal',
            ),
                      ],
                    ),
                  ),
                );
              }

  // 設定目標按鈕(封裝)
  Widget _buildSetGoalButton() {
    return TextButton(
      onPressed: () async {
        // 使用封裝好的函式，確保回來時刷新
        await _navigateToSettings();
      },
      style: ButtonStyle(
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        minimumSize: WidgetStateProperty.all(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap, 
        overlayColor: WidgetStateProperty.all(
          Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith((
          states,
        ) {
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFF7A9C99);
          }
          return const Color(0xFFA5C5C2);
        }),
      ),
      child: const Text(
        '> 設定完整健康目標以查看報告',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNutrientBar(String label, Color color, double percentage, {double? targetValue, String unit = ''}) {
    final String percentageString =
        '${(percentage * 100).toStringAsFixed(0)}%';
    final Color textColor = percentage >= 1.0 ? Colors.red : Colors.black54;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4), 
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: percentage,
                  minHeight: 15,
                  backgroundColor: Colors.grey[300],
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 12), 
            Text(
              percentageString,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 右邊UI
  Widget _buildRightColumn(BuildContext context) {
    return Card(
      elevation: 5,
      shadowColor: Colors.grey.withOpacity(0.5),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              '今日紀錄',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Divider(), 

            _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  ) 
                : _foodList.isEmpty
                    ? const Center(child: Text("目前尚無餐點分析紀錄！"))
                    : ListView.builder(
                        shrinkWrap: true, 
                        physics:
                            const NeverScrollableScrollPhysics(), 
                        padding: const EdgeInsets.only(top: 8.0),
                        itemCount: _foodList.length,
                        itemBuilder: (context, index) {
                          final item = _foodList[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: _buildFoodItem(context, item),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }

  // 輔助函式：根據用餐時段回傳對應的 Icon 和 顏色
  Widget _getMealIcon(String type) {
    IconData iconData;
    Color color;

    switch (type) {
      case '早餐':
        iconData = Icons.wb_twilight; 
        color = Colors.amber;
        break;
      case '午餐':
        iconData = Icons.wb_sunny; 
        color = Colors.orange[400]!;
        break;
      case '晚餐':
        iconData = Icons.nights_stay; 
        color = Colors.indigoAccent;
        break;
      case '點心':
        iconData = Icons.cookie; 
        color = Colors.pinkAccent;
        break;
      default:
        return const SizedBox.shrink(); 
    }

    return Container(
      margin: const EdgeInsets.only(right: 12), 
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, size: 20, color: color),
    );
  }

  // 單一食物項目
  Widget _buildFoodItem(BuildContext context, FoodItem item) {
    // print("檢查圖片資料：[${item.imagePath}]");
    Uint8List? imageBytes;
    Widget imageWidget;

    if (item.imagePath.startsWith('data:image') ||
        (item.imagePath.length > 1000 &&
            !item.imagePath.startsWith('http'))) {
      try {
        final base64String = item.imagePath.replaceFirst(
          'data:image/jpeg;base64,',
          '',
        );
        imageWidget = Image.memory(
          base64Decode(base64String),
          fit: BoxFit.cover,
          width: 60,
          height: 60,
        );
      } catch (e) {
        imageWidget = _buildImagePlaceholder();
      }
    } else if (item.imagePath.startsWith('http')) {
      imageWidget = Image.network(
        item.imagePath,
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        errorBuilder: (context, error, stackTrace) {
          return _buildImagePlaceholder();
        },
      );
    } else {
      imageWidget = _buildImagePlaceholder();
    }

    return InkWell(
      onTap: () async {
        await _showFoodEditDialog(
          context,
          item,
          _selectedDate,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            // 如果 mealType 有值 (且不是空字串)，就顯示 Icon
            if (item.mealType.isNotEmpty) _getMealIcon(item.mealType),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 60,
                height: 60,
                color: Colors.grey[200],
                child: imageWidget,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name, 
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    item.calories, 
                    style:
                        const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),

            SizedBox(
              width: 40, 
              child: IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color.fromARGB(255, 26, 24, 23),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext dialogContext) {
                      return AlertDialog(
                        title: const Text('刪除'),
                        content: Text('您確定要永久刪除「${item.name}」嗎？'),
                        actions: <Widget>[
                          TextButton(
                            child: const Text('取消'),
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                            },
                          ),
                          TextButton(
                            child: const Text('確認'),
                            onPressed: () async {
                              Navigator.of(dialogContext).pop();

                              if (item.reference != null) {
                                try {
                                  await item.reference!.delete();
                                  print(
                                      "已成功從 Firebase 刪除文件: ${item.name}");
                                } catch (e) {
                                  print("刪除失敗: $e");
                                }
                              }
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return const Icon(Icons.restaurant, color: Colors.grey);
  }

  Future<FoodItem?> _showFoodEditDialog(
    BuildContext context,
    FoodItem item,
    DateTime selectedDate,
  ) {
    return showDialog<FoodItem>(
      context: context,
      builder: (BuildContext context) {
        final double screenWidth = MediaQuery.of(context).size.width;
        final double dialogWidth =
            screenWidth > 800 ? 600 : screenWidth * 0.9;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Container(
            width: dialogWidth, // 使用計算後的寬度
            child: FoodEditDialogContent(
              item: item,
              selectedDate: selectedDate,
            ),
          ),
        );
      },
    );
  }
} // 結束 _NutritionHomePageState

// ----------------------------------------------
// 彈出視窗內容(詳情頁面)
// ----------------------------------------------

class FoodEditDialogContent extends StatefulWidget {
  final FoodItem item;
  final DateTime selectedDate;

  const FoodEditDialogContent({
    super.key,
    required this.item,
    required this.selectedDate,
  });

  @override
  State<FoodEditDialogContent> createState() => _FoodEditDialogContentState();
}

class _FoodEditDialogContentState extends State<FoodEditDialogContent> {
  late TextEditingController _nameController;
  late TextEditingController _gramController;
  late TextEditingController _calController;
  late TextEditingController _proteinController;
  late TextEditingController _carbController;
  late TextEditingController _fatController;
  late TextEditingController _remarksController;

  late List<Ingredient> _ingredients;
  bool _isEditingName = false;
  final List<String> _ingredientsToDelete = [];
  final List<String> _mealOptions = ['早餐', '午餐', '晚餐', '點心'];
  String? _selectedMealType; 

  void _calculateTotals() {
    double totalGrams = 0;
    double totalCalories = 0;
    double totalProtein = 0;
    double totalCarbs = 0;
    double totalFat = 0;

    for (final ingredient in _ingredients) {
      if (ingredient.isDeleted) continue;
      totalGrams += ingredient.grams;
      totalCalories += ingredient.calories;
      totalProtein += ingredient.protein;
      totalCarbs += ingredient.carbs;
      totalFat += ingredient.fat;
    }

    _gramController.text = totalGrams.toStringAsFixed(1);
    _calController.text = totalCalories.toStringAsFixed(0);
    _proteinController.text = totalProtein.toStringAsFixed(1);
    _carbController.text = totalCarbs.toStringAsFixed(1);
    _fatController.text = totalFat.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _gramController = TextEditingController();
    _calController = TextEditingController();
    _proteinController = TextEditingController();
    _carbController = TextEditingController();
    _fatController = TextEditingController();
    _remarksController = TextEditingController(text: widget.item.remark);

    _ingredients = List.from(widget.item.ingredients);
    _calculateTotals(); // 呼叫計算函式，填入初始總和
    // 初始化用餐時段：如果有值就設定，沒值(空字串)就設為 null
    if (widget.item.mealType.isNotEmpty &&
        _mealOptions.contains(widget.item.mealType)) {
      _selectedMealType = widget.item.mealType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gramController.dispose();
    _calController.dispose();
    _proteinController.dispose();
    _carbController.dispose();
    _fatController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Widget _buildLabeledTextField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.number,
    bool enabled = true,
    Color? backgroundColor,
    Color? dotColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6), // 圓點跟文字的間距
            ],
            Text(
              label,
              style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 11.5),

            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller, 
            keyboardType: keyboardType,
            enabled: enabled,

            style: const TextStyle(
              color: Colors.black87,
              fontSize: 13, 
              fontWeight: FontWeight.bold,
            ),

            decoration: InputDecoration(
              hintText: '0',
              filled: !enabled || backgroundColor != null,
              fillColor: enabled
                  ? (backgroundColor ?? Colors.transparent)
                  : (backgroundColor ?? Colors.grey[200]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIngredientRow(Ingredient ingredient, int index) {
    final bool isDeleted = ingredient.isDeleted;
    final Color textColor = isDeleted ? Colors.grey[400]! : Colors.black87;
    final Color subTextColor =
        isDeleted ? Colors.grey[300]! : Colors.grey[600]!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: isDeleted ? Colors.grey[200] : const Color(0xFFF5F9F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDeleted ? Colors.grey[200]! : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.all(12), 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    ingredient.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    isDeleted
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                    color: isDeleted
                        ? Colors.teal
                        : Colors.red[300], 
                    size: 24, 
                  ),
                  onPressed: () {
                    setState(() {
                      ingredient.isDeleted = !ingredient.isDeleted;

                      if (ingredient.id != null) {
                        if (ingredient.isDeleted) {
                          _ingredientsToDelete.add(ingredient.id!);
                        } else {
                          _ingredientsToDelete.remove(ingredient.id!);
                        }
                      }
                      _calculateTotals();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),

            Text(
              '${ingredient.grams} g • ${ingredient.calories} kcal',
              style: TextStyle(fontSize: 14, color: subTextColor),
            ),
            const SizedBox(height: 8),

            Opacity(
              opacity: isDeleted ? 0.3 : 1.0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  _buildMacroInfo(Icons.circle,
                      Color.fromARGB(255, 117, 181, 233), ingredient.protein),
                  const SizedBox(width: 16),
                  _buildMacroInfo(Icons.circle,
                      Color.fromARGB(255, 132, 202, 206), ingredient.carbs),
                  const SizedBox(width: 16),
                  _buildMacroInfo(Icons.circle,
                      Color.fromARGB(255, 245, 190, 118), ingredient.fat),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroInfo(IconData icon, Color color, double value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16, 
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '${value.toStringAsFixed(1)}g',
          style: TextStyle(
            color: Colors.grey[800], 
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    final String path = widget.item.imagePath;

    if (path.startsWith('data:image') ||
        (path.length > 1000 && !path.startsWith('http'))) {
      try {
        final base64String =
            path.replaceFirst('data:image/jpeg;base64,', '');
        final Uint8List bytes = base64Decode(base64String);
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: 60,
          height: 60,
        );
      } catch (e) {
        print("圖片解碼錯誤: $e");
        imageWidget = const Icon(Icons.broken_image, color: Colors.grey);
      }
    }
    else if (path.startsWith('http')) {
      imageWidget = Image.network(
        path,
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, color: Colors.grey),
      );
    }
    else {
      imageWidget = const Icon(Icons.restaurant, color: Colors.grey);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 60,
                  height: 60,
                  color: Colors.grey[200],
                  child: imageWidget,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _isEditingName
                              ? SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: _nameController,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      hintText: '食物名稱',
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : Text(
                                  _nameController.text,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                        IconButton(
                          icon: Icon(
                            _isEditingName ? Icons.check : Icons.edit, 
                            color: Colors.grey[700],
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _isEditingName = !_isEditingName;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // A. 日期部分
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "${widget.selectedDate.year}/${widget.selectedDate.month.toString().padLeft(2, '0')}/${widget.selectedDate.day.toString().padLeft(2, '0')}",
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13),
                        ),

                        const SizedBox(width: 12), 

                        Expanded(
                          child: Container(
                            height: 30,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: PopupMenuButton<String>(
                              // 1. 設定偏移量 (X, Y)
                              offset: const Offset(0, 35),
                              // 2. 設定選單的圓角與背景
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              color: Colors.white,
                              elevation: 4,
                              // 3. 設定按鈕原本長什麼樣子 (顯示選中的文字 + 箭頭)
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _selectedMealType ?? '選擇時段', // 如果是 null 就顯示提示
                                      style: TextStyle(
                                        // 如果沒選(提示文字)用灰色，有選用黑色
                                        color: _selectedMealType == null 
                                            ? Colors.grey[500] 
                                            : Colors.black87,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down,
                                      size: 18, color: Colors.grey),
                                ],
                              ),
                              // 4. 當選擇項目時的邏輯
                              onSelected: (String newValue) {
                                setState(() {
                                  _selectedMealType = newValue;
                                });
                              },
                              // 5. 產生選單項目
                              itemBuilder: (BuildContext context) {
                                return _mealOptions.map((String value) {
                                  return PopupMenuItem<String>(
                                    value: value,
                                    height: 40,
                                    child: Text(
                                      value,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }).toList();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: _buildLabeledTextField(
                  '  總克數 (g)',
                  _gramController,
                  enabled: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLabeledTextField(
                  '  熱量 (kcal)',
                  _calController,
                  enabled: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildLabeledTextField(
                  '蛋白質(g)',
                  _proteinController,
                  enabled: false,
                  dotColor: const Color.fromARGB(255, 117, 181, 233),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLabeledTextField(
                  '碳水(g)',
                  _carbController,
                  enabled: false,
                  dotColor: const Color.fromARGB(255, 132, 202, 206),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLabeledTextField(
                  '脂肪(g)',
                  _fatController,
                  enabled: false,
                  dotColor: const Color.fromARGB(255, 245, 190, 118),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          const Text(
            'AI 總結食材清單',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),

          ListView.builder(
            shrinkWrap: true, 
            physics:
                const NeverScrollableScrollPhysics(), 
            itemCount: _ingredients.length,
            itemBuilder: (context, index) {
              return _buildIngredientRow(_ingredients[index], index);
            },
          ),

          const Text(
            'AI分析建議',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),

          Container(
            width: double.infinity, 
            padding: const EdgeInsets.all(12), 
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border.all(color: Colors.black), 
              borderRadius: BorderRadius.circular(12), 
            ),
            child: Text(
              widget.item.aiSuggestion.isEmpty
                  ? "暫無 AI 分析建議"
                  : widget.item.aiSuggestion,
              style: const TextStyle(
                color: Colors.black87,
                height: 1.5,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            '備註',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _remarksController, 
            decoration: InputDecoration(
              hintText: '新增備註...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
            maxLines: 3, 
          ),
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 157, 198, 194),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text('取消'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 157, 198, 194),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text('確定'),
                onPressed: () async {
                  if (widget.item.reference != null) {
                    try {
                      for (String deleteId in _ingredientsToDelete) {
                        print("正在從資料庫刪除食材 ID: $deleteId");
                        await widget.item.reference!
                            .collection('ingredients')
                            .doc(deleteId)
                            .delete();
                      }

                      await widget.item.reference!.update({
                        '食物名': _nameController.text,
                        '備註': _remarksController.text,
                        
                        // 儲存用餐時段 (如果為 null 則存空字串)
                        'meal_type': _selectedMealType ?? '',
                        'total_calories':
                            double.tryParse(_calController.text) ?? 0,
                        'total_protein':
                            double.tryParse(_proteinController.text) ?? 0,
                        'total_carbs':
                            double.tryParse(_carbController.text) ?? 0,
                        'total_fat':
                            double.tryParse(_fatController.text) ?? 0,
                        'last_updated': FieldValue.serverTimestamp(),
                      });

                      print("資料庫更新成功！");
                    } catch (e) {
                      print("更新失敗: $e");
                    }
                  }
                  if (mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}