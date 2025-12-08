// 匯入 Flutter 的 Material UI 函式庫
import 'package:flutter/material.dart';
import 'dart:async'; // 管理StreamSubscription(監聽器的開關)
import 'package:image_picker/image_picker.dart';
import 'package:fl_chart/fl_chart.dart'; //圓餅圖套件
import 'package:firebase_core/firebase_core.dart'; //Firebase核心
import 'package:cloud_firestore/cloud_firestore.dart'; // 引入Firestore資料庫功能
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert'; // 添加這行，為了 base64Decode
import 'dart:typed_data'; // 添加這行，為了 Uint8List
import 'analysisfood.dart'; // 假設 DashboardPage 在這裡
import 'settings.dart'; // 假設 SettingsPage 在這裡

// ----------------------------------------------
// 資料模型區(Models)：定義資料的樣子
// ----------------------------------------------

// 每個"食物"的資料結構
// 對應Firebase的路徑：users/uid/analysis_records/{document}
class FoodItem {
  String id; // 文件ID(刪除、修改用的)
  DocumentReference? reference; // 用來記住這筆資料在 Firebase 的準確位置
  String name; // 食物名稱
  String calories; // 總熱量
  String imagePath; // 圖片網址(Firebase Storage URL或外部連結)
  String grams; // 總熱量
  String protein; // 總蛋白質
  String carbs; // 總碳水化合物
  String fat; // 總脂肪
  List<Ingredient> ingredients; // 食材清單(從子集合中去讀取)
  String remark; // 備註(使用者可編輯)
  String aiSuggestion; // AI分析建議(唯讀，不可編輯)

  FoodItem({
    this.reference,
    required this.id,
    required this.name,
    required this.calories,
    required this.imagePath,
    this.grams = '0', // 給預設值
    this.protein = '0',
    this.carbs = '0',
    this.fat = '0',
    required this.ingredients,
    this.remark = '',
    this.aiSuggestion = '',
  });
}

// 每個"食材"的資料結構
// 對應Firebase的路徑：users/uid/analysis_records/{document}/ingredients/{sub_doc}
class Ingredient {
  final String? id;
  final String name; // 食材名稱
  final double grams; // 重量
  final double calories; // 熱量
  final double carbs; // 碳水化合物
  final double protein; // 蛋白質
  final double fat; // 脂肪

  bool isDeleted = false;

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
  late DateTime _selectedDate; // 目前選到的日期
  final ImagePicker _picker = ImagePicker();
  // Firebase監聽控制器(用來切換日期時關閉舊連線)
  StreamSubscription? _foodSubscription;

  // 判斷是否已設定目標(先設定為false)
  bool _isGoalSet = false;

  // 預設目標值(成人建議值)，當沒讀到資料時會顯示這些值
  double _targetCalories = 2000;
  double _targetProtein = 60;
  double _targetCarbs = 300;
  double _targetFat = 60;

  // UI顯示用的資料清單(會隨著Firebase更新而自動變動)
  List<FoodItem> _foodList = [];
  bool _isLoading = true; // 是否正在讀取資料

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

          // 定義什麼叫做「資料完整」：性別、年齡、身高、體重 都不可以是 null
          bool isComplete =
              data != null &&
              data['gender'] != null &&
              data['age'] != null &&
              data['height'] != null &&
              data['weight'] != null;

