// nutrition_widgets.dart
// 純顯示型 Widget，無業務邏輯依賴，可跨頁面重用

import 'package:flutter/material.dart';
import 'dart:convert';
import 'nutrition_helpers.dart';
import '../models.dart';

// ── 圖片 ──────────────────────────────────────────────────────────────────────

/// 通用食物縮圖：支援 base64、http URL，fallback 為佔位圖示
class FoodImage extends StatelessWidget {
  const FoodImage({
    super.key,
    required this.imagePath,
    this.size = 60,
    this.borderRadius = 8,
  });

  final String imagePath;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: Colors.grey[200],
        child: _resolveImage(),
      ),
    );
  }

  Widget _resolveImage() {
    // base64（前綴 data:image 或超長字串）
    if (imagePath.startsWith('data:image') ||
        (imagePath.length > 1000 && !imagePath.startsWith('http'))) {
      try {
        final data = base64Decode(
          imagePath.replaceFirst('data:image/jpeg;base64,', ''),
        );
        return Image.memory(data,
            fit: BoxFit.cover, width: size, height: size);
      } catch (_) {
        return _placeholder();
      }
    }

    // 網路圖片
    if (imagePath.startsWith('http')) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() =>
      const Icon(Icons.restaurant, color: Colors.grey);
}

// ── 進度條 ────────────────────────────────────────────────────────────────────

/// 單條營養素進度條（標籤 + 條形 + 百分比）
class NutrientBar extends StatelessWidget {
  const NutrientBar({
    super.key,
    required this.label,
    required this.color,
    required this.percentage, // 0.0 ~ 1.0（會自動 clamp）
  });

  final String label;
  final Color  color;
  final double percentage;

  @override
  Widget build(BuildContext context) {
    final clamped = percentage.clamp(0.0, 1.0);
    final pctText = '${(percentage * 100).toStringAsFixed(0)}%';
    final textColor = percentage >= 1.0 ? Colors.red : Colors.black54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: clamped,
                  minHeight: 15,
                  backgroundColor: Colors.grey[300],
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(pctText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                )),
          ],
        ),
      ],
    );
  }
}

// ── 餐別 Icon ─────────────────────────────────────────────────────────────────

/// 根據餐別顯示帶色背景圓形 Icon；未知餐別回傳空 widget
class MealTypeIcon extends StatelessWidget {
  const MealTypeIcon(this.mealType, {super.key});

  final String mealType;

  @override
  Widget build(BuildContext context) {
    final meta = kMealMeta[mealType];
    if (meta == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: meta.color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(meta.icon, size: 20, color: meta.color),
    );
  }
}

// ── 提示 Tooltip ──────────────────────────────────────────────────────────────

/// 帶說明文字的 info 圓形 icon
class InfoTooltip extends StatelessWidget {
  const InfoTooltip({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      preferBelow: false,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      verticalOffset: 12,
      showDuration: const Duration(seconds: 3),
      decoration: BoxDecoration(
        color: Colors.grey[600]?.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      child: Transform.translate(
        offset: const Offset(0, 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.info_outline_rounded,
              size: 18, color: Colors.grey[600]),
        ),
      ),
    );
  }
}

// ── 容器裝飾 ──────────────────────────────────────────────────────────────────

/// 白底 + 圓角 + 陰影的通用卡片容器
class ShadowCard extends StatelessWidget {
  const ShadowCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── 食材列表 (詳情對話框用) ────────────────────────────────────────────────────

/// 單一大量營養素顯示（圓點 + 數值）
class MacroChip extends StatelessWidget {
  const MacroChip({
    super.key,
    required this.color,
    required this.value,
  });

  final Color  color;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 16, color: color),
        const SizedBox(width: 4),
        Text('${value.toStringAsFixed(1)}g',
            style: TextStyle(
              color: Colors.grey[800],
              fontWeight: FontWeight.w500,
              fontSize: 14,
            )),
      ],
    );
  }
}

/// 帶刪除/復原按鈕的食材列項
class IngredientRow extends StatelessWidget {
  const IngredientRow({
    super.key,
    required this.ingredient,
    required this.onToggle,
  });

  final Ingredient ingredient;
  final VoidCallback onToggle;

  static const _blue   = Color.fromARGB(255, 117, 181, 233);
  static const _teal   = Color.fromARGB(255, 132, 202, 206);
  static const _amber  = Color.fromARGB(255, 245, 190, 118);

