import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/ai/ai_api.dart';
import 'package:medlog/ai/ai_prefs.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' show setLangSetting, tr;
import 'package:medlog/library.dart';
import 'package:medlog/lib_user.dart';
import 'package:medlog/screens_ai_quiz.dart';
import 'package:medlog/screens_ai_settings.dart';
import 'package:medlog/screens_library.dart';
import 'package:medlog/settings_tuner.dart';
import 'package:medlog/settings_widgets.dart';
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

Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  // store.setLook saves the settings file (several real IO steps) before it notifies: interleave real time and pumps
  // until the store stopped notifying
  var last = store.rev;
  var stable = 0;
  for (var i = 0; i < 120 && (i < 8 || stable < 8); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 50));
    if (store.rev == last) {
      stable++;
    } else {
      stable = 0;
      last = store.rev;
    }
  }
}

/// Taps and waits for the store to finish the (real IO) save and notify, then redraws.
Future<void> waitRev(WidgetTester tester, int r0) async {
  for (var i = 0; i < 400 && store.rev == r0; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await settle(tester, 100);
}

Future<void> tapWait(WidgetTester tester, Finder f, {bool io = true}) async {
  final r0 = store.rev;
  await tester.tap(f);
  if (io) {
    await waitRev(tester, r0);
  } else {
    await settle(tester, 100);
  }
}

Directory installSome(List<String> ids) {
  final base = Directory.systemTemp.createTempSync('g1base');
  final lib = Directory('${base.path}/library')..createSync(recursive: true);
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
  return base;
}

Future<void> boot(WidgetTester tester, {List<String> packs = const []}) async {
  final dir = Directory.systemTemp.createTempSync('g1').path;
  PathProviderPlatform.instance = FakePP(dir);
  Directory('$dir/medlog/cases').createSync(recursive: true);
  Directory('$dir/medlog/images').createSync(recursive: true);
  File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({'lang': 'en', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String()}));
  await tester.runAsync(() => store.init());
  await tester.runAsync(() async => library.init(packs.isEmpty ? Directory.systemTemp.createTempSync('g1lib') : installSome(packs)));
  installFakeAi(online: true, enabled: false);
  AiStore.master = false;
}

Future<void> pumpScreen(WidgetTester tester, String lang, Size size, double scale, {Widget? home, bool openAll = true}) async {
  setLangSetting(lang);
  if (openAll) store.settings['folds'] = {for (final f in ['ls_reading', 'ls_sheet', 'ls_images', 'ls_search', 'ls_packs', 'ls_ai', 'ls_ai_answers', 'ls_privacy']) f: true};
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: shotKey,
    child: MaterialApp(
      locale: Locale(lang),
      theme: ThemeData(fontFamily: lang == 'ar' ? 'Cairo' : 'Roboto'),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: home ?? const LibrarySettingsScreen(),
    ),
  ));
  await settle(tester, 800);
}

ScrollableState mainScroll(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first);

Future<void> toTop(WidgetTester tester) async {
  mainScroll(tester).position.jumpTo(0);
  await tester.pump();
}

/// Brings a control into the middle of the viewport (scrolling from the top, the list builds lazily).
Future<void> reveal(WidgetTester tester, Finder f) async {
  await toTop(tester);
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 250, scrollable: find.byType(Scrollable).first, maxScrolls: 400);
  }
  Scrollable.ensureVisible(tester.element(f.first), alignment: 0.5, duration: const Duration(milliseconds: 10));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Finder optSwitch(String title) => find.byWidgetPredicate((w) => w is OptSwitch && w.title == title, description: 'OptSwitch($title)');
Finder optChoice(String title) => find.byWidgetPredicate((w) => w is OptChoice && w.title == title, description: 'OptChoice($title)');
Finder optSlider(String title) => find.byWidgetPredicate((w) => w is OptSlider && w.title == title, description: 'OptSlider($title)');

String snapshot() => jsonEncode([store.settings, AiStore.master, AiStore.features, AiStore.allowLibrary, AiStore.allowCase, AiStore.previewMode]);

/// Every switch on the page, in order of appearance: tap, check the Switch moved, the store changed, tap back.
const aiBacked = {'Use the AI assistant', 'Passages of my installed library'};

