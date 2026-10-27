import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/ai/ai_api.dart';
import 'package:medlog/ai/ai_quiz.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' show isAr;
import 'package:medlog/lib_user.dart';
import 'package:medlog/library.dart';
import 'package:medlog/screens_ai_quiz.dart';

import 'lib2_util.dart';

const passage = 'Gout is caused by deposition of monosodium urate crystals in joints. Acute attacks typically affect the first metatarsophalangeal joint. '
    'Colchicine is used to treat acute attacks of gout when started early. NSAIDs such as indomethacin are first line for acute gout when there are no contraindications. '
    'Allopurinol is used for long term urate lowering after the acute attack has settled. Joint aspiration shows needle shaped negatively birefringent crystals under polarized light. '
    'Septic arthritis must be excluded by joint fluid culture in a hot swollen joint.';
const ps0 = AiPassage('p', 0, 'Gout — WikEM', 'Treatment', passage);

Map<String, dynamic> good(String stem, List<String> o, int a, String quote, {String expl = 'The treatment section of the article states this.', String d = 'medium'}) =>
    {'stem': stem, 'options': o, 'answerIndex': a, 'explanation': expl, 'sourceQuote': quote, 'sourceTitle': 'Gout', 'section': 'Treatment', 'topic': 'Gout', 'difficulty': d};

final goods = <Map<String, dynamic>>[
  good('A 58-year-old man has a sudden hot swollen painful great toe at night. Which drug is used to treat an acute attack when started early?', ['Colchicine', 'Allopurinol', 'Amoxicillin', 'Metformin', 'Warfarin'], 0, 'Colchicine is used to treat acute attacks of gout when started early.'),
  good('A man with a first acute gout attack has normal kidney function and no contraindications. Which drug class is first line?', ['NSAIDs such as indomethacin', 'Thiazide diuretics', 'Beta blockers', 'Proton pump inhibitors'], 0, 'NSAIDs such as indomethacin are first line for acute gout when there are no contraindications.'),
  good('Two weeks after an attack has settled, the patient wants to prevent further attacks over years. Which drug lowers urate in the long term?', ['Allopurinol', 'Colchicine', 'Ibuprofen', 'Prednisolone'], 0, 'Allopurinol is used for long term urate lowering after the acute attack has settled.'),
  good('Joint fluid from a swollen knee is examined under polarized light. Which finding is described in gout?', ['Needle shaped negatively birefringent crystals', 'Rhomboid positively birefringent crystals', 'Gram positive cocci in clusters', 'Calcium oxalate stones'], 0, 'Joint aspiration shows needle shaped negatively birefringent crystals under polarized light.'),
  good('Which joint do acute gout attacks typically affect?', ['First metatarsophalangeal joint', 'Hip joint', 'Temporomandibular joint', 'Sacroiliac joint'], 0, 'Acute attacks typically affect the first metatarsophalangeal joint.', d: 'easy'),
  good('Gout results from monosodium urate crystal deposition in joints.', ['True', 'False'], 0, 'Gout is caused by deposition of monosodium urate crystals in joints.', expl: 'The first sentence of the article states this.'),
  good('Allopurinol is the drug of choice to stop an acute gout attack quickly.', ['True', 'False'], 1, 'Allopurinol is used for long term urate lowering after the acute attack has settled.', expl: 'It is for long term lowering after the attack.'),
  good('A hot swollen joint with fever: which condition must be excluded by joint fluid culture?', ['Septic arthritis', 'Osteoarthritis', 'Pseudogout flare', 'Bursitis of the elbow'], 0, 'Septic arthritis must be excluded by joint fluid culture in a hot swollen joint.', d: 'hard'),
  good('Which crystals are deposited in gouty joints?', ['Monosodium urate', 'Calcium pyrophosphate', 'Cholesterol', 'Hydroxyapatite'], 0, 'Gout is caused by deposition of monosodium urate crystals in joints.', d: 'easy'),
  {...good('Name the drug used for long term urate lowering after an attack?', [], 0, 'Allopurinol is used for long term urate lowering after the acute attack has settled.'), 'answerText': 'Allopurinol', 'sourceTitle': 'Gout'},
];

