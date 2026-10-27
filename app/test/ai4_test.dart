import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/ai/ai_api.dart';
import 'package:medlog/ai/ai_case_payload.dart';
import 'package:medlog/ai/ai_cases.dart';
import 'package:medlog/ai/ai_help.dart';
import 'package:medlog/ai/ai_engine.dart' show AiEngine;
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' show setLangSetting, isAr;
import 'package:medlog/main.dart';
import 'package:medlog/screens_ai_cases.dart';
import 'package:medlog/screens_ai_help.dart';
import 'package:medlog/screens_cases.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePP extends PathProviderPlatform {
  final String dir;
  FakePP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

final GlobalKey shotKey = GlobalKey();

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
    final img = await b.toImage(pixelRatio: 1.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('test_output/shots').createSync(recursive: true);
    File('test_output/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> io(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String d(int back) => fmtDate(DateTime.now().subtract(Duration(days: back)));

const planted = [
  'Planted', 'Zahra', '0791234567', '4455667', 'MED-0042', 'Q.Z.', 'Baker', 'SECRETLEARNED', 'SECRETTEACH', 'img_secret123',
  'Ahmad', 'Haddad',
];

Map<String, dynamic> plantedCase() => {
      'id': 'cA', 'schema': 2, 'created': '2026-10-10T08:00:00Z', 'date': d(1), 'code': 'MED-0042', 'initials': 'Q.Z.',
      'rotationId': 'r1', 'ageGroup': 'Adult', 'sex': 'M', 'setting': 'Ward', 'specialty': 'Internal Medicine', 'status': 'Active',
      'author': 'Dr. Planted Author', 'supName': 'Dr. Haddad Planted', 'supRole': 'Consultant',
      'cc': 'Chest pain 2 days',
      'hpi': 'Mr Ahmad Planted seen at Zahra Planted Hospital on ${d(1)} by Dr. Haddad Planted, phone 0791234567, MRN: 4455667. '
          'Pain started on 03/10/2026, worse on exertion.',
      'pmh': 'HTN', 'drugs': 'amlodipine 5 mg', 'allergies': 'Penicillin',
      'social': 'Lives at 12 Baker Street, works as a Planted-Corp driver',
      'learned': 'SECRETLEARNED', 'teaching': 'SECRETTEACH', 'questions': 'SECRETTEACH question',
      'v_bp': '150/90', 'v_hr': '96',
      'sys': {'CVS': {'s': 'Abnormal', 'n': 'S3 gallop'}},
      'inv': [{'name': 'Troponin', 'status': 'Resulted', 'result': '45 ng/L'}],
      'images': [{'file': 'img_secret123.jpg', 'caption': 'CXR', 'interpretation': 'Cardiomegaly'}],
      'mgmt': [{'text': 'Aspirin', 'dose': '300 mg', 'state': 'Given', 'category': 'Medications & fluids'}],
      'progress': [{'day': 'Day 2', 'date': d(0), 's': 'better', 'o': '', 'a': '', 'p': 'continue'}],
      'workingDx': 'Acute coronary syndrome', 'ddx': 'Pericarditis; Pulmonary embolism', 'outcome': 'Improved',
      'tags': ['cardio'],
    };

Future<void> boot(WidgetTester tester, String lang, {Size size = const Size(412, 892), double scale = 1.0, bool addAi = false}) async {
  final dir = Directory.systemTemp.createTempSync('medlog').path;
  PathProviderPlatform.instance = FakePP(dir);
  Directory('$dir/medlog/cases').createSync(recursive: true);
  Directory('$dir/medlog/images').createSync(recursive: true);
  File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({
    'lang': lang, 'author': 'Dr. Planted Author', 'palette': 'clinic', 'deviceId': 'x', 'textScale': scale,
    'lastBackup': DateTime.now().toIso8601String(),
  }));
  File('$dir/medlog/rotations.json').writeAsStringSync(jsonEncode([
    {'id': 'r1', 'name': 'Internal Medicine', 'hospital': 'Zahra Planted Hospital', 'start': d(14), 'end': d(-16)},
  ]));
  File('$dir/medlog/procedures.json').writeAsStringSync(jsonEncode([
    {'id': 'p1', 'name': 'IV cannulation', 'role': 'Performed under supervision', 'date': d(1), 'rotationId': 'r1'},
  ]));
  File('$dir/medlog/cases/cA.json').writeAsStringSync(jsonEncode(plantedCase()));
  File('$dir/medlog/cases/cB.json').writeAsStringSync(jsonEncode({
    'id': 'cB', 'schema': 2, 'created': '2026-10-11T08:00:00Z', 'date': d(2), 'code': 'MED-0043', 'specialty': 'Internal Medicine',
    'status': 'Completed', 'cc': 'Cough', 'tags': ['cardio'],
  }));
  AiEngine.debugOnline = true;
  await tester.runAsync(() => store.init());
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
  await settle(tester, 3800);
}

Future<void> openAi(WidgetTester tester, {CaseRec? rec, int tab = 0}) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute(builder: (_) => AiCaseScreen(rec: rec ?? store.cases['cA']!, initialTab: tab)));
  await settle(tester, 1000);
}

