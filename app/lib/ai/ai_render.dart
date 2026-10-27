import 'dart:convert';

import '../i18n.dart' show tr;
import 'ai_doc_api.dart';

/// Parser (JSON, repaired JSON, markdown rebuild) and exporters of the AI document engine.
/// Entry points are re-exported through ai_doc_api.dart (parseAiOutput, aiDocToPlain, aiDocToMarkdown).

// ---------------------------------------------------------------------------------------------- kinds

final Map<String, RegExp> _kindRx = () {
  RegExp r(String s) => RegExp(s, caseSensitive: false);
  return <String, RegExp>{
    'prognosis': r(r"prognos|outcome|mortality|مآل|التنبؤ|نذير|الإنذار المرضي"),
    'uncertainties': r(r"could not verify|couldn'?t verify|not verified|unverified|uncertain|limitation|caveat|what i (could not|couldn'?t|did not)|unable to confirm|لم أتمكن|لم أستطع|غير (مؤكد|متأكد|موثق)|قيود"),
    'references': r(r"^\W*(references?|sources?|citations?|bibliography|further reading|المراجع|المصادر|مراجع|المرجع|المصدر)\W*$"),
    'mnemonic': r(r"mnemonic|memory aid|acronym|تذكر|حيلة|اختصار|مساعد الذاكرة"),
    'red_flags': r(r"red[- ]?flag|warning sign|danger sign|alarm (sign|feature|symptom)|urgent|emergenc(y|ies) sign|when to (seek|call|refer|escalate|worry)|worry|seek (urgent|medical|immediate)|call (an )?ambulance|escalat|علامات (الخطر|التحذير)|أعراض الخطر|علامات تحذيرية|إنذار|اعلام حمراء|أعلام حمراء|علامات حمراء|أعراض مقلقة"),
    'dont_miss': r(r"(do(n'?t| not)|can'?t|cannot|must not|never) miss|critical diagnos|life[- ]threatening|لا (يجب )?تفوّ?ت|تشخيصات (خطيرة|مهددة)|مهدد للحياة|لا يجب إغفال"),
    'guidelines': r(r"guideline|recommendation|consensus|society|إرشاد|توصيات|ارشادات|المبادئ التوجيهية"),
    'complications': r(r"complication|adverse (effect|event)|side effect|مضاعفات|الآثار الجانبية|الاختلاطات"),
    'disposition': r(r"disposition|admission|admit|discharge|follow[- ]?up|referral|safety[- ]net|الإدخال|الخروج|المتابعة|التحويل|التنويم"),
    'key_points': r(r"key (point|take|message|fact)|take[- ]?home|takeaway|high[- ]yield|pearl|remember|important|النقاط (الرئيسية|المهمة|الأساسية)|نقاط (مهمة|رئيسية|أساسية)|ملاحظات مهمة|تذكير"),
    'steps': r(r"^\W*steps?\b|step[- ]by[- ]step|خطوات"),
    'differential': r(r"differential|ddx|\bdd\b|causes?\b|aetiolog|etiolog|الأسباب|التشخيص التفريقي|التفريقي|الاسباب|مسببات"),
    'investigations': r(r"investigat|work[- ]?up|diagnostic|diagnosis|tests?\b|laborator|\blabs?\b|imaging|الفحوصات|التحاليل|الاستقصاءات|التشخيص|التصوير|المخبر"),
    'management': r(r"manage|treatment|therap|\bplan\b|approach|intervention|first[- ]line|dos(e|es|ing|age)\b|medication|pharmaco|algorithm|protocol|العلاج|التدبير|المعالجة|الخطة|خطة|الإدارة|الجرعة|الجرعات|الأدوية"),
    'presentation': r(r"present|clinical (feature|picture|manifest)|symptom|\bsigns?\b|history|examination|\bexam\b|features|manifest|الأعراض|الاعراض|العلامات|السريري|العرض"),
    'overview': r(r"overview|summary|short answer|quick answer|\banswer\b|definition|background|introduction|tl;?dr|bottom line|in brief|at a glance|نظرة عامة|ملخص|الخلاصة|التعريف|الإجابة|الجواب|باختصار|مقدمة|لمحة"),
  };
}();

/// Section kind for a heading, or null when it says nothing.
String? kindOfTitle(String title) {
  final t = title.trim();
  if (t.isEmpty || t.length > 70) return null;
  for (final e in _kindRx.entries) {
    if (e.value.hasMatch(t)) return e.key;
  }
  return null;
}

const Map<String, String> kKindLabel = {
  'overview': 'Overview', 'presentation': 'Presentation', 'differential': 'Differential', 'investigations': 'Investigations',
  'management': 'Management', 'red_flags': 'Red flags', 'dont_miss': "Don't miss", 'key_points': 'Key points',
  'mnemonic': 'Mnemonic', 'table': 'Table', 'steps': 'Steps', 'guidelines': 'Guidelines', 'complications': 'Complications',
  'prognosis': 'Prognosis', 'disposition': 'Disposition', 'references': 'References', 'note': 'Note', 'other': 'Details',
};

String _normKind(String k) {
  final s = k.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_').replaceAll("'", '');
  const alias = {
    'redflags': 'red_flags', 'red_flag': 'red_flags', 'redflag': 'red_flags', 'warning': 'red_flags', 'warnings': 'red_flags', 'alert': 'red_flags',
    'dontmiss': 'dont_miss', 'dont_miss': 'dont_miss', 'do_not_miss': 'dont_miss', 'cant_miss': 'dont_miss', 'dontmiss_diagnoses': 'dont_miss',
    'ddx': 'differential', 'dd': 'differential', 'causes': 'differential', 'differential_diagnosis': 'differential',
    'workup': 'investigations', 'work_up': 'investigations', 'investigation': 'investigations', 'diagnosis': 'investigations', 'tests': 'investigations',
    'treatment': 'management', 'therapy': 'management', 'plan': 'management', 'dosing': 'management', 'medications': 'management',
    'summary': 'overview', 'answer': 'overview', 'short_answer': 'overview', 'tldr': 'overview', 'definition': 'overview', 'intro': 'overview',
    'clinical_features': 'presentation', 'features': 'presentation', 'symptoms': 'presentation', 'signs': 'presentation',
    'keypoints': 'key_points', 'key_point': 'key_points', 'takeaways': 'key_points', 'pearls': 'key_points', 'high_yield': 'key_points',
    'mnemonics': 'mnemonic', 'guideline': 'guidelines', 'recommendations': 'guidelines', 'complication': 'complications',
    'follow_up': 'disposition', 'followup': 'disposition', 'step': 'steps', 'algorithm': 'steps', 'sources': 'references', 'reference': 'references',
    'citations': 'references', 'tables': 'table', 'caveats': 'uncertainties', 'limitations': 'uncertainties',
  };
  final a = alias[s] ?? s;
  return kAiDocKinds.contains(a) || a == 'uncertainties' ? a : '';
}

