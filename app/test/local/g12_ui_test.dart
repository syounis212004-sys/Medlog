import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/dosing.dart';
import 'package:medlog/screens_dosing.dart';

import '../g5_test.dart' show boot, push, settle, shot;

const real = '/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/5954f736-MedLog_Formulary_Part01_v2.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final lang in ['en', 'ar']) {
    testWidgets('formulary ui $lang', (tester) async {
      await boot(tester, lang);
      await tester.runAsync(() async {
        await dosing.load();
        await dosing.importFiles([real]);
      });
      await push(tester, const DosingScreen());
      await shot(tester, 'G12_${lang}_list');
      final epi = dosing.fdrugs.firstWhere((d) => d.id == 'epinephrine');
      await push(tester, FDrugScreen(drug: epi));
      await shot(tester, 'G12_${lang}_drug');
      await tester.enterText(find.byType(TextField).first, '10');
      await settle(tester, 300);
      await shot(tester, 'G12_${lang}_unapproved');
      await tester.tap(find.byIcon(Icons.fact_check_outlined).first);
      await settle(tester, 500);
      await shot(tester, 'G12_${lang}_review');
      await tester.tap(find.byType(Checkbox).first);
      await settle(tester, 300);
      await tester.tap(find.byType(FilledButton).last);
      await settle(tester, 600);
      await shot(tester, 'G12_${lang}_result');
      expect(store.settings['formApprove'] is Map, true);
      expect(tester.takeException(), isNull);
    });
  }
}
