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
import 'package:medlog/ai/ai_context.dart';
import 'package:medlog/ai/ai_engine.dart';
import 'package:medlog/ai/ai_help.dart';
import 'package:medlog/ai/ai_prefs.dart';
import 'package:medlog/ai/ai_quiz.dart' show aiBank;
import 'package:medlog/ai/ai_tools.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' show setLangSetting;
import 'package:medlog/main.dart';
import 'package:medlog/screens_ai_cases.dart';
import 'package:medlog/screens_ai_tools.dart';
import 'package:medlog/screens_calc.dart';
import 'package:medlog/screens_cases.dart';
import 'package:medlog/screens_home.dart';
import 'package:medlog/screens_portfolio.dart';
import 'package:medlog/screens_search.dart';
import 'package:medlog/screens_skills.dart';
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
  'Planted', 'Zahra', '0791234567', '4455667', 'MED-0042', 'MED-0044', 'Q.Z.', 'Baker', 'SECRETLEARNED', 'SECRETTEACH', 'img_secret123',
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

Future<void> boot(WidgetTester tester, String lang, {Size size = const Size(412, 892), double scale = 1.0}) async {
  final dir = Directory.systemTemp.createTempSync('medlog').path;
  PathProviderPlatform.instance = FakePP(dir);
  Directory('$dir/medlog/cases').createSync(recursive: true);
  Directory('$dir/medlog/images').createSync(recursive: true);
  File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({
    'lang': lang, 'author': 'Dr. Planted Author', 'palette': 'clinic', 'deviceId': 'x', 'textScale': scale,
    'lastBackup': DateTime.now().toIso8601String(),
  }));
  File('$dir/medlog/rotations.json').writeAsStringSync(jsonEncode([
    {
      'id': 'r1', 'name': 'Internal Medicine', 'hospital': 'Zahra Planted Hospital', 'start': d(14), 'end': d(-16),
      'targets': [{'id': 't1', 'kind': 'cases', 'label': 'Cases', 'target': 10}],
    },
  ]));
  File('$dir/medlog/procedures.json').writeAsStringSync(jsonEncode([
    {'id': 'p1', 'name': 'IV cannulation', 'role': 'Performed under supervision', 'date': d(1), 'rotationId': 'r1'},
  ]));
  File('$dir/medlog/cases/cA.json').writeAsStringSync(jsonEncode(plantedCase()));
  File('$dir/medlog/cases/cB.json').writeAsStringSync(jsonEncode({
    'id': 'cB', 'schema': 2, 'created': '2026-10-11T08:00:00Z', 'date': d(2), 'code': 'MED-0043', 'specialty': 'Internal Medicine',
    'status': 'Completed', 'cc': 'Cough', 'tags': ['cardio'],
  }));
  // untagged cases: cC (usable), cD (flagged never-send), cE (today, draft)
  File('$dir/medlog/cases/cC.json').writeAsStringSync(jsonEncode({
    'id': 'cC', 'schema': 2, 'created': '2026-10-12T08:00:00Z', 'date': d(3), 'code': 'MED-0044', 'initials': 'Z.Z.', 'specialty': 'Internal Medicine',
    'ageGroup': 'Adult', 'sex': 'F', 'status': 'Active', 'cc': 'Polyuria and thirst', 'workingDx': 'Diabetic ketoacidosis',
    'hpi': 'Ms Zahra Planted, phone 0791234567', 'tags': [],
  }));
  File('$dir/medlog/cases/cD.json').writeAsStringSync(jsonEncode({
    'id': 'cD', 'schema': 2, 'created': '2026-10-12T09:00:00Z', 'date': d(3), 'code': 'MED-0045', 'specialty': 'Internal Medicine',
    'status': 'Active', 'cc': 'NEVERSEND complaint', 'workingDx': 'NEVERSEND dx', 'aiNever': true, 'tags': [],
  }));
  File('$dir/medlog/cases/cE.json').writeAsStringSync(jsonEncode({
    'id': 'cE', 'schema': 2, 'created': '2026-10-12T10:00:00Z', 'date': d(0), 'code': 'MED-0046', 'specialty': 'Internal Medicine',
    'status': 'Draft', 'cc': 'Headache', 'tags': ['neuro'],
  }));
  AiEngine.debugOnline = true; // no connectivity plugin in tests
  await tester.runAsync(() => store.init());
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
  await settle(tester, 3800);
}

Future<void> push(WidgetTester tester, Widget w, [int ms = 1000]) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute<void>(builder: (_) => w));
  await settle(tester, ms);
}

/// Pops the top route and opens a fresh instance (the AI state is read again).
Future<void> reopen(WidgetTester tester, Widget w, [int ms = 1000]) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.pop();
  await settle(tester, 500);
  await push(tester, w, ms);
}

void expectClean(String text, {String reason = ''}) {
  for (final p in planted) {
    expect(text.contains(p), false, reason: '$reason "$p" leaked in: $text');
  }
  expect(text.contains('NEVERSEND'), false, reason: '$reason never-send case leaked');
}

const _docSenior = '{"title":"Senior view","sections":['
    '{"kind":"key_points","title":"Likely questions","bullets":["What is your differential?","Why did you order troponin?"]},'
    '{"kind":"investigations","title":"Next orders","bullets":["Serial ECG"]}],"citations":[]}';

