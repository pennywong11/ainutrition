import 'dart:async'; // 用於延遲操作
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 引入環境變數套件
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

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
      '食材名': name,
      '重量(g)': weight,
      '熱量(kcal)': calories,
      '蛋白質(g)': protein,
      '碳水化合物(g)': carbs,
      '脂肪(g)': fat,
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
// Dashboard Page
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

  // 🌟 1. 定義一個 GlobalKey 來定位「結果區塊」的位置
  final GlobalKey _resultKey = GlobalKey();

  // 雖然用 GlobalKey 滑動不需要 ScrollController，但為了讓 SingleChildScrollView 正常運作，保留它
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeAuth();
    _initializeAI();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 1. 初始化 Firebase Auth
  Future<void> _initializeAuth() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      try {
        if (kDebugMode) print("偵測到未登入，嘗試匿名登入...");
        await auth.signInAnonymously();
      } catch (e) {
        if (kDebugMode) print("匿名登入失敗: $e");
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
      if (kDebugMode) print("錯誤：未設定 GEMINI_API_KEY");
      setState(() => _isApiKeyLoaded = false);
      return;
    }
    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
    setState(() => _isApiKeyLoaded = true);
  }

  // 3. 選擇圖片
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
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '選擇圖片方式',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
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
      if (image != null) await _showImagePreview(image);
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
      if (image != null) _handleSelectedImage(image);
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
      if (image != null) _handleSelectedImage(image);
    } catch (e) {
      print("選擇檔案錯誤: $e");
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
        "dish_name": "食物總稱",
        "summary": "簡短總結 (約20字)",
        "ingredients": [
          {
            "name": "食材名稱",
            "weight": 0,
            "calories": 0,
            "protein": 0,
            "carbs": 0,
            "fat": 0
          }
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

        // 🌟 關鍵邏輯：使用 GlobalKey 進行精準定位與滑動
        if (mounted) {
          await Future.delayed(const Duration(milliseconds: 100));

          // 檢查 Key 是否有對應的 Widget
          if (_resultKey.currentContext != null) {
            // Scrollable.ensureVisible 會自動計算位置，確保該 Widget 的頂部出現在可視區域
            Scrollable.ensureVisible(
              _resultKey.currentContext!,
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutQuart,
              alignment: 0.0, // 0.0 表示對齊頂部
            );
          }
        }
      }
    } catch (e) {
      _showSnackBar('分析失敗: $e');
      if (kDebugMode) print("分析錯誤: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
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

    setState(() => _isAnalyzing = true);

    try {
      String base64Image = base64Encode(_imageBytes!);
      if (_imageBytes!.length > 800000) {
        base64Image = base64Encode(_imageBytes!.sublist(0, 800000));
      }

      final recordRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('analysis_records')
          .doc();

      WriteBatch batch = FirebaseFirestore.instance.batch();

      final recordData = {
        'AI分析建議': _analysisResult!.aiSummary,
        '食物名': _analysisResult!.dishName,
        '圖片_base64': base64Image,
        'created_at': FieldValue.serverTimestamp(),
        'analyzed_date_string': _formatDateTime(_analysisResult!.analyzedTime),
        'total_calories': _analysisResult!.totalCalories,
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
      _showSnackBar('分析結果已成功儲存！', isSuccess: true);

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.pushNamed(context, '/');
    } catch (e) {
      _showSnackBar('儲存失敗: $e');
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
        backgroundColor: isSuccess ? Colors.teal : null,
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
        backgroundColor: const Color.fromARGB(255, 157, 198, 194),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFF2FDF9)),
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
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert, color: Colors.black87),
          ),
        ],
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

    // 狀態 1: 初始畫面
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

    // 狀態 2: 已選好照片，準備分析
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

    // 狀態 3: 顯示結果
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
              // 🌟 2. 這裡綁定 Key，讓程式知道這是「結果卡片」
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
      return Image.memory(
        _imageBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
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
                  onPressed: _resetAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    '重選 / 取消',
                    style: TextStyle(color: Colors.grey),
                  ),
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
                  backgroundColor: (_imageBytes != null && _isApiKeyLoaded)
                      ? (_analysisResult == null
                            ? Colors.teal
                            : const Color(0xFF2F857D))
                      : Colors.grey[300],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 2,
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
        const SizedBox(height: 8),
        _buildNutritionLabels(isMobile),
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

  Widget _buildNutritionLabels(bool isMobile) {
    return Wrap(
      spacing: isMobile ? 8 : 12,
      runSpacing: 8,
      children: [
        _buildLabel(
          Icons.restaurant_menu,
          Colors.blue[300]!,
          '${_analysisResult!.totalProtein.toStringAsFixed(1)} g',
          isMobile,
        ),
        _buildLabel(
          Icons.eco,
          Colors.green[300]!,
          '${_analysisResult!.totalCarbs.toStringAsFixed(1)} g',
          isMobile,
        ),
        _buildLabel(
          Icons.water_drop,
          Colors.orange[300]!,
          '${_analysisResult!.totalFat.toStringAsFixed(1)} g',
          isMobile,
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
