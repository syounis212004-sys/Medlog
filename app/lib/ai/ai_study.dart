import 'dart:convert';
import 'dart:math';

import '../core_topics.dart';
import '../data.dart';
import '../lib_plan.dart';
import '../lib_user.dart';
import '../library.dart';
import '../review.dart';
import 'ai_api.dart';
import 'ai_doc_api.dart';
import 'ai_prefs.dart';
import 'ai_quiz.dart';
import 'ai_study_prompts.dart';

/// Study features of the optional AI layer (logic only; screens are in screens_ai_study.dart):
///  * daily study coach (local plan + optional AI note),
///  * viva / OSCE examiner, Socratic teaching, guideline check, guideline comparison, case of the day,
///  * pre-shift quiz, written-answer grading, weak-spot memory.
/// Rules: the app works fully without AI (every feature has a local fallback), AI only suggests, nothing is stated
/// without a source (points without a valid source are dropped), fictional patients only.

const String kAiVivaList = 'aiviva';
const String kAiGCheckList = 'aigcheck';
const String kAiGradeList = 'aigrade';
const String kAiWeakList = 'aiweak';
const String kAiTeachList = 'aiteach';
const String kAiCodList = 'aicod';

// ------------------------------------------------------------------ helpers

Map<String, dynamic>? studyJson(AiResult r) {
  if (r.json != null) return r.json;
  var t = r.text.trim();
  if (t.isEmpty) return null;
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
  if (fence != null) t = fence.group(1)!.trim();
  final a = t.indexOf('{'), b = t.lastIndexOf('}');
  if (a < 0 || b <= a) return null;
  try {
    final j = jsonDecode(t.substring(a, b + 1));
    return j is Map ? Map<String, dynamic>.from(j) : null;
  } catch (_) {
    return null;
  }
}

String _s(Object? v) => v == null ? '' : '$v'.trim();
List<String> _strs(Object? v) => v is List ? [for (final e in v) _s(e)].where((e) => e.isNotEmpty).toList() : <String>[];
List<Map> _maps(Object? v) => v is List ? [for (final e in v) if (e is Map) e] : <Map>[];

Future<AiResult> _go(AiRequest r, AiRunner? runner) => runner != null ? runner(r) : Ai.run(r);

/// Why a study request produced nothing, for the UI: 'off' | 'offline' | 'error' | 'cancelled' | ''.
String studyFailure(AiResult r) => r.ok ? '' : (r.cancelled ? 'cancelled' : (r.offline ? (Ai.enabled ? 'offline' : 'off') : 'error'));

/// A source given by the model for one statement.
class StudySource {
  final String org, year, url, quote, title;
  const StudySource({this.org = '', this.year = '', this.url = '', this.quote = '', this.title = ''});
  bool get isEmpty => org.isEmpty && year.isEmpty && url.isEmpty && quote.isEmpty && title.isEmpty;
  String get label {
    final a = [if (title.isNotEmpty) title, [org, year].where((e) => e.isNotEmpty).join(' ')].where((e) => e.isNotEmpty).join(' · ');
    return a.isNotEmpty ? a : url;
  }

  Map<String, dynamic> toJson() => {'org': org, 'year': year, 'url': url, 'quote': quote, 'title': title};
  static StudySource of(Map m) => StudySource(org: _s(m['org']), year: _s(m['year']), url: _s(m['url']), quote: _s(m['quote']), title: _s(m['stitle'] ?? m['source']));
  static StudySource fromJson(Object? j) => j is Map ? StudySource(org: _s(j['org']), year: _s(j['year']), url: _s(j['url']), quote: _s(j['quote']), title: _s(j['title'])) : const StudySource();
  AiCite get cite => AiCite(label: label, org: org, year: year, url: url);
}

/// Source rule shared by every generated statement: returns the source when it is acceptable under [mode], else null.
///  * library: the quote must be inside one of the supplied [passages] (normalised);
///  * web / custom: organisation + year are required, and an address (if given) must be https on the allow-list;
///  * model: allowed, marked unverified by the UI.
StudySource? acceptSource(Map m, {required String mode, List<AiPassage> passages = const []}) {
  final s = StudySource.of(m);
  final hasPassages = passages.isNotEmpty;
  if (mode == 'model' && !hasPassages) return s;
  if (hasPassages && s.quote.isNotEmpty) {
    final nq = aiNorm(s.quote);
    if (nq.length >= 15 && passages.any((p) => aiNorm(p.text).contains(nq))) {
      return StudySource(org: s.org, year: s.year, url: s.url, quote: s.quote, title: s.title.isNotEmpty ? s.title : passages.firstWhere((p) => aiNorm(p.text).contains(nq)).title);
    }
  }
  if (mode == 'library') return null;
  if (mode == 'web' || mode == 'custom') {
    if (s.org.isEmpty || s.year.isEmpty) return null;
    if (s.url.isNotEmpty) {
      final c = AiSources.verify([s.cite], allow: AiSources.allowedFor(mode)).items.first;
      if (c.status == CiteStatus.notAllowed) return null;
    }
    return s;
  }
  return hasPassages ? null : s;
}

/// Request defaults of the study features.
AiRequest studyRequest(String feature, String task, String prompt, {AiLevel level = AiLevel.none, bool json = true, int maxTokens = 1800, String? forceMode, double temperature = 0.3, String? cacheKey}) =>
    AiRequest(
      feature: feature,
      system: StudyPrompts.system(task, forceMode: forceMode),
      prompt: prompt,
      level: level,
      expectJson: json,
      maxTokens: maxTokens,
      temperature: temperature,
      search: StudyPrompts.search(forceMode: forceMode),
      cacheKey: cacheKey,
    );

String _fence(String label, String text) => aiFence(label, text);

/// Library passages about a topic (public licensed text) for grounding; empty when the library has nothing.
Future<List<AiPassage>> passagesForTopic(String topic, {int articles = 2, int sections = 2, String? packId}) async {
  if (!library.ready || topic.trim().isEmpty) return const [];
  final hits = await library.searchEx(topic.trim(), packId: packId, limit: 6, concise: true);
  final out = <AiPassage>[];
  for (final h in hits.take(articles)) {
    out.addAll(await passagesOf(h.packId, h.index, maxSections: sections, maxChars: 1500));
  }
  return out;
}

String _passageBlock(List<AiPassage> ps) {
  final b = StringBuffer();
  for (var i = 0; i < ps.length; i++) {
    b.writeln('Passage ${i + 1}: ${stripSource(ps[i].title)} / ${ps[i].section.isEmpty ? 'Overview' : ps[i].section}');
    b.writeln(_fence('PASSAGE ${i + 1}', ps[i].text));
  }
  return b.toString();
}