  @override
  Widget build(BuildContext context) {
    final deleted = ingredient.isDeleted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: deleted ? Colors.grey[200] : const Color(0xFFF5F9F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: deleted ? Colors.grey[200]! : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 名稱 + 刪除/復原
            Row(
              children: [
                Expanded(
                  child: Text(
                    ingredient.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: deleted ? Colors.grey[400] : Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    deleted
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline,
                    color: deleted ? Colors.teal : Colors.red[300],
                    size: 24,
                  ),
                  onPressed: onToggle,
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 克重 + 熱量
            Text(
              '${ingredient.grams} g • ${ingredient.calories} kcal',
              style: TextStyle(
                fontSize: 14,
                color: deleted ? Colors.grey[300] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),

            // 三大營養素
            Opacity(
              opacity: deleted ? 0.3 : 1.0,
              child: Row(
                children: [
                  MacroChip(color: _blue,  value: ingredient.protein),
                  const SizedBox(width: 16),
                  MacroChip(color: _teal,  value: ingredient.carbs),
                  const SizedBox(width: 16),
                  MacroChip(color: _amber, value: ingredient.fat),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 文字輸入欄位 (詳情對話框用) ───────────────────────────────────────────────

/// 帶標籤（與可選彩色圓點）的單一文字欄位
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.number,
    this.enabled = true,
    this.backgroundColor,
    this.dotColor,
  });

  final String               label;
  final TextEditingController controller;
  final TextInputType         keyboardType;
  final bool                  enabled;
  final Color?                backgroundColor;
  final Color?                dotColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標籤列（可選圓點）
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 11.5)),
          ],
        ),
        const SizedBox(height: 8),

        // 輸入框
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            enabled: enabled,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: '0',
              filled: !enabled || backgroundColor != null,
              fillColor: enabled
                  ? (backgroundColor ?? Colors.transparent)
                  : (backgroundColor ?? Colors.grey[200]),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 今日紀錄列表 ──────────────────────────────────────────────────────────────
//
// 使用方式：
//   DailyFoodList(
//     isLoading: _isLoading,
//     foodList:  _foodList,
//     onTapItem: (item) => FoodEditDialog.show(context, item: item, selectedDate: _selectedDate),
//     onDeleteItem: _confirmDelete,
//   )

/// 確認刪除 dialog（靜態工具，不依賴任何頁面狀態）
class ConfirmDeleteDialog {
  static Future<void> show(BuildContext context, FoodItem item) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除'),
        content: Text('您確定要永久刪除「${item.name}」嗎？'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: const Text('確認'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await item.reference?.delete();
              } catch (e) {
                debugPrint('刪除失敗: $e');
              }
            },
          ),
        ],
      ),
    );
  }
}

/// 今日食物紀錄列表卡片
///
/// - [isLoading]    資料載入中時顯示 loading indicator
/// - [foodList]     食物列表
/// - [onTapItem]    點擊單筆時的行為（由呼叫端決定，例如開編輯 dialog）
/// - [onDeleteItem] 點擊刪除時的行為（由呼叫端決定，通常呼叫 ConfirmDeleteDialog.show）
/// - [isReadOnly]    是否為唯讀模式（預設 false，向下相容），true 時隱藏刪除按鈕
class DailyFoodList extends StatelessWidget {
  const DailyFoodList({
    super.key,
    required this.isLoading,
    required this.foodList,
    required this.onTapItem,
    required this.onDeleteItem,
    this.isReadOnly = false, // 🟢 新增，預設 false 向下相容
  });

  final bool                    isLoading;
  final List<FoodItem>          foodList;
  final void Function(FoodItem) onTapItem;
  final void Function(FoodItem) onDeleteItem;
  final bool                    isReadOnly; // 🟢 新增

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 5,
      shadowColor: Colors.grey.withOpacity(0.5),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('今日紀錄',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const Divider(),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (foodList.isEmpty) return const Center(child: Text('目前尚無餐點分析紀錄！'));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      itemCount: foodList.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _FoodListTile(
          item:       foodList[i],
          onTap:      () => onTapItem(foodList[i]),
          onDelete:   () => onDeleteItem(foodList[i]),
          isReadOnly: isReadOnly, 
        ),
      ),
    );
  }
}

class _FoodListTile extends StatelessWidget {
  const _FoodListTile({
    required this.item,
    required this.onTap,
    required this.onDelete,
    this.isReadOnly = false, 
  });

  final FoodItem     item;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool         isReadOnly; 

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (item.mealType.isNotEmpty) MealTypeIcon(item.mealType),
            FoodImage(imagePath: item.imagePath),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                  Text(item.calories,
                      style: const TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
            ),
            // 唯讀時不顯示刪除按鈕
            if (!isReadOnly)
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Color.fromARGB(255, 26, 24, 23)),
                  onPressed: onDelete,
                ),
              ),
          ],
        ),
      ),
    );
  }
}