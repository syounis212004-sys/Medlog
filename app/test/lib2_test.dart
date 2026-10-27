import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as mm show Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' as i18 show Text;
import 'package:medlog/lib_plan.dart';
import 'package:medlog/lib_quiz.dart';
import 'package:medlog/lib_user.dart';
import 'package:medlog/library.dart';
import 'package:medlog/screens_learn.dart';
import 'package:medlog/screens_library.dart';
import 'package:medlog/screens_quiz.dart';
import 'package:medlog/screens_search.dart';

import 'lib2_util.dart';

Future<void> realWait(WidgetTester tester, [int ms = 400]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Real time passes in small steps with frames in between (HTTP answers need both).
Future<void> realSteps(WidgetTester tester, [int steps = 8]) async {
  for (var i = 0; i < steps; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Alternates real time and frames until [cond] holds (chains of file reads need many small steps).
Future<bool> pumpUntil(WidgetTester tester, bool Function() cond, {int maxMs = 20000}) async {
  final sw = Stopwatch()..start();
  while (!cond() && sw.elapsedMilliseconds < maxMs) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 8)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return cond();
}

Future<void> settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUpAll(() async {
    await initStoreLight();
    final base = installPacks(['orthopedics', 'cardiology', 'clinical-essentials', 'medlineplus']);
    await library.init(base);
  });
  tearDown(() {
    netKindProvider = () async => NetKind.wifi;
  });

  // ---------------------------------------------------------------- 1) Wi-Fi only
  group('wifi only', () {
    test('setting and rule', () async {
      expect(libWifiOnly(), true); // default on
      expect(needsWifiCheck(bytes: 3 * 1024 * 1024), false);
      expect(needsWifiCheck(bytes: 30 * 1024 * 1024), true);
      expect(needsWifiCheck(bytes: 1000, images: true), true);
      await setLibWifiOnly(false);
      expect(needsWifiCheck(bytes: 30 * 1024 * 1024, images: true), false);
      await setLibWifiOnly(true);
    });

    test('a failing plugin never blocks', () async {
      netKindProvider = () async => throw StateError('no plugin');
      expect(await currentNetKind(), NetKind.unknown);
      expect(await waitForWifi(every: const Duration(milliseconds: 5)), true);
    });

    test('waitForWifi waits for Wi-Fi and can be cancelled', () async {
      var n = 0;
      netKindProvider = () async => ++n < 4 ? NetKind.mobile : NetKind.wifi;
      expect(await waitForWifi(every: const Duration(milliseconds: 5)), true);
      expect(n, 4);
      netKindProvider = () async => NetKind.mobile;
      var calls = 0;
      expect(await waitForWifi(every: const Duration(milliseconds: 5), cancelled: () => ++calls > 3), false);
    });

    testWidgets('dialog: download once / wait / cancel', (tester) async {
      bool? result;
      late BuildContext ctx;
      await tester.pumpWidget(host(Builder(builder: (c) {
        ctx = c;
        return TextButton(onPressed: () async => result = await allowDownloadNow(ctx, bytes: 50 * 1024 * 1024, images: true), child: const mm.Text('go'));
      })));
      // on Wi-Fi: no question
      netKindProvider = () async => NetKind.wifi;
      await tester.tap(find.text('go'));
      await realWait(tester);
      expect(find.text('You are on mobile data. Download anyway?'), findsNothing);
      expect(result, true);

      netKindProvider = () async => NetKind.mobile;
      await tester.tap(find.text('go'));
      await realWait(tester);
      expect(find.text('You are on mobile data. Download anyway?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await realWait(tester);
      expect(result, false);

      await tester.tap(find.text('go'));
      await realWait(tester);
      await tester.tap(find.text('Download once'));
      await realWait(tester);
      expect(result, true);

      result = null;
      await tester.tap(find.text('go'));
      await realWait(tester);
      var polls = 0;
      netKindProvider = () async => ++polls < 3 ? NetKind.mobile : NetKind.wifi;
      wifiPollEvery = const Duration(milliseconds: 20);
      await tester.tap(find.text('Wait for Wi-Fi'));
      await realWait(tester, 500);
      expect(polls >= 3, true);
      expect(result, true);
      wifiPollEvery = const Duration(seconds: 4);

      // small text packs and the switched-off setting never ask
      await tester.runAsync(() => setLibWifiOnly(false));
      netKindProvider = () async => NetKind.mobile;
      result = null;
      await tester.tap(find.text('go'));
      await realWait(tester);
      expect(find.text('You are on mobile data. Download anyway?'), findsNothing);
      expect(result, true);
      await tester.runAsync(() => setLibWifiOnly(true));
    });

    testWidgets('Download all images asks on mobile data and Cancel installs nothing', (tester) async {
      HttpOverrides.global = null;
    late HttpServer server;
      final before = library.packs.length;
      await tester.runAsync(() async {
        server = await serveBuild();
        libraryCatalogUrl = 'http://127.0.0.1:${server.port}/catalog.json';
      });
      netKindProvider = () async => NetKind.mobile;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PackManagerScreen()));
      await realSteps(tester);
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Images (optional)'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Images (optional)'));
      await settle(tester);
      final dl = find.textContaining('Download all (');
      expect(dl, findsWidgets);
      await tester.ensureVisible(dl.last);
      await tester.tap(dl.last);
      await settle(tester);
      // the usual "download N courses?" question first
      await tester.tap(find.widgetWithText(FilledButton, 'Download'));
      await realWait(tester);
      expect(find.text('You are on mobile data. Download anyway?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await realWait(tester);
      expect(library.packs.length, before);
      await tester.runAsync(() => server.close(force: true));
    });

    testWidgets('settings screen has the switch', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: LibrarySettingsScreen()));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Packs & downloads'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Packs & downloads'));
      await settle(tester);
      expect(find.text('Download on Wi-Fi only'), findsOneWidget);
      await tester.ensureVisible(find.text('Download on Wi-Fi only'));
      await settle(tester, 300);
      await tester.tap(find.text('Download on Wi-Fi only'));
      await realWait(tester);
      expect(libWifiOnly(), false);
      await tester.runAsync(() => setLibWifiOnly(true));
    });
  });

  // ---------------------------------------------------------------- 2) sources
  group('sources', () {
    test('title suffix helpers', () {
      expect(titleSource('Sepsis — WikEM'), 'WikEM');
      expect(titleSource('Sepsis — Project Tulip'), 'Project Tulip');
      expect(titleSource('Sepsis'), null);
      expect(titleSource('Rise — and fall'), null);
      expect(stripSource('Sepsis — CDC'), 'Sepsis');
      expect(stripSource('Rise — and fall'), 'Rise — and fall');
      expect(library.sourceOf('orthopedics', 'Osteoarthritis'), 'Wikipedia');
      expect(library.sourceOf('medlineplus', 'Abdominal Pain'), 'MedlinePlus');
      expect(library.sourceOf('clinical-essentials', 'X — NCI'), 'NCI');
      expect(library.availableSources(), ['WikEM', 'CDC', 'NCI', 'Project Tulip', 'Wikipedia', 'MedlinePlus']);
    });

    test('search filter by source', () async {
      final all = await library.searchEx('pain', limit: 400);
      expect(all.map((h) => library.sourceOf(h.packId, h.title)).toSet().length >= 3, true);
      for (final s in ['WikEM', 'Wikipedia', 'MedlinePlus', 'CDC']) {
        final hits = await library.searchEx('infection', limit: 100, source: s);
        expect(hits.isNotEmpty, true, reason: s);
        for (final h in hits) {
          expect(library.sourceOf(h.packId, h.title), s, reason: '${h.title} for $s');
        }
      }
      expect((await library.searchEx('pain', source: 'NCI')).every((h) => h.title.endsWith('— NCI')), true);
    });

    test('essentials hit ranks above the long Wikipedia article on a tie, other ranking intact', () async {
      final h = await library.searchEx('osteoarthritis', limit: 10);
      final ess = h.indexWhere((x) => x.packId == kEssentialsPackId && stripSource(x.title).toLowerCase() == 'osteoarthritis');
      final wiki = h.indexWhere((x) => x.packId == 'orthopedics' && x.title == 'Osteoarthritis');
      // the same condition from the same source is one row: the concise essentials copy stays, the course copy is folded into it
      expect(ess >= 0, true);
      expect(wiki, -1, reason: 'Osteoarthritis of the course pack is a duplicate of the essentials one');
      // abbreviations still first
      final oa = await library.searchEx('OA');
      expect(stripSource(oa.first.title).toLowerCase().contains('osteoarthritis'), true);
      // exact title still beats longer ones
      final ex = await library.search('Osteoarthritis', packId: 'orthopedics');
      expect(ex.first.title, 'Osteoarthritis');
    });

    testWidgets('library search shows chips and badges and filters', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: LibraryScreen(initialQuery: 'pain')));
      await realWait(tester, 800);
      await settle(tester);
      expect(find.widgetWithText(ChoiceChip, 'WikEM'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(find.byType(SourceBadge), findsWidgets);
      await tester.tap(find.widgetWithText(ChoiceChip, 'MedlinePlus'));
      await realWait(tester, 800);
      await settle(tester);
      final badges = find.byType(SourceBadge).evaluate().map((e) => ((e.widget as SourceBadge).source)).toSet();
      expect(badges, {'MedlinePlus'});
    });

    testWidgets('pack browse of Clinical Essentials has the same chips', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: PackBrowseScreen(pack: library.pack(kEssentialsPackId)!)));
      await realWait(tester, 800);
      await settle(tester);
      expect(find.widgetWithText(ChoiceChip, 'CDC'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'CDC'));
      await settle(tester);
      final badges = find.byType(SourceBadge).evaluate().map((e) => ((e.widget as SourceBadge).source)).toSet();
      expect(badges, {'CDC'});
      expect(find.textContaining('— CDC'), findsNothing);
    });

    testWidgets('unified search library section filters by source', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SearchScreen(initial: 'pain')));
      await realWait(tester, 900);
      await settle(tester);
      await tester.tap(find.byIcon(Icons.tune)); // the source filter is in the filters sheet
      await settle(tester);
      expect(find.widgetWithText(ChoiceChip, 'WikEM'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'WikEM'));
      await settle(tester);
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await realWait(tester, 900);
      await settle(tester);
      final badges = find.byType(SourceBadge).evaluate().map((e) => ((e.widget as SourceBadge).source)).toSet();
      expect(badges, {'WikEM'});
    });
  });

  // ---------------------------------------------------------------- 3) reading list
  group('reading list', () {
    testWidgets('section appears above favorites, opens and removes', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1400);
      addTearDown(tester.view.reset);
      expect(readingList(), isEmpty);
      await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
      await realWait(tester);
      await settle(tester);
      expect(find.text('Read later'), findsNothing);

      await tester.runAsync(() async {
        await toggleReadingList('orthopedics', 'Osteoarthritis');
        await toggleReadingList('cardiology', (await library.titlesOf('cardiology'))[3]);
        await toggleFavorite('orthopedics', 'Osteoarthritis');
      });
      await tester.pumpWidget(const MaterialApp(home: LibraryScreen(key: ValueKey('again'))));
      await realWait(tester);
      await settle(tester);
      expect(find.text('Read later'), findsOneWidget);
      final later = tester.getTopLeft(find.text('Read later')).dy;
      final fav = tester.getTopLeft(find.text('Favorites')).dy;
      expect(later < fav, true);
      expect(find.widgetWithText(ListTile, 'Osteoarthritis'), findsWidgets);
      // remove with the X button
      await tester.tap(find.byTooltip('Remove').first);
      await realSteps(tester, 5);
      expect(readingList().length, 1);
      // swipe the other one away
      await tester.fling(find.byType(Dismissible).first, const Offset(-500, 0), 1500);
      await settle(tester, 1000);
      await realSteps(tester, 5);
      expect(readingList(), isEmpty);
      expect(find.text('Read later'), findsNothing);
      await tester.runAsync(() => toggleFavorite('orthopedics', 'Osteoarthritis'));
    });
  });

  // ---------------------------------------------------------------- 4) quiz
  group('quiz', () {
    test('clinical essentials quizzes, section and clean titles, no repeated article', () async {
      final qs = await buildQuiz(packId: kEssentialsPackId, count: 10, seed: 11);
      expect(qs.length >= 5, true, reason: 'only ${qs.length}');
      for (final q in qs) {
        expect(q.shownTitle.contains(' — '), false, reason: q.title);
        expect(q.stem.contains('— WikEM') || q.stem.contains('— NCI') || q.stem.contains('— CDC'), false, reason: q.stem);
        for (final o in q.options) {
          expect(RegExp(r'— (WikEM|Wikipedia|CDC|NCI|Project Tulip)$').hasMatch(o), false, reason: o);
        }
        expect(q.explanation.isNotEmpty, true);
      }
      expect(qs.any((q) => q.section.isNotEmpty), true);
      // one question per article, also across courses that hold the same topic
      for (final seed in [1, 2, 3, 4]) {
        final all = await buildQuiz(count: 12, seed: seed);
        final titles = [for (final q in all) q.shownTitle.toLowerCase().trim()];
        expect(titles.toSet().length, titles.length, reason: '$titles');
      }
    });

    test('source filter inside the essentials course', () async {
      for (final s in ['WikEM', 'CDC']) {
        final picks = await pickArticles(packId: kEssentialsPackId, count: 10, seed: 2, sourceFilter: s, limit: 60);
        expect(picks.isNotEmpty, true, reason: s);
        for (final p in picks) {
          expect(titleSource(p.title), s);
        }
      }
      final qs = await buildQuiz(packId: kEssentialsPackId, count: 6, seed: 5, sourceFilter: 'WikEM');
      for (final q in qs) {
        expect(titleSource(q.title), 'WikEM');
      }
    });

    testWidgets('wrong answer shows the why card with the source', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: QuizScreen(packId: 'orthopedics', autoStart: true)));
      expect(await pumpUntil(tester, () => find.byType(OutlinedButton).evaluate().isNotEmpty), true);
      var found = false;
      for (var i = 0; i < 10 && !found; i++) {
        final opts = find.byType(OutlinedButton);
        if (opts.evaluate().isEmpty) break;
        await tester.ensureVisible(opts.first);
        await tester.tap(opts.first);
        await settle(tester);
        found = find.text('Why did I miss this?').evaluate().isNotEmpty;
        if (!found) {
          final next = find.widgetWithText(FilledButton, 'Next');
          if (next.evaluate().isEmpty) break;
          await tester.ensureVisible(next);
          await tester.tap(next);
          await settle(tester);
        }
      }
      expect(found, true);
      expect(find.text('Open the article at this part'), findsOneWidget);
      expect(find.text('Add to review cards'), findsOneWidget);
      await tester.ensureVisible(find.text('Add to review cards'));
      await tester.tap(find.text('Add to review cards'));
      expect(await pumpUntil(tester, () => store.listOf('libcards').isNotEmpty, maxMs: 3000), true);
    });
  });

  // ---------------------------------------------------------------- 5) planner
  group('exam planner', () {
    String inDays(int n) => fmtDate(DateTime.now().add(Duration(days: n)));

    test('days left and schedule', () async {
      expect(examDaysLeft(inDays(10)), 10);
      expect(examDaysLeft(todayStr()), 0);
      expect(examDaysLeft(inDays(-2)), -2);
      final items = [for (var i = 0; i < 23; i++) PlanItem('orthopedics', 'T$i', i < 3)];
      final plan = ExamPlan(name: 'Board', date: inDays(5), packs: const ['orthopedics'], items: items, done: {'orthopedics|T0'});
      final days = planSchedule(plan);
      expect(days.length, 5);
      expect(days.fold<int>(0, (a, d) => a + d.items.length), 22);
      expect(days.first.items.length, 5); // ceil(22/5)
      expect(days.first.questions, 20);
      expect(days.first.items.first.title, 'T1');
      // exam today: everything today
      final today = ExamPlan(name: '', date: todayStr(), packs: const [], items: items, done: const {});
      expect(planSchedule(today).length, 1);
      expect(planSchedule(today).first.items.length, 23);
      expect(planSchedule(ExamPlan(name: '', date: inDays(3), packs: const [], items: const [], done: const {})), isEmpty);
    });

    test('weak spots first, then unreviewed topics of the chosen courses only', () async {
      final t = await library.titlesOf('orthopedics');
      final ct = await library.titlesOf('cardiology');
      await store.upsertExtra('quizlog', {
        'id': 'qlan1',
        'date': '2026-10-20T08:00:00Z',
        'pack': 'orthopedics',
        'n': 2,
        'correct': 0,
        'items': [
          {'p': 'orthopedics', 't': t[40], 'ok': false},
          {'p': 'cardiology', 't': ct[10], 'ok': false},
        ],
      });
      final items = await buildPlanItems(packs: ['orthopedics'], examDate: inDays(6), universe: 'all');
      expect(items.first.title, t[40]);
      expect(items.first.weak, true);
      expect(items.any((i) => i.packId == 'cardiology'), false); // not a chosen course
      expect(items.where((i) => i.weak).length, 1);
      expect(items.length, 30); // 6 days x 5
      expect(items.map((i) => i.key).toSet().length, items.length);
      // tested articles are not offered again as "new"
      expect(items.skip(1).any((i) => i.title == t[40]), false);
      // same inputs -> same plan (ticks stay valid)
      final again = await buildPlanItems(packs: ['orthopedics'], examDate: inDays(6), universe: 'all');
      expect([for (final i in again) i.key], [for (final i in items) i.key]);
      // two courses are mixed
      final two = await buildPlanItems(packs: ['orthopedics', 'cardiology'], examDate: inDays(4), universe: 'all');
      expect(two.where((i) => i.packId == 'orthopedics').isNotEmpty && two.where((i) => i.packId == 'cardiology').isNotEmpty, true);
      // only titles of the installed packs
      for (final i in two) {
        expect((await library.indexOfTitle(i.packId, i.title)) != null, true);
      }
    });

    test('ticks are stored', () async {
      final plan = ExamPlan(name: 'FCPS', date: inDays(9), packs: const ['orthopedics'], items: const [PlanItem('orthopedics', 'A', false), PlanItem('orthopedics', 'B', true)], done: const {});
      await saveExamPlan(plan);
      await togglePlanDone('orthopedics|A');
      expect(examPlan()!.done, {'orthopedics|A'});
      expect(examPlan()!.name, 'FCPS');
      await togglePlanDone('orthopedics|A');
      expect(examPlan()!.done, isEmpty);
      await saveExamPlan(null);
      expect(examPlan(), null);
    });

    testWidgets('empty state, form, plan view and ticking', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1600);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => saveExamPlan(null));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ExamPlannerSection()))));
      await settle(tester);
      await tester.tap(find.text('Exam planner'));
      await settle(tester);
      expect(find.textContaining('No exam date yet'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Build my plan'), findsOneWidget);
      // the button waits for a date and a course
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Build my plan')).onPressed, isNull);
      await tester.tap(find.text('Choose the exam date'));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Orthopedics'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Build my plan'));
      expect(await pumpUntil(tester, () => find.byKey(const ValueKey('planDaysLeft')).evaluate().isNotEmpty), true);
      expect(find.byKey(const ValueKey('planDaysLeft')), findsOneWidget);
      final days = int.parse((tester.widget(find.byKey(const ValueKey('planDaysLeft'))) as mm.Text).data!);
      expect(days >= 29 && days <= 31, true);
      expect(find.byKey(const ValueKey('planToday')), findsOneWidget);
      final today = (tester.widget(find.byKey(const ValueKey('planToday'))) as i18.Text).data;
      expect(today.startsWith('Today: '), true);
      expect(today.contains('articles +') || today.contains('article +'), true);
      expect(examPlan() != null && examPlan()!.items.isNotEmpty, true);
      // tick the first item
      final first = examPlan()!.items.first;
      await tester.tap(find.byType(Checkbox).first);
      expect(await pumpUntil(tester, () => examPlan()!.done.contains(first.key), maxMs: 3000), true);
      expect(await pumpUntil(tester, () => find.textContaining('1 of ').evaluate().isNotEmpty, maxMs: 4000), true);
      expect(find.textContaining('1 of '), findsOneWidget);
    });
  });
}
