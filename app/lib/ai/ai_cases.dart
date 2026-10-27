import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data.dart';
import '../focus.dart' show stageOfRole;
import '../goals_signoff.dart' show targetsOf, progressFor;
import '../i18n.dart';
import '../lib_user.dart';
import '../pdf_export.dart' show kClinStatuses, clinStatusOf;
import '../ui.dart' show trUi;
import 'ai_api.dart';
import 'ai_case_payload.dart';

/// Logic of the AI case assistant. Everything here is either LOCAL (works offline) or builds an [AiRequest]
/// that the screens send with [Ai.run] after the user previews the de-identified payload.

const int kSocraticMaxTurns = 6;

String get _langRule => isAr
    ? 'Write in Modern Standard Arabic, but keep clinical terms, drug and test names in English.'
    : 'Write in English.';

const String _caseRules =
    'You are a teaching assistant for a medical intern. The case is de-identified; use ONLY the facts given in it and never '
    'invent findings. Use wording such as "for your consideration"; you do not diagnose, you do not give orders. Do not '
    'state drug doses or treatment instructions. If information is missing say what is missing. Be concise.';

// ================================================================ (a) discuss my case

AiRequest discussRequest(AiCasePayload p) => AiRequest(
      feature: 'case_ddx',
      system: '$_caseRules\n$_langRule\n'
          'Return ONLY JSON: {"summary":"two sentences: who presents with what, and the main clinical question","diagnoses":[{"name":'
          '"diagnosis name only","likelihood":"more likely|possible|less likely","why":"one or two sentences: why this ranks here",'
          '"for":["facts from the case that support it"],"against":["facts from the case against it, or missing"],'
          '"typical_features":["classic features of this condition that the case does not mention yet"],'
          '"tells_apart":"what would separate it from the next diagnosis on the list","confirm_with":["findings or tests that '
          'would confirm or exclude it"]}],"red_flags":["serious conditions to exclude"],"dont_miss":["dangerous diagnoses not to miss"],'
          '"history_to_ask":["focused questions"],"exam_to_do":["focused examination steps"],"investigations":["tests to consider"],'
          '"would_change_management":["findings that would change the plan"],"missing_in_record":["important things the case '
          'record does not say"],"teaching_points":["3 to 5 short learning points for this presentation"]}. 3 to 6 diagnoses '
          'ordered from most likely. Diagnosis names only: no articles, no links, no treatment, no doses. Be specific to this '
          'case and to the learner level; avoid generic textbook lists.',
      prompt: 'Discuss this case for the learner in depth. Rank the differential with the reasoning, the evidence for and against taken from the case facts, what is still missing, and what the learner should learn from it.',
      level: AiLevel.caseData,
      expectJson: true,
      maxTokens: 3200,
      previewFields: p.fields,
      cacheKey: p.cacheKey('case_ddx'),
    );

class DxItem {
  final String name, likelihood, why, tellsApart;
  final List<String> forList, against, features, confirm;
  const DxItem(this.name, this.likelihood, this.forList, this.against, {this.why = '', this.tellsApart = '', this.features = const [], this.confirm = const []});
}

class CaseDiscussion {
  final String summary;
  final List<DxItem> dx;
  final List<String> redFlags, dontMiss, history, exam, investigations, wouldChange, missing, teaching;
  const CaseDiscussion(this.summary, this.dx, this.redFlags, this.dontMiss, this.history, this.exam, this.investigations, this.wouldChange,
      {this.missing = const [], this.teaching = const []});

  bool get isEmpty => dx.isEmpty && redFlags.isEmpty && dontMiss.isEmpty;

  static List<String> _l(Object? v, [int max = 8]) {
    if (v is List) {
      return [for (final e in v) if (e != null && e.toString().trim().isNotEmpty) e.toString().trim()].take(max).toList();
    }
    return const [];
  }

