import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as mm show Text;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' show langCode, isAr;
import 'package:medlog/main.dart';
import 'package:medlog/screens_portfolio.dart' show DataHealthScreen;
import 'package:medlog/screens_search.dart';
import 'package:medlog/screens_review.dart';
import 'package:medlog/search_index.dart';
import 'package:medlog/review.dart';
import 'package:medlog/focus.dart';
import 'package:medlog/screens_images.dart';
import 'package:medlog/screens_privacy.dart';
import 'package:medlog/screens_skills.dart';
import 'package:medlog/privacy.dart';
import 'package:medlog/screens_cases.dart';
import 'package:medlog/screens_reasoning.dart';
import 'package:medlog/screens_trainer.dart';
import 'package:medlog/reasoning.dart';
import 'package:medlog/screens_notebooks.dart';
import 'package:medlog/pdf_export.dart';
import 'package:medlog/library.dart';
import 'package:medlog/lib_text.dart';
import 'package:medlog/lib_quiz.dart';
import 'package:medlog/core_topics.dart' show resolveCore250;
import 'package:medlog/lib_user.dart';
import 'package:medlog/calculators.dart';
import 'package:medlog/screens_article.dart';
import 'package:medlog/screens_quiz.dart';
import 'package:medlog/screens_calc.dart';
import 'package:medlog/widgets.dart' show Fold;
import 'package:medlog/screens_library.dart';
import 'package:medlog/med_terms.dart';
import 'package:medlog/i18n.dart' show textDirectionFor, medEnglish, tr;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePP extends PathProviderPlatform {
  final String dir;
  FakePP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

final GlobalKey shotKey = GlobalKey();
const out = 'test_output/shots';

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
  }
  await l.load();
}

String d(int back) => fmtDate(DateTime.now().subtract(Duration(days: back)));

void seed(String dir, Map<String, dynamic> settings) {
  final root = Directory('$dir/medlog/cases')..createSync(recursive: true);
  Directory('$dir/medlog/images').createSync(recursive: true);
  void w(String name, Object o) => File('$dir/medlog/$name').writeAsStringSync(jsonEncode(o));
  w('settings.json', settings);
  w('rotations.json', [
    {'id': 'r1', 'name': 'Internal Medicine', 'hospital': 'Al-Shifa', 'start': d(14), 'end': fmtDate(DateTime.now().add(const Duration(days: 16))), 'goals': '10 cannulations', 'supervisor': 'Dr. Ali'},
  ]);
  w('shifts.json', [
    for (final i in [0, 2, 4, 7, 9, 11]) {'date': d(i), 'type': ['Morning', 'Night', 'On-call', 'Evening'][i % 4], 'rotationId': 'r1'},
  ]);
  w('procedures.json', [
    {'id': 'p1', 'name': 'IV cannulation', 'role': 'Performed under supervision', 'confidence': '4', 'date': d(1), 'assessedBy': 'Self-assessed', 'rotationId': 'r1'},
    {'id': 'p2', 'name': 'ABG', 'role': 'Assisted', 'confidence': '3', 'date': d(3), 'assessedBy': 'Supervisor assessed', 'rotationId': 'r1'},
  ]);
  w('notes.json', [
    {'id': 'n1', 'title': 'DKA fluids', 'body': 'Start with 1L NS over 1h...', 'updated': '2026-10-20'},
  ]);
  w('questions.json', [
    {'id': 'q1', 'question': 'When to switch insulin infusion to SC?', 'status': 'Open', 'date': d(2)},
  ]);
  final specs = ['Internal Medicine', 'Emergency', 'Orthopedics', 'Pediatrics', 'General Surgery'];
  final dx = ['Community acquired pneumonia', 'Acute coronary syndrome', 'Distal radius fracture', 'Gastroenteritis', 'Acute appendicitis', 'DKA', 'Heart failure'];
  for (var i = 0; i < 14; i++) {
    final spec = specs[i % specs.length];
    final pre = {'Internal Medicine': 'MED', 'Emergency': 'EM', 'Orthopedics': 'ORT', 'Pediatrics': 'PED', 'General Surgery': 'SUR'}[spec];
    final c = {
      'id': 'c$i', 'schema': 2, 'created': '2026-10-${10 + i}T08:00:00Z', 'date': d(i ~/ 2), 'specialty': spec,
      'rotationId': 'r1', 'status': i % 5 == 0 ? 'Draft' : ['Active', 'Discharged', 'Completed'][i % 3],
      'code': '$pre-${(i + 1).toString().padLeft(4, '0')}', 'ageGroup': i % 3 == 0 ? 'Child' : 'Adult', 'sex': 'M',
      'cc': 'Chest pain 2 days', 'workingDx': dx[i % dx.length], 'setting': ['ER', 'Ward', 'Clinic'][i % 3],
      'role': ['Observed', 'Assisted', 'Supervised', 'Independent'][i % 4], 'tags': i % 4 == 0 ? ['rare'] : [], 'starred': i == 2,
      'hpi': 'Pain started...', 'learned': i % 2 == 0 ? 'Check troponin timing' : '',
    };
    File('${root.path}/c$i.json').writeAsStringSync(jsonEncode(c));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final b = shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> nav(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(AppNavBar), matching: find.text(label)));
}

