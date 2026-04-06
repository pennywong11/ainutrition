import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 定義一個 Callback，當使用者切換家人時，通知首頁更新
typedef OnFamilySelected = void Function(String uid, String name);

class FamilySwitcher extends StatelessWidget {
  final OnFamilySelected onSelected;
  final String currentName; // 目前正在看誰的資料

  const FamilySwitcher({
    super.key,
    required this.onSelected,
    required this.currentName,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      // 監聽我的使用者資料，看 watching_list 有沒有變動
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Icon(Icons.people_outline);

        final userData = snapshot.data!.data() as Map<String, dynamic>?;
        // 取得關注列表 (如果沒有就給空陣列)
        final List<dynamic> watchingList = userData?['watching_list'] ?? [];

        return PopupMenuButton<String>(
          tooltip: "切換家人視角",
          offset: const Offset(0, 50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_horiz, size: 16, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  currentName, // 顯示目前在看誰
                  style: const TextStyle(
                    color: Colors.teal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          onSelected: (String value) {
            // 🟢 判斷：如果是點擊「家庭設定」，就跳轉頁面
            if (value == 'FAMILY_SETTINGS') {
              Navigator.pushNamed(context, '/family_settings');
              return;
            }

            // 否則執行切換使用者的邏輯
            String selectedName = "我自己";
            if (value != user.uid) {
              // 修正: 增加型別檢查與空值處理，避免 crash
              final target = watchingList.firstWhere(
                (e) => e is Map && e['uid'] == value,
                orElse: () => null,
              );
              if (target != null) selectedName = target['name'] ?? "未知家人";
            }
            // 通知首頁切換
            onSelected(value, selectedName);
          },
          itemBuilder: (BuildContext context) {
            List<PopupMenuEntry<String>> menuItems = [];

            // 1. 選項：我自己
            menuItems.add(
              PopupMenuItem(
                value: user.uid,
                child: const Row(
                  children: [
                    Icon(Icons.person, color: Colors.blue),
                    SizedBox(width: 10),
                    Text("我自己"),
                  ],
                ),
              ),
            );

            // 2. 選項：家人們
            if (watchingList.isNotEmpty) {
              menuItems.add(const PopupMenuDivider());
              for (var member in watchingList) {
                if (member is Map) {
                  menuItems.add(
                    PopupMenuItem(
                      value: member['uid'],
                      child: Row(
                        children: [
                          const Icon(Icons.people_alt, color: Colors.orange),
                          const SizedBox(width: 10),
                          Text(member['name'] ?? "家人"),
                        ],
                      ),
                    ),
                  );
                }
              }
            } else {
              // 🟢 如果沒家人，保留提示文字，讓使用者知道還沒連結
              menuItems.add(const PopupMenuDivider());
              menuItems.add(
                const PopupMenuItem(
                  enabled: false, // 這行只是提示，不能點
                  child: Text(
                    "尚無連結的家人\n請點擊下方設定新增",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              );
            }

            // 🟢 3. 新增：家庭共享設定入口 (現在無論如何都會顯示)
            // 如果上方有列表，加個分隔線
            if (watchingList.isNotEmpty) {
              menuItems.add(const PopupMenuDivider());
            }

            menuItems.add(
              const PopupMenuItem(
                value: 'FAMILY_SETTINGS',
                child: Row(
                  children: [
                    Icon(Icons.settings_accessibility, color: Colors.teal),
                    SizedBox(width: 10),
                    Text("家庭共享設定"),
                  ],
                ),
              ),
            );

            return menuItems;
          },
        );
      },
    );
  }
}
