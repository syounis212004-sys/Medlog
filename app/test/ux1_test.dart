import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
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
import 'package:medlog/motion.dart' show EcgBanner;
import 'package:medlog/ui.dart' show DirText;
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

  const sizes = {'412': Size(412, 892), '360': Size(360, 640)};
  for (final lang in ['en', 'ar']) {
    final ar = lang == 'ar';
    String L(String en, String arb) => ar ? arb : en;
    for (final sz in sizes.entries) {
      for (final scale in [1.0, 1.3]) {
        final tag = '${lang}_${sz.key}_x${(scale * 10).round()}';

        testWidgets('home $tag', (tester) async {
          await boot(tester, lang, size: sz.value, packs: const [], extra: {'textScale': scale});
          expect(tester.takeException(), isNull);
          await shot(tester, 'ux1_home_$tag');
          expect(find.byType(EcgBanner), findsNothing, reason: 'ECG off by default');
          expect(find.byKey(const ValueKey('home_quick_case')), findsOneWidget);
          // today's case is above the fold
          final today = find.byKey(const ValueKey('today_c0'));
          expect(today, findsOneWidget);
          final bottomNav = sz.value.height - 80;
          final r = tester.getRect(today);
          if (scale == 1.0) {
            expect(r.top, lessThan(bottomNav), reason: 'today case visible at $tag, top=${r.top}');
          }
          // header collapses on scroll
          final bar = find.byType(SliverAppBar);
          double ext() => (tester.renderObject(bar) as RenderSliver).geometry!.paintExtent;
          final h0 = ext();
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
          await settle(tester, 500);
          final h1 = ext();
          expect(h1, lessThan(h0 - 40), reason: 'header collapsed $h0 -> $h1');
          await shot(tester, 'ux1_home_scrolled_$tag');
          expect(tester.takeException(), isNull);
        });

        testWidgets('quick add $tag', (tester) async {
          await boot(tester, lang, size: sz.value, packs: const [], extra: {'textScale': scale});
          final before = store.cases.length;
          // long-press "+" opens Quick case directly
          await tester.longPress(find.byIcon(Icons.add_rounded).last);
          await settle(tester, 900);
          expect(find.byKey(const ValueKey('quick_cc')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await shot(tester, 'ux1_quick_$tag');
          // keyboard up: footer stays visible above it
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await settle(tester, 500);
          final save = find.byKey(const ValueKey('quick_save'));
          final sr = tester.getRect(save);
          expect(sr.bottom, lessThanOrEqualTo(sz.value.height - 280 + 0.5), reason: 'Save above keyboard');
          expect(sr.top, greaterThan(0));
          await tester.enterText(find.byKey(const ValueKey('quick_cc')), 'Fever 3 days, rigors');
          await shot(tester, 'ux1_quick_kb_$tag');
          // keyboard Done saves
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await settle(tester, 1200);
          tester.view.resetViewInsets();
          await realWait(tester, 300);
          expect(store.cases.length, before + 1);
          expect(store.cases.values.any((c) => c.s('cc') == 'Fever 3 days, rigors'), isTrue);
          expect(tester.takeException(), isNull);
        });

        testWidgets('editor info $tag', (tester) async {
          await boot(tester, lang, size: sz.value, packs: const [], extra: {'textScale': scale});
          await push(tester, CaseEditorScreen(rec: store.cases['c0']!), 1500);
          expect(tester.takeException(), isNull);
          await shot(tester, 'ux1_editor_$tag');
          expect(find.byKey(const ValueKey('info_date')), findsOneWidget);
          await tester.scrollUntilVisible(find.byKey(const ValueKey('spec_more')), 150,
              scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first);
          expect(find.byKey(const ValueKey('spec_more')), findsOneWidget);
          // five specialty chips (+ More)
          final chips = find.descendant(of: find.byType(Wrap), matching: find.byType(ChoiceChip));
          await tester.tap(find.byKey(const ValueKey('spec_more')));
          await settle(tester, 400);
          expect(tester.takeException(), isNull);
          await shot(tester, 'ux1_editor_more_$tag');
          expect(chips.evaluate().length, greaterThan(10));
          // other tabs at this size
          final tabs = find.descendant(of: find.byType(TabBar), matching: find.byType(Tab));
          for (var t = 1; t < 9; t++) {
            await tester.ensureVisible(tabs.at(t));
            await tester.tap(tabs.at(t));
            await settle(tester, 500);
            expect(tester.takeException(), isNull, reason: 'tab $t');
          }
        });

        testWidgets('cases filters $tag', (tester) async {
          await boot(tester, lang, size: sz.value, packs: const [], extra: {'textScale': scale});
          await tabTo(tester, L('Cases', 'الحالات'));
          expect(tester.takeException(), isNull);
          await shot(tester, 'ux1_cases_$tag');
          expect(find.byIcon(Icons.manage_search), findsNothing);
          await tester.enterText(find.byType(TextField).first, 'chest');
          await settle(tester, 700);
          expect(find.byIcon(Icons.manage_search), findsOneWidget, reason: 'single entry to global search');
          expect(tester.takeException(), isNull);
          if (ar) {
            // one rule for statuses: no English "Discharged" next to Arabic ones
            expect(find.text('Discharged'), findsNothing);
          }
        });
      }
    }
  }

  testWidgets('global search: logbook first, scope switch', (tester) async {
    await boot(tester, 'en', packs: const ['clinical-essentials']);
    await push(tester, const SearchScreen(), 800);
    await tester.enterText(find.byType(TextField).first, 'pain');
    await settle(tester, 400);
    await realWait(tester, 800);
    await settle(tester, 800);
    await shot(tester, 'ux1_search_all');
    expect(find.byType(SegmentedButton<int>), findsOneWidget);
    final casesHdr = find.textContaining('Cases (');
    expect(casesHdr, findsOneWidget);
    final lib = find.textContaining('Library (');
    if (lib.evaluate().isNotEmpty) {
      expect(tester.getTopLeft(casesHdr).dy, lessThan(tester.getTopLeft(lib).dy), reason: 'Cases before Library');
    }
    await tester.tap(find.text('Library'));
    await settle(tester, 500);
    expect(find.textContaining('Cases ('), findsNothing);
    await shot(tester, 'ux1_search_lib');
    await tester.tap(find.text('Logbook'));
    await settle(tester, 500);
    expect(find.textContaining('Cases ('), findsOneWidget);
    expect(find.textContaining('Library ('), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calculators: search, favorites, recents', (tester) async {
    await boot(tester, 'en', packs: const []);
    await push(tester, const CalculatorsScreen(), 800);
    await shot(tester, 'ux1_calc');
    await tester.enterText(find.byKey(const ValueKey('calc_search')), 'bmi');
    await settle(tester, 400);
    expect(find.text('Anion gap'), findsNothing);
    expect(find.text('BMI'), findsWidgets);
    await tester.tap(find.byIcon(Icons.star_border).first);
    await settle(tester, 400);
    expect((store.settings['calcFav'] as List), contains('cl_bmi'));
    await tester.enterText(find.byKey(const ValueKey('calc_search')), '');
    await settle(tester, 400);
    expect(find.text('Favorites'), findsOneWidget);
    await shot(tester, 'ux1_calc_fav');
    // opening one records it as recent
    await tester.scrollUntilVisible(find.text('Anion gap'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Anion gap'));
    await settle(tester, 500);
    expect((store.settings['calcRecent'] as List), contains('cl_ag'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mixed-direction paragraphs', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        child: DirText('Pain radiating to the left arm.\nألم في الصدر منذ يومين\n\nNo fever.'),
      ),
    ));
    final dirs = [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        Directionality.of(tester.element(find.byWidget(t)))
    ];
    expect(dirs, [TextDirection.ltr, TextDirection.rtl, TextDirection.ltr]);
  });
}
