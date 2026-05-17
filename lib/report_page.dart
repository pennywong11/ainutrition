// report_page.dart
// 週報 / 月報 / 自訂報告頁面
// 結構：ReportLogic（純資料）+ ReportPage（純 UI，TabBar + RWD + PDF 匯出）

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:convert';
// Web-only 'dart:html' removed; use printing package for downloads

import '../models.dart';
import 'home/nutrition_helpers.dart';

// ════════════════════════════════════════════════════════════════════════════
// 報表類型
// ════════════════════════════════════════════════════════════════════════════

enum ReportType { weekly, monthly, custom }

// ════════════════════════════════════════════════════════════════════════════
// 資料層：ReportLogic
// ════════════════════════════════════════════════════════════════════════════

class ReportLogic {
  ReportLogic({required this.userId, DateTime? initialDate})
      : _referenceDate = initialDate ?? DateTime.now();

  final String  userId;
  DateTime?     _referenceDate;
  ReportType    reportType  = ReportType.weekly;
  DateTime?     customStart;
  DateTime?     customEnd;

  bool          isLoading   = true;
  ReportData?   reportData;
  List<FoodItem> foodList   = [];

  // ── getter / setter ────────────────────────────────────────────────────────

  DateTime get referenceDate => _referenceDate ?? DateTime.now();
  set referenceDate(DateTime d) => _referenceDate = d;

  String get dateRangeText {
    switch (reportType) {
      case ReportType.weekly:
        return '${_fmt(_weekStart(referenceDate))} - ${_fmt(_weekEnd(referenceDate))}';
      case ReportType.monthly:
        return '${referenceDate.year}/${referenceDate.month.toString().padLeft(2, '0')}';
      case ReportType.custom:
        return (customStart != null && customEnd != null)
            ? '${_fmt(customStart!)} - ${_fmt(customEnd!)}'
            : '自訂範圍';
    }
  }

  // ── 資料載入 ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    debugPrint('userId: "$userId"');
    isLoading = true;

    final now = DateTime.now();
    late DateTime start, end;

    switch (reportType) {
      case ReportType.weekly:
        start = _weekStart(referenceDate);
        end   = _weekEnd(referenceDate);
        break;
      case ReportType.monthly:
        start = DateTime(referenceDate.year, referenceDate.month, 1);
        end   = DateTime(referenceDate.year, referenceDate.month + 1, 0);
        break;
      case ReportType.custom:
        start = customStart ?? DateTime(now.year, now.month, now.day - 7);
        end   = customEnd   ?? now;
        break;
    }

    start = DateTime(start.year, start.month, start.day, 0, 0, 0);
    end   = DateTime(end.year,   end.month,   end.day,   23, 59, 59, 999);

    final totalDays = end.difference(start).inDays + 1;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('analysis_records')
          .where('created_at', isGreaterThanOrEqualTo: start)
          .where('created_at', isLessThanOrEqualTo: end)
          .orderBy('created_at', descending: false)
          .get();

      final List<FoodItem>        foods     = [];
      final Map<DateTime, double> dailyCals = {};
      double tCal = 0, tP = 0, tC = 0, tF = 0, tW = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final ts   = data['created_at'] as Timestamp?;
        if (ts == null) continue;
        final time    = ts.toDate();
        final dateKey = DateTime(time.year, time.month, time.day);

        // 讀 total_* 欄位（與第一份邏輯一致）
        double mCal = parseToDouble(data['total_calories']);
        double mP   = parseToDouble(data['total_protein']);
        double mC   = parseToDouble(data['total_carbs']);
        double mF   = parseToDouble(data['total_fat']);
        double mW   = parseToDouble(data['total_weight']);

