import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/lib_quiz.dart';
import 'package:medlog/lib_user.dart';
import 'package:medlog/library.dart';
import 'package:medlog/screens_quiz.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'shots_test.dart' show FakePP, boot, loadFont, realWait, serveOut, settle, shot;

bool nearDup(String a, String b) {
  final x = a.toLowerCase().trim(), y = b.toLowerCase().trim();
  return x == y || x.contains(y) || y.contains(x);
}

void checkQuestion(QuizQ q) {
  // kinds: true/false has two options, the others four; only blank kinds have "____" in the stem
  expect(q.options.length, q.kind == QKind.trueFalse ? 2 : 4, reason: q.stem);
  for (var i = 0; i < q.options.length; i++) {
    for (var j = i + 1; j < q.options.length; j++) {
      expect(nearDup(q.options[i], q.options[j]), false, reason: '${q.options[i]} ~ ${q.options[j]} in ${q.stem}');
    }
  }
  expect(q.answer >= 0 && q.answer < q.options.length, true);
  expect(q.options.contains(q.correct), true);
  if (const [QKind.definition, QKind.cloze, QKind.treatment, QKind.number].contains(q.kind)) {
    expect(q.stem.contains('____'), true, reason: q.stem);
  }
  expect(q.explanation.isNotEmpty, true);
  expect(q.title.isNotEmpty && q.packId.isNotEmpty && q.index >= 0, true);
  expect(gateQuestion(q).ok, true, reason: '${gateQuestion(q)} ${q.stem}');
  if (q.kind == QKind.definition) {
    expect(q.stem.toLowerCase().contains(q.correct.toLowerCase()), false, reason: q.stem);
    for (final o in q.options) {
      expect(q.stem.toLowerCase().contains(o.toLowerCase()), false, reason: 'option $o in stem');
    }
  }
  if (q.kind == QKind.cloze || q.kind == QKind.treatment) {
    expect(q.explanation.toLowerCase().contains(q.correct.toLowerCase()), true);
  }
}

late Directory libBase;
late HttpServer server;

Future<void> initStore() async {
  final dir = Directory.systemTemp.createTempSync('medlog2').path;
  PathProviderPlatform.instance = FakePP(dir);
  Directory('$dir/medlog/cases').createSync(recursive: true);
  void w(String name, Object o) => File('$dir/medlog/$name').writeAsStringSync(jsonEncode(o));
  w('settings.json', {'lang': 'en', 'deviceId': 'x', 'libOnline': false});
  final today = DateTime.now();
  w('rotations.json', [
    {'id': 'r1', 'name': 'Orthopedics', 'hospital': 'Al-Shifa', 'start': fmtDate(today.subtract(const Duration(days: 5))), 'end': fmtDate(today.add(const Duration(days: 20)))},
  ]);
  var n = 0;
  for (final dx in ['Osteoarthritis', 'Rheumatoid arthritis', 'Hip fracture', 'Acute coronary syndrome']) {
    File('$dir/medlog/cases/c$n.json').writeAsStringSync(jsonEncode({
      'id': 'c$n', 'schema': 2, 'created': '2026-10-1${n}T08:00:00Z', 'date': fmtDate(today), 'specialty': 'Orthopedics', 'status': 'Active', 'code': 'ORT-000$n', 'workingDx': dx, 'cc': 'pain',
    }));
    n++;
  }
  await store.init();
}

