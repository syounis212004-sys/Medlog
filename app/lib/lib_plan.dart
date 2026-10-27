import 'dart:math';

import 'core_topics.dart';
import 'data.dart';
import 'lib_quiz.dart';
import 'lib_user.dart';
import 'library.dart';

/// Board / exam planner. Nothing is generated: the plan only lists article titles of the installed packs.
/// By default it draws from the Core 250 topics, split between specialties by weights (a preset taken from a
/// public exam outline, or your own sliders), your weak spots from past quizzes first, and your rotation counts a little more.
/// Ticked items come back as short reviews after 1, 3 and 7 days; when days were missed a "Catch up" re-spreads
/// what is left. Ticks are stored in the settings file on the phone.

/// Questions suggested per article in the daily summary.
const int kPlanQuestionsPerArticle = 4;

/// Articles per day the plan is sized for.
const int kPlanArticlesPerDay = 5;

/// A ticked item is shown again this many days later (spaced repetition).
const List<int> kPlanReviewDays = [1, 3, 7];

// ------------------------------------------------------------------ blueprints (specialty shares)

/// Share of each Core 250 specialty in an exam, in percent (they do not have to add up to 100: they are normalised).
/// None of these is an official blueprint of the Jordan / Arab Board exams (those are not published as weights);
/// they are approximate mappings of public outlines onto the 18 specialties of the Core 250:
/// * USMLE-style: midpoints of the system ranges of the USMLE Step 2 CK content outline
///   (https://www.usmle.org/exam-resources/step-2-ck-materials/step-2-ck-content-outline-specifications):
///   cardiovascular 6-12, respiratory 5-10, GI 5-10, nervous 5-10, behavioral 5-10, blood/immune 5-10, MSK and skin 6-12,
///   renal/urinary + reproductive 7-13, pregnancy 3-7, endocrine 3-7, multisystem 4-8, biostatistics/ethics/professionalism
///   (the Core 250 "General" group), human development 2-4. The percentages are the USMLE's and can change.
/// * Arab Board: the ABIM internal medicine certification blueprint is used as a proxy
///   (https://www.abim.org/~/media/ABIM%20Public/Files/pdf/exam-blueprints/certification/internal-medicine.pdf):
///   cardiology 14, endocrine 9, GI 9, ID 9, pulmonary 9, rheumatology + orthopedics 9, hematology 6, oncology 6,
///   nephrology + urology 6, neurology 4, psychiatry 4, dermatology 3, OB/GYN 3, allergy/immunology 2, geriatrics 3.
/// * Internship: our own judgement, not a published outline: the five usual internship blocks (medicine, surgery,
///   paediatrics, OB/GYN, emergency) with equal weight, the medicine block split like the ABIM shares.
const Map<String, Map<String, double>> kPlanPresets = {
  'internship': {
    'Cardiology': 3.2, 'Pulmonology': 2.1, 'Gastroenterology': 2.1, 'Endocrine/Metabolic': 2.1, 'Nephrology/Fluids': 1.4,
    'Hematology/Oncology': 2.8, 'Infectious disease': 2.1, 'Neurology': 1.0, 'Psychiatry': 1.0, 'Rheum/Immunology/Derm': 2.3,
    'Emergency/Critical care/Tox': 15, 'Radiology/Lab/Skills': 2, 'General/Professional': 3, 'Pharmacology': 0,
    'Surgery': 12, 'Orthopedics': 8, 'Pediatrics': 20, 'OB/GYN': 20,
  },
  'arabboard': {
    'Cardiology': 14, 'Pulmonology': 9, 'Gastroenterology': 9, 'Endocrine/Metabolic': 9, 'Nephrology/Fluids': 6,
    'Hematology/Oncology': 12, 'Infectious disease': 9, 'Neurology': 4, 'Psychiatry': 4, 'Rheum/Immunology/Derm': 10,
    'Emergency/Critical care/Tox': 2, 'Radiology/Lab/Skills': 2, 'General/Professional': 3, 'Pharmacology': 2,
    'Surgery': 1, 'Orthopedics': 4, 'Pediatrics': 1, 'OB/GYN': 3,
  },
  'usmle': {
    'Cardiology': 9, 'Pulmonology': 7.5, 'Gastroenterology': 7.5, 'Endocrine/Metabolic': 5, 'Nephrology/Fluids': 5,
    'Hematology/Oncology': 7.5, 'Infectious disease': 3, 'Neurology': 7.5, 'Psychiatry': 7.5, 'Rheum/Immunology/Derm': 4.5,
    'Emergency/Critical care/Tox': 3, 'Radiology/Lab/Skills': 2, 'General/Professional': 6, 'Pharmacology': 2,
    'Surgery': 3, 'Orthopedics': 4.5, 'Pediatrics': 3, 'OB/GYN': 7.5,
  },
  'equal': {},
};

