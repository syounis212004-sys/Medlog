import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/case_scores.dart';
import 'package:medlog/data.dart';
import 'package:medlog/dose_context.dart';
import 'package:medlog/dosing.dart';
import 'package:medlog/formulary.dart';
import 'package:medlog/pdf_export.dart';
import 'package:medlog/screens_calc.dart';
import 'package:medlog/screens_dosing.dart';

import '../g5_test.dart' show boot, push, settle, shot;
import '../lib2_util.dart' show initStoreLight;

const real = '/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/5954f736-MedLog_Formulary_Part01_v2.json';

String ago(int days) => fmtDate(DateTime.now().subtract(Duration(days: days)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dose context from a case', () {
    final c = CaseRec({
      'id': 'a', 'code': 'MED-1', 'ageGroup': 'Adult', 'sex': 'F', 'v_wt': '70 kg',
      'labs': [
        {'id': 'l1', 'test': 'Creatinine', 'value': 1.0, 'unit': 'mg/dL', 'date': ago(5)},
        {'id': 'l2', 'test': 'Creatinine', 'value': 1.8, 'unit': 'mg/dL', 'date': ago(3)},
      ],
    });
    final p = DoseContext.fromCase(c);
    expect(p.weightKg, 70);
    expect(p.creatinineMgDl, 1.8);
    expect(p.creatinineAgeDays, 3);
    expect(p.female, true);
    final cl = p.clearance(ageYears: 60)!;
    expect(cl.method, 'Cockcroft-Gault');
    expect(cl.value, closeTo((80 * 70) / (72 * 1.8) * 0.85, 0.001));
    expect(p.clearance(), isNull); // age missing
    // child: Schwartz needs the height
    final kid = DoseContext.fromCase(CaseRec({'id': 'k', 'ageGroup': 'Child', 'v_wt': '12', 'labs': [{'id': 'l', 'test': 'Cr', 'value': 88.4, 'unit': 'umol/L', 'date': ago(0)}]}));
    expect(kid.creatinineMgDl, closeTo(1.0, 1e-6));
    expect(kid.clearance(ageYears: 5), isNull);
    expect(kid.clearance(ageYears: 5, heightCm: 100)!.value, closeTo(41.3, 0.001));
    expect(DoseContext.fromCase(CaseRec({'id': 'x', 'v_wt': '26 lb'})).weightKg, closeTo(11.79, 0.01));
  });

  test('renal sentences of the real file', () async {
    await initStoreLight();
    await dosing.load();
    await dosing.importFiles([real]);
    final amox = dosing.fdrugs.firstWhere((d) => d.id == 'amoxicillin');
    final r = renalSentences(amox);
    print('amoxicillin renal sentences: ${r.length}; first: ${r.isEmpty ? '-' : r.first}');
    expect(r.isNotEmpty, true);
    var with_ = 0;
    for (final d in dosing.fdrugs) {
      if (renalSentences(d).isNotEmpty) with_++;
    }
    print('drugs with renal sentences: $with_ / ${dosing.fdrugs.length}');
  });

  testWidgets('add a calculator result to a case, see it, and the PDF has it', (tester) async {
    await boot(tester, 'en', size: const Size(412, 892));
    final c = store.cases.values.firstWhere((x) => x.id == 'cA');
    await push(tester, CalculatorsScreen(attachTo: c));
    await tester.tap(find.text('Glasgow Coma Scale (GCS)').first);
    await settle(tester, 700);
    await tester.ensureVisible(find.byKey(const ValueKey('attach_score')).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('attach_score')).first);
    await settle(tester, 600);
    final list = scoresOf(c);
    expect(list.length, 1);
    expect(list.first.name, 'Glasgow Coma Scale (GCS)');
    expect(list.first.items.length, 3);
    expect(list.first.value.startsWith('GCS'), true);
    final pdf = (await tester.runAsync(() => buildCasesPdf([c])))!;
    expect(pdf.length > 1000, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('doses for the patient of a case', (tester) async {
    await boot(tester, 'en', size: const Size(412, 892));
    await tester.runAsync(() async {
      await dosing.load();
      await dosing.importFiles([real]);
    });
    final c = CaseRec({
      'id': 'p', 'code': 'MED-9', 'ageGroup': 'Child', 'sex': 'M', 'v_wt': '12',
      'labs': [{'id': 'l1', 'test': 'Creatinine', 'value': 1.6, 'unit': 'mg/dL', 'date': ago(3)}],
    });
    final amox = dosing.fdrugs.firstWhere((d) => d.id == 'amoxicillin');
    await push(tester, FDrugScreen(drug: amox, patient: DoseContext.fromCase(c)));
    await shot(tester, 'G13_drug_patient');
    expect(find.textContaining('12'), findsWidgets); // weight filled
    // age + height -> kidney function
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '5');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(fields.at(2), '105');
    await settle(tester, 400);
    await shot(tester, 'G13_drug_patient_kidney');
    expect(find.textContaining('Kidney function'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