// ---------------------------------------------------------------------------------------------- inline helpers

final RegExp _urlRx = RegExp(r'https?://[^\s)\]>"]+');
final RegExp _yearRx = RegExp(r'\b(19|20)\d{2}[a-z]?\b');

String stripInline(String s) {
  var t = s;
  t = t.replaceAllMapped(RegExp(r'\[([^\]]+)\]\((https?://[^)]+)\)'), (m) => '${m[1]} (${m[2]})');
  t = t.replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m[2]!);
  t = t.replaceAllMapped(RegExp(r'(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])'), (m) => m[1]!);
  t = t.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
  return t.replaceAll('**', '').replaceAll('__', '');
}

AiCite citeFromText(String raw) {
  var s = raw.trim();
  s = s.replaceFirst(RegExp(r'^\s*(?:[-*•–]\s*)?(?:\[\d{1,3}\]|\d{1,3}[.)])\s*[:.\-]?\s*'), '');
  final url = _urlRx.firstMatch(s)?.group(0)?.replaceAll(RegExp(r'[.,;]+$'), '') ?? '';
  s = stripInline(s);
  var label = url.isEmpty ? s : s.replaceAll(url, '').replaceAll(RegExp(r'[\s,;:–-]+$'), '').trim();
  label = label.replaceAll(RegExp(r'\(\s*\)'), '').trim();
  if (label.isEmpty && url.isNotEmpty) label = Uri.tryParse(url)?.host ?? url;
  final year = _yearRx.firstMatch(label)?.group(0) ?? '';
  var org = '';
  final toks = label.split(RegExp(r'[\s,.(:;–]+')).where((e) => e.isNotEmpty).toList();
  if (toks.isNotEmpty && RegExp(r'^[A-Z][A-Z/&\-]{1,}$').hasMatch(toks.first)) {
    org = toks.first;
  } else if (toks.length >= 2 && RegExp(r'^[A-Z][a-z]+$').hasMatch(toks.first) && !RegExp(r'\d').hasMatch(toks[1]) && RegExp(r'^[A-Z]').hasMatch(toks[1])) {
    org = '${toks[0]} ${toks[1]}';
  } else if (toks.isNotEmpty && RegExp(r'^[A-Z][a-z]+$').hasMatch(toks.first)) {
    org = toks.first;
  }
  return AiCite(label: label, org: org, year: year.replaceAll(RegExp(r'[a-z]'), ''), url: url);
}

/// Guideline body followed by a code or a year, e.g. 'NICE NG138', 'GINA 2023', 'AHA/ACC 2018'.
final RegExp orgBareRx = RegExp(r'\b((?:NICE|SIGN|WHO|AHA|ACC|ESC|EAS|IDSA|KDIGO|GINA|GOLD|ADA|CDC|AAP|ACOG|BTS|ERC|SSC|JBDS|RCUK)(?:/[A-Z]{2,5})?)(?:\s+((?:[A-Z]{1,3}\d{1,4})|guidelines?))?(?:[,\s]+\(?((?:19|20)\d{2})\)?)?');

/// Inline author-year style citations such as (NICE 2024), (AHA/ACC 2023), (Smith et al., 2020).
final RegExp orgYearRx = RegExp(r"\(([A-Z][\w&/.\-]*(?:\s+(?:[A-Za-z][\w&/.\-]*|et al\.?)){0,5}?),?\s+((?:19|20)\d{2}[a-z]?)\)");

// ---------------------------------------------------------------------------------------------- entry

AiDoc parseAiOutputImpl(String text, {Map<String, dynamic>? json}) {
  if (json != null) {
    final d = _fromMap(json, text.isEmpty ? jsonEncode(json) : text, '', '');
    if (d != null) return d;
  }
  final t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('​', '').trim();
  if (t.isEmpty) return AiDoc(raw: text);
  final found = _findJson(t);
  if (found != null) {
    final d = _fromMap(found.obj, text, found.before, found.after);
    if (d != null && _jsonCovered(t, d)) return d;
  }
  return _rebuild(t, text);
}

final RegExp _wordRx = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// True when every string value of the JSON text made it into the document (guards against a repair that dropped data).
bool _jsonCovered(String raw, AiDoc d) {
  final have = <String>{for (final m in _wordRx.allMatches(docToText(d, markdown: false, footer: false).toLowerCase())) m.group(0)!};
  for (final m in RegExp(r'"((?:[^"\\]|\\.)*)"(\s*:)?').allMatches(raw)) {
    if (m.group(2) != null) continue;
    final v = m.group(1)!.replaceAll(RegExp(r'\\[nrt"\\/]'), ' ');
    if (kAiDocKinds.contains(v)) continue;
    for (final w in _wordRx.allMatches(v.toLowerCase())) {
      if (!have.contains(w.group(0)!) && !stripInline(v).toLowerCase().contains('http')) return false;
    }
  }
  return true;
}

class _Found {
  final Map<String, dynamic> obj;
  final String before, after;
  _Found(this.obj, this.before, this.after);
}

bool _looksSchema(dynamic o) => o is Map && o['sections'] is List;

dynamic _decode(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {}
  var cur = s;
  for (var i = 0; i < 40; i++) {
    final fixed = _repair(cur);
    try {
      return jsonDecode(fixed);
    } catch (_) {}
    final cut = _lastComma(cur);
    if (cut <= 0) return null;
    cur = cur.substring(0, cut);
  }
  return null;
}

int _lastComma(String s) {
  var inStr = false, esc = false, last = -1;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (c == '\\') {
        esc = true;
      } else if (c == '"') {
        inStr = false;
      }
    } else if (c == '"') {
      inStr = true;
    } else if (c == ',') {
      last = i;
    }
  }
  return last;
}