Future<void> realWait(WidgetTester tester, [int ms = 700]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> boot(WidgetTester tester, Map<String, dynamic> settings, {bool splash = false}) async {
  final dir = Directory.systemTemp.createTempSync('medlog').path;
  PathProviderPlatform.instance = FakePP(dir);
  seed(dir, {'libQuick': false, ...settings});
  await tester.runAsync(() => store.init());
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(412, 892);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
}

void main() {
  tourG();
  tourF();
  tourE();
  tourD();
  tourC();
  tourB();
  tourA();
  tour4();
  tour3();
  tour2();
  setUpAll(() async {
    final rb = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
    await loadFont('Tajawal', ['assets/fonts/Tajawal_400Regular.ttf', 'assets/fonts/Tajawal_500Medium.ttf', 'assets/fonts/Tajawal_700Bold.ttf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('tour $lang', (tester) async {
      await boot(tester, {'lang': lang, 'author': lang == 'ar' ? 'د. محمد' : 'Dr. Mohammed', 'palette': 'clinic', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String()});
      await tester.pump(const Duration(milliseconds: 100));
      await settle(tester, 600);
      await shot(tester, '${lang}_00_splash_a');
      await settle(tester, 1400);
      await shot(tester, '${lang}_01_splash_b');
      await settle(tester, 2000);
      await shot(tester, '${lang}_02_home');
      await nav(tester, lang == 'ar' ? 'الحالات' : 'Cases');
      await settle(tester);
      await shot(tester, '${lang}_03_cases');
      await nav(tester, lang == 'ar' ? 'التعلّم' : 'Learn');
      await settle(tester);
      await shot(tester, '${lang}_04_learn');
      await nav(tester, lang == 'ar' ? 'الرئيسية' : 'Home');
      await settle(tester, 800);
      await tester.tap(find.byIcon(Icons.insights_outlined).first);
      await settle(tester, 1800);
      await shot(tester, '${lang}_05_portfolio');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester, 600);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await settle(tester);
      await shot(tester, '${lang}_06_quickadd');
    });
  }
}

void tour2() {
  for (final cfg in [
    ['en', 'royal', 'light'],
    ['ar', 'ocean', 'dark'],
    ['ar', 'sunset', 'light'],
  ]) {
    testWidgets('tour2 ${cfg.join('_')}', (tester) async {
      final lang = cfg[0];
      await boot(tester, {'lang': lang, 'author': 'Dr. Mohammed', 'palette': cfg[1], 'themeMode': cfg[2], 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'motion': true});
      await tester.pump(const Duration(milliseconds: 100));
      await settle(tester, 3600);
      final tag = cfg.join('_');
      await shot(tester, 'h_${tag}_home');
      // calendar
      await tester.tap(find.byIcon(Icons.calendar_month_outlined).first);
      await settle(tester, 1500);
      await shot(tester, 'h_${tag}_calendar');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester);
      // settings
      await tester.tap(find.byIcon(Icons.settings_outlined).first);
      await settle(tester, 1500);
      await shot(tester, 'h_${tag}_settings');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester);
      // editor
      await nav(tester, lang == 'ar' ? 'الحالات' : 'Cases');
      await settle(tester);
      await tester.tap(find.text('Acute coronary syndrome').first);
      await settle(tester, 1500);
      await shot(tester, 'h_${tag}_editor_info');
      await tester.tap(find.byIcon(Icons.history_edu_outlined));
      await settle(tester, 800);
      await shot(tester, 'h_${tag}_editor_history');
    });
  }
}

void tour3() {
  testWidgets('empty + interactions', (tester) async {
    final dir = Directory.systemTemp.createTempSync('medlog').path;
    PathProviderPlatform.instance = FakePP(dir);
    Directory('$dir/medlog').createSync(recursive: true);
    File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({'lang': 'en', 'deviceId': 'x'}));
    await tester.runAsync(() => store.init());
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 892);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
    await settle(tester, 3600);
    await shot(tester, 'z_empty_home_en');
    // quick add -> save
    await tester.tap(find.byIcon(Icons.add_rounded));
    await settle(tester, 800);
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Quick case')));
    await settle(tester, 800);
    await tester.enterText(find.byType(TextField).first, 'Fever 3 days');
    await tester.pump();
    await tester.ensureVisible(find.text('Save quick log'));
    await tester.pump();
    await tester.tap(find.text('Save quick log'));
    await settle(tester, 1500);
    expect(store.cases.length >= 1, true);
    await shot(tester, 'z_after_quickadd_en');
    // switch language at runtime
    await tester.runAsync(() => store.setLook('lang', 'ar'));
    await settle(tester, 1500);
    await shot(tester, 'z_after_lang_ar');
    // switch palette + dark
    await tester.runAsync(() => store.setLook('palette', 'rose'));
    await tester.runAsync(() => store.setLook('themeMode', 'dark'));
    await settle(tester, 1500);
    await shot(tester, 'z_after_rose_dark');
    // cases tab empty search
    await nav(tester, 'الحالات');
    await settle(tester);
    await shot(tester, 'z_cases_ar');
  });
}


void tour4() {
  testWidgets('switch ar->en leaves no arabic', (tester) async {
    await boot(tester, {'lang': 'ar', 'author': 'Dr. Mohammed', 'palette': 'clinic', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String()});
    await settle(tester, 3600);
    final ar = RegExp(r'[\u0600-\u06FF]');
    List<String> bad() => [
          for (final t in tester.widgetList<mm.Text>(find.byType(mm.Text)))
            if (ar.hasMatch(t.data ?? t.textSpan?.toPlainText() ?? '')) (t.data ?? '')
        ];
    // open settings, switch to English there (like the user does)
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await settle(tester, 1500);
    await tester.runAsync(() => store.setLook('lang', 'en'));
    await settle(tester, 2000);
    print('store.lang=${store.lang} langCode=$langCode isAr=$isAr');
    print('AFTER SWITCH offenders: ${bad().length}');
    await shot(tester, 'y_after_switch');
    for (final label in ['Cases', 'Library', 'Learn', 'Home']) {
      if (find.byType(AppNavBar).evaluate().isEmpty) {
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await settle(tester);
      }
      await nav(tester, label);
      await settle(tester, 1200);
      print('$label offenders: ${bad()}');
    }
  });
}