// ------------------------------------------------------------------ weak-spot memory

String _topicKey(String t) => aiNorm(t).replaceAll(' ', '_');

/// Topics the learner struggled with in AI sessions (viva, written answers, teach-me): they feed the coach and the planner.
Future<void> noteWeakAreas(List<String> topics, {String src = 'viva'}) async {
  for (final t in topics) {
    final name = t.trim();
    if (name.isEmpty) continue;
    final id = _topicKey(name);
    if (id.isEmpty) continue;
    final old = store.listOf(kAiWeakList).where((e) => e['id'] == id).toList();
    final n = old.isEmpty ? 1 : ((old.first['n'] as num?)?.toInt() ?? 1) + 1;
    await store.upsertExtra(kAiWeakList, {'id': id, 'topic': name, 'n': n, 'last': nowIso(), 'src': src});
  }
}

/// Weak areas, most recent first.
List<Map<String, dynamic>> aiWeakAreas() {
  final l = [for (final e in store.listOf(kAiWeakList)) Map<String, dynamic>.from(e)];
  l.sort((a, b) => '${b['last']}'.compareTo('${a['last']}'));
  return l;
}

Future<void> clearWeakArea(String topic) => store.removeExtra(kAiWeakList, _topicKey(topic));

/// All weak topics the app knows (quiz weak spots, AI bank, AI sessions): names only, no repeats.
List<String> allWeakTopicNames() {
  final seen = <String>{};
  final out = <String>[];
  void add(String t) {
    final k = _topicKey(stripSource(t));
    if (k.isNotEmpty && seen.add(k)) out.add(stripSource(t));
  }
  for (final w in weakSpots()) {
    add(w.title);
  }
  for (final t in aiWeakTopics()) {
    add(t.$2);
  }
  for (final w in aiWeakAreas()) {
    add('${w['topic']}');
  }
  return out;
}

// ------------------------------------------------------------------ daily coach

class CoachStep {
  final String kind; // cards | weak | plan | rotation | core
  final String title;
  final String detail;
  final int minutes;
  final String packId;
  final String articleTitle;
  const CoachStep(this.kind, this.title, this.detail, this.minutes, {this.packId = '', this.articleTitle = ''});
}

class CoachPlan {
  final List<CoachStep> steps;
  final int due; // flashcards due
  final int weak; // weak topics
  final int planToday; // items of today's exam-plan day
  final int daysToExam; // -1 = no plan
  final String? rotation;
  final int budget;
  const CoachPlan({this.steps = const [], this.due = 0, this.weak = 0, this.planToday = 0, this.daysToExam = -1, this.rotation, this.budget = 25});
  int get minutes => steps.fold<int>(0, (a, s) => a + s.minutes);
  bool get isEmpty => steps.isEmpty;
}

/// The plan of today built ONLY from what is on the phone: due flashcards, weak spots, the exam plan, the rotation, Core 250.
Future<CoachPlan> buildCoachPlan({int minutes = 25, DateTime? now}) async {
  final steps = <CoachStep>[];
  final due = ReviewEngine.dueCount();
  final weak = weakSpots();
  final weakNames = allWeakTopicNames();
  final plan = examPlan();
  var planToday = 0;
  List<PlanItem> todayItems = const [];
  if (plan != null) {
    final days = planSchedule(plan, now: now);
    if (days.isNotEmpty) {
      todayItems = days.first.items;
      planToday = todayItems.length;
    }
  }
  final cand = <CoachStep>[];
  if (due > 0) {
    final m = (due * 0.5).ceil().clamp(3, 8);
    cand.add(CoachStep('cards', 'Review flashcards', due == 1 ? '1 card due' : '$due cards due', m));
  }
  if (weak.isNotEmpty) {
    final w = weak.first;
    cand.add(CoachStep('weak', 'Fix a weak spot: ${stripSource(w.title)}', 'Read it, then 5 questions', 7, packId: w.packId, articleTitle: w.title));
  } else if (weakNames.isNotEmpty) {
    final hits = library.ready ? await library.searchEx(weakNames.first, limit: 1, concise: true) : const <LibHit>[];
    cand.add(CoachStep('weak', 'Fix a weak spot: ${weakNames.first}', hits.isEmpty ? 'Revisit it in the library' : 'Read it, then 5 questions', 7,
        packId: hits.isEmpty ? '' : hits.first.packId, articleTitle: hits.isEmpty ? '' : hits.first.title));
  }
  for (final it in todayItems.take(2)) {
    cand.add(CoachStep('plan', stripSource(it.title), 'From your exam plan', 7, packId: it.packId, articleTitle: it.title));
  }
  {
    try {
      final r = await topicOfTheDay();
      final rot = store.currentRotation();
      if (r != null) {
        cand.add(CoachStep('rotation', stripSource(r.title), rot == null ? 'Topic of the day' : 'For your rotation: ${rot['name']}', 5, packId: r.packId, articleTitle: r.title));
      }
    } catch (_) {}
  }
  try {
    final ts = await resolveCore250();
    final tested = quizResultsByArticle(rows: 100000).keys.toSet();
    final read = {for (final r in recentArticles()) '${r['p']}|${r['t']}'};
    final c = [for (final t in ts) if (t.resolved && !tested.contains('${t.packId}|${t.title}') && !read.contains('${t.packId}|${t.title}')) t]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    if (c.isNotEmpty) {
      cand.add(CoachStep('core', c.first.label, 'New Core 250 topic', 5, packId: c.first.packId!, articleTitle: c.first.title ?? c.first.topic));
    }
  } catch (_) {}
  var total = 0;
  final taken = <String>{};
  for (final s in cand) {
    final key = '${s.kind}|${s.articleTitle}';
    if (s.articleTitle.isNotEmpty && !taken.add(s.articleTitle)) continue;
    if (total + s.minutes > minutes && steps.isNotEmpty) continue;
    steps.add(s);
    total += s.minutes;
    if (key.isEmpty) break;
  }
  final rot = store.currentRotation();
  return CoachPlan(steps: steps, due: due, weak: weakNames.length, planToday: planToday, daysToExam: plan == null ? -1 : examDaysLeft(plan.date, now: now), rotation: rot == null ? null : '${rot['name']}', budget: minutes);
}

CoachPlan reorderCoach(CoachPlan p, List<String> order) {
  final rest = [...p.steps];
  final out = <CoachStep>[];
  for (final k in order) {
    final i = rest.indexWhere((s) => s.kind == k);
    if (i >= 0) out.add(rest.removeAt(i));
  }
  out.addAll(rest);
  return CoachPlan(steps: out, due: p.due, weak: p.weak, planToday: p.planToday, daysToExam: p.daysToExam, rotation: p.rotation, budget: p.budget);
}

