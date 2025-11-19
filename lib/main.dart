// lib/main.dart - AI 營養追蹤儀表板
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print('Firebase initialization failed: $e');
  }

  runApp(const NutritionAnalyzerApp());
}

class NutritionAnalyzerApp extends StatelessWidget {
  const NutritionAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 營養追蹤儀表板',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        textTheme: GoogleFonts.interTextTheme(),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00A389)),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 2,
          ),
        ),
      ),
      home: const NutritionHomePage(),
    );
  }
}

class NutritionHomePage extends StatefulWidget {
  const NutritionHomePage({super.key});

  @override
  State<NutritionHomePage> createState() => _NutritionHomePageState();
}

class _NutritionHomePageState extends State<NutritionHomePage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _analysisResult;
  final List<String> _selectedIngredients = [];
  final TextEditingController _promptController = TextEditingController();

  final String _userId = '04815348abcd';

  static const Map<String, dynamic> _mockMeal = {
    'dish_name': '模擬：烤雞肉與什錦蔬菜',
    'calories': 520,
    'protein_g': 45.0,
    'fat_g': 22.5,
    'carbs_g': 35.0,
    'analysis_summary': '這是一份低碳水化合物、高蛋白的健康餐點。脂肪主要來自健康的橄欖油。',
    'ingredients': ['雞胸肉', '彩椒', '洋蔥', '胡蘿蔔', '橄欖油', '混合香草']
  };

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(source: source, maxWidth: 1600);
      if (file != null) {
        setState(() {
          _pickedImage = file;
          _analysisResult = null;
          _selectedIngredients.clear();
          _promptController.clear();
        });
      }
    } catch (e) {
      _showMessage('圖片錯誤', '無法讀取圖片檔案: ${e.toString()}');
    }
  }

  void _clearSelection() {
    setState(() {
      _pickedImage = null;
      _analysisResult = null;
      _selectedIngredients.clear();
      _isAnalyzing = false;
      _promptController.clear();
    });
    _showMessage('已清除', '已取消選擇照片，請重新上傳。', isError: false);
  }

  Future<void> _startAnalysis() async {
    if (_pickedImage == null) {
      _showMessage('提示', '請先選擇一張照片。', isError: false);
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
      _selectedIngredients.clear();
    });

    await Future.delayed(const Duration(seconds: 2));

    final result = Map<String, dynamic>.from(_mockMeal);
    result['dish_name'] =
        result['dish_name']! + (_promptController.text.isNotEmpty ? ' (有額外提示)' : '');
    result['timestamp'] = DateTime.now().toIso8601String();

    setState(() {
      _analysisResult = result;
      _isAnalyzing = false;
      _selectedIngredients.addAll(_analysisResult!['ingredients'] as List<String>);
    });
  }

  Future<void> _confirmSave() async {
    if (_analysisResult == null) {
      _showMessage('錯誤', '沒有可儲存的分析資料。');
      return;
    }

    if (_selectedIngredients.isEmpty) {
      _showMessage('錯誤', '請至少選擇一個食材。');
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 700));
      _showMessage('儲存成功', '餐點已成功記錄！', isError: false);

      setState(() {
        _pickedImage = null;
        _analysisResult = null;
        _selectedIngredients.clear();
        _promptController.clear();
      });
    } catch (e) {
      _showMessage('儲存失敗', '無法將資料存入伺服器。');
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  void _cancelSave() {
    _showMessage('取消操作', '餐點分析結果已丟棄。', isError: false);
    setState(() {
      _analysisResult = null;
      _selectedIngredients.clear();
    });
  }

  void _showMessage(String title, String message, {bool isError = true}) {
    final snackColor = isError ? Colors.red[600] : const Color(0xFF00A389);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title：$message'),
        backgroundColor: snackColor,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildTopHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'AI 營養追蹤儀表板',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.grey[900]),
            ),
            CircleAvatar(
              backgroundColor: const Color(0xFF00A389).withOpacity(0.1),
              child: const Icon(Icons.person, color: Color(0xFF00A389), size: 24),
            )
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '上傳餐點照片，讓 AI 快速分析營養成分。',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildImageButtonAndStatus() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        ElevatedButton.icon(
          onPressed: () async {
            final source = await showModalBottomSheet<ImageSource>(
              context: context,
              builder: (context) => Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.camera_alt, color: Color(0xFF00A389)),
                      title: const Text('拍照'),
                      onTap: () => Navigator.pop(context, ImageSource.camera),
                    ),
                    ListTile(
                      leading: const Icon(Icons.image, color: Color(0xFF00A389)),
                      title: const Text('從相簿選擇'),
                      onTap: () => Navigator.pop(context, ImageSource.gallery),
                    ),
                  ],
                ),
              ),
            );
            if (source != null) _pickImage(source);
          },
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('選擇照片上傳'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00A389),
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        if (_pickedImage != null)
          OutlinedButton.icon(
            onPressed: _clearSelection,
            icon: const Icon(Icons.cancel_outlined, color: Colors.grey),
            label: const Text('取消上傳', style: TextStyle(color: Colors.grey)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewArea(double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 2),
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
      ),
      child: _pickedImage == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fastfood, size: 48, color: Color(0xFF00A389)),
                  const SizedBox(height: 8),
                  Text('等待您的餐點照片', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                ],
              ),
            )
          : FutureBuilder<Uint8List>(
              future: _pickedImage!.readAsBytes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  if (snapshot.hasData) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                    );
                  } else {
                    return const Center(child: Text('無法顯示圖片'));
                  }
                } else {
                  return Center(child: SpinKitRing(color: const Color(0xFF00A389), size: 30.0));
                }
              },
            ),
    );
  }

  Widget _buildPromptInput() {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: TextField(
        controller: _promptController,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: '提供額外提示 (可選)',
          hintText: '例如：這盤是素食餐點，只分析蔬菜和豆腐。',
          labelStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(Icons.smart_toy_outlined, color: Colors.grey[400]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00A389), width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildNutrientRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[700]))),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildAnalysisCard() {
    if (_isAnalyzing) {
      return Container(
        height: 350,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal.shade100, width: 1.5),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpinKitDualRing(color: const Color(0xFF00A389), size: 50),
              const SizedBox(height: 16),
              Text('AI 正在分析餐點中...', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            ],
          ),
        ),
      );
    }

    if (_analysisResult == null) {
      return Container(
        height: 350,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lightbulb_outline, size: 40, color: Colors.teal.shade300),
              const SizedBox(height: 10),
              Text(
                _pickedImage != null ? '按下「開始分析」獲取結果' : '請先上傳照片',
                style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF00A389).withOpacity(0.3), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _analysisResult!['dish_name'] ?? '未知餐點',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.grey[900]),
              ),
              const Divider(height: 20, thickness: 1, color: Colors.white),
              _buildNutrientRow('總熱量', '${_analysisResult!['calories']} kcal', Colors.orange.shade700),
              _buildNutrientRow('蛋白質', '${_analysisResult!['protein_g']} g', Colors.red.shade700),
              _buildNutrientRow('脂肪', '${_analysisResult!['fat_g']} g', Colors.amber.shade700),
              _buildNutrientRow('碳水化合物', '${_analysisResult!['carbs_g']} g', Colors.blue.shade700),
              const SizedBox(height: 15),
              Text(
                '確認/修改食材 (選擇您吃的部分)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: (_analysisResult!['ingredients'] as List<String>).map(
                  (ingredient) => FilterChip(
                    label: Text(ingredient),
                    selected: _selectedIngredients.contains(ingredient),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedIngredients.add(ingredient);
                        } else {
                          _selectedIngredients.remove(ingredient);
                        }
                      });
                    },
                    selectedColor: const Color(0xFF00A389).withOpacity(0.2),
                    checkmarkColor: const Color(0xFF00A389),
                  ),
                ).toList(),
              ),
              const Divider(height: 25, thickness: 1, color: Colors.white),
              Text(
                'AI 分析摘要:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              ),
              const SizedBox(height: 4),
              Text(
                _analysisResult!['analysis_summary'] ?? '無分析摘要',
                style: TextStyle(fontSize: 13, color: Colors.grey[600], fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final bool isAnalysisComplete = _analysisResult != null && !_isAnalyzing;
    final bool isImagePicked = _pickedImage != null;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (isImagePicked && !isAnalysisComplete && !_isAnalyzing) ? _startAnalysis : null,
            icon: const Icon(Icons.psychology_outlined),
            label: Text(_isAnalyzing ? '分析中...' : '開始分析'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A389),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isAnalysisComplete ? _confirmSave : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('確認並儲存'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (isAnalysisComplete) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _cancelSave,
              icon: const Icon(Icons.close),
              label: const Text('取消'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                foregroundColor: Colors.grey[700],
                side: BorderSide(color: Colors.grey.shade400),
              ),
            ),
          ),
        ]
      ],
    );
  }

  Widget _buildContentLayout(double width, double previewHeight) {
    final isWide = width > 900;

    final imageInputSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImageButtonAndStatus(),
        const SizedBox(height: 12),
        _buildPreviewArea(previewHeight),
        _buildPromptInput(),
      ],
    );

    final analysisSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAnalysisCard(),
        const SizedBox(height: 12),
        _buildActionButtons(),
      ],
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: imageInputSection),
          const SizedBox(width: 16),
          Expanded(child: analysisSection),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          imageInputSection,
          const SizedBox(height: 20),
          analysisSection,
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final previewHeight = width > 900 ? 320 : 220;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopHeader(),
              const SizedBox(height: 20),
              _buildContentLayout(width, previewHeight as double),
            ],
          ),
        ),
      ),
    );
  }
}