        // 若 total_* 為 0，回退到撈食材子集合計算
        if (mCal == 0) {
          try {
            final ingSnap = await doc.reference.collection('ingredients').get();
            final List<Ingredient> ingList = [];
            for (final ing in ingSnap.docs) {
              final d = ing.data();
              final g   = parseToDouble(d['重量(g)']);
              final cal = parseToDouble(d['熱量(kcal)']);
              final p   = parseToDouble(d['蛋白質(g)']);
              final c   = parseToDouble(d['碳水化合物(g)']);
              final f   = parseToDouble(d['脂肪(g)']);
              mCal += cal; mP += p; mC += c; mF += f; mW += g;
              ingList.add(Ingredient(
                id: ing.id, name: d['食材名'] ?? '未知食材',
                grams: g, calories: cal, carbs: c, protein: p, fat: f,
              ));
            }
            // 附帶食材清單（PDF 匯出需要）
            foods.add(_buildFoodItem(doc, data, time, mCal, mP, mC, mF, mW, ingList));
            dailyCals[dateKey] = (dailyCals[dateKey] ?? 0) + mCal;
            tCal += mCal; tP += mP; tC += mC; tF += mF; tW += mW;
            continue;
          } catch (e) {
            debugPrint('撈取食材錯誤: $e');
          }
        }

        // 有 total_* 時也撈食材（PDF 匯出需要食材名稱）
        List<Ingredient> ingList = [];
        try {
          final ingSnap = await doc.reference.collection('ingredients').get();
          for (final ing in ingSnap.docs) {
            final d = ing.data();
            ingList.add(Ingredient(
              id: ing.id, name: d['食材名'] ?? '未知食材',
              grams:    parseToDouble(d['重量(g)']),
              calories: parseToDouble(d['熱量(kcal)']),
              carbs:    parseToDouble(d['碳水化合物(g)']),
              protein:  parseToDouble(d['蛋白質(g)']),
              fat:      parseToDouble(d['脂肪(g)']),
            ));
          }
        } catch (e) { debugPrint('撈取食材錯誤: $e'); }