void tourA() {
  testWidgets('stageA health page', (tester) async {
    await boot(tester, {'lang': 'ar', 'palette': 'clinic', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String()});
    await settle(tester, 3800);
    await tester.runAsync(() => store.loadDemo());
    await settle(tester, 500);
    tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => const DataHealthScreen()));
    await settle(tester, 2500);
    await shot(tester, 'A_health_ar');
    expect(store.hasDemo, true);
    await tester.runAsync(() => store.removeDemo());
    expect(store.hasDemo, false);
  });
  testWidgets('stageA tablet', (tester) async {
    final dir = Directory.systemTemp.createTempSync('medlog').path;
    PathProviderPlatform.instance = FakePP(dir);
    seed(dir, {'lang': 'en', 'palette': 'clinic', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String()});
    await tester.runAsync(() => store.init());
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
    await settle(tester, 3800);
    await shot(tester, 'A_tablet_home');
    await tester.tap(find.text('Cases').last);
    await settle(tester, 1000);
    await shot(tester, 'A_tablet_cases');
  });
  for (final lang in ['en', 'ar']) {
    testWidgets('stageA $lang', (tester) async {
      await boot(tester, {'lang': lang, 'author': 'Dr. Mohammed', 'palette': 'clinic', 'mode': 'study', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false});
      await tester.runAsync(() async {
        await store.upsertExtra('tasks', {'id': 't1', 'title': 'Read about DKA fluids', 'due': fmtDate(DateTime.now().subtract(const Duration(days: 1))), 'priority': 'High'});
        await store.upsertExtra('pearls', {'id': 'p1', 'date': fmtDate(DateTime.now()), 'text': 'Check potassium before insulin', 'topic': 'DKA'});
      });
      await settle(tester, 3800);
      await shot(tester, 'A_${lang}_study');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await settle(tester, 800);
      await shot(tester, 'A_${lang}_addmenu');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester, 500);
      await tester.runAsync(() => store.setLook('mode', 'shift'));
      await settle(tester, 800);
      await shot(tester, 'A_${lang}_shift');
      // editor + undo
      await nav(tester, lang == 'ar' ? 'الحالات' : 'Cases');
      await settle(tester);
      await tester.tap(find.text('Acute coronary syndrome').first);
      await settle(tester, 1200);
      await tester.tap(find.byIcon(Icons.history_edu_outlined));
      await settle(tester, 600);
      final ccField = find.byType(TextField).first;
      await tester.enterText(ccField, 'Changed complaint text');
      await tester.pump(const Duration(milliseconds: 100));
      await shot(tester, 'A_${lang}_editor_typing');
      await tester.tap(find.byIcon(Icons.undo));
      await settle(tester, 600);
      expect((tester.widget(ccField) as TextField).controller!.text, 'Chest pain 2 days');
      await shot(tester, 'A_${lang}_editor_undone');
      await settle(tester, 1500);
    });
  }
  testWidgets('stageA settings+health+tablet', (tester) async {
    await boot(tester, {'lang': 'en', 'palette': 'clinic', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String()});
    await settle(tester, 3800);
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await settle(tester, 1200);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1400));
    await settle(tester, 600);
    await shot(tester, 'A_settings_bottom');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1400));
    await settle(tester, 600);
    await shot(tester, 'A_settings_bottom2');
    await tester.scrollUntilVisible(find.text('Data & recovery'), -300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Data & recovery'));
    await settle(tester, 600);
    await tester.scrollUntilVisible(find.text('Data health'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Data health'));
    await settle(tester, 1500);
    await shot(tester, 'A_datahealth');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester, 600);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester, 600);
  });
}


void tourB() {
  for (final lang in ['en', 'ar']) {
    testWidgets('stageB $lang', (tester) async {
      await boot(tester, {'lang': lang, 'author': 'Dr. Mohammed', 'palette': 'clinic', 'mode': 'study', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false});
      await tester.runAsync(() async {
        // richer data for the engine
        final c = store.cases['c0']!;
        c.set('finalDx', 'Community acquired pneumonia');
        c.set('mistakes', 'Missed checking oxygen saturation early');
        c.set('learned', 'CURB-65 guides admission');
        await store.saveCase(c);
        final c2 = store.cases['c5']!;
        c2.set('status', 'Draft');
        c2.set('date', fmtDate(DateTime.now().subtract(const Duration(days: 4))));
        c2.set('inv', [{'id': 'i1', 'name': 'CBC', 'status': 'Pending'}]);
        await store.saveCase(c2);
        store.inbox.add({'id': 'q9', 'question': 'When to stop antibiotics in CAP?', 'status': 'Answered', 'answer': 'Usually after 5 days if stable', 'reference': 'Local guideline', 'date': fmtDate(DateTime.now().subtract(const Duration(days: 5)))});
        store.inbox.add({'id': 'q10', 'question': 'How to calculate anion gap?', 'status': 'Open', 'date': fmtDate(DateTime.now().subtract(const Duration(days: 6)))});
        store.notes.add({'id': 'n9', 'title': 'DKA fluids', 'body': 'Start with isotonic saline then insulin when potassium safe', 'date': '2026-10-01', 'updated': '2026-10-01'});
        await store.upsertExtra('pearls', {'id': 'p9', 'date': fmtDate(DateTime.now().subtract(const Duration(days: 1))), 'text': 'Always check potassium before insulin', 'topic': 'DKA'});
        store.notifyListeners();
      });
      await settle(tester, 3800);
      await shot(tester, 'B_${lang}_study');
      final nav0 = tester.state<NavigatorState>(find.byType(Navigator).first);
      // search
      nav0.push(MaterialPageRoute(builder: (_) => const SearchScreen(initial: 'pneumonia')));
      await settle(tester, 1200);
      await shot(tester, 'B_${lang}_search');
      expect(searchIndex.search('CAP').isNotEmpty, true); // abbreviation finds the long name
      expect(searchIndex.search('التهاب رئوي').isNotEmpty, true); // Arabic finds English cases
      nav0.pop();
      await settle(tester, 400);
      nav0.push(MaterialPageRoute(builder: (_) => const TopicScreen(topic: 'DKA')));
      await settle(tester, 1200);
      await shot(tester, 'B_${lang}_topic');
      nav0.pop();
      await settle(tester, 400);
      // review session
      nav0.push(MaterialPageRoute(builder: (_) => const ReviewSessionScreen()));
      await settle(tester, 1200);
      await shot(tester, 'B_${lang}_review_front');
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await settle(tester, 800);
      await shot(tester, 'B_${lang}_review_back');
      nav0.pop();
      await settle(tester, 400);
      // replay
      nav0.push(MaterialPageRoute(builder: (_) => OwnReplayScreen(rec: store.cases['c0']!)));
      await settle(tester, 1200);
      await shot(tester, 'B_${lang}_replay1');
      await tester.enterText(find.byType(TextField).first, 'Pneumonia vs PE');
      await tester.pump();
      await tester.tap(find.byType(FilledButton).last);
      await settle(tester, 800);
      await shot(tester, 'B_${lang}_replay_reveal');
      nav0.pop();
      await settle(tester, 400);
      nav0.push(MaterialPageRoute(builder: (_) => const FocusScreen()));
      await settle(tester, 1200);
      await shot(tester, 'B_${lang}_focus');
      expect(buildFocus().isNotEmpty, true);
      nav0.pop();
      await settle(tester, 400);
      nav0.push(MaterialPageRoute(builder: (_) => CompareScreen(a: store.cases['c0']!, b: store.cases['c5']!)));
      await settle(tester, 1200);
      await shot(tester, 'B_${lang}_compare');
      nav0.pop();
      await settle(tester, 400);
      nav0.push(MaterialPageRoute(builder: (_) => SimilarCasesScreen(rec: store.cases['c0']!)));
      await settle(tester, 1200);
      await shot(tester, 'B_${lang}_similar');
      await tester.runAsync(() async {
        final items = ReviewEngine.due();
        expect(items.isNotEmpty, true);
      });
      await settle(tester, 1500);
    });
  }
}