const List<String> kPlanPresetIds = ['internship', 'arabboard', 'usmle', 'equal'];

String planPresetName(String id) => switch (id) {
      'internship' => 'Internship',
      'arabboard' => 'Arab Board',
      'usmle' => 'USMLE-style',
      'equal' => 'Equal',
      _ => 'Custom',
    };

/// Weights of a preset for the given specialties (equal weights for "equal" / unknown ids).
Map<String, double> presetWeights(String id, Iterable<String> specialties) {
  final p = kPlanPresets[id] ?? const <String, double>{};
  return {for (final s in specialties) s: p.isEmpty ? 1.0 : (p[s] ?? 0.0)};
}

// ------------------------------------------------------------------ data

class PlanItem {
  final String packId;
  final String title;
  final bool weak;
  final String spec; // Core 250 specialty ('' for other articles)
  final bool core;
  const PlanItem(this.packId, this.title, this.weak, {this.spec = '', this.core = false});
  String get key => '$packId|$title';
  Map<String, dynamic> toJson() => {'p': packId, 't': title, if (weak) 'w': true, if (spec.isNotEmpty) 's': spec, if (core) 'c': true};
}

class ExamPlan {
  final String name;
  final String date; // yyyy-mm-dd
  final List<String> packs;
  final List<PlanItem> items;
  final Set<String> done;

  /// Specialty weights used to build the plan (empty = courses only) and the preset they came from.
  final Map<String, double> weights;
  final String preset;

  /// When the plan started and how many items a day it was sized for (empty / 0 = spread what is left over the days left).
  final String start;
  final int perDay;

