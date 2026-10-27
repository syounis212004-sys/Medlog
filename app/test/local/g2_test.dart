import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/ai/ai_doc_api.dart';
import 'package:medlog/ai/ai_widgets.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' hide Text;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _PP extends PathProviderPlatform {
  final String dir;
  _PP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

Future<void> _initStore(String lang) async {
  final dir = Directory.systemTemp.createTempSync('g2s').path;
  PathProviderPlatform.instance = _PP(dir);
  Directory('$dir/medlog/cases').createSync(recursive: true);
  File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({'lang': lang, 'deviceId': 'x', 'libOnline': false, 'lastBackup': DateTime.now().toIso8601String()}));
  await store.init();
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

Widget host(Widget child, {double scale = 1.0}) => RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: appLocale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto', textTheme: Typography.material2021().black.apply(fontFamily: 'Roboto', fontFamilyFallback: const ['Naskh'])),
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
        home: Scaffold(body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child))),
      ),
    );

final _wordRx = RegExp(r'[\p{L}\p{N}]+', unicode: true);
Set<String> words(String s) => {for (final m in _wordRx.allMatches(s.toLowerCase())) m.group(0)!};

const ignorable = {'json', 'source', 'sources', 'references', 'reference', 'mnemonic', 'remember', 'step', 'المصدر', 'المصادر', 'المراجع', 'تذكر'};

Set<String> expectedWords(String raw, bool structured) {
  if (!structured) {
    var r = raw.replaceAll(RegExp(r'^\s*(?:[-*]\s+)?(?:\d{1,3}|[\u0660-\u0669]+)[.)]\s', multiLine: true), ' ').replaceAll(RegExp(r'\s\d[.)]\s'), ' ').replaceAll(RegExp(r'\[[ xX]\]'), ' ');
    return words(r)..removeAll(ignorable);
  }
  final out = <String>{};
  for (final m in RegExp(r'"((?:[^"\\]|\\.)*)"(\s*:)?').allMatches(raw)) {
    if (m.group(2) != null) continue;
    final v = m.group(1)!;
    if (kAiDocKinds.contains(v)) continue;
    out.addAll(words(v.replaceAll(RegExp(r'\\[nrt"]'), ' ')));
  }
  // wrapper json {"answer": "..."} contains literal \n
  return out..removeAll(ignorable);
}

String renderedText(WidgetTester t) {
  final b = StringBuffer();
  for (final w in t.widgetList<RichText>(find.byType(RichText))) {
    b.writeln(w.text.toPlainText(includePlaceholders: false));
  }
  return b.toString();
}