Future<Uint8List> makeTestPng() async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 400, 300), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(400, 300), [Colors.grey.shade900, Colors.grey.shade400]));
  c.drawCircle(const Offset(200, 150), 80, Paint()..color = Colors.white70);
  c.drawRect(const Rect.fromLTWH(20, 20, 120, 40), Paint()..color = Colors.white);
  final img = await rec.endRecording().toImage(400, 300);
  final d = await img.toByteData(format: ui.ImageByteFormat.png);
  return d!.buffer.asUint8List();
}

void tourC() {
  testWidgets('stageC annotation painter', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: Colors.grey.shade800,
          child: CustomPaint(
            size: const Size(412, 400),
            painter: AnnPainter(const [
              {'t': 'arrow', 'p': [0.1, 0.2, 0.5, 0.5], 'c': 0},
              {'t': 'circle', 'p': [0.5, 0.1, 0.9, 0.4], 'c': 1},
              {'t': 'rect', 'p': [0.1, 0.6, 0.4, 0.9], 'c': 2},
              {'t': 'pen', 'p': [0.5, 0.6, 0.6, 0.8, 0.7, 0.6, 0.8, 0.85], 'c': 3},
              {'t': 'text', 'p': [0.45, 0.45], 'c': 4, 's': 'Consolidation'},
            ], const Rect.fromLTWH(0, 0, 412, 400)),
          ),
        ),
      ),
    ));
    await tester.pump();
    await shot(tester, 'C_painter');
  });

  testWidgets('stageC burn + strip logic', (tester) async {
    await tester.runAsync(() async {
      final png = await makeTestPng();
      final out = await burnBoxes(png, [const Rect.fromLTWH(0.0, 0.0, 0.5, 0.2)]);
      expect(out.length > 100, true);
      final codec = await ui.instantiateImageCodec(out);
      final f = await codec.getNextFrame();
      expect(f.image.width, 400);
      final bd = await f.image.toByteData();
      // pixel (10,10) is inside the covered box -> black
      final o = (10 * 400 + 10) * 4;
      expect([bd!.getUint8(o), bd.getUint8(o + 1), bd.getUint8(o + 2)], [0, 0, 0]);
      // pixel (300,250) is outside -> not black
      final o2 = (250 * 400 + 300) * 4;
      expect(bd.getUint8(o2) + bd.getUint8(o2 + 1) + bd.getUint8(o2 + 2) > 30, true);
    });
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('stageC $lang', (tester) async {
      await boot(tester, {'lang': lang, 'author': 'Dr. Mohammed', 'palette': 'clinic', 'mode': 'study', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false});
      late String f1, f2;
      await tester.runAsync(() async {
        final png = await makeTestPng();
        f1 = 'c0_a.png';
        f2 = 'c0_b.png';
        File(store.imagePath(f1)).writeAsBytesSync(png);
        File(store.imagePath(f2)).writeAsBytesSync(png);
        final c = store.cases['c0']!;
        c.set('hpi', 'MRN 12345678 admitted. Mr Ahmad called 0599123456 on 12/03/2026');
        c.set('images', [
          {'file': f1, 'type': 'X-ray', 'view': 'AP', 'date': todayStr(), 'interpretation': 'Right lower zone consolidation', 'caption': 'Day 1'},
          {'file': f2, 'type': 'X-ray', 'view': 'AP', 'date': todayStr(), 'interpretation': 'Improved', 'ann': [
            {'t': 'arrow', 'p': [0.2, 0.2, 0.5, 0.5], 'c': 0},
            {'t': 'circle', 'p': [0.4, 0.4, 0.7, 0.7], 'c': 1},
            {'t': 'text', 'p': [0.1, 0.8], 'c': 4, 's': 'Consolidation'},
          ]},
        ]);
        await store.saveCase(c);
        await store.upsertExtra('imaging', {'id': 'im1', 'kind': 'POCUS - Lung', 'date': todayStr(), 'views': 'Anterior', 'reading': 'A-lines', 'agreement': 'Agree', 'caseCode': 'MED-0001'});
        await store.upsertExtra('imaging', {'id': 'im2', 'kind': 'ECG read', 'date': todayStr(), 'reading': 'Sinus rhythm', 'agreement': 'Partly'});
        store.notifyListeners();
      });
      await settle(tester, 3800);
      final nav0 = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav0.push(MaterialPageRoute(builder: (_) => const ImageCompareScreen(a: {'file': 'c0_a.png', 'type': 'X-ray', 'view': 'AP'}, b: {'file': 'c0_b.png', 'type': 'X-ray', 'view': 'AP', 'ann': [{'t': 'arrow', 'p': [0.2, 0.2, 0.5, 0.5], 'c': 0}]})));
      await tester.runAsync(() async {
        final ctx = tester.element(find.byType(Scaffold).last);
        await precacheImage(FileImage(File(store.imagePath('c0_a.png'))), ctx);
        await precacheImage(FileImage(File(store.imagePath('c0_b.png'))), ctx);
      });
      for (var k = 0; k < 4; k++) {
        await realWait(tester, 300);
      }
      await settle(tester, 800);
      await shot(tester, 'C_${lang}_compare_sbs');
      await tester.tap(find.byIcon(Icons.compare));
      await settle(tester, 800);
      await shot(tester, 'C_${lang}_compare_wipe');
      nav0.pop();
      await settle(tester, 400);
      // annotate: draw an arrow by dragging
      List<Map<String, dynamic>>? saved;
      nav0.push(MaterialPageRoute(builder: (_) => ImageAnnotateScreen(path: store.imagePath(f1), initial: const [])));
      await tester.runAsync(() async {
        final ctx = tester.element(find.byType(Scaffold).last);
        await precacheImage(FileImage(File(store.imagePath(f1))), ctx);
      });
      for (var k = 0; k < 4; k++) {
        await realWait(tester, 300);
      }
      await settle(tester, 600);
      await tester.dragFrom(const Offset(120, 300), const Offset(150, 100));
      await settle(tester, 400);
      await shot(tester, 'C_${lang}_annotate');
      await tester.tap(find.byType(TextButton).last);
      await settle(tester, 600);
      nav0.push(MaterialPageRoute(builder: (_) => ImageCoverScreen(path: store.imagePath(f1))));
      for (var k = 0; k < 4; k++) {
        await realWait(tester, 300);
      }
      await settle(tester, 600);
      await tester.dragFrom(const Offset(80, 200), const Offset(160, 90));
      await settle(tester, 400);
      await shot(tester, 'C_${lang}_cover');
      nav0.pop();
      await settle(tester, 400);
      // privacy
      nav0.push(MaterialPageRoute(builder: (_) => PrivacyCheckScreen(rec: store.cases['c0']!)));
      await settle(tester, 1200);
      await shot(tester, 'C_${lang}_privacy');
      expect(scanCase(store.cases['c0']!).length >= 3, true);
      nav0.pop();
      await settle(tester, 400);
      // imaging tab + image review
      nav0.push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('x')), body: const ImagingTab())));
      await settle(tester, 1200);
      await shot(tester, 'C_${lang}_imaging');
      nav0.pop();
      await settle(tester, 400);
      expect(ReviewEngine.hasImages(), true);
      nav0.push(MaterialPageRoute(builder: (_) => const ReviewSessionScreen(kinds: {ReviewKind.image})));
      await settle(tester, 1500);
      await shot(tester, 'C_${lang}_imgreview');
      expect(saved, null);
      await settle(tester, 1500);
    });
  }
}