  /// Day each item was ticked (yyyy-mm-dd) and the reviews already done ("key#1", "key#3", "key#7").
  final Map<String, String> doneOn;
  final Set<String> revDone;
  const ExamPlan({
    required this.name,
    required this.date,
    required this.packs,
    required this.items,
    required this.done,
    this.weights = const {},
    this.preset = '',
    this.start = '',
    this.perDay = 0,
    this.doneOn = const {},
    this.revDone = const {},
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'date': date,
        'packs': packs,
        'items': [for (final i in items) i.toJson()],
        'done': done.toList(),
        if (weights.isNotEmpty) 'weights': weights,
        if (preset.isNotEmpty) 'preset': preset,
        if (start.isNotEmpty) 'start': start,
        if (perDay > 0) 'perDay': perDay,
        if (doneOn.isNotEmpty) 'doneOn': doneOn,
        if (revDone.isNotEmpty) 'revDone': revDone.toList(),
      };

  ExamPlan copyWith({List<PlanItem>? items, Set<String>? done, String? start, int? perDay, Map<String, String>? doneOn, Set<String>? revDone}) => ExamPlan(
        name: name,
        date: date,
        packs: packs,
        items: items ?? this.items,
        done: done ?? this.done,
        weights: weights,
        preset: preset,
        start: start ?? this.start,
        perDay: perDay ?? this.perDay,
        doneOn: doneOn ?? this.doneOn,
        revDone: revDone ?? this.revDone,
      );

  static ExamPlan? fromJson(Object? j) {
    if (j is! Map) return null;
    final date = '${j['date'] ?? ''}';
    if (parseDate(date) == null) return null;
    return ExamPlan(
      name: '${j['name'] ?? ''}',
      date: date,
      packs: [for (final p in (j['packs'] as List? ?? const [])) '$p'],
      items: [
        for (final i in (j['items'] as List? ?? const []))
          if (i is Map) PlanItem('${i['p'] ?? ''}', '${i['t'] ?? ''}', i['w'] == true, spec: '${i['s'] ?? ''}', core: i['c'] == true),
      ],
      done: {for (final d in (j['done'] as List? ?? const [])) '$d'},
      weights: {
        if (j['weights'] is Map)
          for (final e in (j['weights'] as Map).entries) '${e.key}': (e.value as num?)?.toDouble() ?? 0,
      },
      preset: '${j['preset'] ?? ''}',
      start: '${j['start'] ?? ''}',
      perDay: (j['perDay'] as num?)?.toInt() ?? 0,
      doneOn: {
        if (j['doneOn'] is Map)
          for (final e in (j['doneOn'] as Map).entries) '${e.key}': '${e.value}',
      },
      revDone: {for (final d in (j['revDone'] as List? ?? const [])) '$d'},
    );
  }
}

class PlanDay {
  final DateTime date;
  final List<PlanItem> items;
  const PlanDay(this.date, this.items);
  int get articles => items.length;
  int get questions => items.length * kPlanQuestionsPerArticle;
}

/// A short review of an item studied earlier (1, 3 or 7 days after it was ticked).
class PlanReview {
  final PlanItem item;
  final int afterDays;
  final String due; // yyyy-mm-dd
  const PlanReview(this.item, this.afterDays, this.due);
  String get id => '${item.key}#$afterDays';
}

ExamPlan? examPlan() => ExamPlan.fromJson(store.settings['examPlan']);

Future<void> saveExamPlan(ExamPlan? p) async {
  if (p == null) {
    store.settings.remove('examPlan');
  } else {
    store.settings['examPlan'] = p.toJson();
  }
  await store.saveSettings();
}

/// Whole days from today to the exam (0 = today, negative = passed).
int examDaysLeft(String date, {DateTime? now}) {
  final d = parseDate(date);
  if (d == null) return 0;
  final n = now ?? DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
}

// ------------------------------------------------------------------ pure planning

/// Splits [total] places between the specialties by weight (largest remainder), never more than a specialty has,
/// and gives what a small specialty cannot use to the others. Specialties with weight 0 get nothing.
Map<String, int> allocateQuotas(Map<String, double> weights, Map<String, int> available, int total) {
  final quota = <String, int>{for (final k in weights.keys) k: 0};
  var left = min(total, available.entries.where((e) => (weights[e.key] ?? 0) > 0).fold<int>(0, (a, e) => a + e.value));
  final open = {for (final e in weights.entries) if (e.value > 0 && (available[e.key] ?? 0) > 0) e.key};
  while (left > 0 && open.isNotEmpty) {
    final sumW = open.fold<double>(0, (a, k) => a + weights[k]!);
    final shares = {for (final k in open) k: left * weights[k]! / sumW};
    var given = 0;
    final frac = <String, double>{};
    for (final k in open) {
      final room = available[k]! - quota[k]!;
      final take = min(shares[k]!.floor(), room);
      quota[k] = quota[k]! + take;
      given += take;
      frac[k] = shares[k]! - shares[k]!.floor();
    }
    var rest = left - given;
    final order = open.toList()..sort((a, b) => frac[b]!.compareTo(frac[a]!) != 0 ? frac[b]!.compareTo(frac[a]!) : weights[b]!.compareTo(weights[a]!));
    for (final k in order) {
      if (rest <= 0) break;
      if (quota[k]! < available[k]!) {
        quota[k] = quota[k]! + 1;
        rest--;
        given++;
      }
    }
    left -= given;
    if (given == 0) break;
    open.removeWhere((k) => quota[k]! >= available[k]!);
  }
  return quota;
}

/// Orders the chosen items so that every day mixes the specialties in proportion to their weight
/// (smooth weighted round robin). [lists] hold each specialty's items in the order they should be studied.
List<T> interleaveByWeight<T>(Map<String, List<T>> lists, Map<String, double> weights, Map<String, int> quotas) {
  final take = {for (final e in lists.entries) e.key: e.value.take(quotas[e.key] ?? 0).toList()};
  final idx = {for (final k in take.keys) k: 0};
  final credit = {for (final k in take.keys) k: 0.0};
  final out = <T>[];
  final total = take.values.fold<int>(0, (a, l) => a + l.length);
  while (out.length < total) {
    final live = [for (final k in take.keys) if (idx[k]! < take[k]!.length) k];
    final sumW = live.fold<double>(0, (a, k) => a + max(weights[k] ?? 1, 0.0001));
    String? best;
    for (final k in live) {
      credit[k] = credit[k]! + max(weights[k] ?? 1, 0.0001);
      if (best == null || credit[k]! > credit[best]!) best = k;
    }
    credit[best!] = credit[best]! - sumW;
    out.add(take[best]![idx[best]!]);
    idx[best] = idx[best]! + 1;
  }
  return out;
}

/// Which day of the plan an item belongs to (0 = start day), by its place in the list.
int planDayOf(ExamPlan plan, int index) => plan.perDay > 0 ? index ~/ plan.perDay : 0;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Pending items that were due before today (only for plans that know their start and items per day).
List<PlanItem> planOverdue(ExamPlan plan, {DateTime? now}) {
  final s = parseDate(plan.start);
  if (s == null || plan.perDay <= 0) return const [];
  final today = _day(now ?? DateTime.now());
  final passed = today.difference(_day(s)).inDays;
  if (passed <= 0) return const [];
  return [
    for (var i = 0; i < plan.items.length && planDayOf(plan, i) < passed; i++)
      if (!plan.done.contains(plan.items[i].key)) plan.items[i]
  ];
}

/// What is left, spread over the days from today to the day before the exam (a single day when the exam is today).
/// Plans with a start day and items per day keep their fixed days (missed items stay "overdue" until a catch-up).
List<PlanDay> planSchedule(ExamPlan plan, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final pending = [for (final i in plan.items) if (!plan.done.contains(i.key)) i];
  if (pending.isEmpty) return const [];
  final days = max(1, examDaysLeft(plan.date, now: n));
  final s = parseDate(plan.start);
  if (s != null && plan.perDay > 0) {
    final passed = max(0, today.difference(_day(s)).inDays);
    final out = <PlanDay>[];
    final byDay = <int, List<PlanItem>>{};
    for (var i = 0; i < plan.items.length; i++) {
      final d = planDayOf(plan, i);
      if (d >= passed && !plan.done.contains(plan.items[i].key)) (byDay[d] ??= <PlanItem>[]).add(plan.items[i]);
    }
    final keys = byDay.keys.toList()..sort();
    for (final d in keys) {
      out.add(PlanDay(_day(s).add(Duration(days: d)), byDay[d]!));
    }
    return out;
  }
  final per = (pending.length / days).ceil();
  final out = <PlanDay>[];
  for (var d = 0; d < days && d * per < pending.length; d++) {
    out.add(PlanDay(today.add(Duration(days: d)), pending.sublist(d * per, min(pending.length, (d + 1) * per))));
  }
  return out;
}

/// Re-spreads what is left from today to the exam (the "Catch up" button): pending items first, [perDay] recomputed.
ExamPlan catchUpPlan(ExamPlan plan, {DateTime? now}) {
  final n = _day(now ?? DateTime.now());
  final pending = [for (final i in plan.items) if (!plan.done.contains(i.key)) i];
  final doneItems = [for (final i in plan.items) if (plan.done.contains(i.key)) i];
  final days = max(1, examDaysLeft(plan.date, now: n));
  final per = max(1, (pending.length / days).ceil());
  return plan.copyWith(items: [...pending, ...doneItems], start: fmtDate(n), perDay: per);
}

/// Reviews of ticked items that are due (1, 3 and 7 days after the tick, up to the exam day), oldest first.
List<PlanReview> planReviewsDue(ExamPlan plan, {DateTime? now}) {
  final today = fmtDate(_day(now ?? DateTime.now()));
  final out = <PlanReview>[];
  for (final it in plan.items) {
    final d = plan.doneOn[it.key];
    final base = d == null ? null : parseDate(d);
    if (base == null || !plan.done.contains(it.key)) continue;
    for (final off in kPlanReviewDays) {
      final due = fmtDate(_day(base).add(Duration(days: off)));
      if (due.compareTo(today) > 0 || due.compareTo(plan.date) > 0) continue;
      if (plan.revDone.contains('${it.key}#$off')) continue;
      out.add(PlanReview(it, off, due));
    }
  }
  out.sort((a, b) => a.due.compareTo(b.due));
  return out;
}

/// Done / total per specialty (items without a specialty are grouped by course).
Map<String, (int, int)> planProgress(ExamPlan plan) {
  final out = <String, (int, int)>{};
  for (final i in plan.items) {
    final g = i.spec.isNotEmpty ? i.spec : (library.pack(i.packId)?.title ?? i.packId);
    final c = out[g] ?? (0, 0);
    out[g] = (c.$1 + (plan.done.contains(i.key) ? 1 : 0), c.$2 + 1);
  }
  return out;
}

/// Plan items from candidate lists (pure, for tests). [bySpec] must already be in study order.
List<PlanItem> composePlan({
  required List<PlanItem> weakFirst,
  required Map<String, List<PlanItem>> bySpec,
  required Map<String, double> weights,
  required int target,
}) {
  final out = <PlanItem>[...weakFirst.take(target)];
  final seen = {for (final i in out) i.key};
  final lists = {for (final e in bySpec.entries) e.key: [for (final i in e.value) if (!seen.contains(i.key)) i]};
  final quotas = allocateQuotas(weights, {for (final e in lists.entries) e.key: e.value.length}, target - out.length);
  out.addAll(interleaveByWeight(lists, weights, quotas));
  return out;
}

// ------------------------------------------------------------------ building from the installed library

/// Weak spots first, then topics not tested and not recently read. With [universe] = core (default) the topics are the
/// resolved Core 250 split by [weights]; with "all" they are the clinical-looking articles of [packs], a few courses at a
/// time. Only titles that exist in the installed packs.
Future<List<PlanItem>> buildPlanItems({
  required List<String> packs,
  required String examDate,
  DateTime? now,
  Map<String, double>? weights,
  String? universe,
}) async {
  final days = max(1, examDaysLeft(examDate, now: now));
  final target = (days * kPlanArticlesPerDay).clamp(kPlanArticlesPerDay, 400);
  final chosen = packs.where((p) => library.pack(p) != null).toList();
  final uni = universe ?? studyUniverse();
  final seen = <String>{};
  final weakItems = <PlanItem>[];
  final core = await coreByKey();
  for (final w in weakSpots()) {
    if (weakItems.length >= target) break;
    if (library.pack(w.packId) == null) continue;
    if (chosen.isNotEmpty && !chosen.contains(w.packId)) continue;
    final i = await library.indexOfTitle(w.packId, w.title);
    if (i == null) continue;
    if (seen.add('${w.packId}|${w.title}')) {
      final ct = core['${w.packId}|$i'];
      weakItems.add(PlanItem(w.packId, w.title, true, spec: ct?.specialty ?? '', core: ct != null));
    }
  }
  // weak areas found in AI sessions (viva, written answers): the best matching library article of each
  if (weakItems.length < target) {
    final ai = [...store.listOf('aiweak')]..sort((a, b) => '${b['last']}'.compareTo('${a['last']}'));
    for (final w in ai.take(6)) {
      if (weakItems.length >= target) break;
      try {
        final hits = await library.searchEx('${w['topic']}', limit: 1, concise: true);
        if (hits.isEmpty) continue;
        final h = hits.first;
        if (chosen.isNotEmpty && !chosen.contains(h.packId)) continue;
        if (seen.add('${h.packId}|${h.title}')) {
          final ct = core['${h.packId}|${h.index}'];
          weakItems.add(PlanItem(h.packId, h.title, true, spec: ct?.specialty ?? '', core: ct != null));
        }
      } catch (_) {}
    }
  }
  final tested = quizResultsByArticle(rows: 100000).keys.toSet();
  final read = {for (final r in recentArticles()) '${r['p']}|${r['t']}'};
  final rnd = Random(examDate.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff));