class CoachNote {
  final String motivation;
  final String why;
  final List<String> order;
  const CoachNote(this.motivation, this.why, this.order);
}

CoachNote? savedCoachNote({DateTime? now}) {
  final m = store.settings['aiCoachNote'];
  if (m is! Map || m['date'] != fmtDate(now ?? DateTime.now())) return null;
  return CoachNote('${m['motivation'] ?? ''}', '${m['why'] ?? ''}', [for (final o in (m['order'] as List? ?? const [])) '$o']);
}

/// Optional AI pass. Sends ONLY aggregated counts (Level none): no topic names, no case data.
Future<CoachNote?> coachAiNote(CoachPlan p, {AiRunner? runner, bool force = false}) async {
  if (!force) {
    final s = savedCoachNote();
    if (s != null) return s;
  }
  final kinds = [for (final s in p.steps) s.kind];
  final prompt = 'Aggregated counts only (no names): flashcards_due=${p.due}; weak_topics=${p.weak}; exam_plan_items_today=${p.planToday}; '
      'days_to_exam=${p.daysToExam < 0 ? 'none' : p.daysToExam}; minutes_available=${p.budget}; steps_available=${kinds.join(',')}.';
  final r = await _go(
      studyRequest(
        'quiz_coach',
        'Write a short, honest, motivating note (max 2 sentences) for an intern doctor about today\'s study session, and choose the best ORDER of a focused ${p.budget}-minute session using only the step kinds listed. '
            'Return ONLY JSON: {"motivation":"","why":"one sentence on why this order","order":["cards","weak"]}',
        prompt,
        json: true,
        maxTokens: 300,
        forceMode: 'given',
      ),
      runner);
  if (!r.ok) return null;
  final j = studyJson(r);
  if (j == null) return null;
  final order = [for (final o in _strs(j['order'])) if (kinds.contains(o)) o];
  final note = CoachNote(_s(j['motivation']), _s(j['why']), order);
  if (note.motivation.isEmpty) return null;
  store.settings['aiCoachNote'] = {'date': todayStr(), 'motivation': note.motivation, 'why': note.why, 'order': note.order};
  await store.saveSettings();
  return note;
}

// ------------------------------------------------------------------ viva / OSCE

const Map<String, String> kVivaModes = {
  'viva': 'Viva (oral exam)',
  'osce_history': 'OSCE: history',
  'osce_exam': 'OSCE: examination',
  'osce_data': 'OSCE: data interpretation',
  'osce_mgmt': 'OSCE: management',
  'shortcase': 'Short case',
};

const List<String> kVivaLevels = ['easy', 'medium', 'hard'];

class VivaPoint {
  final String text;
  final StudySource source;
  const VivaPoint(this.text, this.source);
  Map<String, dynamic> toJson() => {'text': text, 'src': source.toJson()};
  static VivaPoint fromJson(Map j) => VivaPoint(_s(j['text']), StudySource.fromJson(j['src']));
}

class VivaItem {
  final String question;
  final String topic;
  final List<VivaPoint> points; // hidden marking checklist
  final String senior; // what a senior would expect
  const VivaItem(this.question, this.topic, this.points, this.senior);
  Map<String, dynamic> toJson() => {'q': question, 'topic': topic, 'points': [for (final p in points) p.toJson()], 'senior': senior};
  static VivaItem fromJson(Map j) => VivaItem(_s(j['q']), _s(j['topic']), [for (final p in _maps(j['points'])) VivaPoint.fromJson(p)], _s(j['senior']));
}

class VivaStation {
  final String id;
  final String mode;
  final String specialty;
  final String difficulty;
  final String vignette;
  final List<VivaItem> items;
  final String sourceMode;
  const VivaStation(this.id, this.mode, this.specialty, this.difficulty, this.vignette, this.items, this.sourceMode);
}

class VivaTurn {
  final String answer;
  final List<bool> hits;
  final int score;
  final int max;
  final String feedback;
  final String senior;
  final bool estimated; // scored by the local keyword check (AI unavailable or answer unreadable)
  const VivaTurn(this.answer, this.hits, this.score, this.max, this.feedback, this.senior, {this.estimated = false});
  Map<String, dynamic> toJson() => {'a': answer, 'hits': hits, 'score': score, 'max': max, 'fb': feedback, 'senior': senior, if (estimated) 'est': true};
  static VivaTurn fromJson(Map j) => VivaTurn(_s(j['a']), [for (final h in (j['hits'] as List? ?? const [])) h == true], (j['score'] as num?)?.toInt() ?? 0, (j['max'] as num?)?.toInt() ?? 5, _s(j['fb']), _s(j['senior']), estimated: j['est'] == true);
}

const int kVivaMarks = 5; // marks per question

class VivaGen {
  final VivaStation? station;
  final String failure; // '' | off | offline | error | cancelled | invalid
  const VivaGen(this.station, this.failure);
}

String _vivaTask(String mode) => switch (mode) {
      'osce_history' => 'an OSCE history-taking station: the candidate takes the history from a simulated patient; ask what to ask, red flags and how to structure it',
      'osce_exam' => 'an OSCE examination station: ask which examination steps, what findings to expect and what they mean',
      'osce_data' => 'an OSCE data-interpretation station: the vignette contains fictional results (labs, ECG, X-ray description); ask for interpretation, diagnosis and next steps',
      'osce_mgmt' => 'an OSCE management station: ask for the immediate and subsequent management, with doses only when the source gives them',
      'shortcase' => 'a short case: present the case, then ask for diagnosis, differential and plan',
      _ => 'a viva (oral exam): a fictional vignette, then progressively harder questions',
    };

