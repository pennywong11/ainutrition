import 'dart:async'; // 用於延遲操作
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart'; // 引入 iOS 風格元件
import 'package:flutter/foundation.dart'; // For kIsWeb, compute, defaultTargetPlatform
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 引入環境變數套件
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

import '../services/nutrition_service.dart';

// -----------------------------------------------------------------------------
// 資料模型 (Models)
// -----------------------------------------------------------------------------

class Ingredient {
  String name;
  double weight; // 克
  double calories;
  double protein;
  double carbs;
  double fat;
  bool isSelected; // 用於控制是否包含在總計算中
  bool isFromDatabase; // 標記是否來自資料庫

  Ingredient({
    required this.name,
    required this.weight,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.isSelected = true,
    this.isFromDatabase = false,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      name: json['name'] ?? '未知食材',
      weight: (json['weight'] ?? 0).toDouble(),
      calories: (json['calories'] ?? 0).toDouble(),
      protein: (json['protein'] ?? 0).toDouble(),
      carbs: (json['carbs'] ?? 0).toDouble(),
      fat: (json['fat'] ?? 0).toDouble(),
    );
  }

  // 存入 Firestore 時，四捨五入至小數點第二位
  Map<String, dynamic> toJson() {
    double round2(double val) => double.parse(val.toStringAsFixed(2));

    return {
      '食材名': name,
      '重量(g)': round2(weight),
      '熱量(kcal)': round2(calories),
      '蛋白質(g)': round2(protein),
      '碳水化合物(g)': round2(carbs),
      '脂肪(g)': round2(fat),
      'is_verified': isFromDatabase,
    };
  }
}

class FoodAnalysisResult {
  String dishName;
  String aiSummary;
  DateTime analyzedTime;
  List<Ingredient> ingredients;

  FoodAnalysisResult({
    required this.dishName,
    required this.aiSummary,
    required this.ingredients,
    required this.analyzedTime,
  });

  double get totalWeight => ingredients
      .where((i) => i.isSelected)
      .fold(0, (sum, i) => sum + i.weight);
  double get totalCalories => ingredients
      .where((i) => i.isSelected)
      .fold(0, (sum, i) => sum + i.calories);
  double get totalProtein => ingredients
      .where((i) => i.isSelected)
      .fold(0, (sum, i) => sum + i.protein);
  double get totalCarbs =>
      ingredients.where((i) => i.isSelected).fold(0, (sum, i) => sum + i.carbs);
  double get totalFat =>
      ingredients.where((i) => i.isSelected).fold(0, (sum, i) => sum + i.fat);
}