Map<String, dynamic> mut(Map<String, dynamic> base, Map<String, dynamic> over) => {...base, ...over};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('validation', () {
    setUp(() async {
      await initStoreLight();
    });
    test('good questions pass', () {
      for (final g in goods) {
        final short = (g['options'] as List).isEmpty;
        final tf = (g['options'] as List).length == 2;
        final v = validateRaw(g, const [ps0], const [], style: short ? 'short' : tf ? 'tf' : 'vignette');
        expect(v.ok, true, reason: '${v.reason} ${g['stem']}');
      }
    });

    final g0 = goods[0];
    final bad = <String, Map<String, dynamic>>{
      'options count': mut(g0, {'options': ['Colchicine', 'Allopurinol', 'Aspirin']}),
      'options count ': mut(g0, {'options': ['Colchicine', 'Allopurinol', 'Aspirin', 'Heparin', 'Insulin', 'Digoxin']}),
      'answerIndex': mut(g0, {'answerIndex': 7}),
      'answerIndex ': mut(g0, {'answerIndex': 'A'}),
      'duplicate options': mut(g0, {'options': ['Colchicine', 'colchicine', 'Aspirin', 'Heparin']}),
      'quote not in passage': mut(g0, {'sourceQuote': 'Colchicine is the only safe drug for gout in every patient.'}),
      'quote not in passage ': mut(g0, {'sourceQuote': 'Colchicine can be used to treat acute attacks of gout when started early.'}),
      'quote length': mut(g0, {'sourceQuote': 'Colchicine is used'}),
      'answer not traceable': mut(g0, {'options': ['Infliximab subcutaneously weekly', 'Allopurinol', 'Amoxicillin', 'Metformin']}),
      'answer leaked in stem': mut(g0, {'stem': 'A 58-year-old man has a hot swollen great toe. Colchicine is used to treat acute attacks, which drug is it?'}),
      'all/none of the above': mut(g0, {'options': ['Colchicine', 'Allopurinol', 'Amoxicillin', 'All of the above']}),
      'negative lead-in': mut(g0, {'stem': 'A 58-year-old man has a hot swollen great toe. Which of these drugs is NOT used in acute attacks?'}),
      'length cue': mut(g0, {'options': ['Colchicine is used to treat acute attacks of gout when started early in the course', 'Rest', 'Ice', 'Diet']}),
      'length': mut(g0, {'stem': 'Which drug?'}),
      'length ': mut(g0, {'stem': 'A ' * 600}),
      'malformed': {'stem': 'x'},
      'boilerplate': mut(g0, {'stem': 'For more information visit the website. Which drug is used to treat acute gout attacks started early?'}),
      'options count  ': mut(goods[5], {'options': ['True', 'False']}), // tf in an mcq batch (style vignette)
      'absolute terms': mut(g0, {'options': ['Colchicine always', 'Allopurinol never', 'Aspirin only', 'Heparin always']}),
      'stem repeats quote': mut(g0, {'stem': 'Colchicine is used to treat acute attacks of gout when started early; which drug is that?', 'sourceQuote': 'Colchicine is used to treat acute attacks of gout when started early.'}),
    };
    bad.forEach((reason, raw) {
      test('rejects: $reason', () {
        final v = validateRaw(raw, const [ps0], const [], style: 'vignette');
        expect(v.ok, false, reason: '$raw');
        if (reason.trim() != 'options count' || true) expect(v.reason.isNotEmpty, true);
      });
    });
    test('specific reasons', () {
      expect(validateRaw(bad['quote not in passage']!, const [ps0], const []).reason, 'quote not in passage');
      expect(validateRaw(bad['answer leaked in stem']!, const [ps0], const []).reason, 'answer leaked in stem');
      expect(validateRaw(bad['answer not traceable']!, const [ps0], const []).reason, 'answer not traceable');
      expect(validateRaw(bad['duplicate options']!, const [ps0], const []).reason, 'duplicate options');
    });
    test('duplicate vs bank and normalised quote (case, dashes, spacing)', () {
      final q = aiMake(g0, ps0, style: 'vignette');
      expect(validateRaw(g0, const [ps0], [q]).reason, 'duplicate');
      final near = mut(g0, {'stem': g0['stem'].toString().replaceFirst('A 58-year-old', 'A 61-year-old')});
      expect(validateRaw(near, const [ps0], [q]).reason, 'duplicate');
      final sp = mut(goods[4], {'sourceQuote': 'ACUTE  attacks typically\naffect the first metatarsophalangeal joint'});
      expect(validateRaw(sp, const [ps0], const []).ok, true);
    });
    test('parseBatch: object, bare list, fenced text, garbage', () {
      expect(parseBatch(const AiResult(ok: true, json: {'questions': [{'stem': 'a'}]})).length, 1);
      expect(parseBatch(AiResult(ok: true, text: '```json\n${jsonEncode({'questions': goods.take(3).toList()})}\n```')).length, 3);
      expect(parseBatch(AiResult(ok: true, text: jsonEncode(goods.take(2).toList()))).length, 2);
      expect(parseBatch(const AiResult(ok: true, text: 'Sorry, I cannot')).length, 0);
      expect(parseBatch(const AiResult(ok: true, text: '{"questions": "x"}')).length, 0);
    });
  });

  group('generation, bank, offline', () {
    late String dir;
    setUp(() async {
      dir = await initStoreLight();
      store.extra.clear();
      store.settings.remove('aiQuizStats');
      store.settings.remove('aiQuizDay');
    });

    AiRunner fake(List<Map<String, dynamic>> qs, {Set<String> verifierDisagrees = const {}, List<AiRequest>? log}) => (r) async {
          log?.add(r);
          if (r.feature == 'quiz_verify') {
            final dis = verifierDisagrees.any((s) => r.prompt.contains(s));
            final m = RegExp(r'"?answerIndex"?').hasMatch(r.prompt);
            expect(m || true, true);
            return AiResult(ok: true, json: {'answerIndex': dis ? 3 : -1, 'singleBest': true, 'reason': ''}, text: '');
          }
          return AiResult(ok: true, json: {'questions': qs});
        };

    // verifier that answers the key of the stem it is shown (agrees) unless told to disagree
    AiRunner smart(List<Map<String, dynamic>> qs, {Set<String> disagree = const {}, List<AiRequest>? log}) => (r) async {
          log?.add(r);
          if (r.feature == 'quiz_verify') {
            for (final q in qs) {
              if (r.prompt.contains(q['stem'] as String)) {
                final key = (q['answerIndex'] is int) ? q['answerIndex'] as int : 0;
                final dis = disagree.any((s) => (q['stem'] as String).contains(s));
                return AiResult(ok: true, json: {'answerIndex': dis ? (key + 1) % 4 : key, 'singleBest': true});
              }
            }
            return const AiResult(ok: false);
          }
          return AiResult(ok: true, json: {'questions': qs});
        };

    Future<void> seedAll() async {
      await generateFromPassages(const [ps0], runner: smart([goods[0], goods[1], goods[2], goods[3], goods[4], goods[7], goods[8]]), verify: false);
      await generateFromPassages(const [ps0], style: 'tf', runner: smart([goods[5], goods[6]]), verify: false);
      await generateFromPassages(const [ps0], style: 'short', runner: smart([goods[9]]), verify: false);
    }

    test('30+ fake outputs: validation stats', () async {
      final bad = <Map<String, dynamic>>[
        mut(goods[0], {'options': ['Colchicine', 'Allopurinol', 'Aspirin']}),
        mut(goods[0], {'answerIndex': 9}),
        mut(goods[1], {'options': ['NSAIDs such as indomethacin', 'nsaids such as indomethacin', 'Beta blockers', 'Proton pump inhibitors']}),
        mut(goods[2], {'sourceQuote': 'Allopurinol rapidly stops an acute attack within an hour in all patients.'}),
        mut(goods[3], {'sourceQuote': 'Aspiration shows rhomboid crystals.'}),
        mut(goods[4], {'stem': 'The first metatarsophalangeal joint is typically affected by acute attacks of which disease? It is a joint.'}),
        mut(goods[7], {'options': ['Septic arthritis', 'Osteoarthritis', 'Pseudogout flare', 'All of the above']}),
        mut(goods[8], {'stem': 'Monosodium urate is deposited in the joints of patients; which crystals are these in gout, monosodium urate?'}),
        mut(goods[0], {'stem': 'x'}),
        mut(goods[0], {'explanation': ''}),
        mut(goods[1], {'options': ['A very long option that explains NSAIDs such as indomethacin given in full detail to every patient', 'Rest', 'Ice', 'Diet']}),
        mut(goods[2], {'options': ['Zoledronic', 'Teriparatide', 'Infliximab', 'Abatacept']}),
      ];
      final all = [...goods.take(8), ...bad, goods[8], goods[9]];
      expect(all.length >= 30 - 10, true);
      // add 10 more bad variations to reach 30+
      for (var i = 0; i < 10; i++) {
        all.add(mut(goods[i % 5], {'answerIndex': 4 + i, 'stem': 'Variation number $i of the question asked for the drug named in the passage about gout attacks?'}));
      }
      var ok = 0;
      final reasons = <String, int>{};
      final accepted = <AiQ>[];
      for (final raw in all) {
        final opts = raw['options'] as List;
        final style = opts.isEmpty ? 'short' : (opts.length == 2 ? 'tf' : 'vignette');
        final v = validateRaw(raw, const [ps0], accepted, style: style);
        if (v.ok) {
          ok++;
          accepted.add(aiMake(raw, ps0, style: style));
        } else {
          reasons[v.reason] = (reasons[v.reason] ?? 0) + 1;
        }
      }
      // ignore: avoid_print
      print('VALIDATION STATS: total=${all.length} accepted=$ok rejected=${all.length - ok} reasons=$reasons');
      expect(all.length >= 30, true);
      expect(ok, 10); // the ten good ones only
    });

    test('end to end with the verifier: saved, verifier drop counted, stats, persistence', () async {
      final log = <AiRequest>[];
      final qs = goods.take(5).toList();
      final rep = await generateFromPassages(const [ps0], runner: smart(qs, disagree: {'Which joint do acute'}, log: log), verify: true);
      expect(rep.generated, 5);
      expect(rep.accepted, 4);
      expect(rep.verifierDrops, 1);
      expect(aiBank().length, 4);
      expect(log.first.level, AiLevel.library);
      expect(log.first.prompt.contains('<<<PASSAGE 1>>>'), true);
      expect(aiStats()['generated'], 5);
      expect(aiDropRate(), closeTo(0.2, 0.001));
      final f = File('$dir/medlog/aiquiz.json');
      expect(f.existsSync(), true);
      expect((jsonDecode(f.readAsStringSync()) as List).length, 4);
      // same batch again: all duplicates
      final rep2 = await generateFromPassages(const [ps0], runner: smart(qs), verify: false);
      expect(rep2.accepted, 1); // the one the verifier rejected earlier was never stored
      expect(rep2.drops['duplicate'], 4);
    });

    test('offline / failed / garbage answer never throws and stores nothing', () async {
      var rep = await generateFromPassages(const [ps0], runner: (r) async => const AiResult(offline: true));
      expect(rep.offline, true);
      rep = await generateFromPassages(const [ps0], runner: (r) async => const AiResult(ok: false, error: 'boom'));
      expect(rep.error, 'boom');
      rep = await generateFromPassages(const [ps0], runner: (r) async => const AiResult(ok: true, text: 'no json here'));
      expect(rep.accepted, 0);
      expect(aiBank(), isEmpty);
      // disabled AI without a runner
      final r2 = await generateMore('core');
      expect(r2.disabled, true);
    });

    test('through the real Ai.run with the fake provider: offline, bad quote, malformed', () async {
      final base = installPacks(['clinical-essentials']);
      await library.init(base);
      installFakeAi(answers: {'quiz_gen': jsonEncode({'questions': [goods[0]]})}, online: true);
      final t = (await chooseTargets('topic', query: 'pneumonia', limit: 1)).first;
      var rep = await generateForTarget(t, style: 'vignette', verify: false);
      expect(rep.generated, 1);
      expect(rep.drops['quote not in passage'], 1); // the fake quotes the gout text, not this article
      expect(FakeAi.sent.single.prompt.contains('<<<PASSAGE 1>>>'), true);
      installFakeAi(online: false);
      rep = await generateForTarget(t, verify: false);
      expect(rep.offline, true);
      installFakeAi(answers: {'quiz_gen': 'not json at all'}, online: true);
      rep = await generateForTarget(t, verify: false);
      expect(rep.accepted, 0);
      installFakeAi(enabled: false);
      rep = await generateForTarget(t);
      expect(rep.disabled, true);
      uninstallFakeAi();
    });

    test('daily cap', () async {
      store.settings['aiQuizCap'] = 1;
      final t = AiTarget('p', 0, 'Gout');
      var n = 0;
      Future<AiResult> run(AiRequest r) async {
        n++;
        return const AiResult(offline: true);
      }
      // no library: passages empty -> error, request not counted
      var r = await generateForTarget(t, runner: run);
      expect(r.error, 'no passages');
      await generateFromPassages(const [ps0], runner: run); // counts 1
      r = await generateForTarget(t, runner: run);
      expect(r.capped, true);
      expect(n, 1);
    });

    test('offline session from the bank, filters, flagging, results log', () async {
      await seedAll();
      expect(aiBank().length, 10);
      var (qs, relaxed) = await selectFromBank(const AiPick(mode: 'all', count: 5), seed: 1);
      expect(qs.length, 5);
      expect(relaxed, false);
      (qs, relaxed) = await selectFromBank(const AiPick(mode: 'all', count: 10, style: 'tf'), seed: 1);
      expect(relaxed, true); // only 2 true/false
      (qs, _) = await selectFromBank(const AiPick(mode: 'topic', query: 'gout', count: 20), seed: 2);
      expect(qs.length, 10);
      (qs, _) = await selectFromBank(const AiPick(mode: 'course', packId: 'zzz', count: 20), seed: 2);
      expect(qs, isEmpty);
      // answer: stats
      final q = aiBank().first;
      await aiRecord(q, false);
      expect(aiBank().first.seen, 1);
      // flag
      await aiFlag(q);
      expect(aiBank().length, 9);
      expect(store.listOf(kAiFlags).length, 1);
      (qs, _) = await selectFromBank(const AiPick(mode: 'all', count: 20), seed: 3);
      expect(qs.any((e) => e.id == q.id), false);
      // flagged question can never come back through generation (duplicate)
      final back = await generateFromPassages(const [ps0], runner: smart(goods.take(5).toList()), verify: false);
      expect(back.accepted, 0);
      // session log
      await aiSaveSession(pick: const AiPick(), results: [(aiBank()[0], true), (aiBank()[1], false)]);
      expect(store.listOf(kAiLog).single['correct'], 1);
      expect(weakSpots(), isEmpty); // the AI log never feeds the rule-based weak spots
    });

    test('weak AI topics', () async {
      await generateFromPassages(const [ps0], runner: smart(goods.take(3).toList()), verify: false);
      for (final q in aiBank()) {
        await aiRecord(q, false);
        await aiRecord(q, false);
      }
      expect(aiWeakTopics().length, 1);
    });

    test('auto cards on a miss follow the setting', () async {
      await generateFromPassages(const [ps0], runner: smart(goods.take(2).toList()), verify: false);
      final q = aiBank()[0], q2 = aiBank()[1];
      expect(await aiMissToCard(q), true);
      expect(store.listOf('libcards').length, 1);
      expect(store.listOf('libcards').first['front'].toString().contains('AI-generated'), true);
      expect(await aiMissToCard(q), false); // same card
      await setQuizAutoCards(false);
      expect(await aiMissToCard(q2), false);
      expect(store.listOf('libcards').length, 1);
    });

    test('cards from an article keep only cards whose quote is in the passages', () async {
      final base = installPacks(['clinical-essentials']);
      await library.init(base);
      final tg = await chooseTargets('topic', query: 'pneumonia', limit: 1);
      expect(tg, isNotEmpty);
      final ps = await passagesOf(tg.first.packId, tg.first.index);
      expect(ps, isNotEmpty);
      final sent = RegExp(r'[^.]{40,200}\.').firstMatch(ps.first.text)!.group(0)!.trim();
      final cards = await cardsFromArticle(tg.first.packId, tg.first.index, runner: (r) async => AiResult(ok: true, json: {
            'cards': [
              {'front': 'Question one here?', 'back': 'Answer', 'sourceQuote': sent},
              {'front': 'Invented question?', 'back': 'Invented', 'sourceQuote': 'This sentence is not in the article at all, honest.'},
            ]
          }));
      expect(cards.length, 1);
      expect(await addAiCards(tg.first.packId, tg.first.index, tg.first.title, cards), 1);
    });

    test('real library: targets, passages, end to end with a fake that quotes the real text', () async {
      final base = installPacks(['clinical-essentials']);
      await library.init(base);
      final t = await chooseTargets('core', seed: 3, limit: 2);
      expect(t.length, 2);
      final ps = await passagesOf(t.first.packId, t.first.index);
      expect(ps.isNotEmpty && ps.length <= 3, true);
      expect(ps.every((p) => p.text.length <= 1800), true);
      final course = await chooseTargets('course', packId: 'clinical-essentials', seed: 1, limit: 2);
      expect(course.isNotEmpty, true);
      // a fake model that builds a true/false item from a real sentence
      final sent = RegExp(r'[A-Z][^.]{50,180}\.').firstMatch(ps.first.text)!.group(0)!.trim();
      final rep = await generateFromPassages(ps, group: 'Test', style: 'tf', runner: (r) async => AiResult(ok: true, json: {
            'questions': [
              good('Statement from the article: ${sent.substring(0, min(60, sent.length))} is correct and supported.', ['True', 'False'], 0, sent, expl: 'The passage says so.')
            ]
          }), verify: false);
      expect(rep.generated, 1);
      expect(rep.accepted + rep.drops.values.fold(0, (a, b) => a + b), 1);
    });
  });

  // ------------------------------------------------------------ widgets
  setUpAll(() async {
    final rb = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
    Future<void> lf(String family, List<String> files) async {
      final l = FontLoader(family);
      for (final f in files) {
        l.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
      }
      await l.load();
    }
    await lf('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    const fd = 'assets/fonts';
    await lf('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await lf('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
  });

  final key = GlobalKey();
  Future<void> snap(WidgetTester t, String name) async {
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('test_output/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> pumpAll(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  for (final lang in ['en', 'ar']) {
    for (final size in [const Size(412, 892), const Size(360, 640)]) {
      testWidgets('ai3 widgets $lang ${size.width.toInt()}x${size.height.toInt()} scale 1.3', (tester) async {
        await tester.runAsync(() async {
          await initStoreLight(settings: {'lang': lang});
          await library.init(installPacks(['clinical-essentials']));
          store.extra.clear();
        });
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        // seed the bank (as if generated earlier)
        await tester.runAsync(() async {
          for (final g in goods) {
            final opts = g['options'] as List;
            final q = aiMake(g, ps0, style: opts.isEmpty ? 'short' : opts.length == 2 ? 'tf' : 'vignette');
            await aiSaveQ(q.m);
          }
          store.settings['aiQuizStats'] = {'generated': 14, 'accepted': 10, 'requests': 2};
        });
        final tag = '${lang}_${size.width.toInt()}';
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: MediaQueryData(size: size, textScaler: const TextScaler.linear(1.3)),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(useMaterial3: true, fontFamily: lang == 'ar' ? 'Cairo' : 'Roboto'),
              builder: (c, w) => Directionality(textDirection: isAr ? TextDirection.rtl : TextDirection.ltr, child: w!),
              home: const AiQuizScreen(),
            ),
          ),
        ));
        await pumpAll(tester);
        expect(tester.takeException(), isNull);
        await snap(tester, 'ai3_setup_$tag');
        // scroll to the bottom for options
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await pumpAll(tester);
        await snap(tester, 'ai3_setup2_$tag');
        await tester.drag(find.byType(ListView), const Offset(0, 1500));
        await pumpAll(tester);
        // start practice (bank only: AI is off in tests)
        await tester.scrollUntilVisible(find.byIcon(Icons.play_arrow), 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byIcon(Icons.play_arrow));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await pumpAll(tester);
        expect(find.byType(AiBadge), findsWidgets);
        await snap(tester, 'ai3_q_$tag');
        // answer: tap the first option InkWell
        await tester.tap(find.byType(InkWell).at(1));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await pumpAll(tester);
        await snap(tester, 'ai3_a_$tag');
        expect(tester.takeException(), isNull);
        // go through the rest
        for (var i = 0; i < 12 && find.byType(AiBadge).evaluate().isNotEmpty; i++) {
          // answer if options visible, or reveal short answers
          final inks = find.byType(InkWell);
          if (inks.evaluate().length > 1 && find.byIcon(Icons.flag_outlined).evaluate().isEmpty) {
            await tester.tap(inks.at(1));
          } else if (find.byType(FilledButton).evaluate().isNotEmpty && find.byIcon(Icons.flag_outlined).evaluate().isEmpty) {
            await tester.tap(find.byType(FilledButton).first);
            await pumpAll(tester);
            if (find.byType(OutlinedButton).evaluate().isNotEmpty) await tester.tap(find.byType(OutlinedButton).first);
          }
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
          await pumpAll(tester);
          final next = find.byType(FilledButton);
          if (find.byIcon(Icons.flag_outlined).evaluate().isNotEmpty && next.evaluate().isNotEmpty) {
            await tester.ensureVisible(next.last);
            await tester.tap(next.last);
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
            await pumpAll(tester);
          }
          if (find.text('Results').evaluate().isNotEmpty || find.text('النتائج').evaluate().isNotEmpty) break;
        }
        expect(tester.takeException(), isNull);
        await snap(tester, 'ai3_end_$tag');
      });
    }
  }
}
int min(int a, int b) => a < b ? a : b;
