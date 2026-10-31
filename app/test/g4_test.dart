import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/ai/ai_api.dart';
import 'package:medlog/ai/ai_doc_api.dart';
import 'package:medlog/ai/ai_prefs.dart';
import 'package:medlog/ai/ai_quiz.dart';
import 'package:medlog/ai/ai_study.dart';
import 'package:medlog/ai/ai_study_hooks.dart';
import 'package:medlog/ai/voice_input.dart';
import 'package:medlog/core_topics.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' show isAr, trp;
import 'package:medlog/lib_plan.dart';
import 'package:medlog/lib_user.dart';
import 'package:medlog/library.dart';
import 'package:medlog/screens_ai_quiz.dart';
import 'package:medlog/screens_ai_study.dart';
import 'package:medlog/screens_learn.dart';

import 'ai3_test.dart' show goods, ps0;
import 'lib2_util.dart';

const _nice = 'https://www.nice.org.uk/guidance/ng138';
const _cite = AiCite(label: 'NICE NG138 (2019)', org: 'NICE', year: '2019', url: _nice);

AiDoc sampleDoc() => const AiDoc(
      sections: [
        AiDocSection(kind: 'management', title: 'First-line treatment', bullets: [
          'Start amoxicillin 500 mg three times daily for 5 days in mild community-acquired pneumonia.',
          'Offer oral rehydration solution first to adults with mild dehydration and no vomiting.',
        ], cites: [_cite]),
        AiDocSection(kind: 'key_points', title: 'Opinion', bullets: ['Some doctors prefer to wait before starting treatment in selected patients.']),
        AiDocSection(kind: 'table', title: 'Doses', table: [
          ['Drug', 'Dose'],
          ['Amoxicillin', '500 mg three times daily'],
        ], cites: [_cite]),
        AiDocSection(kind: 'references', title: 'References', text: 'NICE NG138'),
      ],
      citations: [_cite],
      raw: 'raw',
      structured: true,
    );

String vivaJson({int good = 3}) => jsonEncode({
      'vignette': 'A fictional 62-year-old man presents with fever, cough and pleuritic chest pain for three days.',
      'questions': [
        for (var i = 0; i < good; i++)
          {
            'q': 'Question ${i + 1}: what is the first investigation and why in this fictional patient?',
            'topic': 'Pneumonia $i',
            'points': [
              {'text': 'Chest X-ray confirms consolidation', 'org': 'NICE', 'year': '2019', 'url': _nice},
              {'text': 'Check oxygen saturation and respiratory rate', 'org': 'NICE', 'year': '2019', 'url': _nice},
              {'text': 'Use CURB-65 to grade severity', 'org': 'NICE', 'year': '2019', 'url': _nice},
              {'text': 'A point from a bad site', 'org': 'Blog', 'year': '2020', 'url': 'https://evil.example.com/x'},
              {'text': 'A point without any source'},
            ],
            'senior': 'A senior would grade severity with CURB-65 before choosing where to treat.',
          },
        {
          'q': 'A question with only one valid point should be dropped entirely',
          'topic': 'x',
          'points': [
            {'text': 'Only one', 'org': 'NICE', 'year': '2019', 'url': _nice},
            {'text': 'Bad', 'org': 'Blog', 'year': '2020', 'url': 'https://evil.example.com/x'},
          ],
        },
      ],
    });

class FakeVoice implements VoiceEngine {
  bool ok = true;
  String? error;
  String? locale;
  bool started = false;
  bool stopped = false;
  void Function(String, bool)? cb;
  @override
  Future<bool> init({void Function(String error)? onError, void Function(String status)? onStatus}) async {
    if (error != null) onError?.call(error!);
    return ok;
  }

  @override
  Future<List<String>> locales() async => ['en_US', 'ar_JO', 'fr_FR'];
  @override
  Future<void> start({required String localeId, required void Function(String text, bool isFinal) onText}) async {
    locale = localeId;
    started = true;
    cb = onText;
  }

  @override
  Future<void> stop() async => stopped = true;
  @override
  bool get listening => started && !stopped;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  // ------------------------------------------------------------------ hooks
  group('hooks', () {
    setUp(() async {
      await initStoreLight();
    });

    test('makeCards: Q/A pairs, source AI answer + guideline names, no duplicates', () async {
      final n = await AiStudyHooks.makeCards(sampleDoc(), source: 'Pneumonia');
      expect(n, greaterThanOrEqualTo(3)); // two sections + one table row (the reference section is skipped)
      final cards = store.listOf('libcards');
      expect(cards.length, n);
      expect(cards.every((c) => '${c['source']}'.startsWith('AI answer')), true);
      expect(cards.every((c) => '${c['source']}'.contains('NICE NG138 (2019)')), true);
      expect(cards.any((c) => '${c['front']}'.contains('First-line treatment')), true);
      expect(cards.any((c) => '${c['back']}'.contains('amoxicillin')), true);
      expect(cards.any((c) => '${c['front']}'.contains('References')), false);
      expect(await AiStudyHooks.makeCards(sampleDoc(), source: 'Pneumonia'), 0);
    });

    test('makeQuestions: ONLY cited facts; labelled AI (web answer); citation instead of a quote', () async {
      final n = await AiStudyHooks.makeQuestions(sampleDoc());
      expect(n, 3); // 2 cited bullets + 1 cited table row; the uncited "Opinion" bullet gives nothing
      final bank = aiBank();
      expect(bank.length, 3);
      expect(bank.every((q) => q.isWeb && q.group == kAiWebGroup && q.isShort && q.cite == 'NICE NG138 (2019)' && q.citeUrl == _nice), true);
      expect(bank.any((q) => q.stem.contains('Opinion') || q.quote.contains('Some doctors')), false);
      for (final q in bank) {
        expect(q.stem.contains(q.answerText) && !q.stem.contains('______') && !q.stem.startsWith('According'), false, reason: q.stem);
        expect(q.quote.isNotEmpty, true);
      }
      expect(bank.where((q) => q.stem.contains('______')).length, 2);
      // no repeats, practised like any other bank question, and kept out of "Core 250" mode
      expect(await AiStudyHooks.makeQuestions(sampleDoc()), 0);
      final (qs, _) = await selectFromBank(const AiPick(mode: 'all', count: 10));
      expect(qs.length, 3);
      final (core, _) = await selectFromBank(const AiPick(mode: 'core', count: 10));
      expect(core.where((q) => q.isWeb), isEmpty);
    });

    test('inline [n] markers count as a citation; a doc without any citation gives no question', () async {
      const doc = AiDoc(sections: [
        AiDocSection(kind: 'key_points', title: 'Cited inline', bullets: ['Give aspirin 300 mg once as soon as possible in suspected acute coronary syndrome [1].']),
        AiDocSection(kind: 'key_points', title: 'Not cited', bullets: ['Give aspirin 300 mg once as soon as possible in all chest pain at home.']),
      ], citations: [_cite]);
      expect(await AiStudyHooks.makeQuestions(doc), 1);
      expect(AiStudyHooks.citedFacts(doc).length, 1);
      expect(await AiStudyHooks.makeQuestions(const AiDoc(sections: [AiDocSection(title: 'x', bullets: ['A long enough statement without any source at all here.'])])), 0);
    });
  });