/// Builds a station from library passages (or the allow-listed web, per the source mode) with a hidden marking checklist.
/// Returns failure 'off' / 'offline' when AI cannot run (the screen then offers saved sessions and the local self-viva).
Future<VivaGen> generateViva({required String mode, required String specialty, String difficulty = 'medium', String topic = '', int questions = 4, AiRunner? runner}) async {
  final src = AiPrefs.sourceMode;
  final ps = await passagesForTopic(topic.trim().isEmpty ? specialty : topic, articles: 2, sections: 2);
  if (src == 'library' && ps.isEmpty) return const VivaGen(null, 'nolibrary');
  final b = StringBuffer()
    ..writeln('Create ${_vivaTask(mode)}. Specialty: $specialty. ${topic.trim().isEmpty ? '' : 'Topic: ${topic.trim()}. '}Difficulty: $difficulty. $questions questions.')
    ..writeln('The patient is FICTIONAL (no real person). Each question has a hidden marking checklist of 3 to 5 points; every point carries its source.')
    ..writeln(ps.isEmpty ? '' : 'Ground the case and the checklist in these passages:\n${_passageBlock(ps)}');
  final r = await _go(
      studyRequest(
        'quiz_viva',
        'You are a senior examiner running ${_vivaTask(mode)}. Return ONLY JSON: {"vignette":"","questions":[{"q":"","topic":"","points":[{"text":"","org":"","year":"","url":"","quote":"copy one sentence word for word from a passage when you use one","stitle":"source title"}],"senior":"what a senior would expect in 2-3 sentences"}]}. Points without a valid source will be discarded.',
        b.toString(),
        level: ps.isEmpty ? AiLevel.none : AiLevel.library,
        maxTokens: 2600,
        temperature: 0.4,
      ),
      runner);
  if (!r.ok) return VivaGen(null, studyFailure(r));
  final j = studyJson(r);
  if (j == null) return const VivaGen(null, 'invalid');
  final vignette = _s(j['vignette']);
  final items = <VivaItem>[];
  for (final q in _maps(j['questions'])) {
    final pts = <VivaPoint>[];
    for (final p in _maps(q['points'])) {
      final text = _s(p['text']);
      if (text.length < 4) continue;
      final s = acceptSource(p, mode: src, passages: ps);
      if (s != null) pts.add(VivaPoint(text, s));
    }
    final qt = _s(q['q']);
    if (qt.length < 8 || pts.length < 2) continue;
    items.add(VivaItem(qt, _s(q['topic']).isEmpty ? specialty : _s(q['topic']), pts.take(6).toList(), _s(q['senior'])));
  }
  if (vignette.length < 30 || items.length < 2) return const VivaGen(null, 'invalid');
  return VivaGen(VivaStation(newId('vv'), mode, specialty, difficulty, vignette, items.take(6).toList(), src), '');
}

/// Local scoring: a checklist point counts as hit when most of its key words are in the answer.
List<bool> localHits(VivaItem item, String answer) {
  final a = aiTokens(answer, min: 4);
  return [
    for (final p in item.points)
      () {
        final t = aiTokens(p.text, min: 4);
        if (t.isEmpty) return aiNorm(answer).contains(aiNorm(p.text));
        return t.where(a.contains).length / t.length >= 0.5;
      }()
  ];
}

int marksFor(List<bool> hits) => hits.isEmpty ? 0 : (kVivaMarks * hits.where((h) => h).length / hits.length).round();

/// Scores one answer against the hidden checklist (AI judges each point; the app computes the marks itself).
Future<VivaTurn> scoreViva(VivaStation st, int index, String answer, {AiRunner? runner}) async {
  final item = st.items[index];
  final b = StringBuffer()
    ..writeln('Case (fictional): ${st.vignette}')
    ..writeln('Question: ${item.question}')
    ..writeln('Checklist (hidden from the candidate):');
  for (var i = 0; i < item.points.length; i++) {
    b.writeln('${i + 1}. ${item.points[i].text}');
  }
  b.writeln(_fence('CANDIDATE ANSWER', answer));
  final r = await _go(
      studyRequest(
        'quiz_viva_score',
        'You are a fair senior examiner. Judge the candidate answer ONLY against the numbered checklist: a point is hit when the answer clearly contains it (any wording). Return ONLY JSON: {"hit":[true,false,...one per checklist point, in order],"feedback":"2-3 sentences on what was good and what was missing, kind and specific","senior":"what a senior would add in 1-2 sentences"}. Do not add medical facts that are not in the checklist.',
        b.toString(),
        maxTokens: 500,
        temperature: 0.1,
        forceMode: 'given',
      ),
      runner);
  final j = r.ok ? studyJson(r) : null;
  final hit = j == null ? <bool>[] : [for (final h in (j['hit'] as List? ?? const [])) h == true];
  if (j != null && hit.length == item.points.length) {
    return VivaTurn(answer, hit, marksFor(hit), kVivaMarks, _s(j['feedback']), _s(j['senior']).isNotEmpty ? _s(j['senior']) : item.senior);
  }
  final h = localHits(item, answer);
  return VivaTurn(answer, h, marksFor(h), kVivaMarks, '', item.senior, estimated: true);
}

class VivaResult {
  final String id;
  final int total;
  final int max;
  final List<String> weak; // topics under 60 %
  const VivaResult(this.id, this.total, this.max, this.weak);
  double get fraction => max == 0 ? 0 : total / max;
}

/// Saves the session, the weak areas (weak-spot memory) and review cards for the questions under 60 %.
Future<VivaResult> finishViva(VivaStation st, List<VivaTurn> turns, {String type = 'ai'}) async {
  var total = 0, max = 0;
  final weak = <String>[];
  for (var i = 0; i < turns.length; i++) {
    total += turns[i].score;
    max += turns[i].max;
    if (turns[i].max > 0 && turns[i].score / turns[i].max < 0.6) {
      final item = st.items[i];
      weak.add(item.topic);
      final missed = [for (var k = 0; k < item.points.length; k++) if (k >= turns[i].hits.length || !turns[i].hits[k]) '• ${item.points[k].text}'];
      await missedCard(
        front: '${item.question}\n\n(Viva: ${st.specialty})',
        back: '${missed.isEmpty ? item.points.map((p) => '• ${p.text}').join('\n') : missed.join('\n')}${item.senior.isEmpty ? '' : '\n\n${item.senior}'}',
        source: 'Viva',
        title: item.topic,
      );
    }
  }
  final uniq = <String>{...weak}.toList();
  await noteWeakAreas(uniq, src: 'viva');
  await store.upsertExtra(kAiVivaList, {
    'id': st.id,
    'type': type,
    'date': nowIso(),
    'mode': st.mode,
    'spec': st.specialty,
    'diff': st.difficulty,
    'vignette': st.vignette,
    'srcMode': st.sourceMode,
    'items': [for (final i in st.items) i.toJson()],
    'turns': [for (final t in turns) t.toJson()],
    'total': total,
    'max': max,
    'weak': uniq,
  });
  return VivaResult(st.id, total, max, uniq);
}

List<Map<String, dynamic>> vivaSessions() {
  final l = [for (final e in store.listOf(kAiVivaList)) Map<String, dynamic>.from(e)];
  l.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  return l;
}