String _repair(String s) {
  final out = <String>[];
  final stack = <String>[];
  var inStr = false, esc = false;
  void stripComma() {
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    if (out.isNotEmpty && out.last == ',') out.removeLast();
  }

  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      if (esc) {
        esc = false;
        out.add(c);
      } else if (c == '\\') {
        esc = true;
        out.add(c);
      } else if (c == '"') {
        inStr = false;
        out.add(c);
      } else if (c == '\n') {
        out.add(r'\n');
      } else if (c == '\t') {
        out.add(r'\t');
      } else {
        out.add(c);
      }
      continue;
    }
    if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
      while (i < s.length && s[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < s.length && s[i + 1] == '*') {
      final e = s.indexOf('*/', i + 2);
      i = e < 0 ? s.length : e + 1;
      continue;
    }
    if (c == '"') {
      inStr = true;
      out.add(c);
    } else if (c == '{' || c == '[') {
      stack.add(c);
      out.add(c);
    } else if (c == '}' || c == ']') {
      stripComma();
      if (stack.isNotEmpty) stack.removeLast();
      out.add(c);
    } else {
      out.add(c);
    }
  }
  if (inStr) {
    if (esc && out.isNotEmpty) out.removeLast();
    out.add('"');
  }
  stripComma();
  if (out.isNotEmpty && out.last.trimRight().endsWith(':')) out.add('null');
  while (stack.isNotEmpty) {
    out.add(stack.removeLast() == '{' ? '}' : ']');
  }
  return out.join();
}

int _balancedEnd(String s, int start) {
  var depth = 0, inStr = false, esc = false;
  for (var i = start; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (c == '\\') {
        esc = true;
      } else if (c == '"') {
        inStr = false;
      }
    } else if (c == '"') {
      inStr = true;
    } else if (c == '{' || c == '[') {
      depth++;
    } else if (c == '}' || c == ']') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

_Found? _findJson(String t) {
  Map<String, dynamic>? asMap(dynamic o) {
    if (o is Map) return {for (final e in o.entries) '${e.key}': e.value};
    if (o is List && o.isNotEmpty && o.every((e) => e is Map && (e.containsKey('kind') || e.containsKey('title') || e.containsKey('text')))) return {'sections': o};
    return null;
  }

  // 1. pure JSON
  if (t.startsWith('{') || t.startsWith('[')) {
    final o = _decode(t);
    final m = asMap(o);
    if (m != null) return _Found(m, '', '');
  }
  // 2. fenced blocks
  for (final f in RegExp(r'```[ \t]*(?:json|JSON|jsonc)?[ \t]*\n?([\s\S]*?)(?:```|$)').allMatches(t)) {
    final body = (f.group(1) ?? '').trim();
    if (!body.startsWith('{') && !body.startsWith('[')) continue;
    final m = asMap(_decode(body));
    if (m != null && (_looksSchema(m) || t.startsWith('```'))) {
      return _Found(m, t.substring(0, f.start).trim(), t.substring(f.end).trim());
    }
  }
  // 3. embedded object
  final first = t.indexOf('{');
  if (first >= 0 && t.contains('"sections"')) {
    final end = _balancedEnd(t, first);
    if (end > 0) {
      final m = asMap(_decode(t.substring(first, end + 1)));
      if (m != null && _looksSchema(m)) return _Found(m, t.substring(0, first).trim(), t.substring(end + 1).trim());
    }
    // 4. truncated: everything from the first brace
    final m = asMap(_decode(t.substring(first)));
    if (m != null && _looksSchema(m)) return _Found(m, t.substring(0, first).trim(), '');
  }
  return null;
}

// ---------------------------------------------------------------------------------------------- JSON -> doc

String _s(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is List) return v.map(_s).where((e) => e.isNotEmpty).join('; ');
  if (v is Map) return v.entries.map((e) => '${e.key}: ${_s(e.value)}').join('; ');
  return '$v';
}

dynamic _pick(Map m, List<String> keys) {
  for (final k in keys) {
    if (m[k] != null) return m[k];
  }
  return null;
}

AiCite? _citeOf(dynamic v, List<AiCite> pool) {
  if (v is int) return v >= 1 && v <= pool.length ? pool[v - 1] : null;
  if (v is String) {
    final n = int.tryParse(v.trim().replaceAll(RegExp(r'[\[\]]'), ''));
    if (n != null) return n >= 1 && n <= pool.length ? pool[n - 1] : null;
    return v.trim().isEmpty ? null : citeFromText(v);
  }
  if (v is Map) {
    final label = _s(_pick(v, ['label', 'title', 'name', 'source', 'text']));
    final url = _s(_pick(v, ['url', 'link', 'href']));
    final c = AiCite(label: label, org: _s(_pick(v, ['org', 'organization', 'organisation', 'publisher', 'body'])), year: _s(_pick(v, ['year', 'date'])), url: url);
    if (c.isEmpty) return null;
    if (c.label.isEmpty) {
      return AiCite(label: [c.org, c.year].where((e) => e.isNotEmpty).join(' ').isEmpty ? url : [c.org, c.year].where((e) => e.isNotEmpty).join(' '), org: c.org, year: c.year, url: url);
    }
    return c;
  }
  return null;
}

List<List<String>> _tableOf(dynamic v) {
  if (v is String) return _tableFromLines(v.split('\n')) ?? [];
  if (v is Map) {
    final h = _pick(v, ['headers', 'header', 'columns', 'cols']);
    final rows = _pick(v, ['rows', 'data']);
    final out = <List<String>>[];
    if (h is List) out.add([for (final c in h) _s(c)]);
    if (rows is List) {
      for (final r in rows) {
        out.add(r is List ? [for (final c in r) _s(c)] : r is Map ? [for (final c in r.values) _s(c)] : [_s(r)]);
      }
    }
    return _pad(out);
  }
  if (v is List && v.isNotEmpty) {
    if (v.first is Map) {
      final keys = <String>[];
      for (final r in v) {
        if (r is Map) {
          for (final k in r.keys) {
            if (!keys.contains('$k')) keys.add('$k');
          }
        }
      }
      return _pad([keys, for (final r in v) if (r is Map) [for (final k in keys) _s(r[k])]]);
    }
    return _pad([for (final r in v) r is List ? [for (final c in r) _s(c)] : [_s(r)]]);
  }
  return [];
}

List<List<String>> _pad(List<List<String>> rows) {
  if (rows.isEmpty) return rows;
  final n = rows.fold<int>(0, (a, r) => r.length > a ? r.length : a);
  return [for (final r in rows) [...r, for (var i = r.length; i < n; i++) '']];
}