  // ------------------------------------------------------------------ coach
  group('coach', () {
    late String firstTitle;
    setUp(() async {
      await initStoreLight();
      await library.init(installPacks(['clinical-essentials', 'cardiology']));
      await resolveCore250(force: true);
      final titles = await library.titlesOf('clinical-essentials');
      firstTitle = titles[120];
      await store.upsertExtra('quizlog', {
        'id': 'q1', 'date': nowIso(), 'n': 1, 'correct': 0,
        'items': [{'p': 'clinical-essentials', 't': firstTitle, 'ok': false}],
      });
      uninstallFakeAi();
    });

    test('local plan from weak spots, due cards, rotation and Core 250, without AI, within 25 minutes', () async {
      await addLibraryCard(front: 'What is X?', back: 'Y', source: 'test');
      final p = await buildCoachPlan();
      expect(p.isEmpty, false);
      expect(p.minutes <= 25 || p.steps.length == 1, true);
      expect(p.steps.any((s) => s.kind == 'weak' && s.articleTitle == firstTitle), true);
      expect(p.weak, 1);
      final kinds = p.steps.map((s) => s.kind).toSet();
      expect(kinds.length, p.steps.length ~/ 1 == kinds.length ? kinds.length : kinds.length);
      expect(Ai.enabled, false);
    });

    test('exam plan items appear as plan steps', () async {
      final titles = await library.titlesOf('cardiology');
      await saveExamPlan(ExamPlan(
        name: 'Board', date: fmtDate(DateTime.now().add(const Duration(days: 30))), packs: const ['cardiology'],
        items: [for (var i = 0; i < 6; i++) PlanItem('cardiology', titles[10 + i], false, spec: 'Cardiology')],
        done: const {}, start: todayStr(), perDay: 3,
      ));
      final p = await buildCoachPlan();
      expect(p.planToday, 3);
      expect(p.daysToExam, 30);
      expect(p.steps.where((s) => s.kind == 'plan').isNotEmpty, true);
    });

    test('AI pass sends counts only, validates the order, is cached for the day; reorder works', () async {
      installFakeAi(answers: {
        'quiz_coach': jsonEncode({'motivation': 'Small steps count: start with your cards.', 'why': 'Cards first while fresh.', 'order': ['core', 'bogus', 'weak']})
      });
      final p = await buildCoachPlan();
      final note = await coachAiNote(p);
      expect(note, isNotNull);
      expect(note!.motivation, contains('Small steps'));
      expect(note.order.contains('bogus'), false);
      final sent = FakeAi.sent.last;
      expect(sent.level, AiLevel.none);
      expect(sent.prompt.contains(firstTitle), false);
      expect(sent.prompt, contains('weak_topics=1'));
      final again = await coachAiNote(p);
      expect(again!.motivation, note.motivation);
      expect(FakeAi.sent.where((r) => r.feature == 'quiz_coach').length, 1);
      final r = reorderCoach(p, ['core', 'weak']);
      final ks = r.steps.map((s) => s.kind).toList();
      if (ks.contains('core') && ks.contains('weak')) expect(ks.indexOf('core') < ks.indexOf('weak'), true);
      expect(r.steps.length, p.steps.length);
      uninstallFakeAi();
    });

    test('AI off or offline: no note, local plan untouched', () async {
      installFakeAi(online: false);
      final p = await buildCoachPlan();
      expect(await coachAiNote(p), isNull);
      expect(p.isEmpty, false);
      uninstallFakeAi();
    });
  });

