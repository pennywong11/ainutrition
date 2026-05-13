// 匯入必要的函式庫
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:html' as html;

// --- 引用原本檔案中定義的資料模型 (如果你有獨立 Model 檔則可省略，否則必須保留) ---

// 每個"食材"的資料結構 (搬移至此以供報表使用)
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
    newIngredient.isDeleted = this.isDeleted;
    return newIngredient;
  }
}

// 每個"食物"的資料結構 (搬移至此以供報表列表顯示)
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
  DateTime? createdAt;

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

// 報表數據結構：定義"報表"需要顯示的總和數據
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

// ----------------------------------------------
// 週報月報頁面
// ----------------------------------------------

// 分類標籤：週報/月報/自訂範圍(在後面做切換)
enum ReportType { weekly, monthly, custom }

class ReportPage extends StatefulWidget {
  final String userId;
  final DateTime? initialReferenceDate;

  const ReportPage({
    super.key,
    required this.userId,
    this.initialReferenceDate,
  });

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  ReportType _selectedReportType = ReportType.weekly; // 預設為週報
  bool _isLoading = true; //是否正在跑(轉圈圈)
  ReportData? _reportData;
  List<FoodItem> _periodFoodList = []; // 用來裝這段時間的所有食物清單

  DateTime? _customStartDate;
  DateTime? _customEndDate;
  DateTime? _referenceDate;

  @override
  void initState() {
    super.initState();
    // 如果有傳入日期就用傳入的，否則用今天
    _referenceDate = widget.initialReferenceDate ?? DateTime.now();
    _loadReportData();
  }

  // 1. AI 建議生成邏輯(會根據這週/這月/這範圍所吃的熱量平均值去決定在此區顯示哪段文字)
  String _generateAIFeedback(double avgCal, double p, double c, double f) {
    if (avgCal == 0) return " 目前尚無數據喔！\n開始記錄餐點，AI 將為您分析飲食趨勢！";

    List<String> suggestions = [];

    if (avgCal > 2300) {
      suggestions.add(
        "🚨 本期平均熱量攝取較高 (${avgCal.toStringAsFixed(0)} kcal)，建議控制精緻澱粉份量並增加活動量。",
      );
    } else if (avgCal < 1200 && avgCal > 0) {
      suggestions.add("🚨 平均攝取熱量偏低，請確保攝取充足能量以維持基礎代謝。");
    } else {
      suggestions.add(
        "✅ 平均攝取熱量穩定 (${avgCal.toStringAsFixed(0)} kcal)，請繼續保持良好習慣！",
      );
    }
    // 根據營養學比例給予適當建議並顯示在對應畫面中
    double totalMacroCal = (p * 4) + (c * 4) + (f * 9);
    if (totalMacroCal > 0) {
      if ((p * 4) / totalMacroCal < 0.15)
        suggestions.add("🥚 蛋白質比例稍低，可以多補充豆魚蛋肉類。");
      if ((c * 4) / totalMacroCal > 0.65)
        suggestions.add("🍚 碳水比例偏高，建議減少精緻糖類攝取。");
      if ((f * 9) / totalMacroCal > 0.35)
        suggestions.add("🥑 脂質比例較高，建議多採用清蒸或水煮。");
    }

    if (suggestions.length == 1) suggestions.add("🌟 您的飲食比例均衡，目前維持得非常好！");
    return suggestions.join("\n");
  }

  // 2. 資料載入邏輯
  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    try {
      DateTime now = DateTime.now();
      DateTime startDate;
      DateTime endDate = now;
      // 計算"這張報表要從哪天抓取到哪天"的範圍
      // 週報：這週一至周日總共七天
      // 月報：這整個月
      // 自訂範圍：最短2天、最多6個月
      switch (_selectedReportType) {
        case ReportType.weekly:
          startDate = _getWeekStartDate(_referenceDate ?? now);
          endDate = _getWeekEndDate(_referenceDate ?? now);
          break;
        case ReportType.monthly:
          startDate = DateTime(_referenceDate!.year, _referenceDate!.month, 1);
          endDate = DateTime(
            _referenceDate!.year,
            _referenceDate!.month + 1,
            0,
          );
          break;
        case ReportType.custom:
          startDate =
              _customStartDate ?? DateTime(now.year, now.month, now.day - 7);
          endDate = _customEndDate ?? now;
          break;
      }

      startDate = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
      endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);