  if (uni == kUniverseCore && core.isNotEmpty) {
    final topics = [for (final t in core.values) if (chosen.isEmpty || chosen.contains(t.packId) || chosen.any((p) => specialtyForRotation(p) == t.specialty)) t];
    final specs = specialtiesOf(await resolveCore250());
    var w = {for (final s in specs) s: (weights?[s] ?? 1.0)};
    if (w.values.every((v) => v <= 0)) w = {for (final s in specs) s: 1.0};
    // the current rotation counts a little more
    try {
      final rot = store.currentRotation();
      final rs = rot == null ? null : specialtyForRotation('${rot['name'] ?? ''}');
      if (rs != null && w[rs] != null && w[rs]! > 0) w[rs] = w[rs]! * 1.5;
    } catch (_) {}
    final bySpec = <String, List<PlanItem>>{};
    for (final s in specs) {
      final mine = [for (final t in topics) if (t.specialty == s && !seen.contains('${t.packId}|${t.title}')) t];
      int rank(CoreTopic t) => (tested.contains('${t.packId}|${t.title}') ? 2 : 0) + (read.contains('${t.packId}|${t.title}') ? 1 : 0);
      mine.sort((a, b) {
        final c = (a.priority * 4 + rank(a)).compareTo(b.priority * 4 + rank(b));
        return c != 0 ? c : a.topic.compareTo(b.topic);
      });
      var items = [for (final t in mine) PlanItem(t.packId!, t.title!, false, spec: s, core: true)];
      if (items.length > 1) {
        // a small rotation keeps plans for different exam dates from always starting alike (same date = same plan)
        final k = rnd.nextInt(min(3, items.length));
        items = [...items.sublist(k), ...items.sublist(0, k)];
      }
      bySpec[s] = items;
    }
    return composePlan(weakFirst: weakItems, bySpec: bySpec, weights: w, target: target);
  }

