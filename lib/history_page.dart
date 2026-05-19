// 匯入 Flutter 的 Material UI 函式庫
import 'package:flutter/material.dart';
import 'dart:async'; // 管理StreamSubscription(監聽器的開關)
import 'package:fl_chart/fl_chart.dart'; //圓餅圖套件
import 'package:cloud_firestore/cloud_firestore.dart'; // 引入Firestore資料庫功能
import 'package:firebase_auth/firebase_auth.dart';
import 'report_page.dart' as rp;
import 'ana2.dart' as ana2;
import 'dart:convert'; // 添加這行，為了 base64Decode
import 'dart:typed_data'; // 添加這行，為了 Uint8List
// 通知欄
import 'notifications/notification_ui.dart';
import 'notifications/notification_bell.dart';
// 🟢 引入切換按鈕元件 (家庭共享功能)
import '../widgets/family_switcher.dart';
// Models
import 'models.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
  // 🟢 變數：控制「現在看誰的資料」
  String? _targetUid;
  String _targetName = "我自己";

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

  // 檢查使用者資料完整性 (檢查"自己"，因為目標是設定自己的BMR)
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
          bool isComplete =
              data != null &&
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
    String gender,
    int age,
    double height,
    double weight,
  ) {
    double bmr = 0;
    // 1. 計算 BMR (基礎代謝率)
    if (gender == '男性' || gender == '男' || gender.toLowerCase() == 'male') {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }

    // 2. 計算 TDEE (個人每日總熱量需求)
    double tdee = bmr * 1.2;

    // 3. 設定營養素比例
    double proteinRatio = 0.12;
    double fatRatio = 0.27;
    double carbsRatio = 0.60;

    if (mounted) {
      setState(() {
        _targetCalories = tdee;
        _targetProtein = (_targetCalories * proteinRatio) / 4;
        _targetCarbs = (_targetCalories * carbsRatio) / 4;
        _targetFat = (_targetCalories * fatRatio) / 9;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();

    // 🟢 初始化目標 UID 為自己
    _targetUid = FirebaseAuth.instance.currentUser?.uid;

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
            _targetUid = null; // 清除目標 UID
            _targetName = "我自己";
          });
        }
      } else {
        print("系統：偵測到使用者 ID: ${user.uid}，開始讀取資料...");
        // 🟢 登入時，預設看自己
        if (_targetUid == null) {
          _targetUid = user.uid;
          _targetName = "我自己";
        }
        _listenToFirebaseData();
        _checkUserDataStatus();
      }
    });
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

  // 監聽 Firebase(即時抓取資料)
  void _listenToFirebaseData() {
    _foodSubscription?.cancel();

    // 🟢 使用 _targetUid 決定要抓取誰的資料
    final uidToFetch = _targetUid;
    if (uidToFetch == null) {
      setState(() {
        _isLoading = false;
        _foodList = [];
      });
      return;
    }

    print("正在監聽資料，目標 UID: $uidToFetch (${_targetName})");

    final DateTime startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      0,
      0,
      0,
    );
    final DateTime endOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      23,
      59,
      59,
      999,
    );

    _foodSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uidToFetch)
        .collection('analysis_records')
        .where('created_at', isGreaterThanOrEqualTo: startOfDay)
        .where('created_at', isLessThanOrEqualTo: endOfDay)
        .orderBy('created_at', descending: true)
        // 當 Firebase 從「快取」抓到資料時，會立刻觸發第一次 listen
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) async {
            // 無論是快取還是雲端資料，都先顯示（不再因為網路錯誤清空列表)
            List<FoodItem> newFoodList = [];
            try {
              for (var doc in snapshot.docs) {
                if (doc.reference == null) {
                  print("⚠️ 跳過一筆紀錄：reference 為 null (id=${doc.id})");
                  continue;
                }
                var data = doc.data();
                String foodName = data['食物名'] ?? '未命名';
                if (foodName == 'string' || foodName == '未命名') continue;

                String docId = doc.id;
                String suggestion = data['AI分析建議'] ?? '';
                String imgUrl = data['圖片_base64'] ?? data['圖片網址'] ?? '';
                String mealType = (data['meal_type'] ?? '').toString();

                // 取得建立時間
                Timestamp? createdAt = data['created_at'];
                DateTime itemTime = createdAt != null
                    ? createdAt.toDate()
                    : DateTime.now();

                if (mealType.isEmpty) {
                  mealType = _getMealTypeByTime(itemTime);
                }

                List<Ingredient> ingredientsList = [];
                double totalGrams = 0;
                double totalCalories = 0;
                double totalProtein = 0;
                double totalCarbs = 0;
                double totalFat = 0;

                try {
                  var ingredientSnapshot = await doc.reference
                      .collection('ingredients')
                      .get();

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
                } catch (ingredientError) {
                  print("⚠️ 讀取食材失敗 (文件 $docId): $ingredientError");
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
                    createdAt: itemTime,
                  ),
                );
              }
            } catch (e, stack) {
              print("🔥 處理資料時發生未預期錯誤: $e\n$stack");
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
            if (error.toString().contains("permission")) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("您沒有權限查看此家人的資料")));
            }
            // 發生錯誤時，也要結束載入狀態
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

  // 🟢 開啟週報月報 (動態帶入正在觀看的對象 UID)
  Future<void> _openReportPage() async {
    final reportTargetUid =
        _targetUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => rp.ReportPage(
          userId: reportTargetUid,
          initialReferenceDate: _selectedDate, // 傳入目前選擇的日期
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 主頁頂端橫列
      appBar: AppBar(
        automaticallyImplyLeading: false,
        // 🟢 修改標題：顯示目前正在看誰
        // title: _targetName == "我自己"
        //     ? null
        //     : Text("正在檢視: $_targetName", style: const TextStyle(fontSize: 16)),
        actions: [
          // 1. 家庭切換器 (來自 familysetting0402)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FamilySwitcher(
              currentName: _targetName,
              onSelected: (uid, name) {
                setState(() {
                  _targetUid = uid;
                  _targetName = name;
                  _isLoading = true; // 切換時顯示 loading
                });
                // 重新監聽資料流
                _listenToFirebaseData();
              },
            ),
          ),

          // 2. 通知鈴鐺 (來自 main 分支)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: NotificationBell(
              onPressed: () {
                NotificationUI.showTodayNotifications(context);
              },
            ),
          ),

          // 3. 週報月報按鈕
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              onPressed: _openReportPage,
              icon: const Icon(Icons.bar_chart),
              // tooltip: '週報月報',
            ),
          ),

          // 4. 設定按鈕
          Padding(
            padding: const EdgeInsets.only(right: 15.0),
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
                      // 🟢 如果是看家人，顯示醒目的提示條
                      if (_targetName != "我自己")
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "您目前正在檢視 $_targetName 的飲食紀錄 (唯讀模式)",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.orange[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
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
                      _buildLeftColumn(context, false),
                    ),
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
        margin: const EdgeInsets.only(right: 20, bottom: 25),
        // 🟢 如果是看家人，隱藏新增按鈕 (不能幫家人新增)
        child: _targetName != "我自己"
            ? null
            : FloatingActionButton.small(
                elevation: 4,
                backgroundColor: const Color.fromARGB(255, 157, 198, 194),
                foregroundColor: Colors.white,
                child: const Icon(Icons.add, size: 20),
                onPressed: () async {
                  final result = await Navigator.pushNamed(
                    context,
                    '/analysis',
                  );

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
    final double calPercent = (currentTotals.calories / _targetCalories).clamp(
      0,
      1,
    );
    final double proteinPercent = (currentTotals.protein / _targetProtein)
        .clamp(0, 1);
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
    final double carbRingPercent = totalMacroCalories == 0
        ? 0
        : carbCalories / totalMacroCalories;
    final double fatRingPercent = totalMacroCalories == 0
        ? 0
        : fatCalories / totalMacroCalories;

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
                      now.year - 5,
                      now.month,
                      now.day,
                    );

                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate.isAfter(now)
                          ? now
                          : _selectedDate,
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
                    // 左邊儀表板：圓餅圖(算蛋白質、脂質、碳水化合物熱量各的占比占總熱量的%數)
                    PieChart(
                      PieChartData(
                        sectionsSpace: 0,
                        centerSpaceRadius: 70,
                        sections: [
                          PieChartSectionData(
                            color: const Color.fromARGB(255, 117, 181, 233),
                            value: proteinRingPercent * 100,
                            radius: 30,
                            showTitle: false,
                          ),
                          PieChartSectionData(
                            color: const Color.fromARGB(255, 132, 202, 206),
                            value: carbRingPercent * 100,
                            radius: 30,
                            showTitle: false,
                          ),
                          PieChartSectionData(
                            color: const Color.fromARGB(255, 245, 190, 118),
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
                                Text(
                                  '蛋白質: ${(proteinRingPercent * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  '碳水: ${(carbRingPercent * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  '脂肪: ${(fatRingPercent * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (isMobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題 + 提示 icon
                  Row(
                    children: [
                      const Text(
                        '成人每日建議營養攝取量',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // 這裡插入提示 icon
                      _buildInfoTooltip(),
                    ],
                  ),
                  // 如果還沒設定目標，且正在看自己的資料，顯示設定按鈕
                  if (!_isGoalSet && _targetName == "我自己") ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _buildSetGoalButton(),
                    ),
                  ],
                ],
              )
            else
              // 電腦版
              Row(
                children: [
                  const Text(
                    '成人每日建議營養攝取量',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  // 這裡插入提示 icon
                  _buildInfoTooltip(),

                  const Spacer(),

                  if (!_isGoalSet && _targetName == "我自己")
                    _buildSetGoalButton(),
                ],
              ),

            const SizedBox(height: 15),

            // 1. 熱量條
            _buildNutrientBar(
              '熱量 (Calories)',
              const Color(0xFFE96A60),
              calPercent,
              targetValue: _targetCalories,
              unit: 'kcal',
            ),
            const SizedBox(height: 15),

            // 2. 蛋白質條
            _buildNutrientBar(
              '蛋白質 (Protein)',
              const Color.fromARGB(255, 117, 181, 233),
              proteinPercent,
              targetValue: _targetProtein * 4,
              unit: 'kcal',
            ),
            const SizedBox(height: 15),

            // 3. 碳水化合物條
            _buildNutrientBar(
              '碳水化合物 (Carbs)',
              const Color.fromARGB(255, 132, 202, 206),
              carbPercent,
              targetValue: _targetCarbs * 4,
              unit: 'kcal',
            ),
            const SizedBox(height: 15),

            // 4. 脂肪條
            _buildNutrientBar(
              '脂肪 (Fat)',
              const Color.fromARGB(255, 245, 190, 118),
              fatPercent,
              targetValue: _targetFat * 9,
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
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFF7A9C99);
          }
          return const Color(0xFFA5C5C2);
        }),
      ),
      child: const Text(
        '> 設定完整健康目標以查看報告',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildInfoTooltip() {
    return Tooltip(
      message: '進度條將依據您的個人資料\n計算每日的營養攝取目標，\n並顯示目前各類的攝取達成率。',
      preferBelow: false,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      verticalOffset: 12,
      showDuration: const Duration(seconds: 3),
      decoration: BoxDecoration(
        color: Colors.grey[600]?.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      child: Transform.translate(
        offset: const Offset(0, 3.0), // 這裡控制移動：往右 0，往下 3.0
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Colors.grey[600],
          ),
        ),
      ),
    );
  }

  // 左側儀表板：進度條工具(會呼叫4次，印出紅、藍、綠、橘色四條進度條)
  Widget _buildNutrientBar(
    String label,
    Color color,
    double percentage, {
    double? targetValue,
    String unit = '',
  }) {
    final String percentageString = '${(percentage * 100).toStringAsFixed(0)}%';
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
                  value: percentage, // 長度
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
                ? const Center(child: CircularProgressIndicator())
                : _foodList.isEmpty
                ? const Center(child: Text("目前尚無餐點分析紀錄！"))
                // 如果有10筆資料，就會將10個資料欄位整齊排在右側
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
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
    Widget imageWidget;

    if (item.imagePath.startsWith('data:image') ||
        (item.imagePath.length > 1000 && !item.imagePath.startsWith('http'))) {
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

    // 🟢 如果正在看家人的資料，點擊應該是「只能看，不能改」
    final bool isViewingOthers = _targetName != "我自己";

    return InkWell(
      onTap: isViewingOthers
          ? null // 監控模式下不可編輯
          : () async {
              await _showFoodEditDialog(context, item, _selectedDate);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        // 資料(食物)欄位的細節
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
                  // 顯示此食物
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
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),

            // 🟢 如果是看家人，不顯示刪除按鈕
            if (!isViewingOthers)
              SizedBox(
                width: 40,
                // 資料(食物)欄位右側的垃圾桶按鈕
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
                                    print("已成功從 Firebase 刪除文件: ${item.name}");
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
        final double dialogWidth = screenWidth > 800 ? 600 : screenWidth * 0.9;

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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  late TextEditingController _nameController;
  late TextEditingController _gramController;
  late TextEditingController _calController;
  late TextEditingController _proteinController;
  late TextEditingController _carbController;
  late TextEditingController _fatController;
  late TextEditingController _remarksController;

  late List<Ingredient> _ingredients;
  bool _isEditingName = false;
  bool _isOnline = true; // 預設為有網路狀態
  final List<String> _ingredientsToDelete = [];
  final List<String> _mealOptions = ['早餐', '午餐', '晚餐', '點心'];
  String? _selectedMealType;

  void _calculateTotals() {
    double totalGrams = 0;
    double totalCalories = 0;
    double totalProtein = 0;
    double totalCarbs = 0;
    double totalFat = 0;

    // 1. 只計算那些沒有被標記為 isDeleted 的食材
    for (final ingredient in _ingredients) {
      if (!ingredient.isDeleted) {
        totalGrams += ingredient.grams;
        totalCalories += ingredient.calories;
        totalProtein += ingredient.protein;
        totalCarbs += ingredient.carbs;
        totalFat += ingredient.fat;
      }
    }
    // 2. 將計算結果更新到所有的 Controller 中
    // 使用 toStringAsFixed(1) 保持美觀，熱量通常用整數 (0)
    _gramController.text = totalGrams.toStringAsFixed(1);
    _calController.text = totalCalories.toStringAsFixed(0);
    _proteinController.text = totalProtein.toStringAsFixed(1);
    _carbController.text = totalCarbs.toStringAsFixed(1);
    _fatController.text = totalFat.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _checkInitialConnection(); // 初始化時檢查一次網路
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (mounted) {
        setState(() {
          // 只要列表裡面沒有 none，就代表有連線
          _isOnline = !results.contains(ConnectivityResult.none);
        });
      }
    });
    // 點擊資料(食物)欄位時會跳出視窗，將此食物裡的所有食材等顯示出來
    _nameController = TextEditingController(text: widget.item.name);
    _gramController = TextEditingController();
    _calController = TextEditingController();
    _proteinController = TextEditingController();
    _carbController = TextEditingController();
    _fatController = TextEditingController();
    _remarksController = TextEditingController(text: widget.item.remark);
    // 透過map和copy()產生全新的食材列表
    _ingredients = widget.item.ingredients.map((e) => e.copy()).toList();
    _calculateTotals(); // 確保重新計算數值

    // 初始化用餐時段：如果有值就設定，沒值(空字串)就設為 null
    if (widget.item.mealType.isNotEmpty &&
        _mealOptions.contains(widget.item.mealType)) {
      _selectedMealType = widget.item.mealType;
    }
    // 初始化數值
    _gramController.text = widget.item.grams;
    _calController.text = widget.item.calories.replaceAll(' 大卡', '');
    _proteinController.text = widget.item.protein;
    _carbController.text = widget.item.carbs;
    _fatController.text = widget.item.fat;
  }

  // 檢查目前的網路狀態
  Future<void> _checkInitialConnection() async {
    final connectivityResult = await (Connectivity().checkConnectivity());
    setState(() {
      // 只要不是 none，就代表有連線 (Wi-Fi 或 行動數據)
      _isOnline = connectivityResult != ConnectivityResult.none;
    });
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
    _connectivitySubscription?.cancel();
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
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
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
    final Color subTextColor = isDeleted
        ? Colors.grey[300]!
        : Colors.grey[600]!;

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
                  // 處理視窗中顯示的食材旁邊的"紅色減號按鈕"
                  // 當點擊此按鈕，這筆食材會返灰，視窗上方的總熱量、克數等數值會立即更新
                  icon: Icon(
                    isDeleted
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                    color: isDeleted ? Colors.teal : Colors.red[300],
                    size: 24,
                  ),
                  onPressed: () {
                    setState(() {
                      // 切換狀態
                      ingredient.isDeleted = !ingredient.isDeleted;

                      // 管理待刪除清單
                      if (ingredient.id != null) {
                        if (ingredient.isDeleted) {
                          _ingredientsToDelete.add(ingredient.id!);
                        } else {
                          _ingredientsToDelete.remove(ingredient.id!);
                        }
                      }
                      // 重新計算並更新總數值
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
                  _buildMacroInfo(
                    Icons.circle,
                    const Color.fromARGB(255, 117, 181, 233),
                    ingredient.protein, // 蛋白質(藍色圓點)
                  ),
                  const SizedBox(width: 16),
                  _buildMacroInfo(
                    Icons.circle,
                    const Color.fromARGB(255, 132, 202, 206),
                    ingredient.carbs, // 碳水化合物(綠色圓點)
                  ),
                  const SizedBox(width: 16),
                  _buildMacroInfo(
                    Icons.circle,
                    const Color.fromARGB(255, 245, 190, 118),
                    ingredient.fat, // 脂質(橘色圓點)
                  ),
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
        Icon(icon, size: 16, color: color),
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
    // 判斷：如果熱量是 0 大卡，就代表它是離線存下來、還沒分析過的資料
    bool isOfflineData =
        widget.item.calories == "0 大卡" || widget.item.calories == "0";
    if (path.startsWith('data:image') ||
        (path.length > 1000 && !path.startsWith('http'))) {
      try {
        final base64String = path.replaceFirst('data:image/jpeg;base64,', '');
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
    } else if (path.startsWith('http')) {
      imageWidget = Image.network(
        path,
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, color: Colors.grey),
      );
    } else {
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
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _selectedMealType ?? '選擇時段',
                                      style: TextStyle(
                                        color: _selectedMealType == null
                                            ? Colors.grey[500]
                                            : Colors.black87,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_drop_down,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
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
          if (!isOfflineData) ...[
            // 只有非離線時才會顯示
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
          ] else ...[
            // 離線模式
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                // 如果沒網路(_isOnline為false)，onPressed設為null，按鈕會呈現灰色(不可點擊)
                onPressed: _isOnline
                    ? () async {
                        // 這裡的 item 代表所點擊的那筆歷史紀錄物件
                        // item.imagePath 存著舊照片的 base64 字串，item.id 存著這筆紀錄在資料庫的 ID
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ana2.DashboardPage3(
                              existingImageBase64:
                                  widget.item.imagePath, // 塞入舊照片
                              documentId: widget.item.id, // 塞入舊紀錄的 ID
                              recordTime: widget
                                  .item
                                  .createdAt, // 把這筆紀錄原本在 Firebase 存的時間傳過去
                            ),
                          ),
                        );
                        // 如果點完確定儲存回來，result 會是 true，就重新整理畫面
                        if (result == true) {
                          // 加上外層 context 判定，確保 dialog 關閉後安全執行
                          if (mounted) {
                            // 因為這是在 Dialog 裡面，要先把這個修改詳情視窗也關掉，並傳 true 給最外層主頁面
                            Navigator.of(context).pop(true);
                          }
                        }
                      }
                    : null,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  _isOnline ? "進行 AI 分析" : "需網路連線以進行分析",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  // 有連線時用主題色，沒連線時會改為灰色
                  backgroundColor: const Color(0xFF9DC6C2),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300], // 反灰後的顏色
                  disabledForegroundColor: Colors.grey[600],
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                _isOnline ? "※ 此為離線紀錄，連上網路後點擊上方按鈕產出分析報告" : "⚠️ 目前無網路連線，分析功能已停用",
                style: TextStyle(
                  color: _isOnline ? Colors.grey : Colors.red[300],
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          // (1) AI 總結食材清單
          if (!isOfflineData) ...[
            const Text(
              'AI 總結食材清單',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ingredients.length,
              itemBuilder: (context, index) {
                return _buildIngredientRow(_ingredients[index], index);
              },
            ),
            const SizedBox(height: 24), // 增加間距讓畫面平衡
          ],

          // 下方繼續接「AI 分析建議」的部分
          const Text(
            'AI 分析建議',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          // 為一灰底黑框的建議文字欄位區(僅輸出AI判讀，不可手動修改)
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
          // (3) 備註
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
                        'total_fat': double.tryParse(_fatController.text) ?? 0,
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
