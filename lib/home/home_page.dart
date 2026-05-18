// home_page.dart
// 首頁：只負責狀態管理、Firebase 監聽、頁面骨架。
// UI 細節委派給 nutrition_widgets.dart，邏輯委派給 nutrition_helpers.dart。

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models.dart';
import '../report_page.dart';
import '../notifications/notification_handler.dart';
import '../notifications/notification_ui.dart';
import '../notifications/notification_bell.dart';
import '../widgets/family_switcher.dart';

import 'nutrition_helpers.dart';
import 'nutrition_widgets.dart';
import 'food_edit_dialog.dart';

class NutritionHomePage extends StatefulWidget {
  const NutritionHomePage({super.key});

  @override
  State<NutritionHomePage> createState() => _NutritionHomePageState();
}

class _NutritionHomePageState extends State<NutritionHomePage> {
  // ── 狀態 ─────────────────────────────────────────────────────────────────────

  String?                _targetUid; // 目標 UID（預設為自己），現在看誰的資料
  String                 _targetName = "我自己";
  late DateTime          _selectedDate;
  StreamSubscription?    _foodSubscription;

  bool               _isGoalSet   = false;
  NutritionTargets   _targets     = NutritionTargets.defaults();
  List<FoodItem>     _foodList    = [];
  bool               _isLoading   = true;

  // ── 生命週期 ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // 🟢 初始化目標 UID 為自己
    _targetUid = FirebaseAuth.instance.currentUser?.uid;
    _targetName = "我自己";
    _selectedDate = DateTime.now();
    NotificationHandler.init();

