import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用於複製到剪貼簿
import 'package:share_plus/share_plus.dart'; // 🟢 引入分享套件

import '../services/family_service.dart';

class FamilySettingsPage extends StatefulWidget {
  const FamilySettingsPage({super.key});

  @override
  State<FamilySettingsPage> createState() => _FamilySettingsPageState();
}

class _FamilySettingsPageState extends State<FamilySettingsPage> {
  final FamilyService _familyService = FamilyService();
  final TextEditingController _codeController = TextEditingController();

  String? _generatedCode;
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // 1. 產生邀請碼
  Future<void> _handleGenerateCode() async {
    setState(() => _isLoading = true);
    try {
      final code = await _familyService.generateInviteCode();
      setState(() {
        _generatedCode = code;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("產生失敗: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🟢 1-2. 分享邀請碼 (傳送給家人)
  void _shareCode() {
    if (_generatedCode == null) return;

    final String shareText =
        '''
哈囉！邀請您加入我的飲食紀錄家庭共享 🍎
我的專屬邀請碼是：【$_generatedCode】

請在 App 的『家庭共享設定』中輸入此代碼，就可以隨時關心我的健康飲食狀況囉！
(代碼有效期限為 10 分鐘)
''';

    // 呼叫系統分享面板
    Share.share(shareText);
  }

  // 2. 輸入邀請碼加入
  Future<void> _handleJoinFamily() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length != 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("請輸入 4 位數邀請碼")));
      return;
    }

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    try {
      final result = await _familyService.joinFamily(code);
      if (result['success'] == true) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("🎉 加入成功！"),
            content: Text(
              "您現在可以查看 ${result['targetName']} 的飲食紀錄了。\n請至首頁左上角切換視角。",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                },
                child: const Text("太棒了"),
              ),
            ],
          ),
        );
        _codeController.clear();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("加入失敗: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🟢 3. 解除綁定 (移除家人)
  Future<void> _handleUnbind(Map<String, dynamic> member) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("解除綁定"),
            content: Text("確定要移除「${member['name']}」嗎？\n移除後您將無法再查看對方的紀錄。"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("取消", style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("移除", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() => _isLoading = true);
    try {
      await _familyService.unbindFamily(member);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("已成功解除綁定")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("移除失敗: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("家庭共享設定")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "您可以透過邀請碼與家人連結，互相查看飲食紀錄。",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 24),

            // 🟢 新增區塊：已連結的家人列表 (即時監聽)
            const Text(
              "📋 已連結的家人",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            StreamBuilder<DocumentSnapshot>(
              stream: _familyService.getMyFamilyList(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userData = snapshot.data?.data() as Map<String, dynamic>?;
                final List<dynamic> watchingList =
                    userData?['watching_list'] ?? [];

                if (watchingList.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "目前沒有連結任何家人",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: watchingList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final member = watchingList[index] as Map<String, dynamic>;
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal[100],
                          child: const Icon(Icons.person, color: Colors.teal),
                        ),
                        title: Text(
                          member['name'] ?? '未命名',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text("權限: 僅檢視"),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: _isLoading
                              ? null
                              : () => _handleUnbind(member),
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 32),

            // 區塊 A：我是被照顧者 (產生代碼)
            const Text(
              "👵 我想讓家人看我的紀錄",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                children: [
                  if (_generatedCode == null) ...[
                    const Icon(Icons.qr_code, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    const Text("產生一組 4 位數邀請碼\n給您的家人輸入"),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleGenerateCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text("產生邀請碼"),
                    ),
                  ] else ...[
                    const Text("您的邀請碼", style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(
                      _generatedCode!,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "請在 10 分鐘內使用",
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    // 🟢 修改：將「複製」與「傳送給家人」並排顯示
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: _generatedCode!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("已複製代碼")),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text("複製"),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _shareCode,
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text("傳送給家人"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 40),

            // 區塊 B：我是照顧者 (輸入代碼)
            const Text(
              "🧑‍⚕️ 我要查看家人的健康",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                children: [
                  const Icon(Icons.person_add, size: 48, color: Colors.blue),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      hintText: "輸入對方給您的 4 位數代碼",
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      counterText: "",
                    ),
                    style: const TextStyle(fontSize: 24, letterSpacing: 4),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleJoinFamily,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text("加入家庭成員"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
