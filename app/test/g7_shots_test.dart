import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/error_log.dart';
import 'package:medlog/ref_data.dart';
import 'package:medlog/score_engine.dart';
import 'package:medlog/screens_ai_quality.dart';
import 'package:medlog/screens_calc.dart';
import 'package:medlog/screens_cases.dart';
import 'package:medlog/screens_ref.dart';

import 'g5_test.dart' show boot, push, settle, shot;
import 'lib2_util.dart' show openPage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final lang in ['en', 'ar']) {
    testWidgets('g7 shots $lang', (tester) async {
      await tester.runAsync(() async {
        await RefData.cards();
        await RefData.curriculum();
        await RefData.sources();
        await RefData.privacy();
        await ScoreRepo.load();
      });
      await boot(tester, lang);
      store.settings['folds'] = {'sc_phq9': true};
      await push(tester, const BedsideCardsScreen());
      await shot(tester, 'G7_${lang}_cards');
      final cards = await tester.runAsync(() => RefData.cards());
      await push(tester, CardDetailScreen(card: cards!.firstWhere((c) => c['presentation'] == 'Sepsis')));
      await shot(tester, 'G7_${lang}_card_detail');
      await push(tester, const RotationHubScreen());
      await shot(tester, 'G7_${lang}_rotation');
      await push(tester, const GuidelinesScreen());
      await shot(tester, 'G7_${lang}_guidelines');
      await push(tester, const CalculatorsScreen());
      await tester.enterText(find.byKey(const ValueKey('calc_search')), 'PHQ');
      await settle(tester, 600);
      await shot(tester, 'G7_${lang}_calc_phq');
      await push(tester, const PrivacyPolicyScreen());
      await shot(tester, 'G7_${lang}_privacy');
      ErrorLog.record('Example error for the screenshot', StackTrace.fromString('#0 demo (file.dart:1)'));
      await push(tester, const ErrorLogScreen());
      await shot(tester, 'G7_${lang}_errlog');
      await push(tester, const AiQualityScreen());
      await shot(tester, 'G7_${lang}_aiquality');
      final c = store.cases.values.firstWhere((x) => x.id == 'cA');
      c.d['problemList'] = [
        {'id': 'p1', 'text': 'Acute coronary syndrome', 'status': 'active', 'since': d0()},
        {'id': 'p2', 'text': 'Hypertension', 'status': 'resolved', 'since': d0()},
      ];
      c.d['labs'] = [
        {'id': 'l1', 'test': 'Hb', 'value': 13.0, 'unit': 'g/dL', 'date': '2026-10-01'},
        {'id': 'l2', 'test': 'Hb', 'value': 11.2, 'unit': 'g/dL', 'date': '2026-10-03'},
        {'id': 'l3', 'test': 'Creatinine', 'value': 1.1, 'unit': 'mg/dL', 'date': '2026-10-01'},
        {'id': 'l4', 'test': 'Creatinine', 'value': 1.6, 'unit': 'mg/dL', 'date': '2026-10-03'},
        {'id': 'l5', 'test': 'Creatinine', 'value': 2.2, 'unit': 'mg/dL', 'date': '2026-10-05'},
      ];
      await push(tester, CaseEditorScreen(rec: c));
      await shot(tester, 'G7_${lang}_case_info');
      await openPage(tester, Icons.biotech_outlined);
      await settle(tester, 700);
      await shot(tester, 'G7_${lang}_case_labs');
      await openPage(tester, Icons.psychology_outlined);
      await settle(tester, 700);
      await shot(tester, 'G7_${lang}_case_problems');
    });
  }
}

String d0() => fmtDate(DateTime.now());
