import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../choices_engine.dart';
import '../data.dart';
import 'ai_api.dart';

/// De-identified case summary for the AI layer.
///
/// A WHITELIST: only the fields listed in [kPayloadLabels] can ever be read from the case. Everything else
/// (code, ids, initials, author, dates, hospital, supervisor, attachments, images, free text such as
/// social history / lessons / teaching notes) is never read. Every free-text value is cleaned locally
/// (known identifiers of THIS user + exact dates) and then passed through [AiPrivacy.scrub].
/// The list of removals is kept in [AiCasePayload.removed] so the preview can show it.

/// Label of every field that can leave the phone (the whitelist, in order).
const List<String> kPayloadLabels = [
  'Age group', 'Sex', 'Setting', 'Specialty', 'My role', 'Chief complaint', 'History of present illness',
  'Past medical history', 'Past surgical history', 'Medications', 'Allergies', 'Review of systems',
  'Vitals', 'General exam', 'Systemic exam', 'Focused exam', 'Exam by system', 'Investigations',
  'Imaging reports', 'Problem list', 'My differential', 'Working diagnosis', 'Final diagnosis',
  'Red flags noted', 'Plan and management', 'Progress by day', 'Disposition', 'Follow-up', 'Outcome',
];

const int _kMaxValue = 1600;

final RegExp _isoDate = RegExp(r'\b(19|20)\d{2}[-/.](0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])\b');
final RegExp _dmyDate = RegExp(r'\b(0?[1-9]|[12]\d|3[01])[-/.](0?[1-9]|1[0-2])[-/.]((19|20)?\d{2})\b');

class AiCasePayload {
  /// label -> value, only non-empty, already de-identified.
  final Map<String, String> fields;

  /// Human-readable list of what was removed or replaced (shown in the preview).
  final List<String> removed;

  /// The user marked the case "never send to AI".
  final bool blocked;

  const AiCasePayload(this.fields, this.removed, {this.blocked = false});

  bool get isEmpty => fields.isEmpty;

  /// Text given to the model.
  String asPrompt() {
    final b = StringBuffer();
    fields.forEach((k, v) => b.writeln('$k: $v'));
    return b.toString().trim();
  }

  String get digest => md5.convert(utf8.encode(asPrompt())).toString().substring(0, 16);

  /// Cache key: same payload + same feature (+ extra) = the same stored answer, readable offline.
  String cacheKey(String feature, [String extra = '']) =>
      md5.convert(utf8.encode('$feature|$extra|${asPrompt()}')).toString().substring(0, 20);
}

/// Strings that identify the user's own context and must never appear in text sent out.
List<String> knownIdentifiers(CaseRec c) {
  final out = <String>{};
  void add(Object? v) {
    final s = (v ?? '').toString().trim();
    if (s.length >= 3) out.add(s);
  }

  add(c.s('code'));
  add(c.s('initials'));
  add(c.s('author'));
  add(c.s('supName'));
  add(c.s('id'));
  add(store.author);
  for (final r in store.rotations) {
    add(r['hospital']);
  }
  for (final x in store.cases.values) {
    add(x.s('supName'));
    add(x.s('author'));
  }
  for (final p in store.procedures) {
    add(p['supName']);
  }
  return out.toList()..sort((a, b) => b.length.compareTo(a.length));
}

/// Cleans one free-text value: known identifiers, exact dates, then the shared scrubber.
String cleanFreeText(String text, List<String> known, List<String> removed) {
  var t = text;
  if (t.trim().isEmpty) return '';
  for (final k in known) {
    final re = RegExp(RegExp.escape(k), caseSensitive: false);
    if (re.hasMatch(t)) {
      t = t.replaceAll(re, '[removed]');
      final note = 'Your own identifier or name (e.g. hospital, supervisor, code)';
      if (!removed.contains(note)) removed.add(note);
    }
  }
  if (_isoDate.hasMatch(t) || _dmyDate.hasMatch(t)) {
    t = t.replaceAll(_isoDate, '[date]').replaceAll(_dmyDate, '[date]');
    const note = 'Exact dates';
    if (!removed.contains(note)) removed.add(note);
  }
  final s = AiPrivacy.scrub(t);
  for (final r in s.removed) {
    if (!removed.contains(r)) removed.add(r);
  }
  t = s.text.trim();
  if (t.length > _kMaxValue) t = '${t.substring(0, _kMaxValue)}...';
  return t;
}

/// The note-pasting feature uses the same cleaning (note text is previewed too).
ScrubResult cleanNote(String text, {CaseRec? forCase}) {
  final removed = <String>[];
  final known = forCase != null ? knownIdentifiers(forCase) : _globalKnown();
  final t = cleanFreeText(text, known, removed);
  return ScrubResult(t, removed);
}

List<String> _globalKnown() {
  final out = <String>{};
  for (final r in store.rotations) {
    final h = (r['hospital'] ?? '').toString().trim();
    if (h.length >= 3) out.add(h);
  }
  if (store.author.length >= 3) out.add(store.author);
  for (final x in store.cases.values) {
    for (final k in ['code', 'initials', 'supName']) {
      final v = x.s(k).trim();
      if (v.length >= 3) out.add(v);
    }
  }
  return out.toList()..sort((a, b) => b.length.compareTo(a.length));
}

String _s(Object? v) => (v ?? '').toString().trim();

