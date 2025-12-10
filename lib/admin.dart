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
  List<dynamic> filteredUsers = [];

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // 搜尋 + 過濾
  final TextEditingController searchController = TextEditingController();
  bool filterAdmin = false;
  bool filterAnonymous = false;

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
      users = data["users"];
      _applyFilters();
    }
  }

  void _applyFilters() {
    final keyword = searchController.text.trim().toLowerCase();
    filteredUsers = users.where((u) {
      final email = (u["email"] ?? "").toLowerCase();
      final uid = (u["uid"] ?? "").toLowerCase();
      bool matchKeyword =
          keyword.isEmpty || email.contains(keyword) || uid.contains(keyword);
      bool matchAdmin = !filterAdmin || (u["admin"] == true);
      bool matchAnon = !filterAnonymous || (u["email"] == null);
      return matchKeyword && matchAdmin && matchAnon;
    }).toList();
    setState(() {});
  }

  Future<void> _createUser(String email, String password) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (token == null) return;

    final resp = await http.post(
      Uri.parse("$apiBaseUrl/admin/create_user"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"email": email, "password": password}),
    );

    if (resp.statusCode == 200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("成功新增使用者 $email")));
      _getUsers();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("新增失敗：${resp.body}")));
      print("Create user failed: ${resp.statusCode} - ${resp.body}");
    }
  }

  void _showCreateUserDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text("新增使用者"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: "Email",
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text("取消"),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
              child: const Text("新增"),
              onPressed: () async {
                final email = emailController.text.trim();
                final password = passwordController.text.trim();
                if (email.isEmpty || password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Email 與 Password 不可為空")),
                  );
                  return;
                }
                Navigator.pop(context);
                await _createUser(email, password);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> deleteUser(String uid) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("確認刪除"),
          content: Text("確定要刪除使用者：$uid 嗎？此動作無法復原。"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("取消"),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 233, 98, 88),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("刪除"),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (token == null) return;

    final resp = await http.delete(
      Uri.parse("$apiBaseUrl/admin/delete_user/$uid"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (resp.statusCode == 200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("已刪除使用者：$uid")));
      _getUsers();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("刪除失敗")));
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
      appBar: AppBar(title: const Text("管理後台")),
      body: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            _buildSearchBar(cs),
            const SizedBox(height: 12),
            Expanded(child: _buildUserListWithDetails(cs)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateUserDialog,
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: searchController,
          onChanged: (_) => _applyFilters(),
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.surfaceVariant,
            hintText: "搜尋 Email / UID",
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceVariant,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people, size: 18),
                  const SizedBox(width: 6),
                  Text("使用者總數：${users.length}"),
                ],
              ),
            ),
            FilterChip(
              label: const Text("管理員"),
              selected: filterAdmin,
              onSelected: (v) {
                setState(() {
                  filterAdmin = v;
                  _applyFilters();
                });
              },
            ),
            FilterChip(
              label: const Text("匿名用戶"),
              selected: filterAnonymous,
              onSelected: (v) {
                setState(() {
                  filterAnonymous = v;
                  _applyFilters();
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUserListWithDetails(ColorScheme cs) {
    return ListView.separated(
      itemCount: filteredUsers.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final u = filteredUsers[index];
        final meta = u["metadata"] ?? {};
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cs.primary,
                    child: Text(
                      (u["email"] ?? "?")[0].toUpperCase(),
                      style: TextStyle(color: cs.onPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u["email"] ?? "匿名用戶",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        Text("UID: ${u["uid"]}"),
                      ],
                    ),
                  ),
                  if (u["admin"] == true)
                    const Icon(Icons.star, color: Colors.orange),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => deleteUser(u["uid"]),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                  "Email 驗證：${u["email_verified"]} | 註冊時間：${meta["creation_time"] != null ? DateFormat('yyyy/MM/dd').format(DateTime.fromMillisecondsSinceEpoch(meta["creation_time"])) : "未知"} | 最後登入：${meta["last_sign_in_time"] != null ? DateFormat('yyyy/MM/dd').format(DateTime.fromMillisecondsSinceEpoch(meta["last_sign_in_time"])) : "未知"}"),
            ],
          ),
        );
      },
    );
  }
}
