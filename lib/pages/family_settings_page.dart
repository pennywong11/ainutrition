import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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
  Timer? _countdownTimer;
  int _secondsRemaining = 600;

  @override
  void dispose() {
    _codeController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _secondsRemaining = 600;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _countdownTimer?.cancel();
        setState(() {
          _generatedCode = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("邀請碼已過期，請重新產生")));
        }
      }
    });
  }

  String _formatTime(int totalSeconds) {
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // 🟢 通用錯誤訊息過濾器 (拿掉醜醜的 Exception: 字眼)
  String _cleanErrorMsg(Object e) {
    return e.toString().replaceAll("Exception: ", "");
  }

  Future<void> _handleGenerateCode() async {
    setState(() => _isLoading = true);
    try {
      final code = await _familyService.generateInviteCode();
      setState(() {
        _generatedCode = code;
      });
      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("產生失敗: ${_cleanErrorMsg(e)}")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCancelCode() async {
    if (_generatedCode == null) return;
    setState(() => _isLoading = true);
    try {
      await _familyService.cancelInviteCode(_generatedCode!);
      _countdownTimer?.cancel();
      setState(() {
        _generatedCode = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("已取消邀請碼")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("取消失敗: ${_cleanErrorMsg(e)}")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _shareCode() {
    if (_generatedCode == null) return;
    final String shareText =
        '''
哈囉！邀請您加入我的飲食紀錄家庭共享 🍎
我的專屬邀請碼是：【$_generatedCode】
(有效剩餘時間：${_formatTime(_secondsRemaining)})
''';
    Share.share(shareText);
  }

  Future<void> _handleJoinFamily() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length != 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("請輸入 4 位數邀請碼")));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await _familyService.joinFamily(code);
      if (result['success'] == true) {
        if (!mounted) return;
        _showJoinSuccessDialog(result['targetName']);
        _codeController.clear();
      }
    } catch (e) {
      if (!mounted) return;
      // 🟢 修改：這裡只顯示過濾過乾淨的中文錯誤，不會有 [cloud_firestore] 等亂碼
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cleanErrorMsg(e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showJoinSuccessDialog(String targetName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("🎉 加入成功！"),
        content: Text("您現在可以查看 $targetName 的飲食紀錄了。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("太棒了"),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteRelation(Map<String, dynamic> member, bool isViewingMe) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("刪除共享關係"),
        content: Text(
          isViewingMe
              ? "確定要撤銷 ${member['name']} 的觀看權限嗎？\n刪除後對方將無法再看到您的紀錄。"
              : "確定要解除綁定 ${member['name']} 嗎？\n刪除後您將無法再看到對方的紀錄。",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                if (isViewingMe) {
                  await _familyService.removeViewer(member);
                } else {
                  await _familyService.unbindFamily(member);
                }
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("已成功刪除共享關係")));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("刪除失敗: ${_cleanErrorMsg(e)}")),
                );
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("確定刪除", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("家庭共享設定")),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "📋 家庭成員管理",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                StreamBuilder<DocumentSnapshot>(
                  stream: _familyService.getMyFamilyList(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());

                    final userData =
                        snapshot.data?.data() as Map<String, dynamic>?;
                    final List<dynamic> watchingList =
                        userData?['watching_list'] ?? [];
                    final List<dynamic> viewersInfo =
                        userData?['viewers_info'] ?? [];

                    if (watchingList.isEmpty && viewersInfo.isEmpty)
                      return _buildEmptyList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (viewersInfo.isNotEmpty) ...[
                          const Text(
                            "👀 正在查看我紀錄的家人",
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: viewersInfo.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) => _buildMemberTile(
                              viewersInfo[index],
                              isViewingMe: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (watchingList.isNotEmpty) ...[
                          const Text(
                            "🔍 我正在查看的家人",
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: watchingList.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) => _buildMemberTile(
                              watchingList[index],
                              isViewingMe: false,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 32),
                _buildGenerateSection(),
                const SizedBox(height: 40),
                _buildJoinSection(),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyList() {
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

  // 🟢 修改：將惱人的 subtitle 副標題移除了
  Widget _buildMemberTile(
    Map<String, dynamic> member, {
    required bool isViewingMe,
  }) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(
        member['name'] ?? '未命名',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        onPressed: () => _confirmDeleteRelation(member, isViewingMe),
      ),
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
    );
  }

  Widget _buildGenerateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "👵 我想讓家人看我的紀錄",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 180),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.orange[200]!, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_generatedCode == null) ...[
                const Icon(Icons.qr_code_2, size: 64, color: Colors.orange),
                const SizedBox(height: 12),
                const Text(
                  "點擊按鈕產生邀請碼",
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _handleGenerateCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text("產生邀請碼", style: TextStyle(fontSize: 16)),
                ),
              ] else ...[
                const Text(
                  "您的邀請碼",
                  style: TextStyle(color: Colors.grey, letterSpacing: 1.2),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 80),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Text(
                      _generatedCode!,
                      style: const TextStyle(
                        fontSize: 100,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 12,
                        color: Colors.orange,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _secondsRemaining < 60
                          ? Colors.red[50]
                          : Colors.orange[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "剩餘有效時間：${_formatTime(_secondsRemaining)}",
                      style: TextStyle(
                        fontSize: 14,
                        color: _secondsRemaining < 60
                            ? Colors.red
                            : Colors.orange[900],
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
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
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orange),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _shareCode,
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text("分享"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _handleCancelCode,
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  label: const Text(
                    "取消產生",
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJoinSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "🧑‍⚕️ 我要查看家人的健康",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Column(
            children: [
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 4,
                decoration: const InputDecoration(
                  hintText: "請輸入邀請碼",
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  counterText: "",
                ),
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleJoinFamily,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("加入家庭成員"),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
