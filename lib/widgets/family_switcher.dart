import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/family_service.dart';

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
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        // 如果還在載入中，顯示一個預設的人形符號
        if (!snapshot.hasData)
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.people_outline, color: Colors.grey),
          );

        final userData = snapshot.data!.data() as Map<String, dynamic>?;
        final List<dynamic> watchingList = userData?['watching_list'] ?? [];

        return PopupMenuButton<String>(
          tooltip: "切換視角 (目前: $currentName)",
          offset: const Offset(0, 50),
          // 🟢 核心修改：將圖示顏色改為與通知一致的灰色 (Colors.grey)
          icon: const Icon(
            Icons.supervisor_account_outlined,
            color: Colors.white,
            size: 26,
          ),
          onSelected: (String value) {
            if (value == 'FAMILY_SETTINGS') {
              Navigator.pushNamed(context, '/family_settings');
              return;
            }

            String selectedName = "我自己";
            if (value != user.uid) {
              final target = watchingList.firstWhere(
                (e) => e is Map && e['uid'] == value,
                orElse: () => null,
              );
              if (target != null) selectedName = target['name'] ?? "未知家人";
            }
            onSelected(value, selectedName);
          },
          itemBuilder: (BuildContext context) {
            List<PopupMenuEntry<String>> menuItems = [];

            // 1. 選項：我自己
            menuItems.add(
              PopupMenuItem(
                value: user.uid,
                child: Row(
                  children: [
                    Icon(
                      Icons.person,
                      color: currentName == "我自己" ? Colors.teal : Colors.blue,
                    ),
                    const SizedBox(width: 10),
                    // 🟢 核心修改：移除粗體字樣式
                    const Text(
                      "我自己",
                      style: TextStyle(fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
              ),
            );

            // 2. 選項：家人們
            if (watchingList.isNotEmpty) {
              menuItems.add(const PopupMenuDivider());
              for (var member in watchingList) {
                if (member is Map) {
                  final bool isCurrent = currentName == (member['name'] ?? "");
                  menuItems.add(
                    PopupMenuItem(
                      value: member['uid'],
                      child: Row(
                        children: [
                          Icon(
                            Icons.people_alt,
                            color: isCurrent ? Colors.teal : Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          // 🟢 核心修改：移除粗體字樣式
                          Text(
                            member['name'] ?? "家人",
                            style: const TextStyle(
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
              }
            } else {
              menuItems.add(const PopupMenuDivider());
              menuItems.add(
                const PopupMenuItem(
                  enabled: false,
                  child: Text(
                    "尚無連結的家人\n請點擊下方設定新增",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              );
            }

            // 3. 家庭共享設定入口
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
