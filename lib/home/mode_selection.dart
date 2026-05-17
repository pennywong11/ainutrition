import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_mode.dart';

// import 'home_page.dart';
import 'home_simple.dart';
import '../history_page.dart';

class ModeSelection extends StatelessWidget {
  const ModeSelection({super.key});

  @override
  Widget build(BuildContext context) {
    final isSimple = context.watch<AppMode>().isSimple;

    return isSimple
        ? const HomeSimple()
        : const NutritionHomePage();
  }
}