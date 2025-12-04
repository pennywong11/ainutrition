import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 引入環境變數套件
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'services/google_drive_service.dart'; // 新增這行

// 重要：這裡要引入你 configure 產生的設定檔
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 載入環境變數
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    if (kDebugMode) {
      print("錯誤：找不到 .env 檔案。請確保專案根目錄有 .env 檔案且包含 GEMINI_API_KEY");
    }
  }

  // 2. 初始化 Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    if (kDebugMode) {
      print("Firebase 初始化失敗: $e");
    }
  }

  runApp(const NutritionAnalyzer());
}

// -----------------------------------------------------------------------------
// 資料模型
// -----------------------------------------------------------------------------

class Ingredient {
  String name;
  double weight; // 克
  double calories;
  double protein;
  double carbs;
  double fat;
  bool isSelected; // 用於控制是否包含在總計算中

  Ingredient({
    required this.name,
    required this.weight,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.isSelected = true,
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

  Map<String, dynamic> toJson() {
    return {
      '食材名': name, // 修改：配合你的資料庫欄位名稱要求
      '重量(g)': weight, // 修改：配合你的資料庫欄位名稱要求
      '熱量(kcal)': calories, // 修改：配合你的資料庫欄位名稱要求
      '蛋白質(g)': protein, // 修改：配合你的資料庫欄位名稱要求
      '碳水化合物(g)': carbs, // 修改：配合你的資料庫欄位名稱要求
      '脂肪(g)': fat, // 修改：配合你的資料庫欄位名稱要求
      // 'isSelected': isSelected, // 資料庫不需要存這個 UI 狀態，除非你想記住
    };
  }
}

class FoodAnalysisResult {
  String dishName;
  String aiSummary;
  DateTime analyzedTime; // 新增：紀錄分析時間
  List<Ingredient> ingredients;

  FoodAnalysisResult({
    required this.dishName,
    required this.aiSummary,
    required this.ingredients,
    required this.analyzedTime, // 建構子加入時間
  });

  // 計算總值 (只計算 isSelected 為 true 的食材)
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
// 主程式 UI - 完全修復版本 (解決所有 Flex 溢出問題)
// -----------------------------------------------------------------------------

class NutritionAnalyzer extends StatelessWidget {
  const NutritionAnalyzer({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      //title: 'AI 營養追蹤儀表板',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF5F9F8),
        useMaterial3: true,
        fontFamily: 'Noto Sans TC',
      ),
      home: const DashboardPage(),
    );
  }
}

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
  // 檢查 API Key 是否存在
  bool _isApiKeyLoaded = false;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
    _initializeAI();
  }

  // 1. 初始化 Firebase Auth (匿名登入)
  Future<void> _initializeAuth() async {
    final auth = FirebaseAuth.instance;
    // 先檢查當前是否已經登入
    if (auth.currentUser == null) {
      try {
        if (kDebugMode) {
          print("偵測到未登入，嘗試匿名登入...");
        }
        await auth.signInAnonymously();
      } catch (e) {
        if (kDebugMode) {
          print("匿名登入失敗: $e");
        }
      }
    }

    // 監聽使用者狀態改變
    auth.authStateChanges().listen((User? user) {
      if (user != null) {
        if (kDebugMode) {
          print("Auth 狀態更新 - UID: ${user.uid}");
        }
      }
      if (mounted) {
        setState(() {
          _user = user;
        });
      }
    });
  }

  // 2. 初始化 Gemini Model (從環境變數讀取 Key)
  void _initializeAI() {
    // 從 .env 檔案讀取 Key
    final apiKey = dotenv.env['GEMINI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      if (kDebugMode) {
        print("錯誤：未設定 GEMINI_API_KEY");
      }
      setState(() {
        _isApiKeyLoaded = false;
      });
      return;
    }

    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