  // all installed articles of the chosen courses
  final out = <PlanItem>[...weakItems];
  final lists = <List<PlanItem>>[];
  for (final p in chosen) {
    final t = await library.titlesOf(p), l = await library.leadsOf(p);
    final idx = <int>[
      for (var i = 0; i < t.length; i++)
        if (planWorthy(t[i], l[i]) && !tested.contains('$p|${t[i]}') && !read.contains('$p|${t[i]}') && !seen.contains('$p|${t[i]}')) i
    ]..shuffle(rnd);
    lists.add([for (final i in idx.take(target)) PlanItem(p, t[i], false)]);
  }
  for (var k = 0; out.length < target; k++) {
    var any = false;
    for (final l in lists) {
      if (k < l.length && out.length < target) {
        out.add(l[k]);
        any = true;
      }
    }
    if (!any) break;
  }
  return out;
}

Future<void> togglePlanDone(String key) async {
  final p = examPlan();
  if (p == null) return;
  final done = {...p.done};
  final doneOn = {...p.doneOn};
  final rev = {...p.revDone};
  if (done.remove(key)) {
    doneOn.remove(key);
    rev.removeWhere((r) => r.startsWith('$key#'));
  } else {
    done.add(key);
    doneOn[key] = todayStr();
  }
  await saveExamPlan(p.copyWith(done: done, doneOn: doneOn, revDone: rev));
}

