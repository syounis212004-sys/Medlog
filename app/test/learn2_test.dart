import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as mm show Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/core_topics.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' as i18 show Text;
import 'package:medlog/lib_plan.dart';
import 'package:medlog/lib_quiz.dart';
import 'package:medlog/lib_user.dart';
import 'package:medlog/library.dart';
import 'package:medlog/review.dart';
import 'package:medlog/screens_learn.dart';
import 'package:medlog/screens_quiz.dart';

import 'lib2_util.dart';

QuizQ q4(String stem, List<String> opts, {int answer = 0, QKind kind = QKind.management, String expl = 'Source sentence.'}) =>
    QuizQ(kind: kind, stem: stem, options: opts, answer: answer, explanation: expl, packId: 'p', title: 'Gout — WikEM', index: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------- quality gate (synthetic)
  group('quality gate', () {
    test('a clean question passes', () {
      final q = q4('Which of these is part of the management of Gout?', ['Colchicine 0.6 mg orally', 'Dantrolene IV for 24 hours', 'Chest tube insertion', 'Oral rehydration solution']);
      expect(gateQuestion(q).ok, true, reason: '${gateQuestion(q)}');
    });
    test('duplicates, substrings, synonyms and abbreviations are rejected', () {
      expect(gateQuestion(q4('Which of these is part of the management of Gout?', ['Heart failure', 'heart failure', 'Pneumonia', 'Asthma'])).ok, false);
      expect(gateQuestion(q4('Which of these is part of the management of Gout?', ['Heart failure', 'Acute heart failure', 'Pneumonia', 'Asthma'])).ok, false);
      expect(gateQuestion(q4('Which of these is part of the management of Gout?', ['Chronic obstructive pulmonary disease', 'COPD', 'Pneumonia', 'Asthma'])).ok, false);
      expect(gateQuestion(q4('Which of these is part of the management of Gout?', ['Anaemia', 'Anemia', 'Pneumonia', 'Asthma'])).ok, false);
      expect(optionsConflate('1 hr', '1 hour'), true);
      expect(optionsConflate('Aspirin', 'Warfarin'), false);
    });
    test('answer in the stem, boilerplate, phone numbers, urls and captions are rejected', () {
      final leak = q4('Which of these is part of the management of Gout? Colchicine is typical.', ['Colchicine', 'Dantrolene', 'Chest tube', 'Rehydration']);
      expect(gateQuestion(leak).ok, false);
      expect(gateQuestion(q4('Call the Emergency Operations Center at 770-488-7100 to report this event.', ['A', 'B', 'C', 'D'], kind: QKind.management)).ok, false);
      expect(gateQuestion(q4('Which of these is part of the management of Gout? See www.cdc.gov for details', ['Colchicine', 'Dantrolene', 'Chest tube', 'Rehydration'])).ok, false);
      expect(gateQuestion(q4('Figure 2. The knee joint with the patella (left) and the femur (right) shown here', ['Colchicine', 'Dantrolene', 'Chest tube', 'Rehydration'], kind: QKind.trueFalse)).ok, false);
      expect(gateQuestion(QuizQ(kind: QKind.cloze, stem: 'National Library of ____ is a boilerplate source line of MedlinePlus pages', options: const ['Medicine', 'Surgery', 'Pharmacy', 'Nursing'], answer: 0, explanation: 'x', packId: 'p', title: 't', index: 0)).ok, false);
      expect(looksLikeCaption('Gouty tophus of the left metatarsophalangeal joint (left), arrow'), true);
      expect(hasBoilerplate('For more information visit our website'), true);
    });
    test('blank kinds need exactly one blank; generic findings and length cues cost points', () {
      final noBlank = QuizQ(kind: QKind.number, stem: 'Glucagon 1 mg is given subcutaneously or intramuscularly in hypoglycemia', options: const ['1 mg', '10 mg', '4 mg', '2 mg'], answer: 0, explanation: 'x', packId: 'p', title: 't', index: 0);
      expect(gateQuestion(noBlank).ok, false);
      final generic = q4('Which of these is a recognised feature of Gout?', ['Fatigue', 'Podagra of the big toe', 'Tophi on the ears', 'Urate crystals in joints'], kind: QKind.symptom);
      expect(gateQuestion(generic).score < 100, true);
      final cue = q4('Which of these is part of the management of Gout?', ['Rest', 'Colchicine given orally with food during the first twenty four hours of the attack', 'Ice', 'Diet'], answer: 1);
      expect(gateQuestion(cue).ok, false);
    });
    test('true / false keeps its two options', () {
      final tf = QuizQ(kind: QKind.trueFalse, stem: 'Gout: Uric acid crystals deposit in the joints and cause attacks of pain.', options: const ['True', 'False'], answer: 0, explanation: 'Uric acid crystals deposit in the joints and cause attacks of pain.', packId: 'p', title: 'Gout', index: 0);
      expect(gateQuestion(tf).ok, true, reason: '${gateQuestion(tf)}');
      final bad = QuizQ(kind: QKind.trueFalse, stem: tf.stem, options: const ['Yes', 'No'], answer: 0, explanation: 'x', packId: 'p', title: 'Gout', index: 0);
      expect(gateQuestion(bad).ok, false);
    });
    test('numbers with units: only clean single facts', () {
      final a = singleQuantity('Calcium chloride 1 gram IV over 2 minutes');
      expect(a, null); // two quantities
      final b = singleQuantity('Hydrocortisone 100 mg IV bolus: give immediately')!;
      expect(b.text, '100 mg');
      expect(b.unit, 'mg');
      final r = singleQuantity('Give 0.3–0.5 mg of epinephrine intramuscularly in anaphylaxis')!;
      expect(r.range, true);
      expect(singleQuantity('In about 30%-40% of cases the cause stays unknown'), null);
      expect(singleQuantity('The trial of 120 patients showed 12 mg benefit'), null);
      expect(numberSentenceOk('Defined as a potassium above 5.5 mEq/L on a blood sample in the emergency department.'), true);
      expect(numberSentenceOk('It affects about 5% of people worldwide each year in the United States.'), false);
      expect(unitClass('hours').$1, unitClass('days').$1);
      expect(unitClass('mg').$1 == unitClass('mmhg').$1, false);
    });
  });

  // ---------------------------------------------------------------- core 250 (synthetic matcher)
  group('core 250 matcher', () {
    test('the asset has 250 topics in 18 specialties with patterns', () async {
      final ts = parseCoreTopics(File('assets/library/core250.json').readAsStringSync());
      expect(ts.length, 250);
      expect(specialtiesOf(ts).length, 18);
      expect(ts.every((t) => t.patterns.isNotEmpty && t.priority >= 1), true);
      expect(ts.where((t) => t.topic == 'heart failure').first.patterns.contains('Heart failure'), true);
      expect((await loadCoreTopics()).length, 250);
    });
    test('concise sources beat long course articles and patient leaflets; exact titles beat containment', () {
      final ix = CoreIndex();
      ix.add(CoreCand('cardiology', 1, 'Heart failure', 'Wikipedia', false));
      ix.add(CoreCand('clinical-essentials', 2, 'Heart failure — WikEM', 'WikEM', true));
      ix.add(CoreCand('medlineplus', 3, 'Heart Failure', 'MedlinePlus', false));
      ix.add(CoreCand('clinical-essentials', 4, 'Heart failure — Wikipedia', 'Wikipedia', true));
      ix.add(CoreCand('cardiology', 5, 'Heart failure with preserved ejection fraction', 'Wikipedia', false));
      final t = CoreTopic('heart failure', 'Cardiology', 1, ['Heart failure']);
      final sl = shortlist(t, ix);
      expect(sl.first.title, 'Heart failure — WikEM');
      expect(sl.map((c) => c.title).contains('Heart failure with preserved ejection fraction'), false); // exact matches only when there are some
      expect(sl.last.source, 'MedlinePlus');
      // containment only for multi-word patterns and at most one extra word
      final ix2 = CoreIndex()
        ..add(CoreCand('p', 1, 'Catecholaminergic polymorphic ventricular tachycardia', 'Wikipedia', false))
        ..add(CoreCand('p', 2, 'Acute heart failure syndrome', 'Wikipedia', false));
      expect(shortlist(CoreTopic('vt', 'Cardiology', 1, ['Ventricular tachycardia']), ix2), isEmpty);
      expect(shortlist(CoreTopic('hf', 'Cardiology', 1, ['Heart failure syndrome']), ix2).length, 1);
      expect(sizeAdjust(500) < sizeAdjust(8000), true);
      expect(sizeAdjust(80000) < sizeAdjust(8000), true);
      expect(specialtyForRotation('Orthopedics'), 'Orthopedics');
      expect(specialtyForRotation('Internal Medicine'), null);
    });
  });

  // ---------------------------------------------------------------- planner (pure)
  group('planner pure', () {
    String inDays(int n) => fmtDate(DateTime.now().add(Duration(days: n)));

    test('quotas follow the weights, respect what exists and skip weight 0', () {
      final q = allocateQuotas({'A': 3, 'B': 1, 'C': 0}, {'A': 100, 'B': 100, 'C': 100}, 20);
      expect(q['A'], 15);
      expect(q['B'], 5);
      expect(q['C'], 0);
      final small = allocateQuotas({'A': 3, 'B': 1}, {'A': 4, 'B': 100}, 20);
      expect(small['A'], 4);
      expect(small['B'], 16); // what A cannot use goes to B
      expect(allocateQuotas({'A': 1}, {'A': 3}, 20)['A'], 3);
      expect(allocateQuotas({'A': 1, 'B': 1, 'C': 1}, {'A': 9, 'B': 9, 'C': 9}, 10).values.fold<int>(0, (a, b) => a + b), 10);
    });
    test('interleaving mixes specialties in proportion', () {
      final lists = {'A': List.generate(10, (i) => 'A$i'), 'B': List.generate(10, (i) => 'B$i')};
      final out = interleaveByWeight(lists, {'A': 3, 'B': 1}, {'A': 6, 'B': 2});
      expect(out.length, 8);
      expect(out.take(4).where((e) => e.startsWith('A')).length, 3);
      expect(out.where((e) => e.startsWith('B')).length, 2);
    });
    test('presets exist, are justified and normalise', () {
      for (final id in kPlanPresetIds) {
        final w = presetWeights(id, kPlanPresets['usmle']!.keys);
        expect(w.length, 18);
        expect(w.values.any((v) => v > 0), true);
      }
      expect(presetWeights('equal', ['A', 'B']).values.toSet(), {1.0});
      expect(kPlanPresets['arabboard']!['Cardiology']! > kPlanPresets['arabboard']!['Psychiatry']!, true); // ABIM: cardiology 14, psychiatry 4
      expect(kPlanPresets['internship']!['Pediatrics']! > kPlanPresets['internship']!['Neurology']!, true);
      expect(planPresetName('usmle'), 'USMLE-style');
    });
    test('compose: weak spots first, weights decide the mix', () {
      PlanItem it(String s, int i) => PlanItem('p', '$s$i', false, spec: s, core: true);
      final plan = composePlan(
        weakFirst: [const PlanItem('p', 'W0', true, spec: 'A', core: true)],
        bySpec: {'A': [for (var i = 0; i < 30; i++) it('A', i)], 'B': [for (var i = 0; i < 30; i++) it('B', i)]},
        weights: {'A': 4, 'B': 1},
        target: 21,
      );
      expect(plan.length, 21);
      expect(plan.first.weak, true);
      expect(plan.where((i) => i.spec == 'A').length, 17);
      expect(plan.map((i) => i.key).toSet().length, 21);
    });
    test('missed days: overdue items and catch up', () {
      final items = [for (var i = 0; i < 20; i++) PlanItem('p', 'T$i', false, spec: 'A')];
      final plan = ExamPlan(name: '', date: inDays(10), packs: const [], items: items, done: {'p|T0', 'p|T1'}, start: inDays(-3), perDay: 5);
      final over = planOverdue(plan);
      expect(over.length, 13); // days 0..2 = 15 items, 2 done
      expect(over.first.title, 'T2');
      final days = planSchedule(plan);
      expect(days.first.items.first.title, 'T15'); // today is day 3
      final c = catchUpPlan(plan);
      expect(c.start, todayStr());
      expect(c.perDay, 2); // 18 pending over 10 days -> ceil(1.8)
      expect(planOverdue(c), isEmpty);
      expect(c.items.take(18).every((i) => !c.done.contains(i.key)), true);
      expect(planSchedule(c).first.items.length, 2);
      expect(planSchedule(c).fold<int>(0, (a, d) => a + d.items.length), 18);
      // legacy plans (no start day) keep the old behaviour
      expect(planOverdue(ExamPlan(name: '', date: inDays(5), packs: const [], items: items, done: const {})), isEmpty);
    });
    test('spaced repetition: a ticked item comes back after 1, 3 and 7 days (not after the exam)', () {
      final items = [const PlanItem('p', 'A', false, spec: 'X'), const PlanItem('p', 'B', false, spec: 'Y')];
      final d0 = DateTime(2026, 11, 1);
      ExamPlan plan(String date) => ExamPlan(name: '', date: date, packs: const [], items: items, done: {'p|A'}, doneOn: {'p|A': fmtDate(d0)});
      expect(planReviewsDue(plan('2026-12-30'), now: d0), isEmpty);
      expect(planReviewsDue(plan('2026-12-30'), now: d0.add(const Duration(days: 1))).map((r) => r.afterDays), [1]);
      expect(planReviewsDue(plan('2026-12-30'), now: d0.add(const Duration(days: 3))).map((r) => r.afterDays), [1, 3]);
      expect(planReviewsDue(plan('2026-12-30'), now: d0.add(const Duration(days: 8))).map((r) => r.afterDays), [1, 3, 7]);
      final withRev = plan('2026-12-30').copyWith(revDone: {'p|A#1', 'p|A#3'});
      expect(planReviewsDue(withRev, now: d0.add(const Duration(days: 8))).map((r) => r.afterDays), [7]);
      expect(planReviewsDue(plan('2026-11-02'), now: d0.add(const Duration(days: 8))).map((r) => r.afterDays), [1]); // exam on day 1
      expect(planProgress(plan('2026-12-30')), {'X': (1, 1), 'Y': (0, 1)});
    });
    test('the plan round-trips through json with all new fields', () {
      final p = ExamPlan(
        name: 'Board', date: '2027-01-10', packs: const ['cardiology'], items: const [PlanItem('p', 'A', true, spec: 'Cardiology', core: true)], done: {'p|A'},
        weights: const {'Cardiology': 14.0}, preset: 'arabboard', start: '2026-11-01', perDay: 5, doneOn: const {'p|A': '2026-11-02'}, revDone: {'p|A#1'});
      final q = ExamPlan.fromJson(jsonDecode(jsonEncode(p.toJson())))!;
      expect(q.weights, {'Cardiology': 14.0});
      expect(q.preset, 'arabboard');
      expect(q.perDay, 5);
      expect(q.doneOn['p|A'], '2026-11-02');
      expect(q.revDone, {'p|A#1'});
      expect(q.items.first.spec, 'Cardiology');
      expect(q.items.first.core, true);
    });
  });

  // ---------------------------------------------------------------- real packs
  group('real packs', () {
    setUpAll(() async {
      await initStoreLight(dxs: const ['Heart failure', 'Gout']);
      final cat = jsonDecode(File('../library/catalog.json').readAsStringSync()) as Map;
      final base = installPacks([for (final e in cat['packs'] as List) if (e['kind'] != 'images') e['id'] as String]);
      await library.init(base);
    });

    test('core 250 resolves to installed articles, concise sources first', () async {
      final r = await resolveCore250();
      final ok = r.where((t) => t.resolved).toList();
      expect(r.length, 250);
      expect(ok.length >= 225, true, reason: 'resolved ${ok.length}');
      final wiki = ok.where((t) => library.sourceOf(t.packId!, t.title!) != 'MedlinePlus').length;
      expect(wiki >= ok.length - 12, true);
      final hf = ok.firstWhere((t) => t.topic == 'heart failure');
      expect(stripSource(hf.title!).toLowerCase().contains('heart failure'), true);
      for (final t in ok.take(40)) {
        expect(await library.indexOfTitle(t.packId!, t.title!), t.index);
      }
      expect(studyUniverse(), kUniverseCore);
      await setStudyUniverse(kUniverseAll);
      expect(studyUniverse(), kUniverseAll);
      expect(defaultQuizSource(), QuizSource.all);
      await setStudyUniverse(kUniverseCore);
      expect(defaultQuizSource(), QuizSource.core);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('default quiz comes from Core 250 topics and every question passes the gate', () async {
      final core = await coreByKey();
      final seenKinds = <QKind>{};
      var n = 0, tfTrue = 0, tfFalse = 0;
      for (final seed in [1, 2, 3, 4]) {
        final qs = await buildQuiz(count: 20, seed: seed);
        expect(lastQuizReport.source, QuizSource.core);
        expect(qs.length >= 15, true, reason: 'seed $seed gave ${qs.length}');
        for (final q in qs) {
          n++;
          seenKinds.add(q.kind);
          expect(core.containsKey('${q.packId}|${q.index}'), true, reason: 'not a core topic: ${q.title}');
          final g = gateQuestion(q);
          expect(g.ok, true, reason: '${g} ${q.stem}');
          expect(q.group.isNotEmpty, true);
          expect(q.options.toSet().length, q.options.length);
          expect(hasBoilerplate(q.stem), false);
          expect(RegExp(r'\d{3}[-. ]\d{3}[-. ]\d{4}|https?:|www\.').hasMatch(q.stem + q.options.join(' ')), false);
          if (q.kind == QKind.trueFalse) {
            q.correct == 'True' ? tfTrue++ : tfFalse++;
            expect(q.options, ['True', 'False']);
          }
          if (q.kind == QKind.definition) expect(q.stem.contains('____'), true);
          if (q.kind == QKind.number) {
            expect('____'.allMatches(q.stem).length, 1);
            expect(q.options.every((o) => RegExp(r'\d').hasMatch(o)), true);
          }
        }
      }
      expect(n >= 60, true);
      expect(seenKinds.containsAll({QKind.management, QKind.definition, QKind.trueFalse, QKind.treatment}), true, reason: '$seenKinds');
      expect(seenKinds.contains(QKind.number), true, reason: '$seenKinds');
      print('T/F true $tfTrue false $tfFalse');
      expect(tfFalse > 0 && tfTrue <= tfFalse * 2 + 2, true, reason: 'T $tfTrue F $tfFalse');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('wrong options come from other articles of the same specialty and kind of text', () async {
      final qs = <QuizQ>[];
      for (final seed in [11, 12, 13]) {
        qs.addAll(await buildQuiz(count: 20, seed: seed, level: QuizLevel.medium));
      }
      final defs = qs.where((q) => q.kind == QKind.definition).toList();
      expect(defs.length >= 5, true);
      final core = await coreByKey();
      final byTitle = {for (final t in core.values) stripSource(t.title!).replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim().toLowerCase(): t.specialty};
      var same = 0, total = 0;
      for (final q in defs) {
        for (var i = 0; i < q.options.length; i++) {
          if (i == q.answer) continue;
          final sp = byTitle[q.options[i].toLowerCase()];
          if (sp != null) {
            total++;
            if (sp == q.group) same++;
          }
        }
      }
      expect(total > 0 && same / total >= 0.6, true, reason: 'same specialty $same / $total');
      // numbers: options share the kind of unit
      for (final q in qs.where((q) => q.kind == QKind.number)) {
        final classes = {for (final o in q.options) unitClass(singleQuantity('Give $o now')?.unit ?? 'x').$1};
        expect(classes.length, 1, reason: '${q.options}');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('missed question: one review card, scheduled today, again sooner on a second miss', () async {
      final qs = await buildQuiz(count: 6, seed: 21);
      final q = qs.first;
      expect(quizAutoCards(), true);
      final before = store.listOf('libcards').length;
      expect(await missedCard(front: q.cardFront, back: q.cardBack, source: q.title, packId: q.packId, title: q.title), true);
      expect(store.listOf('libcards').length, before + 1);
      final item = buildReviewItems().firstWhere((i) => i.kind == ReviewKind.library && i.front == q.cardFront);
      expect(ReviewEngine.isDue(item), true);
      expect(item.back.contains(q.correct), true);
      // answered well: pushed away; missed again: due today again, still one card
      await ReviewEngine.grade(item, 3);
      expect(ReviewEngine.isDue(item), false);
      expect(await missedCard(front: q.cardFront, back: q.cardBack, source: q.title, packId: q.packId, title: q.title), false);
      expect(store.listOf('libcards').length, before + 1);
      expect(ReviewEngine.isDue(item), true);
      expect(ReviewEngine.stateOf(item.key)!['box'], 0);
      await setQuizAutoCards(false);
      expect(quizAutoCards(), false);
      await setQuizAutoCards(true);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('practice again: only the chosen article, several kinds', () async {
      final core = (await resolveCore250()).where((t) => t.resolved && t.topic == 'hyperkalemia').first;
      final qs = await buildQuiz(count: 5, seed: 3, articles: [QuizPick(core.packId!, core.index!, core.title!, 1)]);
      expect(qs.isNotEmpty, true);
      expect(qs.every((q) => q.packId == core.packId && q.index == core.index), true);
      print('practice kinds: ${qs.map((q) => q.kind.name)} ${quizTimings}');
      expect(qs.map((q) => q.kind).toSet().length >= 2, true, reason: '${qs.map((q) => q.kind)}');
      expect(qs.map((q) => q.stem).toSet().length, qs.length);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('planner on Core 250: blueprint weights, weak spots first, deterministic, only installed titles', () async {
      final specs = specialtiesOf(await resolveCore250());
      final until = fmtDate(DateTime.now().add(const Duration(days: 20)));
      final arab = await buildPlanItems(packs: const [], examDate: until, weights: presetWeights('arabboard', specs), universe: kUniverseCore);
      expect(arab.length, 100);
      expect(arab.every((i) => i.core && i.spec.isNotEmpty), true);
      expect(arab.map((i) => i.key).toSet().length, arab.length);
      final eq = await buildPlanItems(packs: const [], examDate: until, weights: presetWeights('equal', specs), universe: kUniverseCore);
      int share(List<PlanItem> l, String s) => l.where((i) => i.spec == s).length;
      expect(share(arab, 'Cardiology') > share(eq, 'Cardiology'), true);
      expect(share(arab, 'Cardiology') > share(arab, 'Psychiatry'), true);
      expect(share(arab, 'Surgery') < share(eq, 'Surgery'), true);
      // days mix the specialties: the first day is not one specialty
      expect(arab.take(5).map((i) => i.spec).toSet().length >= 3, true);
      // same inputs, same plan
      final again = await buildPlanItems(packs: const [], examDate: until, weights: presetWeights('arabboard', specs), universe: kUniverseCore);
      expect([for (final i in again) i.key], [for (final i in arab) i.key]);
      for (final i in arab.take(30)) {
        expect(await library.indexOfTitle(i.packId, i.title), isNotNull);
      }
      // weak spots go first
      final core = (await resolveCore250()).where((t) => t.resolved && t.topic == 'gout').first;
      await store.upsertExtra('quizlog', {
        'id': 'ql1', 'date': nowIso(), 'pack': core.packId, 'n': 1, 'correct': 0, 'wrong': [core.title],
        'items': [{'p': core.packId, 't': core.title, 'ok': false}],
      });
      final weak = await buildPlanItems(packs: const [], examDate: until, weights: presetWeights('usmle', specs), universe: kUniverseCore);
      expect(weak.first.title, core.title);
      expect(weak.first.weak, true);
      expect(weak.first.core, true);
      // a chosen course limits the topics to that specialty
      final ortho = await buildPlanItems(packs: const ['orthopedics'], examDate: until, weights: presetWeights('equal', specs), universe: kUniverseCore);
      expect(ortho.where((i) => !i.weak).every((i) => i.spec == 'Orthopedics' || i.packId == 'orthopedics'), true);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('ticking stores the day; the review appears the next day', () async {
      final plan = ExamPlan(name: 'B', date: fmtDate(DateTime.now().add(const Duration(days: 30))), packs: const [], items: const [PlanItem('p', 'A', false, spec: 'X'), PlanItem('p', 'B', false, spec: 'X')], done: const {});
      await saveExamPlan(plan);
      await togglePlanDone('p|A');
      expect(examPlan()!.doneOn['p|A'], todayStr());
      expect(planReviewsDue(examPlan()!), isEmpty);
      expect(planReviewsDue(examPlan()!, now: DateTime.now().add(const Duration(days: 1))).length, 1);
      await togglePlanReview('p|A#1');
      expect(examPlan()!.revDone, {'p|A#1'});
      await togglePlanDone('p|A');
      expect(examPlan()!.doneOn, isEmpty);
      expect(examPlan()!.revDone, isEmpty);
      await saveExamPlan(null);
    });
  });

  // ---------------------------------------------------------------- screens
  group('screens', () {
    testWidgets('Learn: Flashcards first, Study instead of Review, no extra buttons floating', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 900);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => initStoreLight());
      await tester.pumpWidget(const MaterialApp(home: LearnScreen()));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final tabs = tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text).toList();
      expect(tabs.first, 'Flashcards');
      expect(tabs.contains('Study'), true);
      expect(tabs.contains('Review'), false);
      expect(tabs.contains('Procedures'), true);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byKey(const ValueKey('flashDue')), findsOneWidget);
      expect(find.text('Add missed questions to review cards'), findsOneWidget);
      // the other tabs have no floating buttons either
      for (final name in ['Procedures', 'Notebook', 'Questions']) {
        await tester.tap(find.widgetWithText(Tab, name));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(FloatingActionButton), findsNothing, reason: name);
      }
    });

    testWidgets('quiz setup has the study universe and the review-card switch; the counter keeps its order in Arabic', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 900);
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await initStoreLight(settings: const {'lang': 'ar'});
        await library.init(installPacks(['clinical-essentials', 'cardiology']));
        await resolveCore250(force: true);
      });
      await tester.pumpWidget(const MaterialApp(home: QuizScreen(autoStart: true, count: 5)));
      var ok = false;
      for (var k = 0; k < 600 && !ok; k++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump(const Duration(milliseconds: 25));
        ok = find.byType(OutlinedButton).evaluate().isNotEmpty;
      }
      expect(ok, true);
      final counters = tester.widgetList<mm.Text>(find.byType(mm.Text)).where((t) => RegExp(r'^\d+ / \d+$').hasMatch(t.data ?? '')).toList();
      expect(counters.length, 1);
      expect(counters.first.textDirection, TextDirection.ltr);
      expect(counters.first.data, '1 / 5');
    });

    testWidgets('quiz setup shows the study universe and the switch', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1400);
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await initStoreLight();
        await library.init(installPacks(['clinical-essentials']));
      });
      await tester.pumpWidget(const MaterialApp(home: QuizScreen()));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('Core 250 (recommended)'), findsWidgets);
      expect(find.text('All installed articles'), findsWidgets);
    });
  });
}