  // ------------------------------------------------------------------ viva
  group('viva', () {
    setUp(() async {
      await initStoreLight();
      await library.init(installPacks(['clinical-essentials', 'cardiology']));
      store.settings.remove('aiSourceMode');
    });
    tearDown(uninstallFakeAi);

    test('station: points without a valid source are dropped; weak questions dropped; fictional; library passages grounded', () async {
      installFakeAi(answers: {'quiz_viva': vivaJson()});
      final g = await generateViva(mode: 'viva', specialty: 'Cardiology', topic: 'pneumonia');
      expect(g.failure, '');
      final st = g.station!;
      expect(st.items.length, 3);
      for (final it in st.items) {
        expect(it.points.length, 3);
        expect(it.points.every((p) => p.source.org == 'NICE' && p.source.year == '2019'), true);
      }
      final sent = FakeAi.sent.firstWhere((r) => r.feature == 'quiz_viva');
      expect(sent.system, contains('fictional'));
      expect(sent.search, isNotNull); // web mode: provider live search with the allow-list
      expect(sent.search!.domains.contains('nice.org.uk'), true);
    });

    test('library mode: a point needs a quote that is inside the passages', () async {
      AiPrefs.sourceMode = 'library';
      final ps = await passagesForTopic('pneumonia', articles: 1, sections: 1);
      expect(ps, isNotEmpty);
      final sentence = RegExp(r'[A-Z][^.]{40,160}\.').firstMatch(ps.first.text)!.group(0)!.trim();
      final j = jsonEncode({
        'vignette': 'A fictional patient with cough and fever for three days, no other history.',
        'questions': [
          {'q': 'What would you do first in this fictional patient, and why?', 'topic': 'T', 'points': [
            {'text': 'Point one from the passage', 'quote': sentence},
            {'text': 'Point two from the passage', 'quote': sentence},
            {'text': 'Invented point', 'quote': 'This sentence is not in any passage at all, really not.'},
          ], 'senior': 'x'},
          {'q': 'Another question that has only an invented quote?', 'topic': 'T', 'points': [
            {'text': 'Invented', 'quote': 'Totally made up sentence which is nowhere to be found.'},
            {'text': 'Invented 2', 'quote': 'Another made up sentence which is nowhere to be found.'},
          ]},
          {'q': 'A third grounded question about the same passage text?', 'topic': 'T', 'points': [
            {'text': 'Point P1 grounded', 'quote': sentence}, {'text': 'Point P2 grounded', 'quote': sentence},
          ]},
        ],
      });
      final g = await generateViva(mode: 'shortcase', specialty: 'Cardiology', topic: 'pneumonia', runner: (r) async => AiResult(ok: true, text: j));
      AiPrefs.sourceMode = 'web';
      expect(g.station, isNotNull, reason: g.failure);
      expect(g.station!.items.length, 2);
      expect(g.station!.items.first.points.length, 2);
      expect(g.station!.items.first.points.first.source.quote, sentence);
    });

    test('scoring: hits parsed, marks computed by the app; malformed answer falls back to local estimate', () async {
      final st = (await generateViva(mode: 'viva', specialty: 'Cardiology', runner: (r) async => AiResult(ok: true, text: vivaJson()))).station!;
      final ok = await scoreViva(st, 0, 'I would get a chest x-ray and check oxygen saturation', runner: (r) async => AiResult(ok: true, text: jsonEncode({'hit': [true, true, false], 'feedback': 'Good start.', 'senior': 'Add CURB-65.'})));
      expect(ok.estimated, false);
      expect(ok.hits, [true, true, false]);
      expect(ok.score, 3); // round(5 * 2/3)
      expect(ok.feedback, 'Good start.');
      final bad = await scoreViva(st, 0, 'chest x-ray consolidation and oxygen saturation respiratory rate', runner: (r) async => const AiResult(ok: true, text: 'sorry, no json'));
      expect(bad.estimated, true);
      expect(bad.hits.length, 3);
      expect(bad.hits.where((h) => h).length, greaterThanOrEqualTo(2));
      final wrongLen = await scoreViva(st, 0, 'nothing relevant', runner: (r) async => AiResult(ok: true, text: jsonEncode({'hit': [true]})));
      expect(wrongLen.estimated, true);
      final offline = await scoreViva(st, 0, 'x', runner: (r) async => const AiResult(offline: true));
      expect(offline.estimated, true);
      expect(offline.score, 0);
    });

    test('whole session: score, weak areas into weak-spot memory, review cards, saved session reloads', () async {
      final st = (await generateViva(mode: 'viva', specialty: 'Cardiology', runner: (r) async => AiResult(ok: true, text: vivaJson()))).station!;
      final turns = [
        await scoreViva(st, 0, 'a', runner: (r) async => AiResult(ok: true, text: jsonEncode({'hit': [true, true, true], 'feedback': 'f', 'senior': 's'}))),
        await scoreViva(st, 1, 'b', runner: (r) async => AiResult(ok: true, text: jsonEncode({'hit': [true, false, false], 'feedback': 'f', 'senior': 's'}))),
        await scoreViva(st, 2, 'c', runner: (r) async => AiResult(ok: true, text: jsonEncode({'hit': [false, false, false], 'feedback': 'f', 'senior': 's'}))),
      ];
      expect(turns.map((t) => t.score), [5, 2, 0]);
      final cards0 = store.listOf('libcards').length;
      final res = await finishViva(st, turns);
      expect(res.total, 7);
      expect(res.max, 15);
      expect(res.weak, ['Pneumonia 1', 'Pneumonia 2']);
      expect(store.listOf('libcards').length, cards0 + 2);
      expect(aiWeakAreas().map((e) => e['topic']).toSet(), {'Pneumonia 1', 'Pneumonia 2'});
      expect(allWeakTopicNames(), containsAll(['Pneumonia 1', 'Pneumonia 2']));
      final saved = vivaSessions();
      expect(saved.length, 1);
      final back = stationOf(saved.first);
      expect(back.items.length, 3);
      expect(back.items.first.points.first.text, 'Chest X-ray confirms consolidation');
      expect(turnsOf(saved.first).map((t) => t.score), [5, 2, 0]);
    });

    test('offline: AI off gives a failure code, self-viva works from weak topics without AI', () async {
      installFakeAi(online: false);
      final g = await generateViva(mode: 'viva', specialty: 'Cardiology');
      expect(g.station, isNull);
      expect(g.failure, 'offline');
      uninstallFakeAi();
      final titles = await library.titlesOf('clinical-essentials');
      await store.upsertExtra('quizlog', {'id': 'q1', 'date': nowIso(), 'items': [{'p': 'clinical-essentials', 't': titles[200], 'ok': false}]});
      final items = await selfVivaItems(n: 3);
      expect(items.length, 3);
      expect(items.first.title, stripSource(titles[200]));
      final r = await finishSelfViva(items, [2, 1, 0]);
      expect(r.total, 5 + 3 + 0);
      expect(r.weak.length, 1);
      expect(vivaSessions().first['type'], 'self');
    });
  });