/// Marks one short review (after 1, 3 or 7 days) as done.
Future<void> togglePlanReview(String id) async {
  final p = examPlan();
  if (p == null) return;
  final rev = {...p.revDone};
  if (!rev.remove(id)) rev.add(id);
  await saveExamPlan(p.copyWith(revDone: rev));
}

// ------------------------------------------------------------------ adapting the week (local algorithm)

/// What happened in the last 7 days against the plan.
class WeekReview {
  final int planned; // items due in the last 7 days
  final int done; // items ticked in the last 7 days
  final double? accuracy; // share of correct answers (self-tests + AI bank) in the last 7 days, null = no answers
  final int answers;
  final Map<String, (int, int)> bySpec; // specialty -> (correct, total) in the last 7 days
  const WeekReview(this.planned, this.done, this.accuracy, this.answers, this.bySpec);
}

DateTime? _logDate(Object? d) {
  final t = DateTime.tryParse('$d');
  return t?.toLocal();
}

/// Results of the last 7 days from the self-test log and the AI-bank log (items carry pack + title).
WeekReview weekReview(ExamPlan plan, {DateTime? now}) {
  final n = _day(now ?? DateTime.now());
  final from = n.subtract(const Duration(days: 6));
  bool inWeek(DateTime? t) => t != null && !_day(t).isBefore(from) && !_day(t).isAfter(n);
  final specOf = {for (final i in plan.items) i.key: i.spec};
  var ok = 0, tot = 0;
  final by = <String, (int, int)>{};
  void take(String key, bool right) {
    tot++;
    if (right) ok++;
    final s = specOf[key];
    if (s != null && s.isNotEmpty) {
      final c = by[s] ?? (0, 0);
      by[s] = (c.$1 + (right ? 1 : 0), c.$2 + 1);
    }
  }
  for (final r in store.listOf('quizlog')) {
    if (!inWeek(_logDate(r['date'])) || r['items'] is! List) continue;
    for (final it in r['items'] as List) {
      if (it is Map) take('${it['p']}|${it['t']}', it['ok'] == true);
    }
  }
  for (final r in store.listOf('aiquizlog')) {
    if (!inWeek(_logDate(r['date'])) || r['items'] is! List) continue;
    for (final it in r['items'] as List) {
      if (it is Map) take('${it['p']}|${it['title']}', it['ok'] == true);
    }
  }
  var done = 0;
  for (final e in plan.doneOn.entries) {
    if (inWeek(parseDate(e.value))) done++;
  }
  var planned = 0;
  final s = parseDate(plan.start);
  if (s != null && plan.perDay > 0) {
    final upTo = n.difference(_day(s)).inDays + 1; // days since the start, including today
    final fromDay = max(0, from.difference(_day(s)).inDays);
    for (var i = 0; i < plan.items.length; i++) {
      final d = planDayOf(plan, i);
      if (d >= fromDay && d < upTo) planned++;
    }
  } else {
    planned = min(plan.items.length, kPlanArticlesPerDay * 7);
  }
  return WeekReview(planned, done, tot == 0 ? null : ok / tot, tot, by);
}