List<String> _strList(dynamic v) {
  if (v is List) return [for (final e in v) if (_s(e).trim().isNotEmpty) _s(e).trim()];
  if (v is String && v.trim().isNotEmpty) return [for (final l in v.split('\n')) if (l.trim().isNotEmpty) l.trim()];
  return [];
}

String _cleanItem(String s) => s.replaceFirst(RegExp(r'^\s*(?:[-*•–—▪◦·]\s+|\d{1,2}[.)]\s+)'), '').trim();

AiDoc? _fromMap(Map<String, dynamic> m, String raw, String before, String after) {
  final pool = <AiCite>[];
  final cs = _pick(m, ['citations', 'references', 'sources']);
  if (cs is List) {
    for (final c in cs) {
      final x = _citeOf(c is int ? null : c, pool);
      if (x != null) pool.add(x);
    }
  }
  final sections = <AiDocSection>[];
  final unc = <String>[..._strList(_pick(m, ['uncertainties', 'uncertainty', 'unverified', 'limitations']))];
  final secs = m['sections'];
  if (secs is List) {
    for (final e in secs) {
      if (e is String) {
        if (e.trim().isNotEmpty) sections.add(_secFromParts('note', '', e, const [], const [], const [], const []));
      } else if (e is Map) {
        final sec = _secFromMap(e, pool, unc);
        if (sec != null) sections.add(sec);
      }
    }
  } else {
    // generic object: each key is a section
    for (final e in m.entries) {
      final k = '${e.key}';
      if (const {'title', 'citations', 'references', 'sources', 'uncertainties', 'disclaimer'}.contains(k)) continue;
      final v = e.value;
      if (v is String && const {'answer', 'response', 'text', 'content', 'message', 'reply'}.contains(k.toLowerCase())) {
        final d = _rebuild(v.trim(), v);
        sections.addAll(d.sections);
        pool.addAll(d.citations);
        unc.addAll(d.uncertainties);
        continue;
      }
      final title = k.replaceAll('_', ' ');
      final kind = _normKind(k).isNotEmpty ? _normKind(k) : (kindOfTitle(title) ?? 'other');
      if (v is Map) {
        final sec = _secFromMap({'kind': kind, 'title': title, ...v.map((a, b) => MapEntry('$a', b))}, pool, unc);
        if (sec != null) sections.add(sec);
      } else if (v is List) {
        final tab = v.isNotEmpty && v.first is Map ? _tableOf(v) : <List<String>>[];
        sections.add(_secFromParts(kind, title, '', tab.isEmpty ? _strList(v) : const [], const [], tab, const []));
      } else if (_s(v).trim().isNotEmpty) {
        sections.add(_secFromParts(kind, title, _s(v), const [], const [], const [], const []));
      }
    }
  }
  if (sections.isEmpty && pool.isEmpty && unc.isEmpty) return null;
  AiDoc? pre, post;
  if (before.isNotEmpty) pre = _rebuild(before, before);
  if (after.isNotEmpty) post = _rebuild(after, after);
  final all = <AiDocSection>[
    if (pre != null) ...pre.sections.map((s) => _asNote(s)),
    ...sections,
    if (post != null) ...post.sections.map((s) => _asNote(s)),
  ];
  return AiDoc(
    sections: all,
    citations: [...pool, if (pre != null) ...pre.citations, if (post != null) ...post.citations],
    raw: raw,
    structured: true,
    title: _s(m['title']).trim(),
    uncertainties: [...unc, if (pre != null) ...pre.uncertainties, if (post != null) ...post.uncertainties],
    disclaimer: _s(m['disclaimer']).trim(),
  );
}

AiDocSection _asNote(AiDocSection s) => s.kind == 'overview' && s.title.isEmpty
    ? AiDocSection(kind: 'note', title: s.title, text: s.text, bullets: s.bullets, table: s.table, cites: s.cites, steps: s.steps, blocks: s.blocks)
    : s;

AiDocSection? _secFromMap(Map e, List<AiCite> pool, List<String> unc) {
  var kind = _normKind(_s(e['kind'] ?? e['type']));
  final title = _s(_pick(e, ['title', 'heading', 'name', 'label'])).trim();
  if (kind.isEmpty) kind = kindOfTitle(title) ?? 'other';
  final text = _s(_pick(e, ['text', 'content', 'body', 'summary', 'description']));
  final bullets = _strList(_pick(e, ['bullets', 'items', 'points', 'list', 'bullet_points']));
  final steps = _strList(_pick(e, ['steps', 'actions', 'procedure']));
  final table = _tableOf(_pick(e, ['table', 'rows']));
  final cites = <AiCite>[];
  final cv = e['cites'] ?? e['citations'] ?? e['sources'];
  if (cv is List) {
    for (final c in cv) {
      final x = _citeOf(c, pool);
      if (x != null) cites.add(x);
    }
  } else if (cv != null) {
    final x = _citeOf(cv, pool);
    if (x != null) cites.add(x);
  }
  if (kind == 'uncertainties') {
    unc.addAll([..._strList(text), ...bullets.map(_cleanItem)]);
    return null;
  }
  if (text.trim().isEmpty && bullets.isEmpty && steps.isEmpty && table.isEmpty && title.isEmpty) return null;
  return _secFromParts(kind, title, text, bullets, steps, table, cites);
}

AiDocSection _secFromParts(String kind, String title, String text, List<String> bullets, List<String> steps, List<List<String>> table, List<AiCite> cites) {
  final blocks = <AiBlock>[];
  if (text.trim().isNotEmpty) {
    final toks = _tokenize(text, hashMode: false);
    for (final t in toks) {
      if (t.block != null) {
        blocks.add(t.block!);
      } else if (t.head != null) {
        blocks.add(AiBlock('h', t.head!));
        if (t.rest.isNotEmpty) blocks.add(AiBlock('p', t.rest));
      }
    }
  }
  for (final b in bullets) {
    final c = _cleanItem(b);
    if (c.isNotEmpty) blocks.add(AiBlock('b', c));
  }
  for (final s in steps) {
    final c = _cleanItem(s);
    if (c.isNotEmpty) blocks.add(AiBlock('n', c));
  }
  if (table.isNotEmpty) blocks.add(AiBlock('t', '', rows: table));
  var k = kind;
  if (k == 'other' || k.isEmpty) k = 'other';
  return _mk(k, title, blocks, cites);
}

