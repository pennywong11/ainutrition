// lib/admin.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  bool? isAdmin;
  String? adminEmail;
  List<dynamic> users = [];

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  @override
  void initState() {
    super.initState();
    checkAdmin();
  }

  Future<void> checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() => isAdmin = false);
      return;
    }

    adminEmail = user.email;

    await user.getIdToken(true);
    final token = await user.getIdToken();

    final response = await http.get(
      Uri.parse("$apiBaseUrl/admin/verify_admin"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      setState(() => isAdmin = true);
      _getUsers();
    } else {
      setState(() => isAdmin = false);
    }
  }

  Future<void> _getUsers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final response = await http.get(
      Uri.parse("$apiBaseUrl/admin/get_users"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() => users = data["users"]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isAdmin == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (isAdmin == false) {
      Future.microtask(() {
        Navigator.pushReplacementNamed(context, "/");
      });
      return const Scaffold();
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.primary,
      /*appBar: AppBar(
        title: Text("管理頁（${adminEmail ?? ''}）"),
        centerTitle: true,
      ),*/
      body: Row(
        children: [
          // -----------------------------------------
          // 左側 : Sidebar（固定 + 可滾動）
          // -----------------------------------------
          SizedBox(
            width: 260,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                //color: cs.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 固定：管理員資訊卡片（頂端）
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.onPrimary.withOpacity(0.2)),
                          ),
                          child: Icon(Icons.person, color: cs.onPrimary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("管理員", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Text(adminEmail ?? "unknown", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 中段：可滾動區（Expanded 會撐滿高度，裡面用 SingleChildScrollView）
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _statCard("使用者總數", "${users.length}", Icons.people, cs),
                          const SizedBox(height: 14),
                          _statCard("上傳數", "5,678", Icons.upload_file, cs),
                          const SizedBox(height: 14),
                          _statCard("活躍日", "87%", Icons.show_chart, cs),
                          const SizedBox(height: 14),
                          _statCard("錯誤回報", "3", Icons.bug_report, cs),
                          const SizedBox(height: 12),
                          // 可根據需要再放更多項目（會出現滾動）
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 固定：登出按鈕（不會捲動，貼在底部）
                  TextButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (mounted) {
                        Navigator.pushNamedAndRemoveUntil(context, "/login", (_) => false);
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text("登出"),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
          ),


          // -----------------------------------------
          // 右側：使用者列表（可滾動）
          // -----------------------------------------
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '所有使用者',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (context, index) {
                        final u = users[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: cs.primary,
                            child: Text(
                              u["email"] != null
                                  ? u["email"][0].toUpperCase()
                                  : "?",
                              style: TextStyle(color: cs.onPrimary),
                            ),
                          ),
                          title: Text(u["email"] ?? "無 email"),
                          subtitle: Text("UID: ${u["uid"]}"),
                          onTap: () => _showUserDetail(context, u["uid"]),
                          trailing: Icon(Icons.chevron_right, color: cs.primary),
                        );
                      },
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

  // ---------------------------
  // 統計卡片
  // ---------------------------
  Widget _statCard(String title, String value, IconData icon, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: cs.onPrimary),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // 使用者詳細資料
  // ---------------------------
  void _showUserDetail(BuildContext context, String uid) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (token == null) return;

    final resp = await http.get(
      Uri.parse("$apiBaseUrl/admin/get_user/$uid"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (resp.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("取得使用者資料失敗")),
      );
      return;
    }

    final user = jsonDecode(resp.body);

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("使用者詳細資料"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Email：${user["email"] ?? "無"}"),
              Text("UID：${user["uid"]}"),
              Text("權限：admin = ${user["admin"]}"),
              Text("email 驗證：${user["email_verified"]}"),
              const SizedBox(height: 10),
              Text(
                "註冊時間：${DateFormat('yyyy/MM/dd').format(
                  DateTime.fromMillisecondsSinceEpoch(user["metadata"]["creation_time"])
                )}"
              ),
              Text(
                "最後登入：${DateFormat('yyyy/MM/dd').format(
                  DateTime.fromMillisecondsSinceEpoch(user["metadata"]["last_sign_in_time"])
                )}"
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("關閉"),
            ),
          ],
        );
      },
    );
  }
}
