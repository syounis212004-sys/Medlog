import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart';
import 'package:medlog/pdf_export.dart';
import 'package:medlog/screens_cases.dart';
import 'package:medlog/screens_notebooks.dart';
import 'package:flutter/material.dart';
import 'quickfill_test.dart' show boot, settle, shot, shotKey;

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
  }
  await l.load();
}

List<CaseRec> sample() {
  final base = {
    'schema': 2, 'date': '2026-10-10', 'specialty': 'Internal Medicine', 'ageGroup': 'Adult', 'sex': 'Male',
    'status': 'Active', 'setting': 'ER', 'role': 'Assisted', 'encounter': 'New admission',
  };
  return [
    CaseRec({
      ...base, 'id': 'a1', 'code': 'MED-0001', 'cstatus': 'Unstable',
      'cc': 'Chest pain 2 days',
      'hpi': 'Central crushing chest pain radiating to the left arm, ' * 12 + 'Supercalifragilisticexpialidocious_pneumonoultramicroscopicsilicovolcanoconiosis_averyveryverylongwordwithoutanyspaces_1234567890',
      'pmh': 'Hypertension, diabetes', 'drugs': 'Metformin', 'allergies': 'Penicillin',
      'v_bp': '90/60', 'v_hr': '130', 'v_temp': '37.2', 'v_rr': '24', 'v_spo2': '91%',
      'examGeneral': 'Pale, sweaty', 'obsGeneral': 'Examined by me',
      'sys': {'CVS': {'s': 'Abnormal', 'n': 'S3 gallop'}, 'Respiratory': {'s': 'Normal'}, 'Abdomen': {'s': 'Not examined'}},
      'redFlags': 'Hypotension\nTachycardia with chest pain; ST elevation V2-V4',
      'workingDx': 'ACS', 'finalDx': 'Anterior STEMI', 'ddx': 'PE; aortic dissection', 'reasoning': 'ST elevation with typical pain.',
      'inv': [
        {'name': 'ECG', 'status': 'Resulted', 'result': 'ST elevation V2-V4', 'interpretation': 'Anterior STEMI'},
        {'name': 'Troponin', 'status': 'Pending', 'result': '', 'interpretation': ''},
      ],
      'mgmt': [
        {'text': 'Aspirin loading', 'dose': '300 mg', 'category': 'Drug', 'by': 'Team', 'state': 'Done'},
        {'text': 'Activate cath lab', 'category': 'Procedure', 'by': 'Supervisor'},
        {'text': 'Admit CCU', 'category': 'Disposition'},
      ],
      'evo': [{'step': 'Initial', 'date': '2026-10-10', 'text': 'ACS', 'evidence': 'ECG changes'}],
      'progress': [{'day': 'Day 1', 'date': '2026-10-11', 's': 'Better', 'o': 'HR 90', 'a': 'Improving', 'p': 'Continue'}],
      'disposition': 'Admitted', 'learned': 'Time is muscle.\nDo ECG within 10 minutes',
      'mistakes': 'Delayed ECG', 'questions': 'Door-to-balloon target?',
    }),
    CaseRec({
      ...base, 'id': 'a2', 'code': 'MED-0002', 'cstatus': 'Stable', 'specialty': 'Pediatrics',
      'cc': 'Fever 3 days', 'finalDx': 'Viral URTI', 'mgmt': [{'text': 'Paracetamol', 'dose': '15 mg/kg'}], 'learned': 'Fluids',
    }),
    CaseRec({...base, 'id': 'a3', 'code': 'MED-0003', 'cc': 'Cough'}),
  ];
}

CaseRec arCase() => CaseRec({
      'id': 'b1', 'code': 'MED-0009', 'date': '2026-10-10', 'specialty': 'Internal Medicine', 'cstatus': 'Critical', 'status': 'Active',
      'cc': 'ألم في الصدر منذ يومين',
      'hpi': 'بدأ الألم فجأة أثناء المجهود ويمتد إلى الذراع الأيسر ويزداد مع التنفس العميق. ' * 6,
      'redFlags': 'هبوط ضغط الدم\nضيق تنفس شديد', 'finalDx': 'Anterior STEMI',
      'mgmt': [
        {'text': 'إعطاء الأسبرين فورًا', 'dose': '300 mg'},
        {'text': 'Activate cath lab'},
      ],
      'learned': 'الوقت عضلة',
      'v_bp': '90/60', 'v_hr': '130',
    });

void main() {
  main2();
}

void main2() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
  });

  for (final lang in ['en', 'ar']) {
    for (final large in [false, true]) {
      test('cases pdf $lang large=$large', () async {
        setLangSetting(lang);
        await Future(() {});
        final cases = lang == 'ar' ? [arCase(), ...sample()] : sample();
        final pages = await casesDoc(cases, large: large).render();
        expect(pages.isNotEmpty, true);
        final bytes = await buildCasesPdf(cases, large: large);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        final tag = '${lang}_${large ? 'L' : 'N'}';
        File('test_output/shots/PDF2_$tag.pdf').writeAsBytesSync(bytes);
        for (var i = 0; i < pages.length; i++) {
          File('test_output/shots/PDF2_${tag}_p${i + 1}.png').writeAsBytesSync(pages[i]);
        }
      });
    }
  }
  test('text pdf', () async {
    setLangSetting('en');
    final b = await buildPdf('Logbook', '## Summary\n3 cases\n## Cases\n' + List.generate(120, (i) => 'line $i').join('\n'));
    expect(b.length > 2000, true);
  });
  test('no status is guessed', () {
    expect(clinStatusOf(CaseRec({'id': 'x', 'disposition': 'Deceased', 'outcome': 'critical'})), '');
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('list chip, filter, editor selector, logbook $lang', (tester) async {
      await boot(tester, lang);
      final rec = store.cases['c0']!;
      rec.set('cstatus', 'Critical');
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await settle(tester, 600);
      await tester.runAsync(() async {
        final d = logbookDoc(false);
        final pages = await d.render();
        File('test_output/shots/PDF2_logbook_$lang.png').writeAsBytesSync(pages.first);
      });
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute(builder: (_) => const CasesScreen()));
      await settle(tester, 1500);
      expect(find.byType(ClinStatusChip), findsOneWidget);
      await shot(tester, 'PDF2_list_$lang');
      Future<void> urgent() async {
        await tester.tap(find.byKey(const Key('cases_filter')));
        await settle(tester, 400);
        await tester.tap(find.widgetWithText(FilterChip, tr('Unstable / Critical')));
        await settle(tester, 300);
        await tester.tapAt(const Offset(10, 10));
        await settle(tester, 500);
      }

      await urgent();
      expect(find.byType(CaseTile), findsOneWidget);
      rec.set('cstatus', 'Stable');
      await urgent(); // off
      await urgent(); // on again: the case is now stable, so nothing matches
      expect(find.byType(CaseTile), findsNothing);
      nav.push(MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: rec, initialTab: 0)));
      await settle(tester, 1500);
      final lab = find.text(tr('Status at presentation (optional)'));
      await tester.dragUntilVisible(lab, find.byType(Scrollable).first, const Offset(0, -250));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.dragUntilVisible(find.text(tr('Critical')), find.byType(Scrollable).first, const Offset(0, -100));
      await tester.tap(find.text(tr('Critical')));
      await settle(tester, 400);
      expect(rec.s('cstatus'), 'Critical');
      await shot(tester, 'PDF2_editor_$lang');
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    });
  }
}