AiDocSection _mk(String kind, String title, List<AiBlock> blocks, [List<AiCite> cites = const []]) {
  final paras = [for (final b in blocks) if (b.type == 'p' || b.type == 'm' || b.type == 'c') b.text];
  return AiDocSection(
    kind: kind,
    title: title,
    text: paras.join('\n'),
    bullets: [for (final b in blocks) if (b.type == 'b') b.text],
    steps: [for (final b in blocks) if (b.type == 'n') b.text],
    table: blocks.where((b) => b.type == 't').map((b) => b.rows).firstOrNull ?? const [],
    cites: cites,
    blocks: blocks,
  );
}

// ---------------------------------------------------------------------------------------------- markdown tokenizer

class _Tok {
  final AiBlock? block; // content
  final String? head; // heading text
  final int level; // 1..6 for '#', 7 strong (bold line), 8 colon / caps / numbered heading
  final String rest; // text on the same line after a lead-in label
  final List<AiCite> refs; // reference definitions found on this line
  _Tok({this.block, this.head, this.level = 0, this.rest = '', this.refs = const []});
}

final RegExp _bulletRx = RegExp(r'^(\s*)([-*•–—▪◦‣·+●○■])\s+(\S.*)$');
final RegExp _numRx = RegExp(r'^(\s*)(?:(\d{1,3}|[٠-٩]{1,3})[.)\-]|[Ss]tep\s+(\d{1,2})\s*[:.\-])\s+(\S.*)$');
final RegExp _hashRx = RegExp(r'^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$');
final RegExp _boldLineRx = RegExp(r'^\s*(\*\*|__)([^*_\n]+?)\1\s*[:：]?\s*$');
final RegExp _sepRx = RegExp(r'^[\s|:+=\-]+$');
final RegExp _ruleRx = RegExp(r'^\s*([-*_=])(\s*\1){2,}\s*$');
final RegExp _srcLineRx = RegExp(r'^\s*(?:[-*•]\s*)?(?:\*\*|__)?(sources?|references?|refs?|citations?|المصدر|المصادر|المراجع|مصدر)(?:\*\*|__)?\s*[:：]\s*(?:\*\*|__)?\s*(\S.*)$', caseSensitive: false);
final RegExp _refDefRx = RegExp(r'^\s*\[(\d{1,3})\]\s*[:.\-]?\s+(\S.{5,})$');
final RegExp _leadRx = RegExp(r'^\s*(?:\*\*|__)?\s*([^:：*\n]{2,45}?)\s*(?:\*\*|__)?\s*[:：]\s*(?:\*\*|__)?\s*(\S.*)$');
final RegExp _mnemLead = RegExp(r'^\s*(?:\*\*|__)?(mnemonics?|memory aid|acronym|remember|تذكر|حيلة|اختصار)(?:\*\*|__)?\s*[:：\-]\s*(\S.*)$', caseSensitive: false);

String _indentFix(String l) => l.replaceAll('\t', '    ');
int _indentOf(String l) => l.length - l.trimLeft().length;

bool _acronymOk(String acr, String rest) {
  final letters = acr.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
  if (letters.length < 3) return false;
  final words = stripInline(rest).split(RegExp(r'[\s,;/()=–—\-]+')).where((w) => w.isNotEmpty).toList();
  var wi = 0, ok = 0;
  for (final ch in letters.split('')) {
    while (wi < words.length && !words[wi].toUpperCase().startsWith(ch)) {
      wi++;
    }
    if (wi < words.length) {
      ok++;
      wi++;
    }
  }
  return ok >= letters.length - 1 && ok >= 3;
}

final RegExp _acrRx = RegExp(r'^\s*(?:[-*•]\s+)?(?:\*\*|__)?([A-Z]{3,8})(?:\*\*|__)?\s*(?:[:=–—\-]|\()\s*(?:\*\*|__)?(\S.*)$');

List<String> _unwall(List<String> lines) {
  final out = <String>[];
  for (final l0 in lines) {
    var l = l0;
    if (l.length < 220) {
      out.add(l);
      continue;
    }
    l = l.replaceAllMapped(RegExp(r'(?<=\S)[ ]+(#{1,4}[ ]+)'), (m) => '\n${m[1]}');
    l = l.replaceAllMapped(RegExp(r'(?<=[.!?:؟])[ ]+(\*\*[^*\n]{2,50}:?\*\*:?)(?=[ ]|$)'), (m) => '\n${m[1]}');
    l = l.replaceAllMapped(RegExp(r'(?<=[.!?؟)\]])[ ]+([A-Z\u0600-\u06FF][^:：\n.!?]{2,34}?)[ ]?[:：](?=[ ]|$)'), (m) {
      final lab = m.group(1)!;
      return kindOfTitle(lab) != null && lab.split(' ').length <= 5 ? '\n${m.group(1)}:' : m.group(0)!;
    });
    l = l.replaceAllMapped(RegExp(r"(?<=\S)[ ]+((?:Red flags|Key points|Management|Differential(?: diagnosis)?|Investigations|Don't miss|Complications|Prognosis|Disposition|Mnemonic|Summary|Short answer|Overview|Presentation|Treatment|References|Sources|Source|Guidelines|علامات الخطر|النقاط المهمة|العلاج|الخلاصة|المراجع))[ ]?[:：]"), (m) => '\n${m.group(1)}:');
    // inline numbered sequence 1. ... 2. ... 3. ...
    if (RegExp(r'(?:^|\s)1[.)]\s').hasMatch(l) && RegExp(r'\s2[.)]\s').hasMatch(l) && RegExp(r'\s3[.)]\s').hasMatch(l)) {
      var n = 1;
      var cur = l;
      final parts = <String>[];
      while (true) {
        final next = RegExp('\\s${n + 1}[.)]\\s').firstMatch(cur);
        if (next == null) break;
        parts.add(cur.substring(0, next.start));
        cur = cur.substring(next.start + 1);
        n++;
      }
      parts.add(cur);
      l = parts.join('\n');
    }
    final bl = RegExp(r'\s[-•]\s(?=[A-Z؀-ۿ*])').allMatches(l).length;
    if (bl >= 3) l = l.replaceAllMapped(RegExp(r'\s([-•])\s(?=[A-Z؀-ۿ*])'), (m) => '\n${m[1]} ');
    for (final p in l.split('\n')) {
      if (p.length > 450 && !p.contains('|')) {
        final sents = p.split(RegExp(r'(?<=[.!?؟])\s+(?=[A-Z؀-ۿ0-9*])'));
        var cur = '';
        var n = 0;
        for (final s in sents) {
          cur = cur.isEmpty ? s : '$cur $s';
          n++;
          if (n >= 3 && cur.length > 160) {
            out.add(cur);
            cur = '';
            n = 0;
          }
        }
        if (cur.isNotEmpty) out.add(cur);
      } else {
        out.add(p);
      }
    }
  }
  return out;
}