VivaStation stationOf(Map<String, dynamic> m) => VivaStation('${m['id']}', '${m['mode']}', '${m['spec']}', '${m['diff']}', '${m['vignette'] ?? ''}', [for (final i in _maps(m['items'])) VivaItem.fromJson(i)], '${m['srcMode'] ?? ''}');

List<VivaTurn> turnsOf(Map<String, dynamic> m) => [for (final t in _maps(m['turns'])) VivaTurn.fromJson(t)];

// ---- self-viva (no AI, no internet)

class SelfVivaItem {
  final String title;
  final String packId;
  final int index;
  final String keyPoints; // the article lead / the card back
  const SelfVivaItem(this.title, this.packId, this.index, this.keyPoints);
}

/// Prompts about the learner's OWN weak topics, answered from the installed library: works fully offline.
Future<List<SelfVivaItem>> selfVivaItems({int n = 5}) async {
  final out = <SelfVivaItem>[];
  final seen = <String>{};
  Future<void> add(String packId, String title) async {
    if (out.length >= n || !library.ready || library.pack(packId) == null) return;
    final i = await library.indexOfTitle(packId, title);
    if (i == null || !seen.add('$packId|$i')) return;
    final leads = await library.leadsOf(packId);
    out.add(SelfVivaItem(stripSource(title), packId, i, i < leads.length ? leads[i] : ''));
  }
  for (final w in weakSpots()) {
    await add(w.packId, w.title);
  }
  for (final t in aiWeakTopics()) {
    await add(t.$1, t.$2);
  }
  if (out.length < n && library.ready) {
    for (final w in aiWeakAreas()) {
      if (out.length >= n) break;
      final hits = await library.searchEx('${w['topic']}', limit: 1, concise: true);
      if (hits.isNotEmpty) await add(hits.first.packId, hits.first.title);
    }
  }
  if (out.length < n) {
    try {
      for (final t in await resolveCore250()) {
        if (out.length >= n) break;
        if (t.resolved) await add(t.packId!, t.title ?? t.topic);
      }
    } catch (_) {}
  }
  return out;
}

/// Saves a self-viva: [got] per item (2 = knew it, 1 = partly, 0 = missed). Misses become weak areas and review cards.
Future<VivaResult> finishSelfViva(List<SelfVivaItem> items, List<int> got) async {
  final turns = <VivaTurn>[];
  final its = <VivaItem>[];
  for (var i = 0; i < items.length; i++) {
    final g = i < got.length ? got[i] : 0;
    its.add(VivaItem('Talk through: ${items[i].title}', items[i].title, [VivaPoint(items[i].keyPoints, StudySource(title: items[i].title))], ''));
    turns.add(VivaTurn('', [g == 2], g == 2 ? kVivaMarks : (g == 1 ? 3 : 0), kVivaMarks, '', ''));
  }
  final st = VivaStation(newId('vs'), 'selfviva', 'Self-viva', 'medium', '', its, 'library');
  return finishViva(st, turns, type: 'self');
}

// ------------------------------------------------------------------ Socratic teaching

class TeachStep {
  final String title;
  final String text;
  final String check;
  final String answer;
  final StudySource source;
  const TeachStep(this.title, this.text, this.check, this.answer, this.source);
}

class TeachLesson {
  final String topic;
  final List<TeachStep> steps;
  final String summary;
  const TeachLesson(this.topic, this.steps, this.summary);
}

/// Step 1: the AI asks first (2 to 3 short questions about what the learner already knows).
Future<(List<String>, String)> teachQuestions(String topic, {AiRunner? runner}) async {
  final r = await _go(
      studyRequest(
        'quiz_teach_ask',
        'Socratic teaching, step 1: do NOT explain yet. Ask 3 short diagnostic questions to find out what the learner already knows about the topic, from basic to applied. Return ONLY JSON: {"questions":["","",""]}',
        'Topic: ${topic.trim()}',
        maxTokens: 300,
        temperature: 0.4,
        forceMode: 'given',
      ),
      runner);
  if (!r.ok) return (const <String>[], studyFailure(r));
  final qs = _strs(studyJson(r)?['questions']);
  return qs.length >= 2 ? (qs.take(4).toList(), '') : (const <String>[], 'invalid');
}

/// Step 2: stepwise explanation adapted to the answers, each step ending with a check question; every step carries a source.
Future<(TeachLesson?, String)> teachLesson(String topic, List<(String, String)> qa, {AiRunner? runner}) async {
  final src = AiPrefs.sourceMode;
  final ps = await passagesForTopic(topic, articles: 2, sections: 2);
  final b = StringBuffer()..writeln('Topic: ${topic.trim()}');
  for (final (q, a) in qa) {
    b.writeln('Diagnostic question: $q');
    b.writeln(_fence('LEARNER ANSWER', a.isEmpty ? '(did not know)' : a));
  }
  if (ps.isNotEmpty) b.writeln('Library passages:\n${_passageBlock(ps)}');
  final r = await _go(
      studyRequest(
        'quiz_teach',
        'Socratic teaching, step 2: from the learner\'s answers find the gaps and teach in 4 to 6 short STEPS, from what they know to what they miss. Each step: a title, a short explanation (max 4 sentences), then ONE check question with its expected short answer, and the source of the step. Return ONLY JSON: {"steps":[{"title":"","text":"","check":"","answer":"","org":"","year":"","url":"","quote":"one sentence copied from a passage if used","stitle":""}],"summary":"2 sentences"}. Steps without a valid source are discarded.',
        b.toString(),
        level: ps.isEmpty ? AiLevel.none : AiLevel.library,
        maxTokens: 2200,
        temperature: 0.3,
      ),
      runner);
  if (!r.ok) return (null, studyFailure(r));
  final j = studyJson(r);
  if (j == null) return (null, 'invalid');
  final steps = <TeachStep>[];
  for (final s in _maps(j['steps'])) {
    final text = _s(s['text']);
    if (text.length < 20 || _s(s['check']).length < 6) continue;
    final so = acceptSource(s, mode: src, passages: ps);
    if (so == null) continue;
    steps.add(TeachStep(_s(s['title']), text, _s(s['check']), _s(s['answer']), so));
  }
  if (steps.length < 2) return (null, 'invalid');
  return (TeachLesson(topic.trim(), steps, _s(j['summary'])), '');
}

Future<void> saveTeachSession(TeachLesson l, {int known = 0}) =>
    store.upsertExtra(kAiTeachList, {'id': newId('at'), 'date': nowIso(), 'topic': l.topic, 'steps': l.steps.length, 'known': known});