const _docGuide = '{"title":"Guidelines","sections":[{"kind":"guidelines","title":"Guidelines","table":['
    '["Organisation","Year","Guideline","Key recommendation"],["ESC","2023","ACS guideline","Early invasive strategy in high risk"]],'
    '"cites":[{"org":"ESC","year":"2023","url":"https://www.escardio.org/guidelines/acs","label":"ESC 2023"}]}],'
    '"citations":[{"org":"ESC","year":"2023","url":"https://www.escardio.org/guidelines/acs","label":"ESC 2023"}]}';

const _docTeach = '{"title":"Teaching","sections":[{"kind":"key_points","title":"Teaching points","bullets":['
    '"Troponin should be repeated at 3 hours in suspected ACS according to the ESC guideline [1]",'
    '"Aspirin loading is given early unless contraindicated according to the ESC guideline [1]"],'
    '"cites":[{"org":"ESC","year":"2023","url":"https://www.escardio.org/guidelines/acs","label":"ESC 2023"}]}],'
    '"citations":[{"org":"ESC","year":"2023","url":"https://www.escardio.org/guidelines/acs","label":"ESC 2023"}],'
    '"quiz":[{"q":"Which marker is repeated in suspected ACS?","options":["Troponin","Amylase","CRP","Ferritin"],"answer":0,"why":"Serial troponin is used.",'
    '"cite":{"org":"ESC","year":"2023","url":"https://www.escardio.org/guidelines/acs"}},'
    '{"q":"Uncited question about aspirin?","options":["Yes","No"],"answer":0,"why":"No cite given."}]}';

const _drugOk = '{"findings":[{"statement":"Concurrent use of warfarin and aspirin increases bleeding risk.","org":"NICE","year":"2023","url":"https://www.nice.org.uk/guidance/ng196"}],"no_source":false}';

