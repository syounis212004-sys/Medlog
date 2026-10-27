import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart';
import 'package:medlog/screens_article.dart';
import 'package:medlog/screens_library.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:medlog/lib_sheet.dart';
import 'package:medlog/lib_text.dart';
import 'package:medlog/library.dart';


Directory installAllPacks() {
  final base = Directory.systemTemp.createTempSync('l3base');
  final lib = Directory('${base.path}/library')..createSync(recursive: true);
  final cat = jsonDecode(File('../library/catalog.json').readAsStringSync()) as Map;
  final metas = <Map>[];
  for (final e in cat['packs'] as List) {
    if (e['kind'] == 'images') continue;
    final id = e['id'];
    for (final ext in ['idx', 'bin']) {
      Link('${lib.path}/$id.$ext').createSync('../library/$id.$ext');
    }
    metas.add({...(e as Map), 'bytes': File('../library/$id.bin').lengthSync() + File('../library/$id.idx').lengthSync()});
  }
  File('${lib.path}/installed.json').writeAsStringSync(jsonEncode(metas));
  return base;
}

class _PP extends PathProviderPlatform {
  final String dir;
  _PP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

Directory _installSome(List<String> ids) {
  final base = Directory.systemTemp.createTempSync('l3some');
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

Future<void> _pumpReal(WidgetTester t, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Iterable<SBlock> _allBlocks(Sheet sh) sync* {
  for (final p in sh.lead) {
    yield* p.blocks;
  }
  for (final s in sh.sections) {
    for (final p in s.parts) {
      yield* p.blocks;
    }
  }
}

String _sq(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Runs the engine on the hand-labelled lines; returns precision / recall of the dose and red-flag tags.
Map<String, num> evalLabels({bool print = false}) {
  final labels = (jsonDecode(File('/tmp/eval/lib/out2/sheet_labels.json').readAsStringSync()) as Map)['lines'] as List;
  final packs = <String, Map>{};
  final bins = <String, List<int>>{};
  final sheets = <String, Sheet>{};
  var tpD = 0, fpD = 0, fnD = 0, tpR = 0, fpR = 0, fnR = 0, missing = 0;
  final out = StringBuffer();
  for (final l in labels.cast<Map>()) {
    final pid = l['pack'] as String;
    final idx = packs[pid] ??= jsonDecode(utf8.decode(gzip.decode(File('../library/$pid.idx').readAsBytesSync()))) as Map;
    final bin = bins[pid] ??= File('../library/$pid.bin').readAsBytesSync();
    final ti = (idx['t'] as List).indexOf(l['title']);
    if (ti < 0) {
      missing++; // article moved or dropped when the pack was rebuilt
      continue;
    }
    final key = '$pid|${l['title']}';
    final sh = sheets[key] ??= () {
      final o = (idx['o'] as List)[ti] as int, n = (idx['n'] as List)[ti] as int;
      final a = LibArticle.fromJson(jsonDecode(utf8.decode(gzip.decode(bin.sublist(o, o + n)))) as Map<String, dynamic>);
      return buildSheet([SheetSrc('x', a)]);
    }();
    final want = _sq(l['text'] as String);
    SBlock? hit;
    for (final b in _allBlocks(sh)) {
      if (_sq(b.text).contains(want)) {
        hit = b;
        break;
      }
    }
    if (hit == null) {
      missing++;
      continue;
    }
    final dose = hit.tag == SheetTag.dose, red = hit.tag == SheetTag.redFlag;
    final wd = l['dose'] == 1, wr = l['red'] == 1;
    if (dose && wd) tpD++;
    if (dose && !wd) fpD++;
    if (!dose && wd) fnD++;
    if (red && wr) tpR++;
    if (red && !wr) fpR++;
    if (!red && wr) fnR++;
    if (print && ((dose != wd) || (red != wr))) out.writeln('${dose != wd ? (dose ? 'FP-dose' : 'FN-dose') : ''} ${red != wr ? (red ? 'FP-red' : 'FN-red') : ''} | ${l['sec']} | ${l['text']}');
  }
  if (print) File('/tmp/h/label_errors.txt').writeAsStringSync(out.toString());
  double pr(int tp, int fp) => tp + fp == 0 ? 1 : tp / (tp + fp);
  double rc(int tp, int fn) => tp + fn == 0 ? 1 : tp / (tp + fn);
  return {
    'doseP': pr(tpD, fpD), 'doseR': rc(tpD, fnD), 'redP': pr(tpR, fpR), 'redR': rc(tpR, fnR),
    'tpD': tpD, 'fpD': fpD, 'fnD': fnD, 'tpR': tpR, 'fpR': fpR, 'fnR': fnR, 'missing': missing, 'n': labels.length,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sheet precision / recall on the 153 hand-labelled lines', () {
    final m = evalLabels(print: true);
    print('LABELS ${m.entries.map((e) => '${e.key}=${e.value is double ? (e.value as double).toStringAsFixed(2) : e.value}').join(' ')}');
  });
  group('in-text index', () {
    test('build on all 28 packs: size, time, queries', () async {
      final base = installAllPacks();
      final s = LibraryStore();
      await s.init(base);
      final sw = Stopwatch()..start();
      await s.ensureFts();
      final tBuild = sw.elapsedMilliseconds;
      var fts = 0, packs = 0;
      for (final p in s.textPacks) {
        fts += File('${s.dir.path}/${p.id}.fts').lengthSync();
        packs += p.bytes;
      }
      print('FTS build all ${s.textPacks.length} packs: $tBuild ms, index ${(fts / 1e6).toStringAsFixed(1)} MB for ${(packs / 1e6).toStringAsFixed(1)} MB of packs (${(100 * fts / packs).toStringAsFixed(0)}%), indexed ${s.ftsIndexed}');
      expect(s.ftsIndexed, s.textPacks.length);
      expect(fts / packs < 0.3, true);
      // body hits: the words are in the shown sentence and it is highlighted
      for (final q in ['STEMI', 'GCS', 'CURB-65', 'APGAR', 'qSOFA', 'SBP']) {
        final h = (await s.searchEx(q, body: true)).where((x) => x.inText).toList();
        expect(h.isNotEmpty, true, reason: q);
        final low = q.toLowerCase().replaceAll('-', '');
        final okAny = h.any((x) => x.snippet.toLowerCase().replaceAll('-', '').contains(low.replaceAll('curb65', 'curb65')) && x.marks.isNotEmpty);
        expect(okAny, true, reason: 'snippet with the term for $q');
        // title hits first, then in-text hits
        final all = await s.searchEx(q, body: true);
        final firstIn = all.indexWhere((x) => x.inText);
        expect(all.skip(firstIn).any((x) => x.titleMatch && !x.inText), false, reason: 'title matches come before in-text hits ($q)');
      }
      // no duplicates of one condition and source
      final os = await s.searchEx('osteoarthritis', body: true, concise: true);
      final keys = [for (final x in os) '${titleKey(x.title)}|${s.sourceOf(x.packId, x.title)}'];
      expect(keys.toSet().length, keys.length);
      // a body search is quick once the indexes are loaded
      final sw2 = Stopwatch()..start();
      await s.searchEx('calcium gluconate', body: true, concise: true);
      print('FTS warm body search: ${sw2.elapsedMilliseconds} ms');
      expect(sw2.elapsedMilliseconds < 3000, true);
      // an index of another version of the pack is not used
      File('${s.dir.path}/cardiology.fts').writeAsBytesSync([1, 2, 3]);
      s.warmFts();
      for (final q in ['STEMI', 'GCS', 'SBP', 'CURB-65', 'APGAR', 'qSOFA', 'CHA2DS2-VASc', 'HAS-BLED', 'MELD', 'calcium gluconate', 'warfarin reversal', 'high potassium', 'paracetamol overdose', 'Light criteria']) {
        sw.reset();
        final h = await s.searchEx(q, body: true, concise: true);
        final ms = sw.elapsedMilliseconds;
        final inText = h.where((x) => x.inText).toList();
        print('FTSQ "$q" $ms ms, ${h.length} hits (${inText.length} in text): ${[for (final x in h.take(5)) '${x.inText ? '*' : ''}${stripSource(x.title)}@${x.packId}'].join(' | ')}');
        if (q != 'Light criteria' && q != 'MELD') expect(h.isNotEmpty, true, reason: q);
        if (inText.isNotEmpty) print('      snippet: ${inText.first.snippetHead} :: ${inText.first.snippet.substring(0, inText.first.snippet.length.clamp(0, 160))}');
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
  group('text helpers', () {
    test('caption filter keeps clinical sentences', () {
      for (final c in [
        'MRI of osteoarthritis in the knee, with characteristic narrowing of the joint space',
        'Micrograph showing a Mallory body. Original magnification 400X. H&E stain.',
        'Figure 3: A 26-year-old man presenting with wrist pain after being assaulted.',
        '(a) Coronal T1-weighted MRI shows a linear low-signal band through the femoral neck (arrowheads).',
        'Diagram of the human shoulder joint, front view',
        'Ultrasound showing a pneumothorax',
      ]) {
        expect(isCaptionLike(c), true, reason: c);
      }
      for (final c in [
        'MRI provides a clear picture of the soft tissue of the abdomen, however, its expense often outweighs the benefits.',
        'Medicine describes the pathology of diseases and promotes prevention, diagnosis, and treatment.',
        'Do NOT delay antibiotics for cultures.',
        'Aspirin 325 mg chewed in all patients with suspected ACS.',
        'The mandibular (lower) teeth are innervated by the inferior alveolar nerve, a branch of the mandibular division.',
        'Light sensitivity (photophobia) is common.',
      ]) {
        expect(isCaptionLike(c), false, reason: c);
      }
      expect(isGalleryHeading('Additional images'), true);
      expect(isGalleryHeading('Treatment'), false);
    });

    test('fitSentences never cuts inside a sentence', () {
      const t = 'First sentence is here. Second sentence follows it closely. Third one ends the paragraph.';
      expect(fitSentences(t, 40), 'First sentence is here.');
      expect(fitSentences(t, 200), t);
      expect(fitSentences('A' * 500, 100), '');
    });

    test('abbreviations and phrases', () {
      expect(expandAbbrev('STEMI'), contains('st elevation myocardial infarction'));
      expect(expandAbbrev('GCS'), contains('glasgow coma scale'));
      expect(expandAbbrev('SBP'), containsAll(['spontaneous bacterial peritonitis', 'systolic blood pressure']));
      expect(expandAbbrev('CURB-65').length, 2);
      expect(expandAbbrev('apgar'), contains('apgar score'));
      expect(expandAbbrev('high potassium'), contains('hyperkalemia'));
      expect(expandAbbrev('VSD'), contains('ventricular septal defect'));
      expect(topicOfTitle('Tibial fracture'), 'Fractures and injuries');
      expect(topicOfTitle('Abdominal muscles'), 'Anatomy');
      expect(topicOfTitle('Atorvastatin'), 'Drugs and treatments');
    });

    test('sheet: captions and gallery sections are left out only when asked; doses and tables', () {
      final a = LibArticle('Test', '', [
        const LibSection('', 'Test is a condition. MRI of the knee showing narrowing (arrow). It is common.'),
        const LibSection('Management', '• Ceftriaxone 1 g IV once\n• Do NOT give NSAIDs to these patients\n• Enoxaparin\n  – 1 mg/kg SC BID'),
        const LibSection('Additional images', 'Diagram of the knee'),
        LibSection('Dosing', 'Doses are listed below.', [
          const LibTable('Dose chart', [['Drug', 'Dose'], ['A', '5 mg IV'], ['B', '10 mg PO']]),
        ]),
      ]);
      final raw = buildSheet([SheetSrc('x', a)]);
      final clean = buildSheet([SheetSrc('x', a)], hideCaptions: true);
      expect(_allBlocks(raw).any((b) => b.text.contains('MRI of the knee')), true);
      expect(_allBlocks(clean).any((b) => b.text.contains('MRI of the knee')), false);
      expect(clean.sections.any((s) => s.title == 'Additional images'), false);
      expect(raw.sections.any((s) => s.title == 'Additional images'), true);
      expect(clean.doses.map((d) => d.text), contains('Ceftriaxone 1 g IV once'));
      final nested = clean.doses.firstWhere((d) => d.text.contains('1 mg/kg'));
      expect(nested.parent, 'Enoxaparin');
      expect(clean.doseTables.length, 1);
      expect(clean.redFlags.any((b) => b.text.contains('NSAIDs')), true);
    });

    test('hand-labelled lines: recall and precision floor', () {
      final m = evalLabels();
      expect(m['doseR']! >= 0.8 && m['doseP']! >= 0.9, true, reason: '$m');
      expect(m['redR']! >= 0.7 && m['redP']! >= 0.85, true, reason: '$m');
    });
  });

  group('perf', () {
    test('cold start on all 28 packs', () async {
      final base = installAllPacks();
      final s = LibraryStore();
      await s.init(base);
      // main-thread lag while everything loads
      var last = DateTime.now().microsecondsSinceEpoch, maxLag = 0;
      final tick = Timer.periodic(const Duration(milliseconds: 5), (_) {
        final n = DateTime.now().microsecondsSinceEpoch;
        if (n - last > maxLag) maxLag = n - last;
        last = n;
      });
      final sw = Stopwatch()..start();
      await s.warmUp();
      print('PERF3 warmUp (28 indexes, 4 isolates): ${sw.elapsedMilliseconds} ms, longest main-thread stall ${maxLag ~/ 1000} ms');
      sw.reset();
      final r = await s.searchEx('osteoarthritis');
      print('PERF3 first search after warm-up: ${sw.elapsedMilliseconds} ms hits=${r.length}');
      final s2 = LibraryStore();
      await s2.init(installAllPacks());
      sw.reset();
      final r2 = await s2.searchEx('osteoarthritis');
      print('PERF3 cold first search (loads indexes itself): ${sw.elapsedMilliseconds} ms hits=${r2.length}');
      expect(sw.elapsedMilliseconds < 3000, true, reason: 'cold first search');
      expect(maxLag < 600000, true, reason: 'main thread was blocked');
      tick.cancel();
      sw.reset();
      final ac = await s.searchEx('acute pancreatitis');
      print('PERF3 second search: ${sw.elapsedMilliseconds} ms hits=${ac.length}');
      for (final q in ['STEMI', 'GCS', 'osteoarthritis']) {
        final h = await s.searchEx(q, concise: true);
        print('SEARCH $q -> ${[for (final x in h.take(6)) '${x.title}@${x.packId}'].join(' | ')}');
      }
      SheetIndex.reset();
      sw.reset();
      final sib = await SheetIndex.siblings(s, 'clinical-essentials', 'Acute pancreatitis — WikEM');
      print('PERF3 siblings first: ${sw.elapsedMilliseconds} ms ${sib.map((e) => e.label)}');
      sw.reset();
      await SheetIndex.siblings(s, 'clinical-essentials', 'Acute pancreatitis — WikEM');
      print('PERF3 siblings second: ${sw.elapsedMilliseconds} ms');
      expect(sw.elapsedMilliseconds < 200, true);
      expect(sib.map((e) => e.label), containsAll(['Tulip']));
      // the condition from a course pack has siblings in other packs too (the combined chip needs them)
      final oa = await SheetIndex.siblings(s, 'orthopedics', 'Osteoarthritis');
      print('PERF3 Osteoarthritis (orthopedics) siblings: ${oa.map((e) => '${e.label}:${e.packId}')}');
      expect(oa.length >= 2, true);
      final pa = await SheetIndex.siblings(s, 'gastroenterology', 'Acute pancreatitis');
      print('PERF3 Acute pancreatitis (gastroenterology) siblings: ${pa.map((e) => '${e.label}:${e.packId}')}');
      expect(pa.length >= 2, true);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('screens', () {
    Future<void> boot(WidgetTester tester, Map<String, dynamic> settings, List<String> ids) async {
      final dir = Directory.systemTemp.createTempSync('l3app').path;
      PathProviderPlatform.instance = _PP(dir);
      Directory('$dir/medlog/cases').createSync(recursive: true);
      File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({'lang': 'en', 'deviceId': 'x', 'libOnline': false, 'lastBackup': DateTime.now().toIso8601String(), ...settings}));
      await tester.runAsync(() => store.init());
      await tester.runAsync(() => library.init(_installSome(ids)));
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SheetIndex.reset();
      clearSheetCache();
    }

    testWidgets('combined chip shows in the quick view of a course article, provenance chips', (tester) async {
      await boot(tester, {}, ['orthopedics', 'clinical-essentials', 'medlineplus']);
      final i = await tester.runAsync(() => library.indexOfTitle('orthopedics', 'Osteoarthritis'));
      await tester.pumpWidget(MaterialApp(home: ArticleScreen(packId: 'orthopedics', index: i!)));
      await _pumpReal(tester);
      await _pumpReal(tester, 20);
      print('DBG combined: ${find.textContaining('Combined').evaluate().length} sibs=${(await tester.runAsync(() => SheetIndex.siblings(library, 'orthopedics', 'Osteoarthritis')))!.map((e) => e.label)}');
      expect(find.text(trp('Combined view ({n} sources)', {'n': 4})), findsOneWidget);
      // a WikEM article has a date: "Source last edited"
      final j = await tester.runAsync(() => library.indexOfTitle('clinical-essentials', 'Acute pancreatitis — WikEM'));
      await tester.pumpWidget(MaterialApp(home: ArticleScreen(key: UniqueKey(), packId: 'clinical-essentials', index: j!)));
      await _pumpReal(tester, 20);
      expect(find.textContaining('Source last edited'), findsOneWidget);
      expect(find.textContaining('Combined view'), findsOneWidget);
    });

    testWidgets('library search: snippet with the words from inside the article, concise toggle', (tester) async {
      await boot(tester, {}, ['clinical-essentials', 'cardiology']);
      await tester.runAsync(() => library.ensureFts());
      expect(library.ftsIndexed, 2);
      await tester.pumpWidget(const MaterialApp(home: LibraryScreen(initialQuery: 'qSOFA')));
      await _pumpReal(tester, 20);
      expect(find.text('Search inside articles'), findsOneWidget);
      expect(find.text('Concise sources first'), findsOneWidget);
      expect(find.textContaining('qSOFA', findRichText: true), findsWidgets);
    });
  });
}
