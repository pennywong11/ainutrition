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
  // 詳細資料顯示
  final Map<String, Map<String, dynamic>> userDetails = {};
  final Set<String> loadingDetailUids = {};
  final Set<String> expandedUids = {};

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // 搜尋 / 篩選
  final TextEditingController searchController = TextEditingController();
  bool filterAdmin = false;
  bool filterNormal = false;
  bool filterAnonymous = false;
  // 批次選取
  final Set<String> selectedUids = {};
  bool get isAllSelected =>
      filteredUsers.isNotEmpty &&
      selectedUids.length == filteredUsers.length;

  // 初始化並檢查是否為管理員
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
    final token = await user.getIdToken(true);

    final resp = await http.get(
      Uri.parse("$apiBaseUrl/admin/verify_admin"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (resp.statusCode == 200) {
      setState(() => isAdmin = true);
      _getUsers();
    } else {
      setState(() => isAdmin = false);
    }
  }

  // 取得使用者列表
  Future<void> _getUsers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/admin/get_users"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (resp.statusCode == 200) {
      users = jsonDecode(resp.body)["users"];
      _applyFilters();
    }
  }

  // 取得使用者詳細資料
  Future<void> _loadUserDetail(String uid) async {
    if (userDetails.containsKey(uid)) return; // 已載入過
    if (loadingDetailUids.contains(uid)) return;

    loadingDetailUids.add(uid);
    setState(() {});

    final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (token == null) return;

    final resp = await http.get(
      Uri.parse("$apiBaseUrl/admin/get_user/$uid"),
      headers: {"Authorization": "Bearer $token"},
    );

    loadingDetailUids.remove(uid);

    if (resp.statusCode == 200) {
      userDetails[uid] = jsonDecode(resp.body);
    }

    setState(() {});
  }

  // OR 篩選邏輯
  void _applyFilters() {
    final keyword = searchController.text.trim().toLowerCase();

    filteredUsers = users.where((u) {
      final email = (u["email"] ?? "").toLowerCase();
      final uid = (u["uid"] ?? "").toLowerCase();

      bool matchKeyword =
          keyword.isEmpty || email.contains(keyword) || uid.contains(keyword);
      if (!matchKeyword) return false;

      final isAdminUser = u["admin"] == true;
      final isAnonymous = u["email"] == null;
      final isNormal = !isAdminUser && !isAnonymous;

      if (!filterAdmin && !filterNormal && !filterAnonymous) return true;

      return (filterAdmin && isAdminUser) ||
          (filterNormal && isNormal) ||
          (filterAnonymous && isAnonymous);
    }).toList();

    // 移除不在篩選結果中的已選 UID
    /*
    selectedUids.removeWhere(
      (uid) => !filteredUsers.any((u) => u["uid"] == uid),
    );*/

    setState(() {});
  }

  // 新增使用者
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("成功新增使用者${email}")));

      _getUsers(); // 🔵 自動刷新列表
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("新增失敗：${resp.body}")));
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

                Navigator.pop(context); // 關閉彈窗

                await _createUser(email, password);
              },
            ),
          ],
        );
      },
    );
  }

  // 刪除使用者
  Future<void> deleteUser(String uid) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("確認刪除"),
        content: Text("確定要刪除使用者：$uid ？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("刪除", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (token == null) return;

    final resp = await http.delete(
      Uri.parse("$apiBaseUrl/admin/delete_user/$uid"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (resp.statusCode == 200) {
      _getUsers();
    }
  }

  // 刪除多個使用者
  Future<void> deleteSelectedUsers() async {
    if (selectedUids.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text("確定要刪除 ${selectedUids.length} 位使用者？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("刪除", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (token == null) return;

    final resp = await http.delete(
      Uri.parse("$apiBaseUrl/admin/delete_users"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"uids": selectedUids.toList()}),
    );

    if (resp.statusCode == 200) {
      selectedUids.clear();
      _getUsers();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("批次刪除失敗：${resp.body}")));
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
      body: Row(
        children: [
          _buildSidebar(cs),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildSearchBar(cs),
                  const SizedBox(height: 12),
                  Expanded(child: _buildUserList(cs)),
                ],
              ),
            ),
          ),
        ],
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
            hintText: "搜尋 Email / UID",
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: cs.surfaceVariant,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // 總/已選使用者數
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
                  //Text("使用者總數：${users.length}"),
                  Text("${filteredUsers.length}"),
                ],
              ),
            ),
            if (selectedUids.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 6),
                    Text("已選取：${selectedUids.length}"),
                  ],
                ),
              ),
            // 全選
            FilterChip(
              label: Text(isAllSelected ? "取消全選" : "全選"),
              selected: isAllSelected,
              onSelected: (_) {
                setState(() {
                  if (isAllSelected) {
                    selectedUids.clear();
                  } else {
                    selectedUids
                      ..clear()
                      ..addAll(filteredUsers.map((u) => u["uid"]));
                  }
                });
              },
            ),
            FilterChip(
              label: const Text("管理員"),
              selected: filterAdmin,
              onSelected: (v) => setState(() {
                filterAdmin = v;
                _applyFilters();
              }),
            ),
            FilterChip(
              label: const Text("一般使用者"),
              selected: filterNormal,
              onSelected: (v) => setState(() {
                filterNormal = v;
                _applyFilters();
              }),
            ),
            FilterChip(
              label: const Text("匿名用戶"),
              selected: filterAnonymous,
              onSelected: (v) => setState(() {
                filterAnonymous = v;
                _applyFilters();
              }),
            ),
            // 批次刪除按鈕
            if (selectedUids.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.delete, color: Colors.white),
                label: Text("刪除 (${selectedUids.length})"),
                backgroundColor: Colors.red,
                labelStyle: const TextStyle(color: Colors.white),
                onPressed: deleteSelectedUsers,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildUserList(ColorScheme cs) {
    return ListView.separated(
      itemCount: filteredUsers.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, i) {
        final u = filteredUsers[i];
        final uid = u["uid"];
        final isExpanded = expandedUids.contains(uid);
        final detail = userDetails[uid];
        final isLoading = loadingDetailUids.contains(uid);

        return GestureDetector(
          onTap: () async {
            setState(() {
              if (isExpanded) {
                expandedUids.remove(uid);
              } else {
                expandedUids.add(uid);
              }
            });

            if (!userDetails.containsKey(uid)) {
              await _loadUserDetail(uid);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: selectedUids.contains(uid),
                      onChanged: (v) {
                        setState(() {
                          v == true
                              ? selectedUids.add(uid)
                              : selectedUids.remove(uid);
                        });
                      },
                    ),
                    const SizedBox(width: 12),
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  u["email"] ?? "匿名用戶",
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (u["admin"] == true)
                                const Icon(Icons.star, color: Colors.orange, size: 18,), 
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "UID：${u["uid"]}",
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // 展開區
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : detail == null
                            ? const Text("載入失敗")
                            : _buildUserDetail(detail),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserDetail(Map<String, dynamic> d) {
    final meta = d["metadata"] ?? {};

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 8),
      child:Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Email 驗證：${d["email_verified"]}"),
          Text("管理員：${d["admin"]}"),
          Text(
            "註冊時間：${meta["creation_time"] != null
                ? DateFormat('yyyy/MM/dd').format(
                    DateTime.fromMillisecondsSinceEpoch(meta["creation_time"]),
                  )
                : "未知"}",
          ),
          Text(
            "最後登入：${meta["last_sign_in_time"] != null
                ? DateFormat('yyyy/MM/dd').format(
                    DateTime.fromMillisecondsSinceEpoch(meta["last_sign_in_time"]),
                  )
                : "未知"}",
          ),
        ],
      ),
    );
  }

  Widget _adminInfo(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: cs.primary,
            child: Icon(Icons.person, color: cs.onPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "管理員",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  adminEmail ?? "unknown",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 左側工具列
  Widget _buildSidebar(ColorScheme cs) {
    return SizedBox(
      width: 260,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _adminInfo(cs),

            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _toolButton(
                      icon: Icons.person_add,
                      label: "新增使用者",
                      cs: cs,
                      onTap: () {
                        _showCreateUserDialog();
                      },
                    ),
                    const SizedBox(height: 12),

                    /*_toolButton(
                      icon: Icons.admin_panel_settings,
                      label: "設定管理員",
                      cs: cs,
                      onTap: () {
                        // TODO: push route
                      },
                    ),
                    const SizedBox(height: 12),

                    _toolButton(
                      icon: Icons.group_add,
                      label: "新增管理員",
                      cs: cs,
                      onTap: () {
                        // TODO: push route
                      },
                    ),*/
                  ],
                ),
              ),
            ),

            // 固定：登出按鈕（不會捲動，貼在底部）
            TextButton.icon(
              onPressed: () async {
                try {
                  // 嘗試登出 Firebase
                  await FirebaseAuth.instance.signOut();
                  setState(() {isAdmin = false;});
                  if (mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      "/auth",
                      (_) => false,
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('登出失敗：$e')));
                  print('登出失敗：$e');
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text("登出"),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ],
        ), 
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required ColorScheme cs,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: cs.background.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
          //border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