/// Cards from the check questions of a lesson (each carries the source name).
Future<int> teachCards(TeachLesson l) async {
  var n = 0;
  for (final s in l.steps) {
    if (await addLibraryCard(front: '${s.check}\n\n(AI lesson: ${l.topic})', back: '${s.answer}\n\n(${s.source.label.isEmpty ? 'AI lesson' : s.source.label})', source: 'AI lesson', title: l.topic)) n++;
  }
  return n;
}

// ------------------------------------------------------------------ tables: guideline check and comparison

AiDoc _tableDoc(String title, List<List<String>> rows, List<AiCite> cites, String note, String raw) => AiDoc(
      sections: [
        AiDocSection(kind: 'table', title: title, table: rows, cites: cites),
        if (note.isNotEmpty) AiDocSection(kind: 'note', title: '', text: note),
      ],
      citations: cites,
      raw: raw,
      structured: true,
    );

class GRow {
  final String item;
  final String mine; // what the article / reference says
  final String current; // what the guideline says now
  final String status; // changed | same | unclear | no_source
  final StudySource source;
  final String note;
  const GRow(this.item, this.mine, this.current, this.status, this.source, this.note);
  Map<String, dynamic> toJson() => {'item': item, 'mine': mine, 'current': current, 'status': status, 'src': source.toJson(), 'note': note};
  static GRow fromJson(Map j) => GRow(_s(j['item']), _s(j['mine']), _s(j['current']), _s(j['status']), StudySource.fromJson(j['src']), _s(j['note']));
}

class GCheck {
  final String id, packId, title, date, summary;
  final List<GRow> rows;
  final bool searched;
  const GCheck(this.id, this.packId, this.title, this.date, this.rows, this.summary, this.searched);
  int get changed => rows.where((r) => r.status == 'changed').length;
  bool get noChange => changed == 0;

  /// Honest wording for the result.
  String get verdict => changed > 0
      ? '$changed item${changed == 1 ? '' : 's'} may be out of date: check the guideline itself before changing anything.'
      : 'No change found in the allowed sources. This does not prove that the article is up to date.';

  AiDoc toDoc() {
    final rows0 = <List<String>>[
      ['Item', 'In my reference', 'Current guideline', 'Status'],
      for (final r in rows)
        [r.item, r.mine, r.source.org.isEmpty ? r.current : '${r.current} (${r.source.org} ${r.source.year})', switch (r.status) { 'changed' => 'Changed', 'same' => 'No change', 'no_source' => 'No source found', _ => 'Unclear' }],
    ];
    return _tableDoc(title, rows0, [for (final r in rows) if (r.source.url.isNotEmpty || r.source.org.isNotEmpty) r.source.cite], '', summary);
  }

  Map<String, dynamic> toJson() => {'id': id, 'pack': packId, 'title': title, 'date': date, 'summary': summary, 'searched': searched, 'rows': [for (final r in rows) r.toJson()]};
  static GCheck fromJson(Map j) => GCheck('${j['id']}', _s(j['pack']), _s(j['title']), _s(j['date']), [for (final r in _maps(j['rows'])) GRow.fromJson(r)], _s(j['summary']), j['searched'] == true);
}

/// 'Is my reference still current? What changed?' for a library article, with the allow-listed web (web mode is forced).
Future<(GCheck?, String)> guidelineCheck(String packId, int index, {AiRunner? runner}) async {
  final ps = await passagesOf(packId, index, maxSections: 4, maxChars: 1400);
  if (ps.isEmpty) return (null, 'nopassage');
  final title = stripSource(ps.first.title);
  final b = StringBuffer()
    ..writeln('Reference article: $title. For each important recommendation in the passages (drug, dose, threshold, first-line choice, screening interval) check the CURRENT guideline of a recognised organisation.')
    ..writeln(_passageBlock(ps));
  final r = await _go(
      studyRequest(
        'ask_gcheck',
        'You verify whether a reference article is still current. Return ONLY JSON: {"rows":[{"item":"","mine":"what the article says","current":"what the current guideline says","status":"changed|same|unclear","org":"","year":"","url":"","note":""}],"summary":"1-2 sentences"}. '
            'Rules: only report "changed" or "same" when you found a guideline on the allowed sites and give its organisation, year and exact URL. Otherwise use "unclear". Be honest: if you found no change, say so; if you could not search, say so. Never invent a guideline.',
        b.toString(),
        level: AiLevel.library,
        maxTokens: 2200,
        forceMode: 'web',
        cacheKey: 'gcheck|$packId|$index|${todayStr()}',
      ),
      runner);
  if (!r.ok) return (null, studyFailure(r));
  final j = studyJson(r);
  if (j == null) return (null, 'invalid');
  final rows = <GRow>[];
  for (final m in _maps(j['rows'])) {
    final item = _s(m['item']);
    if (item.isEmpty) continue;
    var st = _s(m['status']).toLowerCase();
    if (!const ['changed', 'same', 'unclear'].contains(st)) st = 'unclear';
    final so = acceptSource(m, mode: 'web');
    if (so == null) {
      // no valid source: the item stays visible but makes no claim
      rows.add(GRow(item, _s(m['mine']), '', 'no_source', const StudySource(), ''));
    } else {
      rows.add(GRow(item, _s(m['mine']), _s(m['current']), st, so, _s(m['note'])));
    }
  }
  if (rows.isEmpty) {
    final c = GCheck(newId('gc'), packId, title, todayStr(), const [], _s(j['summary']), r.searched);
    await store.upsertExtra(kAiGCheckList, c.toJson());
    return (c, '');
  }
  final c = GCheck(newId('gc'), packId, title, todayStr(), rows, _s(j['summary']), r.searched);
  await store.upsertExtra(kAiGCheckList, c.toJson());
  return (c, '');
}

List<GCheck> guidelineChecks({String? packId, String? title}) {
  final l = [for (final e in store.listOf(kAiGCheckList)) GCheck.fromJson(e)];
  l.sort((a, b) => b.date.compareTo(a.date));
  return [for (final c in l) if ((packId == null || c.packId == packId) && (title == null || c.title == stripSource(title))) c];
}

class GCompare {
  final String topic, orgA, orgB, summary;
  final StudySource a, b;
  final List<List<String>> rows; // aspect, A, B
  const GCompare(this.topic, this.orgA, this.orgB, this.a, this.b, this.rows, this.summary);
  AiDoc toDoc() {
    final yearA = a.year.isEmpty ? '' : ' ${a.year}';
    final yearB = b.year.isEmpty ? '' : ' ${b.year}';
    return _tableDoc(
      'Compare: $topic',
      [
        ['Aspect', '$orgA$yearA', '$orgB$yearB'],
        ...rows,
      ],
      [if (a.org.isNotEmpty) a.cite, if (b.org.isNotEmpty) b.cite],
      '',
      summary,
    );
  }
}