    setState(() {
      _isApiKeyLoaded = true;
    });
  }

  // 3. 選擇圖片
  // 3. 圖片選擇功能 - 三選一版本
  Future<void> _showImagePickerOptions() async {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      await _showMobileImagePicker();
    } else {
      await _pickImageFromGallery();
    }
  }

  Future<void> _showMobileImagePicker() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '選擇圖片方式',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.teal),
                title: const Text('拍照'),
                onTap: () => Navigator.pop(context, 1),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.teal),
                title: const Text('上傳照片'),
                onTap: () => Navigator.pop(context, 2),
              ),
              ListTile(
                leading: const Icon(Icons.folder, color: Colors.teal),
                title: const Text('選擇檔案'),
                onTap: () => Navigator.pop(context, 3),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, 0),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      side: const BorderSide(color: Colors.grey),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('取消'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

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

  Future<void> _takePhotoWithCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        await _showImagePreview(image);
      }
    } catch (e) {
      print("拍照錯誤: $e");
      _showErrorDialog("無法開啟相機，請檢查權限設定");
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        _handleSelectedImage(image);
      }
    } catch (e) {
      print("選擇照片錯誤: $e");
      _showErrorDialog("無法存取相簿");
    }
  }

  Future<void> _pickImageFromFiles() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        _handleSelectedImage(image);
      }
    } catch (e) {
      print("選擇檔案錯誤: $e");
      _showErrorDialog("無法存取檔案");
    }
  }

  Future<void> _showImagePreview(XFile image) async {
    final bytes = await image.readAsBytes();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '確認照片',
          style: TextStyle(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 5,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  bytes,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('重拍'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('使用此照片'),
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
      print('圖片已選擇: ${image.name}');
    } catch (e) {
      print("處理圖片錯誤: $e");
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

  // 4. 重置/取消
  void _resetAll() {
    setState(() {
      _selectedImage = null;
      _imageBytes = null;
      _promptController.clear();
      _analysisResult = null;
      _isAnalyzing = false;
    });
  }

  // 5. 開始分析
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
      final prompt =
          """
      你是一個專業的營養師。請分析這張食物圖片。
      使用者提示詞: ${_promptController.text}
      
      請辨識圖片中的食物，並詳細列出所有可見食材的營養估算。
      
      【重要】請嚴格按照以下 JSON 格式回傳，不要包含 Markdown 標記 (如 ```json)：
      {
        "dish_name": "食物總稱 (例如：雞肉凱薩沙拉)",
        "summary": "對這道食物的簡短健康總結，約 20 字。",
        "ingredients": [
          {
            "name": "食材名稱 (例如：雞胸肉)",
            "weight": 數字(克),
            "calories": 數字(大卡),
            "protein": 數字(克),
            "carbs": 數字(克),
            "fat": 數字(克)
          },
          ...更多食材
        ]
      }
      
      請確保數值是合理的估算。
      """;

      final content = [
        Content.multi([TextPart(prompt), DataPart('image/jpeg', _imageBytes!)]),
      ];

      final response = await _model.generateContent(content);
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

        final data = jsonDecode(cleanJson);

        List<Ingredient> ingredients = [];
        if (data['ingredients'] != null) {
          ingredients = (data['ingredients'] as List)
              .map((i) => Ingredient.fromJson(i))
              .toList();
        }

        setState(() {
          _analysisResult = FoodAnalysisResult(
            dishName: data['dish_name'] ?? '未知食物',
            aiSummary: data['summary'] ?? '無法產生總結',
            ingredients: ingredients,
            analyzedTime: DateTime.now(),
          );
        });
      }
    } catch (e) {
      _showSnackBar('分析失敗: $e');
      if (kDebugMode) {
        print("分析錯誤: $e");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  // 6. 儲存到 Firestore (修改重點：修正 UID 檢查與資料庫結構)
  Future<void> _saveToFirestore() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showSnackBar('錯誤：系統偵測到尚未登入');
      return;
    }

    if (_analysisResult == null || _imageBytes == null) return;

    setState(() {
      _isAnalyzing = true;
    });

    try {
      // 簡單的 Base64 編碼
      String base64Image = base64Encode(_imageBytes!);

      // 如果圖片太大，簡單壓縮（可選）
      if (_imageBytes!.length > 800000) {
        // 大於 800KB
        print('⚠️ 圖片較大，進行簡單壓縮');
        // 這裡可以添加壓縮邏輯，或直接取部分資料
        base64Image = base64Encode(_imageBytes!.sublist(0, 800000));
      }

      final recordRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('analysis_records')
          .doc();

      WriteBatch batch = FirebaseFirestore.instance.batch();

      // 儲存資料（包含 Base64 圖片）
      final recordData = {
        'AI分析建議': _analysisResult!.aiSummary,
        '食物名': _analysisResult!.dishName,
        '圖片_base64': base64Image, // !!
        'created_at': FieldValue.serverTimestamp(),
        'analyzed_date_string': _formatDateTime(_analysisResult!.analyzedTime),
        'total_calories': _analysisResult!.totalCalories,
      };

      batch.set(recordRef, recordData);

      // 儲存食材
      for (var ingredient in _analysisResult!.ingredients) {
        if (ingredient.isSelected) {
          DocumentReference ingredientDoc = recordRef
              .collection('ingredients')
              .doc();
          batch.set(ingredientDoc, ingredient.toJson());
        }
      }

      await batch.commit();
      _showSnackBar('分析結果已成功儲存！', isSuccess: true);
      print('✅ 資料儲存完成，包含 Base64 圖片');

      // 重要：儲存完成後自動跳轉到歷史記錄頁面
      // 延遲一小段時間，讓使用者看到成功訊息
      await Future.delayed(const Duration(milliseconds: 500));

      // 使用 Navigator 跳轉到歷史記錄頁面
      if (mounted) {
        Navigator.pushNamed(context, '/');
      }
    } catch (e) {
      _showSnackBar('儲存失敗: $e');
      print("儲存錯誤: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  // 輔助函式：格式化時間
  String _formatDateTime(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} ${twoDigits(dt.hour)}:${twoDigits(dt.minute)}";
  }

  // Web 優化的 SnackBar 顯示
  void _showSnackBar(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.teal : null,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final isMobile = screenWidth < 600;

            return Container(
              constraints: const BoxConstraints(maxWidth: 1400),
              padding: isMobile
                  ? const EdgeInsets.all(16)
                  : const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 控制欄
                  _buildControlBar(isMobile),

                  const SizedBox(height: 24),

                  // 主要內容區域 - 最終修正版本
                  Expanded(child: _buildMainContent(isMobile)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildControlBar(bool isMobile) {
    if (isMobile) {
      return Column(
        children: [
          // 圖片選擇按鈕
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showImagePickerOptions,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_selectedImage == null ? '選擇餐點' : '更換照片'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                side: const BorderSide(color: Colors.teal),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 文字輸入框
          TextField(
            controller: _promptController,
            decoration: InputDecoration(
              hintText: '輸入餐點名稱或細節提示詞 (可選)',
              hintStyle: TextStyle(color: Colors.grey[400]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 按鈕列
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _resetAll,
                  child: const Text('取消', style: TextStyle(color: Colors.grey)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed:
                      (_imageBytes != null && !_isAnalyzing && _isApiKeyLoaded)
                      ? _analyzeImage
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_imageBytes != null && _isApiKeyLoaded)
                        ? Colors.teal
                        : Colors.grey[300],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
                      : const Text('開始分析'),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      // 修復桌面版控制欄溢出問題
      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final isCompact = availableWidth < 800;

          if (isCompact) {
            // 緊湊佈局：垂直排列
            return Column(
              children: [
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _showImagePickerOptions,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(_selectedImage == null ? '選擇餐點' : '更換照片'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.teal,
                        side: const BorderSide(color: Colors.teal),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: _resetAll,
                        child: const Text(
                          '取消',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed:
                          (_imageBytes != null &&
                              !_isAnalyzing &&
                              _isApiKeyLoaded)
                          ? _analyzeImage
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            (_imageBytes != null && _isApiKeyLoaded)
                            ? Colors.teal
                            : Colors.grey[300],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: _isAnalyzing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('開始分析'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _promptController,
                  decoration: InputDecoration(
                    hintText: '輸入餐點名稱或細節提示詞 (可選)',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            );
          } else {
            // 正常佈局：水平排列
            return Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _showImagePickerOptions,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(_selectedImage == null ? '選擇餐點' : '更換照片'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.teal,
                    side: const BorderSide(color: Colors.teal),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    decoration: InputDecoration(
                      hintText: '輸入餐點名稱或細節提示詞 (可選)',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: _resetAll,
                  child: const Text('取消', style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed:
                      (_imageBytes != null && !_isAnalyzing && _isApiKeyLoaded)
                      ? _analyzeImage
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_imageBytes != null && _isApiKeyLoaded)
                        ? Colors.teal
                        : Colors.grey[300],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
                      : const Text('開始分析'),
                ),
              ],
            );
          }
        },
      );
    }
  }

  // 主要內容區域 - 最終修正版本
  Widget _buildMainContent(bool isMobile) {
    if (isMobile) {
      // 手機版：整個內容區域滾動（圖片 + 結果）
      return SingleChildScrollView(
        child: Column(
          children: [
            // 圖片區域 - 固定高度
            Container(height: 250, child: _buildImageSection()),
            const SizedBox(height: 20),
            // 結果區域 - 自然擴展
            _buildResultSection(true),
          ],
        ),
      );
    } else {
      // 桌面版：只有結果區域滾動，圖片固定顯示
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 圖片區域 - 固定高度
          Expanded(flex: 4, child: _buildImageSection()),
          const SizedBox(width: 24),
          // 結果區域 - 可滾動
          Expanded(
            flex: 6,
            child: SingleChildScrollView(child: _buildResultSection(false)),
          ),
        ],
      );
    }
  }

  // 圖片區域
  Widget _buildImageSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _imageBytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _imageBytes!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            )
          : Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.grey[400]!,
                  style: BorderStyle.solid,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    '上傳圖片或輸入名稱以開始分析',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // 結果區域
  Widget _buildResultSection(bool isMobile) {
    if (_analysisResult == null) {
      return Container(
        width: double.infinity,
        height: 400, //
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: const Center(
          child: Text(
            '分析結果將顯示在這裡...',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

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

  // 結果內容
  Widget _buildResultContent(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題區域
        _buildTitleSection(isMobile),
        const SizedBox(height: 16),

        // 營養摘要卡片
        _buildNutritionSummary(isMobile),
        const SizedBox(height: 16),

        // 營養素卡片
        _buildNutrientCards(isMobile),
        const SizedBox(height: 20),

        // 食材清單標題
        Text(
          'AI 總結食材清單 (${_analysisResult!.ingredients.length} 項)',
          style: TextStyle(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),

        // 營養素標籤 - 修復溢出問題
        _buildNutritionLabels(isMobile),
        const SizedBox(height: 12),

        // 食材清單 - 自然擴展
        _buildIngredientsList(isMobile),

        const SizedBox(height: 16),

        // AI 總結
        _buildAISummary(isMobile),
        const SizedBox(height: 16),

        // 操作按鈕 - 修復溢出問題
        _buildActionButtons(isMobile),
      ],
    );
  }

  // 食材清單
  Widget _buildIngredientsList(bool isMobile) {
    return Column(
      children: _analysisResult!.ingredients.map((ingredient) {
        final opacity = ingredient.isSelected ? 1.0 : 0.5;

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
                border: Border.all(color: Colors.teal.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ingredient.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 14 : 16,
                          ),
                        ),
                        Text(
                          '${ingredient.weight} g • ${ingredient.calories} kcal',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: isMobile ? 12 : 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 修復營養素標籤溢出 - 使用 Wrap
                        Wrap(
                          spacing: isMobile ? 6 : 8,
                          children: [
                            _buildMiniNutrient(
                              Icons.circle,
                              Colors.blue,
                              ingredient.protein,
                              isMobile,
                            ),
                            _buildMiniNutrient(
                              Icons.circle,
                              Colors.green,
                              ingredient.carbs,
                              isMobile,
                            ),
                            _buildMiniNutrient(
                              Icons.circle,
                              Colors.orange,
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
                          : Colors.teal,
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

  // 標題區域
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
        if (!isMobile)
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.edit_outlined, color: Colors.teal),
          ),
      ],
    );
  }

  // 營養摘要
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

  // 營養素
  Widget _buildNutrientCards(bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: _buildNutrientCard(
            '蛋白質',
            '${_analysisResult!.totalProtein.toStringAsFixed(1)} g',
            Colors.blue,
            isMobile,
          ),
        ),
        SizedBox(width: isMobile ? 6 : 8),
        Expanded(
          child: _buildNutrientCard(
            '碳水化合物',
            '${_analysisResult!.totalCarbs.toStringAsFixed(1)} g',
            Colors.green,
            isMobile,
          ),
        ),
        SizedBox(width: isMobile ? 6 : 8),
        Expanded(
          child: _buildNutrientCard(
            '脂肪',
            '${_analysisResult!.totalFat.toStringAsFixed(1)} g',
            Colors.orange,
            isMobile,
          ),
        ),
      ],
    );
  }

  // 營養素標籤 - 修復溢出問題
  Widget _buildNutritionLabels(bool isMobile) {
    return Wrap(
      spacing: isMobile ? 8 : 12,
      runSpacing: 8,
      alignment: WrapAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.restaurant_menu,
              size: isMobile ? 12 : 14,
              color: Colors.blue[300],
            ),
            const SizedBox(width: 4),
            Text(
              '${_analysisResult!.totalProtein.toStringAsFixed(1)} g',
              style: TextStyle(
                fontSize: isMobile ? 10 : 12,
                color: Colors.blue[300],
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco, size: isMobile ? 12 : 14, color: Colors.green[300]),
            const SizedBox(width: 4),
            Text(
              '${_analysisResult!.totalCarbs.toStringAsFixed(1)} g',
              style: TextStyle(
                fontSize: isMobile ? 10 : 12,
                color: Colors.green[300],
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.water_drop,
              size: isMobile ? 12 : 14,
              color: Colors.orange[300],
            ),
            const SizedBox(width: 4),
            Text(
              '${_analysisResult!.totalFat.toStringAsFixed(1)} g',
              style: TextStyle(
                fontSize: isMobile ? 10 : 12,
                color: Colors.orange[300],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // AI 總結
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

  // 操作按鈕 - 修復溢出問題
  Widget _buildActionButtons(bool isMobile) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: isMobile ? 8 : 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _resetAll,
          icon: Icon(Icons.cancel_outlined, size: isMobile ? 16 : 18),
          label: Text('取消', style: TextStyle(fontSize: isMobile ? 14 : null)),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
        ),
        ElevatedButton.icon(
          onPressed: _saveToFirestore,
          icon: Icon(Icons.check_circle_outline, size: isMobile ? 16 : 18),
          label: Text('確定儲存', style: TextStyle(fontSize: isMobile ? 14 : null)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2F857D),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 20,
              vertical: isMobile ? 10 : 12,
            ),
          ),
        ),
      ],
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

  Widget _buildMiniNutrient(
    IconData icon,
    Color color,
    double value,
    bool isMobile,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: isMobile ? 6 : 8, color: color),
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