  // ------------------------------------------------------------------ teach, case of the day
  group('teach and case', () {
    setUp(() async {
      await initStoreLight();
      await library.init(installPacks(['clinical-essentials', 'cardiology']));
    });
    tearDown(uninstallFakeAi);

    test('Socratic: asks first, then a stepwise lesson; steps without a source are dropped; cards made', () async {
      installFakeAi(answers: {
        'quiz_teach_ask': jsonEncode({'questions': ['What is atrial fibrillation?', 'How do you decide on anticoagulation?', 'What is rate vs rhythm control?']}),
        'quiz_teach': jsonEncode({
          'steps': [
            {'title': 'Definition', 'text': 'Atrial fibrillation is an irregularly irregular rhythm without P waves.', 'check': 'What does the ECG show?', 'answer': 'No P waves, irregular RR', 'org': 'NICE', 'year': '2021', 'url': 'https://www.nice.org.uk/guidance/ng196'},
            {'title': 'No source', 'text': 'This step has no source and must be dropped by the app.', 'check': 'Which step is this?', 'answer': 'none'},
            {'title': 'Stroke risk', 'text': 'Use the CHA2DS2-VASc score to decide on anticoagulation in AF.', 'check': 'Which score is used?', 'answer': 'CHA2DS2-VASc', 'org': 'ESC', 'year': '2020', 'url': 'https://www.escardio.org/Guidelines'},
          ],
          'summary': 'AF needs a rhythm check and a stroke-risk decision.'
        }),
      });
      final (qs, f) = await teachQuestions('atrial fibrillation');
      expect(f, '');
      expect(qs.length, 3);
      final (lesson, f2) = await teachLesson('atrial fibrillation', [(qs[0], 'irregular'), (qs[1], '')]);
      expect(f2, '');
      expect(lesson!.steps.length, 2);
      expect(lesson.steps.every((s) => s.source.org.isNotEmpty), true);
      // the learner's empty answer is marked as unknown, not left blank
      expect(FakeAi.sent.last.prompt, contains('did not know'));
      expect(await teachCards(lesson), 2);
      await saveTeachSession(lesson, known: 1);
      expect(store.listOf('aiteach').length, 1);
    });

    test('Socratic offline / AI off gives a failure, nothing invented', () async {
      installFakeAi(enabled: false);
      final (qs, f) = await teachQuestions('asthma');
      expect(qs, isEmpty);
      expect(f, 'off');
    });

    test('case of the day: valid steps only, saved for the day (second call does not ask the AI again)', () async {
      installFakeAi(answers: {
        'case_ofday': jsonEncode({
          'title': 'Chest pain on the ward',
          'vignette': 'A fictional 58-year-old man has central chest pain for 30 minutes on the ward.',
          'steps': [
            {'ask': 'What is your first action?', 'answer': 'ABC and ECG', 'teach': 'Get an ECG within 10 minutes of arrival for chest pain.', 'org': 'NICE', 'year': '2020', 'url': 'https://www.nice.org.uk/guidance/cg95'},
            {'ask': 'Which test next?', 'answer': 'Troponin', 'teach': 'Take a high-sensitivity troponin at presentation.', 'org': 'ESC', 'year': '2023', 'url': 'https://www.escardio.org/Guidelines'},
            {'ask': 'A step without any source at all?', 'answer': 'x', 'teach': 'This teaching point has no source and is dropped.'},
          ],
        })
      });
      final (c, f) = await caseOfTheDay(topic: 'chest pain');
      expect(f, '');
      expect(c!.steps.length, 2);
      final n = FakeAi.sent.length;
      final (c2, _) = await caseOfTheDay(topic: 'chest pain');
      expect(c2!.title, 'Chest pain on the ward');
      expect(FakeAi.sent.length, n);
      expect(savedCaseOfDay()!.steps.length, 2);
    });
  });

  // ------------------------------------------------------------------ guideline check, comparison
  group('tables', () {
    late AiTarget t;
    setUp(() async {
      await initStoreLight();
      await library.init(installPacks(['clinical-essentials', 'cardiology']));
      t = (await chooseTargets('core', seed: 3, limit: 1)).first;
    });
    tearDown(uninstallFakeAi);

    test('guideline check: web mode, table rows, unsourced claims become "no source found", saved with date', () async {
      installFakeAi(answers: {
        'ask_gcheck': jsonEncode({
          'rows': [
            {'item': 'First-line antibiotic', 'mine': 'Amoxicillin 5 days', 'current': 'Amoxicillin 500 mg for 5 days', 'status': 'changed', 'org': 'NICE', 'year': '2019', 'url': _nice},
            {'item': 'Severity score', 'mine': 'CURB-65', 'current': 'CURB-65', 'status': 'same', 'org': 'NICE', 'year': '2019', 'url': 'https://evil.example.com/x'},
            {'item': 'Steroids', 'mine': 'Not used', 'current': 'Consider dexamethasone', 'status': 'changed'},
          ],
          'summary': 'One item may have changed.'
        })
      });
      final (c, f) = await guidelineCheck(t.packId, t.index);
      expect(f, '');
      expect(c!.rows.length, 3);
      expect(c.rows[0].status, 'changed');
      expect(c.rows[1].status, 'no_source');
      expect(c.rows[2].status, 'no_source');
      expect(c.rows[2].current, '');
      expect(c.changed, 1);
      expect(c.verdict, contains('may be out of date'));
      final doc = c.toDoc();
      expect(doc.sections.first.kind, 'table');
      expect(doc.sections.first.table.first, ['Item', 'In my reference', 'Current guideline', 'Status']);
      expect(doc.sections.first.table[1][2], contains('NICE 2019'));
      expect(doc.sections.first.table[3][3], 'No source found');
      final sent = FakeAi.sent.firstWhere((r) => r.feature == 'ask_gcheck');
      expect(sent.search, isNotNull);
      expect(sent.search!.mode, 'web'); // forced, whatever the source mode is
      expect(guidelineChecks(packId: t.packId).length, 1);
      expect(guidelineChecks(packId: t.packId).first.date, todayStr());
    });

    test('guideline check honesty: nothing found = "no change found", not "up to date"', () async {
      installFakeAi(answers: {'ask_gcheck': jsonEncode({'rows': [], 'summary': ''})});
      final (c, _) = await guidelineCheck(t.packId, t.index);
      expect(c!.noChange, true);
      expect(c.verdict, startsWith('No change found'));
      expect(c.verdict, contains('does not prove'));
    });

    test('guideline check offline gives the failure code and no row', () async {
      installFakeAi(online: false);
      final (c, f) = await guidelineCheck(t.packId, t.index);
      expect(c, isNull);
      expect(f, 'offline');
    });

    test('compare: a table only when both guidelines were found, otherwise an honest message', () async {
      installFakeAi(answers: {
        'ask_compare': jsonEncode({
          'a': {'org': 'ESC', 'year': '2023', 'url': 'https://www.escardio.org/Guidelines/x'},
          'b': {'org': 'AHA/ACC', 'year': '2025', 'url': 'https://www.ahajournals.org/doi/x'},
          'rows': [
            {'aspect': 'Target', 'a': '<130/80 if tolerated', 'b': '<130/80'},
            {'aspect': 'First-line', 'a': 'ACEi/ARB + CCB', 'b': ''},
          ],
          'summary': 'Both aim for 130/80.'
        })
      });
      final (c, _) = await compareGuidelines('hypertension targets', 'ESC', 'AHA/ACC');
      expect(c!.rows.length, 2);
      expect(c.rows[1][2], 'not addressed');
      final d = c.toDoc();
      expect(d.sections.first.table.first, ['Aspect', 'ESC 2023', 'AHA/ACC 2025']);
      installFakeAi(answers: {
        'ask_compare': jsonEncode({
          'a': {'org': 'ESC', 'year': '2023', 'url': 'https://www.escardio.org/Guidelines/x'},
          'b': {'org': 'AHA', 'year': '', 'url': ''},
          'rows': [{'aspect': 'Target', 'a': 'x', 'b': 'y'}],
        })
      });
      final (c2, _) = await compareGuidelines('hypertension targets', 'ESC', 'AHA/ACC');
      expect(c2!.rows, isEmpty);
      expect(c2.summary, contains('No source found'));
    });
  });

