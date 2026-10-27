import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart';
import 'package:medlog/lib_sheet.dart';
import 'package:medlog/lib_text.dart';
import 'package:medlog/lib_user.dart';
import 'package:medlog/library.dart';
import 'package:medlog/main.dart';
import 'package:medlog/screens_article.dart';
import 'package:medlog/screens_library.dart';
import 'package:medlog/sheet_widgets.dart';
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
    File('test_output/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> realWait(WidgetTester tester, [int ms = 300]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump(const Duration(milliseconds: 100));
}

// ---- real pack reader (same format as /tmp/proto/load.py)
class RealPack {
  final Map idx;
  final List<int> bin;
  RealPack(this.idx, this.bin);
  List<String> get titles => (idx['t'] as List).cast<String>();
  LibArticle art(int i) {
    final o = (idx['o'] as List)[i] as int, n = (idx['n'] as List)[i] as int;
    return LibArticle.fromJson(jsonDecode(utf8.decode(gzip.decode(bin.sublist(o, o + n)))) as Map<String, dynamic>);
  }
}

RealPack realPack(String id) => RealPack(jsonDecode(utf8.decode(gzip.decode(File('../library/$id.idx').readAsBytesSync()))) as Map, File('../library/$id.bin').readAsBytesSync());

List<String> toks(String s) => [for (final m in RegExp(r'[a-z0-9]+').allMatches(s.toLowerCase())) m.group(0)!]..sort();

Iterable<SBlock> allBlocks(Sheet sh) sync* {
  for (final p in sh.lead) {
    yield* p.blocks;
  }
  for (final s in sh.sections) {
    for (final p in s.parts) {
      yield* p.blocks;
    }
  }
}