/// 'Compare ESC vs AHA for X' as a table. Only differences found in a source of BOTH organisations are listed.
Future<(GCompare?, String)> compareGuidelines(String topic, String orgA, String orgB, {AiRunner? runner}) async {
  final r = await _go(
      studyRequest(
        'ask_compare',
        'Compare how two organisations\' CURRENT guidelines handle a topic. Return ONLY JSON: {"a":{"org":"","year":"","url":""},"b":{"org":"","year":"","url":""},"rows":[{"aspect":"","a":"","b":""}],"summary":"1-2 sentences"}. '
            'Rules: use the exact guideline you found for each organisation (year + URL on the allowed sites). If you cannot find one of them, return an empty "rows" and say so in the summary. In a cell write "not addressed" rather than guessing. Never invent a recommendation.',
        'Topic: ${topic.trim()}\nOrganisation A: ${orgA.trim()}\nOrganisation B: ${orgB.trim()}',
        maxTokens: 2000,
        forceMode: 'web',
      ),
      runner);
  if (!r.ok) return (null, studyFailure(r));
  final j = studyJson(r);
  if (j == null) return (null, 'invalid');
  final a = j['a'] is Map ? acceptSource(j['a'] as Map, mode: 'web') : null;
  final b = j['b'] is Map ? acceptSource(j['b'] as Map, mode: 'web') : null;
  final rows = <List<String>>[];
  if (a != null && b != null) {
    for (final m in _maps(j['rows'])) {
      final asp = _s(m['aspect']);
      if (asp.isEmpty) continue;
      rows.add([asp, _s(m['a']).isEmpty ? 'not addressed' : _s(m['a']), _s(m['b']).isEmpty ? 'not addressed' : _s(m['b'])]);
    }
  }
  var summary = _s(j['summary']);
  if (a == null || b == null) {
    summary = 'No source found on the allowed sites for ${a == null ? orgA.trim() : ''}${a == null && b == null ? ' and ' : ''}${b == null ? orgB.trim() : ''}: no comparison is shown, because nothing is stated without a source.';
  }
  return (GCompare(topic.trim(), orgA.trim(), orgB.trim(), a ?? const StudySource(), b ?? const StudySource(), rows, summary), '');
}

// ------------------------------------------------------------------ pre-shift quiz and case of the day

class PreShift {
  final List<AiQ> questions;
  final bool generated;
  final String? packId;
  final String rotation;
  const PreShift(this.questions, this.generated, this.packId, this.rotation);
}

/// 5 quick questions about the current rotation: the bank first, new ones generated only if online and AI is on.
Future<PreShift> preShiftSet({int n = 5, AiRunner? runner}) async {
  final rot = store.currentRotation();
  final name = rot == null ? '' : '${rot['name'] ?? ''}';
  final pack = name.isEmpty ? null : packIdForRotation(name);
  final usable = pack != null && library.pack(pack) != null;
  final pick = AiPick(mode: usable ? 'course' : 'all', packId: usable ? pack : null, count: n);
  var (qs, _) = await selectFromBank(pick);
  var generated = false;
  if (qs.length < n && usable && (Ai.enabled || runner != null)) {
    final rep = await generateMore('course', packId: pack, count: max(5, n - qs.length), runner: runner);
    if (rep.accepted > 0) {
      generated = true;
      (qs, _) = await selectFromBank(pick);
    }
  }
  if (qs.length < n && usable) {
    // pad with questions of any course so the set is never shorter than the bank allows
    final (more, _) = await selectFromBank(AiPick(mode: 'all', count: n));
    final have = {for (final q in qs) q.id};
    qs = [...qs, for (final q in more) if (!have.contains(q.id)) q].take(n).toList();
  }
  return PreShift(qs, generated, usable ? pack : null, name);
}

class CodStep {
  final String ask, answer, teach;
  final StudySource source;
  const CodStep(this.ask, this.answer, this.teach, this.source);
  Map<String, dynamic> toJson() => {'ask': ask, 'answer': answer, 'teach': teach, 'src': source.toJson()};
  static CodStep fromJson(Map j) => CodStep(_s(j['ask']), _s(j['answer']), _s(j['teach']), StudySource.fromJson(j['src']));
}

class CaseDay {
  final String date, topic, title, vignette;
  final List<CodStep> steps;
  const CaseDay(this.date, this.topic, this.title, this.vignette, this.steps);
  Map<String, dynamic> toJson() => {'id': date, 'date': date, 'topic': topic, 'title': title, 'vignette': vignette, 'steps': [for (final s in steps) s.toJson()]};
  static CaseDay fromJson(Map j) => CaseDay(_s(j['date']), _s(j['topic']), _s(j['title']), _s(j['vignette']), [for (final s in _maps(j['steps'])) CodStep.fromJson(s)]);
}

CaseDay? savedCaseOfDay({String? date}) {
  for (final e in store.listOf(kAiCodList)) {
    if (e['id'] == (date ?? todayStr())) return CaseDay.fromJson(e);
  }
  return null;
}

List<CaseDay> pastCasesOfDay() {
  final l = [for (final e in store.listOf(kAiCodList)) CaseDay.fromJson(e)]..sort((a, b) => b.date.compareTo(a.date));
  return l;
}