void main() {
  final dir = Directory('/tmp/eval/ai_corpus');
  final expect_ = jsonDecode(File('${dir.path}/expect.json').readAsStringSync()) as Map<String, dynamic>;
  final names = expect_.keys.toList()..sort();

  setUpAll(() async {
    const rb = '/opt/flutter/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
    await loadFont('Naskh', ['/opt/flutter/engine/src/flutter/txt/third_party/fonts/NotoNaskhArabic-Regular.ttf']);
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('corpus parse', () {
    var pass = 0;
    final fails = <String>[];
    for (final n in names) {
      test(n, () {
        final raw = File('${dir.path}/$n.txt').readAsStringSync();
        final e = expect_[n] as Map<String, dynamic>;
        final problems = <String>[];
        late AiDoc d;
        try {
          d = parseAiOutput(raw);
        } catch (ex) {
          fail('threw $ex');
        }
        if (d.raw != raw) problems.add('raw changed');
        final kinds = d.sections.map((s) => s.kind).toSet();
        for (final k in (e['kinds'] as List)) {
          if (!kinds.contains(k) && !(k == 'uncertainties')) problems.add('missing kind $k (got $kinds)');
        }
        if (e['table'] == true && !d.sections.any((s) => s.allBlocks.any((b) => b.type == 't' && b.rows.length >= 2))) problems.add('no table');
        if (e['cites'] == true && d.citations.isEmpty && !d.sections.any((s) => s.cites.isNotEmpty)) problems.add('no citations');
        if (e['structured'] == true && !d.structured) problems.add('not structured');
        if (e['steps'] == true && !d.sections.any((s) => s.allBlocks.where((b) => b.type == 'n').length >= 2)) problems.add('no steps');
        final plain = aiDocToPlain(d);
        final md = aiDocToMarkdown(d);
        if (plain.contains('**') || plain.contains('##') || RegExp(r'^\s*- ', multiLine: true).hasMatch(plain)) problems.add('markers in plain');
        if (md.trim().isEmpty) problems.add('empty md');
        final have = words(plain);
        final missing = expectedWords(raw, d.structured).difference(have);
        if (missing.isNotEmpty) problems.add('lost words: ${missing.take(8)}');
        // second parse of own markdown must not throw
        parseAiOutput(md);
        if (problems.isEmpty) {
          pass++;
        } else {
          fails.add('$n: ${problems.join(' | ')}');
        }
        expect(problems, isEmpty, reason: n);
      });
    }
    tearDownAll(() {
      final total = names.length;
      File('/tmp/h/g2_corpus_result.txt').writeAsStringSync('pass $pass / $total\n${fails.join('\n')}\n');
    });
  });

  test('fuzz: never throws, stays fast', () {
    final rnd = ['**', '## ', '- ', '1. ', '| a | b |', '|---|---|', '[1]', '(NICE 2024)', 'https://x.org/a', '```', '{"sections":[', '"', '\n', '\n\n', ' ', 'Red flags:', 'x', 'علامات', '*', '_', '`', '#', '\t', 'Mnemonic: ABC', '}', ']', ','];
    var seed = 7;
    int next() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    final sw = Stopwatch()..start();
    for (var i = 0; i < 400; i++) {
      final b = StringBuffer();
      for (var k = 0; k < 5 + next() % 60; k++) {
        b.write(rnd[next() % rnd.length]);
        if (next() % 3 == 0) b.write('word${next() % 9} ');
      }
      final d = parseAiOutput(b.toString());
      aiDocToMarkdown(d);
      aiDocToPlain(d);
    }
    final wall = List.generate(3000, (i) => 'Sentence $i about drug ${i * 3} mg - item. ').join();
    parseAiOutput(wall);
    parseAiOutput('{"sections":[' + List.generate(2000, (i) => '{"kind":"note","text":"t$i"},').join());
    expect(sw.elapsedMilliseconds < 15000, true, reason: '${sw.elapsedMilliseconds} ms');
  });

  test('schema + prompts', () {
    expect(kAiDocSchemaPrompt.contains('red_flags'), true);
    expect(kAiDocSchemaPromptMixed.contains('English'), true);
    final j = jsonEncode(aiDocJsonSchema);
    expect(j.contains('pattern'), false);
    expect(j.contains(r'$ref'), false);
    expect(jsonEncode(aiDocJsonSchemaStrict()).contains('additionalProperties'), true);
    expect(parseAiOutput('').sections, isEmpty);
    expect(() => parseAiOutput('{{{[[[ ``` | | |\n#\n**'), returnsNormally);
    final d = parseAiOutput('', json: {'sections': [{'kind': 'red_flags', 'title': 'X', 'bullets': ['a']}]});
    expect(d.sections.first.kind, 'red_flags');
  });

  final shots = ['en01_dka_md', 'en11_stable_unstable', 'en16_guidelines_table', 'en03_pipe_table', 'en05_fenced_json', 'en12_mnemonic', 'en40_many_sections', 'en09_wall', 'ar01_md', 'ar04_json', 'mx01_mixed', 'ar03_table', 'en32_json_table_object', 'en15_bold_headings'];

  for (final lang in ['en', 'ar']) {
    group('widgets $lang', () {
      setUpAll(() => _initStore(lang));
      for (final cfg in [
        [412.0, 892.0, 1.0],
        [360.0, 640.0, 1.3],
      ]) {
        testWidgets('all corpus ${cfg[0].toInt()}x${cfg[1].toInt()} x${cfg[2]}', (tester) async {
          tester.view.physicalSize = Size(cfg[0], cfg[1]);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          for (final n in names) {
            final raw = File('${dir.path}/$n.txt').readAsStringSync();
            final doc = parseAiOutput(raw);
            await tester.pumpWidget(host(AiDocView(doc: doc), scale: cfg[2]));
            await tester.pump(const Duration(milliseconds: 50));
            final err = tester.takeException();
            expect(err, isNull, reason: '$n $lang ${cfg[0]}: $err');
            final txt = renderedText(tester);
            expect(txt.contains('**'), false, reason: '$n shows **');
            expect(txt.contains('##'), false, reason: '$n shows ##');
            expect(RegExp(r'^\s*- ', multiLine: true).hasMatch(txt), false, reason: '$n shows "- "');
            if (shots.contains(n) && cfg[0] == 412.0 || shots.take(5).contains(n) && cfg[0] == 360.0) {
              await shot(tester, 'g2_${lang}_${n}_${cfg[0].toInt()}');
            }
          }
        });
      }
      testWidgets('tall screenshots + interactions', (tester) async {
        tester.view.physicalSize = const Size(412, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        for (final n in ['en01_dka_md', 'en11_stable_unstable', 'en16_guidelines_table', 'ar01_md', 'mx01_mixed', 'en40_many_sections', 'en17_citation_styles', 'en09_wall']) {
          final doc = parseAiOutput(File('${dir.path}/$n.txt').readAsStringSync());
          AiCite? got;
          await tester.pumpWidget(host(AiDocView(doc: doc, onCite: (c) => got = c)));
          await tester.pump(const Duration(milliseconds: 50));
          await shot(tester, 'g2_tall_${lang}_$n');
          if (n == 'en01_dka_md' && lang == 'en') {
            // tap the citation chip "1" and the raw toggle
            final chip = find.text('1').first;
            await tester.tap(chip);
            await tester.pump();
            expect(got, isNotNull);
            await tester.tap(find.text('Raw text'));
            await tester.pump();
            expect(find.textContaining('# Diabetic'), findsWidgets);
          }
        }
      });
    });
  }

  testWidgets('AiOutputCard renders through the engine', (tester) async {
    await tester.runAsync(() => _initStore('en'));
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const AiOutputCard(text: '## Overview\n**DKA** is serious [1].\n\n## Red flags\n- GCS < 15\n', sources: ['NICE NG17 2022'])));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    final t = renderedText(tester);
    expect(t.contains('**'), false);
    expect(t.contains('##'), false);
    await shot(tester, 'g2_outputcard');
  });
}