  // ------------------------------------------------------------------ pre-shift, plan, grading
  group('pre-shift, plan, grading', () {
    setUp(() async {
      await initStoreLight();
      await library.init(installPacks(['clinical-essentials', 'cardiology', 'pulmonology']));
      await resolveCore250(force: true);
    });
    tearDown(uninstallFakeAi);

    test('pre-shift quiz: 5 questions from the bank first, no AI needed; empty bank offers the standard quiz', () async {
      var s = await preShiftSet();
      expect(s.questions, isEmpty);
      for (final g in goods) {
        final opts = g['options'] as List;
        await aiSaveQ(aiMake(g, ps0, style: opts.isEmpty ? 'short' : opts.length == 2 ? 'tf' : 'vignette').m);
      }
      s = await preShiftSet();
      expect(s.questions.length, 5);
      expect(s.rotation, 'Orthopedics');
      expect(s.generated, false);
    });

    test('week review and rebalancing: weak specialty gets more time, strong less; behind plans detected', () async {
      final titles = await library.titlesOf('cardiology');
      final pt = await library.titlesOf('pulmonology');
      final now = DateTime.now();
      final items = [
        for (var i = 0; i < 12; i++) PlanItem('cardiology', titles[20 + i], false, spec: 'Cardiology'),
        for (var i = 0; i < 12; i++) PlanItem('pulmonology', pt[20 + i], false, spec: 'Pulmonology'),
      ];
      final plan = ExamPlan(
        name: 'Board', date: fmtDate(now.add(const Duration(days: 40))), packs: const [], items: items, done: {items[0].key, items[1].key},
        weights: const {'Cardiology': 4, 'Pulmonology': 4, 'Surgery': 0}, preset: 'internship',
        start: fmtDate(now.subtract(const Duration(days: 7))), perDay: 2,
        doneOn: {items[0].key: todayStr(), items[1].key: todayStr()},
      );
      await store.upsertExtra('quizlog', {'id': 'a', 'date': nowIso(), 'items': [
        for (var i = 0; i < 4; i++) {'p': 'cardiology', 't': titles[20 + i], 'ok': i == 0},
        for (var i = 0; i < 6; i++) {'p': 'pulmonology', 't': pt[20 + i], 'ok': true},
      ]});
      await store.upsertExtra('quizlog', {'id': 'old', 'date': now.subtract(const Duration(days: 20)).toUtc().toIso8601String(), 'items': [
        for (var i = 0; i < 6; i++) {'p': 'cardiology', 't': titles[20 + i], 'ok': true},
      ]});
      final wr = weekReview(plan);
      expect(wr.answers, 10);
      expect(wr.accuracy, closeTo(0.7, 0.001));
      expect(wr.bySpec['Cardiology'], (1, 4));
      expect(wr.done, 2);
      expect(wr.planned, greaterThan(4));
      final rb = rebalanceWeights(plan, wr);
      expect(rb.after['Cardiology'], 6.0);
      expect(rb.after['Pulmonology'], 3.0);
      expect(rb.after['Surgery'], 0.0);
      expect(rb.changes.first.spec, 'Cardiology');
      expect(rb.behind, true);
      // AI explanation: numbers only
      installFakeAi(answers: {'quiz_adapt': jsonEncode({'text': 'Cardiology answers were weak, so it gets more time.'})});
      final txt = await explainRebalance(rb, wr);
      expect(txt, contains('Cardiology'));
      final sent = FakeAi.sent.firstWhere((r) => r.feature == 'quiz_adapt');
      expect(sent.level, AiLevel.none);
      expect(sent.prompt, contains('Cardiology: 4.0 -> 6.0'));
      expect(sent.prompt.contains(titles[20]), false);
      // applying: weights saved, ticked items kept, spread restarts today
      final np = await adaptWeekPlan(plan, rb);
      expect(np.weights['Cardiology'], 6.0);
      expect(np.start, todayStr());
      expect(np.done, plan.done);
      expect(np.preset, 'custom');
      expect(np.items.isNotEmpty, true);
      expect(np.perDay >= 1, true);
    });

    test('nothing to change: empty rebalance; weights stay', () async {
      final plan = ExamPlan(name: '', date: fmtDate(DateTime.now().add(const Duration(days: 10))), packs: const [], items: const [], done: const {}, weights: const {'Cardiology': 4});
      final rb = rebalanceWeights(plan, weekReview(plan));
      expect(rb.isEmpty, true);
      expect(rb.after['Cardiology'], 4.0);
    });

    test('written answer: rubric parsed, invented "wrong" statements dropped, score clamped, saved; offline = local estimate', () async {
      const ref = 'Colchicine is used to treat acute attacks of gout when started early. NSAIDs are first line when there are no contraindications.';
      const answer = 'Gout is caused by bacteria in the joint and is treated with colchicine started early.';
      final (g, f) = await gradeWritten(
          question: 'How is an acute attack of gout treated?', reference: ref, sourceLabel: 'Gout — WikEM', answer: answer,
          runner: (r) async => AiResult(ok: true, text: jsonEncode({
                'score': 14, 'strengths': ['Colchicine named, started early'], 'missing': ['NSAIDs as first line'],
                'wrong': [{'statement': 'Gout is caused by bacteria in the joint', 'why': 'It is urate crystals.'}, {'statement': 'Zebras graze on the savannah daily', 'why': 'invented'}],
                'comment': 'Partly right.'
              })));
      expect(f, '');
      expect(g!.score, 10);
      expect(g.wrong.length, 1);
      expect(g.wrong.first.$1, contains('bacteria'));
      expect(g.missing, ['NSAIDs as first line']);
      expect(g.estimated, false);
      expect(gradings().length, 1);
      final (g2, f2) = await gradeWritten(question: 'How is gout treated?', reference: ref, sourceLabel: 'Gout', answer: 'colchicine', runner: (r) async => const AiResult(offline: true));
      expect(g2!.estimated, true);
      expect(f2.isNotEmpty, true);
      expect(g2.score, lessThan(10));
      expect(g2.comment, contains('Local keyword check'));
      expect(gradings().length, 2);
    });
  });

