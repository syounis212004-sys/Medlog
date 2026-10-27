import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/choices_engine.dart';
import 'package:medlog/data.dart';
import 'package:medlog/dosing.dart';
import 'package:medlog/quick_add.dart';
import 'package:medlog/screens_calc.dart';
import 'package:medlog/screens_cases.dart';
import 'package:medlog/screens_dosing.dart';
import 'package:medlog/screens_library.dart';
import 'package:medlog/screens_portfolio.dart';

import '../g5_test.dart' show boot, push, settle, shot;

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
  }
  await l.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Tajawal', ['$fd/Tajawal_400Regular.ttf', '$fd/Tajawal_500Medium.ttf', '$fd/Tajawal_700Bold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
    await loadFont('MaterialIcons', ['/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });
  for (final lang in ['en', 'ar']) {
    testWidgets('journey $lang', (tester) async {
      await tester.runAsync(() => ChoicesRepo.load());
      await boot(tester, lang, size: const Size(360, 760));
      await shot(tester, 'J_${lang}_01_home');
      // quick add
      final ctx = tester.element(find.byType(Scaffold).first);
      showQuickAdd(ctx);
      await settle(tester, 900);
      await shot(tester, 'J_${lang}_02_quickadd');
      await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await settle(tester, 500);
      // a case in orthopedics with choices
      final c = store.cases.values.firstWhere((x) => x.id == 'cA');
      c.d['specialty'] = 'Orthopedics';
      c.d['ageGroup'] = 'Child';
      await push(tester, CaseEditorScreen(rec: c));
      await shot(tester, 'J_${lang}_03_case_info');
      final tabs = [Icons.history_edu_outlined, Icons.monitor_heart_outlined, Icons.biotech_outlined, Icons.psychology_outlined, Icons.medication_outlined, Icons.timeline, Icons.school_outlined];
      var n = 4;
      for (final t in tabs) {
        final f = find.byIcon(t);
        if (f.evaluate().isEmpty) continue;
        await tester.tap(f.first);
        await settle(tester, 700);
        await shot(tester, 'J_${lang}_${n.toString().padLeft(2, '0')}_tab${n - 3}');
        n++;
      }
      // doses
      await tester.runAsync(() async {
        await dosing.load();
        await dosing.importFiles(['/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/5954f736-MedLog_Formulary_Part01_v2.json']);
      });
      await push(tester, const DosingScreen());
      await shot(tester, 'J_${lang}_20_doses');
      final amox = dosing.fdrugs.firstWhere((d) => d.id == 'amoxicillin');
      await push(tester, FDrugScreen(drug: amox));
      await shot(tester, 'J_${lang}_21_drug');
      await push(tester, const CalculatorsScreen());
      await shot(tester, 'J_${lang}_22_calcs');
      await push(tester, const PortfolioScreen());
      await shot(tester, 'J_${lang}_23_portfolio');
      await push(tester, const LibraryScreen());
      await shot(tester, 'J_${lang}_24_library');
      await push(tester, const SettingsScreen());
      await shot(tester, 'J_${lang}_25_settings');
    });
  }
}