class WeightChange {
  final String spec;
  final double before;
  final double after;
  final double? accuracy;
  const WeightChange(this.spec, this.before, this.after, this.accuracy);
}

class Rebalance {
  final Map<String, double> before;
  final Map<String, double> after;
  final List<WeightChange> changes;
  final bool behind; // fewer than half of last week's items were done
  const Rebalance(this.before, this.after, this.changes, this.behind);
  bool get isEmpty => changes.isEmpty && !behind;
}

/// Weak specialties (accuracy < 60 % over at least 3 answers) get 50 % more weight, strong ones (>= 85 % over at least 5)
/// 25 % less. Weights stay between 0.5 and 20, a weight of 0 stays 0. Deterministic and explainable.
Rebalance rebalanceWeights(ExamPlan plan, WeekReview wr) {
  final before = {...plan.weights};
  final after = {...before};
  final changes = <WeightChange>[];
  for (final e in wr.bySpec.entries) {
    final w = before[e.key];
    if (w == null || w <= 0) continue;
    final acc = e.value.$1 / e.value.$2;
    double? nw;
    if (e.value.$2 >= 3 && acc < 0.6) {
      nw = min(20.0, w * 1.5);
    } else if (e.value.$2 >= 5 && acc >= 0.85) {
      nw = max(0.5, w * 0.75);
    }
    if (nw != null && (nw - w).abs() > 0.01) {
      after[e.key] = double.parse(nw.toStringAsFixed(2));
      changes.add(WeightChange(e.key, w, after[e.key]!, acc));
    }
  }
  changes.sort((a, b) => (a.accuracy ?? 1).compareTo(b.accuracy ?? 1));
  return Rebalance(before, after, changes, wr.planned >= 4 && wr.done * 2 < wr.planned);
}

/// Re-plans what is left from today with the new weights (ticked items stay ticked, weak spots from the latest results first).
Future<ExamPlan> adaptWeekPlan(ExamPlan plan, Rebalance rb, {DateTime? now}) async {
  final items = await buildPlanItems(packs: plan.packs, examDate: plan.date, now: now, weights: rb.after.isEmpty ? null : rb.after);
  final doneKeys = plan.done;
  final doneItems = [for (final i in plan.items) if (doneKeys.contains(i.key)) i];
  final fresh = [for (final i in items) if (!doneKeys.contains(i.key)) i];
  final n = _day(now ?? DateTime.now());
  final days = max(1, examDaysLeft(plan.date, now: n));
  final per = max(1, (fresh.length / days).ceil());
  return ExamPlan(
    name: plan.name,
    date: plan.date,
    packs: plan.packs,
    items: [...fresh, ...doneItems],
    done: plan.done,
    weights: rb.after.isEmpty ? plan.weights : rb.after,
    preset: rb.changes.isEmpty ? plan.preset : 'custom',
    start: fmtDate(n),
    perDay: per,
    doneOn: plan.doneOn,
    revDone: plan.revDone,
  );
}
