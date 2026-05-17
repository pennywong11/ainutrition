// food_edit_dialog.dart
// 食物詳情 / 編輯對話框，職責：顯示與儲存單筆分析紀錄

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models.dart';
import '../widget_handler.dart';
import 'nutrition_widgets.dart';

// ── 進入點（靜態方法，保持呼叫端整潔）──────────────────────────────────────────

class FoodEditDialog {
  /// 顯示詳情對話框，並等待關閉
  static Future<void> show(
    BuildContext context, {
    required FoodItem item,
    required DateTime selectedDate,
  }) {
    final w = MediaQuery.of(context).size.width;
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: w > 800 ? 600 : w * 0.9,
          child: FoodEditDialogContent(
            item: item,
            selectedDate: selectedDate,
          ),
        ),
      ),
    );
  }
}

// ── 對話框主體 ────────────────────────────────────────────────────────────────

class FoodEditDialogContent extends StatefulWidget {
  const FoodEditDialogContent({
    super.key,
    required this.item,
    required this.selectedDate,
  });

  final FoodItem item;
  final DateTime selectedDate;

  @override
  State<FoodEditDialogContent> createState() => _FoodEditDialogContentState();
}

class _FoodEditDialogContentState extends State<FoodEditDialogContent> {
  // 文字控制器
  late final TextEditingController _nameController;
  late final TextEditingController _gramController;
  late final TextEditingController _calController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbController;
  late final TextEditingController _fatController;
  late final TextEditingController _remarksController;

  // 食材列表（本地副本，避免直接改原始資料）
  late List<Ingredient> _ingredients;

  // 待刪除的食材 ID（確定送出時才真正刪除）
  final List<String> _ingredientsToDelete = [];

  bool _isEditingName = false;

  static const _mealOptions = ['早餐', '午餐', '晚餐', '點心'];
  String? _selectedMealType;

  // ── 生命週期 ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetHandler.checkInitialRoute();

    _nameController    = TextEditingController(text: widget.item.name);
    _gramController    = TextEditingController();
    _calController     = TextEditingController();
    _proteinController = TextEditingController();
    _carbController    = TextEditingController();
    _fatController     = TextEditingController();
    _remarksController = TextEditingController(text: widget.item.remark);

    _ingredients = widget.item.ingredients.map((e) => e.copy()).toList();
    _recalcTotals();