// -----------------------------------------------------------------------------
// Dashboard Page (分析頁面主體)
// -----------------------------------------------------------------------------

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // 狀態變數
  User? _user;
  XFile? _selectedImage;
  Uint8List? _imageBytes;
  final TextEditingController _promptController = TextEditingController();
  bool _isAnalyzing = false;
  FoodAnalysisResult? _analysisResult;

  late final GenerativeModel _model;
  bool _isApiKeyLoaded = false;

  // 宣告 NutritionService
  final NutritionService _nutritionService = NutritionService();

  // 定位 Key 與 滾動控制器
  final GlobalKey _resultKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  static Future<String> _encodeImageInBackground(Uint8List bytes) async {
    return compute((Uint8List b) => base64Encode(b), bytes);
  }

  @override
  void initState() {
    super.initState();
    _initializeAuth();
    _initializeAI();

    // 啟動時載入 CSV 資料庫
    _nutritionService.loadCsvData();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 1. 初始化 Auth 監聽
  Future<void> _initializeAuth() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      try {
        await auth.signInAnonymously();
      } catch (e) {
        print("Dashboard: 補救登入失敗: $e");
      }
    }

    auth.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _user = user;
        });
      }
    });
  }

  // 2. 初始化 Gemini Model
  void _initializeAI() {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      if (kDebugMode) print("錯誤：DashboardPage 讀取不到 GEMINI_API_KEY");
      setState(() => _isApiKeyLoaded = false);
      return;
    }
    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
    setState(() => _isApiKeyLoaded = true);
  }

  // ---------------------------------------------------------------------------
  // 3. 選擇圖片邏輯
  // ---------------------------------------------------------------------------
  Future<void> _showImagePickerOptions() async {
    if (kIsWeb) {
      await _pickImageFromGallery();
      return;
    }

    final bool isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    if (isIOS) {
      await _showCupertinoImagePicker();
    } else {
      await _showMaterialImagePicker();
    }
  }

  Future<void> _showCupertinoImagePicker() async {
    final result = await showCupertinoModalPopup<int>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('選擇圖片方式'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            child: const Text('拍照'),
            onPressed: () => Navigator.pop(context, 1),
          ),
          CupertinoActionSheetAction(
            child: const Text('照片圖庫'),
            onPressed: () => Navigator.pop(context, 2),
          ),
          CupertinoActionSheetAction(
            child: const Text('選擇檔案'),
            onPressed: () => Navigator.pop(context, 3),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('取消'),
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context, 0),
        ),
      ),
    );
    _handlePickerResult(result);
  }

  Future<void> _showMaterialImagePicker() async {
    final primaryColor = Theme.of(context).colorScheme.primary;

    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '選擇圖片方式',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: primaryColor),
                title: const Text('拍照'),
                onTap: () => Navigator.pop(context, 1),
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: primaryColor),
                title: const Text('照片圖庫'),
                onTap: () => Navigator.pop(context, 2),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.close, color: Colors.grey),
                title: const Text('取消'),
                onTap: () => Navigator.pop(context, 0),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    _handlePickerResult(result);
  }

  Future<void> _handlePickerResult(int? result) async {
    if (result == null || result == 0) return;
    switch (result) {
      case 1:
        await _takePhotoWithCamera();
        break;
      case 2:
        await _pickImageFromGallery();
        break;
      case 3:
        await _pickImageFromFiles();
        break;
    }
  }

  // 速度優化 1：調整圖片壓縮參數 (maxWidth: 600, quality: 50)
  // 這會大幅減少上傳時間，解決 "分析要20秒" 的問題
  Future<void> _takePhotoWithCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 50,
      );
      if (image != null) await _showImagePreview(image);
    } catch (e) {
      _showErrorDialog("無法開啟相機，請檢查權限設定");
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 50,
      );
      if (image != null) _handleSelectedImage(image);
    } catch (e) {
      _showErrorDialog("無法存取相簿");
    }
  }

  Future<void> _pickImageFromFiles() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 50,
      );
      if (image != null) _handleSelectedImage(image);
    } catch (e) {
      _showErrorDialog("無法存取檔案");
    }
  }

  Future<void> _showImagePreview(XFile image) async {
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        scrollable: true,
        title: const Text(
          '確認照片',
          style: TextStyle(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      foregroundColor: Colors.grey,
                    ),
                    child: const Text('重拍'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text('確定'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      _handleSelectedImage(image);
    } else {
      await _takePhotoWithCamera();
    }
  }

  void _handleSelectedImage(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImage = image;
        _imageBytes = bytes;
        _analysisResult = null;
      });
      _showSnackBar('圖片選擇成功！', isSuccess: true);
    } catch (e) {
      _showErrorDialog("處理圖片時發生錯誤");
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('錯誤'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _resetAll() {
    setState(() {
      _selectedImage = null;
      _imageBytes = null;
      _promptController.clear();
      _analysisResult = null;
      _isAnalyzing = false;
    });
  }

  // ---------------------------------------------------------------------------
  // 5. 開始分析
  // ---------------------------------------------------------------------------
  Future<void> _analyzeImage() async {
    if (_imageBytes == null) return;
    if (!_isApiKeyLoaded) {
      _showSnackBar('錯誤：找不到 API Key,請檢查 .env 設定');
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    try {
      final userInput = _promptController.text.trim();

      // Prompt 修改
      final prompt =
          """
      你是一個專業的營養師。請依據以下邏輯分析這張圖片與使用者的描述。
      
      使用者描述: "$userInput"
      
      請執行【圖文整合分析機制】：
      
      1. **辨識圖片**：首先列出圖片中「所有」看得到的食材 (例如：豬排、咖哩醬、紅蘿蔔、白飯)。
      2. **判斷情境** (依序判定)：
      
         - **情境 A [修飾模式]**：圖片清晰且是食物。
           -> 核心原則：**圖片是主角，文字是修飾。**
           -> 行動：保留圖片中看到的所有食材。若使用者文字提到「半飯」、「少油」、「去皮」等，請**調整對應食材的重量或熱量**。
           -> **【重要】強制拆解原則**：若圖片中食材是「分開擺放」的（例如便當、自助餐），即使使用者文字輸入「炒飯」、「燴飯」等混合料理名稱，也請**優先依據圖片視覺，將飯、肉、菜分開列出**，除非圖片本身真的是混合料理。
           -> 範例：圖是「排骨便當（飯、菜分開）」，文字寫「排骨炒飯」。
              * 正確行為：忽略「炒飯」文字定義，輸出「白飯」、「炸排骨」、「炒青菜」。
           -> 輸出：is_food: true, dish_name: 辨識結果, summary: 總結。
           
         - **情境 B [補救情境]**：圖片模糊/全黑/無法辨識，但使用者有輸入描述。
           -> 行動：完全信賴使用者描述，提供標準估算值。
           -> 輸出：is_food: true, dish_name: "$userInput (標準估算)", summary: "因圖片模糊，已依據文字分析提供標準數據。"
           
         - **情境 C [衝突情境]**：圖片清晰顯示為「非食物」(如貓、椅子、馬桶)，但使用者有輸入食物描述。
           -> 行動：**強制信賴使用者描述**，忽略圖片內容。
           -> 輸出：is_food: true, dish_name: "$userInput (文字估算)", summary: "圖片看起來是[圖片內容]，但已依據您的描述提供$userInput數據。"
           
         - **情境 D [無效情境]**：圖片非食物，且使用者「沒有」輸入描述。
           -> 行動：拒絕服務。
           -> 輸出：is_food: false, error_msg: "無法辨識為食物，請補充文字說明。"

      【嚴格輸出規範】：
      1. **dish_name (餐點名稱)**：請**簡潔扼要** (建議 10 字內)。
         - 錯誤：營養豐富的香煎雞腿排佐時蔬便當
         - 正確：香煎雞腿便當
      2. **summary (營養總結)**：請非常精簡，**絕對不要超過 35 個中文字**。直接講重點，不要廢話。
      3. **ingredients (食材名稱)**：
         - name: 請**只寫最核心的食材名**，去除所有冗言贅詞。
         - **search_terms**: [重要] 請提供 2~3 個適合在「台灣衛福部食品成分資料庫」搜尋的關鍵字。
         - **calories**: 提供 AI 估算的總營養素數值。

      【回傳格式 (JSON Only)】：
      {
        "is_food": true/false,
        "error_msg": "...",
        "dish_name": "...",
        "summary": "...",
        "ingredients": [
          {
            "name": "...", 
            "weight": 100, 
            "search_terms": ["關鍵字1", "關鍵字2"],
            "calories": 150, 
            "protein": 5, 
            "carbs": 20, 
            "fat": 3
          }
        ]
      }
      """;

      final content = [
        Content.multi([TextPart(prompt), DataPart('image/jpeg', _imageBytes!)]),
      ];

      final safetySettings = [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
      ];

      final response = await _model.generateContent(
        content,
        safetySettings: safetySettings,
      );
      final responseText = response.text;

      if (responseText != null) {
        String cleanJson = responseText
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        if (cleanJson.contains('{')) {
          int startIndex = cleanJson.indexOf('{');
          int endIndex = cleanJson.lastIndexOf('}');
          if (endIndex != -1) {
            cleanJson = cleanJson.substring(startIndex, endIndex + 1);
          }
        }

        try {
          final data = jsonDecode(cleanJson);

          if (data['is_food'] == false) {
            throw data['error_msg'] ?? "圖片無法辨識為食物";
          }

          List<Ingredient> ingredients = [];
          if (data['ingredients'] != null) {
            for (var item in data['ingredients']) {
              String name = item['name'] ?? '未知食材';
              double weight = (item['weight'] ?? 0).toDouble();

              double calories = (item['calories'] ?? 0).toDouble();
              double protein = (item['protein'] ?? 0).toDouble();
              double carbs = (item['carbs'] ?? 0).toDouble();
              double fat = (item['fat'] ?? 0).toDouble();
              bool isVerified = false;

              List<String> searchTerms = [];
              if (item['search_terms'] != null) {
                searchTerms = List<String>.from(item['search_terms']);
              }
              searchTerms.insert(0, name);

              List<FoodItem> matches = [];
              for (var term in searchTerms) {
                // 這裡使用 await，無論是 SQLite 還是 CSV 都能通用
                var currentMatches = await _nutritionService.searchFood(term);

                if (currentMatches.isNotEmpty) {
                  // 智慧排序邏輯
                  currentMatches.sort((a, b) {
                    bool aExact = a.name == term;
                    bool bExact = b.name == term;
                    if (aExact && !bExact) return -1;
                    if (!aExact && bExact) return 1;
                    return a.name.length.compareTo(b.name.length);
                  });

                  matches = currentMatches;
                  break;
                }
              }

              if (matches.isNotEmpty) {
                final dbFood = matches.first;

                // 計算數值
                double ratio = weight / 100.0;

                calories = dbFood.calories * ratio;
                protein = dbFood.protein * ratio;
                fat = dbFood.fat * ratio;
                carbs = dbFood.carbs * ratio;

                isVerified = true;

                print("✅ [查表成功] $name -> ${dbFood.name}");
              } else {
                print("⚠️ [查無資料] $name 使用 AI 估算值");
              }

              ingredients.add(
                Ingredient(
                  name: name,
                  weight: weight,
                  calories: calories,
                  protein: protein,
                  carbs: carbs,
                  fat: fat,
                  isFromDatabase: isVerified,
                ),
              );
            }
          }

          setState(() {
            _analysisResult = FoodAnalysisResult(
              dishName: data['dish_name'] ?? '未知食物',
              aiSummary: data['summary'] ?? '無法產生總結',
              ingredients: ingredients,
              analyzedTime: DateTime.now(),
            );
          });

          if (mounted) {
            await Future.delayed(const Duration(milliseconds: 100));
            if (_resultKey.currentContext != null) {
              Scrollable.ensureVisible(
                _resultKey.currentContext!,
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutQuart,
                alignment: 0.0,
              );
            }
          }
        } catch (e) {
          if (e is String) rethrow;
          print("JSON 解析失敗: $cleanJson");
          throw "AI 回傳格式有誤，請重試";
        }
      }
    } catch (e) {
      String errorMessage = e.toString().replaceAll("Exception: ", "");
      if (errorMessage.contains("Socket")) errorMessage = "網路連線錯誤";
      _showSnackBar(errorMessage);
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  // 6. 儲存到 Firestore
  Future<void> _saveToFirestore() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showSnackBar('錯誤：系統偵測到尚未登入');
      return;
    }
    if (_analysisResult == null || _imageBytes == null) return;

    // 防呆機制：檢查是否有選取任何食材

    final hasSelectedItems = _analysisResult!.ingredients.any(
      (i) => i.isSelected,
    );
    if (!hasSelectedItems) {
      _showSnackBar('請至少選取一項食材才能儲存');
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      String base64Image = await _encodeImageInBackground(_imageBytes!);

      if (base64Image.length > 1048576) {
        throw "圖片壓縮後仍然過大，請嘗試重拍更簡單的畫面";
      }

      final recordRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('analysis_records')
          .doc();

      WriteBatch batch = FirebaseFirestore.instance.batch();

      double round2(double val) => double.parse(val.toStringAsFixed(2));

      final recordData = {
        'AI分析建議': _analysisResult!.aiSummary,
        '食物名': _analysisResult!.dishName,
        '圖片_base64': base64Image,
        'created_at': FieldValue.serverTimestamp(),
        'analyzed_date_string': _formatDateTime(DateTime.now()),
        'total_calories': round2(_analysisResult!.totalCalories),
        'total_protein': round2(_analysisResult!.totalProtein),
        'total_carbs': round2(_analysisResult!.totalCarbs),
        'total_fat': round2(_analysisResult!.totalFat),
      };

      batch.set(recordRef, recordData);

      for (var ingredient in _analysisResult!.ingredients) {
        if (ingredient.isSelected) {
          DocumentReference ingredientDoc = recordRef
              .collection('ingredients')
              .doc();
          batch.set(ingredientDoc, ingredient.toJson());
        }
      }

      await batch.commit();

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('儲存成功'),
            content: const Text('分析結果已儲存。'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).pop(true);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print("儲存錯誤: $e");
      if (e.toString().contains("larger than")) {
        _showSnackBar('圖片過大，無法儲存');
      } else {
        _showSnackBar('儲存失敗: $e');
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  String _formatDateTime(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} ${twoDigits(dt.hour)}:${twoDigits(dt.minute)}";
  }

  void _showSnackBar(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // =========================================================================
  // UI 佈局核心邏輯
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: null,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              FocusScope.of(context).unfocus();
            }
          },
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final isMobile = screenWidth < 600;

          return Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1400),
              padding: EdgeInsets.zero,
              child: _buildMainContent(isMobile),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainContent(bool isMobile) {
    final bool hasImage = _imageBytes != null;
    final bool hasResult = _analysisResult != null;

    if (!hasImage) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
            child: InkWell(
              onTap: _showImagePickerOptions,
              child: _buildImageSection(),
            ),
          ),
        ),
      );
    }

    if (hasImage && !hasResult) {
      return Column(
        children: [
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildImageSection(),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F9F8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _buildControlBar(isMobile),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (isMobile) {
      return SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 250,
              width: double.infinity,
              color: const Color(0xFFF0F4F5),
              child: _buildImageSection(),
            ),
            Container(
              key: _resultKey,
              transform: Matrix4.translationValues(0.0, -20.0, 0.0),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F9F8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildResultSection(true),
                  const SizedBox(height: 20),
                  _buildControlBar(true),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildImageSection(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildControlBar(false),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 6,
              child: SingleChildScrollView(child: _buildResultSection(false)),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildImageSection() {
    if (_imageBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          _imageBytes!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    return DottedBorder(
      color: Colors.grey[400]!,
      strokeWidth: 2,
      dashPattern: const [8, 4],
      borderType: BorderType.RRect,
      radius: const Radius.circular(12),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              '點擊上傳圖片或拍照',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '支援 JPG, PNG 格式',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBar(bool isMobile) {
    return Column(
      children: [
        if (_imageBytes != null && _analysisResult == null) ...[
          TextField(
            controller: _promptController,
            enabled: !_isAnalyzing, // 分析中鎖定輸入框
            decoration: InputDecoration(
              hintText: '補充細節能讓估算更精準 (例：去皮、半飯、無糖...)',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              prefixIcon: Icon(Icons.edit_note, color: Colors.teal[300]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
        ],

        Row(
          children: [
            if (_imageBytes != null)
              Expanded(
                child: TextButton(
                  onPressed: _isAnalyzing ? null : _resetAll, // 分析中禁用重選
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.grey,
                  ),
                  child: const Text('重選 / 取消'),
                ),
              ),
            if (_imageBytes != null) const SizedBox(width: 12),

            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed:
                    (_imageBytes != null && !_isAnalyzing && _isApiKeyLoaded)
                    ? (_analysisResult == null
                          ? _analyzeImage
                          : _saveToFirestore)
                    : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: _isAnalyzing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _analysisResult == null
                                ? Icons.analytics_outlined
                                : Icons.save_alt,
                          ),
                          const SizedBox(width: 8),
                          Text(_analysisResult == null ? '開始分析' : '確定儲存'),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultSection(bool isMobile) {
    if (_analysisResult == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: isMobile ? const EdgeInsets.all(16) : const EdgeInsets.all(24),
        child: _buildResultContent(isMobile),
      ),
    );
  }

  Widget _buildResultContent(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleSection(isMobile),
        const SizedBox(height: 16),
        _buildNutritionSummary(isMobile),
        const SizedBox(height: 16),
        _buildNutrientCards(isMobile),
        const SizedBox(height: 20),
        Text(
          'AI 總結食材清單 (${_analysisResult!.ingredients.length} 項)',
          style: TextStyle(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        _buildIngredientsList(isMobile),
        const SizedBox(height: 16),
        _buildAISummary(isMobile),
      ],
    );
  }

  Widget _buildIngredientsList(bool isMobile) {
    return Column(
      children: _analysisResult!.ingredients.map((ingredient) {
        final opacity = ingredient.isSelected ? 1.0 : 0.5;
        final borderColor = const Color.fromARGB(
          255,
          132,
          202,
          206,
        ).withOpacity(0.1);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Opacity(
            opacity: opacity,
            child: Container(
              padding: isMobile
                  ? const EdgeInsets.all(10)
                  : const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F9F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              ingredient.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isMobile ? 14 : 16,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${ingredient.weight} g • ${ingredient.calories.toStringAsFixed(1)} kcal',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: isMobile ? 12 : 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: isMobile ? 6 : 8,
                          children: [
                            _buildMiniNutrient(
                              const Color.fromARGB(255, 117, 181, 233),
                              ingredient.protein,
                              isMobile,
                            ),
                            _buildMiniNutrient(
                              const Color.fromARGB(255, 132, 202, 206),
                              ingredient.carbs,
                              isMobile,
                            ),
                            _buildMiniNutrient(
                              const Color.fromARGB(255, 245, 190, 118),
                              ingredient.fat,
                              isMobile,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        ingredient.isSelected = !ingredient.isSelected;
                      });
                    },
                    icon: Icon(
                      ingredient.isSelected
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                      color: ingredient.isSelected
                          ? Colors.red[300]
                          : const Color.fromARGB(255, 132, 202, 206),
                      size: isMobile ? 24 : 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // 以下 UI 元件保持不變
  Widget _buildTitleSection(bool isMobile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _analysisResult!.dishName,
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _formatDateTime(_analysisResult!.analyzedTime),
                style: TextStyle(
                  fontSize: isMobile ? 12 : 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNutritionSummary(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            '總克數 (g)',
            '${_analysisResult!.totalWeight.toStringAsFixed(1)} g',
            Colors.black87,
            isMobile,
          ),
        ),
        SizedBox(width: isMobile ? 8 : 12),
        Expanded(
          child: _buildSummaryCard(
            '熱量 (kcal)',
            '${_analysisResult!.totalCalories.toStringAsFixed(1)} kcal',
            Colors.redAccent,
            isMobile,
          ),
        ),
      ],
    );
  }

  Widget _buildNutrientCards(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: _buildNutrientCard(
            '蛋白質',
            '${_analysisResult!.totalProtein.toStringAsFixed(1)} g',
            const Color.fromARGB(255, 117, 181, 233),
            isMobile,
          ),
        ),
        SizedBox(width: isMobile ? 6 : 8),
        Expanded(
          child: _buildNutrientCard(
            '碳水化合物',
            '${_analysisResult!.totalCarbs.toStringAsFixed(1)} g',
            const Color.fromARGB(255, 132, 202, 206),
            isMobile,
          ),
        ),
        SizedBox(width: isMobile ? 6 : 8),
        Expanded(
          child: _buildNutrientCard(
            '脂肪',
            '${_analysisResult!.totalFat.toStringAsFixed(1)} g',
            const Color.fromARGB(255, 245, 190, 118),
            isMobile,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(IconData icon, Color color, String text, bool isMobile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: isMobile ? 12 : 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: isMobile ? 10 : 12, color: color),
        ),
      ],
    );
  }

  Widget _buildAISummary(bool isMobile) {
    return Container(
      padding: isMobile ? const EdgeInsets.all(10) : const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _analysisResult!.aiSummary,
              style: TextStyle(
                color: Colors.black87,
                fontSize: isMobile ? 12 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    Color valueColor,
    bool isMobile,
  ) {
    return Container(
      padding: isMobile
          ? const EdgeInsets.symmetric(vertical: 10, horizontal: 12)
          : const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: isMobile ? 10 : 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientCard(
    String title,
    String value,
    Color color,
    bool isMobile,
  ) {
    return Container(
      padding: isMobile
          ? const EdgeInsets.symmetric(vertical: 6, horizontal: 8)
          : const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: isMobile ? 10 : 11, color: color),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 12 : 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniNutrient(Color color, double value, bool isMobile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isMobile ? 6 : 8,
          height: isMobile ? 6 : 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '${value.toStringAsFixed(1)} g',
          style: TextStyle(
            fontSize: isMobile ? 9 : 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}