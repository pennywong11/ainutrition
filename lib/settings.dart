// settings.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

final user = FirebaseAuth.instance.currentUser;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // UI-only states
  bool notifications = true;
  bool darkPreview = false;
  String displayName = '';
  String preferredUnit = 'metric';

  String? gender;
  int? age;
  double? height;
  double? weight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primaryDeep = cs.primary;
    //final primaryLight = cs.surface;
    final primaryLight = cs.background;

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Card
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
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: primaryLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: primaryDeep.withOpacity(0.2)),
                      ),
                      child: Icon(Icons.person, size: 38, color: primaryDeep),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName.isEmpty ? '使用者名稱' : displayName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ' user@example.com',
                            style: TextStyle(color: cs.onSurface.withOpacity(0.7)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '✎修改密碼',
                            style: TextStyle(color: cs.onSurface.withOpacity(0.5)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                '個人健康資料',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _sectionLabel('性別'),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            value: 'male',
                            groupValue: gender,
                            onChanged: (v) => setState(() => gender = v),
                            title: const Text('男'),
                            activeColor: primaryDeep,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            value: 'female',
                            groupValue: gender,
                            onChanged: (v) => setState(() => gender = v),
                            title: const Text('女'),
                            activeColor: primaryDeep,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    _sectionLabel('年齡'),
                    TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '請輸入年齡'),
                      onChanged: (v) => setState(() => age = int.tryParse(v)),
                    ),
                    const SizedBox(height: 16),

                    _sectionLabel('身高 (cm)'),
                    TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '請輸入身高'),
                      onChanged: (v) => setState(() => height = double.tryParse(v)),
                    ),
                    const SizedBox(height: 16),

                    _sectionLabel('體重 (kg)'),
                    TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '請輸入體重'),
                      onChanged: (v) => setState(() => weight = double.tryParse(v)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryDeep,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('已儲存健康資料（示範）')));
                      },
                      child: const Text('儲存設定'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              _sectionTitle('應用資訊'),
              _infoRow('版本', '1.0.0'),
              _infoRow('條款', '隱私權政策與使用條款'),

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryDeep,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('已儲存設定（模擬）')));
                      },
                      child: const Text('儲存設定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ===== UI Components =====
  Widget _sectionLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _infoRow(String title, String value) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(value, style: TextStyle(color: cs.primary)),
        ],
      ),
    );
  }
}