void main() {
  setUpAll(() async {
    final rb = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  void fakeOn({bool online = true, bool enabled = true, Map<String, String> extra = const {}}) {
    installFakeAi(online: online, enabled: enabled, answers: {
      'case_senior': _docSenior,
      'case_guideline': _docGuide,
      'case_patient': '{"title":"Patient","sections":[{"kind":"overview","title":"What is going on","text":"Your heart muscle may not be getting enough blood."},{"kind":"steps","title":"What happens next","bullets":["We repeat the heart tracing","We check a blood test again"]}]}',
      'case_teach': _docTeach,
      'case_tags_bulk': '{"cases":[{"n":1,"tags":["#diabetes","dka","bad tag!!"]},{"n":9,"tags":["outside"]}]}',
      'ask_score': '{"sections":[{"kind":"table","title":"Scores","table":[["Score","Why it fits","Inputs needed","Source"],["CURB-65","Pneumonia severity","Confusion, urea, RR, BP, age","BTS 2009"]],"cites":[{"org":"BTS","year":"2009","url":"https://www.nice.org.uk/x"}]}]}',
      'ask_calc_interpret': '{"sections":[{"kind":"overview","title":"Meaning","text":"A score of 0 to 1 is low risk according to BTS 2009."}],"citations":[{"org":"BTS","year":"2009","url":"https://www.nice.org.uk/x"}]}',
      'summary_brief': 'You have 2 cases and no flashcards due. Suggestion: review one weak topic today.',
      'report_reflection': '{"title":"Chest pain on the ward","happened":"I saw a patient with exertional chest pain.","felt":"I felt unsure about the ECG.","learned":"I learned to repeat troponin.","next":"I will read the ACS guideline."}',
      'report_gap': '{"sections":[{"kind":"overview","title":"Where you are","text":"Cases are behind."},{"kind":"steps","title":"Next actions","bullets":["Log one case per day","Review two flashcards"]}]}',
      'report_cv': 'Intern in internal medicine with 5 logged cases and 1 procedure.',
      'report_logbook': 'The logbook holds a mix of cases.',
      'ask_procedure': '{"sections":[{"kind":"steps","title":"Steps","bullets":["Explain and consent","Clean the skin"],"cites":[{"org":"WHO","year":"2010","url":"https://www.who.int/x"}]},{"kind":"key_points","title":"Consent points","bullets":["Risks: bruising"]}],"citations":[{"org":"WHO","year":"2010","url":"https://www.who.int/x"}]}',
      'quiz_case_of_day': '{"sections":[{"kind":"overview","title":"Case","text":"A fictional teaching vignette."}]}',
      'ask_drug': _drugOk,
      'help_faq': '1. Tap Calculators.',
      ...extra,
    });
    AiStore.allowCase = true;
    AiStore.caseConsented = true;
    AiStore.allowLibrary = true;
    AiEngine.fakeSearchOk = true;
    AiEngine.fakeSources = const [AiSource(title: 'NICE', url: 'https://www.nice.org.uk/guidance/ng196', host: 'nice.org.uk')];
    AiPrefs.sourceMode; // read once
  }

  setUp(() {
    setLangSetting('en');
    uninstallFakeAi();
  });

  Future<void> tapV(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(f);
    await settle(tester, 200);
    await tester.tap(f, warnIfMissed: false);
  }

  Future<void> sendPreview(WidgetTester tester) async {
    await settle(tester, 700);
    expect(find.byType(AlertDialog), findsOneWidget);
    final texts = tester.widgetList<Text>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Text))).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join('\n');
    expectClean(texts, reason: 'preview');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await settle(tester, 900);
  }

  // ================================================================ privacy and logic
  group('case tool requests: privacy', () {
    testWidgets('every builder uses only the payload; planted identifiers never leak', (tester) async {
      await boot(tester, 'en');
      final p = buildCasePayload(store.cases['cA']!);
      final reqs = [
        seniorRequest(p), guidelineRequest(p), patientExplainRequest(p), teachRequest(p), reflectionDraftRequest(p), scoreFinderRequest(p: p),
      ];
      for (final r in reqs) {
        expect(r.level, AiLevel.caseData, reason: r.feature);
        expect(r.previewFields, isNotNull);
        expect(r.previewFields!.isNotEmpty, true, reason: r.feature);
        expectClean('${r.system}\n${r.prompt}\n${jsonEncode(r.previewFields)}', reason: r.feature);
        for (final k in r.previewFields!.keys) {
          expect(kPayloadLabels.contains(k) || (kSpecialtyFields['Internal Medicine'] ?? []).any((f) => f[1] == k), true, reason: '${r.feature}: $k');
        }
      }
      // the guideline request sends only the diagnosis block, not history, labs or drugs
      final g = guidelineRequest(p);
      expect(g.previewFields!.keys.toSet().difference({...kGuidelineLabels, 'Chief complaint'}), isEmpty);
      expect(g.previewFields!['Working diagnosis'], 'Acute coronary syndrome');
      expect(g.previewFields!.containsKey('Medications'), false);
      expect(g.previewFields!.containsKey('Investigations'), false);
      expect(g.system, contains('no patient-specific orders'.replaceAll('no ', 'do NOT give ').isEmpty ? '' : 'patient-specific orders'));
      // typed score descriptions are scrubbed, level none
      final s = scoreFinderRequest(description: 'Pt phone 0791234567 with fever and cough');
      expect(s.level, AiLevel.none);
      expect(s.prompt.contains('0791234567'), false);
      expect(s.previewFields, isNull);
    });

    testWidgets('a never-send case gives an empty payload, is not tagged in bulk and not in untaggedCases', (tester) async {
      await boot(tester, 'en');
      final nev = store.cases['cD']!;
      expect(isCaseAiBlocked(nev), true);
      expect(buildCasePayload(nev).blocked, true);
      final un = untaggedCases();
      expect(un.map((c) => c.id), ['cC']);
      final req = bulkTagsRequest(untaggedCases());
      expectClean('${req.system}${req.prompt}${jsonEncode(req.previewFields)}', reason: 'bulk');
      expect(req.previewFields!.length, 1);
      expect(req.previewFields!['Case 1'], contains('Diabetic ketoacidosis'));
      expect(req.previewFields!['Case 1']!.contains('MED-0044'), false);
      expect(req.level, AiLevel.caseData);
    });

    testWidgets('bulk tag parsing keeps only valid positions and clean tags', (tester) async {
      await boot(tester, 'en');
      final m = parseBulkTags(jsonDecode('{"cases":[{"n":1,"tags":["#Diabetes","dka","bad tag!!","dka"]},{"n":9,"tags":["outside"]},{"n":"x","tags":["y"]}]}') as Map<String, dynamic>, 1);
      expect(m.keys, [1]);
      expect(m[1], ['diabetes', 'dka']);
    });

    testWidgets('mini quiz: only cited questions are saved to the AI bank', (tester) async {
      await boot(tester, 'en');
      final j = jsonDecode(_docTeach) as Map<String, dynamic>;
      final qs = parseMiniQuiz(j);
      expect(qs.length, 2);
      expect(qs[0].cite, isNotNull);
      expect(qs[1].cite, isNull);
      final n = await tester.runAsync(() => saveMiniQuiz(qs));
      expect(n, 1);
      expect(aiBank().where((q) => q.stem.startsWith('Which marker')).length, 1);
      expect(await tester.runAsync(() => saveMiniQuiz(qs)), 0);
    });
  });

  group('drug check: cited-only', () {
    testWidgets('web mode: a cited answer on the allow-list is shown; request carries no case data', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      final r = (await tester.runAsync(() => runDrugCheck(DrugQuery(DrugKind.interaction, ['warfarin', 'aspirin 0791234567']))))!;
      expect(r.status, DrugStatus.answered);
      expect(r.findings.single.cite.org, 'NICE');
      expect(r.findings.single.confirmed, true);
      final s = FakeAi.sent.single;
      expect(s.level, AiLevel.none);
      expect(s.search, isNotNull);
      expect(s.search!.domains, contains('nice.org.uk'));
      expectClean('${s.system}${s.prompt}');
      expect(s.prompt.contains('0791234567'), false);
      expect(s.prompt, contains('warfarin'));
    });

    testWidgets('off-list domain, missing year or no source -> no answer', (tester) async {
      await boot(tester, 'en');
      for (final a in [
        '{"findings":[{"statement":"x is safe","org":"RandomBlog","year":"2023","url":"https://randomblog.example.com/x"}],"no_source":false}',
        '{"findings":[{"statement":"x is safe","org":"NICE","year":"","url":"https://www.nice.org.uk/x"}],"no_source":false}',
        '{"findings":[{"statement":"x is safe","org":"NICE","year":"2023","url":"https://evilnice.org.uk/x"}],"no_source":false}',
        '{"findings":[{"statement":"x is safe","org":"NICE","year":"2023","url":"http://nice.org.uk.evil.com/x"}],"no_source":false}',
        '{"findings":[],"no_source":true}',
        'plain text answer without json',
      ]) {
        fakeOn(extra: {'ask_drug': a});
        final r = (await tester.runAsync(() => runDrugCheck(DrugQuery(DrugKind.renal, ['metformin']))))!;
        expect(r.status, DrugStatus.noSource, reason: a);
        expect(r.findings, isEmpty);
      }
    });

    testWidgets('a host the live search did not return is dropped', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      AiEngine.fakeSources = const [AiSource(title: 'CDC', url: 'https://www.cdc.gov/x', host: 'cdc.gov')];
      final r = (await tester.runAsync(() => runDrugCheck(DrugQuery(DrugKind.pregnancy, ['lisinopril']))))!;
      expect(r.status, DrugStatus.noSource);
    });

    testWidgets('model mode and empty library mode send nothing and give no answer', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      AiPrefs.sourceMode = 'model';
      var r = (await tester.runAsync(() => runDrugCheck(DrugQuery(DrugKind.hepatic, ['paracetamol']))))!;
      expect(r.status, DrugStatus.noSource);
      expect(r.reason, 'mode');
      AiPrefs.sourceMode = 'library';
      r = (await tester.runAsync(() => runDrugCheck(DrugQuery(DrugKind.hepatic, ['paracetamol']))))!;
      expect(r.status, DrugStatus.noSource);
      expect(FakeAi.sent, isEmpty);
      AiPrefs.sourceMode = 'web';
    });

    testWidgets('AI off / offline / invalid input', (tester) async {
      await boot(tester, 'en');
      fakeOn(enabled: false);
      expect((await tester.runAsync(() => runDrugCheck(DrugQuery(DrugKind.renal, ['metformin']))))!.status, DrugStatus.off);
      fakeOn(online: false);
      expect((await tester.runAsync(() => runDrugCheck(DrugQuery(DrugKind.renal, ['metformin']))))!.status, DrugStatus.offline);
      fakeOn();
      expect((await tester.runAsync(() => runDrugCheck(DrugQuery(DrugKind.interaction, ['warfarin']))))!.status, DrugStatus.noSource); // needs two drugs
      expect(FakeAi.sent, isEmpty);
    });
  });

  group('morning brief and portfolio drafts', () {
    testWidgets('local numbers come from the phone; AI facts hold only aggregates', (tester) async {
      await boot(tester, 'en');
      final b = buildMorningBrief();
      expect(b.casesToday, 1); // cE (draft) is dated today
      expect(b.drafts, 1);
      expect(b.rotation, 'Internal Medicine');
      expect(b.rotDays, greaterThan(20));
      expect(b.reviewDue, 0);
      expect(b.lines().first, '1 cases today');
      expect(b.lines().any((l) => l.contains('Internal Medicine')), true);
      final req = briefRequest(b);
      expect(req.level, AiLevel.none);
      expectClean('${req.system}${req.prompt}', reason: 'brief');
      expect(req.prompt.contains('Zahra'), false);
    });

    testWidgets('reflection draft is marked as a draft; CV and gap requests are aggregate only', (tester) async {
      await boot(tester, 'en');
      final e = reflectionEntryFrom(jsonDecode('{"title":"Chest pain","happened":"a","felt":"b","learned":"c","next":"d"}') as Map<String, dynamic>);
      expect(e['title'], startsWith('AI draft: '));
      expect(e['aiDraft'], true);
      final st = statsOfCases(store.cases.values.toList(), store.procedures, title: 'All');
      final cv = cvRequest(st);
      final gap = goalGapRequest(goalGaps(), weekStats());
      for (final r in [cv, gap, periodNarrativeRequest(st)]) {
        expect(r.level, AiLevel.none);
        expectClean('${r.system}${r.prompt}', reason: r.feature);
      }
      expect(cv.system, contains('never invent'));
    });

    testWidgets('logbook narrative: AI off -> null, AI on -> text, no case content sent', (tester) async {
      await boot(tester, 'en');
      final st = statsOfCases(store.cases.values.toList(), store.procedures, title: 'All');
      fakeOn(enabled: false);
      expect(await tester.runAsync(() => logbookNarrative(st)), isNull);
      fakeOn();
      expect(await tester.runAsync(() => logbookNarrative(st)), contains('logbook'));
      expectClean('${FakeAi.sent.single.system}${FakeAi.sent.single.prompt}');
    });
  });

  group('prompts and FAQ', () {
    testWidgets('English by default, sources by mode, domains restricted', (tester) async {
      await boot(tester, 'en');
      expect(AiPrefs.answerLang, 'en');
      final web = AiToolPrompts.base('Task X');
      expect(web, contains('English'));
      expect(web, contains('nice.org.uk'));
      expect(web, contains('year'));
      expect(AiToolPrompts.search(), isNotNull);
      AiPrefs.sourceMode = 'model';
      expect(AiToolPrompts.search(), isNull);
      AiPrefs.sourceMode = 'web';
      AiPrefs.answerLang = 'mixed';
      expect(AiToolPrompts.base('Task X'), contains('Arabic'));
      AiPrefs.answerLang = 'en';
    });

    test('new FAQ entries cover the new features and are findable', () {
      String top(String q) => searchFaq(q).isEmpty ? '' : searchFaq(q).first.entry.id;
      for (final id in ['aiask', 'aisources', 'ailang', 'aiformat', 'aibank', 'aiviva', 'aiguide', 'aivoice', 'aidrug', 'aiscore', 'aibrief', 'aiportfolio', 'aisettings', 'aigate', 'aioff']) {
        expect(kFaq.any((e) => e.id == id), true, reason: id);
      }
      expect(top('floating ask ai button'), 'aiask');
      expect(top('drug check interaction'), 'aidrug');
      expect(top('morning brief'), 'aibrief');
      expect(top('what is sent to ai'), 'aisend');
      setLangSetting('ar');
      expect(top('فحص دواء'), 'aidrug');
      setLangSetting('en');
    });
  });

  // ================================================================ gating (widgets)
  group('gating: AI off / offline / on', () {
    testWidgets('Calculators: entries visible; off = disabled + Turn on AI; offline = note; on = works', (tester) async {
      await boot(tester, 'en');
      store.settings['folds'] = {'cl_curb': true};
      fakeOn(enabled: false);
      await push(tester, const CalculatorsScreen());
      expect(AiContext.current.value?.kind, 'calc');
      expect(find.byKey(const ValueKey('calc_which_score')), findsOneWidget);
      expect(find.byKey(const ValueKey('calc_drug_check')), findsOneWidget);
      expect(find.textContaining('Turn on AI'), findsWidgets);
      final off = tester.widget<OutlinedButton>(find.descendant(of: find.byKey(const ValueKey('calc_which_score')), matching: find.byType(OutlinedButton)));
      expect(off.onPressed, isNull);
      await tester.ensureVisible(find.text('Interpret my result'));
      await settle(tester, 300);
      expect(find.text('Interpret my result'), findsOneWidget);
      expect(FakeAi.sent, isEmpty);
      await shot(tester, 'G5_calc_off');
      // offline
      fakeOn(online: false);
      await reopen(tester, const CalculatorsScreen());
      expect(find.textContaining('Needs internet'), findsWidgets);
      // on
      fakeOn();
      await reopen(tester, const CalculatorsScreen());
      await tester.ensureVisible(find.text('Interpret my result'));
      await settle(tester, 300);
      await tester.tap(find.text('Interpret my result'));
      await settle(tester, 900);
      expect(find.textContaining('low risk'), findsWidgets);
      expect(find.textContaining('AI-generated, not medically reviewed'), findsWidgets);
      final s = FakeAi.sent.single;
      expect(s.level, AiLevel.none);
      expect(s.prompt, contains('CURB-65'));
      expect(s.prompt, contains('Result: 0'));
      expectClean('${s.system}${s.prompt}');
      await shot(tester, 'G5_calc_on');
    });

    testWidgets('Which score fits: typed description (level none) and case with preview', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await push(tester, const WhichScoreScreen());
      await tester.enterText(find.byType(TextField).first, 'Elderly with cough, fever and confusion. Call 0791234567');
      await settle(tester, 300);
      await tester.tap(find.text('Which score fits?'));
      await settle(tester, 900);
      expect(find.textContaining('CURB-65'), findsWidgets);
      expect(find.textContaining('Open calculator'), findsWidgets);
      final s = FakeAi.sent.single;
      expect(s.level, AiLevel.none);
      expect(s.prompt.contains('0791234567'), false);
      expect(AiContext.current.value?.kind, 'calc');
    });

    testWidgets('Drug check screen: banner, no source, then a cited answer', (tester) async {
      await boot(tester, 'en');
      fakeOn(extra: {'ask_drug': '{"findings":[],"no_source":true}'});
      await push(tester, const DrugCheckScreen());
      expect(find.textContaining('hospital formulary'), findsWidgets);
      expect(find.textContaining('never combined with a patient case'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'warfarin');
      await tester.enterText(find.byType(TextField).at(1), 'aspirin');
      await settle(tester, 300);
      await tester.tap(find.text('Check with sources'));
      await settle(tester, 900);
      expect(find.text('No verified source found'), findsOneWidget);
      expect(find.textContaining('check your hospital formulary'), findsOneWidget);
      await shot(tester, 'G5_drug_nosource');
      fakeOn();
      await tester.tap(find.text('Check with sources'));
      await settle(tester, 900);
      expect(find.textContaining('increases bleeding risk'), findsOneWidget);
      expect(find.textContaining('NICE 2023'), findsOneWidget);
      expect(find.textContaining('Verify in your hospital formulary'), findsOneWidget);
      await shot(tester, 'G5_drug_answer');
    });

    testWidgets('Drug check with AI off: disabled with Turn on AI', (tester) async {
      await boot(tester, 'en');
      fakeOn(enabled: false);
      await push(tester, const DrugCheckScreen());
      await tester.enterText(find.byType(TextField).at(0), 'warfarin');
      await tester.enterText(find.byType(TextField).at(1), 'aspirin');
      await settle(tester, 300);
      final b = tester.widget<FilledButton>(find.descendant(of: find.byType(AiEntry), matching: find.byType(FilledButton)));
      expect(b.onPressed, isNull);
      expect(find.text('Turn on AI'), findsOneWidget);
      expect(FakeAi.sent, isEmpty);
    });

    testWidgets('Home: morning brief with local numbers works with AI off; AI paragraph on demand; AI card and bank link', (tester) async {
      await boot(tester, 'en');
      fakeOn(enabled: false);
      await push(tester, Scaffold(body: AiContextScope(ctx: const AiScreenContext(kind: 'home', title: 'Home'), child: ListView(children: const [MorningBriefCard(), HomeAiCard()]))));
      expect(AiContext.current.value?.kind, 'home');
      await tester.scrollUntilVisible(find.text('Morning brief'), 300, scrollable: find.byType(Scrollable).first);
      await settle(tester, 400);
      expect(find.text('Morning brief'), findsOneWidget);
      expect(find.textContaining('1 cases today'), findsOneWidget);
      expect(find.textContaining('flashcards due'), findsOneWidget);
      expect(find.text('Write my brief'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.descendant(of: find.byType(AiEntry), matching: find.byType(OutlinedButton)).first).onPressed, isNull);
      expect(find.text('AI question bank'), findsOneWidget);
      expect(find.text('Case of the day'), findsNothing); // shortcuts only when AI is on
      expect(FakeAi.sent, isEmpty);
      fakeOn();
      await reopen(tester, Scaffold(body: AiContextScope(ctx: const AiScreenContext(kind: 'home', title: 'Home'), child: ListView(children: const [MorningBriefCard(), HomeAiCard()]))));
      await tester.scrollUntilVisible(find.text('Morning brief'), 300, scrollable: find.byType(Scrollable).first);
      await settle(tester, 400);
      expect(find.text('Case of the day'), findsOneWidget);
      expect(find.text('Pre-shift quiz'), findsOneWidget);
      await tester.ensureVisible(find.text('Write my brief'));
      await tester.tap(find.text('Write my brief'));
      await settle(tester, 900);
      expect(find.textContaining('Suggestion: review one weak topic'), findsOneWidget);
      final s = FakeAi.sent.single;
      expect(s.level, AiLevel.none);
      expectClean('${s.system}${s.prompt}');
      await shot(tester, 'G5_home_brief');
    });

    testWidgets('Case assistant: Senior tab with preview, result and clean request', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await push(tester, AiCaseScreen(rec: store.cases['cA']!, initialTab: 6));
      expect(AiContext.current.value?.kind, 'case');
      expect(find.text('Prepare me for the senior'), findsOneWidget);
      await tester.tap(find.text('Prepare me for the senior'));
      await sendPreview(tester);
      expect(find.textContaining('What is your differential?'), findsWidgets);
      expect(FakeAi.sent.single.feature, 'case_senior');
      expectClean('${FakeAi.sent.single.system}${FakeAi.sent.single.prompt}');
      await shot(tester, 'G5_senior');
    });

    testWidgets('Case assistant: guidelines tab shows only the diagnosis block and a cited table', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await push(tester, AiCaseScreen(rec: store.cases['cA']!, initialTab: 7));
      await tester.tap(find.text('Link this case to guidelines'));
      await sendPreview(tester);
      expect(find.textContaining('ESC'), findsWidgets);
      final s = FakeAi.sent.single;
      expect(s.feature, 'case_guideline');
      expect(s.prompt.contains('Chest pain'), false);
      expect(s.prompt.contains('amlodipine'), false);
      expect(s.prompt, contains('Acute coronary syndrome'));
      expect(s.search, isNotNull);
    });

    testWidgets('Case assistant: patient draft is labelled; teach tab saves only cited questions', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await push(tester, AiCaseScreen(rec: store.cases['cA']!, initialTab: 8));
      await tester.tap(find.text('Explain this to a patient'));
      await sendPreview(tester);
      expect(find.textContaining('DRAFT for you to check'), findsOneWidget);
      expect(find.textContaining('heart muscle'), findsWidgets);
      // teach
      Navigator.of(tester.element(find.byType(AiCaseScreen))).pop();
      await settle(tester, 500);
      await push(tester, AiCaseScreen(rec: store.cases['cA']!, initialTab: 9));
      await tester.tap(find.text('Teaching points and mini quiz'));
      await sendPreview(tester);
      expect(find.text('Mini quiz'), findsOneWidget);
      expect(find.textContaining('Which marker is repeated'), findsOneWidget);
      await tester.ensureVisible(find.text('Show answer').first);
      await settle(tester, 200);
      await tester.tap(find.text('Show answer').first);
      await settle(tester, 300);
      expect(find.textContaining('Serial troponin is used.'), findsOneWidget);
      await tester.ensureVisible(find.text('Save cited questions to AI bank'));
      await settle(tester, 200);
      await tester.tap(find.text('Save cited questions to AI bank'));
      for (var i = 0; i < 5; i++) {
        await io(tester);
      }
      await settle(tester, 600);
      expect(aiBank().any((q) => q.stem.startsWith('Which marker')), true);
      expect(aiBank().any((q) => q.stem.startsWith('Uncited')), false);
      await tester.ensureVisible(find.text('Make review cards'));
      await settle(tester, 200);
      await tester.tap(find.text('Make review cards'));
      await io(tester);
      await settle(tester, 600);
      expect(store.listOf('libcards').isNotEmpty, true);
    });

    testWidgets('Case assistant: never-send case blocks the new tabs and sends nothing', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await push(tester, AiCaseScreen(rec: store.cases['cD']!, initialTab: 6));
      expect(find.textContaining('Never send this case to AI'), findsOneWidget);
      expect(find.text('Prepare me for the senior'), findsNothing);
      expect(FakeAi.sent, isEmpty);
    });

    testWidgets('Bulk tags: preview of short lines, never-send case skipped, apply and undo', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await push(tester, const BulkTagsScreen());
      expect(find.textContaining('1 cases have no tags'), findsOneWidget);
      await tester.tap(find.textContaining('Suggest tags ('));
      await sendPreview(tester);
      expect(find.textContaining('diabetes'), findsWidgets);
      final s = FakeAi.sent.single;
      expectClean('${s.system}${s.prompt}');
      await shot(tester, 'G5_bulk');
      final rec = store.cases['cC']!;
      expect(rec.tags, isEmpty); // nothing before Apply
      await tester.tap(find.text('Apply selected'));
      await io(tester);
      await settle(tester, 600);
      expect(rec.tags, containsAll(['diabetes', 'dka']));
      expect(rec.d['aiSuggested'], contains('tags'));
      await shot(tester, 'G5_dbg_bulk');
      await tester.tap(find.text('Undo').last);
      await io(tester);
      await settle(tester, 600);
      expect(rec.tags, isEmpty);
      expect(store.cases['cD']!.tags, isEmpty);
    });

    testWidgets('Reflection draft: preview, DRAFT banner, nothing saved until the user edits and saves', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await push(tester, const ReflectionDraftScreen());
      final before = store.listOf('reflections').length;
      await tester.tap(find.byType(OutlinedButton).first);
      await settle(tester, 800);
      await tester.tap(find.textContaining('MED-0042'));
      await settle(tester, 600);
      await tester.tap(find.text('Draft my reflection'));
      await sendPreview(tester);
      expect(find.textContaining('DRAFT written by AI'), findsWidgets);
      expect(find.text('Edit and save as my reflection'), findsOneWidget);
      expect(store.listOf('reflections').length, before);
      expectClean('${FakeAi.sent.single.system}${FakeAi.sent.single.prompt}');
    });

    testWidgets('Goal gap + CV screens: local numbers shown, AI suggestions on demand', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await push(tester, const GoalGapScreen());
      await tester.tap(find.text('Suggest next actions'));
      await settle(tester, 900);
      expect(find.textContaining('Log one case per day'), findsWidgets);
      expect(FakeAi.sent.single.level, AiLevel.none);
      Navigator.of(tester.element(find.byType(GoalGapScreen))).pop();
      await settle(tester, 500);
      await push(tester, const CvSummaryScreen());
      await tester.tap(find.text('Write CV text'));
      await settle(tester, 900);
      expect(find.textContaining('Intern in internal medicine'), findsOneWidget);
      expect(find.textContaining('DRAFT written by AI from your counts'), findsOneWidget);
    });

    testWidgets('Search: Ask AI card is prominent; off = disabled + Turn on AI', (tester) async {
      await boot(tester, 'en');
      fakeOn(enabled: false);
      await push(tester, const SearchScreen(initial: 'chest pain'));
      expect(AiContext.current.value?.kind, 'search');
      expect(find.text('Ask AI about this query'), findsOneWidget);
      expect(find.text('Turn on AI'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.descendant(of: find.byType(SearchAskAiCard), matching: find.byType(FilledButton))).onPressed, isNull);
      fakeOn();
      await reopen(tester, const SearchScreen(initial: 'chest pain'));
      expect(tester.widget<FilledButton>(find.descendant(of: find.byType(SearchAskAiCard), matching: find.byType(FilledButton))).onPressed, isNotNull);
      await shot(tester, 'G5_search');
    });

    testWidgets('Portfolio: AI portfolio tools card is visible in every state', (tester) async {
      await boot(tester, 'en');
      fakeOn(enabled: false);
      await push(tester, const PortfolioScreen());
      expect(AiContext.current.value?.kind, 'portfolio');
      expect(find.text('AI portfolio tools'), findsOneWidget);
      expect(find.text('Reflection draft'), findsOneWidget);
      expect(find.text('Goal gap analysis'), findsOneWidget);
      expect(find.text('CV summary'), findsOneWidget);
      await shot(tester, 'G5_portfolio');
    });

    testWidgets('Skills: procedure deep-dive entry, sources and library links', (tester) async {
      await boot(tester, 'en');
      fakeOn();
      await push(tester, Scaffold(appBar: AppBar(), body: const SkillsTab()));
      expect(find.byKey(const ValueKey('skill_ai_IV cannulation')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('skill_ai_IV cannulation')));
      await settle(tester, 800);
      expect(find.text('Procedure deep-dive'), findsWidgets);
      await tester.tap(find.text('Explain this procedure'));
      await settle(tester, 900);
      expect(find.textContaining('Clean the skin'), findsWidgets);
      expect(find.textContaining('Consent points'), findsWidgets);
      expect(FakeAi.sent.single.prompt, contains('IV cannulation'));
      expect(FakeAi.sent.single.level, AiLevel.none);
    });

    testWidgets('Case list and case editor have a visible AI entry (disabled look when off)', (tester) async {
      await boot(tester, 'en');
      fakeOn(enabled: false);
      await push(tester, const CasesScreen());
      expect(find.byKey(const ValueKey('cases_ai_chip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cases_ai_chip')));
      await settle(tester, 800);
      expect(find.text('Suggest tags for my untagged cases'), findsOneWidget);
      expect(find.text('Drug check'), findsOneWidget);
      expect(find.text('Turn on AI'), findsOneWidget);
      Navigator.of(tester.element(find.text('Drug check'))).pop();
      await settle(tester, 500);
      Navigator.of(tester.element(find.byType(CasesScreen))).pop();
      await settle(tester, 500);
      await push(tester, CaseEditorScreen(rec: store.cases['cA']!));
      expect(find.byKey(const ValueKey('case_ai_chip')), findsOneWidget);
      expect(AiContext.current.value?.kind, 'case');
      await tester.tap(find.byKey(const ValueKey('case_ai_chip')));
      await settle(tester, 1000);
      expect(find.byType(AiCaseScreen), findsOneWidget);
    });
  });

  // ================================================================ layout and screenshots
  const sizes = {'412': Size(412, 892), '360': Size(360, 640)};
  for (final lang in ['en', 'ar']) {
    for (final sz in sizes.entries) {
      testWidgets('layout $lang ${sz.key}', (tester) async {
        setLangSetting(lang);
        await boot(tester, lang, size: sz.value, scale: sz.key == '360' ? 1.3 : 1.0);
        fakeOn();
        final tag = 'G5_${lang}_${sz.key}';
        store.settings['folds'] = {'cl_curb': true};
        // home
        await push(tester, Scaffold(body: const HomeScreen()));
        await settle(tester, 700);
        await shot(tester, '${tag}_home');
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
        await settle(tester, 500);
        // calculators + interpret
        await push(tester, const CalculatorsScreen());
        await shot(tester, '${tag}_calc');
        await tapV(tester, find.byType(AiEntry).last);
        await settle(tester, 900);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await settle(tester, 400);
        await shot(tester, '${tag}_calc_interpret');
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(CalculatorsScreen))).pop();
        await settle(tester, 500);
        // drug check no source
        fakeOn(extra: {'ask_drug': '{"findings":[],"no_source":true}'});
        await push(tester, const DrugCheckScreen());
        await tester.scrollUntilVisible(find.byKey(const ValueKey('drug_a')), 100, scrollable: find.byType(Scrollable).first);
        await tester.enterText(find.byKey(const ValueKey('drug_a')), 'warfarin');
        await tester.scrollUntilVisible(find.byKey(const ValueKey('drug_b')), 100, scrollable: find.byType(Scrollable).first);
        await tester.enterText(find.byKey(const ValueKey('drug_b')), 'aspirin');
        await settle(tester, 300);
        await tapV(tester, find.byType(AiEntry).first);
        await settle(tester, 900);
        await shot(tester, '${tag}_drug');
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(DrugCheckScreen))).pop();
        await settle(tester, 500);
        fakeOn();
        // case assistant tabs
        await push(tester, AiCaseScreen(rec: store.cases['cA']!, initialTab: 6));
        await shot(tester, '${tag}_senior_start');
        await tapV(tester, find.byType(AiEntry).first);
        await sendPreview(tester);
        await shot(tester, '${tag}_senior');
        for (final i in [7, 8, 9]) {
          await tester.tap(find.byType(Tab).at(i));
          await settle(tester, 700);
          await tapV(tester, find.byType(AiEntry).first);
          await sendPreview(tester);
          await shot(tester, '${tag}_tab$i');
        }
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(AiCaseScreen))).pop();
        await settle(tester, 500);
        // bulk, portfolio, search
        await push(tester, const BulkTagsScreen());
        await shot(tester, '${tag}_bulk');
        Navigator.of(tester.element(find.byType(BulkTagsScreen))).pop();
        await settle(tester, 500);
        await push(tester, const PortfolioScreen());
        await tester.scrollUntilVisible(find.byKey(const ValueKey('pf_cv')), 300, scrollable: find.byType(Scrollable).first);
        await settle(tester, 400);
        await shot(tester, '${tag}_portfolio');
        Navigator.of(tester.element(find.byType(PortfolioScreen))).pop();
        await settle(tester, 500);
        await push(tester, const SearchScreen(initial: 'chest pain'));
        await shot(tester, '${tag}_search');
        expect(tester.takeException(), isNull);
        setLangSetting('en');
      });
    }
  }
}
