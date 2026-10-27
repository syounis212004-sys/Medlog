import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/ai/ai_engine.dart' show AiEngine;
import 'package:medlog/data.dart';
import 'package:medlog/goals_signoff.dart';
import 'package:medlog/pdf_export.dart';
import 'package:medlog/i18n.dart';
import 'package:medlog/main.dart';
import 'package:medlog/library.dart';
import 'package:medlog/screens_cases.dart';
import 'package:medlog/screens_search.dart';
import 'package:medlog/screens_review.dart';
import 'package:medlog/screens_article.dart';
import 'package:medlog/screens_quiz.dart';
import 'package:medlog/screens_calc.dart';
import 'package:medlog/screens_library.dart';
import 'package:medlog/screens_portfolio.dart';
import 'package:medlog/screens_privacy.dart';
import 'package:medlog/screens_calendar.dart';
import 'package:medlog/screens_notebooks.dart';
import 'package:medlog/screens_skills.dart';
import 'package:medlog/lib_user.dart';
import 'package:medlog/widgets.dart' show Fold;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePP extends PathProviderPlatform {
  final String dir;
  FakePP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

final GlobalKey shotKey = GlobalKey();
const out = 'test_output/shots';
final log = <String>[];

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
  }
  await l.load();
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final b = shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.5);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> settle(WidgetTester tester, [int ms = 1000]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> realWait(WidgetTester tester, [int ms = 150]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> waitSpin(WidgetTester tester) async {
  for (var k = 0; k < 40; k++) {
    await realWait(tester, 120);
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty && k > 3) break;
  }
  await settle(tester, 700);
}

/// Runs a step; a failure is logged, never fatal.
Future<void> step(String name, Future<void> Function() f) async {
  try {
    await f();
    log.add('ok   $name');
  } catch (e) {
    log.add('FAIL $name: ${e.toString().split('\n').first}');
  }
}

String d(int back) => fmtDate(DateTime.now().subtract(Duration(days: back)));

void seed(String dir, Map<String, dynamic> settings, {bool empty = false}) {
  final root = Directory('$dir/medlog/cases')..createSync(recursive: true);
  Directory('$dir/medlog/images').createSync(recursive: true);
  void w(String name, Object o) => File('$dir/medlog/$name').writeAsStringSync(jsonEncode(o));
  w('settings.json', settings);
  if (empty) return;
  w('rotations.json', [
    {'id': 'r0', 'name': 'Emergency', 'hospital': 'Al-Shifa', 'start': d(70), 'end': d(42), 'supervisor': 'Dr. Nour'},
    {'id': 'r1', 'name': 'Internal Medicine', 'hospital': 'Al-Shifa Hospital', 'start': d(14), 'end': fmtDate(DateTime.now().add(const Duration(days: 16))), 'goals': '10 cannulations, 5 ABGs, present 3 cases', 'supervisor': 'Dr. Ali'},
  ]);
  w('shifts.json', [
    for (final i in [0, 2, 4, 7, 9, 11]) {'date': d(i), 'type': ['Morning', 'Night', 'On-call', 'Evening'][i % 4], 'rotationId': 'r1'},
  ]);
  w('procedures.json', [
    {'id': 'p1', 'name': 'IV cannulation', 'role': 'Performed under supervision', 'confidence': '4', 'date': d(1), 'assessedBy': 'Self-assessed', 'rotationId': 'r1'},
    {'id': 'p2', 'name': 'ABG', 'role': 'Assisted', 'confidence': '3', 'date': d(3), 'assessedBy': 'Supervisor assessed', 'rotationId': 'r1'},
    {'id': 'p3', 'name': 'Lumbar puncture', 'role': 'Observed', 'confidence': '2', 'date': d(6), 'assessedBy': 'Self-assessed', 'rotationId': 'r1'},
    {'id': 'p4', 'name': 'Suturing', 'role': 'Performed independently', 'confidence': '5', 'date': d(40), 'assessedBy': 'Supervisor assessed', 'rotationId': 'r0'},
    {'id': 'p5', 'name': 'IV cannulation', 'role': 'Performed independently', 'confidence': '5', 'date': d(45), 'assessedBy': 'Supervisor assessed', 'rotationId': 'r0'},
  ]);
  w('notes.json', [
    {'id': 'n1', 'title': 'DKA fluids', 'body': 'Start with 1L NS over 1h then insulin 0.1 u/kg/h once K > 3.3', 'updated': '2026-10-20', 'date': '2026-10-20'},
  ]);
  w('questions.json', [
    {'id': 'q1', 'question': 'When to switch insulin infusion to SC?', 'status': 'Open', 'date': d(2)},
  ]);
  final specs = ['Internal Medicine', 'Emergency', 'Orthopedics', 'Pediatrics', 'General Surgery', 'Cardiology'];
  final dx = ['Community acquired pneumonia', 'Acute coronary syndrome', 'Distal radius fracture', 'Gastroenteritis', 'Acute appendicitis', 'DKA', 'Heart failure', 'Osteoarthritis'];
  final pre = {'Internal Medicine': 'MED', 'Emergency': 'EM', 'Orthopedics': 'ORT', 'Pediatrics': 'PED', 'General Surgery': 'SUR', 'Cardiology': 'CAR'};
  for (var i = 0; i < 12; i++) {
    final spec = specs[i % specs.length];
    final c = {
      'id': 'c$i', 'schema': 2, 'created': '2026-10-${10 + i}T08:00:00Z', 'date': d(i ~/ 2), 'specialty': spec,
      'rotationId': i < 8 ? 'r1' : 'r0', 'status': i % 5 == 0 ? 'Draft' : ['Active', 'Discharged', 'Completed'][i % 3],
      'code': '${pre[spec]}-${(i + 1).toString().padLeft(4, '0')}', 'ageGroup': i % 3 == 0 ? 'Child' : 'Adult', 'sex': i % 2 == 0 ? 'M' : 'F',
      'age': '${20 + i * 5}', 'cc': ['Chest pain 2 days', 'Fever and cough', 'Fall on outstretched hand', 'Vomiting x3 days'][i % 4],
      'workingDx': dx[i % dx.length], 'setting': ['ER', 'Ward', 'Clinic'][i % 3],
      'role': ['Observed', 'Assisted', 'Supervised', 'Independent'][i % 4], 'tags': i % 4 == 0 ? ['rare'] : [], 'starred': i == 2,
      'hpi': 'Pain started 2 days ago, worse on exertion, radiating to the left arm.', 'pmh': i % 2 == 0 ? 'HTN, T2DM' : '',
      'allergies': i == 0 ? 'Penicillin' : '', 'v_bp': '130/85', 'v_hr': '88', 'v_temp': '37.2', 'v_spo2': '97',
      'learned': i % 2 == 0 ? 'Check troponin timing' : '',
    };
    File('${root.path}/c$i.json').writeAsStringSync(jsonEncode(c));
  }
}

/// symlink the real packs into <dir>/library (what main.dart's library.init reads)
void installPacksAt(String dir, List<String> ids) {
  final lib = Directory('$dir/library')..createSync(recursive: true);
  final cat = jsonDecode(File('../library/catalog.json').readAsStringSync()) as Map;
  final metas = <Map>[];
  for (final e in cat['packs'] as List) {
    final id = e['id'];
    if (!ids.contains(id)) continue;
    for (final ext in ['idx', 'bin']) {
      Link('${lib.path}/$id.$ext').createSync('../library/$id.$ext');
    }
    metas.add({...(e as Map), 'bytes': File('../library/$id.bin').lengthSync() + File('../library/$id.idx').lengthSync()});
  }
  File('${lib.path}/installed.json').writeAsStringSync(jsonEncode(metas));
}

Future<void> boot(WidgetTester tester, String lang, {Map<String, dynamic> extra = const {}, bool empty = false, List<String> packs = const ['orthopedics', 'cardiology', 'clinical-essentials', 'medlineplus'], Size size = const Size(412, 892), bool firstLaunch = false}) async {
  final dir = Directory.systemTemp.createTempSync('medlog').path;
  PathProviderPlatform.instance = FakePP(dir);
  seed(dir, {
    'lang': lang, 'author': lang == 'ar' ? 'د. محمد' : 'Dr. Mohammed', 'palette': 'clinic', 'deviceId': 'x',
    'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false, 'libQuick': true, ...extra,
  }, empty: empty);
  if (packs.isNotEmpty) installPacksAt(dir, packs);
  AiEngine.debugOnline = true;
  await tester.runAsync(() => store.init());
  await tester.runAsync(() => library.init(Directory(dir)));
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
  await settle(tester, 3800);
  await realWait(tester, 200);
  await settle(tester, 500);
}

NavigatorState navi(WidgetTester t) => t.state<NavigatorState>(find.byType(Navigator).first);
Future<void> push(WidgetTester t, Widget w, [int ms = 1200]) async {
  navi(t).push(MaterialPageRoute(builder: (_) => w));
  await settle(t, ms);
}
Future<void> pop(WidgetTester t) async {
  navi(t).pop();
  await settle(t, 600);
}
Future<void> tabTo(WidgetTester t, String label) async {
  await t.tap(find.descendant(of: find.byType(AppNavBar), matching: find.text(label)));
  await settle(t, 1000);
}


Future<void> finish(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await realWait(tester, 100);
  }
}