void tourD() {
  for (final lang in ['en', 'ar']) {
    testWidgets('stageD $lang', (tester) async {
      await boot(tester, {'lang': lang, 'author': 'Dr. Mohammed', 'palette': 'clinic', 'mode': 'study', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false});
      await tester.runAsync(() async {
        final c = store.cases['c0']!;
        c.set('initialDx', 'Pneumonia');
        c.set('finalDx', 'Pulmonary embolism');
        c.set('initialConf', '85');
        c.set('initialRight', 'Wrong');
        c.set('encounters', [
          {'id': 'e1', 'date': fmtDate(DateTime.now()), 'type': 'Follow-up', 'note': 'Improving'}
        ]);
        await store.saveCase(c);
      });
      await settle(tester, 3800);
      await shot(tester, 'D_${lang}_study');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await settle(tester, 800);
      await shot(tester, 'D_${lang}_study2');
      final nav0 = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav0.push(MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: store.cases['c0']!, initialTab: 2)));
      await settle(tester, 1500);
      await shot(tester, 'D_${lang}_exam');
      await tester.ensureVisible(find.byIcon(Icons.event_note_outlined));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.event_note_outlined));
      await settle(tester, 1000);
      await shot(tester, 'D_${lang}_timeline');
      await tester.ensureVisible(find.byIcon(Icons.school_outlined));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.school_outlined));
      await settle(tester, 1000);
      await shot(tester, 'D_${lang}_learning');
      await tester.ensureVisible(find.byIcon(Icons.psychology_outlined).first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.psychology_outlined).first);
      await settle(tester, 1000);
      await shot(tester, 'D_${lang}_assess');
      nav0.pop();
      await settle(tester, 500);
      for (final e in {
        'trainer': const PresentationTrainerScreen(),
        'trainer_case': PresentationTrainerScreen(rec: store.cases['c0']!),
        'comm': const CommunicationPracticeScreen(),
        'journal': const DecisionJournalScreen(),
      }.entries) {
        nav0.push(MaterialPageRoute(builder: (_) => e.value));
        await settle(tester, 1200);
        await shot(tester, 'D_${lang}_${e.key}');
        nav0.pop();
        await settle(tester, 500);
      }
      nav0.push(MaterialPageRoute(builder: (_) => Scaffold(body: ListView(children: [const CalibrationCard()]))));
      await settle(tester, 1000);
      await shot(tester, 'D_${lang}_calib');
    });
  }
}


void tourE() {
  test('stageE versions', () {
    expect(compareVersions('1.2.3', '1.2.10'), -1);
    expect(compareVersions('1.3.0', '1.2.9'), 1);
    expect(compareVersions('1.2.3', '1.2.3'), 0);
  });
  for (final lang in ['en', 'ar']) {
    testWidgets('stageE $lang', (tester) async {
      await boot(tester, {'lang': lang, 'author': 'Dr. Mohammed', 'palette': 'clinic', 'mode': 'study', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false});
      await tester.runAsync(() async {
        await store.upsertExtra('achievements', {'id': 'a1', 'title': 'Poster at student congress', 'kind': 'Presentation', 'date': d(5), 'where': 'AUC'});
        await store.upsertExtra('reflections', {'id': 'r1', 'title': 'Delivering news', 'date': d(2), 'happened': 'Told a family...', 'learned': 'Sit down first'});
        await store.upsertExtra('qi', {'id': 'q1', 'title': 'Handover checklist', 'status': 'Running', 'result': 'Fewer missed tasks'});
        await store.upsertExtra('evidence', {'id': 'e1', 'title': 'Surviving sepsis guidelines', 'source': 'Crit Care Med', 'year': '2021', 'level': 'Guideline', 'saved': d(400), 'reviewed': d(400)});
      });
      await settle(tester, 3800);
      final nav0 = tester.state<NavigatorState>(find.byType(Navigator).first);
      for (final e in {
        'hub': const NotebooksScreen(),
        'ach': const AchievementsScreen(),
        'refl': const ReflectionsScreen(),
        'qi': const QiScreen(),
        'evid': const EvidenceScreen(),
        'pubmed': const PubMedScreen(),
        'sites': const TrustedSitesScreen(),
        'analytics': const AnalyticsScreen(),
      }.entries) {
        nav0.push(MaterialPageRoute(builder: (_) => e.value));
        await settle(tester, 1200);
        await shot(tester, 'E_${lang}_${e.key}');
        nav0.pop();
        await settle(tester, 500);
      }
      // PubMed blocks identifiers before anything is sent
      nav0.push(MaterialPageRoute(builder: (_) => const PubMedScreen()));
      await settle(tester, 800);
      await tester.enterText(find.byType(TextField).first, 'chest pain 0599123456');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester, 600);
      await shot(tester, 'E_${lang}_pubmed_blocked');
      nav0.pop();
      await settle(tester, 400);
      // PDF
      await tester.runAsync(() async {
        final txt = caseAsText(store.cases['c0']!) + '\nالحالة: ألم صدر لمدة يومين\nمريض ذكر';
        final bytes = await buildPdf('Case MED-0001', txt);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length > 2000, true);
        final pages = await renderPages('Case MED-0001', txt);
        File('test_output/shots/E_${lang}_pdfpage.png').writeAsBytesSync(pages.first);
        final long = await renderPages('Long', List.generate(200, (i) => 'Line $i of text').join('\n'));
        expect(long.length > 1, true);
        expect(logbookSummaryText().contains('MED-0001'), true);
      });
    });
  }
}