      // 到Firebase撈取資料
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('analysis_records')
          .where('created_at', isGreaterThanOrEqualTo: startDate)
          .where('created_at', isLessThanOrEqualTo: endDate)
          .orderBy('created_at', descending: false)
          .get();

      List<FoodItem> periodFoods = [];
      Map<DateTime, double> dailyCalories = {};
      double tCal = 0, tP = 0, tC = 0, tF = 0, tW = 0;

      for (var doc in snapshot.docs) {
        var data = doc.data();
        Timestamp? createdAt = data['created_at'];
        if (createdAt == null) continue;
        DateTime itemDate = createdAt.toDate();
        DateTime dateKey = DateTime(itemDate.year, itemDate.month, itemDate.day);
        
        // --- 核心修正：撈取該餐點子集合內的所有食材細節 ---
        List<Ingredient> ingredientsList = [];
        try {
          var ingredientSnapshot = await doc.reference.collection('ingredients').get();
          for (var ingDoc in ingredientSnapshot.docs) {
            var ingData = ingDoc.data();
            ingredientsList.add(
              Ingredient(
                id: ingDoc.id,
                name: ingData['食材名'] ?? '未知食材',
                grams: _parseToDouble(ingData['重量(g)']),
                calories: _parseToDouble(ingData['熱量(kcal)']),
                carbs: _parseToDouble(ingData['碳水化合物(g)']),
                protein: _parseToDouble(ingData['蛋白質(g)']),
                fat: _parseToDouble(ingData['脂肪(g)']),
              ),
            );
          }
        } catch (e) {
          print("撈取報表食材時出錯: $e");
        }

        double mCal = _parseToDouble(data['total_calories']);
        double mP = _parseToDouble(data['total_protein']);
        double mC = _parseToDouble(data['total_carbs']);
        double mF = _parseToDouble(data['total_fat']);
        double mW = _parseToDouble(data['total_weight']);
        dailyCalories[dateKey] = (dailyCalories[dateKey] ?? 0) + mCal;
        tCal += mCal;
        tP += mP;
        tC += mC;
        tF += mF;
        tW += mW;
        
        periodFoods.add(
          FoodItem(
            reference: doc.reference,
            id: doc.id,
            name: data['食物名'] ?? '未命名',
            calories: '${mCal.toStringAsFixed(0)} 大卡',
            imagePath: data['圖片_base64'] ?? data['圖片網址'] ?? '',
            grams: mW.toStringAsFixed(1),
            protein: mP.toStringAsFixed(1),
            carbs: mC.toStringAsFixed(1),
            fat: mF.toStringAsFixed(1),
            ingredients: ingredientsList,
            remark: data['備註'] ?? '',
            aiSuggestion: data['AI分析建議'] ?? '',
            mealType: data['meal_type'] ??'',
            createdAt: itemDate,
          ),
        );
      }

      int totalDaysInRange = endDate.difference(startDate).inDays + 1;
      int recordedDaysCount = dailyCalories.length;
      double avgCal = tCal / totalDaysInRange;