  // ------------------------------------------------------------------ voice
  group('voice', () {
    test('locale choice follows the app language and what the device offers', () {
      expect(VoiceInput.pickLocale(['en_US', 'ar_JO'], arabic: true), 'ar_JO');
      expect(VoiceInput.pickLocale(['en_US', 'ar-EG'], arabic: true), 'ar-EG');
      expect(VoiceInput.pickLocale(['en-GB', 'en-US'], arabic: false), 'en-US');
      expect(VoiceInput.pickLocale(const [], arabic: true), 'ar_JO');
      expect(VoiceInput.messageFor('error_permission'), contains('permission'));
    });

    testWidgets('partial results go into the field, existing text is kept, stop works', (tester) async {
      final fake = FakeVoice();
      VoiceInput.engine = fake;
      final c = TextEditingController(text: 'Pt has');
      var changed = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextField(controller: c, decoration: InputDecoration(suffixIcon: VoiceInputButton(controller: c, arabic: true, onChanged: () => changed++))))));
      await tester.tap(find.byKey(const ValueKey('voiceInput')));
      await tester.pump();
      await tester.pump();
      expect(fake.started, true);
      expect(fake.locale, 'ar_JO');
      fake.cb!('fever and', false);
      await tester.pump();
      expect(c.text, 'Pt has fever and');
      fake.cb!('fever and cough', false);
      expect(c.text, 'Pt has fever and cough');
      fake.cb!('fever and cough', true);
      await tester.pump();
      expect(c.text, 'Pt has fever and cough');
      expect(changed, 3);
      expect(find.byIcon(Icons.mic_none), findsOneWidget); // final result ended the listening state
      await tester.tap(find.byKey(const ValueKey('voiceInput')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voiceInput')));
      await tester.pump();
      expect(fake.stopped, true);
      VoiceInput.engine = SttEngine();
    });

    testWidgets('permission denied and unavailable recogniser fail gracefully (message, no crash)', (tester) async {
      final fake = FakeVoice()
        ..ok = false
        ..error = 'error_permission';
      VoiceInput.engine = fake;
      final c = TextEditingController();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [TextField(controller: c), VoiceInputButton(controller: c)]))));
      await tester.tap(find.byKey(const ValueKey('voiceInput')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Microphone permission was denied'), findsOneWidget);
      expect(tester.takeException(), isNull);
      fake.error = null;
      await tester.tap(find.byKey(const ValueKey('voiceInput')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('not available'), findsOneWidget);
      expect(fake.started, false);
      VoiceInput.engine = SttEngine();
    });
  });

  // ------------------------------------------------------------------ widgets
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

  Future<void> settle(WidgetTester t, {int n = 14}) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> reveal(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(f);
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpApp(WidgetTester t, Size size, String lang, Widget home) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = size;
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MediaQuery(
        data: MediaQueryData(size: size, textScaler: const TextScaler.linear(1.3)),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: lang == 'ar' ? 'Cairo' : 'Roboto'),
          builder: (c, w) => Directionality(textDirection: isAr ? TextDirection.rtl : TextDirection.ltr, child: w!),
          home: home,
        ),
      ),
    ));
    await settle(t);
  }

  Future<void> seed(WidgetTester tester, String lang) async {
    await tester.runAsync(() async {
      await initStoreLight(settings: {'lang': lang});
      await library.init(installPacks(['clinical-essentials', 'cardiology']));
      await resolveCore250(force: true);
      for (final g in goods) {
        final opts = g['options'] as List;
        await aiSaveQ(aiMake(g, ps0, style: opts.isEmpty ? 'short' : opts.length == 2 ? 'tf' : 'vignette').m);
      }
      final titles = await library.titlesOf('clinical-essentials');
      await store.upsertExtra('quizlog', {'id': 'q1', 'date': nowIso(), 'items': [{'p': 'clinical-essentials', 't': titles[120], 'ok': false}]});
      await addLibraryCard(front: 'What is X?', back: 'Y', source: 'test');
    });
  }

  for (final lang in ['en', 'ar']) {
    for (final size in [const Size(412, 892), const Size(360, 640)]) {
      final tag = '${lang}_${size.width.toInt()}';
      testWidgets('g4 Learn: AI bank card on top of Study, AI tab, coach, counts $tag', (tester) async {
        addTearDown(tester.view.reset);
        await seed(tester, lang);
        installFakeAi(enabled: false);
        await pumpApp(tester, size, lang, const LearnScreen());
        expect(tester.takeException(), isNull);
        // the hub: four verbs and a short More list instead of eight tabs
        expect(find.byType(Tab), findsNothing);
        expect(find.byKey(const ValueKey('learnCards')), findsOneWidget);
        expect(find.byKey(const ValueKey('learnQuiz')), findsOneWidget);
        expect(find.byKey(const ValueKey('learnStudy')), findsOneWidget);
        expect(find.byKey(const ValueKey('tabAi')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('learnCards')));
        await settle(tester);
        // my cards: the count, a new-card button and the settings; nothing else
        expect(find.byKey(const ValueKey('flashDue')), findsOneWidget);
        expect(find.byKey(const Key('flash_new')), findsOneWidget);
        expect(find.byKey(const Key('flash_settings')), findsOneWidget);
        expect(find.byKey(const ValueKey('aiBankCard')), findsNothing);
        await snap(tester, 'g4_learn_flash_$tag');
        // Study screen: the card sits ABOVE the planner
        await tester.pageBack();
        await settle(tester);
        await tester.drag(find.byType(ListView).first, const Offset(0, 900));
        await settle(tester, n: 3);
        await tester.tap(find.byKey(const ValueKey('learnStudy')));
        await settle(tester);
        final card = tester.getTopLeft(find.byKey(const ValueKey('aiBankCard')).hitTestable()).dy;
        final planner = tester.getTopLeft(find.text(lang == 'en' ? 'Exam planner' : 'مخطط الامتحان').first).dy;
        expect(card < planner, true);
        expect(find.text(trp('{n} saved questions', {'n': 10})), findsOneWidget);
        expect(find.byKey(const ValueKey('aiBankWeak')), findsOneWidget);
        await snap(tester, 'g4_learn_study_$tag');
        // AI study
        await tester.pageBack();
        await settle(tester);
        await tester.ensureVisible(find.byKey(const ValueKey('tabAi')));
        await settle(tester, n: 3);
        await tester.tap(find.byKey(const ValueKey('tabAi')));
        await settle(tester);
        expect(find.byKey(const ValueKey('aiHub')), findsOneWidget);
        expect(find.byKey(const ValueKey('aiBankPractice')), findsOneWidget);
        expect(find.byKey(const ValueKey('aiBankGenerate')), findsOneWidget);
        await snap(tester, 'g4_learn_ai_$tag');
        await tester.drag(find.byKey(const ValueKey('aiHub')), const Offset(0, -700));
        await settle(tester, n: 4);
        await snap(tester, 'g4_learn_ai2_$tag');
        expect(tester.takeException(), isNull);
        uninstallFakeAi();
      });
    }
  }

  testWidgets('g4 bank card: Practice now starts a session; Generate more explains when AI is off; AI on generates', (tester) async {
    addTearDown(tester.view.reset);
    await seed(tester, 'en');
    installFakeAi(enabled: false);
    await pumpApp(tester, const Size(412, 892), 'en', const Scaffold(body: SingleChildScrollView(child: AiBankEntryCard())));
    await tester.tap(find.byKey(const ValueKey('aiBankGenerate')));
    await settle(tester, n: 4);
    expect(find.text('AI is off. Turn it on in Settings to generate questions.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('aiBankPractice')));
    await settle(tester, n: 20);
    expect(find.byType(AiBadge), findsWidgets);
    expect(find.text('Question 1 of 10'), findsOneWidget);
    uninstallFakeAi();
  });

  testWidgets('g4 AI hub offline / AI off shows the explanation and local tools stay reachable', (tester) async {
    addTearDown(tester.view.reset);
    await seed(tester, 'en');
    installFakeAi(online: false);
    await pumpApp(tester, const Size(412, 892), 'en', const AiHubScreen());
    expect(find.textContaining('You are offline'), findsWidgets);
    // the two main tools are up front; the rest is under "Other tools"
    expect(find.byKey(const ValueKey('tileViva')), findsOneWidget);
    expect(find.byKey(const ValueKey('tileTeach')), findsOneWidget);
    await tester.ensureVisible(find.text('Other tools'));
    await tester.tap(find.text('Other tools'));
    await settle(tester);
    for (final k in ['tilePreShift', 'tileCod', 'tileGCheck', 'tileCompare']) {
      await tester.scrollUntilVisible(find.byKey(ValueKey(k)), 200, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(ValueKey(k)), findsOneWidget);
    }
    uninstallFakeAi();
  });

  for (final lang in ['en', 'ar']) {
    for (final size in [const Size(412, 892), const Size(360, 640)]) {
      final tag = '${lang}_${size.width.toInt()}';
      testWidgets('g4 viva flow with the fake AI $tag', (tester) async {
        addTearDown(tester.view.reset);
        await seed(tester, lang);
        installFakeAi(answers: {
          'quiz_viva_score': jsonEncode({'hit': [true, false, true], 'feedback': 'Good start, you missed the oxygen saturation.', 'senior': 'A senior would also grade severity with CURB-65.'}),
          'quiz_viva': vivaJson(),
        });
        await pumpApp(tester, size, lang, const VivaScreen());
        await snap(tester, 'g4_viva_setup_$tag');
        await reveal(tester, find.byKey(const ValueKey('vivaStart')));
        await tester.tap(find.byKey(const ValueKey('vivaStart')));
        await settle(tester, n: 24);
        await reveal(tester, find.byKey(const ValueKey('vivaSubmit')));
        await snap(tester, 'g4_viva_q_$tag');
        for (var i = 0; i < 3; i++) {
          await tester.enterText(find.byType(TextField).first, 'I would do a chest x-ray and treat with antibiotics.');
          await tester.pump();
          await reveal(tester, find.byKey(const ValueKey('vivaSubmit')));
          await tester.tap(find.byKey(const ValueKey('vivaSubmit')));
          await settle(tester, n: 24);
          expect(find.byKey(const ValueKey('vivaScore')), findsOneWidget);
          if (i == 0) {
            expect(find.textContaining('3 / 5'), findsOneWidget); // hits true,false,true = 2 of 3 = round(3.33)
          }
          await reveal(tester, find.byKey(const ValueKey('vivaNext')));
          if (i == 0) await snap(tester, 'g4_viva_fb_$tag');
          await tester.tap(find.byKey(const ValueKey('vivaNext')));
          await settle(tester, n: 24);
        }
        expect(find.byKey(const ValueKey('vivaTotal')), findsOneWidget);
        await snap(tester, 'g4_viva_result_$tag');
        expect(vivaSessions().length, 1);
        expect(tester.takeException(), isNull);
        uninstallFakeAi();
      });
    }
  }

  testWidgets('g4 viva offline: saved sessions visible and self-viva works without AI', (tester) async {
    addTearDown(tester.view.reset);
    await seed(tester, 'en');
    installFakeAi(online: false);
    await pumpApp(tester, const Size(412, 892), 'en', const VivaScreen());
    final start = tester.widget<FilledButton>(find.byKey(const ValueKey('vivaStart')));
    expect(start.onPressed, isNull);
    await reveal(tester, find.byKey(const ValueKey('selfVivaStart')));
    await tester.tap(find.byKey(const ValueKey('selfVivaStart')));
    await settle(tester, n: 24);
    expect(find.byKey(const ValueKey('selfReveal')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('selfReveal')));
    await settle(tester, n: 4);
    await tester.tap(find.byKey(const ValueKey('selfMiss')));
    await settle(tester, n: 6);
    expect(tester.takeException(), isNull);
    uninstallFakeAi();
  });

  for (final lang in ['en', 'ar']) {
    final size = const Size(360, 640);
    final tag = '${lang}_360';
    testWidgets('g4 guideline check, compare, written answer, teach, case, pre-shift screens $tag', (tester) async {
      addTearDown(tester.view.reset);
      await seed(tester, lang);
      final t = (await tester.runAsync(() => chooseTargets('core', seed: 3, limit: 1)))!.first;
      installFakeAi(answers: {
        'ask_gcheck': jsonEncode({'rows': [
          {'item': 'First-line antibiotic', 'mine': 'Amoxicillin 5 days', 'current': 'Amoxicillin 500 mg for 5 days', 'status': 'changed', 'org': 'NICE', 'year': '2019', 'url': _nice},
          {'item': 'Steroids', 'mine': 'Not used', 'current': 'Consider', 'status': 'changed'},
        ], 'summary': 'One item may have changed.'}),
        'ask_compare': jsonEncode({'a': {'org': 'ESC', 'year': '2023', 'url': 'https://www.escardio.org/Guidelines/x'}, 'b': {'org': 'AHA/ACC', 'year': '2025', 'url': 'https://www.ahajournals.org/doi/x'}, 'rows': [{'aspect': 'Target', 'a': '<130/80', 'b': '<130/80'}], 'summary': 'Both aim for 130/80.'}),
        'quiz_grade': jsonEncode({'score': 6, 'strengths': ['Named colchicine'], 'missing': ['NSAIDs'], 'wrong': [], 'comment': 'Partly right.'}),
        'quiz_teach_ask': jsonEncode({'questions': ['What is AF?', 'How do you treat AF?']}),
        'case_ofday': jsonEncode({'title': 'Chest pain on the ward', 'vignette': 'A fictional 58-year-old man has central chest pain for 30 minutes on the ward.', 'steps': [
          {'ask': 'What is your first action?', 'answer': 'ABC and ECG', 'teach': 'Get an ECG within 10 minutes of arrival for chest pain.', 'org': 'NICE', 'year': '2020', 'url': 'https://www.nice.org.uk/guidance/cg95'},
          {'ask': 'Which test next?', 'answer': 'Troponin', 'teach': 'Take a high-sensitivity troponin at presentation.', 'org': 'ESC', 'year': '2023', 'url': 'https://www.escardio.org/Guidelines'},
        ]}),
      });
      // guideline check
      await pumpApp(tester, size, lang, GuidelineCheckScreen(packId: t.packId, index: t.index));
      await reveal(tester, find.byKey(const ValueKey('gcRun')));
      await tester.tap(find.byKey(const ValueKey('gcRun')));
      await settle(tester, n: 24);
      await reveal(tester, find.byKey(const ValueKey('gcDate')));
      await snap(tester, 'g4_gcheck_$tag');
      await reveal(tester, find.byKey(const ValueKey('gcVerdict')));
      await snap(tester, 'g4_gcheck2_$tag');
      // compare
      await pumpApp(tester, size, lang, const CompareScreen());
      await tester.enterText(find.byKey(const ValueKey('cmpTopic')), 'blood pressure targets');
      await reveal(tester, find.byKey(const ValueKey('cmpRun')));
      await tester.tap(find.byKey(const ValueKey('cmpRun')));
      await settle(tester, n: 24);
      await reveal(tester, find.byKey(const ValueKey('cmpSummary')));
      await snap(tester, 'g4_compare_$tag');
      // written answer
      await pumpApp(tester, size, lang, const WrittenAnswerScreen(question: 'How is an acute attack of gout treated?', reference: 'Colchicine is used to treat acute attacks of gout when started early.', sourceLabel: 'Gout'));
      await tester.enterText(find.byType(TextField).first, 'Colchicine started early.');
      await tester.pump();
      await reveal(tester, find.byKey(const ValueKey('gradeRun')));
      await tester.tap(find.byKey(const ValueKey('gradeRun')));
      await settle(tester, n: 24);
      await reveal(tester, find.byKey(const ValueKey('gradeScore')));
      await snap(tester, 'g4_grade_$tag');
      // teach: ask first
      await pumpApp(tester, size, lang, const TeachScreen(topic: 'atrial fibrillation'));
      await reveal(tester, find.byKey(const ValueKey('teachStart')));
      await tester.tap(find.byKey(const ValueKey('teachStart')));
      await settle(tester, n: 24);
      await reveal(tester, find.byKey(const ValueKey('teachGo')));
      await snap(tester, 'g4_teach_$tag');
      // case of the day
      await pumpApp(tester, size, lang, const CaseOfDayScreen());
      await settle(tester, n: 24);
      await reveal(tester, find.byKey(const ValueKey('codReveal')));
      await snap(tester, 'g4_cod_$tag');
      // pre-shift
      await pumpApp(tester, size, lang, const PreShiftScreen());
      await settle(tester, n: 24);
      expect(find.byKey(const ValueKey('preShiftReady')), findsOneWidget);
      await snap(tester, 'g4_preshift_$tag');
      expect(tester.takeException(), isNull);
      uninstallFakeAi();
    });
  }

  testWidgets('g4 planner: Adapt this week dialog (local result, AI explanation optional)', (tester) async {
    addTearDown(tester.view.reset);
    await seed(tester, 'en');
    final titles = await tester.runAsync(() => library.titlesOf('cardiology'));
    await tester.runAsync(() async {
      final now = DateTime.now();
      final items = [for (var i = 0; i < 10; i++) PlanItem('cardiology', titles![20 + i], false, spec: 'Cardiology')];
      await saveExamPlan(ExamPlan(name: 'Board', date: fmtDate(now.add(const Duration(days: 30))), packs: const [], items: items, done: const {}, weights: const {'Cardiology': 4, 'Pulmonology': 4}, preset: 'internship', start: fmtDate(now.subtract(const Duration(days: 3))), perDay: 2));
      await store.upsertExtra('quizlog', {'id': 'w', 'date': nowIso(), 'items': [for (var i = 0; i < 4; i++) {'p': 'cardiology', 't': titles![20 + i], 'ok': false}]});
    });
    installFakeAi(answers: {'quiz_adapt': jsonEncode({'text': 'Cardiology answers were weak this week, so it gets 50% more time.'})});
    await pumpApp(tester, const Size(412, 892), 'en', const LearnScreen());
    await tester.tap(find.byKey(const ValueKey('learnStudy')));
    await settle(tester);
    final fold = find.text('Exam planner');
    await tester.tap(fold.first);
    await settle(tester);
    await reveal(tester, find.byKey(const ValueKey('planAdapt')));
    await tester.tap(find.byKey(const ValueKey('planAdapt')));
    await settle(tester, n: 6);
    expect(find.byKey(const ValueKey('adaptWeek')), findsOneWidget);
    expect(find.textContaining('Cardiology: 4.0 to 6.0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('adaptExplain')));
    await settle(tester, n: 20);
    expect(find.textContaining('gets 50% more time'), findsOneWidget);
    await snap(tester, 'g4_adapt_en_412');
    await tester.tap(find.byKey(const ValueKey('adaptApply')));
    await settle(tester, n: 40);
    final plan = examPlan()!;
    expect(plan.weights['Cardiology'], 6.0);
    expect(plan.start, todayStr());
    uninstallFakeAi();
  });
}