Future<void> fontsInit() async {
  final rb = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
  await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
  const fd = 'assets/fonts';
  await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
  await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
  await loadFont('Tajawal', ['$fd/Tajawal_400Regular.ttf', '$fd/Tajawal_500Medium.ttf', '$fd/Tajawal_700Bold.ttf']);
  await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await fontsInit();
    HttpOverrides.global = null;
  });

  // ------------------------------------------------------------ goals maths
  testWidgets('goal progress maths and pace', (tester) async {
    await boot(tester, 'en', packs: const []);
    final rot = store.rotationById('r1')!;
    // cases: 8 in r1
    var gp = progressFor(rot, {'kind': 'Cases', 'target': 20});
    expect(gp.done, 8);
    expect(gp.target, 20);
    expect(gp.frac, closeTo(0.4, 1e-9));
    expect(gp.met, false);
    gp = progressFor(rot, {'kind': 'Cases', 'target': 5});
    expect(gp.met, true);
    expect(gp.frac, 1.0);
    // procedure: one performed (under supervision) IV cannulation in r1, ABG assisted
    final iv = {'kind': 'Procedure', 'name': 'IV cannulation', 'tPerf': 5, 'tAssist': 5};
    gp = progressFor(rot, iv);
    expect(gp.done, 1);
    expect(gp.target, 10);
    store.procedures.add({'id': 'p9', 'name': 'IV cannulation', 'role': 'Assisted', 'date': d(1), 'rotationId': 'r1'});
    store.procedures.add({'id': 'p10', 'name': 'IV cannulation', 'role': 'Observed', 'date': d(1), 'rotationId': 'r1'});
    store.procedures.add({'id': 'p11', 'name': 'IV cannulation', 'role': 'Performed independently', 'date': d(1), 'rotationId': 'r0'});
    gp = progressFor(rot, iv);
    expect(gp.done, 2, reason: 'observed and other-rotation entries do not count');
    expect(gp.detail.contains('1 / 5'), true);
    // extra performed beyond the target does not push assisted over
    for (var i = 0; i < 7; i++) {
      store.procedures.add({'id': 'px$i', 'name': 'ABG', 'role': 'Performed under supervision', 'date': d(1), 'rotationId': 'r1'});
    }
    gp = progressFor(rot, {'kind': 'Procedure', 'name': 'ABG', 'tPerf': 5, 'tAssist': 2});
    expect(gp.done, 6, reason: 'performed capped at 5, plus the one assisted ABG');
    // achievements in the rotation dates
    store.listOf('achievements').add({'id': 'a1', 'kind': 'Presentation', 'date': d(2)});
    store.listOf('achievements').add({'id': 'a2', 'kind': 'Presentation', 'date': d(300)});
    store.listOf('achievements').add({'id': 'a3', 'kind': 'Award', 'date': d(2)});
    expect(progressFor(rot, {'kind': 'Achievements', 'name': 'Presentation', 'target': 3}).done, 1);
    expect(progressFor(rot, {'kind': 'Achievements', 'name': '', 'target': 3}).done, 2);
    // notes (n1 dated 2026-10-20, outside d(14)..+16 only if before start) just must not throw
    progressFor(rot, {'kind': 'Notes', 'target': 1});
    progressFor(rot, {'kind': 'Reflections', 'target': 1});
    // pace: rotation 14 days ago .. 16 days ahead = 30 days, 14/30 elapsed = 0.47
    final now = DateTime.now();
    expect(paceOf(rot, progressFor(rot, {'kind': 'Cases', 'target': 20}), now), Pace.onTrack); // 0.4 + 0.1 >= 0.47
    expect(paceOf(rot, progressFor(rot, {'kind': 'Cases', 'target': 40}), now), Pace.behind); // 0.2 + 0.1 < 0.47
    expect(paceOf(rot, progressFor(rot, {'kind': 'Cases', 'target': 8}), now), Pace.done);
    expect(paceOf(rot, progressFor(rot, {'kind': 'Cases', 'target': 40}), now.add(const Duration(days: 40))), Pace.behind);
    expect(paceOf({'id': 'r1'}, progressFor(rot, {'kind': 'Cases', 'target': 40}), now), Pace.none);
    expect(daysLeftOf(rot, now), 16);
    expect(daysLeftOf({'id': 'x'}), null);
  });

  testWidgets('performed assisted split', (tester) async {
    await boot(tester, 'en', packs: const []);
    final rot = store.rotationById('r1')!;
    for (var i = 0; i < 3; i++) {
      store.procedures.add({'id': 'pa$i', 'name': 'ABG', 'role': 'Assisted', 'date': d(1), 'rotationId': 'r1'});
    }
    // p2 is already an assisted ABG in r1 => 4 assisted, 0 performed
    final gp = progressFor(rot, {'kind': 'Procedure', 'name': 'ABG', 'tPerf': 2, 'tAssist': 3});
    expect(gp.done, 3, reason: 'assisted capped at 3, performed 0');
    expect(gp.target, 5);
  });

  // ------------------------------------------------------------ sign-off
  for (final lang in ['en', 'ar']) {
    testWidgets('sign-off flow procedures and cases $lang', (tester) async {
      await boot(tester, lang, packs: const []);
      await push(tester, const SignOffScreen(), 1000);
      await shot(tester, 'PORT_signoff_list_$lang');
      expect(find.byType(ListTile), findsWidgets);
      expect(isSigned(store.procedures.first), false);
      // open first row (newest) and sign
      final p = store.procedures.firstWhere((x) => x['id'] == 'p1');
      await tester.runAsync(() async {});
      navi(tester).context; // keep analyzer quiet
      // go through the sheet API directly for the procedure
      final ctx = tester.element(find.byType(SignOffTab));
      final fut = editProcedureSignOff(ctx, p);
      await settle(tester, 700);
      await shot(tester, 'PORT_signoff_sheet_$lang');
      await tester.enterText(find.byType(TextField).at(0), 'Dr. Nour');
      await tester.enterText(find.byType(TextField).at(1), 'Consultant');
      final sheetChips = find.descendant(of: find.byType(BottomSheet), matching: find.byType(ChoiceChip));
      await tester.ensureVisible(sheetChips.at(3));
      await tester.tap(sheetChips.at(3));
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await settle(tester, 300);
      await shot(tester, 'PORT_signoff_sheet2_$lang');
      await tester.enterText(find.byType(TextField).at(2), 'AN');
      await tester.tap(find.byType(FilledButton).last);
      await finish(tester);
      await settle(tester, 600);
      expect(isSigned(p), true);
      expect(p['supName'], 'Dr. Nour');
      expect(p['supLevel'], 'Performed independently');
      expect(p['supInit'], 'AN');
      expect((p['supDate'] ?? '').toString().isNotEmpty, true);
      expect(signedText(p).contains('Dr. Nour'), true);
      expect(signCell(p).contains('AN'), true);
      // 'Not signed yet' filter no longer lists it
      final sc = signCounts();
      expect(sc.signed, 1);
      // a case
      final rec = store.cases['c0']!;
      final fut2 = editCaseSignOff(ctx, rec);
      await settle(tester, 700);
      await tester.enterText(find.byType(TextField).at(0), 'Dr. Ali');
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await settle(tester, 300);
      await tester.tap(find.byType(FilledButton).last);
      await finish(tester);
      await settle(tester, 600);
      expect(isSigned(rec.d), true);
      expect(signCounts().signed, 2);
      // persisted on disk
      final onDisk = jsonDecode(File('${store.casesDir.path}/c0.json').readAsStringSync()) as Map;
      expect(onDisk['supSigned'], '1');
      expect(onDisk['supName'], 'Dr. Ali');
      // filter: switch to 'All' then 'Signed'
      await tester.tap(find.byType(ChoiceChip).at(1));
      await settle(tester, 500);
      await shot(tester, 'PORT_signoff_signed_$lang');
      expect(find.byIcon(Icons.verified_outlined), findsWidgets);
      // clear sign-off
      final fut3 = editProcedureSignOff(ctx, p);
      await settle(tester, 700);
      await tester.tap(find.widgetWithText(TextButton, tr('Clear')));
      await finish(tester);
      await settle(tester, 400);
      expect(isSigned(p), false);
      expect(p.containsKey('supName'), false);
    });
  }

  // ------------------------------------------------------------ export
  for (final lang in ['en', 'ar']) {
    test('export csv + pdf with sign-off $lang', () async {
      // no widget needed: use the store with a seeded temp dir
      final dir = Directory.systemTemp.createTempSync('medlog').path;
      PathProviderPlatform.instance = FakePP(dir);
      seed(dir, {'lang': lang, 'author': 'Dr. A', 'palette': 'clinic', 'deviceId': 'x'});
      await store.init();
      setLangSetting(lang);
      await Future(() {});
      // sign one procedure and one case
      final p = store.procedures.firstWhere((x) => x['id'] == 'p1');
      p..['supName'] = 'Dr. Nour'..['supSigned'] = '1'..['supDate'] = d(1)..['supLevel'] = 'Performed under supervision'..['supInit'] = 'AN';
      final rec = store.cases['c0']!;
      rec.d..['supName'] = 'Dr. Ali'..['supSigned'] = '1'..['supDate'] = d(2);

      final o = ExportOptions(range: 'rotation', rotationId: 'r1');
      final cases = o.cases();
      expect(cases.length, 8);
      expect(cases.every((c) => c.s('rotationId') == 'r1'), true);
      expect(o.procedures().length, 3);
      final od = ExportOptions(range: 'dates', from: DateTime.now().subtract(const Duration(days: 3)), to: DateTime.now());
      expect(od.cases().every((c) => c.s('date').compareTo(d(3)) >= 0), true);
      expect(od.cases().length < store.cases.length, true);

      final rows = store.casesCsvRows(cases);
      expect(rows.first.contains('Signed by supervisor'), true);
      final i = rows.first.indexOf('Signed by supervisor');
      final signedRow = rows.firstWhere((r) => r[0] == 'MED-0001');
      expect(signedRow[i], 'yes');
      expect(signedRow[rows.first.indexOf('Supervisor')], 'Dr. Ali');
      final prow = store.procsCsvRows(o.procedures());
      expect(prow.length, 4);
      expect(prow.any((r) => r.contains('Dr. Nour') && r.contains('AN')), true);
      expect(store.casesCsvRows(cases, signOff: false).first.contains('Signed by supervisor'), false);

      final doc = logbookDoc(false, opts: o);
      final pagesSign = await doc.render();
      final pagesPlain = await logbookDoc(false, opts: ExportOptions(range: 'rotation', rotationId: 'r1', signOff: false)).render();
      final pagesOld = await logbookDoc(false).render();
      expect(pagesSign.isNotEmpty, true);
      expect(pagesOld.isNotEmpty, true);
      expect(pagesSign.length >= pagesPlain.length, true);
      for (var k = 0; k < pagesSign.length; k++) {
        File('test_output/shots/PORT_logbook_${lang}_p${k + 1}.png').writeAsBytesSync(pagesSign[k]);
      }
      final bytes = await buildCasesPdf(cases.take(3).toList(), signOff: true);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final cp = await casesDoc(cases.take(3).toList(), signOff: true).render();
      for (var k = 0; k < cp.length && k < 2; k++) {
        File('test_output/shots/PORT_cases_${lang}_p${k + 1}.png').writeAsBytesSync(cp[k]);
      }
      // a rotation with targets prints them
      final rot = store.rotationById('r1')!;
      targetsOf(rot).addAll([
        {'id': 't1', 'kind': 'Cases', 'target': 20},
        {'id': 't2', 'kind': 'Procedure', 'name': 'IV cannulation', 'tPerf': 5, 'tAssist': 5},
      ]);
      final withT = await logbookDoc(false, opts: o).render();
      File('test_output/shots/PORT_rotsummary_$lang.png').writeAsBytesSync(withT.first);
    });
  }

  // ------------------------------------------------------------ rotation screen
  for (final lang in ['en', 'ar']) {
    for (final big in [false, true]) {
      testWidgets('rotation targets screen $lang big=$big', (tester) async {
        await boot(tester, lang, packs: const [], size: big ? const Size(360, 640) : const Size(412, 892), extra: big ? {'textScale': 1.3} : {});
        await finish(tester);
        await push(tester, RotationScreen(rotationId: 'r1'), 1200);
        await finish(tester);
        await shot(tester, 'PORT_rot_empty_${lang}_${big ? 'S' : 'M'}');
        // apply example targets through the real UI
        await tester.tap(find.byIcon(Icons.auto_awesome_outlined).first);
        await settle(tester, 700);
        await shot(tester, 'PORT_rot_templates_${lang}_${big ? 'S' : 'M'}');
        await tester.tap(find.byIcon(Icons.flag_outlined).last);
        await finish(tester);
        await settle(tester, 900);
        expect(targetsOf(store.rotationById('r1')!).length, 3);
        await shot(tester, 'PORT_rot_targets_${lang}_${big ? 'S' : 'M'}');
        // edit first target via sheet
        await tester.ensureVisible(find.text(tr('IV cannulation')).first);
        await tester.pump();
        await tester.tap(find.text(tr('IV cannulation')).first);
        await settle(tester, 700);
        await shot(tester, 'PORT_rot_edit_${lang}_${big ? 'S' : 'M'}');
        await tester.enterText(find.byType(TextField).at(1), '8');
        await tester.ensureVisible(find.byType(FilledButton).last);
        await tester.tap(find.byType(FilledButton).last);
        await finish(tester);
        await settle(tester, 700);
        expect(targetsOf(store.rotationById('r1')!).first['tPerf'], 8);
        // persisted in rotations.json
        final saved = jsonDecode(File('${store.root.path}/rotations.json').readAsStringSync()) as List;
        expect((saved.firstWhere((r) => r['id'] == 'r1')['targets'] as List).length, 3);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
        await settle(tester, 500);
        await shot(tester, 'PORT_rot_targets2_${lang}_${big ? 'S' : 'M'}');
      });
    }
  }

  // ------------------------------------------------------------ settings
  for (final lang in ['en', 'ar']) {
    for (final big in [false, true]) {
      testWidgets('settings sections and search $lang big=$big', (tester) async {
        await boot(tester, lang, packs: const [], size: big ? const Size(360, 640) : const Size(412, 892), extra: big ? {'textScale': 1.3} : {});
        await push(tester, const SettingsScreen(), 1200);
        final tag = '${lang}_${big ? 'S' : 'M'}';
        await shot(tester, 'PORT_set_top_$tag');
        final titles = tester.widgetList<Fold>(find.byType(Fold)).map((f) => f.title).toList();
        final en = ['Appearance', 'Language', 'Library', 'Privacy & security', 'Sharing', 'Reminders', 'AI assistant', 'Access & members', 'Backup & export'];
        expect(titles.length >= 3, true, reason: '$titles');
        // order check (list is lazy: only the built ones; titles are translated in ar)
        for (var i = 0; i < titles.length && i < en.length; i++) {
          expect(titles[i], tr(en[i]), reason: 'section $i');
        }
        // Library open by default, Sharing closed (when built)
        final folds = tester.widgetList<Fold>(find.byType(Fold)).toList();
        expect(folds[2].initiallyOpen, true, reason: 'Library');
        if (folds.length > 4) expect(folds[4].initiallyOpen, false, reason: 'Sharing');
        expect(folds[0].initiallyOpen, false, reason: 'Appearance');
        // search: font
        await tester.enterText(find.byType(TextField).first, lang == 'ar' ? 'Cairo' : 'font');
        await settle(tester, 500);
        await shot(tester, 'PORT_set_search_font_$tag');
        expect(find.byType(Fold), findsNothing);
        expect(find.byType(ChoiceChip), findsWidgets);
        // backup
        await tester.enterText(find.byType(TextField).first, 'backup');
        await settle(tester, 500);
        await shot(tester, 'PORT_set_search_backup_$tag');
        expect(find.byType(FilledButton), findsWidgets);
        await tester.enterText(find.byType(TextField).first, 'zzzqq');
        await settle(tester, 400);
        expect(find.byType(ChoiceChip), findsNothing);
        await shot(tester, 'PORT_set_search_none_$tag');
        // clear
        await tester.tap(find.byIcon(Icons.close));
        await settle(tester, 500);
        expect(find.byType(Fold), findsWidgets);
        // open backup fold and the app-lock/reminder rows still exist
        await tester.enterText(find.byType(TextField).first, 'reminder');
        await settle(tester, 400);
        expect(find.byType(SwitchListTile), findsWidgets);
        await shot(tester, 'PORT_set_search_rem_$tag');
        await tester.enterText(find.byType(TextField).first, 'lock');
        await settle(tester, 400);
        expect(find.byType(SwitchListTile), findsWidgets);
        await tester.tap(find.byIcon(Icons.close));
        await settle(tester, 400);
        // open Backup fold
        final bk = find.widgetWithText(Fold, tr('Backup & export'));
        await tester.dragUntilVisible(bk, find.byType(Scrollable).first, const Offset(0, -200));
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
        await settle(tester, 300);
        await tester.tap(find.descendant(of: bk, matching: find.text(tr('Backup & export'))));
        await settle(tester, 700);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await settle(tester, 400);
        await shot(tester, 'PORT_set_backup_$tag');
        expect(find.byIcon(Icons.upload_file_outlined), findsWidgets);
      });
    }
  }

  // old backup nudge: never backed up
  testWidgets('backup nudge shows when never backed up', (tester) async {
    await boot(tester, 'en', packs: const [], extra: {'lastBackup': ''});
    await push(tester, const SettingsScreen(), 1000);
    await tester.enterText(find.byType(TextField).first, 'backup');
    await settle(tester, 500);
    expect(find.text('Never backed up'), findsWidgets);
    expect(find.text('Back up now'), findsOneWidget);
    await shot(tester, 'PORT_set_nudge');
  });

  testWidgets('export dialog', (tester) async {
    await boot(tester, 'en', packs: const []);
    final ctx = tester.element(find.byType(Scaffold).first);
    final fut = askExportOptions(ctx);
    await settle(tester, 700);
    await shot(tester, 'PORT_export_dialog');
    await tester.tap(find.text('Date range'));
    await settle(tester, 300);
    await shot(tester, 'PORT_export_dialog_dates');
    await tester.tap(find.text('CSV'));
    await settle(tester, 300);
    await tester.tap(find.text('Export'));
    await tester.pump();
    final o = await fut;
    expect(o!.range, 'dates');
    expect(o.format, 'csv');
    expect(o.signOff, true);
  });
}
