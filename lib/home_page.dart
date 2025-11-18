import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Uint8List? selectedImage;
  final TextEditingController promptController = TextEditingController();

  // 分析結果
  Map<String, dynamic>? analysisResult;

  // 取得圖片
  Future<void> pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        selectedImage = bytes;
      });
    }
  }

  // 假分析功能（等你說就換成真的 AI）
  Future<void> startAnalysis() async {
    if (selectedImage == null) return;

    setState(() {
      analysisResult = {
        "name": "炸雞腿便當",
        "calories": 780,
        "protein": 32,
        "fat": 38,
        "carbs": 65,
        "items": ["雞腿", "飯", "玉米", "花椰菜"]
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI 食物營養素分析"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// ---------------- 上方三區塊 ----------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// 左邊：拍照上傳
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      ElevatedButton(
                        onPressed: pickImage,
                        child: const Text("拍照 / 上傳照片"),
                      ),
                      const SizedBox(height: 10),
                      if (selectedImage != null)
                        Image.memory(selectedImage!, height: 150),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                /// 中間：提示詞
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: promptController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "提示 AI：這是什麼食物？",
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                /// 右邊：開始分析
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: startAnalysis,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 60),
                    ),
                    child: const Text("開始分析"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            /// ---------------- 分析結果 ----------------
            if (analysisResult != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Card(
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("食物名稱：${analysisResult!['name']}",
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Text("卡路里：${analysisResult!['calories']} kcal"),
                          Text("蛋白質：${analysisResult!['protein']} g"),
                          Text("脂肪：${analysisResult!['fat']} g"),
                          Text("碳水化合物：${analysisResult!['carbs']} g"),
                          const SizedBox(height: 10),

                          const Text("食材列表："),
                          ...analysisResult!["items"].map<Widget>((item) {
                            return CheckboxListTile(
                              title: Text(item),
                              value: true,
                              onChanged: (_) {},
                            );
                          }).toList(),

                          const SizedBox(height: 20),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      analysisResult = null;
                                    });
                                  },
                                  child: const Text("取消")),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: () {
                                  /// TODO: 寫入 Firebase
                                },
                                child: const Text("儲存"),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
// TODO Implement this library.