          if (mounted) {
            setState(() {
              // 更新狀態：如果完整，_isGoalSet 為 true (紅字消失)
              // 如果不完整，_isGoalSet 為 false (紅字顯示)
              _isGoalSet = isComplete;
              print("資料完整性檢查結果: $_isGoalSet"); // Debug log
            });
          }
          if (isComplete) {
            try {
              // 從 Firestore 讀取資料 (使用 tryParse 防止格式錯誤導致當機)
              String gender = data!['gender'].toString();

              // 處理數值轉換，如果資料庫存的是 String 也能轉成 int/double
              int age = int.tryParse(data['age'].toString()) ?? 25;
              double height = double.tryParse(data['height'].toString()) ?? 160;
              double weight = double.tryParse(data['weight'].toString()) ?? 50;

              // 呼叫剛剛寫好的計算函式
              _calculatePersonalizedTargets(gender, age, height, weight);
            } catch (e) {
              print("計算營養目標時發生錯誤: $e");
            }
          }
        } else {
          // 如果文件根本不存在，當然也要顯示紅字
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

    // 1. 計算 BMR (基礎代謝率) - 使用 Mifflin-St Jeor 公式
    // 公式來源參考：國際通用的代謝計算標準
    if (gender == '男性' || gender == '男' || gender.toLowerCase() == 'male') {
      // 男性公式: (10 × 公斤) + (6.25 × 公分) - (5 × 年齡) + 5
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      // 女性公式: (10 × 公斤) + (6.25 × 公分) - (5 × 年齡) - 161
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }

    // 2. 計算 TDEE (每日總消耗熱量)
    double tdee = bmr * 1.2;

    // 3. 設定三大營養素比例 (依照國人膳食營養素參考攝取量 DRIs 的建議範圍)
    // 碳水化合物 50-60%, 蛋白質 10-20%, 脂肪 20-30%
    // 這裡我們採用一個均衡的比例：
    double proteinRatio = 0.15; // 蛋白質 15%
    double carbsRatio = 0.55; // 碳水 55%
    double fatRatio = 0.30; // 脂肪 30%

    // 4. 更新 UI 變數 (使用 setState 觸發畫面更新)
    if (mounted) {
      setState(() {
        _targetCalories = tdee;

        // 蛋白質 (1克 = 4大卡)
        _targetProtein = (_targetCalories * proteinRatio) / 4;

        // 碳水化合物 (1克 = 4大卡)
        _targetCarbs = (_targetCalories * carbsRatio) / 4;

        // 脂肪 (1克 = 9大卡)
        _targetFat = (_targetCalories * fatRatio) / 9;
      });

      print(
        "已更新個人化目標: BMR=${bmr.toStringAsFixed(0)}, TDEE=${_targetCalories.toStringAsFixed(0)}",
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();

    // 一旦登入狀態改變 (登入或登出)，就會執行裡面的程式碼
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user == null) {
        // 情況 A：偵測到「已登出」
        print("系統：偵測到登出，正在清除畫面資料...");

        // 1. 停止監聽 Firestore 資料庫
        _foodSubscription?.cancel();

        // 2. 清空畫面上的資料
        if (mounted) {
          setState(() {
            _foodList.clear(); // 清空食物列表
            _isGoalSet = false; // 重置目標設定狀態
            _targetCalories = 2050; // 重置回預設熱量
            _isLoading = false; // 停止轉圈圈
          });
        }
      } else {
        // 情況 B：偵測到「已登入」 (包含剛開啟 App 或是剛完成匿名登入)
        print("系統：偵測到使用者 ID: ${user.uid}，開始讀取資料...");

        // 開始抓取這個人的資料
        _listenToFirebaseData();
        _checkUserDataStatus();
      }
    });

    // 如果一開始完全沒登入，就執行匿名登入
    _checkLoginAndListen();
  }

  // 如果沒人登入，就幫忙執行匿名登入
  Future<void> _checkLoginAndListen() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      try {
        print("系統：初次檢查無使用者，正在進行匿名登入...");
        await FirebaseAuth.instance.signInAnonymously();
        // 登入成功後，上面的 authStateChanges 會自動感應到，並開始讀取資料
      } catch (e) {
        print("系統：登入失敗: $e");
      }
    }
  }

  // 移除參數，改用 _selectedDate 進行精準查詢
  void _listenToFirebaseData() {
    // 1. 切斷舊的連線，避免重複監聽
    _foodSubscription?.cancel();

    // 取得當前登入的 UID
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserUid == null) {
      print("系統：目前沒有登入使用者，無法讀取資料。");
      setState(() {
        _isLoading = false;
      });
      return;
    }

    print("系統：切換日期至 ${_selectedDate.toString().split(' ')[0]}");
    print("系統：正在向 Firebase 請求該日期的資料...");

    // 2. 設定當天的「開始時間」與「結束時間」
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

    // 3. 建立帶有時間範圍過濾的查詢 - 使用正確的路徑結構
    _foodSubscription = FirebaseFirestore.instance
        .collection('users') // 第一層：users
        .doc(currentUserUid) // 第二層：使用者 UID
        .collection('analysis_records') // 第三層：分析記錄
        .where('created_at', isGreaterThanOrEqualTo: startOfDay)
        .where('created_at', isLessThanOrEqualTo: endOfDay)
        .orderBy('created_at', descending: true) // 按時間倒序排列
        .snapshots()
        .listen(
          (snapshot) async {
            List<FoodItem> newFoodList = [];

            try {
              for (var doc in snapshot.docs) {
                var data = doc.data();

                // 過濾垃圾資料 "string"
                String foodName = data['食物名'] ?? '未命名';
                if (foodName == 'string' || foodName == '未命名') continue;

                String docId = doc.id;
                String suggestion = data['AI分析建議'] ?? '';
                String imgUrl = data['圖片_base64'] ?? data['圖片網址'] ?? '';

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
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        );
  }

  // 把任何形態的數字轉乘double，防止資料庫格式錯誤導致App崩潰
  double _parseToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  Future<void> _pickImage(ImageSource source) async {
    // 呼叫 image_picker 的 pickImage 方法
    // 網頁版會開啟檔案總管，並篩選圖片
    final XFile? image = await _picker.pickImage(source: source);

    // XFile? 表示 image 可能是 XFile 或 null (如果使用者取消選擇)
    if (image != null) {
      // 如果有選到
      print('成功選取照片！');
      print('照片路徑 (在網頁上是 blob URL): ${image.path}');
    } else {
      // 如果使用者按了「取消」
      print('使用者取消選取');
    }
  }

  // 計算目前所有食物的總營養(左邊圓餅圖使用)
  _DailyTotals _calculateCurrentTotals() {
    final totals = _DailyTotals();
    // 迭代 _foodList 中的每一個食物
    for (final item in _foodList) {
      // 從 FoodItem 中讀取字串並轉換為 double
      final calString = item.calories.replaceAll(' 大卡', '');
      totals.calories += double.tryParse(calString) ?? 0;
      totals.protein += double.tryParse(item.protein) ?? 0;
      totals.carbs += double.tryParse(item.carbs) ?? 0;
      totals.fat += double.tryParse(item.fat) ?? 0;
    }
    return totals;
  }

  // --- 前往設定頁面並在返回時更新狀態 ---
  Future<void> _navigateToSettings() async {
    // 等待設定頁面關閉
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );

    // !!! 關鍵修改：無論回傳什麼，只要從設定頁回來，就檢查一次狀態 !!!
    if (mounted) {
      print("從設定頁返回，正在重新檢查資料完整性...");
      await _checkUserDataStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // ！！！關鍵修正：隱藏預設的返回鍵 (防止首頁出現上一頁箭頭)
        automaticallyImplyLeading: false,
        backgroundColor: const Color.fromARGB(255, 157, 198, 194),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () async {
              // 使用封裝好的函式
              await _navigateToSettings();
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      // 解決Overflow的關鍵：使用 Column+Expanded 限制高度
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          // 使用 LayoutBuilder 判斷螢幕寬度
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 如果螢幕寬度小於 900 像素，就改成垂直堆疊 (手機/平板直立模式)
              if (constraints.maxWidth < 900) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min, // 讓 Column 僅佔用其內容所需的垂直空間
                    children: [
                      // 左邊的圓餅圖和進度條 (移除 Expanded/Flex)
                      Container(
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
                        child: _buildLeftColumn(context, true),
                      ),
                      const SizedBox(height: 16),
                      // 右邊的歷史紀錄 (移除 Expanded/Flex)
                      _buildRightColumn(context),
                    ],
                  ),
                );
              }

              // 如果螢幕寬度夠大 (>= 900 像素)，則維持左右並排
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左邊(圓餅圖)
                  Expanded(
                    flex: 3,
                    child: Container(
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
                      child: _buildLeftColumn(context, false),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 右邊(歷史紀錄)
                  Expanded(flex: 2, child: _buildRightColumn(context)),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: Container(
        margin: const EdgeInsets.only(
          right: 20, // 距離右邊20px
          bottom: 25, // 距離底部100px
        ),
        child: FloatingActionButton.small(
          elevation: 4,
          backgroundColor: const Color.fromARGB(255, 157, 198, 194),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add, size: 20),
          onPressed: () async {
            // 🟢 修改重點：接收 DashboardPage 回傳的 true
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DashboardPage()),
            );

            // 如果回傳 true，代表有新增資料
            if (result == true) {
              if (mounted) {
                setState(() {
                  // 1. 將日期切換回「今天」
                  _selectedDate = DateTime.now();
                  // 2. 顯示讀取中
                  _isLoading = true;
                });
                // 3. 重新向 Firebase 請求今天的資料
                _listenToFirebaseData();
              }
            }
          },
        ),
      ),
    );
  }

  // 左邊UI
  Widget _buildLeftColumn(BuildContext context, bool isMobile) {
    // 在build時自動計算總合
    final _DailyTotals currentTotals = _calculateCurrentTotals();

    // 計算百分比(0.0-1.0之間)
    // 加上 .clamp(0, 1) 確保百分比不會超過 100% (不會溢出進度條)
    final double calPercent = (currentTotals.calories / _targetCalories).clamp(
      0,
      1,
    );
    final double proteinPercent = (currentTotals.protein / _targetProtein)
        .clamp(0, 1);
    final double carbPercent = (currentTotals.carbs / _targetCarbs).clamp(0, 1);
    final double fatPercent = (currentTotals.fat / _targetFat).clamp(0, 1);

    // 計算圓餅圖的占比
    // 從 currentTotals (單位: g) 轉換成熱量 (單位: kcal)
    final double proteinCalories = currentTotals.protein * 4;
    final double carbCalories = currentTotals.carbs * 4;
    final double fatCalories = currentTotals.fat * 9;
    // 加總"巨量營養素"的總熱量
    final double totalMacroCalories =
        proteinCalories + carbCalories + fatCalories;
    // 計算各自在環圈圖中的佔比 (0.0 ~ 1.0)
    // 處理 totalMacroCalories 為 0 的情況 (避免除以零)
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
            // 日期選擇工具
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

                    // 彈出日曆
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
                        _isLoading = true; // 切換日期時，先轉圈圈
                      });

                      // 選完日期後，重新去Firebase中抓取那天的資料
                      final user = FirebaseAuth.instance.currentUser;
                      if (user != null) {
                        // 已經移除 UID 參數，改用全域查詢
                        _listenToFirebaseData();
                      }
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 圓餅圖
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
            // 如果是手機版 (isMobile 為 true)，使用 Column (垂直排列)
            // 如果是電腦版 (isMobile 為 false)，使用 Row (水平排列)
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
                      // ！！這裡是控制紅字顯示的地方！！
                      if (!_isGoalSet) ...[
                        const SizedBox(height: 8), // 垂直間距
                        Align(
                          alignment: Alignment.centerLeft, // 靠左對齊
                          child: TextButton(
                            onPressed: () async {
                              // 使用封裝好的函式，確保回來時刷新
                              await _navigateToSettings();
                            },
                            style: ButtonStyle(
                              padding: WidgetStateProperty.all(EdgeInsets.zero),
                              minimumSize: WidgetStateProperty.all(Size.zero),
                              tapTargetSize: MaterialTapTargetSize
                                  .shrinkWrap, // 縮減點擊範圍至內容大小
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
                          ),
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
                        TextButton(
                          onPressed: () async {
                            // 使用封裝好的函式，確保回來時刷新
                            await _navigateToSettings();
                          },
                          style: ButtonStyle(
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
                        ),
                      ],
                    ],
                  ),

            //新增解決溢出問題
            const SizedBox(height: 15),

            // 營養進度條
            _buildNutrientBar('熱量 (Calories)', Color(0xFFE96A60), calPercent),
            const SizedBox(height: 15),
            _buildNutrientBar(
              '蛋白質 (Protein)',
              Color.fromARGB(255, 117, 181, 233),
              proteinPercent,
            ),
            const SizedBox(height: 15),
            _buildNutrientBar(
              '碳水化合物 (Carbs)',
              Color.fromARGB(255, 132, 202, 206),
              carbPercent,
            ),
            const SizedBox(height: 15),
            _buildNutrientBar(
              '脂肪 (Fat)',
              Color.fromARGB(255, 245, 190, 118),
              fatPercent,
            ),
          ],
        ),
      ),
    );
  }

  // 營養進度條 (輔助)
  Widget _buildNutrientBar(String label, Color color, double percentage) {
    final String percentageString = '${(percentage * 100).toStringAsFixed(0)}%';
    // 如果進度超過100%，文字顏色變紅
    final Color textColor = percentage >= 1.0 ? Colors.red : Colors.black54;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4), // 加上一點間距
        // 把進度條和 % 數放在一個Row裡面
        Row(
          children: [
            // 1. 進度條
            Expanded(
              // 讓進度條填滿所有可用空間
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

            // 2. 百分比文字
            const SizedBox(width: 12), // 進度條和文字的間距
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
            const Divider(), // 標題下的分隔線

            _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  ) // 如果正在讀取，顯示轉圈
                : _foodList.isEmpty
                ? const Center(child: Text("還沒有紀錄喔！"))
                : ListView.builder(
                    shrinkWrap: true, // 讓 ListView 僅佔用內容所需的空間
                    physics: const NeverScrollableScrollPhysics(), // 禁用內層捲動
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

  // 單一食物項目
  Widget _buildFoodItem(BuildContext context, FoodItem item) {
    print("檢查圖片資料：[${item.imagePath}]");

    // 解碼 Base64 圖片（如果存在）
    Uint8List? imageBytes;
    Widget imageWidget;

    // 檢查是否是 Base64 圖片
    if (item.imagePath.startsWith('data:image') ||
        (item.imagePath.length > 1000 && !item.imagePath.startsWith('http'))) {
      // 可能是 Base64 圖片
      try {
        final base64String = item.imagePath.replaceFirst(
          'data:image/jpeg;base64,',
          '',
        );
        imageBytes = base64Decode(base64String);
        imageWidget = Image.memory(
          imageBytes,
          fit: BoxFit.cover,
          width: 60,
          height: 60,
        );
        print('✅ 顯示 Base64 圖片');
      } catch (e) {
        print('❌ Base64 解碼錯誤: $e');
        imageWidget = _buildImagePlaceholder();
      }
    } else if (item.imagePath.startsWith('http')) {
      // 網路圖片
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
      // 預設圖標
      imageWidget = _buildImagePlaceholder();
    }

    return InkWell(
      onTap: () async {
        // 點擊後跳出彈窗顯示詳情
        final FoodItem? updatedItem = await _showFoodEditDialog(
          context,
          item,
          _selectedDate,
        );
        if (updatedItem != null) {
          // TODO: 如果之後要實作「修改資料」，要與 Firebase update 連接
          print("修改功能預留中");
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name, // 顯示名稱
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    item.calories, // 顯示大卡
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),

            // 垃圾桶按鈕的修正區塊
            SizedBox(
              // 解決水平溢位 (RenderFlex Overflow)
              width: 40, // 限制按鈕的最小寬度
              child: IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color.fromARGB(255, 26, 24, 23),
                ),
                onPressed: () {
                  // 點擊垃圾桶標示，跳出確認 Dialog
                  showDialog(
                    context: context,
                    builder: (BuildContext dialogContext) {
                      return AlertDialog(
                        title: const Text('刪除'),
                        content: Text('您確定要永久刪除「${item.name}」嗎？'),
                        actions: <Widget>[
                          // 取消按鈕
                          TextButton(
                            child: const Text('取消'),
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                            },
                          ),
                          // 確認按鈕
                          TextButton(
                            child: const Text('確認'),
                            onPressed: () async {
                              // 1. 先關閉彈窗
                              Navigator.of(dialogContext).pop();

                              // 2. 執行 Firebase 刪除指令 (使用 FoodItem 儲存的 reference)
                              if (item.reference != null) {
                                try {
                                  await item.reference!.delete();
                                  print("已成功從 Firebase 刪除文件: ${item.name}");
                                  // 💡 UI 會因為 Firebase Stream 自動更新！
                                } catch (e) {
                                  print("刪除失敗: $e");
                                  // 可選：顯示一個 Snackbar 提示使用者刪除失敗
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

  // 圖片佔位符
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
        // 1. 取得螢幕總寬度
        final double screenWidth = MediaQuery.of(context).size.width;

        // 2. 設定寬度邏輯：
        // 如果螢幕夠寬 (電腦/平板)，設為 600
        // 如果是手機，設為螢幕寬度的 90% (留一點邊距)
        final double dialogWidth = screenWidth > 800 ? 600 : screenWidth * 0.9;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Container(
            width: dialogWidth,
            // padding: const EdgeInsets.all(24.0), // 避免滾動條被擠壓

            // Dialog的內容在FoodEditDialogContent這個Widget裡
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
  // 接收從主頁面傳來的「原始」食物資料
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

  // 宣告_ingredients
  late List<Ingredient> _ingredients;
  // 宣告_isEditingName並給予初始值
  bool _isEditingName = false;
  // 用來暫存「準備要刪除」的食材 ID
  final List<String> _ingredientsToDelete = [];

  // 建立一個可自動計算所有食材總和的函式
  void _calculateTotals() {
    // 1. 先歸零
    double totalGrams = 0;
    double totalCalories = 0;
    double totalProtein = 0;
    double totalCarbs = 0;
    double totalFat = 0;

    // 2. 迭代 _ingredients List 進行加總
    for (final ingredient in _ingredients) {
      if (ingredient.isDeleted) continue;
      totalGrams += ingredient.grams;
      totalCalories += ingredient.calories;
      totalProtein += ingredient.protein;
      totalCarbs += ingredient.carbs;
      totalFat += ingredient.fat;
    }

    // 3. 更新 Controller 的文字
    // (熱量用整數計算，其他會計算到小數點後1位)
    _gramController.text = totalGrams.toStringAsFixed(1);
    _calController.text = totalCalories.toStringAsFixed(0);
    _proteinController.text = totalProtein.toStringAsFixed(1);
    _carbController.text = totalCarbs.toStringAsFixed(1);
    _fatController.text = totalFat.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    // 在 Widget 建立時，用傳進來的資料初始化所有 Controller
    _nameController = TextEditingController(text: widget.item.name);
    _gramController = TextEditingController();
    _calController = TextEditingController();
    _proteinController = TextEditingController();
    _carbController = TextEditingController();
    _fatController = TextEditingController();
    _remarksController = TextEditingController(text: widget.item.remark);

    _ingredients = List.from(widget.item.ingredients);
    _calculateTotals(); // 呼叫計算函式，填入初始總和
  }

  @override
  void dispose() {
    // dispose 所有 Controller
    _nameController.dispose();
    _gramController.dispose();
    _calController.dispose();
    _proteinController.dispose();
    _carbController.dispose();
    _fatController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  // 輔助函式：建立一個帶有標籤的輸入框
  Widget _buildLabeledTextField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.number,
    bool enabled = true,
    Color? backgroundColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller, // 綁定Controller
            keyboardType: keyboardType,
            enabled: enabled,

            style: const TextStyle(
              color: Colors.black87,
              fontSize: 13, // 字體大小
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
    // 根據是否刪除，決定顏色與透明度
    final bool isDeleted = ingredient.isDeleted;
    final Color textColor = isDeleted ? Colors.grey[400]! : Colors.black87;
    final Color subTextColor = isDeleted
        ? Colors.grey[300]!
        : Colors.grey[600]!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Container(
        // 如果刪除：背景變全白(或很淡的灰)；沒刪除：維持原本的淡底色
        decoration: BoxDecoration(
          color: isDeleted ? Colors.grey[200] : const Color(0xFFF5F9F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDeleted ? Colors.grey[200]! : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.all(12), // 稍微加點內距比較好看
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：食材名稱
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  ingredient.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor, // 套用顏色
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  // 切換圖示：刪除狀態顯示 + (加回來)，正常狀態顯示 - (刪除)
                  icon: Icon(
                    isDeleted
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                    color: isDeleted
                        ? Colors.teal
                        : Colors.red[300], // 刪除時變綠色(加回)，平時紅色
                    size: 24, // 稍微加大一點點比較好按
                  ),
                  onPressed: () {
                    setState(() {
                      // 1. 切換刪除狀態
                      ingredient.isDeleted = !ingredient.isDeleted;

                      // 2. 同步更新「待刪除清單 (_ingredientsToDelete)」
                      if (ingredient.id != null) {
                        if (ingredient.isDeleted) {
                          // 如果現在變成「已刪除」，加入待刪除清單
                          _ingredientsToDelete.add(ingredient.id!);
                        } else {
                          // 如果現在變成「恢復」，從待刪除清單移除
                          _ingredientsToDelete.remove(ingredient.id!);
                        }
                      }

                      // 3. 重新計算總數 (_calculateTotals 會自動過濾掉 isDeleted 的項目)
                      _calculateTotals();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 第二行：克數與熱量
            Text(
              '${ingredient.grams} g • ${ingredient.calories} kcal',
              style: TextStyle(fontSize: 14, color: subTextColor),
            ),
            const SizedBox(height: 8),

            // 第三行：三個營養素 (如果刪除就讓它變得很淡)
            Opacity(
              opacity: isDeleted ? 0.3 : 1.0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  _buildMacroInfo(
                    Icons.eco,
                    Color.fromARGB(255, 132, 202, 206),
                    ingredient.carbs,
                  ),
                  const SizedBox(width: 16),
                  _buildMacroInfo(
                    Icons.restaurant_menu,
                    Color.fromARGB(255, 117, 181, 233),
                    ingredient.protein,
                  ),
                  const SizedBox(width: 16),
                  _buildMacroInfo(
                    Icons.water_drop,
                    Color.fromARGB(255, 245, 190, 118),
                    ingredient.fat,
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
        Icon(
          icon,
          size: 16, // 圖示大小，可依需求調整
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '${value.toStringAsFixed(1)}g',
          style: TextStyle(
            color: Colors.grey[800], // 文字顏色
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

    // 檢查是否是 Base64 圖片 (長度很長且不以 http 開頭，或是明確以 data:image 開頭)
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
    }
    // 檢查是否是網路圖片
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
    // 預設圖示
    else {
      imageWidget = const Icon(Icons.restaurant, color: Colors.grey);
    }
    // SingleChildScrollView可確保鍵盤彈出時內容不會溢位
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min, // 讓Column符合內容高度
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 圖片與名稱
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
              const SizedBox(width: 16),
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
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                        // 編輯/完成按鈕
                        IconButton(
                          icon: Icon(
                            _isEditingName ? Icons.check : Icons.edit, // 切換圖示
                            color: Colors.grey[700],
                            size: 20,
                          ),
                          onPressed: () {
                            // 點擊圖示時，切換狀態
                            setState(() {
                              _isEditingName = !_isEditingName;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 時間
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          // 使用 widget.selectedDate 來動態格式化
                          "${widget.selectedDate.year}/${widget.selectedDate.month.toString().padLeft(2, '0')}/${widget.selectedDate.day.toString().padLeft(2, '0')}",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 2. 數值顯示區
          Row(
            children: [
              Expanded(
                child: _buildLabeledTextField(
                  '總克數 (g)',
                  _gramController,
                  enabled: false,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildLabeledTextField(
                  '熱量 (kcal)',
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
                  '蛋白質 (g)',
                  _proteinController,
                  enabled: false,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildLabeledTextField(
                  '碳水化合物 (g)',
                  _carbController,
                  enabled: false,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildLabeledTextField(
                  '脂肪 (g)',
                  _fatController,
                  enabled: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3. AI營養分析建議
          const Text(
            'AI 總結食材清單',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),

          // 食材清單
          ListView.builder(
            shrinkWrap: true, // 讓 ListView 符合內容高度
            physics:
                const NeverScrollableScrollPhysics(), // 由 SingleChildScrollView 滾動
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
            width: double.infinity, // 填滿寬度
            padding: const EdgeInsets.all(12), // 內距，讓文字不要貼著框
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border.all(color: Colors.black), //黑色邊框
              borderRadius: BorderRadius.circular(12), // 邊框變為圓角
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

          // 4. 使用者備註
          const Text(
            '備註',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _remarksController, // 綁定新的Controller
            decoration: InputDecoration(
              hintText: '新增備註...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
            maxLines: 3, // 可以輸入多行
          ),
          const SizedBox(height: 24),

          // 5. 取消/確定按鈕
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
                  // 關閉 Dialog，回傳 null
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
                // 連動 Firebase 的核心邏輯
                onPressed: () async {
                  if (widget.item.reference != null) {
                    try {
                      // 1. 從資料庫刪除食材
                      for (String deleteId in _ingredientsToDelete) {
                        print("正在從資料庫刪除食材 ID: $deleteId");
                        await widget.item.reference!
                            .collection('ingredients')
                            .doc(deleteId)
                            .delete();
                      }

                      // 2. 更新主文件 (名稱、備註)
                      // 注意：如果您的資料庫有 'total_calories' 等欄位，請在這裡加上更新
                      await widget.item.reference!.update({
                        '食物名': _nameController.text,
                        '備註': _remarksController.text,
                        'total_calories':
                            double.tryParse(_calController.text) ?? 0,
                        'total_protein':
                            double.tryParse(_proteinController.text) ?? 0,
                        'total_carbs':
                            double.tryParse(_carbController.text) ?? 0,
                        'total_fat': double.tryParse(_fatController.text) ?? 0,
                        // 強制觸發更新的時間戳記，確保 App 一定會收到通知
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
