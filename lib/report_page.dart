// report_page.dart
// 週報 / 月報 / 自訂報告頁面
// 結構：ReportLogic（純資料）+ ReportPage（純 UI，TabBar + RWD + PDF 匯出）

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
// import 'dart:html' as html;

// 🟢 跨平台支援 (完美融合 HEAD 的存檔邏輯)
import 'dart:html' as html;
import 'package:flutter/foundation.dart'; // 引入 kIsWeb 判斷
import 'dart:io'; // 給手機端存檔用
import 'package:path_provider/path_provider.dart'; // 取得手機路徑
import 'package:share_plus/share_plus.dart'; // 呼叫手機的原生分享/存檔
import '../models.dart';
import '../home/nutrition_helpers.dart';

// ════════════════════════════════════════════════════════════════════════════
// 報表類型
// ════════════════════════════════════════════════════════════════════════════

enum ReportType { weekly, monthly, custom }

// ════════════════════════════════════════════════════════════════════════════
// 資料層：ReportLogic
// ════════════════════════════════════════════════════════════════════════════
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

  const ReportData({
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

class ReportLogic {
  ReportLogic({required this.userId, DateTime? initialDate})
    : _referenceDate = initialDate ?? DateTime.now();
  final String userId;
  DateTime? _referenceDate;
  ReportType reportType = ReportType.weekly;
  DateTime? customStart;
  DateTime? customEnd;

  bool isLoading = true;
  ReportData? reportData;
  List<FoodItem> foodList = [];

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
    isLoading = true;

    final now = DateTime.now();
    late DateTime start, end;

    switch (reportType) {
      case ReportType.weekly:
        start = _weekStart(referenceDate);
        end = _weekEnd(referenceDate);
        break;
      case ReportType.monthly:
        start = DateTime(referenceDate.year, referenceDate.month, 1);
        end = DateTime(referenceDate.year, referenceDate.month + 1, 0);
        break;
      case ReportType.custom:
        start = customStart ?? DateTime(now.year, now.month, now.day - 7);
        end = customEnd ?? now;
        break;
    }

    // 🔒 妳寫的黃金防線：定死時分秒，消除任何重新整理網頁時產生的微秒差！
    final DateTime finalStartDate = DateTime(start.year, start.month, start.day, 0, 0, 0);
    final DateTime finalEndDate = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

    final totalDays = finalEndDate.difference(finalStartDate).inDays + 1;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('analysis_records')
          .where('created_at', isGreaterThanOrEqualTo: finalStartDate)
          .where('created_at', isLessThanOrEqualTo: finalEndDate)
          .orderBy('created_at', descending: false)
          .get();

      final List<FoodItem> foods = [];
      final Map<DateTime, double> dailyCals = {};
      double tCal = 0, tP = 0, tC = 0, tF = 0, tW = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final ts = data['created_at'] as Timestamp?;
        if (ts == null) continue;
        final time = ts.toDate();
        final dateKey = DateTime(time.year, time.month, time.day);

        // 讀 total_* 欄位（與第一份邏輯一致）
        double mCal = parseToDouble(data['total_calories']);
        double mP = parseToDouble(data['total_protein']);
        double mC = parseToDouble(data['total_carbs']);
        double mF = parseToDouble(data['total_fat']);
        double mW = parseToDouble(data['total_weight']);

        // 若 total_* 為 0，回退到撈食材子集合計算
        if (mCal == 0) {
          try {
            final ingSnap = await doc.reference.collection('ingredients').get();
            final List<Ingredient> ingList = [];
            for (final ing in ingSnap.docs) {
              final d = ing.data();
              final g = parseToDouble(d['重量(g)']);
              final cal = parseToDouble(d['熱量(kcal)']);
              final p = parseToDouble(d['蛋白質(g)']);
              final c = parseToDouble(d['碳水化合物(g)']);
              final f = parseToDouble(d['脂肪(g)']);
              mCal += cal;
              mP += p;
              mC += c;
              mF += f;
              mW += g;
              ingList.add(
                Ingredient(
                  id: ing.id,
                  name: d['食材名'] ?? '未知食材',
                  grams: g,
                  calories: cal,
                  carbs: c,
                  protein: p,
                  fat: f,
                ),
              );
            }
            // 附帶食材清單（PDF 匯出需要）
            foods.add(
              _buildFoodItem(doc, data, time, mCal, mP, mC, mF, mW, ingList),
            );
            dailyCals[dateKey] = (dailyCals[dateKey] ?? 0) + mCal;
            tCal += mCal;
            tP += mP;
            tC += mC;
            tF += mF;
            tW += mW;
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
            ingList.add(
              Ingredient(
                id: ing.id,
                name: d['食材名'] ?? '未知食材',
                grams: parseToDouble(d['重量(g)']),
                calories: parseToDouble(d['熱量(kcal)']),
                carbs: parseToDouble(d['碳水化合物(g)']),
                protein: parseToDouble(d['蛋白質(g)']),
                fat: parseToDouble(d['脂肪(g)']),
              ),
            );
          }
        } catch (e) {
          debugPrint('撈取食材錯誤: $e');
        }

        dailyCals[dateKey] = (dailyCals[dateKey] ?? 0) + mCal;
        tCal += mCal;
        tP += mP;
        tC += mC;
        tF += mF;
        tW += mW;
        foods.add(
          _buildFoodItem(doc, data, time, mCal, mP, mC, mF, mW, ingList),
        );
      }

      final recorded = dailyCals.length;
      final double avgCal = tCal / totalDays;

      // 🔐 經由時分秒對齊後，產生具備完全確定性的快取身份證 (cacheId)
      final String reportTypeName = reportType == ReportType.weekly 
          ? 'weekly' 
          : (reportType == ReportType.monthly ? 'monthly' : 'custom');
      final String dateStringKey = "${finalStartDate.year}${finalStartDate.month}${finalStartDate.day}_${finalEndDate.year}${finalEndDate.month}${finalEndDate.day}";
      final String cacheId = "${userId}_${reportTypeName}_${dateStringKey}_${foods.length}_${tCal.toStringAsFixed(0)}";      
      String aiText = "";

      try {
        // 先去 Firebase 檢查這份舊報告存在與否
        DocumentSnapshot cachedDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('saved_reports')
            .doc(cacheId)
            .get();

        if (cachedDoc.exists && cachedDoc.data() != null) {
          aiText = (cachedDoc.data() as Map<String, dynamic>)['content'] ?? "";
          print("🎯 快取完美命中！直接讀取舊報告 A，重整不再消耗 API 額度。");
        }
      } catch (e) {
        print("讀取舊報告快取失敗: $e");
      }

      // 如果 Firebase 裡面沒存過，或者是全新數據
      if (aiText.isEmpty) {
        print("🤖 [數據更新/首次生成] 正在呼叫 Gemini API 生成全新飲食建議...");
        aiText = await _generateFeedback(
          avgCal: avgCal,
          totalDaysInRange: totalDays.toDouble(),
          foods: foods,
        );

        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('saved_reports')
              .doc(cacheId)
              .set({
            'content': aiText,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          print("💾 報告 A 已安全在 Firebase 快取鎖定！");
        } catch (e) {
          print("寫入 Firebase 備份失敗: $e");
        }
      }

      reportData = ReportData(
        period: dateRangeText,
        totalCalories: tCal,
        totalProtein: tP,
        totalCarbs: tC,
        totalFat: tF,
        totalMeals: foods.length,
        totalWeight: tW,
        dailyAverages: {
          'protein': recorded > 0 ? tP / recorded : 0,
          'carbs': recorded > 0 ? tC / recorded : 0,
          'fat': recorded > 0 ? tF / recorded : 0,
        },
        topCalorieDays: dailyCals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)),
        aiFeedback: aiText, // 使用經過快取檢查的 aiText 成果
      );
      foodList = foods;
    } catch (e) {
      debugPrint('ReportLogic.load 錯誤: $e');
    }

    isLoading = false;
  }

  FoodItem _buildFoodItem(
    QueryDocumentSnapshot doc,
    Map<String, dynamic> data,
    DateTime time,
    double mCal,
    double mP,
    double mC,
    double mF,
    double mW,
    List<Ingredient> ingredients,
  ) {
    final mealType = (data['meal_type'] ?? '').toString().isNotEmpty
        ? data['meal_type'].toString()
        : mealTypeByTime(time);

    return FoodItem(
      reference: doc.reference,
      id: doc.id,
      name: data['食物名'] ?? '未命名',
      calories: '${mCal.toStringAsFixed(0)} 大卡',
      imagePath: data['圖片_base64'] ?? data['圖片網址'] ?? '',
      grams: mW.toStringAsFixed(1),
      protein: mP.toStringAsFixed(1),
      carbs: mC.toStringAsFixed(1),
      fat: mF.toStringAsFixed(1),
      ingredients: ingredients,
      remark: data['備註'] ?? '',
      aiSuggestion: data['AI分析建議'] ?? '',
      mealType: mealType,
      createdAt: time,
    );
  }

  // ── AI 建議（Gemini API）─────────────────────────────────────────────────────

  Future<String> _generateFeedback({
    required double avgCal,
    required double totalDaysInRange,
    required List<FoodItem> foods,
  }) async {
    if (foods.isEmpty) {
      return '目前尚無數據喔！\n開始記錄餐點，AI 將為您分析飲食趨勢！';
    }

    // 把每一餐轉成結構化文字
    final mealsText = StringBuffer();
    for (final food in foods) {
      final dateStr = food.createdAt != null
          ? '${food.createdAt!.year}/${food.createdAt!.month}/${food.createdAt!.day} '
                '${food.createdAt!.hour}:${food.createdAt!.minute.toString().padLeft(2, '0')}'
          : '未知時間';
      final ingNames = food.ingredients
          .where((i) => !i.isDeleted)
          .map((i) => i.name)
          .join(' ');
      mealsText.writeln(
        '- $dateStr: ${food.name}, 熱量 ${food.calories}, '
        '蛋: ${food.protein}g, 碳: ${food.carbs}g, 脂: ${food.fat}g. '
        '食材: ${ingNames.isNotEmpty ? ingNames : '無詳細記錄'}',
      );
    }

    final prompt = """
    你是一位親切、專業的台灣臨床營養師。請根據以下使用者在這段期間的飲食數據，生成繁體中文的專業飲食分析與改善建議。

    【飲食數據統計】
    - 統計天數：${totalDaysInRange.toInt()} 天
    - 總餐數：${foods.length} 餐
    - 每日平均攝取熱量：${avgCal.toStringAsFixed(0)} kcal

    【詳細飲食明細】
    ${mealsText.toString()}

    【專業評估依據（台灣衛福部國健署標準）】
    請嚴格參照台灣「每日飲食指南」與「我的餐盤」核心原則來審視上述明細：
    1. 三大營養素均衡比例：標準為蛋白質 10-20%、脂質 20-30%、醣類（碳水化合物） 50-60%。
    2. 六大類食物均衡度：檢視是否滿足「每天早晚一杯奶、每餐水果拳頭大、菜比水果多一點、飯跟蔬菜一樣多、豆魚蛋肉一掌心、堅果種子一茶匙」的口訣。特別留意台灣人極易缺乏乳品類與堅果種子類。

    核心指令：
    請直接根據上述數據與台灣官方標準，給出 4 點「精準、具體、可操作」的建議。
    請嚴格遵守以下格式規範，不要包含任何前後言、不要開頭自我介紹、不要結尾客套話。
    每點的標題與內容請務必「分行」分開，嚴格依照下方格式輸出：

    1. 熱量評估：
    [請用1到2句話評估平均熱量是否合適，並說出為什麼]

    2. 營養比例：
    [請用1到2句話指出三大營養素比例與台灣官方健康標準對比的優缺點]

    3. 飲食多樣性：
    [請依據我的餐盤原則，用1到2句話指出缺乏哪大類食材(如乳品、堅果或蔬果)或哪類吃太多]

    4. 行動指南：
    [請結合「我的餐盤」口訣，給出一個明天就能開始做的具體飲食調整動作]

    備註：
    - 每個項目（包含標題與內容）之間請空一行，確保排版清晰。
    - 語氣要溫柔、口語化且專業（多用「您」、「建議您可以嘗試...」）。
    - 整體總字數控制在 250 字以內，絕對不要冗長。
    """;

    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      final model = GenerativeModel(
        model: 'gemini-2.5-flash', 
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.0, // 鎖死最嚴謹輸出
        ),
      );
      final res = await model.generateContent([Content.text(prompt)]);
      return res.text ?? '無法取得 AI 建議';
    } catch (e) {
      debugPrint('呼叫 Gemini API 失敗: $e');
      return '暫時無法取得 AI 建議，請稍後再試。';
    }
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

  final String userId;
  final DateTime? initialReferenceDate;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final ReportLogic _logic;

  static const double _spacing = 16.0;
  static const Color _teal = Color(0xFF9DC6C2);

  // ── 生命週期 ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _logic = ReportLogic(
      userId: widget.userId,
      initialDate: widget.initialReferenceDate,
    );
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
        lastDate: DateTime.now(),
      );
      if (range != null) {
        _logic.customStart = range.start;
        _logic.customEnd = range.end;
        _reload();
      }
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: _logic.referenceDate,
        firstDate: DateTime(DateTime.now().year - 5),
        lastDate: DateTime.now(),
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
      const SnackBar(
        content: Text('正在生成完整營養報告...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final pdf = pw.Document();
      final chineseFont = await PdfGoogleFonts.notoSansTCRegular();
      final chineseFontBold = await PdfGoogleFonts.notoSansTCBold();

      const black = PdfColors.black;
      const headerTeal = PdfColor.fromInt(0xff9dc6c2);
      const bgLight = PdfColor.fromInt(0xfff0f5f2);

      final feedback = _logic.reportData?.aiFeedback ?? '目前尚無數據';
      final cleanFeedback = feedback
          .replaceAll(
            RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9\s，。！、：\[\]\(\)\.\-\n]'),
            '',
          )
          .trim();
      final isWarning = feedback.contains('偏低') || feedback.contains('不佳');
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
              if (res.statusCode == 200)
                imageProvider = pw.MemoryImage(res.bodyBytes);
            }
          } catch (e) {
            debugPrint('PDF圖片失敗: $e');
          }
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
                width: 35,
                height: 35,
                margin: const pw.EdgeInsets.only(right: 8),
                child: imageProvider != null
                    ? pw.Image(imageProvider, fit: pw.BoxFit.cover)
                    : pw.Container(color: PdfColors.grey300),
              ),
              pw.Text(
                meal.name,
                style: pw.TextStyle(font: chineseFontBold, fontSize: 11),
              ),
            ],
          ),
          pw.Text(
            ingredientsStr,
            style: pw.TextStyle(font: chineseFontBold, fontSize: 10),
            textAlign: pw.TextAlign.center,
          ),
          pw.Text(
            meal.calories,
            style: pw.TextStyle(font: chineseFontBold, fontSize: 10),
          ),
        ]);
      }

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(
            base: chineseFont,
            bold: chineseFontBold,
          ),
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
                        border: pw.Border(
                          bottom: pw.BorderSide(color: black, width: 2.5),
                        ),
                      ),
                      child: pw.Text(
                        '營養報告',
                        style: pw.TextStyle(
                          font: chineseFontBold,
                          fontSize: 26,
                          color: black,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 30),
                    pw.Text(
                      ' ■ AI 飲食分析建議',
                      style: pw.TextStyle(
                        font: chineseFontBold,
                        fontSize: 18,
                        color: black,
                      ),
                    ),
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
                        children: cleanFeedback
                            .split('\n')
                            .map(
                              (line) => pw.Padding(
                                padding: const pw.EdgeInsets.only(bottom: 4),
                                child: pw.Text(
                                  line.trim(),
                                  textAlign: pw.TextAlign.left,
                                  style: pw.TextStyle(
                                    font: chineseFontBold,
                                    fontSize: 15,
                                    height: 1.4,
                                    color: feedbackColor,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    pw.SizedBox(height: 40),
                    pw.Text(
                      ' ■ 詳細餐點紀錄',
                      style: pw.TextStyle(
                        font: chineseFontBold,
                        fontSize: 18,
                        color: black,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.TableHelper.fromTextArray(
                      border: pw.TableBorder.all(color: black, width: 1),
                      headerDecoration: const pw.BoxDecoration(
                        color: headerTeal,
                      ),
                      headerStyle: pw.TextStyle(
                        font: chineseFontBold,
                        fontSize: 12,
                        color: black,
                      ),
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
        ),
      );

      final bytes = await pdf.save();
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', '營養報告.pdf')
        ..click();
      html.Url.revokeObjectUrl(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('營養報告成功匯出！'),
            backgroundColor: Colors.green,
          ),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('營養報告'),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.file_download,
              color: Colors.white,
              size: 28,
            ),
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
                      child: isMobile ? _mobileLayout() : _desktopLayout(),
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
            child: Column(
              children: [
                _avg(),
                const SizedBox(height: _spacing),
                _topThree(),
              ],
            ),
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
              const Text(
                '營養摘要',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: _onDateRangeTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _teal.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _logic.dateRangeText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_calendar, size: 14, color: _teal),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _summaryItem(
                  '總餐數',
                  '${d?.totalMeals ?? 0}',
                  Icons.restaurant,
                  Colors.deepPurple,
                ),
              ),
              Expanded(
                child: _summaryItem(
                  '總重量',
                  '${(d?.totalWeight ?? 0).toStringAsFixed(1)} g',
                  Icons.fitness_center,
                  Colors.green,
                ),
              ),
              Expanded(
                child: _summaryItem(
                  '總熱量',
                  '${(d?.totalCalories ?? 0).toStringAsFixed(0)} kcal',
                  Icons.local_fire_department,
                  Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _summaryItem(
                  '蛋白質',
                  '${(d?.totalProtein ?? 0).toStringAsFixed(1)} g',
                  Icons.egg,
                  const Color(0xFF75B5E9),
                ),
              ),
              Expanded(
                child: _summaryItem(
                  '碳水',
                  '${(d?.totalCarbs ?? 0).toStringAsFixed(1)} g',
                  Icons.water_drop,
                  const Color(0xFF84CACE),
                ),
              ),
              Expanded(
                child: _summaryItem(
                  '脂質',
                  '${(d?.totalFat ?? 0).toStringAsFixed(1)} g',
                  Icons.opacity,
                  const Color(0xFFF5BE76),
                ),
              ),
            ],
          ),
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
          const Text(
            '每日平均攝取',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Divider(height: 22),
          Row(
            children: [
              _avgColumn(
                '${(avgs['protein'] ?? 0).toStringAsFixed(1)} g',
                '蛋白質',
                const Color(0xFF75B5E9),
              ),
              _avgColumn(
                '${(avgs['carbs'] ?? 0).toStringAsFixed(1)} g',
                '碳水',
                const Color(0xFF84CACE),
              ),
              _avgColumn(
                '${(avgs['fat'] ?? 0).toStringAsFixed(1)} g',
                '脂質',
                const Color(0xFFF5BE76),
              ),
            ],
          ),
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

    const rankColors = [
      Color(0xFFE96A60),
      Color(0xFFF5BE76),
      Color(0xFFA5C5C2),
    ];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '熱量排行 Top 3',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 40),
          if (top.isEmpty)
            const Center(child: Text('目前尚無紀錄喔！'))
          else
            ...top.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: rankColors[e.key],
                      child: Text(
                        '${e.key + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.value.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.teal[600], size: 18),
              const SizedBox(width: 8),
              const Text(
                'AI 飲食建議',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D4F4B),
                ),
              ),
            ],
          ),
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
          const Text(
            '餐點紀錄',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
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
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      );

  Widget _avgColumn(String value, String label, Color color) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );

  Widget _foodRow(FoodItem item) => Row(
    children: [
      _foodImage(item.imagePath, item.mealType),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          item.name,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Text(
        item.calories,
        style: TextStyle(
          fontSize: 15,
          color: Colors.grey[600],
          fontWeight: FontWeight.bold,
        ),
      ),
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
          child: Image.memory(
            base64Decode(b64),
            fit: BoxFit.cover,
            width: 50,
            height: 50,
            errorBuilder: (_, __, ___) => _placeholder(mealType),
          ),
        );
      } else if (path.startsWith('http')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            path,
            fit: BoxFit.cover,
            width: 50,
            height: 50,
            errorBuilder: (_, __, ___) => _placeholder(mealType),
          ),
        );
      }
    } catch (e) {
      debugPrint('圖片顯示錯誤: $e');
    }
    return _placeholder(mealType);
  }

  Widget _placeholder(String mealType) {
    final color = _mealColor(mealType);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(_mealIcon(mealType), color: color, size: 20),
    );
  }
  static IconData _mealIcon(String t) {
    switch (t) {
      case '早餐':
        return Icons.wb_twilight;
      case '午餐':
        return Icons.wb_sunny;
      case '晚餐':
        return Icons.nights_stay;
      default:
        return Icons.cookie;
    }
  }

  static Color _mealColor(String t) {
    switch (t) {
      case '早餐':
        return Colors.amber;
      case '午餐':
        return Colors.orange;
      case '晚餐':
        return Colors.indigoAccent;
      default:
        return Colors.pinkAccent;
    }
  }
}