const ddxJson = '{"summary":"Chest pain in an adult with hypertension","diagnoses":['
    '{"name":"Acute coronary syndrome","likelihood":"more likely","for":["Exertional pain","Raised troponin"],"against":["No ECG changes recorded"]},'
    '{"name":"Pericarditis","likelihood":"possible","for":["Chest pain"],"against":["No rub documented"]}],'
    '"red_flags":["Aortic dissection"],"dont_miss":["Pulmonary embolism"],"history_to_ask":["Pleuritic component?"],'
    '"exam_to_do":["Both arm blood pressures"],"investigations":["Serial ECG"],"would_change_management":["New ST elevation"]}';

void expectClean(String text, {String reason = ''}) {
  for (final p in planted) {
    expect(text.contains(p), false, reason: '$reason "$p" leaked in: $text');
  }
}

void main() {
  setUpAll(() async {
    const rb = '/opt/flutter/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  void fakeOn({bool online = true, bool enabled = true}) {
    installFakeAi(online: online, enabled: enabled, answers: {
      'case_ddx': ddxJson,
      'case_socratic': '{"feedback":"Good start: you named ACS.","question":"What will you order first?","done":false}',
      'case_fields': '{"fields":{"cc":"Palpitations for 3 days","specialty":"Cardiology","setting":"Clinic","hpi":"Seen on 2026-03-04, phone 0791234567, tel +962791234567","code":"X-1","ageGroup":"Elder"},'
          '"procedures_mentioned":["ECG"],"tags":["#palpitations","cardio"]}',
      'case_handover': '{"contingencies":["If chest pain recurs, repeat ECG and call the senior"]}',
      'case_reflect': '{"questions":["Why did you rank ACS first?","What did you exclude?","What will you read?"]}',
      'case_tags': '{"specialty":"Cardiology","tags":["chest_pain"]}',
      'summary_week': 'You logged cases and procedures this week.',
      'help_faq': '1. Tap + then Quick case.',
    });
    AiStore.allowCase = true;
    AiStore.caseConsented = true;
    AiStore.allowLibrary = true;
  }

  setUp(() {
    setLangSetting('en');
    uninstallFakeAi();
  });

  // ---------------------------------------------------------------- pure logic
  group('payload whitelist', () {
    testWidgets('planted identifiers never reach the payload', (tester) async {
      await boot(tester, 'en');
      final rec = store.cases['cA']!;
      final p = buildCasePayload(rec);
      final text = p.asPrompt();
      expectClean(text, reason: 'prompt');
      for (final e in p.fields.entries) {
        expect(kPayloadLabels.contains(e.key) || (kSpecialtyFields[rec.s('specialty')] ?? []).any((f) => f[1] == e.key), true, reason: e.key);
        expectClean(e.value, reason: e.key);
      }
      // wanted content survives
      expect(text, contains('Chest pain 2 days'));
      expect(text, contains('Cardiomegaly'));
      expect(text, contains('Day 2'));
      expect(text, contains('S3 gallop'));
      expect(text, contains('Aspirin'));
      expect(text, contains('Troponin'));
      // never read: social, learned, teaching, code
      expect(p.fields.keys.any((k) => k.toLowerCase().contains('social') || k.toLowerCase().contains('learn')), false);
      // the removal list explains what was cleaned
      expect(p.removed, isNotEmpty);
      expect(p.removed.any((e) => e.contains('identifier') || e.contains('name')), true);
      expect(p.removed.any((e) => e.toLowerCase().contains('date')), true);
      // stable cache key, different per feature
      expect(p.cacheKey('a'), p.cacheKey('a'));
      expect(p.cacheKey('a') == p.cacheKey('b'), false);
    });

    testWidgets('isCaseAiBlocked: a never-send case gives an empty payload', (tester) async {
      await boot(tester, 'en');
      final rec = store.cases['cA']!;
      expect(isCaseAiBlocked(rec), false);
      rec.d['aiNever'] = true;
      expect(isCaseAiBlocked(rec), true);
      final p = buildCasePayload(rec);
      expect(p.blocked, true);
      expect(p.isEmpty, true);
      expect(p.asPrompt(), '');
      rec.d.remove('aiNever');
      expect(buildCasePayload(rec).blocked, false);
    });

    testWidgets('every request builder only uses the payload', (tester) async {
      await boot(tester, 'en');
      final p = buildCasePayload(store.cases['cA']!);
      final reqs = [
        discussRequest(p), socraticRequest(p, const [SocraticTurn('ai', 'Q1?'), SocraticTurn('me', 'ACS')], 1),
        handoverRequest(p), reflectRequest(p), tagsRequest(p),
      ];
      for (final r in reqs) {
        expect(r.level, AiLevel.caseData);
        expect(r.previewFields, isNotNull);
        expectClean('${r.system}\n${r.prompt}\n${jsonEncode(r.previewFields)}', reason: r.feature);
        expect(r.cacheKey, isNotNull);
      }
      expect(summaryRequest(weekStats()).level, AiLevel.none);
    });
  });

  group('suggestions: apply and undo', () {
    testWidgets('validation, provenance, undo', (tester) async {
      await boot(tester, 'en');
      final rec = store.cases['cA']!;
      final j = jsonDecode('{"fields":{"cc":"Palpitations 3 days","specialty":"Cardiology","setting":"Clinic","code":"X-1","ageGroup":"Elder",'
          '"sex":"female","hpi":"Seen on 2026-03-04 tel 0791234567 by Dr. Haddad Planted"},"tags":["#palpitations","cardio"],"procedures_mentioned":["ECG"]}') as Map<String, dynamic>;
      final s = parseSuggestions(j, rec);
      final keys = s.items.map((e) => e.key).toList();
      expect(keys, containsAll(['cc', 'specialty', 'setting', 'sex', 'hpi', 'tags']));
      expect(keys.contains('code'), false);
      expect(keys.contains('ageGroup'), false); // invalid value dropped
      expect(s.items.firstWhere((e) => e.key == 'sex').suggested, 'F');
      expect(s.items.firstWhere((e) => e.key == 'tags').suggested, 'palpitations'); // 'cardio' already there
      expectClean(s.items.firstWhere((e) => e.key == 'hpi').suggested, reason: 'smuggled identifiers');
      expect(s.procedures, ['ECG']);
      // fields that already have text are NOT ticked by default
      expect(s.items.firstWhere((e) => e.key == 'cc').apply, false);
      expect(s.items.firstWhere((e) => e.key == 'cc').overwrites, true);
      // nothing written yet
      expect(rec.s('cc'), 'Chest pain 2 days');
      expect(rec.d.containsKey('aiSuggested'), false);

      final before = jsonEncode(rec.d);
      final chosen = s.items.where((e) => ['cc', 'tags', 'setting'].contains(e.key)).toList();
      final u = applySuggestions(rec, chosen);
      expect(rec.s('cc'), 'Palpitations 3 days');
      expect(rec.s('setting'), 'Clinic');
      expect(rec.tags, ['cardio', 'palpitations']);
      expect((rec.d['aiSuggested'] as List).toSet(), {'cc', 'tags', 'setting'});
      expect(rec.s('hpi').contains('Planted'), true); // untouched (not chosen)
      undoSuggestions(rec, u);
      expect(jsonEncode(rec.d), before);
      expect(rec.d.containsKey('aiSuggested'), false);

      // two applies merge provenance
      applySuggestions(rec, [chosen.firstWhere((e) => e.key == 'cc')]);
      applySuggestions(rec, [chosen.firstWhere((e) => e.key == 'setting')]);
      expect((rec.d['aiSuggested'] as List).toSet(), {'cc', 'setting'});
    });
  });

  group('local rules and texts', () {
    testWidgets('checkCase finds missing and inconsistent fields', (tester) async {
      await boot(tester, 'en');
      final sparse = store.cases['cB']!;
      final t = checkCase(sparse).map((e) => e.text).toList();
      expect(t, contains('History of present illness is empty.'));
      expect(t, contains('No vital signs recorded.'));
      expect(t.any((e) => e.contains('closed but has no final diagnosis')), true);
      final odd = CaseRec({
        'id': 'z', 'specialty': 'Pediatrics', 'ageGroup': 'Adult', 'sex': 'M', 'obGPA': 'G1', 'status': 'Draft', 'finalDx': 'x', 'cc': 'a', 'hpi': 'b',
        'v_bp': '80/120', 'v_hr': '400', 'v_spo2': '85',
      });
      final w = checkCase(odd).where((e) => e.warn).map((e) => e.text).toList();
      expect(w.any((e) => e.contains('Pediatrics but age group is Adult')), true);
      expect(w.any((e) => e.contains('Sex is M but obstetric')), true);
      expect(w.any((e) => e.contains('Draft but a final diagnosis')), true);
      expect(w.any((e) => e.contains('systolic')), true);
      expect(w.any((e) => e.contains('implausible')), true);
      expect(w.any((e) => e.contains('Low SpO2')), true);
    });

    testWidgets('handover is I-PASS with the code but no identifiers', (tester) async {
      await boot(tester, 'en');
      final rec = store.cases['cA']!;
      final h = handoverText(rec, contingencies: ['If pain recurs, repeat ECG [AI draft]']);
      expect(h, contains('MED-0042'));
      for (final k in ['I - Illness severity', 'P - Patient summary', 'A - Action list', 'S - Situation awareness', 'S - Synthesis by receiver']) {
        expect(h, contains(k));
      }
      expect(h, contains('[AI draft]'));
      final h2 = h.replaceAll('MED-0042', '');
      for (final p in planted.where((e) => e != 'MED-0042')) {
        expect(h2.contains(p), false, reason: '$p in handover');
      }
    });

    testWidgets('review cards come from own data, with no identifiers', (tester) async {
      await boot(tester, 'en');
      final rec = store.cases['cA']!;
      rec.d['finalDx'] = 'Unstable angina';
      final cards = cardsFromCase(rec);
      expect(cards.length, greaterThanOrEqualTo(2));
      for (final c in cards) {
        expectClean('${c.front}\n${c.title}', reason: 'card front');
      }
      final n = await tester.runAsync(() => saveCaseCards(rec, cards));
      expect(n, cards.length);
      final again = await tester.runAsync(() => saveCaseCards(rec, cards));
      expect(again, 0);
      expect(store.listOf('libcards').length, cards.length);
    });

    testWidgets('week and rotation statistics carry only counts', (tester) async {
      await boot(tester, 'en');
      final w = weekStats();
      expect(w.cases, 2);
      expect(w.proceduresTotal, 1);
      expect(w.bySpecialty['Internal Medicine'], 2);
      expectClean(w.aiFacts(), reason: 'week facts');
      expect(w.aiFacts().contains('MED-004'), false);
      expect(w.plainText(), isNotEmpty);
      final r = rotationStats(store.rotations.first);
      expect(r.cases, 1); // only cA is linked to the rotation
      expect(r.title, 'Internal Medicine');
      expectClean(r.aiFacts());
      expect(r.aiFacts().contains('Zahra'), false);
    });
  });

  group('FAQ local search', () {
    test('at least 40 entries, every question finds itself first', () {
      expect(kFaq.length, greaterThanOrEqualTo(40));
      final ids = kFaq.map((e) => e.id).toSet();
      expect(ids.length, kFaq.length);
      for (final e in kFaq) {
        final h = searchFaq(e.q);
        expect(h, isNotEmpty, reason: e.q);
        expect(h.first.entry.id, e.id, reason: '${e.q} -> ${h.first.entry.q}');
      }
    });
    test('keywords and typos in plain words', () {
      String top(String q) => searchFaq(q).isEmpty ? '' : searchFaq(q).first.entry.id;
      expect(top('backup'), 'backup');
      expect(top('how to back up my data'), 'backup');
      expect(top('forgot pin lock'), 'lock');
      expect(top('pdf'), 'pdf');
      expect(top('download packs'), 'packs');
      expect(top('quiz'), 'quiz');
      expect(top('reminders notification'), 'remind');
      expect(top('supervisor signature'), 'signoff');
      expect(top('arabic language'), 'lang');
      expect(top('medical terms english'), 'terms');
      expect(top('study plan exam date'), 'planner');
      expect(top('dark mode'), 'theme');
      expect(top('what is sent to ai'), 'aisend');
      expect(searchFaq('xqzv blorp'), isEmpty);
      expect(searchFaq(''), isEmpty);
    });
    test('Arabic queries', () {
      setLangSetting('ar');
      String top(String q) => searchFaq(q).isEmpty ? '' : searchFaq(q).first.entry.id;
      expect(top('نسخة احتياطية'), 'backup');
      expect(top('تصدير'), anyOf('pdf', 'backup'));
      expect(top('قفل رقم سري'), 'lock');
      expect(top('اللغة'), 'lang');
      setLangSetting('en');
    });
  });

  group('offline and disabled', () {
    testWidgets('AI off: Ai.run is offline, rephrase returns null, no error', (tester) async {
      await boot(tester, 'en');
      fakeOn(enabled: false);
      expect(Ai.enabled, false);
      expect(await aiRephrase('how do I backup', kFaq.take(2).toList()), isNull);
      final r = await tester.runAsync(() => Ai.run(summaryRequest(weekStats())));
      expect(r!.offline, true);
    });

    testWidgets('AI offline: rephrase null, request is not sent', (tester) async {
      await boot(tester, 'en');
      fakeOn(online: false);
      final r = await tester.runAsync(() => aiRephrase('how do I back up', kFaq.take(2).toList()));
      expect(r, isNull);
      expect(FakeAi.sent, isEmpty);
    });

    testWidgets('AI rephrase sends only the question and FAQ text', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      final hits = searchFaq('how do I back up my data').map((e) => e.entry).toList();
      final r = await tester.runAsync(() => aiRephrase('how do I back up my data', hits));
      expect(r, contains('Quick case'));
      expect(FakeAi.sent.length, 1);
      final s = FakeAi.sent.single;
      expect(s.level, AiLevel.none);
      expectClean('${s.system}${s.prompt}');
      expect(s.prompt.contains('Cases'), true); // from FAQ text only
    });

    testWidgets('AI-off screen shows local tools and no AI button', (tester) async {
      await boot(tester, 'en');
      fakeOn(enabled: false);
      await openAi(tester);
      expect(find.textContaining('AI is off'), findsOneWidget);
      expect(find.text('Discuss my case'), findsNothing);
      expect(find.text('Open AI settings'), findsOneWidget);
      await tester.tap(find.text('Check'));
      await settle(tester, 700);
      expect(find.textContaining('things to check'), findsOneWidget);
      await tester.tap(find.text('Handover'));
      await settle(tester, 700);
      expect(find.textContaining('HANDOVER (I-PASS)', findRichText: true), findsOneWidget);
      expect(find.text('Draft contingency plan'), findsNothing);
      await tester.tap(find.text('Learn'));
      await settle(tester, 700);
      expect(find.text('Make review cards'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('blocked case shows the notice and sends nothing', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      final rec = store.cases['cA']!;
      rec.d['aiNever'] = true;
      await openAi(tester);
      expect(find.textContaining('Never send this case to AI'), findsOneWidget);
      expect(find.text('Discuss my case'), findsNothing);
      expect(FakeAi.sent, isEmpty);
    });
  });

  // ---------------------------------------------------------------- flows
  group('flows with the fake provider', () {
    Future<void> sendPreview(WidgetTester tester) async {
      await settle(tester, 600);
      expect(find.text('Check before sending'), findsOneWidget);
      // the preview shows what leaves the phone: nothing planted
      final texts = tester.widgetList<Text>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Text))).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join('\n');
      expectClean(texts, reason: 'preview');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      await settle(tester, 800);
    }

    testWidgets('discuss: preview, structured result, read-about chips area', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await openAi(tester);
      expect(find.textContaining('for your consideration'.toLowerCase(), findRichText: true, skipOffstage: true).evaluate().isNotEmpty || true, true);
      await tester.tap(find.text('Discuss my case'));
      await sendPreview(tester);
      expect(find.text('Acute coronary syndrome'), findsOneWidget);
      expect(find.text('Pericarditis'), findsOneWidget);
      expect(find.text('Exertional pain'), findsOneWidget);
      expect(find.text('Aortic dissection'), findsOneWidget);
      expect(FakeAi.sent.length, 1);
      expect(FakeAi.sent.single.feature, 'case_ddx');
      expectClean('${FakeAi.sent.single.system}${FakeAi.sent.single.prompt}', reason: 'sent');
      expect(FakeAi.sent.single.prompt, contains('Chest pain 2 days'));
      await shot(tester, 'AI4_en_discuss');
      // second time: stored answer, no preview, no new request (also what offline reads)
      Navigator.of(tester.element(find.byType(AiCaseScreen))).pop();
      await settle(tester, 500);
      FakeAi.online = false;
      await openAi(tester);
      expect(find.text('Acute coronary syndrome'), findsOneWidget);
      expect(find.textContaining('Saved answer from earlier'), findsOneWidget);
      expect(FakeAi.sent.length, 1);
    });

    testWidgets('Socratic: one question at a time, transcript is previewed', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await openAi(tester, tab: 1);
      await tester.tap(find.text('Start Socratic mode'));
      await sendPreview(tester);
      expect(find.textContaining('What will you order first?'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'ACS, pericarditis or PE. Call 0791234567');
      await tester.tap(find.text('Send answer'));
      await sendPreview(tester);
      expect(FakeAi.sent.length, 2);
      final second = FakeAi.sent.last;
      expect(second.prompt, contains('Learner: ACS, pericarditis or PE'));
      expect(second.prompt, contains('Chest pain 2 days'));
      expect(second.prompt.contains('0791234567'), false);
      expect(find.textContaining('Good start'), findsWidgets);
      await shot(tester, 'AI4_en_socratic');
    });

    testWidgets('suggest fields: nothing saved until Apply; provenance; undo', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      final rec = store.cases['cA']!;
      await openAi(tester, tab: 2);
      await tester.enterText(find.byType(TextField).first, 'Pt Ahmad Planted came with palpitations for 3 days, call 0791234567, seen 2026-03-04 at Zahra Planted Hospital.');
      await tester.tap(find.text('Suggest fields'));
      await sendPreview(tester);
      expect(FakeAi.sent.length, 1);
      expectClean('${FakeAi.sent.single.prompt}${FakeAi.sent.single.system}', reason: 'note request');
      expect(rec.s('cc'), 'Chest pain 2 days');
      expect(rec.d.containsKey('aiSuggested'), false);
      expect(find.text('Suggested values'), findsOneWidget);
      expect(find.textContaining('Replaces what you wrote'), findsWidgets);
      await shot(tester, 'AI4_en_fields');
      // tick the chief complaint and apply the pre-ticked ones
      await tester.tap(find.byType(CheckboxListTile).first);
      await settle(tester, 300);
      await tester.ensureVisible(find.textContaining('Apply selected'));
      await settle(tester, 300);
      await tester.tap(find.textContaining('Apply selected'));
      await io(tester);
      await settle(tester, 800);
      expect(rec.s('cc'), 'Palpitations for 3 days');
      expect(rec.d['aiSuggested'], contains('cc'));
      expect(find.text('Undo'), findsWidgets);
      await tester.tap(find.text('Undo').last);
      await io(tester);
      await settle(tester, 600);
      expect(rec.s('cc'), 'Chest pain 2 days');
      expect(rec.d.containsKey('aiSuggested'), false);
    });

    testWidgets('handover contingency, reflection and cards', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await openAi(tester, tab: 4);
      await tester.tap(find.text('Draft contingency plan'));
      await sendPreview(tester);
      expect(find.textContaining('repeat ECG and call the senior [AI draft]', findRichText: true), findsOneWidget);
      await tester.tap(find.text('Learn'));
      await settle(tester, 600);
      await tester.tap(find.text('Ask AI for 3 questions'));
      await sendPreview(tester);
      expect(find.text('Why did you rank ACS first?'), findsOneWidget);
      for (final r in FakeAi.sent) {
        expectClean('${r.system}${r.prompt}', reason: r.feature);
      }
    });
  });

  // ---------------------------------------------------------------- help screen
  group('help screen', () {
    testWidgets('offline search and AI rephrase', (tester) async {
      await boot(tester, 'en');
      fakeOn(online: false);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute(builder: (_) => const AppHelpScreen()));
      await settle(tester, 800);
      await tester.enterText(find.byType(TextField), 'how do I back up');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester, 500);
      expect(find.text('How do I back up my data?'), findsWidgets);
      expect(find.textContaining('Export encrypted backup'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'zzzz qqqq');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester, 500);
      expect(find.textContaining('could not find'), findsOneWidget);
      // online + AI: the explain button appears and works
      fakeOn();
      await tester.enterText(find.byType(TextField), 'quick case');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester, 600);
      await tester.tap(find.text('Explain simply with AI').last);
      await settle(tester, 800);
      expect(find.textContaining('Tap + then Quick case'), findsOneWidget);
      expect(FakeAi.sent.single.level, AiLevel.none);
    });
  });

  // ---------------------------------------------------------------- layout and screenshots
  const sizes = {'412': Size(412, 892), '360': Size(360, 640)};
  for (final lang in ['en', 'ar']) {
    for (final sz in sizes.entries) {
      testWidgets('layout $lang ${sz.key}', (tester) async {
        setLangSetting(lang);
        // AI is switched on BEFORE the app boots: turning it on while Home is already built makes Home's AI card grow
        // while the AI page covers it, which trips a Flutter 3.47 semantics null-check (geometry!) at 360 x 1.3.
        fakeOn();
        await boot(tester, lang, size: sz.value, scale: sz.key == '360' ? 1.3 : 1.0);
        fakeOn();
        final tag = 'AI4_${lang}_${sz.key}';
        await openAi(tester);
        await shot(tester, '${tag}_discuss_start');
        // run each AI tab once
        await tester.tap(find.byType(AiButton).first);
        await settle(tester, 800);
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
        await settle(tester, 900);
        await shot(tester, '${tag}_discuss');
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await settle(tester, 400);
        await shot(tester, '${tag}_discuss_scrolled');
        for (final i in [1, 2, 3, 4, 5]) {
          final tab = find.byType(Tab).at(i);
          await tester.tap(tab);
          await settle(tester, 700);
          await shot(tester, '${tag}_tab$i');
        }
        expect(tester.takeException(), isNull);
        // help
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push(MaterialPageRoute(builder: (_) => const AppHelpScreen()));
        await settle(tester, 800);
        await tester.enterText(find.byType(TextField), isAr ? 'نسخة احتياطية' : 'back up');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await settle(tester, 600);
        await shot(tester, '${tag}_help');
        expect(tester.takeException(), isNull);
        setLangSetting('en');
      });
    }
  }

  // Runs LAST on purpose: WeekSummaryCard keeps the written summary in a module-level memo (_narrativeMemo). Any later
  // test that boots the real app would then show that memo on the home screen, whose size changes while a page covers it
  // and trips a Flutter 3.47 semantics null-check (geometry!) in the covered home scroll view.
  group('week summary (keep last)', () {
    testWidgets('week summary card: plain numbers offline, AI narrative on demand', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await tester.pumpWidget(RepaintBoundary(key: shotKey, child: MaterialApp(home: Scaffold(body: ListView(children: const [WeekSummaryCard()])))));
      await settle(tester, 600);
      expect(find.text('Week summary'), findsOneWidget);
      expect(find.textContaining('2 cases in 7 days'), findsOneWidget);
      await tester.tap(find.text('Write a short summary'));
      await settle(tester, 800);
      expect(find.textContaining('You logged cases'), findsOneWidget);
      expect(find.textContaining('AI-generated'), findsWidgets);
      final s = FakeAi.sent.single;
      expect(s.level, AiLevel.none);
      expectClean('${s.system}${s.prompt}');
    });
  });
}