LibArticle syn(String title, Map<String, String> secs, {String lead = ''}) => LibArticle(title, '', [LibSection('', lead), for (final e in secs.entries) LibSection(e.key, e.value)]);

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

  group('canonical sections', () {
    test('headings of all sources map to the fixed order', () {
      expect(canonOf(''), Canon.background);
      for (final h in ['Background', 'General', 'Overview', 'Definition', 'Key points']) {
        expect(canonOf(h), Canon.background, reason: h);
      }
      for (final h in ['Clinical Features', 'Clinical features', 'Symptoms', 'Signs and symptoms', 'Presentation']) {
        expect(canonOf(h), Canon.symptoms, reason: h);
      }
      for (final h in ['Differential Diagnosis', 'Differential diagnosis']) {
        expect(canonOf(h), Canon.differential, reason: h);
      }
      for (final h in ['Evaluation', 'Diagnosis', 'Work-up', 'Testing and diagnosis', 'Diagnostics', 'Recommended tests']) {
        expect(canonOf(h), Canon.diagnosis, reason: h);
      }
      for (final h in ['Management', 'Treatment', 'Treatment options', 'Treatment and Prognosis', 'Patient management', 'Surgery']) {
        expect(canonOf(h), Canon.treatment, reason: h);
      }
      expect(canonOf('Disposition'), Canon.disposition);
      expect(canonOf('Follow-Up'), Canon.disposition);
      expect(canonOf('Complications'), Canon.complications);
      expect(canonOf('Prognosis'), Canon.prognosis);
      for (final h in ['Causes and risk factors', 'Cause', 'Risk factors', 'Risk Factors', 'Causes']) {
        expect(canonOf(h), Canon.causes, reason: h);
      }
      expect(canonOf('Epidemiology'), Canon.epidemiology);
      expect(canonOf('Prevention'), Canon.prevention);
      expect(canonOf('Pathophysiology'), Canon.pathophys);
      expect(canonOf('Adverse Reactions'), Canon.other);
      expect(canonOf('Etymology'), Canon.history);
      // order: background first ... prevention, then other, history last
      expect(kCanonOrder.indexOf(Canon.symptoms) < kCanonOrder.indexOf(Canon.diagnosis), true);
      expect(kCanonOrder.indexOf(Canon.diagnosis) < kCanonOrder.indexOf(Canon.treatment), true);
      expect(kCanonOrder.indexOf(Canon.treatment) < kCanonOrder.indexOf(Canon.disposition), true);
      expect(kCanonOrder.last, Canon.history);
      // old behaviour of secKind untouched
      expect(secKind('Signs and symptoms'), SecKind.symptoms);
      expect(secKind('Complications'), SecKind.prevention);
    });

    test('sheet sorts sections canonically and keeps every word', () {
      final a = syn('Test disease', {
        'Prognosis': 'Prognosis is good.',
        'Management': '• Rest\n• Fluids',
        'Evaluation': '• CBC\n• Lipase',
        'Clinical Features': '• Pain\n• Fever',
        'Disposition': '▸ Discharge\n• Mild case',
      }, lead: 'Test disease is a condition of testing. It is rare.');
      final sh = buildSheet([SheetSrc('WikEM', a)]);
      expect(sh.definition, 'Test disease is a condition of testing.');
      expect([for (final s in sh.sections) s.canon], [Canon.symptoms, Canon.diagnosis, Canon.treatment, Canon.disposition, Canon.prognosis]);
      expect([for (final s in sh.sections) s.title], ['Clinical Features', 'Evaluation', 'Management', 'Disposition', 'Prognosis']);
    });

    test('parseBlocks reads bullets, nested bullets and sub-headings', () {
      final b = parseBlocks('▸ Medical\n• Lipase\n  – Amylase is less sensitive\n    – deeper\nPlain paragraph.\n• Next');
      expect([for (final x in b) '${x.kind.name}${x.level}'], ['sub0', 'bullet0', 'bullet1', 'bullet2', 'para0', 'bullet0']);
    });
  });

  group('callouts on synthetic text', () {
    test('red flags: conservative', () {
      final a = syn('Test disease', {
        'Management': [
          '• Do NOT delay antibiotics for cultures',
          '• Immediately call the ICU team',
          '• Oral steroids do not reduce duration of symptoms in these patients',
          '• Consider tPA if not contraindicated',
          '• Shock',
          '• Patients do not usually need admission',
        ].join('\n'),
        'Differential Diagnosis': '• Perforation with life-threatening shock and urgent surgery needs',
        'Prognosis': 'Mortality is urgent and life-threatening in many cases.',
      });
      final sh = buildSheet([SheetSrc('WikEM', a)]);
      final flagged = [for (final b in allBlocks(sh)) if (b.tag == SheetTag.redFlag) b.text];
      expect(flagged, ['Do NOT delay antibiotics for cultures', 'Immediately call the ICU team']);
      expect(sh.redFlags.length, 2);
    });

    test('red flags: at most 4 per article, dose card shows the whole line, mnemonic, high-yield', () {
      final lines = [for (var i = 0; i < 8; i++) '• Emergent surgical consult for case number $i of this problem'];
      final a = syn('Test disease', {
        'Management': [
          ...lines,
          '• Epinephrine 0.3-0.5 mg IM in the thigh for anaphylaxis',
          '• Lab value: calcium 8.5 mg/dL is normal here',
          '• NSAIDs, RICE (rest, ice, compression, elevation)',
          '• Admit patients with diuresis of >250 mL/h for >2 hours',
        ].join('\n'),
        'Clinical Features': '• Pain is the most common symptom\n• Cullen sign is a hallmark of hemorrhage',
      });
      final sh = buildSheet([SheetSrc('x', a)]);
      expect(sh.redFlags.length, 4);
      final dose = [for (final b in allBlocks(sh)) if (b.tag == SheetTag.dose) b.text];
      expect(dose, ['Epinephrine 0.3-0.5 mg IM in the thigh for anaphylaxis']);
      expect([for (final b in allBlocks(sh)) if (b.tag == SheetTag.mnemonic) b.text], ['NSAIDs, RICE (rest, ice, compression, elevation)']);
      expect([for (final b in allBlocks(sh)) if (b.tag == SheetTag.highYield) b.text].length, 2);
      expect(isLetterExpansion('CAVE: Cardiac, Aortic, Valve, Embolic'), true);
      expect(isLetterExpansion('The AJCC has designated staging by TNM (tumor, node, metastasis) classification'), false);
    });

    test('prose: a red-flag sentence becomes its own block, the rest keeps its order', () {
      final a = syn('Test disease', {
        'Treatment': 'Rest helps. Do not delay surgery in unstable patients. Fluids are given. Diet is normal.',
      });
      final sh = buildSheet([SheetSrc('x', a)]);
      final bl = sh.sections.first.parts.first.blocks.toList();
      expect([for (final b in bl) b.text], ['Rest helps.', 'Do not delay surgery in unstable patients.', 'Fluids are given. Diet is normal.']);
      expect(bl[1].tag, SheetTag.redFlag);
    });

    test('doses: drug lines with route / frequency / per-kg are tagged, lab values and trial summaries are not', () {
      final a = syn('Test disease', {
        'Management': [
          '• Ceftriaxone 1 g IV once daily for 7 days',
          '• Insulin 0.1 units/kg/hr IV drip',
          '• Dopamine 5mcg/kg/min; titrate by 5mcg/kg/min q10min',
          '• Potassium level 6.5 mEq/L is severe',
          '• A phase III trial gave 800 mg imatinib daily to 746 patients',
          '• Avoid ketorolac in renal failure',
          '• Do not exhibit warning signs',
        ].join('\n'),
      });
      final sh = buildSheet([SheetSrc('x', a)]);
      expect([for (final b in allBlocks(sh)) if (b.tag == SheetTag.dose) b.text], ['Ceftriaxone 1 g IV once daily for 7 days', 'Insulin 0.1 units/kg/hr IV drip', 'Dopamine 5mcg/kg/min; titrate by 5mcg/kg/min q10min']);
      expect(sh.doses.length, 3);
      expect([for (final b in allBlocks(sh)) if (b.tag == SheetTag.redFlag) b.text], ['Avoid ketorolac in renal failure']);
    });

    test('decision cards only when confident', () {
      final good = syn('Test disease', {
        'Management': '• Mild: avoid triggers\n• Moderate: drops\n  – repeat daily\n• Severe: refer to ophthalmology',
      });
      var sh = buildSheet([SheetSrc('x', good)]);
      final d = sh.sections.first.parts.first.items.whereType<SDecision>().single;
      expect([for (final g in d.groups) g.tone], [Tone.green, Tone.amber, Tone.red]);
      expect(d.groups[1].blocks.length, 2); // label + its nested bullet
      expect(d.groups[0].rest, 'avoid triggers');
      // one label only, a chain "If fails ... If fails", labels in other sections: no card
      for (final txt in ['• Mild: rest\n• Other thing\n• More text', '• If fails: x\n• If fails: y', '• Mild: rest\n• Something else\n• Severe: refer', '• Rest\n• Fluids']) {
        sh = buildSheet([SheetSrc('x', syn('T', {'Management': txt}))]);
        expect(sh.sections.first.parts.first.items.whereType<SDecision>(), isEmpty, reason: txt);
      }
      sh = buildSheet([SheetSrc('x', syn('T', {'Epidemiology': '• Mild: 10%\n• Severe: 2%'}))]);
      expect(sh.sections.first.parts.first.items.whereType<SDecision>(), isEmpty);
    });

    test('numbered steps become a flow only with 3 or more in order', () {
      var sh = buildSheet([SheetSrc('x', syn('T', {'Management': '1. Airway\n2. Breathing\n3. Circulation'}))]);
      expect(sh.sections.first.parts.first.items.whereType<SSteps>().single.steps.length, 3);
      sh = buildSheet([SheetSrc('x', syn('T', {'Management': '1. Airway\n3. Breathing\n4. Circulation'}))]);
      expect(sh.sections.first.parts.first.items.whereType<SSteps>(), isEmpty);
    });
  });

  group('merge', () {
    test('base titles and badges', () {
      expect(baseTitle('Acute pancreatitis — WikEM'), 'Acute pancreatitis');
      expect(baseTitleKey('Acute Pancreatitis — Project Tulip'), 'acute pancreatitis');
      expect(baseTitleKey('Pancreatitis — wikipedia'), 'pancreatitis');
      expect(baseTitleKey('Hepatitis A — CDC'), 'hepatitis a');
      expect(sourceBadge('X — Project Tulip'), 'Tulip');
      expect(sourceBadge('X — National'), 'Source');
      expect(sourceBadge('Pancreatitis', packKind: 'wiki'), 'Wikipedia');
    });

    test('Jaccard dedupe keeps one copy and keeps bullets', () {
      final a = syn('Test disease', {'Management': '• Give intravenous fluids and monitor urine output closely\n• Pain control with opioids'});
      final b = syn('Test disease', {'Treatment': '• Give intravenous fluids and monitor urine output closely.\n• Early enteral feeding is preferred\nNPO is not needed.'});
      final sh = buildSheet([SheetSrc('WikEM', a), SheetSrc('CDC', b)]);
      expect(sh.combined, true);
      expect(sh.sections.length, 1);
      final s = sh.sections.single;
      expect(s.canon, Canon.treatment);
      expect(s.title, 'Treatment');
      expect([for (final p in s.parts) p.src], ['WikEM', 'CDC']);
      expect([for (final x in s.parts[1].blocks) x.text], ['Early enteral feeding is preferred', 'NPO is not needed.']);
      expect(s.parts[1].blocks.first.kind, BKind.bullet);
    });

    test('real pancreatitis pair (Tulip + WikEM) merges with badges, order and no near-duplicates', () {
      final p = realPack('clinical-essentials');
      final ia = p.titles.indexOf('Acute pancreatitis — WikEM');
      final ib = p.titles.indexOf('Acute Pancreatitis — Project Tulip');
      expect(ia >= 0 && ib >= 0, true);
      expect(baseTitleKey(p.titles[ia]), baseTitleKey(p.titles[ib]));
      final w = p.art(ia), t = p.art(ib);
      final sh = buildSheet([SheetSrc('WikEM', w), SheetSrc('Tulip', t)]);
      expect(sh.sources, ['WikEM', 'Tulip']);
      final order = [for (final s in sh.sections) kCanonOrder.indexOf(s.canon)];
      expect(order, [...order]..sort());
      final sy = sh.sections.where((s) => s.canon == Canon.symptoms).single;
      expect(sy.parts.map((x) => x.src).toSet(), {'WikEM', 'Tulip'});
      expect(sy.title, 'Symptoms');
      // every section that has both sources: no later-source unit is a >=0.8 duplicate of an earlier one
      var checked = 0;
      for (final s in sh.sections) {
        final seen = <Set<String>>[];
        for (final part in s.parts) {
          final mine = <Set<String>>[];
          for (final b in part.blocks) {
            if (b.kind == BKind.sub) continue;
            for (final u in b.kind == BKind.para ? sentences(b.text) : [b.text]) {
              final tk = {for (final m in RegExp(r'[a-z0-9]+').allMatches(u.toLowerCase())) m.group(0)!};
              if (tk.length < 4) continue;
              if (part.src != s.parts.first.src) {
                for (final o in seen) {
                  expect(jaccard(tk, o) < 0.8, true, reason: 'dup kept: $u');
                  checked++;
                }
              }
              mine.add(tk);
            }
          }
          seen.addAll(mine);
        }
      }
      expect(checked > 100, true);
      // merged view is shorter than the plain concatenation (duplicates dropped) but never invents words
      final srcTokens = {for (final x in [w, t]) for (final sec in x.sections) ...toks(sec.text)};
      for (final b in allBlocks(sh)) {
        for (final tk in toks(b.text)) {
          expect(srcTokens.contains(tk), true, reason: tk);
        }
      }
    });
  });

  group('real packs', () {
    test('single sheet keeps every word of the article (nothing added, nothing lost)', () {
      var n = 0;
      for (final id in ['clinical-essentials', 'gastroenterology', 'cardiology', 'medlineplus', 'emergency-critical-care']) {
        final p = realPack(id);
        final step = (p.titles.length / 60).ceil();
        for (var i = 0; i < p.titles.length; i += step) {
          final a = p.art(i);
          final sh = buildSheet([SheetSrc('x', a)]);
          final got = <String>[...toks(sh.definition), for (final b in allBlocks(sh)) ...toks(b.text)]..sort();
          final want = <String>[for (final s in a.sections) ...toks(s.text)]..sort();
          expect(got, want, reason: '$id ${a.title}');
          n++;
        }
      }
      print('word-for-word check on $n articles');
    });

    test('red flag precision on 40 real articles (review list written to test_output/flags.txt)', () {
      final p = realPack('clinical-essentials');
      final out = StringBuffer();
      var articles = 0, flags = 0, withFlags = 0;
      final bad = <String>[];
      for (var i = 7; i < p.titles.length && articles < 60; i += 24) {
        final a = p.art(i);
        final sh = buildSheet([SheetSrc('x', a)]);
        articles++;
        expect(sh.redFlags.length <= 4, true);
        if (sh.redFlags.isNotEmpty) withFlags++;
        out.writeln('## ${a.title}');
        for (final s in sh.sections) {
          for (final part in s.parts) {
            for (final b in part.blocks) {
              if (b.tag != SheetTag.redFlag) continue;
              flags++;
              out.writeln('  [${s.canon.name}] ${b.text}');
              expect({Canon.symptoms, Canon.diagnosis, Canon.treatment, Canon.complications, Canon.disposition}.contains(s.canon), true);
              expect(b.text.length <= 220, true);
              // known false-positive shapes: negated statements, list intros, differential lists, section pointers
              if (RegExp(r'(patients|people|these|they)\s+(?:\w+\s+){0,3}do not|\bnot contraindicated|:\s*$|\bsee\b.*\bsection\b|distinguish', caseSensitive: false).hasMatch(b.text)) bad.add('${a.title}: ${b.text}');
            }
          }
        }
      }
      File('test_output/flags.txt').writeAsStringSync(out.toString());
      print('articles $articles, with red flags $withFlags, flagged lines $flags, shape-checked false positives ${bad.length}');
      expect(articles >= 40, true);
      expect(bad, isEmpty);
    });

    test('decision cards on all 1543 essentials: every card has 2+ unique condition labels', () {
      final p = realPack('clinical-essentials');
      var cards = 0;
      for (var i = 0; i < p.titles.length; i += 3) {
        final sh = buildSheet([SheetSrc('x', p.art(i))]);
        for (final s in sh.sections) {
          for (final part in s.parts) {
            for (final it in part.items.whereType<SDecision>()) {
              cards++;
              expect(s.canon, Canon.treatment);
              expect(it.groups.length >= 2, true);
              expect(it.groups.map((g) => g.label.toLowerCase()).toSet().length, it.groups.length);
              for (final g in it.groups) {
                expect(decisionLabel(g.blocks.first.text), isNotNull);
              }
            }
          }
        }
      }
      print('decision cards in a third of essentials: $cards');
    });

    test('speed: a sheet of a long article builds in well under 100 ms', () {
      final p = realPack('gastroenterology');
      var longest = 0, li = 0;
      for (var i = 0; i < p.titles.length; i += 7) {
        final a = p.art(i);
        final n = a.sections.fold<int>(0, (x, s) => x + s.text.length);
        if (n > longest) {
          longest = n;
          li = i;
        }
      }
      final a = p.art(li);
      final sw = Stopwatch()..start();
      buildSheet([SheetSrc('x', a)]);
      sw.stop();
      print('longest sampled article ${a.title}: $longest chars, sheet in ${sw.elapsedMilliseconds} ms');
      expect(sw.elapsedMilliseconds < 400, true);
    });
  });

  test('sibling index over all shipped packs: built once, cached, finds the pancreatitis pair', () async {
    final base = Directory.systemTemp.createTempSync('medlib');
    final ld = Directory('${base.path}/library')..createSync(recursive: true);
    final metas = <Map>[];
    for (final f in Directory('../library').listSync().whereType<File>().where((f) => f.path.endsWith('.idx') && !f.path.endsWith('-images.idx'))) {
      final id = f.uri.pathSegments.last.replaceAll('.idx', '');
      File('${ld.path}/$id.idx').writeAsBytesSync(f.readAsBytesSync());
      File('${ld.path}/$id.bin').writeAsBytesSync(File('../library/$id.bin').readAsBytesSync());
      final meta = Map<String, dynamic>.from((jsonDecode(utf8.decode(gzip.decode(f.readAsBytesSync()))) as Map)['meta'] as Map);
      metas.add(meta);
    }
    File('${ld.path}/installed.json').writeAsStringSync(jsonEncode(metas));
    final lib = LibraryStore();
    await lib.init(base);
    SheetIndex.reset();
    final sw = Stopwatch()..start();
    final sib = await SheetIndex.siblings(lib, 'clinical-essentials', 'Acute pancreatitis — WikEM');
    final first = sw.elapsedMilliseconds;
    sw.reset();
    final sib2 = await SheetIndex.siblings(lib, 'clinical-essentials', 'Acute pancreatitis — WikEM');
    print('packs ${lib.textPacks.length}: first lookup (builds the map) $first ms, second ${sw.elapsedMilliseconds} ms; siblings ${sib.map((e) => '${e.label}:${e.title}').toList()}');
    expect(sib.map((e) => e.label), ['Tulip', 'Wikipedia']);
    expect(sib2.length, 2);
    expect(sw.elapsedMilliseconds < 50, true);
    // a Wikipedia course article and its Essentials twin, when they share a base title
    var pairs = 0;
    final seenKeys = <String>{};
    for (final p in lib.textPacks) {
      for (final t in (await lib.titlesOf(p.id)).take(400)) {
        final k = baseTitleKey(t);
        if (!seenKeys.add(k)) continue;
        final l = await SheetIndex.siblings(lib, p.id, t);
        if (l.isNotEmpty) pairs++;
      }
    }
    print('titles (first 400 per pack) that have an equally titled article elsewhere: $pairs');
  });

  // -------------------------------------------------------------------------------- widgets
  for (final lang in ['en', 'ar']) {
    testWidgets('study sheet $lang: callouts, combined view, original text, reading list', (tester) async {
      final dir = Directory.systemTemp.createTempSync('medlog').path;
      PathProviderPlatform.instance = FakePP(dir);
      Directory('$dir/medlog/cases').createSync(recursive: true);
      Directory('$dir/medlog/images').createSync(recursive: true);
      File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({
        'lang': lang,
        'author': 'Dr. M',
        'palette': 'clinic',
        'deviceId': 'x',
        'lastBackup': DateTime.now().toIso8601String(),
        'libOnline': false,
        'libQuick': false,
        'libSheetStyle': 2,
        if (lang == 'ar') 'themeMode': 'dark',
      }));
      await tester.runAsync(() => store.init());
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 892);
      addTearDown(tester.view.reset);
      SheetIndex.reset();
      clearSheetCache();
      await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
      await tester.runAsync(() async {
        final base = Directory.systemTemp.createTempSync('medlib');
        await library.init(base);
        final rp = realPack('clinical-essentials');
        LibArticle pick(String t) => rp.art(rp.titles.indexOf(t));
        await library.writePack(
          const PackMeta(id: 'clinical-essentials', title: 'Clinical Essentials', kind: 'user', source: 'Various', license: 'Various', date: '2026-10-01'),
          [pick('Acute pancreatitis — WikEM'), pick('Acute Pancreatitis — Project Tulip'), pick('Allergic conjunctivitis — WikEM'), pick('Anaphylaxis — WikEM')],
        );
        await library.writePack(
          const PackMeta(id: 'gastroenterology', title: 'Gastroenterology', kind: 'wiki', source: 'Wikipedia', license: 'CC BY-SA 4.0', date: '2026-10-01'),
          [
            LibArticle('Acute pancreatitis', 'https://en.wikipedia.org/wiki/Acute_pancreatitis', [
              const LibSection('', 'Acute pancreatitis is sudden inflammation of the pancreas. Gallstones and alcohol are the most common causes. Severe cases can lead to organ failure.'),
              const LibSection('Signs and symptoms', 'The most common symptom is severe upper abdominal pain that radiates to the back. Nausea and vomiting are frequent. Do not delay fluids in hypotensive patients.'),
              const LibSection('Treatment', 'Treatment is supportive with intravenous fluids and pain control. Early oral feeding is preferred when tolerated.'),
            ]),
          ],
        );
      });
      Future<void> open(String packId, String title) async {
        final idx = await tester.runAsync(() => library.indexOfTitle(packId, title));
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push(MaterialPageRoute(builder: (_) => ArticleScreen(packId: packId, index: idx!)));
        await settle(tester, 600);
        for (var k = 0; k < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; k++) {
          await realWait(tester, 120);
        }
        for (var k = 0; k < 15; k++) {
          await realWait(tester, 150);
        }
        await settle(tester, 700);
      }

      String t(String en, String ar) => tr(en);
      Future<void> toTop() async {
        tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
        await settle(tester, 200);
      }

      Future<void> expandAll() async {
        await toTop();
        await tester.scrollUntilVisible(find.text(t('Expand all', 'توسيع الكل')), 300, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text(t('Expand all', 'توسيع الكل')));
      }

      Future<void> jump(IconData icon) async {
        await toTop();
        final f = find.descendant(of: find.byType(Card), matching: find.byIcon(icon));
        for (var k = 0; k < 120 && f.hitTestable().evaluate().isEmpty; k++) {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
        await settle(tester, 500);
      }

      final chip3 = trp('Combined view ({n} sources)', {'n': 3});
      await open('clinical-essentials', 'Acute pancreatitis — WikEM');
      // combined view is on by default: three sources, badges and chip
      expect(find.text(chip3), findsOneWidget);
      expect(find.text('WikEM'), findsWidgets);
      expect(find.text('Tulip'), findsWidgets);
      expect(find.text('Wikipedia'), findsWidgets);
      expect(find.text(t('Red flags', 'علامات الخطر')), findsOneWidget);
      await shot(tester, 'SHEET_${lang}_top');
      // expand everything and look at the sections
      await expandAll();
      await settle(tester, 700);
      await jump(Icons.sick_outlined);
      await shot(tester, 'SHEET_${lang}_combined_symptoms');
      await jump(Icons.medication_outlined);
      await shot(tester, 'SHEET_${lang}_combined_treatment');
      // single source: chip off
      await toTop();
      await tester.ensureVisible(find.text(chip3));
      await settle(tester, 300);
      await tester.tap(find.text(chip3));
      await settle(tester, 600);
      expect(find.text('Tulip'), findsNothing);
      // original text: untouched, no callout cards
      await toTop();
      await tester.tap(find.text(t('Original text', 'النص الأصلي')));
      await settle(tester, 600);
      expect(find.text(t('Red flag', 'علامة خطر')), findsNothing);
      expect(find.text(t('Red flags', 'علامات الخطر')), findsNothing);
      await tester.scrollUntilVisible(find.text(t('Expand all', 'توسيع الكل')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(t('Expand all', 'توسيع الكل')));
      await settle(tester, 700);
      await shot(tester, 'SHEET_${lang}_original');
      await toTop();
      await toTop();
      await tester.tap(find.text(t('Study sheet', 'ورقة المذاكرة')));
      await settle(tester, 600);
      await toTop();
      // reading list bookmark
      expect(isInReadingList('clinical-essentials', 'Acute pancreatitis — WikEM'), false);
      await tester.tap(find.byIcon(Icons.bookmark_border));
      for (var k = 0; k < 6; k++) {
        await realWait(tester, 200);
      }
      await settle(tester, 500);
      expect(isInReadingList('clinical-essentials', 'Acute pancreatitis — WikEM'), true);
      await settle(tester, 300);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester, 600);
      // decision cards (Mild / Moderate / Severe)
      await open('clinical-essentials', 'Allergic conjunctivitis — WikEM');
      await expandAll();
      await settle(tester, 700);
      await jump(Icons.medication_outlined);
      expect(find.text('Moderate'), findsWidgets);
      await shot(tester, 'SHEET_${lang}_decision');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester, 600);
      // a single article: sheet with callouts
      await open('clinical-essentials', 'Anaphylaxis — WikEM');
      await expandAll();
      await settle(tester, 700);
      await jump(Icons.medication_outlined);
      await shot(tester, 'SHEET_${lang}_callouts');
    });
  }

  testWidgets('library settings: sheet style, bolder text, combined view', (tester) async {
    final dir = Directory.systemTemp.createTempSync('medlog').path;
    PathProviderPlatform.instance = FakePP(dir);
    Directory('$dir/medlog/cases').createSync(recursive: true);
    Directory('$dir/medlog/images').createSync(recursive: true);
    File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({'lang': 'en', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String()}));
    await tester.runAsync(() => store.init());
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async => library.init(Directory.systemTemp.createTempSync('medlib')));
    expect(store.libSheetStyle, 1);
    expect(store.libBold, false);
    expect(store.libCombined, true);
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MaterialApp(home: LibrarySettingsScreen())));
    await settle(tester, 800);
    await tester.scrollUntilVisible(find.text('Larger and bolder text'), 200, scrollable: find.byType(Scrollable).first);
    await shot(tester, 'SHEET_en_settings');
    await tester.tap(find.text('Rich'));
    await settle(tester, 300);
    expect(store.libSheetStyle, 2);
    await tester.tap(find.text('Larger and bolder text'));
    await settle(tester, 300);
    expect(store.libBold, true);
    await tester.tap(find.text('Combined view of several sources'));
    await settle(tester, 300);
    expect(store.libCombined, false);
  });
}
