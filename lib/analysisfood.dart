import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 引入環境變數套件
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

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
// 主程式 UI
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
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImage = image;
        _imageBytes = bytes;
        _analysisResult = null;
      });
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('錯誤：找不到 API Key，請檢查 .env 設定')),
      );
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
            analyzedTime: DateTime.now(), // 這裡加入當前時間
          );
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分析失敗: $e')));
      if (kDebugMode) {
        print("分析錯誤: $e");
      }
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  // 6. 儲存到 Firestore (修改重點：修正 UID 檢查與資料庫結構)
  Future<void> _saveToFirestore() async {
    // 修改 1: 不只檢查 _user 變數，直接檢查 FirebaseAuth 的核心實例
    // 這樣可以避免因為 UI 狀態沒更新而導致誤判為未登入
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('錯誤：系統偵測到尚未登入，請重啟 App 再試')));
      return;
    }

    if (_analysisResult == null) return;

    try {
      // 修改 2: 資料庫結構調整
      // 目標結構: users -> uid -> analysis_records -> (doc) -> ingredients -> (sub-collection docs)

      // A. 建立 analysis_records 文件的參考
      final recordRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('analysis_records') // 改為 analysis_records
          .doc(); // 自動產生 RecordId

      // B. 準備批次寫入 (Batch Write) 以確保資料完整性
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // C. 設定主文件資料 (符合你的描述：AI分析建議, 食物名)
      batch.set(recordRef, {
        'AI分析建議': _analysisResult!.aiSummary, // 欄位名稱改成中文
        '食物名': _analysisResult!.dishName, // 欄位名稱改成中文
        'created_at': FieldValue.serverTimestamp(), // 加上系統時間戳記以利排序
        'analyzed_date_string': _formatDateTime(
          _analysisResult!.analyzedTime,
        ), // 儲存字串格式的時間備用
        // 也可以存總營養素方便列表顯示，不存也可以
        'total_calories': _analysisResult!.totalCalories,
      });

      // D. 將食材寫入 ingredients 子集合
      for (var ingredient in _analysisResult!.ingredients) {
        // 只儲存被選中的食材
        if (ingredient.isSelected) {
          DocumentReference ingredientDoc = recordRef
              .collection('ingredients')
              .doc();
          batch.set(ingredientDoc, ingredient.toJson());
        }
      }

      // E. 提交寫入
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('資料已成功儲存！'), backgroundColor: Colors.teal),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('儲存失敗: $e')));
      if (kDebugMode) {
        print("儲存錯誤: $e");
      }
    }
  }

  // 輔助函式：格式化時間
  String _formatDateTime(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} ${twoDigits(dt.hour)}:${twoDigits(dt.minute)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              //const Text(
              //'AI 營養追蹤儀表板',
              //style: TextStyle(
              //fontSize: 28,
              //fontWeight: FontWeight.bold,
              //color: Color(0xFF1E5E5B),
              //),
              //),
              //const SizedBox(height: 30),
              //const Text(
              //'餐點 AI 分析',
              //style: TextStyle(
              //fontSize: 20,
              //fontWeight: FontWeight.bold,
              //color: Colors.black87,
              //),
              //),
              //const SizedBox(height: 16),
              _buildControlBar(),

              //const SizedBox(height: 24),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    bool isWide = constraints.maxWidth > 800;
                    return isWide ? _buildWideLayout() : _buildMobileLayout();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(_selectedImage == null ? '選擇餐點' : '更換照片'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.teal,
            side: const BorderSide(color: Colors.teal),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: (_imageBytes != null && !_isAnalyzing && _isApiKeyLoaded)
              ? _analyzeImage
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: (_imageBytes != null && _isApiKeyLoaded)
                ? Colors.teal
                : Colors.grey[300],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: _buildImageSection()),
        const SizedBox(width: 24),
        Expanded(flex: 6, child: _buildResultSection()),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: 300, child: _buildImageSection()),
          const SizedBox(height: 24),
          _buildResultSection(),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _imageBytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_imageBytes!, fit: BoxFit.contain),
            )
          : DottedBorder(
              color: Colors.grey[400]!, // 已移除，避免編譯錯誤
              strokeWidth: 2.0,
              dashPattern: const [6.0, 6.0],
              borderType: BorderType.RRect,
              radius: const Radius.circular(12),
              child: const Center(
                child: Text(
                  '上傳圖片或輸入名稱以開始分析',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildResultSection() {
    if (_analysisResult == null) {
      return Container(
        width: double.infinity,
        height: 400,
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
      padding: const EdgeInsets.all(24),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start, // 調整對齊
            children: [
              Expanded(
                // 使用 Expanded 避免文字溢出
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _analysisResult!.dishName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // 新增：顯示日期時間
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(_analysisResult!.analyzedTime),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.edit_outlined, color: Colors.teal),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  '總克數 (g)',
                  '${_analysisResult!.totalWeight.toStringAsFixed(1)} g',
                  Colors.black87,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  '熱量 (kcal)',
                  '${_analysisResult!.totalCalories.toStringAsFixed(1)} kcal',
                  Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildNutrientCard(
                  '蛋白質',
                  '${_analysisResult!.totalProtein.toStringAsFixed(1)} g',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNutrientCard(
                  '碳水化合物',
                  '${_analysisResult!.totalCarbs.toStringAsFixed(1)} g',
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNutrientCard(
                  '脂肪',
                  '${_analysisResult!.totalFat.toStringAsFixed(1)} g',
                  Colors.orange,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Text(
            'AI 總結食材清單 (${_analysisResult!.ingredients.length} 項)',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.restaurant_menu, size: 14, color: Colors.blue[300]),
              const SizedBox(width: 4),
              Text(
                '${_analysisResult!.totalProtein.toStringAsFixed(1)} g',
                style: TextStyle(fontSize: 12, color: Colors.blue[300]),
              ),
              const SizedBox(width: 12),
              Icon(Icons.eco, size: 14, color: Colors.green[300]),
              const SizedBox(width: 4),
              Text(
                '${_analysisResult!.totalCarbs.toStringAsFixed(1)} g',
                style: TextStyle(fontSize: 12, color: Colors.green[300]),
              ),
              const SizedBox(width: 12),
              Icon(Icons.water_drop, size: 14, color: Colors.orange[300]),
              const SizedBox(width: 4),
              Text(
                '${_analysisResult!.totalFat.toStringAsFixed(1)} g',
                style: TextStyle(fontSize: 12, color: Colors.orange[300]),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Expanded(
            child: ListView.separated(
              itemCount: _analysisResult!.ingredients.length,
              separatorBuilder: (ctx, index) => const SizedBox(height: 12),
              itemBuilder: (ctx, index) {
                final ingredient = _analysisResult!.ingredients[index];
                final opacity = ingredient.isSelected ? 1.0 : 0.5;

                return Opacity(
                  opacity: opacity,
                  child: Container(
                    padding: const EdgeInsets.all(12),
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                '${ingredient.weight} g • ${ingredient.calories} kcal',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _buildMiniNutrient(
                                    Icons.circle,
                                    Colors.blue,
                                    ingredient.protein,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildMiniNutrient(
                                    Icons.circle,
                                    Colors.green,
                                    ingredient.carbs,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildMiniNutrient(
                                    Icons.circle,
                                    Colors.orange,
                                    ingredient.fat,
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
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _analysisResult!.aiSummary,
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _resetAll,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('取消'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _saveToFirestore,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('確定儲存'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F857D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, color: color)),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniNutrient(IconData icon, Color color, double value) {
    return Row(
      children: [
        Icon(icon, size: 8, color: color),
        const SizedBox(width: 4),
        Text(
          '${value.toStringAsFixed(1)} g',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