    if (widget.item.mealType.isNotEmpty &&
        _mealOptions.contains(widget.item.mealType)) {
      _selectedMealType = widget.item.mealType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gramController.dispose();
    _calController.dispose();
    _proteinController.dispose();
    _carbController.dispose();
    _fatController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  // ── 業務邏輯 ────────────────────────────────────────────────────────────────

  /// 重新計算所有非刪除食材的合計，更新對應欄位
  void _recalcTotals() {
    double g = 0, cal = 0, p = 0, c = 0, f = 0;
    for (final ing in _ingredients) {
      if (ing.isDeleted) continue;
      g   += ing.grams;
      cal += ing.calories;
      p   += ing.protein;
      c   += ing.carbs;
      f   += ing.fat;
    }
    _gramController.text    = g.toStringAsFixed(1);
    _calController.text     = cal.toStringAsFixed(0);
    _proteinController.text = p.toStringAsFixed(1);
    _carbController.text    = c.toStringAsFixed(1);
    _fatController.text     = f.toStringAsFixed(1);
  }

  /// 切換食材刪除狀態，並維護待刪清單
  void _toggleIngredient(Ingredient ingredient) {
    setState(() {
      ingredient.isDeleted = !ingredient.isDeleted;
      final id = ingredient.id;
      if (id != null) {
        ingredient.isDeleted
            ? _ingredientsToDelete.add(id)
            : _ingredientsToDelete.remove(id);
      }
      _recalcTotals();
    });
  }

  /// 儲存變更至 Firestore（刪除食材 + 更新主文件）
  Future<void> _save() async {
    final ref = widget.item.reference;
    if (ref == null) return;

    try {
      // 1. 刪除標記的食材子文件
      for (final id in _ingredientsToDelete) {
        await ref.collection('ingredients').doc(id).delete();
      }

      // 2. 更新主文件
      await ref.update({
        '食物名':          _nameController.text,
        '備註':            _remarksController.text,
        'meal_type':      _selectedMealType ?? '',
        'total_calories': double.tryParse(_calController.text)     ?? 0,
        'total_protein':  double.tryParse(_proteinController.text)  ?? 0,
        'total_carbs':    double.tryParse(_carbController.text)     ?? 0,
        'total_fat':      double.tryParse(_fatController.text)      ?? 0,
        'last_updated':   FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('更新失敗: $e');
    }
  }

  // ── 建構 ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildTotalFields(),
          const SizedBox(height: 24),
          _buildIngredientSection(),
          _buildAiSuggestionSection(),
          const SizedBox(height: 24),
          _buildRemarksSection(),
          const SizedBox(height: 24),
          _buildActionButtons(),
        ],
      ),
    );
  }

  // ── 區塊 builders ──────────────────────────────────────────────────────────

  /// 圖片 + 名稱 + 日期 + 餐別選擇
  Widget _buildHeader() {
    return Row(
      children: [
        FoodImage(imagePath: widget.item.imagePath),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildNameRow(),
              const SizedBox(height: 4),
              _buildDateAndMealRow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNameRow() {
    return Row(
      children: [
        Expanded(
          child: _isEditingName
              ? SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '食物名稱',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                )
              : Text(
                  _nameController.text,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        IconButton(
          icon: Icon(
            _isEditingName ? Icons.check : Icons.edit,
            color: Colors.grey[700],
            size: 20,
          ),
          onPressed: () => setState(() => _isEditingName = !_isEditingName),
        ),
      ],
    );
  }

  Widget _buildDateAndMealRow() {
    final d = widget.selectedDate;
    final dateStr =
        '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    return Row(
      children: [
        Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(dateStr,
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(child: _buildMealDropdown()),
      ],
    );
  }

  Widget _buildMealDropdown() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        elevation: 4,
        onSelected: (v) => setState(() => _selectedMealType = v),
        itemBuilder: (_) => _mealOptions
            .map((v) => PopupMenuItem<String>(
                  value: v,
                  height: 40,
                  child: Text(v, style: const TextStyle(fontSize: 13)),
                ))
            .toList(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _selectedMealType ?? '選擇時段',
                style: TextStyle(
                  color: _selectedMealType == null
                      ? Colors.grey[500]
                      : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  /// 克重 + 熱量 + 三大營養素欄位
  Widget _buildTotalFields() {
    const blue  = Color.fromARGB(255, 117, 181, 233);
    const teal  = Color.fromARGB(255, 132, 202, 206);
    const amber = Color.fromARGB(255, 245, 190, 118);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: LabeledTextField(
                  label: '  總克數 (g)', controller: _gramController, enabled: false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LabeledTextField(
                  label: '  熱量 (kcal)', controller: _calController, enabled: false),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LabeledTextField(
                  label: '蛋白質(g)', controller: _proteinController,
                  enabled: false, dotColor: blue),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LabeledTextField(
                  label: '碳水(g)', controller: _carbController,
                  enabled: false, dotColor: teal),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LabeledTextField(
                  label: '脂肪(g)', controller: _fatController,
                  enabled: false, dotColor: amber),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIngredientSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI 總結食材清單',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _ingredients.length,
          itemBuilder: (_, i) => IngredientRow(
            ingredient: _ingredients[i],
            onToggle: () => _toggleIngredient(_ingredients[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildAiSuggestionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI分析建議',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            border: Border.all(color: Colors.black),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.item.aiSuggestion.isEmpty
                ? '暫無 AI 分析建議'
                : widget.item.aiSuggestion,
            style: const TextStyle(
                color: Colors.black87, height: 1.5, fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildRemarksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('備註',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: _remarksController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: '新增備註...',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    const btnStyle = ButtonStyle(
      padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
    );
    const teal = Color.fromARGB(255, 157, 198, 194);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          style: btnStyle.copyWith(
            backgroundColor: const WidgetStatePropertyAll(teal),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () async {
            await _save();
            if (mounted) Navigator.of(context).pop();
          },
          child: const Text('確定'),
        ),
      ],
    );
  }
}