  factory CaseDiscussion.fromJson(Map<String, dynamic> j) {
    final dx = <DxItem>[];
    final raw = j['diagnoses'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final n = (e['name'] ?? '').toString().trim();
          if (n.isEmpty) continue;
          dx.add(DxItem(n, (e['likelihood'] ?? '').toString().trim(), _l(e['for'], 5), _l(e['against'], 5),
              why: (e['why'] ?? '').toString().trim(),
              tellsApart: (e['tells_apart'] ?? '').toString().trim(),
              features: _l(e['typical_features'], 5),
              confirm: _l(e['confirm_with'], 5)));
        } else if (e is String && e.trim().isNotEmpty) {
          dx.add(DxItem(e.trim(), '', const [], const []));
        }
      }
    }
    return CaseDiscussion((j['summary'] ?? '').toString().trim(), dx.take(7).toList(), _l(j['red_flags']), _l(j['dont_miss']),
        _l(j['history_to_ask']), _l(j['exam_to_do']), _l(j['investigations']), _l(j['would_change_management']),
        missing: _l(j['missing_in_record']), teaching: _l(j['teaching_points'], 6));
  }
}

// ================================================================ (b) Socratic mode

class SocraticTurn {
  final String role; // 'ai' | 'me'
  final String text;
  const SocraticTurn(this.role, this.text);
}

/// The case payload is sent with every call (the model has no memory), but it is the same text each time,
/// and the transcript is sent as part of the preview so the user sees what leaves the phone.
AiRequest socraticRequest(AiCasePayload p, List<SocraticTurn> turns, int turnNo) {
  final transcript = turns.map((t) => '${t.role == 'ai' ? 'Tutor' : 'Learner'}: ${t.text}').join('\n');
  final last = turnNo >= kSocraticMaxTurns;
  return AiRequest(
    feature: 'case_socratic',
    system: '$_caseRules\n$_langRule\n'
        'You are a Socratic tutor. Ask the learner ONE short question at a time about this case (for example: what is your '
        'differential? what will you order and why? what would change your plan?). After the learner answers, give brief '
        'feedback (2 sentences, say what was good and what was missed, based on the case facts only) and then ask the next '
        'question. Do not reveal the full answer before the learner commits. Do not give doses. '
        '${last ? 'This is the last turn: give a closing summary of 3 points and set "done" to true. ' : ''}'
        'Return ONLY JSON: {"feedback":"feedback on the last answer, empty for the first question","question":"next question, empty when done","done":false}.',
    prompt: turns.isEmpty ? 'Start: ask the first question.' : 'Continue the tutoring: respond to the last learner answer.',
    level: AiLevel.caseData,
    expectJson: true,
    maxTokens: 600,
    temperature: 0.4,
    previewFields: {...p.fields, if (transcript.isNotEmpty) 'Conversation so far': transcript},
    cacheKey: p.cacheKey('case_socratic', transcript),
  );
}

// ================================================================ (c) suggest fields from a note

/// Case fields the AI may suggest (the user confirms each one). key -> label.
const Map<String, String> kSuggestable = {
  'cc': 'Chief complaint',
  'hpi': 'History of present illness',
  'pmh': 'Past medical history',
  'drugs': 'Medications',
  'allergies': 'Allergies',
  'problems': 'Problem list',
  'ddx': 'Differential diagnosis',
  'workingDx': 'Working diagnosis',
  'redFlags': 'Red flags',
  'learned': 'What I learned',
  'specialty': 'Specialty',
  'setting': 'Setting',
  'ageGroup': 'Age group',
  'sex': 'Sex',
  'tags': 'Tags',
};

const Set<String> _kSettings = {'ER', 'Clinic', 'Ward', 'ICU', 'OR'};

AiRequest suggestFieldsRequest(String cleanedNote) {
  final keys = kSuggestable.keys.join(', ');
  return AiRequest(
    feature: 'case_fields',
    system: '$_caseRules\n$_langRule\n'
        'Extract structured case fields from the clinician note. Use ONLY what the note states; leave a field out when the '
        'note does not say it. Never copy names, ids, phone numbers or dates. Return ONLY JSON: {"fields":{"cc":"...",...},'
        '"procedures_mentioned":["..."],"tags":["short tags"]}. Allowed keys in fields: $keys. specialty must be one of: '
        '${kSpecialtyNames.join(', ')}. setting one of ER, Clinic, Ward, ICU, OR. ageGroup Child or Adult. sex M or F (only '
        'if stated). Keep clinical text in English, short, in the clinician style.',
    prompt: 'Extract the fields from the note.',
    level: AiLevel.caseData,
    expectJson: true,
    maxTokens: 1200,
    previewFields: {'Note (cleaned)': cleanedNote},
    cacheKey: md5.convert(utf8.encode('case_fields|$cleanedNote')).toString().substring(0, 20),
  );
}

