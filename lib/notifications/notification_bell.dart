import 'package:flutter/material.dart';
import 'notification_repository.dart';

class NotificationBell extends StatelessWidget {
  final VoidCallback onPressed;

  const NotificationBell({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationRepository.unreadCountStream(),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;

        return Badge(
          isLabelVisible: unread > 0,
          smallSize: 10,                 // 紅點大小
          backgroundColor: Colors.red,
          alignment: Alignment.topRight, // 穩定對齊右上
          offset: const Offset(5, 5),   // 微調位置（不會亂跑）
          child: IconButton(
            icon: const Icon(Icons.notifications_rounded),
            onPressed: onPressed,
          ),
        );
      },
    );
  }
}
