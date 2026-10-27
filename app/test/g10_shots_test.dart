import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/choices_engine.dart';
import 'package:medlog/data.dart';
import 'package:medlog/screens_cases.dart';

import 'g5_test.dart' show boot, push, settle, shot;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final lang in ['en', 'ar']) {
    testWidgets('choices ui $lang', (tester) async {
      await tester.runAsync(() => ChoicesRepo.load());
      await boot(tester, lang);
      final c = store.cases.values.firstWhere((x) => x.id == 'cA');
      c.d['specialty'] = 'Orthopedics';
      await push(tester, CaseEditorScreen(rec: c));
      await tester.tap(find.byIcon(Icons.history_edu_outlined).first);
      await settle(tester, 700);
      await shot(tester, 'G10_${lang}_hist0');
      final elbow = find.text('Elbow');
      if (elbow.evaluate().isNotEmpty) {
        await tester.tap(elbow.first);
        await settle(tester, 500);
        await shot(tester, 'G10_${lang}_hist_elbow');
        await tester.tap(find.text('Injury').first);
        await settle(tester, 500);
        await tester.drag(find.byType(ListView).first, const Offset(0, -300));
        await settle(tester, 500);
        await shot(tester, 'G10_${lang}_hist_injury');
      }
      final cc = CaseChoices(c);
      final t = cc.template()!;
      var res = cc.resolve(t);
      cc.toggle(t, t.step('problem')!, res['problem']!, 'Injury');
      res = cc.resolve(t);
      cc.toggle(t, t.step('assessment')!, res['assessment']!, res['assessment']!.first.v);
      cc.toggle(t, t.step('diagnostic_certainty')!, res['diagnostic_certainty']!, 'Confirmed');
      ChoicesSync.derive(c, (k, v) => c.set(k, v));
      await tester.tap(find.byIcon(Icons.psychology_outlined).first);
      await settle(tester, 700);
      await shot(tester, 'G10_${lang}_assess');
      await tester.tap(find.byIcon(Icons.medication_outlined).first);
      await settle(tester, 500);
      await shot(tester, 'G10_${lang}_mgmt');
      expect(tester.takeException(), isNull);
      final saved = jsonDecode(jsonEncode(c.d['choices'])) as Map;
      print('saved: ${jsonEncode(saved)}');
    });
  }
}