Future<void> installLibrary() async {
  server = await serveOut(null);
  libBase = Directory.systemTemp.createTempSync('medlib2');
  final lib = LibraryStore();
  await lib.init(libBase);
  final cat = await lib.fetchCatalog(catalogUrl: 'http://127.0.0.1:${server.port}/catalog.json');
  await lib.install(cat.firstWhere((e) => e.meta.id == 'orthopedics'));
  await lib.install(cat.firstWhere((e) => e.meta.id == 'cardiology'));
  await library.init(libBase);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('quiz2 logic', () {
    setUpAll(() async {
      await initStore();
      await installLibrary();
    });
    tearDownAll(() async => server.close(force: true));

    test('fallback when a source has too few articles', () async {
      expect(weakSpots(), isEmpty);
      final qs = await buildQuiz(packId: 'orthopedics', count: 6, seed: 5, source: QuizSource.favorites);
      expect(lastQuizReport.fallbackFrom, QuizSource.favorites);
      expect(qs.length >= 3, true);
      final qw = await buildQuiz(packId: 'orthopedics', count: 6, seed: 5, source: QuizSource.weak);
      expect(lastQuizReport.fallbackFrom, QuizSource.weak);
      expect(qw.length >= 3, true);
      final ok = await buildQuiz(packId: 'orthopedics', count: 6, seed: 5);
      expect(lastQuizReport.fallbackFrom, null);
      expect(ok.length >= 3, true);
    });

    test('questions are well formed (all levels, several seeds) and new kinds exist', () async {
      final kinds = <QKind, int>{for (final k in QKind.values) k: 0};
      var fixed20 = <QuizQ>[];
      final sw = Stopwatch()..start();
      await pickArticles(packId: 'orthopedics', count: 20, seed: 1);
      // ignore: avoid_print
      print('pick only: ${sw.elapsedMilliseconds} ms');
      sw.reset();
      for (final level in [QuizLevel.medium, QuizLevel.easy, QuizLevel.hard, QuizLevel.auto]) {
        for (final seed in [1, 2, 3]) {
          final qs = await buildQuiz(packId: 'orthopedics', count: 20, seed: seed, level: level);
          expect(qs.length >= 12, true, reason: 'level $level seed $seed gave ${qs.length}');
          expect(qs.map((q) => q.stem).toSet().length, qs.length);
          for (final q in qs) {
            checkQuestion(q);
            if (level == QuizLevel.medium) kinds[q.kind] = kinds[q.kind]! + 1;
          }
          if (level == QuizLevel.medium && seed == 1) fixed20 = qs;
        }
      }
      // ignore: avoid_print
      print('12 quizzes of 20 took ${sw.elapsedMilliseconds} ms');
      // ignore: avoid_print
      print('kinds over 3 medium quizzes of 20: $kinds');
      // the new default mix: management, true/false, definition and treatment questions (cloze is only a fallback)
      expect(kinds[QKind.management]! + kinds[QKind.trueFalse]! >= 4, true);
      expect(kinds[QKind.definition]! >= 2, true);
      expect(kinds.values.where((v) => v > 0).length >= 3, true);
      expect(fixed20.any((q) => q.kind == QKind.management || q.kind == QKind.treatment || q.kind == QKind.number), true);
      // a quiz over both courses and a topic
      final both = await buildQuiz(count: 10, seed: 4);
      for (final q in both) {
        checkQuestion(q);
      }
      expect(both.length >= 6, true);
      final topic = await buildQuiz(query: 'fracture', count: 6, seed: 3);
      expect(topic.isNotEmpty, true);
      for (final q in topic.take(3)) {
        for (final e in q.options.map((o) => o.length)) {
          expect(e > 0, true);
        }
      }
    });

    test('weighting prefers favorites, rotation and cases', () async {
      final titles = await library.titlesOf('orthopedics');
      final leads = await library.leadsOf('orthopedics');
      final favIdx = <int>[];
      for (var i = 0; i < titles.length && favIdx.length < 25; i += 7) {
        if (leads[i].length > 150) favIdx.add(i);
      }
      for (final i in favIdx) {
        await toggleFavorite('orthopedics', titles[i]);
      }
      final favSet = {for (final i in favIdx) i};
      var hit = 0, total = 0;
      for (var seed = 0; seed < 12; seed++) {
        final picks = await pickArticles(packId: 'orthopedics', count: 10, seed: seed, source: QuizSource.all);
        total += picks.length;
        hit += picks.where((p) => favSet.contains(p.index)).length;
      }
      final share = hit / total, poolShare = favIdx.length / titles.length;
      // ignore: avoid_print
      print('favorites share $share vs pool share $poolShare');
      expect(share > poolShare * 2.5, true);
      // random source ignores the weights
      var rhit = 0, rtotal = 0;
      for (var seed = 0; seed < 12; seed++) {
        final picks = await pickArticles(packId: 'orthopedics', count: 10, seed: seed, source: QuizSource.random);
        rtotal += picks.length;
        rhit += picks.where((p) => favSet.contains(p.index)).length;
      }
      expect(rhit / rtotal < share, true);
      // source = favorites -> questions come from favorites only
      final qs = await buildQuiz(packId: 'orthopedics', count: 8, seed: 2, source: QuizSource.favorites);
      expect(lastQuizReport.fallbackFrom, null);
      expect(qs.length >= 3, true);
      for (final q in qs) {
        expect(favSet.contains(q.index), true, reason: q.title);
      }
      // organisations are unlikely
      final all = await pickArticles(count: 20, seed: 9, limit: 200);
      final orgs = all.where((p) => RegExp(r'association|society|organization|institute|university', caseSensitive: false).hasMatch(p.title)).length;
      expect(orgs <= all.length * 0.1, true);
      // rotation -> course of the current rotation (Orthopedics), even with two courses installed
      final rot = await buildQuiz(count: 8, seed: 3, source: QuizSource.rotation);
      expect(lastQuizReport.fallbackFrom, null);
      expect(rot.every((q) => q.packId == 'orthopedics'), true);
      // cases -> articles for the diagnoses of my cases
      final cp = await pickArticles(count: 10, seed: 1, source: QuizSource.cases, limit: 200);
      expect(lastQuizReport.fallbackFrom, null);
      expect(cp.any((p) => p.title == 'Osteoarthritis'), true);
      for (final i in favIdx) {
        await toggleFavorite('orthopedics', titles[i]);
      }
    });

    test('weak spots from the quiz log and the weak source', () async {
      final titles = await library.titlesOf('orthopedics');
      String d(int n) => '2026-10-${(10 + n).toString().padLeft(2, '0')}T08:00:00Z';
      Future<void> row(int n, List<List<Object>> items) => store.upsertExtra('quizlog', {
            'id': 'r$n', 'date': d(n), 'pack': 'orthopedics', 'query': '', 'n': items.length, 'correct': items.where((e) => e[1] == true).length,
            'wrong': [for (final e in items) if (e[1] != true) e[0]],
            'items': [for (final e in items) {'p': 'orthopedics', 't': e[0], 'ok': e[1]}],
          });
      final a = titles[3], b = titles[40], c = titles[80], e = titles[120], f = titles[160];
      await row(1, [[a, true], [b, false], [c, true], [e, false], [f, false]]);
      await row(2, [[a, false], [b, false], [c, true], [e, true]]);
      await row(3, [[a, true], [b, true], [c, true], [f, false]]);
      // a: false in row2 then true in row3 -> last right, wrong 1 -> not weak
      // b: wrong, wrong, right -> last right but wrong>=2 in last 5 -> weak
      // c: always right -> not weak; e: wrong then right -> not weak; f: wrong, wrong(last) -> weak
      final weak = weakSpots();
      final names = weak.map((w) => w.title).toSet();
      expect(names, {b, f});
      expect(weak.firstWhere((w) => w.title == f).lastWrong, true);
      expect(weak.firstWhere((w) => w.title == b).lastWrong, false);
      expect(weak.firstWhere((w) => w.title == b).wrongRecent, 2);
      // only the last 40 rows count
      for (var k = 0; k < 40; k++) {
        await store.upsertExtra('quizlog', {'id': 'old$k', 'date': '2026-11-${(k % 28 + 1).toString().padLeft(2, '0')}T0$k:00:00Z'.replaceAll('T0${k}', 'T09'), 'pack': 'orthopedics', 'n': 1, 'correct': 1, 'wrong': [], 'items': [{'p': 'orthopedics', 't': c, 'ok': true}]});
      }
      expect(weakSpots(), isEmpty);
      for (var k = 0; k < 40; k++) {
        await store.removeExtra('quizlog', 'old$k');
      }
      // more weak articles so the weak source has enough
      await row(4, [[titles[200], false], [titles[240], false], [titles[280], false]]);
      final w2 = weakSpots().map((w) => w.title).toSet();
      expect(w2.containsAll({b, f, titles[200], titles[240], titles[280]}), true);
      final qs = await buildQuiz(packId: 'orthopedics', count: 10, seed: 3, source: QuizSource.weak);
      expect(lastQuizReport.fallbackFrom, null);
      expect(qs.isNotEmpty, true);
      for (final q in qs) {
        expect(w2.contains(q.title), true, reason: q.title);
      }
      // auto level: weak spots are asked easy
      final auto = await buildQuiz(packId: 'orthopedics', count: 6, seed: 3, source: QuizSource.weak, level: QuizLevel.auto);
      expect(auto.every((q) => q.level == QuizLevel.easy), true);
    });

    test('ignored questions are never asked again', () async {
      final qs = await buildQuiz(packId: 'cardiology', count: 10, seed: 11);
      expect(qs.length >= 5, true);
      final gone = qs.take(4).toList();
      for (final q in gone) {
        await ignoreQuizQuestion(q.hash);
      }
      expect(quizIgnored().containsAll(gone.map((q) => q.hash)), true);
      expect(store.settings['quizIgnored'] is List, true);
      for (final seed in [11, 12]) {
        final again = await buildQuiz(packId: 'cardiology', count: 10, seed: seed);
        for (final q in again) {
          expect(gone.any((g) => g.hash == q.hash), false);
        }
      }
    });
  });

  setUpAll(() async {
    final rb = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
    await loadFont('Tajawal', ['$fd/Tajawal_400Regular.ttf', '$fd/Tajawal_500Medium.ttf', '$fd/Tajawal_700Bold.ttf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('QZ screens $lang', (tester) async {
      await boot(tester, {'lang': lang, 'author': 'Dr. Mohammed', 'palette': 'clinic', 'mode': 'study', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false});
      late HttpServer srv;
      await tester.runAsync(() async {
        srv = await serveOut(null);
        final base = Directory.systemTemp.createTempSync('medlibw');
        await library.init(base);
        final cat = await library.fetchCatalog(catalogUrl: 'http://127.0.0.1:${srv.port}/catalog.json');
        await library.install(cat.firstWhere((e) => e.meta.id == 'orthopedics'));
        final titles = await library.titlesOf('orthopedics');
        final oa = titles.indexOf('Osteoarthritis');
        for (final t in [titles[oa], titles[oa + 1], titles[oa + 2]]) {
          await store.upsertExtra('quizlog', {
            'id': 'w$t', 'date': nowIso(), 'pack': 'orthopedics', 'query': '', 'n': 1, 'correct': 0, 'wrong': [t], 'items': [{'p': 'orthopedics', 't': t, 'ok': false}], 'source': 'all', 'level': 'medium',
          });
        }
        await toggleFavorite('orthopedics', 'Osteoarthritis');
      });
      await settle(tester, 3000);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute(builder: (_) => const QuizScreen(packId: 'orthopedics')));
      await settle(tester, 800);
      await shot(tester, 'QZ_${lang}_setup');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await settle(tester, 500);
      await shot(tester, 'QZ_${lang}_setup_bottom');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
      await settle(tester, 300);
      await tester.tap(find.byType(FilledButton).first);
      for (var k = 0; k < 400 && find.byType(OutlinedButton).evaluate().isEmpty; k++) {
        await realWait(tester, 150);
      }
      await settle(tester, 500);
      expect(find.byType(OutlinedButton), findsWidgets);
      await tester.tap(find.byType(OutlinedButton).first);
      await settle(tester, 500);
      await shot(tester, 'QZ_${lang}_question');
      for (var q = 0; q < 40 && find.byIcon(Icons.speed).evaluate().isEmpty; q++) {
        final next = find.byType(FilledButton);
        if (next.evaluate().isEmpty) {
          await tester.tap(find.byType(OutlinedButton).first);
          await settle(tester, 250);
          continue;
        }
        await tester.ensureVisible(next.last);
        await tester.tap(next.last);
        await realWait(tester, 250);
        await settle(tester, 300);
      }
      expect(find.byIcon(Icons.speed), findsOneWidget);
      await settle(tester, 800);
      await shot(tester, 'QZ_${lang}_results');
      await tester.runAsync(() => srv.close(force: true));
    });
  }
}