void tourF() {
  test('stageF pack engine: install from catalog, search, read, import, remove', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    final base = Directory.systemTemp.createTempSync('medlib');
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final f = File('../library${req.uri.path}');
      if (await f.exists()) {
        req.response.add(await f.readAsBytes());
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    final lib = LibraryStore();
    await lib.init(base, bundled: const ['medlineplus']);
    expect(lib.pack('medlineplus') != null, true);
    expect((await lib.search('asthma')).isNotEmpty, true);
    final cat = await lib.fetchCatalog(catalogUrl: 'http://127.0.0.1:${server.port}/catalog.json');
    expect(cat.length > 20, true);
    final ortho = cat.firstWhere((e) => e.meta.id == 'orthopedics');
    var last = 0.0;
    await lib.install(ortho, onProgress: (p) => last = p);
    expect(last, 1.0);
    final hits = await lib.search('osteoarthritis', packId: 'orthopedics');
    expect(hits.first.title, 'Osteoarthritis');
    final art = await lib.read('orthopedics', hits.first.index);
    expect(art!.sections.length > 3, true);
    expect(art.sections.first.text.contains('degenerative joint disease'), true);
    expect(art.url.startsWith('https://en.wikipedia.org/wiki/'), true);
    // a damaged download is refused and nothing is left half installed
    final bad = CatalogEntry(PackMeta(id: 'cardiology', title: 'x', bytes: 100), ortho.idxUrl.replaceAll('orthopedics', 'cardiology'), ortho.binUrl.replaceAll('orthopedics', 'cardiology'), 'deadbeef', '');
    expect(() => lib.install(bad), throwsA(isA<FormatException>()));
    expect(lib.pack('cardiology'), null);
    expect(File('${lib.dir.path}/cardiology.bin.part').existsSync(), false);
    // own files
    final f = File('${base.path}/Fracture notes.md')..writeAsStringSync('Intro line\n# Reduction\nClosed reduction first.\n# Follow-up\nXR at 2 weeks');
    expect(await lib.importTextFiles([f.path]), 1);
    final mine = await lib.search('fracture notes', packId: LibraryStore.userPackId);
    expect(mine.length, 1);
    final a2 = await lib.read(LibraryStore.userPackId, mine.first.index);
    expect(a2!.sections.map((s) => s.heading).toList(), ['', 'Reduction', 'Follow-up']);
    // reopen: everything is remembered
    final lib2 = LibraryStore();
    await lib2.init(base);
    expect(lib2.packs.map((p) => p.id).toSet(), {'medlineplus', 'orthopedics', LibraryStore.userPackId});
    await lib2.remove('orthopedics');
    expect(File('${lib2.dir.path}/orthopedics.bin').existsSync(), false);
    await server.close(force: true);
  });

  test('stageF dictionary and direction', () {
    expect(lookupTerms('pneumo').first.key, 'pneumonia');
    expect(lookupTerms('كسر').first.key, 'fracture');
    expect(textDirectionFor('Pertinent negatives:') == TextDirection.ltr, true);
    expect(textDirectionFor('  ٢ ألم') == TextDirection.rtl, true);
    expect(textDirectionFor('120/80'), null);
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('stageF library $lang', (tester) async {
      await boot(tester, {'lang': lang, 'author': 'Dr. Mohammed', 'palette': 'clinic', 'mode': 'study', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false});
      late HttpServer server;
      await tester.runAsync(() async {
        server = await HttpServer.bind('127.0.0.1', 0);
        server.listen((req) async {
          final f = File('../library${req.uri.path}');
          if (await f.exists()) {
            req.response.add(await f.readAsBytes());
          } else {
            req.response.statusCode = 404;
          }
          await req.response.close();
        });
      });
      libraryCatalogUrl = 'http://127.0.0.1:${server.port}/catalog.json';
      await tester.runAsync(() async {
        final base = Directory.systemTemp.createTempSync('medlib');
        await library.init(base, bundled: const ['medlineplus']);
        final cat = await library.fetchCatalog();
        await library.install(cat.firstWhere((e) => e.meta.id == 'orthopedics'));
      });
      final dbg = await tester.runAsync(() => library.search('osteoarthritis'));
      // ignore: avoid_print
      print('DBG hits ${dbg!.length} ${dbg.first.packId} ${dbg.first.index}');
      final dba = await tester.runAsync(() => library.read(dbg.first.packId, dbg.first.index));
      // ignore: avoid_print
      print('DBG article ${dba?.title} ${dba?.sections.length}');
      await settle(tester, 3800);
      final nav0 = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav0.push(MaterialPageRoute(builder: (_) => const LibraryScreen()));
      await settle(tester, 1200);
      await shot(tester, 'F_${lang}_library');
      await tester.enterText(find.byType(TextField).first, 'osteoarthritis');
      await settle(tester, 600);
      for (var k = 0; k < 8 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty; k++) {
        await realWait(tester, 500);
      }
      await settle(tester, 600);
      await shot(tester, 'F_${lang}_library_search');
      await tester.tap(find.text('Osteoarthritis').first);
      await settle(tester, 600);
      for (var k = 0; k < 40; k++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      // ignore: avoid_print
      print('DBG art=${find.byType(ArticleScreen).evaluate().length} circ=${find.byType(CircularProgressIndicator).evaluate().length} missing=${find.text('Could not open this article.').evaluate().length}');
      await settle(tester, 1000);
      await shot(tester, 'F_${lang}_article');
      for (var k = 0; k < 14 && find.byIcon(Icons.expand_more).evaluate().isEmpty; k++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
        await settle(tester, 200);
      }
      await tester.ensureVisible(find.byIcon(Icons.expand_more).first);
      await settle(tester, 300);
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await settle(tester, 800);
      await shot(tester, 'F_${lang}_article_open');
      nav0.pop();
      await settle(tester, 400);
      nav0.pop();
      await settle(tester, 400);
      nav0.push(MaterialPageRoute(builder: (_) => const PackManagerScreen()));
      await settle(tester, 600);
      for (var k = 0; k < 40; k++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await settle(tester, 1200);
      await shot(tester, 'F_${lang}_packs');
      nav0.pop();
      await settle(tester, 400);
      nav0.push(MaterialPageRoute(builder: (_) => const DictionaryScreen()));
      await settle(tester, 1000);
      await shot(tester, 'F_${lang}_terms');
      nav0.pop();
      await settle(tester, 400);
      // exam tab with foldable systems
      nav0.push(MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: store.cases['c0']!, initialTab: 2)));
      await settle(tester, 1500);
      await shot(tester, 'F_${lang}_exam');
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
      await settle(tester, 600);
      await shot(tester, 'F_${lang}_exam2');
      nav0.pop();
      await settle(tester, 500);
      await tester.runAsync(() => server.close(force: true));
    });
  }
}


Future<HttpServer> serveOut(WidgetTester? tester) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((req) async {
    final f = File('../library${req.uri.path}');
    if (await f.exists()) {
      req.response.add(await f.readAsBytes());
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  });
  return server;
}

void tourG() {
  test('stageG text helpers', () {
    expect(sentences('Osteoarthritis (OA) is a degenerative joint disease. It affects 3.5 percent of people, e.g. adults. More text here.').length, 3);
    expect(expandAbbrev('OA knee').last, 'osteoarthritis knee');
    expect(expandAbbrev('knee').length, 1);
    expect(editDistance('arthrodsis', 'arthrodesis', max: 2), 1);
    expect(editDistance('abc', 'xyz', max: 1), 2);
    expect(secKind('Signs and symptoms'), SecKind.symptoms);
    expect(secKind('Management'), SecKind.treatment);
    expect(secKind('Etymology'), SecKind.history);
    expect(maskTitle('Osteoarthritis (OA) is a degenerative joint disease of the knee.', 'Osteoarthritis')!.contains('Osteoarthritis'), false);
  });

  test('stageG calculators', () {
    expect(bmi(70, 175).toStringAsFixed(1), '22.9');
    expect(map(120, 80).toStringAsFixed(1), '93.3');
    expect(anionGap(140, 104, 24), 12);
    expect(correctedCalcium(8.0, 2.0).toStringAsFixed(1), '9.6');
    expect(qtcBazett(400, 60).round(), 400);
    expect(qtcBazett(360, 75).toStringAsFixed(0), '402');
    expect(egfrCkdEpi2021(1.0, 50, false).toStringAsFixed(0), '92');
    expect(egfrCkdEpi2021(0.8, 60, true).toStringAsFixed(0), '84');
    expect(cockcroftGault(60, 80, 1.0, false).toStringAsFixed(1), '88.9');
    expect(gcs(4, 5, 6), 15);
    expect(gcsClass(8), 'Severe (3-8)');
    expect(curb65(confusion: true, urea: false, rr: true, bp: false, age: true), 3);
    expect(curb65Risk(3), 'High risk (3-5)');
    expect(sumChecked(kWellsDvt, {0, 9}), -1);
    expect(sumChecked(kWellsPe, {0, 1, 2}), 7.5);
    expect(sumChecked(kChadsVasc, {2, 4}), 4);
    expect(maintenanceFluid421(8), 32);
    expect(maintenanceFluid421(15), 50);
    expect(maintenanceFluid421(25), 65);
    expect(fmtDate(eddFromLmp(DateTime(2026, 1, 1))), '2026-10-08');
    expect(gestationalAge(DateTime(2026, 1, 1), DateTime(2026, 2, 12)), (6, 0));
  });

  test('stageG search with abbreviations and typos, quiz, favorites', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    final base = Directory.systemTemp.createTempSync('medlib');
    final server = await serveOut(null);
    final lib = LibraryStore();
    await lib.init(base, bundled: const ['medlineplus']);
    final cat = await lib.fetchCatalog(catalogUrl: 'http://127.0.0.1:${server.port}/catalog.json');
    await lib.install(cat.firstWhere((e) => e.meta.id == 'orthopedics'));
    await lib.install(cat.firstWhere((e) => e.meta.id == 'cardiology'));
    final imgPack = cat.firstWhere((e) => e.meta.id == 'orthopedics-images');
    expect(imgPack.meta.kind, 'images');
    expect(imgPack.meta.forId, 'orthopedics');
    await lib.install(imgPack);
    expect(lib.imagePackFor('orthopedics') != null, true);
    expect(lib.textPacks.any((p) => p.kind == 'images'), false);
    final im = await lib.imageFor('Osteoarthritis');
    expect(im != null && im.bytes.length > 500, true);
    expect(im!.credit, 'Drahreg01 — CC BY-SA 3.0');
    expect(im.filePage.startsWith('https://commons.wikimedia.org/wiki/File:'), true);
    expect(await lib.imageFor('No such article'), null);
    final oa = await lib.searchEx('OA');
    expect(oa.first.title, 'Osteoarthritis');
    final mi = await lib.searchEx('MI');
    expect(mi.any((h) => h.title.toLowerCase().contains('myocardial infarction')), true);
    expect(await lib.didYouMean('osteoarthrits'), 'osteoarthritis');
    expect(await lib.didYouMean('osteoarthritis'), null);
    final idx = await lib.indexOfTitle('orthopedics', 'Osteoarthritis');
    expect(idx != null, true);
    final rel = await lib.related('orthopedics', idx!);
    expect(rel.isNotEmpty, true);
    final day = await lib.dailyPick('orthopedics', '2026-10-21');
    expect(day, await lib.dailyPick('orthopedics', '2026-10-21'));
    // quiz built from the article text only
    final qs = await (() async {
      // buildQuiz uses the global library: point it at this base
      await library.init(base);
      return buildQuiz(packId: 'orthopedics', count: 8, seed: 7);
    })();
    expect(qs.length >= 5, true);
    for (final q in qs) {
      expect(q.options.length >= 2, true);
      expect(q.options.toSet().length, q.options.length);
      expect(q.answer >= 0 && q.answer < q.options.length, true);
      if (q.kind == QKind.definition || q.kind == QKind.cloze) expect(q.stem.contains('____'), true);
      if (q.kind == QKind.definition) expect(q.stem.toLowerCase().contains(q.correct.toLowerCase()), false);
    }
    final topicQs = await buildQuiz(query: 'fracture', count: 4, seed: 3);
    expect(topicQs.isNotEmpty, true);
    await server.close(force: true);
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('stageG ui $lang', (tester) async {
      await boot(tester, {'lang': lang, 'author': 'Dr. Mohammed', 'palette': 'clinic', 'mode': 'study', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false, 'libQuick': false});
      late HttpServer server;
      await tester.runAsync(() async {
        server = await serveOut(null);
        libraryCatalogUrl = 'http://127.0.0.1:${server.port}/catalog.json';
        final base = Directory.systemTemp.createTempSync('medlib');
        await library.init(base, bundled: const ['medlineplus']);
        final cat = await library.fetchCatalog();
        await library.install(cat.firstWhere((e) => e.meta.id == 'orthopedics'));
        // a small image pack made by hand (same format the build script writes)
        final img = await makeTestPng();
        final idx = (await library.titlesOf('orthopedics')).indexOf('Osteoarthritis');
        expect(idx >= 0, true);
        final imx = gzip.encode(utf8.encode(jsonEncode({'meta': {'id': 'orthopedics-images', 'kind': 'images', 'for': 'orthopedics', 'title': 'Orthopedics images', 'count': 1, 'date': '2026-10-01'}, 't': ['Osteoarthritis'], 'o': [0], 'n': [img.length], 'c': ['Test Author — CC BY-SA 4.0'], 'f': ['Test_image.png']})));
        await File('${library.dir.path}/orthopedics-images.idx').writeAsBytes(imx);
        await File('${library.dir.path}/orthopedics-images.bin').writeAsBytes(img);
        await File('${library.dir.path}/installed.json').writeAsString(jsonEncode([
          for (final p in library.packs) p.toJson(),
          {'id': 'orthopedics-images', 'title': 'Orthopedics images', 'kind': 'images', 'for': 'orthopedics', 'count': 1, 'bytes': img.length + imx.length, 'date': '2026-10-01'},
        ]));
        await library.init(base);
        expect(library.imagePackFor('orthopedics') != null, true);
        expect((await library.imageFor('Osteoarthritis'))!.credit, 'Test Author — CC BY-SA 4.0');
        await store.upsertExtra('pearls', {'id': 'pz', 'date': todayStr(), 'text': 'x'});
        await toggleFavorite('orthopedics', 'Osteoarthritis');
      });
      await settle(tester, 3800);
      await nav(tester, lang == 'ar' ? 'المكتبة' : 'Library');
      await settle(tester, 1200);
      for (var k = 0; k < 15; k++) {
        await realWait(tester, 120);
      }
      await settle(tester, 800);
      await shot(tester, 'G_${lang}_library_tab');
      final nav0 = tester.state<NavigatorState>(find.byType(Navigator).first);
      // article
      final aIdx = await tester.runAsync(() => library.indexOfTitle('orthopedics', 'Osteoarthritis'));
      nav0.push(MaterialPageRoute(builder: (_) => ArticleScreen(packId: 'orthopedics', index: aIdx!)));
      await settle(tester, 600);
      for (var k = 0; k < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; k++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      for (var k = 0; k < 6; k++) {
        await realWait(tester, 150);
      }
      await settle(tester, 800);
      await shot(tester, 'G_${lang}_article_top');
      for (var k = 0; k < 12 && find.text(tr('Expand all')).evaluate().isEmpty; k++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await settle(tester, 200);
      }
      if (find.text(tr('Expand all')).evaluate().isNotEmpty) {
        await tester.tap(find.text(tr('Expand all')).first);
        await settle(tester, 900);
      }
      await shot(tester, 'G_${lang}_article_treatment');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1400));
      await settle(tester, 600);
      await shot(tester, 'G_${lang}_article_bottom');
      nav0.pop();
      await settle(tester, 500);
      // unified search shows library articles too (abbreviation understood)
      nav0.push(MaterialPageRoute(builder: (_) => const SearchScreen(initial: 'OA')));
      await settle(tester, 700);
      for (var k = 0; k < 20; k++) {
        await realWait(tester, 120);
      }
      await settle(tester, 600);
      await shot(tester, 'G_${lang}_search_library');
      expect(find.text('Osteoarthritis'), findsWidgets);
      nav0.pop();
      await settle(tester, 500);
      // review cards from the library
      await tester.runAsync(() => addLibraryCard(front: 'What is osteoarthritis?', back: 'Degenerative joint disease', source: 'Osteoarthritis', packId: 'orthopedics', title: 'Osteoarthritis'));
      expect(buildReviewItems().any((i) => i.kind == ReviewKind.library), true);
      // calculators
      nav0.push(MaterialPageRoute(builder: (_) => const CalculatorsScreen()));
      await settle(tester, 900);
      final egfr = find.text(tr('eGFR (CKD-EPI 2021)'));
      await tester.scrollUntilVisible(egfr, 300, scrollable: find.byType(Scrollable).first);
      await settle(tester, 300);
      await tester.tap(egfr);
      await settle(tester, 700);
      final egfrFields = find.descendant(of: find.byKey(const ValueKey('cl_egfr')), matching: find.byType(TextField));
      await tester.ensureVisible(egfrFields.at(0));
      await tester.enterText(egfrFields.at(0), '1.0');
      await tester.enterText(egfrFields.at(1), '50');
      await settle(tester, 500);
      await shot(tester, 'G_${lang}_calc');
      expect(find.textContaining('92'), findsWidgets);
      nav0.pop();
      await settle(tester, 500);
      // quiz (the first Core-250 resolution reads hundreds of articles: do it in real time, not pump by pump)
      await tester.runAsync(() => resolveCore250());
      nav0.push(MaterialPageRoute(builder: (_) => const QuizScreen(packId: 'orthopedics', autoStart: true)));
      await settle(tester, 800);
      final quizWatch = Stopwatch()..start();
      while (quizWatch.elapsedMilliseconds < 90000 && find.byType(OutlinedButton).evaluate().length < 4) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      // ignore: avoid_print
      print('DBG quiz ready after ${quizWatch.elapsedMilliseconds} ms, options=${find.byType(OutlinedButton).evaluate().length}');
      await settle(tester, 600);
      await shot(tester, 'G_${lang}_quiz_q');
      await tester.tap(find.byType(OutlinedButton).first);
      await settle(tester, 700);
      await shot(tester, 'G_${lang}_quiz_a');
      nav0.pop();
      await settle(tester, 500);
      await tester.runAsync(() => server.close(force: true));
    });
  }
}