List<List<String>>? _tableFromLines(List<String> ls) {
  final rows = <List<String>>[];
  var sawSep = false;
  for (final l in ls) {
    final t = l.trim();
    if (t.isEmpty) continue;
    if (_sepRx.hasMatch(t) && t.contains('-')) {
      sawSep = true;
      continue;
    }
    var c = t;
    if (c.startsWith('|')) c = c.substring(1);
    if (c.endsWith('|')) c = c.substring(0, c.length - 1);
    rows.add([for (final x in c.split('|')) x.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '; ').trim()]);
  }
  if (rows.length < 2 && !(rows.length == 1 && sawSep)) return null;
  final padded = _pad(rows);
  if (padded.isEmpty || padded.first.length < 2) return null;
  return padded;
}

bool _tableLine(String l) {
  final t = l.trim();
  if (t.startsWith('|')) return true;
  if (_bulletRx.hasMatch(l) || _numRx.hasMatch(l)) return false;
  return '|'.allMatches(t).length >= 2 || (_sepRx.hasMatch(t) && t.contains('|') && t.contains('-'));
}

List<_Tok> _tokenize(String md, {required bool hashMode}) {
  final lines = _unwall([for (final l in md.split('\n')) _indentFix(l).trimRight()]);
  final toks = <_Tok>[];
  final stack = <int>[];
  var prevType = '';
  int nextNonBlank(int i) {
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].trim().isNotEmpty) return j;
    }
    return -1;
  }

  void add(AiBlock b) {
    toks.add(_Tok(block: b));
    prevType = b.type;
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final t = line.trim();
    if (t.isEmpty) {
      continue;
    }
    // fenced code
    if (t.startsWith('```')) {
      final buf = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buf.add(lines[i]);
        i++;
      }
      final code = buf.join('\n').trim();
      if (code.isNotEmpty) add(AiBlock('c', code));
      stack.clear();
      continue;
    }
    if (_ruleRx.hasMatch(line)) continue;
    // table
    if (_tableLine(line)) {
      final grp = <String>[line];
      var j = i + 1;
      while (j < lines.length && lines[j].trim().isNotEmpty && _tableLine(lines[j])) {
        grp.add(lines[j]);
        j++;
      }
      final tab = _tableFromLines(grp);
      if (tab != null) {
        add(AiBlock('t', '', rows: tab));
        stack.clear();
        i = j - 1;
        continue;
      }
    }
    final hm = _hashRx.firstMatch(line);
    if (hm != null) {
      var h = hm.group(2)!.replaceAll(RegExp(r'[:：]\s*$'), '').trim();
      h = h.replaceAllMapped(RegExp(r'^(\*\*|__)(.+)\1$'), (m) => m[2]!);
      toks.add(_Tok(head: h, level: hm.group(1)!.length));
      prevType = 'H';
      stack.clear();
      continue;
    }
    final sm = _srcLineRx.firstMatch(line);
    if (sm != null) {
      final parts = sm.group(2)!.split(RegExp(r'\s*;\s*|\s+\|\s+|\s+•\s+'));
      toks.add(_Tok(refs: [for (final p in parts) if (p.trim().isNotEmpty) citeFromText(p)]));
      prevType = 'S';
      continue;
    }
    final rd = _refDefRx.firstMatch(line);
    if (rd != null && (_urlRx.hasMatch(line) || _yearRx.hasMatch(line) || RegExp(r'^[A-Z]').hasMatch(rd.group(2)!)) && !RegExp(r'[.!?]\s+[a-z]').hasMatch(rd.group(2)!.substring(0, rd.group(2)!.length.clamp(0, 40)))) {
      toks.add(_Tok(refs: [citeFromText(rd.group(2)!)]));
      prevType = 'S';
      continue;
    }
    final bm = _bulletRx.firstMatch(line);
    if (bm != null) {
      final ind = bm.group(1)!.length;
      while (stack.isNotEmpty && ind < stack.last) {
        stack.removeLast();
      }
      if (stack.isEmpty || ind > stack.last) stack.add(ind);
      final lvl = (stack.length - 1).clamp(0, 3);
      var body = bm.group(3)!;
      body = body.replaceFirst(RegExp(r'^\[[ xX]\]\s*'), '');
      final am = _acrRx.firstMatch(body);
      if (am != null && _acronymOk(am.group(1)!, am.group(2)!)) {
        add(AiBlock('m', body));
      } else {
        add(AiBlock('b', body, level: lvl));
      }
      continue;
    }
    final nm = _numRx.firstMatch(line);
    if (nm != null) {
      final body = nm.group(4)!;
      final words = stripInline(body).trim().split(RegExp(r'\s+')).length;
      final ni = nextNonBlank(i);
      final nextLine = ni < 0 ? '' : lines[ni];
      final nextNum = nextLine.isNotEmpty && _numRx.hasMatch(nextLine);
      final nextIndented = nextLine.isNotEmpty && _indentOf(nextLine) >= 2 && !nextNum;
      final headish = words <= 5 && !RegExp(r'[.!?;,،]$').hasMatch(stripInline(body).trim()) && nextLine.isNotEmpty && !nextNum && !nextIndented && prevType != 'n';
      if (headish) {
        toks.add(_Tok(head: stripInline(body).replaceAll(RegExp(r'[:：]\s*$'), '').trim(), level: 8));
        prevType = 'H';
        stack.clear();
      } else {
        stack.clear();
        add(AiBlock('n', body));
      }
      continue;
    }
    // indented continuation of a bullet / step
    if (_indentOf(line) >= 2 && (prevType == 'b' || prevType == 'n') && toks.isNotEmpty && toks.last.block != null && !_boldLineRx.hasMatch(line)) {
      final last = toks.removeLast().block!;
      toks.add(_Tok(block: AiBlock(last.type, '${last.text} $t', level: last.level)));
      continue;
    }
    stack.clear();
    final bl = _boldLineRx.firstMatch(line);
    if (bl != null && bl.group(2)!.trim().length <= 80) {
      final h = bl.group(2)!.replaceFirst(RegExp(r'^\d{1,2}[.)]\s*'), '').trim();
      toks.add(_Tok(head: h, level: 7));
      prevType = 'H';
      continue;
    }
    final ml = _mnemLead.firstMatch(line);
    if (ml != null) {
      toks.add(_Tok(head: ml.group(1)!, level: 8, rest: ml.group(2)!.trim()));
      prevType = 'H';
      continue;
    }
    final am = _acrRx.firstMatch(t);
    if (am != null && _acronymOk(am.group(1)!, am.group(2)!)) {
      add(AiBlock('m', t));
      continue;
    }
    final lm = _leadRx.firstMatch(line);
    if (lm != null) {
      final label = stripInline(lm.group(1)!).trim();
      if (label.split(RegExp(r'\s+')).length <= 5 && kindOfTitle(label) != null) {
        toks.add(_Tok(head: label, level: 8, rest: lm.group(2)!.trim()));
        prevType = 'H';
        continue;
      }
    }
    final plain = stripInline(t);
    if (RegExp(r'[:：]$').hasMatch(plain) && plain.length <= 70 && plain.split(RegExp(r'\s+')).length <= 8) {
      toks.add(_Tok(head: plain.replaceAll(RegExp(r'[:：]\s*$'), '').trim(), level: 8));
      prevType = 'H';
      continue;
    }
    final letters = plain.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.length >= 3 && plain.length <= 60 && plain == plain.toUpperCase() && !RegExp(r'[.!?]$').hasMatch(plain) && (plain.trim().contains(' ') || kindOfTitle(plain) != null) && !RegExp(r'\d').hasMatch(plain)) {
      toks.add(_Tok(head: plain, level: 8));
      prevType = 'H';
      continue;
    }
    if (plain.split(RegExp(r'\s+')).length <= 5 && !RegExp(r'[.!?;,،:]$').hasMatch(plain) && kindOfTitle(plain) != null && !hashMode) {
      final ni = nextNonBlank(i);
      if (ni >= 0 && (_bulletRx.hasMatch(lines[ni]) || _numRx.hasMatch(lines[ni]) || _tableLine(lines[ni]))) {
        toks.add(_Tok(head: plain, level: 8));
        prevType = 'H';
        continue;
      }
    }
    add(AiBlock('p', t));
  }
  return toks;
}