const switchTitles = [
  'Larger and bolder text',
  'Highlight doses and red flags',
  'Combined view of several sources',
  'Show captions',
  'Show downloaded images',
  'Show tables',
  'Load pictures from the internet',
  'Search inside articles',
  'Concise sources first',
  'Suggest other search words',
  'Download on Wi-Fi only',
  'Use the AI assistant',
  "Use the provider's live web search when available",
  'Show citations',
  'Floating Ask AI button',
  'Passages of my installed library',
];

final _sw = Stopwatch()..start();
void st(String m) => print('[${_sw.elapsedMilliseconds}ms] $m');

void main() {
  setUpAll(() async {
    final rb = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() {
    setLangSetting('en');
    uninstallFakeAi();
  });

  // ---------------------------------------------------------------- root cause
  testWidgets('root cause: a const child under AnimatedBuilder is never rebuilt (the old _SheetSettingsFold)', (tester) async {
    final n = ValueNotifier<int>(0);
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      home: AnimatedBuilder(
        animation: n,
        builder: (c, _) => Column(children: [Text('v${n.value}'), const _Probe()]),
      ),
    ));
    final first = _Probe.builds;
    n.value = 1;
    await tester.pump();
    expect(find.text('v1'), findsOneWidget);
    expect(_Probe.builds, first, reason: 'const subtree skipped: it kept drawing the old value');
    builds++;
    expect(builds, 1);
  });

  // ---------------------------------------------------------------- the controls, every size and language
  for (final lang in ['en', 'ar']) {
    for (final size in const [Size(412, 892), Size(360, 640)]) {
      for (final scale in const [1.0, 1.3]) {
        final tag = '${lang}_${size.width.toInt()}_${(scale * 10).round()}';
        testWidgets('every control saves and redraws: $tag', (tester) async {
          await boot(tester);
          await pumpScreen(tester, lang, size, scale);
          expect(tester.takeException(), isNull);
          await shot(tester, 'g1_settings_${tag}_1');

          // --- sheet style: SegmentedButton selection follows the tap, the preview is redrawn
          st('sheet style: SegmentedButton selection f');
          for (final st in [2, 0, 1]) {
            final ch = optChoice('Sheet style');
            await reveal(tester, ch);
            final seg = find.descendant(of: ch, matching: find.byType(SegmentedButton<int>));
            final btn = find.descendant(of: seg, matching: find.byType(TextButton));
            expect(btn, findsNWidgets(3));
            await tapWait(tester, btn.at(st));
            await settle(tester, 300);
            expect(store.libSheetStyle, st, reason: 'style saved');
            expect(tester.widget<SegmentedButton<int>>(seg).selected, {st}, reason: 'segment redrawn');
            expect(find.byKey(Key('sheet_preview_desc_$st')), findsOneWidget, reason: 'preview redrawn');
            // Plain shows no callout cards (no flag icon), Light and Rich show them
            final cards = find.descendant(of: find.byKey(const Key('sheet_preview')), matching: find.byIcon(Icons.medication_outlined));
            expect(cards, st == 0 ? findsNothing : findsOneWidget, reason: 'preview cards for style $st');
            final hy = find.descendant(of: find.byKey(const Key('sheet_preview')), matching: find.byIcon(Icons.star_border));
            expect(hy, st == 2 ? findsOneWidget : findsNothing);
          }
          await shot(tester, 'g1_settings_${tag}_sheet');

          // --- the callouts switch removes the cards in Light
          st('the callouts switch removes the cards in');
          final marks = optSwitch('Highlight doses and red flags');
          await reveal(tester, marks);
          await tapWait(tester, find.descendant(of: marks, matching: find.byType(Switch)));
          await settle(tester, 300);
          expect(store.settings['libMarks'], false);
          expect(find.descendant(of: find.byKey(const Key('sheet_preview')), matching: find.byIcon(Icons.medication_outlined)), findsNothing);
          await tapWait(tester, find.descendant(of: marks, matching: find.byType(Switch)));
          await settle(tester, 300);
          expect(find.descendant(of: find.byKey(const Key('sheet_preview')), matching: find.byIcon(Icons.medication_outlined)), findsOneWidget);

          // --- text size slider (drag) changes the preview font
          st('text size slider (drag) changes the prev');
          final sl = optSlider('Article text size');
          await reveal(tester, sl);
          final before = store.libFontScale;
          final pv = find.byKey(const Key('reading_preview'));
          final fsBefore = tester.widget<Text>(find.descendant(of: pv, matching: find.byType(Text))).style!.fontSize!;
          final r1 = store.rev;
          await tester.drag(find.descendant(of: sl, matching: find.byType(Slider)), const Offset(80, 0));
          await waitRev(tester, r1);
          expect(store.libFontScale, isNot(before));
          final fsAfter = tester.widget<Text>(find.descendant(of: pv, matching: find.byType(Text))).style!.fontSize!;
          expect(fsAfter, isNot(fsBefore), reason: 'reading preview redrawn');

          // --- every switch
          st('every switch');
          for (final t in switchTitles) {
            final f = optSwitch(t);
            st('switch $t');
            await reveal(tester, f);
            expect(f, findsOneWidget, reason: t);
            final sw = find.descendant(of: f, matching: find.byType(Switch));
            final v0 = tester.widget<Switch>(sw).value;
            final s0 = snapshot();
            final io = !aiBacked.contains(t);
            await tapWait(tester, sw, io: io);
            expect(tester.widget<Switch>(find.descendant(of: optSwitch(t), matching: find.byType(Switch))).value, !v0, reason: '$t redrawn');
            expect(snapshot(), isNot(s0), reason: '$t saved');
            await tapWait(tester, find.descendant(of: optSwitch(t), matching: find.byType(Switch)), io: io);
            expect(tester.widget<Switch>(find.descendant(of: optSwitch(t), matching: find.byType(Switch))).value, v0, reason: '$t back');
            expect(tester.takeException(), isNull, reason: t);
          }
          // the master switch is left off again; turn it on to reach the per-feature switches
          final master = optSwitch('Use the AI assistant');
          await reveal(tester, master);
          await tapWait(tester, find.descendant(of: master, matching: find.byType(Switch)), io: false);
          await settle(tester, 300);
          expect(AiStore.master, true);
          for (final g in kAiGroups) {
            final f = find.byWidgetPredicate((w) => w is OptSwitch && w.value == (AiStore.features[g] != false) && w.help == _groupHelp[g], description: 'AI group $g');
            await reveal(tester, f);
            final sw = find.descendant(of: f, matching: find.byType(Switch));
            await tapWait(tester, sw, io: false);
            await settle(tester, 300);
            expect(AiStore.features[g], false, reason: g);
            await tapWait(tester, find.descendant(of: find.byWidgetPredicate((w) => w is OptSwitch && w.help == _groupHelp[g]), matching: find.byType(Switch)), io: false);
            await settle(tester, 300);
            expect(AiStore.features[g], true, reason: g);
          }

          // --- choices
          st('choices');
          Future<void> pick(String title, int i, bool Function() ok, {bool io = true}) async {
            final ch = optChoice(title);
            await reveal(tester, ch);
            final rows = find.descendant(of: ch, matching: find.byType(ListTile));
            await tapWait(tester, rows.at(i), io: io);
            await settle(tester, 300);
            expect(ok(), true, reason: '$title #$i');
          }

          await pick('Answer language', 1, () => AiPrefs.answerLang == 'mixed');
          await pick('Answer language', 2, () => AiPrefs.answerLang == 'ar');
          await pick('Answer language', 0, () => AiPrefs.answerLang == 'en');
          await pick('Where answers come from', 1, () => AiPrefs.sourceMode == 'library');
          await pick('Where answers come from', 2, () => AiPrefs.sourceMode == 'model');
          await pick('Where answers come from', 3, () => AiPrefs.sourceMode == 'custom');
          await pick('Where answers come from', 0, () => AiPrefs.sourceMode == 'web');
          await pick('Preview before sending', 1, () => AiStore.previewMode == 'session', io: false);
          await pick('Preview before sending', 0, () => AiStore.previewMode == 'always', io: false);
          // segmented ones
          for (final e in [
            ['Answer length', 0, 'brief'],
            ['Answer length', 2, 'full'],
            ['Answer length', 1, 'standard'],
          ]) {
            final ch = optChoice(e[0] as String);
            await reveal(tester, ch);
            await tapWait(tester, find.descendant(of: ch, matching: find.byType(TextButton)).at(e[1] as int));
            await settle(tester, 300);
            expect(AiPrefs.answerLength, e[2]);
          }
          for (final e in [
            ['How answers look', 1, 'text'],
            ['How answers look', 0, 'cards'],
            ['Button side', 1, 'end'],
            ['Button side', 0, 'start'],
          ]) {
            final ch = optChoice(e[0] as String);
            await reveal(tester, ch);
            await tapWait(tester, find.descendant(of: ch, matching: find.byType(TextButton)).at(e[1] as int));
            await settle(tester, 300);
            expect(e[0] == 'How answers look' ? AiPrefs.renderStyle : AiPrefs.fabSide, e[2]);
          }

          // --- daily cap slider
          st('daily cap slider');
          final cap = optSlider('Daily request limit');
          await reveal(tester, cap);
          final c0 = AiPrefs.dailyCap;
          final r2 = store.rev;
          await tester.drag(find.descendant(of: cap, matching: find.byType(Slider)), const Offset(-60, 0));
          await waitRev(tester, r2);
          expect(AiPrefs.dailyCap, isNot(c0));

          // --- screen chips
          st('screen chips');
          final chip = find.byKey(const Key('ai_scr_quiz'));
          await reveal(tester, chip);
          expect(AiPrefs.screenOn('quiz'), true);
          await tapWait(tester, chip);
          await settle(tester, 300);
          expect(AiPrefs.screenOn('quiz'), false);
          expect(tester.widget<FilterChip>(find.byKey(const Key('ai_scr_quiz'))).selected, false);
          await tapWait(tester, find.byKey(const Key('ai_scr_quiz')));
          await settle(tester, 300);
          expect(AiPrefs.screenOn('quiz'), true);

          // --- region text
          st('region text');
          final region = find.byKey(const Key('ai_region'));
          await reveal(tester, region);
          final r3 = store.rev;
          await tester.enterText(region, 'Jordan');
          await waitRev(tester, r3);
          expect(AiPrefs.region, 'Jordan');

          // --- domains
          st('domains');
          await reveal(tester, find.byKey(const Key('dom_input')));
          await tester.enterText(find.byKey(const Key('dom_input')), 'https://www.Example.org/page');
          await tapWait(tester, find.byKey(const Key('dom_add')));
          await settle(tester, 300);
          expect(AiPrefs.domains.contains('example.org'), true);
          expect(find.byKey(const Key('dom_example.org')), findsOneWidget);
          await tester.enterText(find.byKey(const Key('dom_input')), 'not a domain');
          await tapWait(tester, find.byKey(const Key('dom_add')), io: false);
          await settle(tester, 300);
          expect(AiPrefs.domains.contains('not a domain'), false);
          // remove chip (the delete icon of the chip)
          final chipDel = find.descendant(of: find.byKey(const Key('dom_example.org')), matching: find.byType(Icon));
          await reveal(tester, find.byKey(const Key('dom_example.org')));
          await tapWait(tester, chipDel.first);
          await settle(tester, 300);
          expect(AiPrefs.domains.contains('example.org'), false);
          AiPrefs.domains = ['a.org', 'b.org'];
          await settle(tester, 300);
          await reveal(tester, find.byKey(const Key('dom_reset')));
          await tapWait(tester, find.byKey(const Key('dom_reset')));
          await settle(tester, 300);
          expect(AiPrefs.domainsAreDefault, true);
          expect(AiPrefs.domains.length, AiPrefs.defaultDomains.length);

          // --- the (i) button opens the explanation
          st('the (i) button opens the explanation');
          final head = optChoice('Answer length');
          await reveal(tester, head);
          await tester.tap(find.descendant(of: head, matching: find.byType(OptInfoButton)));
          await settle(tester, 500);
          expect(find.byType(BottomSheet), findsOneWidget);
          await tester.tap(find.byType(TextButton).last);
          await settle(tester, 500);
          expect(find.byType(BottomSheet), findsNothing);

          // --- folds open and close
          st('folds open and close');
          await toTop(tester);
          final reading = find.text(tr('Reading'));
          await tester.tap(reading);
          await settle(tester, 400);
          expect(find.byKey(const Key('reading_preview')).hitTestable(), findsNothing);
          await tester.tap(reading);
          await settle(tester, 400);
          expect(find.byKey(const Key('reading_preview')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  // ---------------------------------------------------------------- links and navigation
  testWidgets('AI question bank link opens, AiSettingsScreen route still works', (tester) async {
    await boot(tester);
    await pumpScreen(tester, 'en', const Size(412, 892), 1.0);
    final link = find.byWidgetPredicate((w) => w is OptLink && w.title == 'AI question bank');
    await reveal(tester, link);
    await tester.tap(link);
    await settle(tester, 800);
    expect(find.byType(AiQuizScreen), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester, 500);
    await pumpScreen(tester, 'en', const Size(412, 892), 1.0, home: const AiSettingsScreen());
    expect(find.text('Use the AI assistant'), findsOneWidget);
    await tester.tap(find.descendant(of: optSwitch('Use the AI assistant'), matching: find.byType(Switch)));
    await settle(tester, 300);
    expect(AiStore.master, true);
  });

  testWidgets('packs: storage per pack and delete', (tester) async {
    await boot(tester, packs: ['clinical-essentials']);
    await pumpScreen(tester, 'en', const Size(412, 892), 1.0);
    final del = find.byTooltip('Delete');
    await reveal(tester, find.text('Storage used by each pack'));
    await tester.tap(find.text('Packs & downloads'));
    await settle(tester, 300);
    await tester.tap(find.text('Packs & downloads'));
    await settle(tester, 300);
    await reveal(tester, del);
    expect(library.packs.any((p) => p.id == 'clinical-essentials'), true);
    await tester.tap(del.first);
    await settle(tester, 400);
    await tester.tap(find.text('Delete').last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await settle(tester, 400);
    expect(library.packs.any((p) => p.id == 'clinical-essentials'), false);
  });

  // ---------------------------------------------------------------- the tuner
  group('tuner rules (offline)', () {
    test('rotation, font, storage, wifi, unused AI', () {
      const packs = [PackMeta(id: 'cardiology', title: 'Cardiology', bytes: 40 * 1024 * 1024), PackMeta(id: 'cardiology-images', title: 'Cardiology images', kind: 'images', bytes: 30 * 1024 * 1024)];
      final ids = tuneRules(TuneCtx(
        widthDp: 360,
        libFont: 1.4,
        wifiOnly: false,
        packs: packs,
        freeBytes: 300 * 1024 * 1024,
        imageCacheBytes: 10 * 1024 * 1024,
        rotationPackId: 'orthopedics',
        rotationCourse: 'Orthopedics',
        missingCore: 7,
        essentialsInstalled: false,
        aiOn: true,
        aiLogged: 9,
        aiUse: const {'ask': 9},
        aiFeatures: const {'ask': true, 'explain': true, 'quiz': true, 'case': true, 'reports': true, 'help': true},
      )).map((e) => e.id).toList();
      expect(ids, ['pack_orthopedics', 'pack_essentials', 'font_narrow', 'storage_low', 'wifi_only', 'ai_unused']);
      // a good setup gets nothing
      expect(tuneRules(const TuneCtx(rotationPackId: 'cardiology', packs: [PackMeta(id: 'cardiology', title: 'C')])), isEmpty);
      // wide screen, small text
      expect(tuneRules(const TuneCtx(widthDp: 800, libFont: 0.9)).map((e) => e.id), ['font_wide']);
      expect(tuneRules(const TuneCtx(sysTextScale: 1.4, libFont: 1.3)).map((e) => e.id), ['font_double']);
    });

    test('aggregate for AI holds counts and pack ids only', () {
      final c = const TuneCtx(rotationPackId: 'cardiology', packs: [PackMeta(id: 'cardiology', title: 'C')]);
      final j = jsonEncode(aggregateForAi(c, tuneRules(c)));
      expect(j.contains('cardiology'), true);
      for (final bad in ['name', 'patient', 'case']) {
        expect(j.toLowerCase().contains('"$bad'), false);
      }
    });
  });

  testWidgets('tuner card: suggestions, apply, undo, nothing without a tap, AI paragraph', (tester) async {
    await boot(tester);
    await tester.runAsync(() => store.setLook('libFont', 1.4));
    await tester.runAsync(() => setLibWifiOnly(false));
    installFakeAi(online: true, answers: {'suggestionIds': 'Short and helpful explanation.'});
    final fakeCtx = TuneCtx(
      widthDp: 360,
      libFont: 1.4,
      wifiOnly: false,
      packs: const [PackMeta(id: 'cardiology', title: 'Cardiology', bytes: 80 * 1024 * 1024)],
      rotationPackId: 'orthopedics',
      rotationCourse: 'Orthopedics',
      aiOn: true,
    );
    await tester.pumpWidget(const SizedBox());
    await pumpScreenWith(tester, fakeCtx);
    expect(find.text('Suggest settings for me'), findsWidgets);
    // nothing changes before a tap
    expect(store.libFontScale, 1.4);
    expect(libWifiOnly(), false);
    await tapWait(tester, find.byKey(const Key('tune_run')));
    await settle(tester, 500);
    expect(store.libFontScale, 1.4, reason: 'suggesting changes nothing');
    expect(find.byKey(const Key('tune_apply_font_narrow')), findsOneWidget);
    expect(find.byKey(const Key('tune_apply_wifi_only')), findsOneWidget);
    await tapWait(tester, find.byKey(const Key('tune_apply_font_narrow')));
    await settle(tester, 400);
    expect(store.libFontScale, 1.0);
    await tapWait(tester, find.byKey(const Key('tune_undo_font_narrow')));
    await settle(tester, 400);
    expect(store.libFontScale, 1.4, reason: 'undo');
    await tapWait(tester, find.byKey(const Key('tune_apply_all')));
    await settle(tester, 600);
    expect(store.libFontScale, 1.0);
    expect(libWifiOnly(), true);
    // the open-section suggestion opens the Packs section
    await tapWait(tester, find.byKey(const Key('tune_apply_pack_orthopedics')));
    await settle(tester, 700);
    await reveal(tester, find.text('Storage used by each pack'));
    expect(find.text('Storage used by each pack'), findsOneWidget);
    // AI paragraph (Level none: counts and pack ids only)
    await reveal(tester, find.byKey(const Key('tune_ai')));
    await tester.tap(find.byKey(const Key('tune_ai')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await settle(tester, 600);
    expect(find.byKey(const Key('tune_ai_text')), findsOneWidget);
    final sent = FakeAi.sent.last;
    expect(sent.level, AiLevel.none);
    expect(sent.prompt.contains('"suggestionIds"'), true);
    expect(sent.prompt.contains('orthopedics'), true);
    await shot(tester, 'g1_tuner_en');
  });

  testWidgets('tuner AI button hidden when AI is off', (tester) async {
    await boot(tester);
    await pumpScreenWith(tester, const TuneCtx(widthDp: 360, libFont: 1.4));
    await tester.tap(find.byKey(const Key('tune_run')));
    await settle(tester, 500);
    expect(find.byKey(const Key('tune_apply_font_narrow')), findsOneWidget);
    expect(find.byKey(const Key('tune_ai')), findsNothing);
  });

  // ---------------------------------------------------------------- screenshots
  for (final lang in ['en', 'ar']) {
    for (final size in const [Size(412, 892), Size(360, 640)]) {
      testWidgets('shots $lang ${size.width.toInt()}', (tester) async {
        await boot(tester);
        AiStore.master = true;
        await pumpScreen(tester, lang, size, size.width < 400 ? 1.3 : 1.0);
        await shot(tester, 'g1_${lang}_${size.width.toInt()}_a');
        for (var i = 1; i <= 6; i++) {
          mainScroll(tester).position.jumpTo(mainScroll(tester).position.pixels + size.height * 0.8);
          await settle(tester, 200);
          await shot(tester, 'g1_${lang}_${size.width.toInt()}_${String.fromCharCode(97 + i)}');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> pumpScreenWith(WidgetTester tester, TuneCtx ctx) async {
  setLangSetting('en');
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(360, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: shotKey,
    child: MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: LibrarySettingsScreen(tuneGather: (_) async => ctx),
    ),
  ));
  await settle(tester, 600);
}

const _groupHelp = {
  'ask': 'Answers questions using the library you installed.',
  'explain': 'Explains or translates a passage in simple words.',
  'quiz': 'Drafts practice questions from a topic.',
  'case': 'Suggests ideas for a case from a de-identified summary.',
  'reports': 'Drafts summaries of your own logbook.',
  'help': 'Answers "how do I do this in MedLog".',
};

class _Probe extends StatelessWidget {
  static int builds = 0;
  const _Probe();
  @override
  Widget build(BuildContext context) {
    builds++;
    return const SizedBox();
  }
}