/// Builds the de-identified payload. A case marked "never send" (rec.d['aiNever']) gives an empty, blocked payload.
AiCasePayload buildCasePayload(CaseRec c, {bool blocked = false}) {
  if (blocked || isCaseAiBlocked(c)) return const AiCasePayload({}, [], blocked: true);
  final removed = <String>[];
  final known = knownIdentifiers(c);
  final f = <String, String>{};
  String clean(String v) => cleanFreeText(v, known, removed);
  void put(String label, String v, {bool free = true}) {
    final t = free ? clean(v) : v.trim();
    if (t.isNotEmpty) f[label] = t;
  }

  // coded fields (no free text)
  put('Age group', c.s('ageGroup'), free: false);
  put('Sex', c.s('sex'), free: false);
  put('Setting', c.s('setting'), free: false);
  put('Specialty', c.s('specialty'), free: false);
  put('My role', c.s('role'), free: false);

  put('Chief complaint', c.s('cc'));
  put('History of present illness', c.s('hpi'));
  put('Past medical history', c.s('pmh'));
  put('Past surgical history', c.s('psh'));
  put('Medications', c.s('drugs'));
  put('Allergies', c.s('allergies'));
  put('Review of systems', c.s('ros'));
  for (final e in (kSpecialtyFields[c.s('specialty')] ?? const <List<String>>[])) {
    // age/birth details of children and pregnancy dates are free text: cleaned like the rest
    put(e[1], c.s(e[0]));
  }

  // what the user picked in the quick choices (coded vocabulary; the optional details are cleaned like free text)
  final cc = CaseChoices(c);
  for (final sec in const ['History', 'Examination']) {
    final rows = cc.lines(section: sec);
    if (rows.isNotEmpty) put('$sec choices', rows.map((r) => '${r[0]}: ${r[1]}${r[2].isEmpty ? '' : ' (${r[2]})'}').join('; '));
  }

  final sc = c.lst('scores');
  if (sc.isNotEmpty) put('Scores', sc.map((e) => '${e['name']}: ${e['value']}${'${e['meaning'] ?? ''}'.isEmpty ? '' : ' (${e['meaning']})'}').join('; '));

  final vit = [
    ['BP', 'v_bp'], ['HR', 'v_hr'], ['Temp', 'v_temp'], ['RR', 'v_rr'],
    ['SpO2', 'v_spo2'], ['RBS', 'v_rbs'], ['Wt', 'v_wt'],
  ].where((e) => c.s(e[1]).trim().isNotEmpty).map((e) => '${e[0]} ${c.s(e[1]).trim()}').join(', ');
  put('Vitals', vit);

  put('General exam', c.s('examGeneral'));
  put('Systemic exam', c.s('examSystemic'));
  put('Focused exam', c.s('examFocused'));
  final sys = c.d['sys'];
  if (sys is Map) {
    final parts = <String>[];
    sys.forEach((k, v) {
      if (v is Map) {
        final st = _s(v['s']);
        if (st.isEmpty) return;
        final n = _s(v['n']);
        parts.add('$k: $st${n.isEmpty ? '' : ' ($n)'}');
      }
    });
    put('Exam by system', parts.join('; '));
  }

  final inv = <String>[];
  for (final i in c.lst('inv')) {
    final r = _s(i['result']);
    final it = _s(i['interpretation']);
    final n = _s(i['name']);
    if (n.isEmpty) continue;
    inv.add('$n [${_s(i['status'])}]${r.isEmpty ? '' : ': $r'}${it.isEmpty ? '' : ' - $it'}');
  }
  put('Investigations', inv.join('\n'));

  // imaging REPORT text only: never the picture, file name or path
  final img = <String>[];
  for (final i in c.lst('images')) {
    final cap = _s(i['caption']);
    final it = _s(i['interpretation']);
    final t = [cap, it].where((e) => e.isNotEmpty).join(': ');
    if (t.isNotEmpty) img.add(t);
  }
  put('Imaging reports', img.join('\n'));

  put('Problem list', c.s('problems'));
  put('My differential', c.s('ddx'));
  put('Working diagnosis', c.s('workingDx'));
  put('Final diagnosis', c.s('finalDx'));
  put('Red flags noted', c.s('redFlags'));

  final mg = <String>[];
  for (final m in c.lst('mgmt')) {
    final t = _s(m['text']);
    if (t.isEmpty) continue;
    final d = _s(m['dose']);
    mg.add('${_s(m['category']).isEmpty ? '' : '${_s(m['category'])}: '}$t${d.isEmpty ? '' : ' ($d)'}');
  }
  put('Plan and management', mg.join('\n'));

  // progress notes: "Day N" (relative), never the calendar date
  final pr = <String>[];
  for (final p in c.lst('progress')) {
    final parts = [
      for (final k in const ['s', 'o', 'a', 'p'])
        if (_s(p[k]).isNotEmpty) '${k.toUpperCase()}: ${_s(p[k])}',
    ];
    if (parts.isEmpty) continue;
    final day = _s(p['day']).isEmpty ? 'Day ?' : _s(p['day']);
    pr.add('$day - ${parts.join(' | ')}');
  }
  put('Progress by day', pr.join('\n'));

  put('Disposition', c.s('disposition'));
  put('Follow-up', c.s('followUp'));
  put('Outcome', c.s('outcome'));

  return AiCasePayload(f, removed);
}

/// Case code stays local: used only when composing text that stays on the phone.
String payloadCode(CaseRec c) => c.s('code');