/// 'Case of the day': a fictional learning case from library passages / guidelines about a topic of the rotation or a weak spot.
Future<(CaseDay?, String)> caseOfTheDay({String? topic, bool force = false, AiRunner? runner}) async {
  if (!force) {
    final s = savedCaseOfDay();
    if (s != null) return (s, '');
  }
  var t = (topic ?? '').trim();
  if (t.isEmpty) {
    final weak = allWeakTopicNames();
    if (weak.isNotEmpty) {
      t = weak.first;
    } else {
      final h = await topicOfTheDay();
      t = h == null ? '' : stripSource(h.title);
    }
  }
  if (t.isEmpty) return (null, 'notopic');
  final src = AiPrefs.sourceMode;
  final ps = await passagesForTopic(t, articles: 2, sections: 2);
  if (src == 'library' && ps.isEmpty) return (null, 'nolibrary');
  final r = await _go(
      studyRequest(
        'case_ofday',
        'Write a short FICTIONAL learning case for an intern doctor about the topic, discussed in 4 to 5 steps (e.g. first assessment, investigations, diagnosis, management, pitfall). Each step: a question for the learner (ask), the expected answer, a one-paragraph teaching point and its source. Return ONLY JSON: {"title":"","vignette":"","steps":[{"ask":"","answer":"","teach":"","org":"","year":"","url":"","quote":"sentence copied from a passage if used","stitle":""}]}. Steps without a valid source are discarded.',
        'Topic: $t\n${ps.isEmpty ? '' : _passageBlock(ps)}',
        level: ps.isEmpty ? AiLevel.none : AiLevel.library,
        maxTokens: 2200,
        temperature: 0.5,
      ),
      runner);
  if (!r.ok) return (null, studyFailure(r));
  final j = studyJson(r);
  if (j == null) return (null, 'invalid');
  final steps = <CodStep>[];
  for (final s in _maps(j['steps'])) {
    if (_s(s['ask']).length < 8 || _s(s['teach']).length < 15) continue;
    final so = acceptSource(s, mode: src, passages: ps);
    if (so != null) steps.add(CodStep(_s(s['ask']), _s(s['answer']), _s(s['teach']), so));
  }
  if (_s(j['vignette']).length < 30 || steps.length < 2) return (null, 'invalid');
  final c = CaseDay(todayStr(), t, _s(j['title']).isEmpty ? t : _s(j['title']), _s(j['vignette']), steps);
  await store.upsertExtra(kAiCodList, c.toJson());
  final all = store.listOf(kAiCodList);
  if (all.length > 40) {
    all.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    all.removeRange(0, all.length - 40);
    await store.saveExtra(kAiCodList);
  }
  return (c, '');
}

// ------------------------------------------------------------------ written-answer grading

class Grade {
  final int score; // 0..10
  final List<String> strengths, missing;
  final List<(String, String)> wrong; // statement, why
  final String comment;
  final bool estimated;
  const Grade(this.score, this.strengths, this.missing, this.wrong, this.comment, {this.estimated = false});
  Map<String, dynamic> toJson() => {'score': score, 'strengths': strengths, 'missing': missing, 'wrong': [for (final w in wrong) {'s': w.$1, 'why': w.$2}], 'comment': comment, if (estimated) 'est': true};
}

/// Local rubric: key terms of the reference found / not found in the answer (works offline).
Grade gradeLocal(String reference, String answer) {
  final ref = aiTokens(reference, min: 5).toList();
  final ans = aiTokens(answer, min: 4);
  if (ref.isEmpty) return const Grade(0, [], [], [], '', estimated: true);
  final hit = ref.where(ans.contains).toList();
  final miss = ref.where((t) => !ans.contains(t)).toList();
  final score = (10 * hit.length / ref.length).round();
  return Grade(score, [if (hit.isNotEmpty) 'Mentions: ${hit.take(6).join(', ')}'], [if (miss.isNotEmpty) 'Not mentioned: ${miss.take(6).join(', ')}'], const [], 'Local keyword check only: it cannot tell if what you wrote is correct.', estimated: true);
}

/// Grades an open-ended answer against the cited [reference] (the source sentence or fact). Saves the result.
Future<(Grade?, String)> gradeWritten({required String question, required String reference, required String sourceLabel, required String answer, AiRunner? runner}) async {
  final r = await _go(
      studyRequest(
        'quiz_grade',
        'You grade an intern doctor\'s written answer against the REFERENCE only (never your own knowledge). Rubric: strengths, missing points, wrong statements (only statements the learner actually wrote that contradict the reference, quoted briefly), a score 0-10 and a short comment. Return ONLY JSON: {"score":0,"strengths":[],"missing":[],"wrong":[{"statement":"","why":""}],"comment":""}',
        'Question: $question\n${_fence('REFERENCE ($sourceLabel)', reference)}\n${_fence('LEARNER ANSWER', answer)}',
        maxTokens: 700,
        temperature: 0.1,
        forceMode: 'given',
      ),
      runner);
  Grade? g;
  final j = r.ok ? studyJson(r) : null;
  if (j != null && j['score'] is num) {
    final ansTok = aiTokens(answer, min: 4);
    final wrong = <(String, String)>[];
    for (final w in _maps(j['wrong'])) {
      final st = _s(w['statement']);
      final toks = aiTokens(st, min: 4);
      // keep only statements that really come from the learner's answer (no invented mistakes)
      if (st.isNotEmpty && toks.isNotEmpty && toks.where(ansTok.contains).length / toks.length >= 0.5) wrong.add((st, _s(w['why'])));
    }
    g = Grade(((j['score'] as num).toInt()).clamp(0, 10), _strs(j['strengths']), _strs(j['missing']), wrong, _s(j['comment']));
  }
  if (g == null) {
    final fail = studyFailure(r);
    g = gradeLocal(reference, answer);
    await store.upsertExtra(kAiGradeList, {'id': newId('ag'), 'date': nowIso(), 'q': question, 'src': sourceLabel, 'a': answer, ...g.toJson()});
    return (g, fail);
  }
  await store.upsertExtra(kAiGradeList, {'id': newId('ag'), 'date': nowIso(), 'q': question, 'src': sourceLabel, 'a': answer, ...g.toJson()});
  if (g.score < 6) await noteWeakAreas([question.length > 60 ? '${question.substring(0, 57)}...' : question], src: 'written');
  return (g, '');
}

List<Map<String, dynamic>> gradings() {
  final l = [for (final e in store.listOf(kAiGradeList)) Map<String, dynamic>.from(e)]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  return l;
}

// ------------------------------------------------------------------ board plan: AI explanation of the rebalancing

/// Short AI explanation of a rebalancing (Level none, specialty names and percentages only, no case data).
Future<String?> explainRebalance(Rebalance rb, WeekReview wr, {AiRunner? runner}) async {
  final lines = [for (final c in rb.changes) '${c.spec}: ${c.before.toStringAsFixed(1)} -> ${c.after.toStringAsFixed(1)} (accuracy ${c.accuracy == null ? 'n/a' : '${(c.accuracy! * 100).round()}%'})'];
  final r = await _go(
      studyRequest(
        'quiz_adapt',
        'Explain in 3 to 4 plain sentences, for an intern doctor preparing for a board exam, why the weekly study plan was rebalanced this way. Use ONLY the numbers given; do not invent results. Return ONLY JSON: {"text":""}',
        'Last 7 days: planned ${wr.planned}, done ${wr.done}, question accuracy ${wr.accuracy == null ? 'n/a' : '${(wr.accuracy! * 100).round()}%'}. Weight changes (specialty: before -> after):\n${lines.join('\n')}',
        maxTokens: 350,
        forceMode: 'given',
      ),
      runner);
  if (!r.ok) return null;
  final t = _s(studyJson(r)?['text']);
  return t.isEmpty ? null : t;
}