class FieldSuggestion {
  final String key, label, current, suggested;
  bool apply;
  FieldSuggestion(this.key, this.label, this.current, this.suggested, {this.apply = false});
  bool get overwrites => current.trim().isNotEmpty && key != 'tags';
}

class SuggestionSet {
  final List<FieldSuggestion> items;
  final List<String> procedures;
  const SuggestionSet(this.items, this.procedures);
}

/// Turns the model JSON into validated suggestions. Anything not whitelisted or not valid is dropped.
SuggestionSet parseSuggestions(Map<String, dynamic> j, CaseRec rec) {
  final f = j['fields'] is Map ? Map<String, dynamic>.from(j['fields'] as Map) : <String, dynamic>{};
  final items = <FieldSuggestion>[];
  void add(String k, String v) {
    final cur = k == 'tags' ? rec.tags.join(', ') : rec.s(k);
    if (v.trim().isEmpty || v.trim() == cur.trim()) return;
    items.add(FieldSuggestion(k, kSuggestable[k] ?? k, cur, v.trim(), apply: cur.trim().isEmpty));
  }

  for (final k in kSuggestable.keys) {
    if (k == 'tags') continue;
    final raw = f[k];
    if (raw == null) continue;
    var v = (raw is List ? raw.join('; ') : raw.toString()).trim();
    if (v.length > 900) v = v.substring(0, 900);
    switch (k) {
      case 'specialty':
        final m = kSpecialtyNames.where((s) => s.toLowerCase() == v.toLowerCase());
        if (m.isEmpty) continue;
        v = m.first;
      case 'setting':
        final m = _kSettings.where((s) => s.toLowerCase() == v.toLowerCase());
        if (m.isEmpty) continue;
        v = m.first;
      case 'ageGroup':
        final m = ['Child', 'Adult'].where((s) => s.toLowerCase() == v.toLowerCase());
        if (m.isEmpty) continue;
        v = m.first;
      case 'sex':
        final u = v.toUpperCase();
        if (u.startsWith('M')) {
          v = 'M';
        } else if (u.startsWith('F')) {
          v = 'F';
        } else {
          continue;
        }
    }
    // the model must not smuggle identifiers back: the same cleaning as outgoing text
    if (!const {'specialty', 'setting', 'ageGroup', 'sex'}.contains(k)) {
      v = cleanFreeText(v, knownIdentifiers(rec), <String>[]);
    }
    add(k, v);
  }
  final tagSrc = <String>[
    if (j['tags'] is List) ...(j['tags'] as List).map((e) => e.toString()),
    if (f['tags'] is List) ...(f['tags'] as List).map((e) => e.toString()),
  ];
  final have = rec.tags.map((e) => e.toLowerCase()).toSet();
  final newTags = <String>[];
  for (final t in tagSrc) {
    final c = t.trim().replaceAll('#', '').replaceAll(RegExp(r'\s+'), '_').toLowerCase();
    if (c.isEmpty || c.length > 30 || have.contains(c) || newTags.contains(c)) continue;
    newTags.add(c);
  }
  if (newTags.isNotEmpty) {
    items.add(FieldSuggestion('tags', kSuggestable['tags']!, rec.tags.join(', '), newTags.take(6).join(', '), apply: true));
  }
  final procs = [
    if (j['procedures_mentioned'] is List) ...(j['procedures_mentioned'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
  ];
  return SuggestionSet(items, procs.take(6).toList());
}

/// What an Apply changed, so it can be undone.
class AiUndo {
  final Map<String, dynamic> before; // key -> previous value (null = key did not exist)
  const AiUndo(this.before);
}

/// Applies the chosen suggestions. Nothing is written before this call. Provenance: rec.d['aiSuggested'] = [field names].
/// A non-empty field is replaced only when the user ticked it (the screen shows current and suggested side by side).
AiUndo applySuggestions(CaseRec rec, List<FieldSuggestion> chosen) {
  final before = <String, dynamic>{};
  void keep(String k) {
    if (!before.containsKey(k)) before[k] = rec.d.containsKey(k) ? _copy(rec.d[k]) : null;
  }

  keep('aiSuggested');
  final prov = <String>{...(rec.d['aiSuggested'] is List ? (rec.d['aiSuggested'] as List).map((e) => e.toString()) : const <String>[])};
  for (final s in chosen) {
    if (!kSuggestable.containsKey(s.key)) continue;
    if (s.key == 'tags') {
      keep('tags');
      final l = rec.tags;
      for (final t in s.suggested.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)) {
        if (!l.contains(t)) l.add(t);
      }
      rec.tags = l;
    } else {
      keep(s.key);
      rec.set(s.key, s.suggested);
    }
    prov.add(s.key);
  }
  rec.d['aiSuggested'] = prov.toList();
  return AiUndo(before);
}

void undoSuggestions(CaseRec rec, AiUndo u) {
  u.before.forEach((k, v) {
    if (v == null) {
      rec.d.remove(k);
    } else {
      rec.d[k] = _copy(v);
    }
  });
}

dynamic _copy(dynamic v) => v is List ? List<dynamic>.from(v) : v;

// ================================================================ (d) missing / inconsistent fields (local rules)

class CaseIssue {
  final String text; // English template, shown through trp()
  final Map<String, Object> args;
  final bool warn; // true = inconsistency, false = missing
  const CaseIssue(this.text, {this.warn = false, this.args = const {}});

  /// Translated text.
  String get display => args.isEmpty ? tr(text) : trp(text, args);
}

double? _num(String s) {
  final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

List<CaseIssue> checkCase(CaseRec c) {
  final out = <CaseIssue>[];
  bool has(String k) => c.s(k).trim().isNotEmpty;
  void miss(String t) => out.add(CaseIssue(t));
  void warn(String t, [Map<String, Object> a = const {}]) => out.add(CaseIssue(t, warn: true, args: a));
  final status = c.s('status');
  final done = status == 'Completed' || status == 'Discharged';

  if (!has('cc')) miss('Chief complaint is empty.');
  if (!has('hpi')) miss('History of present illness is empty.');
  if (!has('ageGroup')) miss('Age group is not set.');
  if (!has('setting')) miss('Setting is not set.');
  if (!has('specialty')) miss('Specialty is not set.');
  if (!has('allergies') && c.s('st_allergies').isEmpty) miss('Allergies are not recorded (write "none" or mark Unknown).');
  final vit = ['v_bp', 'v_hr', 'v_temp', 'v_rr', 'v_spo2'].where(has).length;
  if (vit == 0) {
    miss('No vital signs recorded.');
  } else if (vit < 4) {
    miss('Vital signs are incomplete (BP, HR, Temp, RR, SpO2).');
  }
  final anyExam = has('examGeneral') || has('examSystemic') || has('examFocused') || (c.d['sys'] is Map && (c.d['sys'] as Map).isNotEmpty);
  if (!anyExam) miss('No examination recorded.');
  if (!has('workingDx') && !has('finalDx')) miss('No working or final diagnosis yet.');
  if ((has('workingDx') || has('finalDx')) && !has('reasoning') && !has('problems') && !has('ddx')) {
    miss('Diagnosis without reasoning, problem list or differential.');
  }
  if (c.lst('mgmt').isEmpty && status != 'Draft') miss('No plan / management recorded.');
  if (done) {
    if (!has('finalDx')) miss('Case is closed but has no final diagnosis.');
    if (!has('outcome') && !has('disposition')) miss('Case is closed but has no outcome or disposition.');
    if (!has('learned')) miss('No learning point written (What I learned).');
    if (c.lst('inv').any((i) => (i['status'] ?? '') == 'Pending')) warn('Case is closed but an investigation is still Pending.');
  }
  if (c.lst('mgmt').any((m) => (m['state'] ?? '') == 'Given' && (m['dose'] ?? '').toString().trim().isEmpty && (m['category'] ?? '') == 'Medications & fluids')) {
    miss('A given medication has no dose / route / frequency.');
  }

  // consistency
  final spec = c.s('specialty'), age = c.s('ageGroup'), sex = c.s('sex');
  if (spec == 'Pediatrics' && age == 'Adult') warn('Specialty is Pediatrics but age group is Adult.');
  if (age == 'Child' && (spec == 'OB/GYN' || spec == 'Internal Medicine')) warn('Age group is Child but the specialty is {s}.', {'s': tr(spec)});
  if (sex == 'M' && (has('obGPA') || has('obLmp'))) warn('Sex is M but obstetric fields are filled.');
  if (status == 'Draft' && has('finalDx')) warn('Status is Draft but a final diagnosis is entered.');
  if (!done && status != 'Draft' && status.isNotEmpty && has('outcome')) warn('An outcome is written but the status is still {s}.', {'s': trUi(status)});
  final bp = c.s('v_bp');
  final m = RegExp(r'(\d{2,3})\s*/\s*(\d{2,3})').firstMatch(bp);
  if (bp.trim().isNotEmpty && m == null) warn('Blood pressure is not in the form 120/80.');
  if (m != null && int.parse(m.group(1)!) <= int.parse(m.group(2)!)) warn('Blood pressure: systolic is not higher than diastolic.');
  void range(String k, String name, double lo, double hi) {
    final v = _num(c.s(k));
    if (v != null && (v < lo || v > hi)) warn('{name} value looks implausible: {v}.', {'name': tr(name), 'v': c.s(k)});
  }

  range('v_hr', 'Heart rate', 15, 250);
  range('v_temp', 'Temperature', 28, 44);
  range('v_rr', 'Respiratory rate', 3, 80);
  range('v_spo2', 'SpO2', 40, 100);
  range('v_rbs', 'Blood sugar', 10, 1500);
  final spo2 = _num(c.s('v_spo2'));
  if (spo2 != null && spo2 < 92 && !has('workingDx') && !has('problems')) {
    warn('Low SpO2 recorded but no problem or diagnosis mentions it.');
  }
  return out;
}

/// Tags already used in the user's logbook that appear in this case's text (local, offline).
List<String> suggestTagsLocal(CaseRec c, {int max = 5}) {
  final hay = [c.s('cc'), c.s('hpi'), c.s('workingDx'), c.s('finalDx'), c.s('problems'), c.s('ddx')].join(' ').toLowerCase();
  final have = c.tags.map((e) => e.toLowerCase()).toSet();
  final used = <String, int>{};
  for (final x in store.cases.values) {
    for (final t in x.tags) {
      used[t] = (used[t] ?? 0) + 1;
    }
  }
  final out = <String>[];
  final keys = used.keys.toList()..sort((a, b) => used[b]!.compareTo(used[a]!));
  for (final t in keys) {
    final w = t.toLowerCase().replaceAll('_', ' ');
    if (w.length < 3 || have.contains(t.toLowerCase())) continue;
    if (hay.contains(w)) out.add(t);
    if (out.length >= max) break;
  }
  return out;
}

AiRequest tagsRequest(AiCasePayload p) => AiRequest(
      feature: 'case_tags',
      system: '$_caseRules\nReturn ONLY JSON: {"specialty":"one of ${kSpecialtyNames.join(', ')}","tags":["up to 5 short lowercase tags"]}. English only.',
      prompt: 'Suggest the specialty and tags that best classify this case.',
      level: AiLevel.caseData,
      expectJson: true,
      maxTokens: 200,
      previewFields: p.fields,
      cacheKey: p.cacheKey('case_tags'),
    );

// ================================================================ (e) handover (I-PASS)

/// I-PASS handover built LOCALLY from whitelisted fields. It carries the case CODE (never a name) because it
/// stays between clinicians; it is never sent to AI. [contingencies] come from the optional AI draft.
String handoverText(CaseRec c, {List<String> contingencies = const []}) {
  final b = StringBuffer();
  final f = buildCasePayload(c).fields;
  String g(String k) => f[k] ?? '';
  final who = [c.s('ageGroup'), c.s('sex')].where((e) => e.isNotEmpty).join(' ');
  b.writeln('HANDOVER (I-PASS) • ${c.s('code')}${who.isEmpty ? '' : ' • $who'}${c.s('specialty').isEmpty ? '' : ' • ${c.s('specialty')}'}');
  final sev = clinStatusOf(c);
  b.writeln('\nI - Illness severity: ${sev.isEmpty ? 'not recorded (${kClinStatuses.join(' / ')})' : sev}');
  b.writeln('\nP - Patient summary');
  void line(String l, String v) {
    if (v.trim().isNotEmpty) b.writeln('- $l: ${v.trim()}');
  }

  line('Complaint', g('Chief complaint'));
  final hpi = g('History of present illness');
  line('History', hpi.length > 450 ? '${hpi.substring(0, 450)}...' : hpi);
  line('Past history', g('Past medical history'));
  line('Medications', g('Medications'));
  line('Allergies', g('Allergies'));
  line('Vitals', g('Vitals'));
  line('Key findings', g('Systemic exam').isNotEmpty ? g('Systemic exam') : g('Focused exam'));
  line('Investigations', g('Investigations'));
  line('Working diagnosis', g('Working diagnosis').isNotEmpty ? g('Working diagnosis') : g('Final diagnosis'));
  line('Problems', g('Problem list'));
  final given = [for (final m in c.lst('mgmt')) if (m['state'] == 'Given') (m['text'] ?? '').toString()].where((e) => e.isNotEmpty);
  line('Done so far', given.join('; '));

  b.writeln('\nA - Action list');
  final acts = <String>[
    for (final i in c.lst('inv')) if (i['status'] == 'Pending') 'Chase result: ${i['name']}',
    for (final m in c.lst('mgmt')) if (m['state'] == 'Suggested' || m['state'] == 'Ordered') '${m['state'] == 'Ordered' ? 'Check done' : 'Consider'}: ${m['text']}',
    if (c.s('followUp').trim().isNotEmpty) 'Follow-up: ${cleanFreeText(c.s('followUp'), const [], <String>[])}',
  ];
  if (acts.isEmpty) {
    b.writeln('- (none recorded)');
  } else {
    for (final a in acts) {
      b.writeln('- [ ] $a');
    }
  }

  b.writeln('\nS - Situation awareness and contingency');
  line('Red flags', g('Red flags noted'));
  if (contingencies.isEmpty) {
    b.writeln('- If: ______ then: ______');
  } else {
    for (final x in contingencies) {
      b.writeln('- $x');
    }
  }
  b.writeln('\nS - Synthesis by receiver');
  b.writeln('- Receiver reads back the plan and asks questions: [ ]');
  return b.toString().trimRight();
}

AiRequest handoverRequest(AiCasePayload p) => AiRequest(
      feature: 'case_handover',
      system: '$_caseRules\n$_langRule\n'
          'Return ONLY JSON: {"contingencies":["If <observation>, then <re-assess / call senior / re-check ...>"]}. 3 to 5 items about '
          'what to watch for overnight and when to escalate. No doses, no drug names.',
      prompt: 'Draft contingency statements (I-PASS "situation awareness and contingency planning") for this case.',
      level: AiLevel.caseData,
      expectJson: true,
      maxTokens: 500,
      previewFields: p.fields,
      cacheKey: p.cacheKey('case_handover'),
    );

// ================================================================ (f) learning points + cards

AiRequest reflectRequest(AiCasePayload p) => AiRequest(
      feature: 'case_reflect',
      system: '$_caseRules\n$_langRule\n'
          'Return ONLY JSON: {"questions":["q1","q2","q3"]}: exactly 3 reflective questions the learner should answer about THIS case '
          '(reasoning, what was missed, what to read). Questions only: do not answer them.',
      prompt: 'Write 3 reflection questions for this case.',
      level: AiLevel.caseData,
      expectJson: true,
      maxTokens: 350,
      previewFields: p.fields,
      cacheKey: p.cacheKey('case_reflect'),
    );

/// Local fallback prompts (offline).
List<String> localReflectionPrompts(CaseRec c) {
  final dx = c.title == '(no diagnosis yet)' ? '' : c.title;
  return [
    dx.isEmpty ? 'What is the most likely diagnosis here, and which finding made you choose it?' : 'Which findings supported "$dx", and which did not fit?',
    'What serious diagnosis did you have to exclude, and how did you do that?',
    'What would you do differently next time, and what is the one thing to read about this case?',
  ];
}

class CardDraft {
  final String front, back, title;
  const CardDraft(this.front, this.back, this.title);
}

/// Review cards phrased from the user's own case data (local; no identifiers: age group, sex, complaint only).
List<CardDraft> cardsFromCase(CaseRec c) {
  final f = buildCasePayload(c).fields;
  final out = <CardDraft>[];
  final who = [f['Age group'], f['Sex']].where((e) => (e ?? '').isNotEmpty).join(' ');
  final cc = f['Chief complaint'] ?? '';
  final dx = (f['Final diagnosis'] ?? '').isNotEmpty ? f['Final diagnosis']! : (f['Working diagnosis'] ?? '');
  final tag = c.s('code');
  final src = 'My case ${tag.isEmpty ? '' : tag}'.trim();
  if (cc.isNotEmpty && dx.isNotEmpty) {
    final key = [f['Vitals'], f['Focused exam'] ?? f['Systemic exam'], f['Investigations']].where((e) => (e ?? '').isNotEmpty).join('\n');
    out.add(CardDraft('${who.isEmpty ? 'Patient' : who} with $cc.${key.isEmpty ? '' : '\n$key'}\nWhat is your diagnosis and why?', dx + ((f['Problem list'] ?? '').isEmpty ? '' : '\n${f['Problem list']}'), dx));
  }
  if (cc.isNotEmpty && (f['Red flags noted'] ?? '').isNotEmpty) {
    out.add(CardDraft('Red flags to look for in: $cc', f['Red flags noted']!, cc));
  }
  final learned = c.s('learned').trim();
  if (learned.isNotEmpty) {
    out.add(CardDraft('Lesson from my case${dx.isEmpty ? '' : ' ($dx)'}: what did I learn?', cleanFreeText(learned, knownIdentifiers(c), <String>[]), dx.isEmpty ? cc : dx));
  }
  final q = c.s('questions').trim();
  if (q.isNotEmpty) {
    out.add(CardDraft('My open question${dx.isEmpty ? '' : ' about $dx'}', cleanFreeText(q, knownIdentifiers(c), <String>[]), dx.isEmpty ? cc : dx));
  }
  return [for (final d in out) CardDraft(d.front, d.back, d.title.isEmpty ? src : d.title)];
}

/// Saves the drafts as library review cards. Returns how many new cards were made.
Future<int> saveCaseCards(CaseRec c, List<CardDraft> drafts) async {
  var n = 0;
  final src = 'My case ${c.s('code')}'.trim();
  for (final d in drafts) {
    if (await addLibraryCard(front: d.front, back: d.back, source: src, title: d.title)) n++;
  }
  return n;
}

// ================================================================ (3) week / rotation summary (aggregated numbers only)

class AiStats {
  final String title; // 'Week' | rotation name
  final int days;
  final int cases;
  final Map<String, int> bySpecialty;
  final Map<String, int> byRole;
  final Map<String, int> procedures; // name -> count
  final int proceduresTotal;
  final int performed; // procedures at stage >= 3
  final List<String> goals; // "Cases 6 / 10"
  final List<String> weakTopics;
  final int reviewDue;
  const AiStats(this.title, this.days, this.cases, this.bySpecialty, this.byRole, this.procedures, this.proceduresTotal, this.performed,
      this.goals, this.weakTopics, this.reviewDue);

  bool get isEmpty => cases == 0 && proceduresTotal == 0;

  /// Plain local summary (also the offline version). Shown as-is on Home and in the PDF.
  String plainText() {
    final b = StringBuffer();
    String top(Map<String, int> m, [int n = 4]) {
      final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return e.take(n).map((x) => '${tr(x.key)} ${x.value}').join(', ');
    }

    b.writeln(trp('{n} cases in {d} days', {'n': cases, 'd': days}) + (bySpecialty.isEmpty ? '' : ': ${top(bySpecialty)}'));
    if (proceduresTotal > 0) {
      b.writeln('${trp('{n} procedures', {'n': proceduresTotal})} (${trp('{n} performed', {'n': performed})})'
          '${procedures.isEmpty ? '' : ': ${top(procedures)}'}');
    }
    if (byRole.isNotEmpty) b.writeln('${tr('My role')}: ${top(byRole)}');
    for (final g in goals) {
      b.writeln(g);
    }
    if (weakTopics.isNotEmpty) b.writeln('${tr('Weak topics')}: ${weakTopics.join(', ')}');
    return b.toString().trimRight();
  }

  /// The numbers given to the model (no case content, no dates, no names).
  String aiFacts() {
    final b = StringBuffer();
    b.writeln('Period: $title ($days days)');
    b.writeln('Cases logged: $cases');
    if (bySpecialty.isNotEmpty) b.writeln('Cases by specialty: ${bySpecialty.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
    if (byRole.isNotEmpty) b.writeln('Cases by my role: ${byRole.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
    b.writeln('Procedures logged: $proceduresTotal (performed by me: $performed)');
    if (procedures.isNotEmpty) b.writeln('Procedures by name: ${procedures.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
    for (final g in goals) {
      b.writeln('Goal: $g');
    }
    if (weakTopics.isNotEmpty) b.writeln('Weak quiz topics: ${weakTopics.join(', ')}');
    return b.toString().trimRight();
  }

  String get digest => md5.convert(utf8.encode(aiFacts())).toString().substring(0, 16);
}

bool _isCurrent(J r) {
  final t = todayStr();
  final s = (r['start'] ?? '').toString(), e = (r['end'] ?? '').toString();
  if (s.isNotEmpty && t.compareTo(s) < 0) return false;
  if (e.isNotEmpty && t.compareTo(e) > 0) return false;
  return s.isNotEmpty || e.isNotEmpty;
}

String _clean(Object? v) => (v ?? '').toString().trim();

/// [from]/[to] inclusive date strings (yyyy-mm-dd); [rotation] limits to one rotation (goals of that rotation).
AiStats computeStats({required String title, required String from, required String to, J? rotation, int days = 7}) {
  bool inRange(String d) => d.isNotEmpty && d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
  final spec = <String, int>{}, role = <String, int>{}, procs = <String, int>{};
  var cases = 0, ptotal = 0, performed = 0;
  final rid = rotation == null ? null : rotation['id'].toString();
  for (final c in store.cases.values) {
    if (c.d['demo'] == true) continue;
    if (rid != null ? c.s('rotationId') != rid : !inRange(c.s('date'))) continue;
    cases++;
    final s = c.s('specialty');
    if (s.isNotEmpty) spec[s] = (spec[s] ?? 0) + 1;
    final r = c.s('role');
    if (r.isNotEmpty) role[r] = (role[r] ?? 0) + 1;
  }
  for (final p in store.procedures) {
    if (p['demo'] == true) continue;
    if (rid != null ? p['rotationId'] != rid : !inRange(_clean(p['date']))) continue;
    ptotal++;
    final n = _clean(p['name']);
    if (n.isNotEmpty) procs[n] = (procs[n] ?? 0) + 1;
    if (stageOfRole(_clean(p['role'])) >= 3) performed++;
  }
  final goals = <String>[];
  final rots = rotation != null ? [rotation] : store.rotations.where((r) => r['demo'] != true && _isCurrent(r)).toList();
  for (final r in rots.take(2)) {
    for (final g in targetsOf(r).take(6)) {
      final pr = progressFor(r, g);
      if (pr.target > 0) goals.add('${pr.label} ${pr.done} / ${pr.target}');
    }
  }
  final weak = <String>[];
  try {
    for (final w in weakSpots().take(4)) {
      weak.add(w.title);
    }
  } catch (_) {}
  var due = 0;
  try {
    final t = todayStr();
    due = store.listOf('review').where((e) => _clean(e['due']).isNotEmpty && _clean(e['due']).compareTo(t) <= 0).length;
  } catch (_) {}
  return AiStats(title, days, cases, spec, role, procs, ptotal, performed, goals, weak, due);
}

AiStats weekStats() {
  final now = DateTime.now();
  final from = fmtDate(now.subtract(const Duration(days: 6)));
  return computeStats(title: 'Last 7 days', from: from, to: fmtDate(now), days: 7);
}

AiStats rotationStats(J rot) {
  final s = _clean(rot['start']), e = _clean(rot['end']);
  var days = 0;
  final a = parseDate(s), z = parseDate(e);
  if (a != null && z != null) days = z.difference(a).inDays + 1;
  return computeStats(title: _clean(rot['name']).isEmpty ? 'Rotation' : _clean(rot['name']), from: s, to: e, rotation: rot, days: days);
}

/// [kind] 'week' | 'rotation'. Narrative from the aggregated facts only (Level none: no case content leaves the phone).
AiRequest summaryRequest(AiStats s, {String kind = 'week'}) => AiRequest(
      feature: 'summary_$kind',
      system: 'You write a short, encouraging progress summary for a medical trainee from aggregated logbook numbers. Use ONLY the '
          'numbers given; never invent counts, cases or clinical details. 3 to 4 sentences, plain text, no headings, no advice '
          'about treatment. Mention one strength and one gap or next step (for example a goal that is behind or a weak quiz topic). '
          '$_langRule',
      prompt: 'Write the ${kind == 'week' ? 'weekly' : 'rotation'} summary from these numbers:\n${s.aiFacts()}',
      level: AiLevel.none,
      maxTokens: 300,
      temperature: 0.4,
      cacheKey: md5.convert(utf8.encode('summary_$kind|${s.digest}|$langCode')).toString().substring(0, 20),
    );