// ---------------------------------------------------------------------------------------------- markdown -> doc

bool _subLabel(String t) => RegExp(r"^\W*(un)?stable|^\W*(mild|moderate|severe)\b|^\W*(adults?|children|paediatrics?|pediatrics?|elderly|pregnan\w*)\b|^\W*(first|second|third)[- ]line|مستقر|غير مستقر|بالغين|أطفال|الأطفال", caseSensitive: false).hasMatch(t.trim());

class _SecB {
  String kind;
  String title;
  final List<AiBlock> blocks = [];
  _SecB(this.kind, this.title);
}

AiDoc _rebuild(String md, String raw) {
  final hashMode0 = RegExp(r'^\s{0,3}#{1,6}\s+\S', multiLine: true).hasMatch(md);
  final toks = _tokenize(md, hashMode: hashMode0);
  final levels = [for (final t in toks) if (t.head != null && t.level >= 1 && t.level <= 6) t.level];
  var secLevel = 0;
  var title = '';
  var skipFirstH1 = false;
  if (levels.isNotEmpty) {
    final mn = levels.reduce((a, b) => a < b ? a : b);
    secLevel = mn;
    if (mn == 1 && levels.where((l) => l == 1).length == 1 && levels.length > 1) {
      secLevel = levels.where((l) => l > 1).reduce((a, b) => a < b ? a : b);
      skipFirstH1 = true;
    }
  }
  final hashMode = levels.isNotEmpty;
  final secs = <_SecB>[];
  final cites = <AiCite>[];
  final unc = <String>[];
  _SecB? cur;
  _SecB ensure() {
    if (cur == null) {
      cur = _SecB('overview', '');
      secs.add(cur!);
    }
    return cur!;
  }

  for (final t in toks) {
    if (t.refs.isNotEmpty) {
      cites.addAll(t.refs);
      continue;
    }
    if (t.head != null) {
      final h = stripInline(t.head!).trim();
      final lvl = t.level;
      final isTitleH1 = skipFirstH1 && lvl == 1 && title.isEmpty;
      if (isTitleH1) {
        title = h;
        continue;
      }
      final kind = kindOfTitle(h);
      var asSection = false;
      if (hashMode) {
        if (lvl <= 6) {
          asSection = lvl <= secLevel;
        } else {
          asSection = kind != null && kind != 'overview' && !(cur != null && cur!.kind == 'management' && _subLabel(h));
        }
        if (lvl <= 6 && lvl > secLevel && kind != null && (kind == 'red_flags' || kind == 'dont_miss' || kind == 'references') && (cur == null || cur!.kind != kind)) asSection = true;
      } else {
        asSection = !(cur != null && _subLabel(h));
      }
      if (asSection) {
        cur = _SecB(kind ?? 'other', h);
        secs.add(cur!);
        if (t.rest.isNotEmpty) cur!.blocks.add(AiBlock('p', t.rest));
      } else {
        final c = ensure();
        c.blocks.add(AiBlock('h', h));
        if (t.rest.isNotEmpty) c.blocks.add(AiBlock('p', t.rest));
      }
      continue;
    }
    final b = t.block!;
    final c = ensure();
    if (c.kind == 'references' && (b.type == 'b' || b.type == 'n' || b.type == 'p')) {
      cites.add(citeFromText(b.text));
      continue;
    }
    c.blocks.add(b);
  }

  // post-process
  final out = <AiDocSection>[];
  final structuredOnly = secs.length == 1 && secs.first.title.isEmpty;
  for (final s in secs) {
    if (s.blocks.isEmpty && s.title.isEmpty) continue;
    var kind = s.kind;
    if (kind == 'uncertainties') {
      for (final b in s.blocks) {
        if (b.type == 'b' || b.type == 'n' || b.type == 'p' || b.type == 'm') unc.add(b.text);
      }
      continue;
    }
    if (kind == 'references') {
      if (s.blocks.isEmpty) continue;
    }
    final types = s.blocks.map((b) => b.type).toSet();
    if (kind == 'other' || kind == 'overview' && s.title.isEmpty) {
      if (types.length == 1 && types.first == 't') kind = 'table';
      if (types.length == 1 && types.first == 'n') kind = 'steps';
      if (types.length == 1 && types.first == 'm') kind = 'mnemonic';
    }
    if (s.title.isEmpty && kind == 'overview' && types.every((t) => t == 'b' || t == 'h')) kind = 'key_points';
    final tab = s.blocks.where((b) => b.type == 't').map((b) => b.rows).firstOrNull;
    if (tab != null && (kind == 'other' || kind == 'table') && _isGuidelineTable(tab)) kind = 'guidelines';
    // a single short plain answer with no structure
    if (structuredOnly && kind == 'overview' && types.every((t) => t == 'p')) kind = 'note';
    out.add(_mk(kind, s.title, s.blocks));
  }
  // inline citations (Org Year) and URLs become citation entries when not listed
  final inlineSeen = <String>{};
  void scan(String text) {
    for (final m in orgYearRx.allMatches(text)) {
      final org = m.group(1)!.trim();
      final year = m.group(2)!;
      final key = '$org $year'.toLowerCase();
      if (inlineSeen.contains(key)) continue;
      inlineSeen.add(key);
      final listed = cites.any((c) => c.label.toLowerCase().contains(org.toLowerCase().split(' ').first) && c.label.contains(year));
      if (!listed) cites.add(AiCite(label: '$org ($year)', org: org.split(RegExp(r'[\s,]')).first, year: year.replaceAll(RegExp(r'[a-z]'), '')));
    }
    for (final m in orgBareRx.allMatches(text)) {
      final org = m.group(1)!;
      final code = m.group(2) ?? '';
      final year = m.group(3) ?? '';
      if (code.isEmpty && year.isEmpty) continue;
      if (code.toLowerCase().startsWith('guideline') && year.isEmpty) continue;
      final key = '$org $code $year'.trim().toLowerCase();
      if (inlineSeen.contains(key)) continue;
      inlineSeen.add(key);
      final listed = cites.any((c) => c.label.toLowerCase().contains(org.toLowerCase()) && (year.isEmpty || c.label.contains(year)) && (code.isEmpty || c.label.contains(code)));
      if (!listed) cites.add(AiCite(label: '$org ${code.toLowerCase().startsWith('guideline') ? '' : code} ${year.isEmpty ? '' : '($year)'}'.replaceAll(RegExp(r'\s+'), ' ').trim(), org: org, year: year));
    }
    for (final m in _urlRx.allMatches(text)) {
      final u = m.group(0)!.replaceAll(RegExp(r'[.,;:]+$'), '');
      if (!cites.any((c) => c.url == u)) cites.add(AiCite(label: Uri.tryParse(u)?.host ?? u, url: u));
    }
  }

  for (final s in out) {
    for (final b in s.allBlocks) {
      if (b.type != 't') scan(b.text);
    }
  }
  return AiDoc(sections: out, citations: cites, raw: raw, structured: false, title: title, uncertainties: unc);
}