      _reportData = ReportData(
        period: _getDateRangeText(),
        totalCalories: tCal,
        totalProtein: tP,
        totalCarbs: tC,
        totalFat: tF,
        totalWeight: tW,
        totalMeals: periodFoods.length,
        dailyAverages: {
          'protein': recordedDaysCount > 0 ? tP / recordedDaysCount : 0,
          'carbs': recordedDaysCount > 0 ? tC / recordedDaysCount : 0,
          'fat': recordedDaysCount > 0 ? tF / recordedDaysCount : 0,
        },
        topCalorieDays: dailyCalories.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
        aiFeedback: _generateAIFeedback(avgCal, tP/totalDaysInRange, tC/totalDaysInRange, tF/totalDaysInRange),
      );
      setState(() {
        _periodFoodList = periodFoods;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportToPDF() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在生成完整營養報告...'), duration: Duration(seconds: 2)),
    );

    try {
      final pdf = pw.Document();
      final chineseFont = await PdfGoogleFonts.notoSansTCRegular();
      final chineseFontBold = await PdfGoogleFonts.notoSansTCBold();
      
      // 根據自訂範圍決定標題日期
      String dateRangeStr = "";
      // 判斷邏輯：如果自訂範圍不為空，就用自訂範圍；否則用單選日期
      if (_customStartDate != null && _customEndDate != null) {
        if (_customStartDate!.year == _customEndDate!.year) {
          dateRangeStr = "${_customStartDate!.year}/${_customStartDate!.month}/${_customStartDate!.day} - ${_customEndDate!.month}/${_customEndDate!.day}";
        } else {
          dateRangeStr = "${_customStartDate!.year}/${_customStartDate!.month}/${_customStartDate!.day} - ${_customEndDate!.year}/${_customEndDate!.month}/${_customEndDate!.day}";
        }
      } else {
        dateRangeStr = "${_referenceDate!.year}/${_referenceDate!.month}/${_referenceDate!.day}";
      }
      final String fileNameStr = dateRangeStr.replaceAll('/', '-');

      const black = PdfColors.black;
      const headerTeal = PdfColor.fromInt(0xff9dc6c2);
      const bgLight = PdfColor.fromInt(0xfff0f5f2);

      String feedback = _reportData?.aiFeedback ?? "目前尚無數據";
      String cleanFeedback = feedback.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9\s，。！、：\[\]\(\)\.\-\n]'), '').trim();
      bool isWarning = feedback.contains('偏低') || feedback.contains('不佳');
      PdfColor feedbackColor = isWarning ? PdfColors.red900 : PdfColors.green900;

      List<List<dynamic>> tableData = [];
      for (var meal in _periodFoodList) {
        pw.ImageProvider? imageProvider;
        if (meal.imagePath.isNotEmpty) {
          String path = meal.imagePath;
          try {
            if (path.startsWith('data:image') || (path.length > 1000 && !path.startsWith('http'))) {
              // 處理 Base64
              final base64String = path.contains(',') ? path.split(',').last : path;
              imageProvider = pw.MemoryImage(base64Decode(base64String));
            } else if (path.startsWith('http')) {
              // 處理網路圖片
              final response = await http.get(Uri.parse(path));
              if (response.statusCode == 200) imageProvider = pw.MemoryImage(response.bodyBytes);
            }
          } catch (e) { debugPrint("圖片失敗: $e"); }
        }

        String ingredientsStr = (meal.ingredients != null && meal.ingredients.isNotEmpty)
            ? meal.ingredients.where((ing) => !ing.isDeleted).map((ing) => ing.name).join('、') 
            : "無記錄";

        tableData.add([
          // 欄位 1: 時間 (加粗並置中)
          pw.Text(
            "${meal.createdAt!.year}/${meal.createdAt!.month}/${meal.createdAt!.day}\n${meal.createdAt!.hour}:${meal.createdAt!.minute.toString().padLeft(2, '0')}",
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: chineseFontBold, fontSize: 10)
          ),
          // 欄位 2: 餐點內容 (加粗並置中)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Container(width: 35, height: 35, margin: const pw.EdgeInsets.only(right: 8), child: imageProvider != null ? pw.Image(imageProvider, fit: pw.BoxFit.cover) : pw.Container(color: PdfColors.grey300)),
              pw.Text(meal.name, style: pw.TextStyle(font: chineseFontBold, fontSize: 11)),
            ],
          ),
          // 欄位 3: 食材 (加粗並置中)
          pw.Text(ingredientsStr, style: pw.TextStyle(font: chineseFontBold, fontSize: 10), textAlign: pw.TextAlign.center),        
          // 欄位 4: 熱量 (加粗並置中)
          pw.Text("${meal.calories}", style: pw.TextStyle(font: chineseFontBold, fontSize: 10)),
        ]);
      }

      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(base: chineseFont, bold: chineseFontBold),
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) => [
            pw.FullPage(
              ignoreMargins: true,
              child: pw.Container(
                color: bgLight,
                padding: const pw.EdgeInsets.all(35),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // --- 標題區 (延伸到全寬) ---
                    pw.Container(
                      width: double.infinity, padding: const pw.EdgeInsets.only(bottom: 10),
                      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: black, width: 2.5))),
                      child: pw.Text('營養報告', style: pw.TextStyle(font: chineseFontBold, fontSize: 26, color: black)),
                    ),
                    pw.SizedBox(height: 30),
                    pw.Text(' ■ AI 飲食分析建議', style: pw.TextStyle(font: chineseFontBold, fontSize: 18, color: black)),
                    pw.SizedBox(height: 12),
                    pw.Container(
                      width: double.infinity, padding: const pw.EdgeInsets.all(20),
                      decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(12), border: pw.Border.all(color: black, width: 1.5)),
                      // AI 建議左對齊修正
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start, 
                        children: cleanFeedback.split('\n').map((line) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 4),
                          child: pw.Text(line.trim(), textAlign: pw.TextAlign.left, style: pw.TextStyle(font: chineseFontBold, fontSize: 15, height: 1.4, color: feedbackColor)),
                        )).toList(),
                      ),
                    ),
                    pw.SizedBox(height: 40),
                    // --- 詳細餐點紀錄 (表格內容設定加粗與全面置中) ---
                    pw.Text(' ■ 詳細餐點紀錄', style: pw.TextStyle(font: chineseFontBold, fontSize: 18, color: black)),
                    pw.SizedBox(height: 12),
                    pw.TableHelper.fromTextArray(
                      context: context,
                      border: pw.TableBorder.all(color: black, width: 1),
                      headerDecoration: const pw.BoxDecoration(color: headerTeal),
                      headerStyle: pw.TextStyle(font: chineseFontBold, fontSize: 12, color: black),
                      // 設定表格內所有單元格內容置中
                      cellAlignment: pw.Alignment.center,
                      columnWidths: {0: const pw.FixedColumnWidth(120), 1: const pw.FlexColumnWidth(1.75), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FixedColumnWidth(70)},
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
      html.AnchorElement(href: url)..setAttribute("download", "營養報告.pdf")..click();
      html.Url.revokeObjectUrl(url);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('營養報告成功匯出！'), backgroundColor: Colors.green));
    } catch (e) { print(e); }
  }

  // --- UI Widget 區 (Summary, Cards 等) ---
  Widget _card1() => Card(
    elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('營養摘要', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            GestureDetector(
              onTap: _onDateRangeTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFF9DC6C2).withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF9DC6C2).withOpacity(0.3))),
                child: Row(children: [
                  Text(_getDateRangeText(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_calendar, size: 14, color: Color(0xFF9DC6C2)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _buildSummaryItem('總餐數', '${_reportData?.totalMeals ?? 0}', Icons.restaurant, Colors.deepPurple)),
            Expanded(child: _buildSummaryItem('總重量', '${_reportData?.totalWeight.toStringAsFixed(1) ?? "0.0"} g', Icons.fitness_center, Colors.green)),
            Expanded(child: _buildSummaryItem('總熱量', '${_reportData?.totalCalories.toStringAsFixed(0) ?? 0} kcal', Icons.local_fire_department, Colors.redAccent)),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _buildSummaryItem('蛋白質', '${_reportData?.totalProtein.toStringAsFixed(1) ?? "0.0"} g', Icons.egg, const Color(0xFF75B5E9))),
            Expanded(child: _buildSummaryItem('碳水', '${_reportData?.totalCarbs.toStringAsFixed(1) ?? "0.0"} g', Icons.water_drop, const Color(0xFF84CACE))),
            Expanded(child: _buildSummaryItem('脂質', '${_reportData?.totalFat.toStringAsFixed(1) ?? "0.0"} g', Icons.opacity, const Color(0xFFF5BE76))),
          ]),
        ],
      ),
    ),
  );

  Widget _card2() => Card(
    elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('每日平均攝取', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Divider(height: 22),
          Row(children: [
            _buildAvgColumn('${_reportData?.dailyAverages['protein']?.toStringAsFixed(1) ?? "0.0"} g', '蛋白質', const Color(0xFF75B5E9)),
            _buildAvgColumn('${_reportData?.dailyAverages['carbs']?.toStringAsFixed(1) ?? "0.0"} g', '碳水', const Color(0xFF84CACE)),
            _buildAvgColumn('${_reportData?.dailyAverages['fat']?.toStringAsFixed(1) ?? "0.0"} g', '脂質', const Color(0xFFF5BE76)),
          ]),
        ],
      ),
    ),
  );

  Widget _card3() => Card(
    elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('熱量排行 Top 3', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Divider(height: 40),
          if (_periodFoodList.isNotEmpty) ...[
            ...(() {
              List<FoodItem> topFoods = List.from(_periodFoodList);
              topFoods.sort((a, b) => (double.tryParse(b.calories.replaceAll(' 大卡', '')) ?? 0).compareTo(double.tryParse(a.calories.replaceAll(' 大卡', '')) ?? 0));
              return topFoods.take(3);
            })().toList().asMap().entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(children: [
                CircleAvatar(radius: 10, backgroundColor: [const Color(0xFFE96A60), const Color(0xFFF5BE76), const Color(0xFFA5C5C2)][entry.key], child: Text('${entry.key + 1}', style: const TextStyle(color: Colors.white, fontSize: 10))),
                const SizedBox(width: 8),
                Expanded(child: Text(entry.value.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              ]),
            )).toList(),
          ] else const Center(child: Text("目前尚無紀錄喔！")),
        ],
      ),
    ),
  );

  Widget _card4({required bool isMobile}) => Container(
    constraints: BoxConstraints(minHeight: isMobile ? 120 : 250),
    child: Card(
      elevation: 4, color: const Color(0xFFF1F8F7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.auto_awesome, color: Colors.teal[600], size: 18), const SizedBox(width: 8), const Text('AI 飲食建議', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF2D4F4B)))]),
          const Divider(height: 30),
          if (_reportData == null || _reportData!.totalCalories == 0)
            SizedBox(height: isMobile ? 60 : 78, child: Center(child: Text(_generateAIFeedback(0, 0, 0, 0), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, height: 1.5))))
          else
            Text(_reportData?.aiFeedback ?? "分析中...", style: const TextStyle(fontSize: 15, height: 1.5)),
        ]),
      ),
    ),
  );

  Widget _card5({required bool isMobile}) => Container(
    constraints: BoxConstraints(minHeight: isMobile ? 120 : 250),
    child: Card(
      elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('餐點紀錄', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Divider(height: 20),
          if (_periodFoodList.isEmpty)
            const Center(child: Text('目前尚無紀錄喔！'))
          else
            ..._periodFoodList.take(3).map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(children: [
                _buildFoodImage(item.imagePath, item.mealType),
                const SizedBox(width: 8),
                Expanded(child: Text(item.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                Text(item.calories, style: TextStyle(fontSize: 15, color: Colors.grey[600], fontWeight: FontWeight.bold)),
              ]),
            )),
        ]),
      ),
    ),
  );

  // --- 輔助函式與工具 ---

  Widget _buildSummaryItem(String l, String v, IconData i, Color c) => Column(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle), child: Icon(i, color: c, size: 24)), const SizedBox(height: 8), Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(l, style: TextStyle(fontSize: 12, color: Colors.grey[600]))]);

  Widget _buildAvgColumn(String v, String l, Color c) => Expanded(child: Column(children: [Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c)), Text(l, style: const TextStyle(fontSize: 12))]));

  Widget _buildFoodImage(String path, String mealType) {
    // 1. 如果路徑完全是空的，才顯示預設圖示
    if (path.isEmpty) {
      return _buildImagePlaceholder(mealType);
    }

    try {
      // 2. 判斷是否為 Base64 格式 (通常你拍的照片是這種)
      if (path.startsWith('data:image') || path.contains(',') || path.length > 100) {
        final base64String = path.contains(',') ? path.split(',').last : path;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            base64Decode(base64String),
            fit: BoxFit.cover,
            width: 50, // 稍微加大一點讓你看得更清楚
            height: 50,
            // 如果 Base64 解析失敗，還有一個保險方案顯示圖示
            errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(mealType),
          ),
        );
      } 
      // 3. 判斷是否為網路圖片
      else if (path.startsWith('http')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            path,
            fit: BoxFit.cover,
            width: 50,
            height: 50,
            errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(mealType),
          ),
        );
      }
    } catch (e) {
      debugPrint("UI圖片顯示錯誤: $e");
    }

    // 4. 最後的保險：顯示預設圖示
    return _buildImagePlaceholder(mealType);
  }

  Widget _buildImagePlaceholder(String t) => Container(width: 40, height: 40, decoration: BoxDecoration(color: _getMealColor(t).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(_getMealIcon(t), color: _getMealColor(t), size: 20));

  IconData _getMealIcon(String t) => t == '早餐' ? Icons.wb_twilight : (t == '午餐' ? Icons.wb_sunny : (t == '晚餐' ? Icons.nights_stay : Icons.cookie));
  Color _getMealColor(String t) => t == '早餐' ? Colors.amber : (t == '午餐' ? Colors.orange : (t == '晚餐' ? Colors.indigoAccent : Colors.pinkAccent));

  String _getDateRangeText() {
    DateTime now = DateTime.now();
    switch (_selectedReportType) {
      case ReportType.weekly: return '${_formatDate(_getWeekStartDate(_referenceDate ?? now))} - ${_formatDate(_getWeekEndDate(_referenceDate ?? now))}';
      case ReportType.monthly: return '${(_referenceDate ?? now).year}/${(_referenceDate ?? now).month.toString().padLeft(2, '0')}';
      case ReportType.custom: return (_customStartDate != null && _customEndDate != null) ? '${_formatDate(_customStartDate!)} - ${_formatDate(_customEndDate!)}' : '自訂範圍';
    }
  }

  DateTime _getWeekStartDate(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
  DateTime _getWeekEndDate(DateTime d) => DateTime(d.year, d.month, d.day + (7 - d.weekday), 23, 59, 59);
  String _formatDate(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  double _parseToDouble(dynamic v) => v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '0') ?? 0.0);

  Future<void> _onDateRangeTap() async {
    if (_selectedReportType == ReportType.custom) {
      DateTimeRange? r = await showDateRangePicker(context: context, firstDate: DateTime(DateTime.now().year, DateTime.now().month - 6), lastDate: DateTime.now());
      if (r != null) { setState(() { _customStartDate = r.start; _customEndDate = r.end; }); _loadReportData(); }
    } else {
      DateTime? p = await showDatePicker(context: context, initialDate: _referenceDate ?? DateTime.now(), firstDate: DateTime(DateTime.now().year - 1), lastDate: DateTime.now());
      if (p != null) { setState(() => _referenceDate = p); _loadReportData(); }
    }
  }

  Widget _buildReportTypeButton(String label, ReportType type, IconData icon) {
    bool isSelected = _selectedReportType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedReportType = type;
          if (type != ReportType.custom && _referenceDate == null) _referenceDate = DateTime.now();
        });
        _loadReportData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isSelected ? const Color(0xFF9DC6C2) : Colors.transparent, width: 3))),
        child: Row(children: [Icon(icon, size: 18, color: isSelected ? const Color(0xFF9DC6C2) : Colors.grey), const SizedBox(width: 4), Text(label, style: TextStyle(color: isSelected ? const Color(0xFF9DC6C2) : Colors.grey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF9DC6C2), elevation: 0,
        title: const Text('營養報告', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.file_download, color: Colors.white, size: 30), tooltip: '匯出 PDF 報告', onPressed: _exportToPDF), const SizedBox(width: 12)],
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(50), child: Container(color: Colors.white, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildReportTypeButton('週報', ReportType.weekly, Icons.calendar_view_week), _buildReportTypeButton('月報', ReportType.monthly, Icons.calendar_view_month), _buildReportTypeButton('自訂', ReportType.custom, Icons.edit_calendar)]))),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : LayoutBuilder(builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 700;
        return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (isMobile) ...[_card1(), const SizedBox(height: 16), _card2(), const SizedBox(height: 16), _card3(), const SizedBox(height: 16), _card4(isMobile: true), const SizedBox(height: 16), _card5(isMobile: true)]
          else ...[Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 1, child: _card1()), const SizedBox(width: 16), Expanded(flex: 1, child: Column(children: [_card2(), const SizedBox(height: 16), _card3()]))]), const SizedBox(height: 16), Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _card4(isMobile: false)), const SizedBox(width: 16), Expanded(child: _card5(isMobile: false))])]
        ]))));
      }),
    );
  }
}