    // 監聽登入狀態變化
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _onSignOut();
      } else {
        _listenToFirebaseData();
        _checkUserDataStatus();
      }
    });

    _checkLoginAndListen();
  }

  @override
  void dispose() {
    _foodSubscription?.cancel();
    super.dispose();
  }

  // ── Firebase 相關 ─────────────────────────────────────────────────────────────

  void _onSignOut() {
    _foodSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _foodList.clear();
      _isGoalSet = false;
      _targets   = NutritionTargets.defaults();
      _isLoading = false;
    });
  }

  Future<void> _checkLoginAndListen() async {
    if (FirebaseAuth.instance.currentUser == null) {
      debugPrint('系統：初次檢查無使用者');
    }
  }

  /// 檢查個人資料完整性，若完整則計算個人化目標
  Future<void> _checkUserDataStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        if (mounted) setState(() => _isGoalSet = false);
        return;
      }

      final data = doc.data();
      final complete = data != null &&
          data['gender'] != null &&
          data['age']    != null &&
          data['height'] != null &&
          data['weight'] != null;

      if (mounted) setState(() => _isGoalSet = complete);

      if (complete) {
        final targets = calculateTargets(
          gender: data!['gender'].toString(),
          age:    int.tryParse(data['age'].toString())        ?? 25,
          height: double.tryParse(data['height'].toString())  ?? 160,
          weight: double.tryParse(data['weight'].toString())  ?? 50,
        );
        if (mounted) setState(() => _targets = targets);
      }
    } catch (e) {
      debugPrint('checkUserDataStatus 錯誤: $e');
    }
  }

  /// 監聽當日 Firestore 食物分析紀錄
  void _listenToFirebaseData() {
    _foodSubscription?.cancel();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    final start = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0);
    final end = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59, 999);

    _foodSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('analysis_records')
        .where('created_at', isGreaterThanOrEqualTo: start)
        .where('created_at', isLessThanOrEqualTo: end)
        .orderBy('created_at', descending: true)
        .snapshots()
        .listen(
          _onSnapshotReceived,
          onError: (e) {
            debugPrint('Firebase 查詢錯誤: $e');
            if (mounted) setState(() => _isLoading = false);
          },
        );
  }

  /// 解析 Firestore snapshot → FoodItem 列表
  Future<void> _onSnapshotReceived(QuerySnapshot snapshot) async {
    final List<FoodItem> result = [];

    try {
      for (final doc in snapshot.docs) {
        final item = await _parseFoodItem(doc);
        if (item != null) result.add(item);
      }
    } catch (e) {
      debugPrint('處理 snapshot 錯誤: $e');
    }

    if (mounted) {
      setState(() {
        _foodList  = result;
        _isLoading = false;
      });
    }
  }

  /// 將單份 Firestore 文件解析成 FoodItem；無效文件回傳 null
  Future<FoodItem?> _parseFoodItem(QueryDocumentSnapshot doc) async {
    final data     = doc.data() as Map<String, dynamic>;
    final foodName = data['食物名'] ?? '未命名';
    if (foodName == 'string' || foodName == '未命名') return null;

    // 餐別判斷
    String mealType = (data['meal_type'] ?? '').toString();
    if (mealType.isEmpty) {
      final ts  = data['created_at'] as Timestamp?;
      mealType  = mealTypeByTime(ts?.toDate() ?? DateTime.now());
    }

    // 食材子集合
    double g = 0, cal = 0, p = 0, c = 0, f = 0;
    final List<Ingredient> ingredients = [];

    try {
      final ingSnap = await doc.reference.collection('ingredients').get();
      for (final ing in ingSnap.docs) {
        final d = ing.data();
        final grams    = parseToDouble(d['重量(g)']);
        final calories = parseToDouble(d['熱量(kcal)']);
        final protein  = parseToDouble(d['蛋白質(g)']);
        final carbs    = parseToDouble(d['碳水化合物(g)']);
        final fat      = parseToDouble(d['脂肪(g)']);

        g   += grams;
        cal += calories;
        p   += protein;
        c   += carbs;
        f   += fat;

        ingredients.add(Ingredient(
          id:       ing.id,
          name:     d['食材名'] ?? '未知食材',
          grams:    grams,
          calories: calories,
          carbs:    carbs,
          protein:  protein,
          fat:      fat,
        ));
      }
    } catch (e) {
      debugPrint('讀取食材錯誤: $e');
    }

    return FoodItem(
      reference:   doc.reference,
      id:          doc.id,
      name:        foodName,
      calories:    '${cal.toStringAsFixed(0)} 大卡',
      imagePath:   data['圖片_base64'] ?? data['圖片網址'] ?? '',
      grams:       g.toStringAsFixed(1),
      protein:     p.toStringAsFixed(1),
      carbs:       c.toStringAsFixed(1),
      fat:         f.toStringAsFixed(1),
      ingredients: ingredients,
      remark:      data['備註'] ?? '',
      aiSuggestion: data['AI分析建議'] ?? '',
      mealType:    mealType,
    );
  }

  // ── 導航 ──────────────────────────────────────────────────────────────────────

  Future<void> _navigateToSettings() async {
    await Navigator.pushNamed(context, '/settings');
    if (mounted) await _checkUserDataStatus();
  }

  Future<void> _openReportPage() async {
    final reportTargetUid =
        _targetUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportPage(
          userId: reportTargetUid,
          initialReferenceDate: _selectedDate, // 傳入目前選擇的日期
        ),
      ),
    );
  }

  // ── 計算 ──────────────────────────────────────────────────────────────────────

  DailyTotals _calcCurrentTotals() {
    final totals = DailyTotals();
    for (final item in _foodList) {
      totals.calories += double.tryParse(item.calories.replaceAll(' 大卡', '')) ?? 0;
      totals.protein  += double.tryParse(item.protein) ?? 0;
      totals.carbs    += double.tryParse(item.carbs)   ?? 0;
      totals.fat      += double.tryParse(item.fat)     ?? 0;
    }
    return totals;
  }

  // ── 建構 ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                // 手機版：垂直排列
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShadowCard(child: _buildLeftColumn(isMobile: true)),
                      const SizedBox(height: 16),
                      _buildRightColumn(),
                    ],
                  ),
                );
              }
              // 桌機版：左右並排
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      flex: 3,
                      child: ShadowCard(
                          child: _buildLeftColumn(isMobile: false))),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildRightColumn()),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: _buildFab(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
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
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: NotificationBell(
            onPressed: () => NotificationUI.showTodayNotifications(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: const Icon(Icons.bar_chart),
            // onPressed: () => Navigator.pushNamed(context, '/reports'),
            onPressed: () => _openReportPage(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 25),
          child: IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSettings,
          ),
        ),
      ],
    );
  }

  Widget _buildFab() {
    return Container(
      margin: const EdgeInsets.only(right: 20, bottom: 25),
      // 只有在查看自己的資料時才顯示 FAB
      child: _targetName != "我自己"
        ? null
        : FloatingActionButton.small(
        elevation: 4,
        backgroundColor: const Color.fromARGB(255, 157, 198, 194),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 20),
        onPressed: () async {
          final result = await Navigator.pushNamed(context, '/analysis');
          if (result == true && mounted) {
            setState(() {
              _selectedDate = DateTime.now();
              _isLoading    = true;
            });
            _listenToFirebaseData();
          }
        },
      ),
    );
  }

  // ── 左欄（儀表板）────────────────────────────────────────────────────────────

  Widget _buildLeftColumn({required bool isMobile}) {
    final totals = _calcCurrentTotals();

    final calPct     = (totals.calories / _targets.calories).clamp(0.0, 1.0);
    final proteinPct = (totals.protein  / _targets.protein).clamp(0.0, 1.0);
    final carbPct    = (totals.carbs    / _targets.carbs).clamp(0.0, 1.0);
    final fatPct     = (totals.fat      / _targets.fat).clamp(0.0, 1.0);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateRow(),
            const SizedBox(height: 4),
            _buildPieChart(totals),
            const SizedBox(height: 20),
            _buildGoalHeader(isMobile),
            const SizedBox(height: 15),
            NutrientBar(
              label: '熱量 (Calories)',
              color: const Color(0xFFE96A60),
              percentage: calPct,
            ),
            const SizedBox(height: 15),
            NutrientBar(
              label: '蛋白質 (Protein)',
              color: const Color.fromARGB(255, 117, 181, 233),
              percentage: proteinPct,
            ),
            const SizedBox(height: 15),
            NutrientBar(
              label: '碳水化合物 (Carbs)',
              color: const Color.fromARGB(255, 132, 202, 206),
              percentage: carbPct,
            ),
            const SizedBox(height: 15),
            NutrientBar(
              label: '脂肪 (Fat)',
              color: const Color.fromARGB(255, 245, 190, 118),
              percentage: fatPct,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRow() {
    final d = _selectedDate;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}',
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        IconButton(
          icon: Icon(Icons.calendar_month_outlined, color: Colors.grey[700]),
          onPressed: _pickDate,
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(now.year - 5, now.month, now.day),
      lastDate: now,
    );
    if (picked != null && picked != _selectedDate && mounted) {
      setState(() {
        _selectedDate = picked;
        _isLoading    = true;
      });
      _listenToFirebaseData();
    }
  }

  Widget _buildPieChart(DailyTotals totals) {
    final macroTotal = totals.macroCalories;
    final empty      = macroTotal == 0;

    return Center(
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
                    color: const Color.fromARGB(255, 117, 181, 233),
                    value: empty ? 0 : totals.proteinCalorieFraction * 100,
                    radius: 30,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    color: const Color.fromARGB(255, 132, 202, 206),
                    value: empty ? 0 : totals.carbCalorieFraction * 100,
                    radius: 30,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    color: const Color.fromARGB(255, 245, 190, 118),
                    value: empty ? 0 : totals.fatCalorieFraction * 100,
                    radius: 30,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    color: Colors.grey[200],
                    value: empty ? 100 : 0,
                    radius: 30,
                    showTitle: false,
                  ),
                ],
              ),
            ),
            // 中心文字
            if (empty)
              Text('尚未攝取\n(0%)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700], fontSize: 14))
            else
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('蛋白質: ${(totals.proteinCalorieFraction * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12)),
                  Text('碳水: ${(totals.carbCalorieFraction * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12)),
                  Text('脂肪: ${(totals.fatCalorieFraction * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalHeader(bool isMobile) {
    const title = Text(
      '成人每日建議營養攝取量',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    );
    const tooltip = InfoTooltip(
      message: '進度條將依據您的個人資料\n計算每日的營養攝取目標，\n並顯示目前各類的攝取達成率。',
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [title, tooltip]),
          if (!_isGoalSet) ...[
            const SizedBox(height: 8),
            _buildSetGoalButton(),
          ],
        ],
      );
    }

    return Row(
      children: [
        title,
        tooltip,
        const Spacer(),
        if (!_isGoalSet) _buildSetGoalButton(),
      ],
    );
  }

  Widget _buildSetGoalButton() {
    return TextButton(
      onPressed: _navigateToSettings,
      style: ButtonStyle(
        padding: WidgetStateProperty.all(EdgeInsets.zero),
        minimumSize: WidgetStateProperty.all(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.pressed)
              ? const Color(0xFF7A9C99)
              : const Color(0xFFA5C5C2);
        }),
      ),
      child: const Text(
        '> 設定完整健康目標以查看報告',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ── 右欄（今日紀錄列表）──────────────────────────────────────────────────────

  Widget _buildRightColumn() {
    return DailyFoodList(
      isLoading: _isLoading,
      foodList:  _foodList,
      onTapItem: (item) => FoodEditDialog.show(
        context,
        item:         item,
        selectedDate: _selectedDate,
      ),
      onDeleteItem: (item) => ConfirmDeleteDialog.show(context, item),
    );
  }
}