bool _isGuidelineTable(List<List<String>> t) {
  if (t.isEmpty || t.first.length < 2) return false;
  final h = t.first.map((e) => e.toLowerCase()).join(' ');
  return RegExp(r'organi[sz]ation|society|guideline|body|issuer|الجهة|المنظمة|الإرشاد').hasMatch(h) && RegExp(r'recommend|year|توصية|السنة').hasMatch(h);
}

// ---------------------------------------------------------------------------------------------- export

String _kindTitle(AiDocSection s) => s.title.isNotEmpty ? s.title : tr(kKindLabel[s.kind] ?? 'Details');

String docToText(AiDoc d, {required bool markdown, bool footer = true}) {
  final o = StringBuffer();
  String f(String s) => markdown ? s.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => '**${m[1]}**') : stripInline(s);
  if (d.title.isNotEmpty) o.writeln(markdown ? '# ${d.title}\n' : '${d.title}\n');
  for (final s in d.sections) {
    final hasHead = s.kind != 'note' || s.title.isNotEmpty;
    if (hasHead) o.writeln(markdown ? '## ${_kindTitle(s)}' : _kindTitle(s).toUpperCase());
    var n = 0;
    for (final b in s.allBlocks) {
      if (b.type != 'n') n = 0;
      switch (b.type) {
        case 'b':
          o.writeln('${'  ' * b.level}${markdown ? '-' : '•'} ${f(b.text)}');
          break;
        case 'n':
          n++;
          o.writeln('$n. ${f(b.text)}');
          break;
        case 'h':
          o.writeln(markdown ? '\n### ${stripInline(b.text)}' : '${stripInline(b.text)}:');
          break;
        case 'm':
          o.writeln(markdown ? '> ${f(b.text)}' : f(b.text));
          break;
        case 'c':
          o.writeln(markdown ? '```\n${b.text}\n```' : b.text);
          break;
        case 't':
          if (b.rows.isNotEmpty) {
            if (markdown) {
              o.writeln('| ${b.rows.first.map(stripInline).join(' | ')} |');
              o.writeln('|${List.filled(b.rows.first.length, ' --- ').join('|')}|');
              for (final r in b.rows.skip(1)) {
                o.writeln('| ${r.map(stripInline).join(' | ')} |');
              }
            } else {
              for (final r in b.rows) {
                o.writeln(r.map(stripInline).join(' | '));
              }
            }
          }
          break;
        default:
          o.writeln(f(b.text));
      }
    }
    o.writeln();
  }
  if (d.uncertainties.isNotEmpty) {
    o.writeln(markdown ? '## ${tr('What I could not verify')}' : tr('What I could not verify').toUpperCase());
    for (final u in d.uncertainties) {
      o.writeln('${markdown ? '-' : '•'} ${f(u)}');
    }
    o.writeln();
  }
  if (d.citations.isNotEmpty) {
    o.writeln(markdown ? '## ${tr('References')}' : tr('References').toUpperCase());
    for (var i = 0; i < d.citations.length; i++) {
      final c = d.citations[i];
      var lab = c.label.isNotEmpty ? c.label : c.short;
      if (c.org.isNotEmpty && !lab.contains(c.org)) lab = '${c.org} $lab';
      if (c.year.isNotEmpty && !lab.contains(c.year)) lab = '$lab (${c.year})';
      o.writeln('[${i + 1}] $lab${c.url.isNotEmpty && !lab.contains(c.url) ? ' ${c.url}' : ''}');
    }
    o.writeln();
  }
  if (d.disclaimer.isNotEmpty) o.writeln(d.disclaimer);
  if (!footer) return o.toString().trim();
  o.write(markdown ? '_${tr('AI-generated, not medically reviewed. Verify with the cited source and your local protocol.')}_' : tr('AI-generated, not medically reviewed. Verify with the cited source and your local protocol.'));
  return o.toString().trim();
}