        dailyCals[dateKey] = (dailyCals[dateKey] ?? 0) + mCal;
        tCal += mCal; tP += mP; tC += mC; tF += mF; tW += mW;
        foods.add(_buildFoodItem(doc, data, time, mCal, mP, mC, mF, mW, ingList));
      }

      final recorded = dailyCals.length;
      reportData = ReportData(
        period:        dateRangeText,
        totalCalories: tCal,
        totalProtein:  tP,
        totalCarbs:    tC,
        totalFat:      tF,
        totalMeals:    foods.length,
        totalWeight:   tW,
        dailyAverages: {
          'protein': recorded > 0 ? tP / recorded : 0,
          'carbs':   recorded > 0 ? tC / recorded : 0,
          'fat':     recorded > 0 ? tF / recorded : 0,
        },
        topCalorieDays: dailyCals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)),
        aiFeedback: _generateFeedback(
          tCal / totalDays, tP / totalDays, tC / totalDays, tF / totalDays),
      );
      foodList = foods;
      debugPrint('抓到 ${snap.docs.length} 筆，範圍: $start → $end');
    } catch (e) {
      debugPrint('ReportLogic.load 錯誤: $e');
    }

    isLoading = false;
  }

  FoodItem _buildFoodItem(
    QueryDocumentSnapshot doc,
    Map<String, dynamic>  data,
    DateTime              time,
    double mCal, double mP, double mC, double mF, double mW,
    List<Ingredient> ingredients,
  ) {
    final mealType = (data['meal_type'] ?? '').toString().isNotEmpty
        ? data['meal_type'].toString()
        : mealTypeByTime(time);

    return FoodItem(
      reference:    doc.reference,
      id:           doc.id,
      name:         data['食物名'] ?? '未命名',
      calories:     '${mCal.toStringAsFixed(0)} 大卡',
      imagePath:    data['圖片_base64'] ?? data['圖片網址'] ?? '',
      grams:        mW.toStringAsFixed(1),
      protein:      mP.toStringAsFixed(1),
      carbs:        mC.toStringAsFixed(1),
      fat:          mF.toStringAsFixed(1),
      ingredients:  ingredients,
      remark:       data['備註'] ?? '',
      aiSuggestion: data['AI分析建議'] ?? '',
      mealType:     mealType,
      createdAt:    time,
    );
  }

  // ── AI 建議 ────────────────────────────────────────────────────────────────

  String _generateFeedback(double avgCal, double p, double c, double f) {
    if (avgCal == 0) return '目前尚無數據喔！\n開始記錄餐點，AI 將為您分析飲食趨勢！';

    final buf = <String>[];

    if (avgCal > 2300) {
      buf.add('🚨 本期平均熱量攝取較高 (${avgCal.toStringAsFixed(0)} kcal)，建議控制精緻澱粉份量並增加活動量。');
    } else if (avgCal < 1200) {
      buf.add('🚨 平均攝取熱量偏低，請確保攝取充足能量以維持基礎代謝。');
    } else {
      buf.add('✅ 平均攝取熱量穩定 (${avgCal.toStringAsFixed(0)} kcal)，請繼續保持良好習慣！');
    }

    final total = (p * 4) + (c * 4) + (f * 9);
    if (total > 0) {
      if ((p * 4) / total < 0.15) buf.add('🥚 蛋白質比例稍低，可以多補充豆魚蛋肉類。');
      if ((c * 4) / total > 0.65) buf.add('🍚 碳水比例偏高，建議減少精緻糖類攝取。');
      if ((f * 9) / total > 0.35) buf.add('🥑 脂質比例較高，建議多採用清蒸或水煮。');
    }

    if (buf.length == 1) buf.add('🌟 您的飲食比例均衡，目前維持得非常好！');
    return buf.join('\n');
  }

  // ── 靜態輔助 ───────────────────────────────────────────────────────────────

  static DateTime _weekStart(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));
  static DateTime _weekEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day + (7 - d.weekday), 23, 59, 59);
  static String _fmt(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

// ════════════════════════════════════════════════════════════════════════════
// UI 層：ReportPage
// ════════════════════════════════════════════════════════════════════════════

class ReportPage extends StatefulWidget {
  const ReportPage({
    super.key,
    required this.userId,
    this.initialReferenceDate,
  });

  final String    userId;
  final DateTime? initialReferenceDate;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tabController;
  late final ReportLogic   _logic;

  static const double _spacing = 16.0;
  static const Color  _teal    = Color(0xFF9DC6C2);

  // ── 生命週期 ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _logic = ReportLogic(userId: widget.userId, initialDate: widget.initialReferenceDate);
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);
    _reload();
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  // ── 事件 ────────────────────────────────────────────────────────────────────

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _logic.reportType = ReportType.values[_tabController.index];
    _reload();
  }

  Future<void> _reload() async {
    await _logic.load();
    if (mounted) setState(() {});
  }

  Future<void> _onDateRangeTap() async {
    if (_logic.reportType == ReportType.custom) {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(DateTime.now().year - 1),
        lastDate:  DateTime.now(),
      );
      if (range != null) {
        _logic.customStart = range.start;
        _logic.customEnd   = range.end;
        _reload();
      }
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: _logic.referenceDate,
        firstDate:   DateTime(DateTime.now().year - 5),
        lastDate:    DateTime.now(),
      );
      if (picked != null) {
        _logic.referenceDate = picked;
        _reload();
      }
    }
  }

  // ── PDF 匯出 ─────────────────────────────────────────────────────────────────

  Future<void> _exportToPDF() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在生成完整營養報告...'), duration: Duration(seconds: 2)),
    );

    try {
      final pdf            = pw.Document();
      final chineseFont    = await PdfGoogleFonts.notoSansTCRegular();
      final chineseFontBold = await PdfGoogleFonts.notoSansTCBold();

      const black      = PdfColors.black;
      const headerTeal = PdfColor.fromInt(0xff9dc6c2);
      const bgLight    = PdfColor.fromInt(0xfff0f5f2);

      final feedback      = _logic.reportData?.aiFeedback ?? '目前尚無數據';
      final cleanFeedback = feedback
          .replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9\s，。！、：\[\]\(\)\.\-\n]'), '')
          .trim();
      final isWarning     = feedback.contains('偏低') || feedback.contains('不佳');
      final feedbackColor = isWarning ? PdfColors.red900 : PdfColors.green900;

      // 建立表格資料（含圖片）
      final List<List<dynamic>> tableData = [];
      for (final meal in _logic.foodList) {
        pw.ImageProvider? imageProvider;
        final path = meal.imagePath;
        if (path.isNotEmpty) {
          try {
            if (path.startsWith('data:image') ||
                (path.length > 1000 && !path.startsWith('http'))) {
              final b64 = path.contains(',') ? path.split(',').last : path;
              imageProvider = pw.MemoryImage(base64Decode(b64));
            } else if (path.startsWith('http')) {
              final res = await http.get(Uri.parse(path));
              if (res.statusCode == 200) imageProvider = pw.MemoryImage(res.bodyBytes);
            }
          } catch (e) { debugPrint('PDF圖片失敗: $e'); }
        }

        final ingredientsStr = meal.ingredients.isNotEmpty
            ? meal.ingredients
                .where((i) => !i.isDeleted)
                .map((i) => i.name)
                .join('、')
            : '無記錄';

        final ct = meal.createdAt!;
        tableData.add([
          pw.Text(
            '${ct.year}/${ct.month}/${ct.day}\n${ct.hour}:${ct.minute.toString().padLeft(2, '0')}',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: chineseFontBold, fontSize: 10),
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Container(
                width: 35, height: 35,
                margin: const pw.EdgeInsets.only(right: 8),
                child: imageProvider != null
                    ? pw.Image(imageProvider, fit: pw.BoxFit.cover)
                    : pw.Container(color: PdfColors.grey300),
              ),
              pw.Text(meal.name, style: pw.TextStyle(font: chineseFontBold, fontSize: 11)),
            ],
          ),
          pw.Text(ingredientsStr,
              style: pw.TextStyle(font: chineseFontBold, fontSize: 10),
              textAlign: pw.TextAlign.center),
          pw.Text(meal.calories,
              style: pw.TextStyle(font: chineseFontBold, fontSize: 10)),
        ]);
      }

      pdf.addPage(pw.MultiPage(
        theme: pw.ThemeData.withFont(base: chineseFont, bold: chineseFontBold),
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => [
          pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(
              color: bgLight,
              padding: const pw.EdgeInsets.all(35),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // 標題
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.only(bottom: 10),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: black, width: 2.5))),
                    child: pw.Text('營養報告',
                        style: pw.TextStyle(font: chineseFontBold, fontSize: 26, color: black)),
                  ),
                  pw.SizedBox(height: 30),
                  pw.Text(' ■ AI 飲食分析建議',
                      style: pw.TextStyle(font: chineseFontBold, fontSize: 18, color: black)),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(20),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(12),
                      border: pw.Border.all(color: black, width: 1.5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: cleanFeedback.split('\n').map((line) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Text(line.trim(),
                            textAlign: pw.TextAlign.left,
                            style: pw.TextStyle(
                                font: chineseFontBold, fontSize: 15,
                                height: 1.4, color: feedbackColor)),
                      )).toList(),
                    ),
                  ),
                  pw.SizedBox(height: 40),
                  pw.Text(' ■ 詳細餐點紀錄',
                      style: pw.TextStyle(font: chineseFontBold, fontSize: 18, color: black)),
                  pw.SizedBox(height: 12),
                  pw.TableHelper.fromTextArray(
                    border: pw.TableBorder.all(color: black, width: 1),
                    headerDecoration: const pw.BoxDecoration(color: headerTeal),
                    headerStyle: pw.TextStyle(font: chineseFontBold, fontSize: 12, color: black),
                    cellAlignment: pw.Alignment.center,
                    columnWidths: {
                      0: const pw.FixedColumnWidth(120),
                      1: const pw.FlexColumnWidth(1.75),
                      2: const pw.FlexColumnWidth(1.5),
                      3: const pw.FixedColumnWidth(70),
                    },
                    headers: ['時間', '餐點內容', '食材', '熱量'],
                    data: tableData,
                  ),
                ],
              ),
            ),
          ),
        ],
      ));

      final bytes = await pdf.save();
      // Use the printing package to handle sharing/saving the PDF across platforms
      await Printing.sharePdf(bytes: bytes, filename: '營養報告.pdf');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('營養報告成功匯出！'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('PDF 匯出錯誤: $e');
    }
  }

  // ── 建構 ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('營養報告'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download, color: Colors.white, size: 28),
            tooltip: '匯出 PDF 報告',
            onPressed: _exportToPDF,
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(child: Text('週報')),
                Tab(child: Text('月報')),
                Tab(child: Text('自訂')),
              ],
            ),
          ),
        ),
      ),
      body: _logic.isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 700;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: isMobile
                          ? _mobileLayout()
                          : _desktopLayout(),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ── 版面 ────────────────────────────────────────────────────────────────────

  Widget _mobileLayout() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _summary(),
      const SizedBox(height: _spacing),
      _avg(),
      const SizedBox(height: _spacing),
      _topThree(),
      const SizedBox(height: _spacing),
      _ai(),
      const SizedBox(height: _spacing),
      _list(),
    ],
  );

  Widget _desktopLayout() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _summary()),
          const SizedBox(width: _spacing),
          Expanded(
            child: Column(children: [
              _avg(),
              const SizedBox(height: _spacing),
              _topThree(),
            ]),
          ),
        ],
      ),
      const SizedBox(height: _spacing),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _ai()),
          const SizedBox(width: _spacing),
          Expanded(child: _list()),
        ],
      ),
    ],
  );

  // ── 區塊 builders ──────────────────────────────────────────────────────────

  /// 1. 營養摘要
  Widget _summary() {
    final d = _logic.reportData;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('營養摘要',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: _onDateRangeTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _teal.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Text(_logic.dateRangeText,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700])),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_calendar, size: 14, color: _teal),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _summaryItem('總餐數',  '${d?.totalMeals ?? 0}',                                   Icons.restaurant,            Colors.deepPurple)),
            Expanded(child: _summaryItem('總重量',  '${(d?.totalWeight   ?? 0).toStringAsFixed(1)} g',          Icons.fitness_center,        Colors.green)),
            Expanded(child: _summaryItem('總熱量',  '${(d?.totalCalories ?? 0).toStringAsFixed(0)} kcal',       Icons.local_fire_department, Colors.redAccent)),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _summaryItem('蛋白質', '${(d?.totalProtein ?? 0).toStringAsFixed(1)} g', Icons.egg,          const Color(0xFF75B5E9))),
            Expanded(child: _summaryItem('碳水',   '${(d?.totalCarbs   ?? 0).toStringAsFixed(1)} g', Icons.water_drop,   const Color(0xFF84CACE))),
            Expanded(child: _summaryItem('脂質',   '${(d?.totalFat     ?? 0).toStringAsFixed(1)} g', Icons.opacity,      const Color(0xFFF5BE76))),
          ]),
        ],
      ),
    );
  }

  /// 2. 每日平均
  Widget _avg() {
    final avgs = _logic.reportData?.dailyAverages ?? {};
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每日平均攝取',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Divider(height: 22),
          Row(children: [
            _avgColumn('${(avgs['protein'] ?? 0).toStringAsFixed(1)} g', '蛋白質', const Color(0xFF75B5E9)),
            _avgColumn('${(avgs['carbs']   ?? 0).toStringAsFixed(1)} g', '碳水',   const Color(0xFF84CACE)),
            _avgColumn('${(avgs['fat']     ?? 0).toStringAsFixed(1)} g', '脂質',   const Color(0xFFF5BE76)),
          ]),
        ],
      ),
    );
  }

  /// 3. 熱量排行 Top 3
  Widget _topThree() {
    final foods = List<FoodItem>.from(_logic.foodList)
      ..sort((a, b) {
        final ca = double.tryParse(a.calories.replaceAll(' 大卡', '')) ?? 0;
        final cb = double.tryParse(b.calories.replaceAll(' 大卡', '')) ?? 0;
        return cb.compareTo(ca);
      });
    final top = foods.take(3).toList();

    const rankColors = [Color(0xFFE96A60), Color(0xFFF5BE76), Color(0xFFA5C5C2)];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('熱量排行 Top 3',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Divider(height: 40),
          if (top.isEmpty)
            const Center(child: Text('目前尚無紀錄喔！'))
          else
            ...top.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: rankColors[e.key],
                  child: Text('${e.key + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.value.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            )),
        ],
      ),
    );
  }

  /// 4. AI 建議
  Widget _ai() {
    final feedback = _logic.reportData?.aiFeedback;
    return _card(
      color: const Color(0xFFF1F8F7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome, color: Colors.teal[600], size: 18),
            const SizedBox(width: 8),
            const Text('AI 飲食建議',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold,
                    color: Color(0xFF2D4F4B))),
          ]),
          const Divider(height: 30),
          Text(
            feedback ?? '分析中...',
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 5. 餐點紀錄
  Widget _list() {
    final foods = _logic.foodList;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('餐點紀錄',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Divider(height: 20),
          if (foods.isEmpty)
            const Center(child: Text('目前尚無紀錄喔！'))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: foods.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _foodRow(foods[i]),
            ),
        ],
      ),
    );
  }

  // ── 小型 Widget 輔助 ────────────────────────────────────────────────────────

  Widget _card({required Widget child, Color? color}) => Card(
    elevation: 4,
    color: color,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );

  Widget _summaryItem(String label, String value, IconData icon, Color color) =>
    Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 24),
      ),
      const SizedBox(height: 8),
      Text(value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          textAlign: TextAlign.center),
    ]);

  Widget _avgColumn(String value, String label, Color color) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]),
  );

  Widget _foodRow(FoodItem item) => Row(
    children: [
      _foodImage(item.imagePath, item.mealType),
      const SizedBox(width: 8),
      Expanded(
        child: Text(item.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis),
      ),
      Text(item.calories,
          style: TextStyle(fontSize: 15, color: Colors.grey[600], fontWeight: FontWeight.bold)),
    ],
  );

  Widget _foodImage(String path, String mealType) {
    if (path.isEmpty) return _placeholder(mealType);
    try {
      if (path.startsWith('data:image') ||
          (path.length > 1000 && !path.startsWith('http'))) {
        final b64 = path.contains(',') ? path.split(',').last : path;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(base64Decode(b64),
              fit: BoxFit.cover, width: 50, height: 50,
              errorBuilder: (_, __, ___) => _placeholder(mealType)),
        );
      } else if (path.startsWith('http')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(path,
              fit: BoxFit.cover, width: 50, height: 50,
              errorBuilder: (_, __, ___) => _placeholder(mealType)),
        );
      }
    } catch (e) { debugPrint('圖片顯示錯誤: $e'); }
    return _placeholder(mealType);
  }

  Widget _placeholder(String mealType) {
    final color = _mealColor(mealType);
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
          color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Icon(_mealIcon(mealType), color: color, size: 20),
    );
  }

  static IconData _mealIcon(String t) {
    switch (t) {
      case '早餐': return Icons.wb_twilight;
      case '午餐': return Icons.wb_sunny;
      case '晚餐': return Icons.nights_stay;
      default:    return Icons.cookie;
    }
  }

  static Color _mealColor(String t) {
    switch (t) {
      case '早餐': return Colors.amber;
      case '午餐': return Colors.orange;
      case '晚餐': return Colors.indigoAccent;
      default:    return Colors.pinkAccent;
    }
  }
}