import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import 'core_topics.dart';
import 'data.dart';
import 'lib_text.dart';
import 'lib_user.dart';
import 'library.dart';
import 'quiz_gate.dart';

export 'quiz_gate.dart';

/// Self-test questions made only from the text of the library articles you downloaded.
/// Nothing is invented: every question is a sentence, a bullet or a title of an article. The default
/// pool is the Core 250 topics (weighted by your rotation, favorites and weak spots); the wrong
/// options are real text of OTHER articles of the same specialty and the same kind of text (other
/// conditions for "which condition", other drugs for a drug, other numbers with the same unit).
/// Every generated question goes through [gateQuestion]; the ones that fail are dropped.

enum QuizSource { core, all, rotation, cases, favorites, weak, random }

/// What the last [buildQuiz] did (shown on the screens and used by the tests).
class QuizReport {
  QuizSource source = QuizSource.all;
  QuizLevel level = QuizLevel.medium;
  QuizSource? fallbackFrom; // the chosen source had fewer than 3 articles
  int pool = 0;
  int reads = 0;
  int generated = 0; // questions built before the gate
  int dropped = 0; // questions the gate rejected
  final Map<String, int> droppedWhy = {};
  final Map<QKind, int> kinds = {for (final k in QKind.values) k: 0};
}

QuizReport lastQuizReport = QuizReport();

/// Milliseconds spent in the phases of the last [buildQuiz] (for tests and tuning).
final Map<String, int> quizTimings = {};

String _cleanTitle(String t) => t.replaceAll(RegExp(r'\s+—\s+(WikEM|Wikipedia|CDC|NCI|Project Tulip|MedlinePlus)$'), '').replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

final RegExp _medSuffix = RegExp(r'(itis|osis|pathy|ectomy|plasty|emia|oma|ase|ine|ide|mab|ism|algia|plegia|uria|penia|trophy|stomy|otomy|scopy|graphy)$', caseSensitive: false);
final RegExp _drugStrong = RegExp(
    r'(mab|pril|sartan|olol|statin|cillin|mycin|azole|vir|oxacin|cycline|triptan|dipine|prazole|tidine|epam|olam|thiazide|parin|xaban|gliptin|glitazone|formin|profen|fenac|coxib|setron|terol|navir|caine|sone|olone|penem|bactam|barbital|mol|tinib|ciclib)$',
    caseSensitive: false);
final RegExp _procSuffix = RegExp(r'(ectomy|plasty|otomy|ostomy|scopy|desis|pexy|rrhaphy)$', caseSensitive: false);
const Set<String> _drugWords = {
  'aspirin', 'acetaminophen', 'warfarin', 'heparin', 'insulin', 'digoxin', 'amiodarone', 'adenosine', 'atropine', 'lidocaine', 'morphine', 'codeine', 'tramadol', 'oxycodone', 'fentanyl',
  'gabapentin', 'pregabalin', 'methotrexate', 'colchicine', 'allopurinol', 'hydroxychloroquine', 'sulfasalazine', 'tamoxifen', 'levothyroxine', 'epinephrine', 'adrenaline', 'naloxone',
  'nitroglycerin', 'dopamine', 'dobutamine', 'noradrenaline', 'norepinephrine', 'vancomycin', 'ibuprofen', 'naproxen', 'diclofenac', 'prednisone', 'prednisolone', 'dexamethasone', 'furosemide',
  'labetalol', 'nicardipine', 'magnesium', 'calcium', 'albuterol', 'ceftriaxone', 'azithromycin', 'doxycycline', 'metoprolol', 'diltiazem', 'verapamil', 'tenecteplase', 'alteplase',
};
const Set<String> _procWords = {
  'physiotherapy', 'radiotherapy', 'chemotherapy', 'immunotherapy', 'dialysis', 'transfusion', 'thrombolysis', 'intubation', 'cardioversion', 'defibrillation', 'immobilization', 'immobilisation',
  'traction', 'splinting', 'casting', 'angioplasty', 'arthrodesis', 'bracing', 'ventilation', 'resuscitation', 'drainage', 'debridement', 'cementation',
};
const Set<String> _notDrug = {
  'medicine', 'medicines', 'routine', 'determine', 'examine', 'guideline', 'guidelines', 'decline', 'combine', 'define', 'disease', 'diseases', 'increase', 'decrease', 'release', 'purchase', 'database',
  'baseline', 'outside', 'inside', 'provide', 'provided', 'divide', 'decide', 'alongside', 'bedside', 'intestine', 'intestines', 'uterine', 'bovine', 'canine', 'feline', 'equine', 'magazine', 'heroine',
  'sometimes', 'determined', 'examined', 'endocrine', 'exocrine', 'paracrine', 'medicinal', 'vaccine', 'vaccines', 'amine', 'porcine', 'carotene', 'adjacent', 'pipeline', 'discipline',
  'peritoneum', 'online', 'mainstream', 'undertaken', 'worldwide', 'nationwide', 'oxide', 'creatinine', 'glutamine', 'histamine', 'serotonine', 'molecule', 'molecules', 'disorder', 'syndrome',
  'cholesterol', 'ergosterol', 'sterol', 'cortisol', 'sulfonamide', 'amide', 'amino', 'hormone', 'hormones', 'infection', 'infections', 'inflammation', 'symptoms', 'diagnosis', 'diagnoses', 'tuberculosis', 'prognosis', 'hypothesis',
};

/// Hides the title (and its long words) inside a sentence.
String? maskTitle(String sentence, String title) {
  final base = _cleanTitle(title);
  if (base.length < 4) return null;
  var s = sentence;
  s = s.replaceAll(RegExp(RegExp.escape(base), caseSensitive: false), '____');
  s = s.replaceAll(RegExp(r'\(\s*(also|or|abbreviated|commonly|known|sometimes|often)[^)]*\)', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'\(\s*[A-Z][A-Za-z]{1,6}s?\s*\)'), '');
  for (final w in base.split(RegExp(r'[\s\-/]+'))) {
    if (w.length >= 6) s = s.replaceAll(RegExp('\\b${RegExp.escape(w)}\\w*', caseSensitive: false), '____');
  }
  s = s.replaceAll(RegExp(r'(____\s*){2,}'), '____ ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.contains('____') ? s : null;
}

List<String> _keyTerms(String sentence) {
  final out = <String>[];
  for (final m in RegExp(r"\b[A-Za-z][A-Za-z\-]{6,}\b").allMatches(sentence)) {
    final w = m.group(0)!;
    if (kGenericWords.contains(w.toLowerCase()) || _stopWords.contains(w.toLowerCase())) continue;
    out.add(w);
  }
  return out;
}

const Set<String> _stopWords = {
  'however', 'because', 'although', 'between', 'including', 'usually', 'typically', 'commonly', 'several', 'another', 'patients', 'patient', 'without', 'through', 'during', 'compared', 'increased', 'decreased', 'associated', 'approximately', 'following', 'certain', 'different', 'sometimes', 'generally', 'particularly', 'especially', 'recommended', 'considered', 'whereas', 'therefore', 'experience', 'experienced', 'important', 'available', 'difficult', 'difficulty', 'information', 'development', 'understanding', 'environment', 'individual', 'individuals', 'population', 'populations', 'relationship', 'application', 'activities', 'significant', 'performance', 'professional', 'community', 'example', 'examples', 'knowledge', 'sufficient', 'production', 'secondary', 'condition', 'conditions', 'improvement', 'research', 'incidence', 'treatment', 'diagnosis', 'symptoms', 'disease', 'people', 'children', 'medical', 'clinical', 'studies', 'results',
};

// ---------------------------------------------------------------- terms

enum _TK { drug, proc, disease, other }

class _Term {
  final String text;
  final String key; // pack|index of the article
  final String group;
  final String low;
  _TK? _k;
  _Term(this.text, this.key, this.group) : low = text.toLowerCase();
  _TK get kind => _k ??= _kindOf(text);
}

_TK _kindOf(String w) {
  final l = w.toLowerCase();
  if (_drugWords.contains(l) || _drugStrong.hasMatch(l)) return _TK.drug;
  if (_procWords.contains(l) || _procSuffix.hasMatch(l)) return _TK.proc;
  if (_medSuffix.hasMatch(l)) return _TK.disease;
  return _TK.other;
}

/// Drug or procedure word of a treatment sentence (null when it is not clear).
_TK? _treatmentKind(String w) {
  final l = w.toLowerCase();
  if (_notDrug.contains(l)) return null;
  if (_drugWords.contains(l) || (_drugStrong.hasMatch(l) && l.length >= 6)) return _TK.drug;
  if (_procWords.contains(l) || (_procSuffix.hasMatch(l) && l.length >= 7)) return _TK.proc;
  return null;
}

// ---------------------------------------------------------------- units of an article

/// A sentence or bullet of an article with where it comes from.
class _U {
  final String text;
  final bool bullet;
  final Canon sec;
  final String heading;
  final String sub;
  const _U(this.text, this.bullet, this.sec, this.heading, this.sub);
}

List<_U> _unitsOf(LibArticle a, bool structured) {
  final out = <_U>[];
  for (final s in a.sections) {
    final sec = canonOf(s.heading);
    var sub = '';
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      for (final snt in sentences(buf.toString())) {
        final t = tidy(snt);
        if (t.isNotEmpty) out.add(_U(t, false, sec, s.heading, sub));
      }
      buf.clear();
    }

    for (final line in s.text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('▸')) {
        flush();
        sub = t.substring(1).trim();
        continue;
      }
      if (t.startsWith('•') || t.startsWith('–') || t.startsWith('- ')) {
        flush();
        final x = tidy(t.substring(1));
        if (x.isEmpty) continue;
        final words = x.split(' ').length;
        // bullets are real facts in WikEM / Tulip / CDC; elsewhere they are often picture captions
        if (structured || (x.endsWith('.') && words >= 6)) out.add(_U(x, true, sec, s.heading, sub));
        continue;
      }
      buf.write('$t ');
    }
    flush();
  }
  return out;
}

final Map<String, List<_U>> _unitCache = {};

class _Rd {
  final String pid;
  final int idx;
  final LibArticle art;
  final String allLower;
  final QuizLevel level;
  final String group;
  final bool core;
  final bool structured;
  final String title; // cleaned title
  late final List<_U> units = _unitCache.putIfAbsent('$pid|$idx', () {
    if (_unitCache.length > 400) _unitCache.clear();
    return _unitsOf(art, structured);
  });
  _Rd(this.pid, this.idx, this.art, this.allLower, this.level, this.group, this.core, this.structured) : title = _cleanTitle(art.title);
  String get key => '$pid|$idx';
}

class _Finding {
  final String text;
  final String key;
  final String group;
  final String src;
  const _Finding(this.text, this.key, this.group, this.src);
}

class _TitleRef {
  final String title;
  final String key;
  final String group;
  const _TitleRef(this.title, this.key, this.group);
}

class _Num {
  final QuantityHit hit;
  final String key;
  final String group;
  const _Num(this.hit, this.key, this.group);
}

class _Line {
  final String text;
  final String key;
  final String group;
  final bool bullet;
  late final Set<String> words = distinctiveWords(text);
  _Line(this.text, this.key, this.group, this.bullet);
}

class _Pools {
  final List<_Term> cloze = [];
  final List<_Term> treat = [];
  final List<_Finding> findings = [];
  final List<_Line> mgmt = [];
  final List<_Line> red = [];
  final List<_Num> nums = [];
  final List<_TitleRef> titles = [];
  final Set<String> titleKeys = {};
  int reads = 0;
  int tfTrue = 0, tfFalse = 0; // keeps true / false statements balanced
}

const List<Canon> _clinicalCanon = [Canon.symptoms, Canon.diagnosis, Canon.treatment, Canon.causes, Canon.pathophys, Canon.complications, Canon.differential];

/// Article worth asking about: not a stub, not an organisation / person, has real text.
bool articleWorthAsking(LibArticle a, {bool core = false}) {
  if (a.sections.isEmpty) return false;
  if (!core) {
    // not a Core 250 topic: only real clinical articles (at least two of symptoms / diagnosis / treatment / causes sections)
    final kinds = <Canon>{for (final s in a.sections) if (const [Canon.symptoms, Canon.diagnosis, Canon.treatment, Canon.causes, Canon.complications].contains(canonOf(s.heading))) canonOf(s.heading)};
    if (kinds.length < 2) return false;
  }
  final lead = a.sections.first.text;
  if (lead.length < 100) return false;
  final total = a.sections.fold<int>(0, (n, s) => n + s.text.length);
  if (total < 1000) return false;
  if (_orgTitle.hasMatch(a.title) || _orgLead.hasMatch(lead)) return false;
  return true;
}

// ---------------------------------------------------------------- candidates

class QuizPick {
  final String packId;
  final int index;
  final String title;
  final double weight;
  const QuizPick(this.packId, this.index, this.title, this.weight);
}

class _C {
  final String pid;
  final int idx;
  final String title;
  final String lead;
  final double base;
  double w = 1;
  _C(this.pid, this.idx, this.title, this.lead, this.base);
  late final String key = '$pid|$idx';
}

/// Base weights of all titles of a course, computed in a background isolate (regex work on thousands of leads).
Float32List _baseWeights((List<String>, List<String>) tl) {
  final (t, l) = tl;
  final out = Float32List(t.length);
  for (var i = 0; i < t.length; i++) {
    out[i] = _baseWeight(t[i], l[i]);
  }
  return out;
}

/// Candidate objects per course (base weights need regexes on every title: computed once per pack
/// version, kept in memory and in a small file next to the pack, so later quizzes do not repeat it).
final Map<String, (String, List<_C>)> _candCache = {};

Future<List<_C>> _packCands(PackMeta p) async {
  final sig = '${p.count}|${p.date}|${p.bytes}';
  final hit = _candCache[p.id];
  if (hit != null && hit.$1 == sig) return hit.$2;
  final t = await library.titlesOf(p.id), l = await library.leadsOf(p.id);
  Float32List? cached;
  final f = File('${library.dir.path}/${p.id}.qw');
  try {
    final idx = File('${library.dir.path}/${p.id}.idx');
    if (f.existsSync() && !f.lastModifiedSync().isBefore(idx.lastModifiedSync())) {
      final b = await f.readAsBytes();
      if (b.length == t.length * 4) cached = Float32List.view(Uint8List.fromList(b).buffer);
    }
  } catch (_) {}
  final Float32List w = cached ?? await compute<(List<String>, List<String>), Float32List>(_baseWeights, (t, l));
  if (cached == null) {
    try {
      await f.writeAsBytes(w.buffer.asUint8List(), flush: true);
    } catch (_) {}
  }
  final list = <_C>[for (var i = 0; i < t.length; i++) _C(p.id, i, t[i], l[i], w[i])];
  _candCache[p.id] = (sig, list);
  return list;
}

final RegExp _orgTitle = RegExp(r'\b(organi[sz]ation|association|society|institute|foundation|hospital|university|college|council|journal|list of|index of|timeline|history of|awards?|ministry|agency|company|corporation|clinic|school of|department|congress|federation)\b', caseSensitive: false);
final RegExp _orgLead = RegExp(r'\b(is|was|are) (an?|the) [^.]{0,50}(organi[sz]ation|company|society|institution|journal|hospital|university|agency|nonprofit|charity|born|physician|surgeon|researcher|professor|politician|footballer|actor)', caseSensitive: false);
final RegExp _medLead = RegExp(r'\b(disease|disorder|condition|syndrome|infection|symptom|treatment|pain|cancer|injury|fracture|inflammation|deficiency|failure|tumou?r|diagnos|drug|medication|surgery|therapy|chronic|acute)', caseSensitive: false);

double _baseWeight(String title, String lead) {
  var w = 1.0;
  if (lead.length < 60) {
    w *= 0.15;
  } else if (lead.length < 120) {
    w *= 0.5;
  }
  if (_orgTitle.hasMatch(title) || _orgLead.hasMatch(lead)) w *= 0.12;
  if (_medLead.hasMatch(lead)) w *= 1.6;
  if (title.length < 4) w *= 0.3;
  return w;
}

/// True for articles that look like clinical topics (not organisations, people or stubs): used by the exam planner.
bool planWorthy(String title, String lead) => _baseWeight(title, lead) >= 1;

class _Sets {
  final Set<String> fav = {};
  final Set<String> recent = {};
  final Set<String> cases = {};
  final Set<String> weak = {};
  String? rotPack;
  String? rotSpec;
}

Future<_Sets> _loadSets() async {
  final s = _Sets();
  try {
    final rot = store.currentRotation();
    if (rot != null) {
      final name = '${rot['name'] ?? ''}';
      final id = packIdForRotation(name);
      if (id != null && library.pack(id) != null) s.rotPack = id;
      s.rotSpec = specialtyForRotation(name);
    }
  } catch (_) {}
  Future<void> add(Set<String> into, String p, String t) async {
    if (library.pack(p) == null) return;
    final i = await library.indexOfTitle(p, t);
    if (i != null) into.add('$p|$i');
  }

  try {
    for (final f in favorites()) {
      await add(s.fav, '${f['pack']}', '${f['title']}');
    }
    for (final f in recentArticles()) {
      await add(s.recent, '${f['p']}', '${f['t']}');
    }
    for (final w in weakSpots()) {
      await add(s.weak, w.packId, w.title);
    }
  } catch (_) {}
  try {
    final seen = <String>{};
    var n = 0;
    for (final c in store.cases.values) {
      final dx = [c.s('finalDx'), c.s('workingDx')].firstWhere((e) => e.trim().isNotEmpty, orElse: () => '').trim().toLowerCase();
      if (dx.isEmpty || !seen.add(dx)) continue;
      if (++n > 25) break;
      for (final h in (await articlesForCase(c)).take(3)) {
        s.cases.add('${h.packId}|${h.index}');
      }
    }
  } catch (_) {}
  return s;
}

/// Source used when the caller does not choose: Core 250 (or all installed articles when the study universe says so).
QuizSource defaultQuizSource() => studyUniverse() == kUniverseAll ? QuizSource.all : QuizSource.core;

/// The weighted choice of articles (exposed for tests). Higher weight = more likely.
Future<List<QuizPick>> pickArticles({String? packId, String? query, int count = 10, int? seed, QuizSource? source, int? limit, String? sourceFilter}) async {
  final rnd = Random(seed ?? DateTime.now().millisecondsSinceEpoch);
  final cs = await _candidates(packId, query, source ?? defaultQuizSource(), sourceFilter, null);
  return [for (final c in _draw(cs, rnd, limit ?? min(60, max(count * 3, 12)))) QuizPick(c.pid, c.idx, c.title, c.w)];
}

_Sets _lastSets = _Sets();
Map<String, CoreTopic> _lastCore = {};

Future<List<_C>> _candidates(String? packId, String? query, QuizSource source, String? sourceFilter, List<QuizPick>? only) async {
  final report = lastQuizReport = QuizReport()..source = source;
  final packs = [for (final p in library.textPacks) if (packId == null || p.id == packId) p];
  if (packs.isEmpty) return const [];
  final sets = _lastSets = await _loadSets();
  _lastCore = await coreByKey();
  final hasQuery = query != null && query.trim().isNotEmpty;

  // explicit article list ("practice again")
  if (only != null) {
    final out = <_C>[for (final p in only) _C(p.packId, p.index, p.title, '', 1)];
    report.pool = out.length;
    return out;
  }

  double coreW(String key) {
    final t = _lastCore[key];
    return t == null ? 1 : (t.priority == 1 ? 1.0 : 0.7);
  }

  void weighCore(List<_C> list) {
    for (final c in list) {
      var w = c.base;
      final t = _lastCore[c.key]!;
      if (sets.weak.contains(c.key)) w *= 8;
      if (sets.fav.contains(c.key)) w *= 4;
      if (sets.recent.contains(c.key)) w *= 2.5;
      if (sets.cases.contains(c.key)) w *= 3;
      if (sets.rotSpec != null && t.specialty == sets.rotSpec) w *= 3;
      c.w = w;
    }
  }

  // Core 250: the resolved topics (default pool)
  if ((source == QuizSource.core || (source == QuizSource.rotation && sets.rotSpec != null && studyUniverse() == kUniverseCore)) && packId == null && !hasQuery) {
    final topics = [
      for (final t in _lastCore.values)
        if (source == QuizSource.core || t.specialty == sets.rotSpec) t
    ];
    final all = <_C>[];
    for (final t in topics) {
      if (sourceFilter != null && library.sourceOf(t.packId!, t.title!) != sourceFilter) continue;
      all.add(_C(t.packId!, t.index!, t.title!, '', coreW(t.key)));
    }
    if (all.length >= 3) {
      weighCore(all);
      report.pool = all.length;
      return all;
    }
    report.fallbackFrom = source;
    source = QuizSource.all;
  }
  final coreWanted = source == QuizSource.core;
  if (coreWanted) {
    source = QuizSource.all; // a course or a topic was chosen
    if (packId != null && !hasQuery) {
      // a course stands for its specialty: the Core 250 topics of that specialty (wherever the article lives)
      final spec = specialtyForRotation(packId);
      final inPack = [
        for (final t in _lastCore.values)
          if ((spec != null ? t.specialty == spec : t.packId == packId) && (sourceFilter == null || library.sourceOf(t.packId!, t.title!) == sourceFilter)) _C(t.packId!, t.index!, t.title!, '', coreW(t.key))
      ];
      if (inPack.length >= 6) {
        weighCore(inPack);
        report.pool = inPack.length;
        return inPack;
      }
    }
  }

  final all = <_C>[];
  if (hasQuery) {
    for (final h in await library.searchEx(query, packId: packId, limit: 80, source: sourceFilter)) {
      all.add(_C(h.packId, h.index, h.title, h.lead, _baseWeight(h.title, h.lead)));
    }
  } else {
    await library.warmUp(packs);
    // weights of packs seen for the first time are computed a few at a time in background isolates
    for (var i = 0; i < packs.length; i += 3) {
      await Future.wait([for (final p in packs.skip(i).take(3)) _packCands(p)]);
    }
    for (final p in packs) {
      all.addAll(await _packCands(p));
    }
  }
  if (sourceFilter != null) {
    all.removeWhere((c) => library.sourceOf(c.pid, c.title) != sourceFilter);
  }
  var pool = all;
  if (source != QuizSource.all && source != QuizSource.random) {
    final Set<String> keys = switch (source) {
      QuizSource.rotation => {for (final c in all) if (c.pid == sets.rotPack) c.key},
      QuizSource.cases => sets.cases,
      QuizSource.favorites => {...sets.fav, ...sets.recent},
      QuizSource.weak => sets.weak,
      _ => <String>{},
    };
    final sub = [for (final c in all) if (keys.contains(c.key)) c];
    if (sub.length >= 3) {
      pool = sub;
    } else {
      report.fallbackFrom ??= source;
    }
  }
  // clinical-looking articles only (no stubs, organisations, people); keep everything when that leaves too little
  final clinical = [for (final c in pool) if (c.base >= 1 || _lastCore.containsKey(c.key) || sets.fav.contains(c.key)) c];
  if (clinical.length >= 20) pool = clinical;
  if (source == QuizSource.random) {
    for (final c in pool) {
      c.w = 1;
    }
  } else {
    for (final c in pool) {
      var w = c.base;
      if (_lastCore.containsKey(c.key)) w *= (coreWanted ? 30 : 6); // Core 250 topics first
      if (sets.weak.contains(c.key)) w *= 8;
      if (sets.fav.contains(c.key)) w *= 4;
      if (sets.recent.contains(c.key)) w *= 2.5;
      if (sets.cases.contains(c.key)) w *= 3;
      if (sets.rotPack != null && c.pid == sets.rotPack) w *= 2;
      c.w = w;
    }
  }
  report.pool = pool.length;
  return pool;
}

/// Weighted sampling without replacement (Efraimidis-Spirakis).
List<_C> _draw(List<_C> pool, Random rnd, int n) {
  if (pool.length <= n) return [...pool]..shuffle(rnd);
  final keys = Float64List(pool.length);
  for (var i = 0; i < pool.length; i++) {
    keys[i] = log(max(rnd.nextDouble(), 1e-12)) / pool[i].w;
  }
  // the n-th largest key is the cut: a native sort of plain doubles is much cheaper than sorting objects
  final sorted = Float64List.fromList(keys)..sort();
  final cut = sorted[sorted.length - n];
  final idx = <int>[for (var i = 0; i < keys.length; i++) if (keys[i] >= cut) i]..sort((a, b) => keys[b].compareTo(keys[a]));
  return [for (final i in idx.take(n)) pool[i]];
}

// ---------------------------------------------------------------- reading

final Map<String, LibArticle> _artCache = {};

Future<LibArticle?> _readCached(String pid, int idx) async {
  final k = '$pid|$idx';
  final hit = _artCache[k];
  if (hit != null) return hit;
  final a = await library.read(pid, idx);
  if (a != null) {
    if (_artCache.length > 500) _artCache.clear();
    _artCache[k] = a;
  }
  return a;
}

String _groupOf(String pid, int idx) => _lastCore['$pid|$idx']?.specialty ?? library.pack(pid)?.title ?? pid;

Future<_Rd?> _makeRd(String pid, int idx, QuizLevel level) async {
  final a = await _readCached(pid, idx);
  if (a == null || a.sections.isEmpty) return null;
  final text = a.sections.map((s) => s.text).join('\n').toLowerCase();
  final src = library.sourceOf(pid, a.title);
  final structured = src == 'WikEM' || src == 'Project Tulip' || src == 'CDC';
  return _Rd(pid, idx, a, text, level, _groupOf(pid, idx), _lastCore.containsKey('$pid|$idx'), structured);
}

// ---------------------------------------------------------------- build

/// Questions per kind: share of the quiz (management and number questions first: they test what a doctor needs).
const Map<QKind, double> _kindWeight = {
  QKind.management: 3,
  QKind.number: 2.5,
  QKind.definition: 1.6,
  QKind.trueFalse: 1.1,
  QKind.redflag: 1.2,
  QKind.treatment: 1.5,
  QKind.symptom: 0.6,
  QKind.cloze: 0.05,
};

/// Builds up to [count] questions. [query] limits the topic ("knee", "sepsis"...), [packId] the course.
/// [source] decides where the articles come from (default: Core 250, or all installed articles when the
/// study universe says so), [level] how hard the wrong options are. [articles] asks only about those articles
/// ("practice again"). What happened (fallback, dropped questions) is in [lastQuizReport].
Future<List<QuizQ>> buildQuiz({
  String? packId,
  String? query,
  int count = 10,
  int? seed,
  QuizSource? source,
  QuizLevel level = QuizLevel.medium,
  String? sourceFilter,
  List<QuizPick>? articles,
  void Function(double progress)? onProgress,
}) async {
  final sw = Stopwatch()..start();
  void lap(String k) {
    quizTimings[k] = sw.elapsedMilliseconds;
    sw.reset();
  }

  final rnd = Random(seed ?? DateTime.now().millisecondsSinceEpoch);
  final cands = await _candidates(packId, query, source ?? defaultQuizSource(), sourceFilter, articles);
  lap('candidates');
  final report = lastQuizReport;
  report.level = level;
  if (cands.isEmpty) return const [];
  final sets = _lastSets;
  final results = quizResultsByArticle();
  QuizLevel levelFor(String key) {
    if (level != QuizLevel.auto) return level;
    if (sets.weak.contains(key)) return QuizLevel.easy;
    final r = results[key];
    if (r != null && r.isNotEmpty && r.first) return QuizLevel.hard;
    return QuizLevel.medium;
  }

  final broadPool = !_lastCore.isNotEmpty || report.source != QuizSource.core;
  final maxReads = articles != null ? articles.length : min(60, max((count * (broadPool ? 5 : 3)).round(), 14));
  final picked = _draw(cands, rnd, maxReads);

  // 1) read the articles that are worth asking about (stubs, organisations and people are skipped)
  final reads = <_Rd>[];
  final haveKeys = <String>{};
  for (var k = 0; k < picked.length; k++) {
    final c = picked[k];
    final r = await _makeRd(c.pid, c.idx, levelFor(c.key));
    onProgress?.call(0.6 * (k + 1) / picked.length);
    if (r == null) continue;
    if (!articleWorthAsking(r.art, core: r.core)) continue;
    if (c.pid == r.pid && !haveKeys.add(r.key)) continue;
    reads.add(r);
  }
  report.reads = reads.length;
  lap('reads');

  // 2) other articles of the same specialty: their text gives the wrong options
  final pools = _Pools()..reads = reads.length;
  final all = <_Rd>[...reads];
  final groups = <String>{for (final r in reads) r.group};
  var gi = 0;
  for (final g in groups) {
    final extra = await _siblings(g, haveKeys, rnd, level);
    all.addAll(extra);
    onProgress?.call(0.6 + 0.2 * (++gi / groups.length));
  }
  lap('siblings');
  await _titlePool(pools, groups, reads, rnd);
  lap('titles');
  for (final r in all) {
    _learn(pools, r);
  }
  lap('learn');
  // a few more Core 250 articles feed the number bank (done once per article, so the bank grows over the session)
  if (report.source == QuizSource.core && _lastCore.isNotEmpty) {
    var added = 0;
    for (final t in (_lastCore.values.toList()..shuffle(rnd))) {
      if (added >= 25) break;
      if (_learnCache.containsKey(t.key)) continue;
      final r = await _makeRd(t.packId!, t.index!, level);
      if (r == null) continue;
      _learn(_Pools(), r);
      added++;
    }
    lap('bank');
  }
  // everything learned so far in this session (other articles of the same specialty first) gives wrong options too
  final inKeys = {for (final r in all) r.key};
  for (final e in _learnCache.entries) {
    if (inKeys.contains(e.key)) continue;
    final l = e.value;
    pools.nums.addAll(l.nums);
    pools.mgmt.addAll(l.mgmt);
    pools.red.addAll(l.red);
    pools.findings.addAll(l.findings);
    pools.cloze.addAll(l.cloze);
    pools.treat.addAll(l.treat);
  }
  quizTimings['poolNums'] = pools.nums.length;
  quizTimings['poolMgmt'] = pools.mgmt.length;
  quizTimings['poolRed'] = pools.red.length;
  quizTimings['poolFind'] = pools.findings.length;
  quizTimings['ownNumUnits'] = reads.fold<int>(0, (n, r) => n + r.units.where(_numberUnitOk).length);

  // 3) one question per article and pass; the kinds are mixed
  final ignored = quizIgnored();
  final out = <QuizQ>[];
  final counts = {for (final k in QKind.values) k: 0};
  final used = <String>{}; // explanation sentences already asked

  Future<bool> ask(_Rd r) async {
    final order = [...QKind.values];
    final noise = {for (final k in order) k: rnd.nextDouble() * 0.5};
    order.sort((a, b) => ((counts[a]! + 0.5) / _kindWeight[a]! + noise[a]!).compareTo((counts[b]! + 0.5) / _kindWeight[b]! + noise[b]!));
    for (final kind in order) {
      final List<QuizQ> cand = switch (kind) {
        QKind.definition => _definition(r, rnd, pools),
        QKind.cloze => _cloze(r, rnd, pools),
        QKind.treatment => _treatment(r, rnd, pools),
        QKind.symptom => _symptom(r, rnd, pools),
        QKind.number => _number(r, rnd, pools),
        QKind.management => _management(r, rnd, pools),
        QKind.redflag => _redflag(r, rnd, pools),
        QKind.trueFalse => _trueFalse(r, rnd, pools, all),
      };
      for (final q in cand) {
        report.generated++;
        final g = gateQuestion(q);
        if (!g.ok) {
          report.dropped++;
          final why = g.issues.isEmpty ? 'score' : g.issues.first.replaceAll(RegExp(r'"[^"]*"'), '…');
          report.droppedWhy[why] = (report.droppedWhy[why] ?? 0) + 1;
          continue;
        }
        if (ignored.contains(q.hash) || out.any((e) => e.stem == q.stem) || used.contains(q.explanation)) continue;
        used.add(q.explanation);
        out.add(q);
        counts[kind] = counts[kind]! + 1;
        report.kinds[kind] = report.kinds[kind]! + 1;
        return true;
      }
    }
    return false;
  }

  final order = [...reads]..shuffle(rnd);
  var passes = 0;
  while (out.length < count && passes < 4) {
    var progress = false;
    final seenTitles = <String>{};
    for (final r in order) {
      if (out.length >= count) break;
      // first pass: one article once; later passes: the same article again with another kind of question
      if (passes == 0 && !seenTitles.add(r.title.toLowerCase())) continue;
      if (await ask(r)) progress = true;
      onProgress?.call(0.8 + 0.2 * min(1.0, out.length / count));
    }
    passes++;
    if (!progress) break;
  }
  lap('ask');
  onProgress?.call(1);
  out.shuffle(rnd);
  return out;
}

/// A few other readable articles of the same specialty (core topics) or course.
Future<List<_Rd>> _siblings(String group, Set<String> have, Random rnd, QuizLevel level) async {
  final keys = <(String, int)>[];
  final core = [for (final t in _lastCore.values) if (t.specialty == group) t]..shuffle(rnd);
  if (core.isNotEmpty) {
    for (final t in core) {
      if (have.contains(t.key)) continue;
      keys.add((t.packId!, t.index!));
      if (keys.length >= 8) break;
    }
  } else {
    final p = library.textPacks.where((p) => p.title == group || p.id == group).toList();
    if (p.isNotEmpty) {
      final cs = (await _packCands(p.first)).where((c) => c.base >= 1.2).toList();
      for (var i = 0; i < 8 && cs.isNotEmpty; i++) {
        final c = cs[rnd.nextInt(cs.length)];
        if (have.contains(c.key)) continue;
        keys.add((c.pid, c.idx));
      }
    }
  }
  final out = <_Rd>[];
  for (final (p, i) in keys) {
    if (!have.add('$p|$i')) continue;
    final r = await _makeRd(p, i, level);
    if (r != null && articleWorthAsking(r.art, core: r.core)) out.add(r);
  }
  return out;
}

Future<void> _titlePool(_Pools pools, Set<String> groups, List<_Rd> reads, Random rnd) async {
  void add(String title, String key, String group) {
    final t = _cleanTitle(title);
    if (t.length < 4 || t.toLowerCase().startsWith('list of')) return;
    if (pools.titleKeys.add('$group|${t.toLowerCase()}')) pools.titles.add(_TitleRef(t, key, group));
  }

  for (final t in _lastCore.values) {
    add(t.title!, t.key, t.specialty);
  }
  // not core: titles of clinical-looking articles of the same course
  for (final g in groups) {
    if (_lastCore.values.any((t) => t.specialty == g)) continue;
    final p = library.textPacks.where((p) => p.title == g || p.id == g).toList();
    if (p.isEmpty) continue;
    final cs = (await _packCands(p.first)).where((c) => c.base >= 1.2 && c.lead.length >= 150).toList()..shuffle(rnd);
    for (final c in cs.take(60)) {
      add(c.title, c.key, g);
    }
  }
  for (final r in reads) {
    add(r.art.title, r.key, r.group);
  }
}

// ---------------------------------------------------------------- pools

/// Sub-headings of WikEM / Tulip that introduce red flags (the bullets below them are the red flags).
final RegExp _redSub = RegExp(r"red flag|warning sign|worrisome|concerning|can.t miss|dangerous|alarm|ominous|high[- ]risk features|life[- ]threatening", caseSensitive: false);
final RegExp _danglingRe = RegExp(r'\b(these|this|those|such|the latter|the former|the above|the following|as mentioned|mentioned (above|below|earlier)|see below|see above)\b', caseSensitive: false);
final RegExp _yearRe = RegExp(r'\b(1[89]|20)\d\d\b');
final RegExp _narrativeRe = RegExp(r'\b(study|studies|trial|review|reviews|authors?|reported|researchers|published|journal|survey|cohort|patients? (in|from) the|in the united states|in the us\b|united kingdom|in europe|fda|approved in|was approved)\b', caseSensitive: false);
final RegExp _actionCue = RegExp(
    r'\b(should|recommended|indicated|treated with|treatment (is|consists|includes|involves|options)|managed|first[- ]line|second[- ]line|may be (used|given|treated|considered|needed)|can be (used|given|treated)|is given|are given|administer\w*|prescribed|is used|are used|initial (treatment|therapy)|therapy (is|includes|consists)|include[sd]?|requires?|consist(s|ed)? of|must)\b',
    caseSensitive: false);
final RegExp _badLineStart = RegExp(r'^(takes|onset|duration|lasts|peak|half-life|effect|note|see|refer|consider consult|consult|if |when |in (the|a) )', caseSensitive: false);
final RegExp _clinTok = RegExp(
    r'\b(antibiotics?|steroids?|corticosteroids?|fluids?|oxygen|surgery|surgical|transfusion|admit|intubation|ventilation|dialysis|analges\w*|antiemetics?|anticoagula\w*|vasopressors?|inotropes?|bolus|infusion|IV|PO|IM|SC|mg|mcg|g|mL|units|referral|observation|splint\w*|cast|casting|reduction|drainage|monitoring|ECG|CT|MRI|x-ray|ultrasound|biopsy|culture|vaccin\w*|insulin|antivenom|antidote|therapy|chemotherapy|radiotherapy|physiotherapy|exercise|diet|lifestyle|counsel\w*|cessation|screening|endoscopy|catheter\w*|stent|transplant\w*|resection|excision|antivirals?|antifungals?|antihypertensives?|diuretics?|beta[- ]blockers?|inhibitors?|agonists?|antagonists?|supplement\w*|tablets?|doses?|medications?|drugs?)\b',
    caseSensitive: false);

bool _clinicalToken(String s) {
  if (_clinTok.hasMatch(s)) return true;
  for (final m in RegExp(r'[A-Za-z][A-Za-z\-]{5,}').allMatches(s)) {
    if (_treatmentKind(m.group(0)!) != null) return true;
  }
  return false;
}

/// A management line (bullet of a structured source, or a prose sentence that says what to do).
final RegExp _actionStart = RegExp(
    r"^(do not|don.t|give|administer|consider|use|avoid|start|stop|treat|repeat|obtain|admit|place|monitor|keep|maintain|titrate|perform|order|transfuse|replace|correct|insert|apply|discontinue|hold|ensure|check|initiate|add|switch|reduce|increase|restrict|stabilize|resuscitate|intubate|ventilate|control|prevent|begin|continue|aggressive|early|immediate|iv\b|po\b|im\b|sc\b|oral|intravenous|subcutaneous|topical|inhaled|nebuli[sz]ed|goal|target|indications?|dosing|dose)",
    caseSensitive: false);

/// True when the line names the article's own subject (a giveaway when used as an option).
bool _namesTitle(String line, String title) {
  if (_whole(line, title)) return true;
  final tl = title.toLowerCase();
  for (final e in kLibAbbrev.entries) {
    if (e.value.contains(tl) && _whole(line, e.key)) return true;
  }
  for (final w in title.split(RegExp(r'[\s\-–/]+'))) {
    if (w.length >= 6 && !kGenericWords.contains(w.toLowerCase()) && line.toLowerCase().contains(w.toLowerCase().substring(0, w.length - 1))) return true;
  }
  return false;
}

bool _mgmtOk(_U u, [String title = '']) {
  final t = _plainLine(u.text);
  if (!_lineOk(t)) return false;
  if (_badLineStart.hasMatch(t)) return false;
  if (!_clinicalToken(t)) return false;
  if (title.isNotEmpty && _namesTitle(t, title)) return false;
  if (!u.bullet && (!u.text.trim().endsWith('.') || t.split(' ').length < 6)) return false;
  if (u.bullet) return _actionStart.hasMatch(t) || singleQuantity(t) != null || (t.split(' ').length >= 6 && _tfVerb.hasMatch(t));
  return _actionCue.hasMatch(t) && !_yearRe.hasMatch(t) && !_narrativeRe.hasMatch(t) && !_danglingRe.hasMatch(t) && !kStatWords.hasMatch(t) && !_startsPronoun(t);
}

/// A red-flag line: a bullet under a "red flags" sub-heading, or a sentence that names a warning sign.
bool _redOk(_U u, [String title = '']) {
  if (title.isNotEmpty && _namesTitle(_plainLine(u.text), title)) return false;
  if (u.sec == Canon.history || u.sec == Canon.epidemiology || u.sec == Canon.background || u.sec == Canon.treatment) return false;
  final t = _plainLine(u.text);
  if (!_lineOk(t, minLen: 14, maxLen: 170)) return false;
  if (RegExp(r"red flag|warning sign|can.t miss|manage |^consider ", caseSensitive: false).hasMatch(t)) return false;
  // only the bullets under a "red flags" sub-heading of a structured source: prose sentences are too vague
  return u.bullet && _redSub.hasMatch(u.sub) && t.split(' ').length >= 2;
}

bool _hasDigit(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 48 && c <= 57) return true;
  }
  return false;
}

String _plainLine(String t) {
  var x = t.trim().replaceAll(RegExp(r'[\s.;:,]+$'), '');
  if (x.isNotEmpty) x = x[0].toUpperCase() + x.substring(1);
  return x;
}

bool _lineOk(String t, {int minLen = 18, int maxLen = 150}) {
  if (t.length < minLen || t.length > maxLen) return false;
  if (!cleanFact(t, minLen: minLen, maxLen: maxLen + 20)) return false;
  if (t.split(' ').length < 3) return false;
  if (t.endsWith(':') || RegExp(r'\b(and|or|the|of|with|to|in|for|a|an)$', caseSensitive: false).hasMatch(t)) return false;
  if (RegExp(r'^(see|refer|consider consult|consult)\b', caseSensitive: false).hasMatch(t)) return false;
  return distinctiveWords(t).isNotEmpty;
}

/// What one article gives the pools (kept per article: the same article is learned once).
class _Learned {
  final List<_Term> cloze = [], treat = [];
  final List<_Finding> findings = [];
  final List<_Line> mgmt = [], red = [];
  final List<_Num> nums = [];
}

final Map<String, _Learned> _learnCache = {};

void _learn(_Pools p, _Rd r) {
  var l = _learnCache[r.key];
  if (l == null) {
    if (_learnCache.length > 400) _learnCache.clear();
    l = _learnCache[r.key] = _learnOne(r);
  }
  p.cloze.addAll(l.cloze);
  p.treat.addAll(l.treat);
  p.findings.addAll(l.findings);
  p.mgmt.addAll(l.mgmt);
  p.red.addAll(l.red);
  p.nums.addAll(l.nums);
}

/// Collects terms, findings, management lines, red flags and numbers of one article for the wrong options of the others.
_Learned _learnOne(_Rd r) {
  final p = _Learned();
  var perSec = <Canon, int>{};
  for (final u in r.units) {
    final n = perSec[u.sec] = (perSec[u.sec] ?? 0) + 1;
    if (_clinicalCanon.contains(u.sec) && n <= 18) {
      for (final w in _keyTerms(u.text)) {
        final tk = _kindOf(w);
        if (tk != _TK.other && w.length >= 7 && !_notDrug.contains(w.toLowerCase())) p.cloze.add(_Term(w, r.key, r.group));
        if (u.sec == Canon.treatment) {
          final k2 = _treatmentKind(w);
          if (k2 != null) p.treat.add(_Term(w, r.key, r.group).._k = k2);
        }
      }
    }
    if (u.sec == Canon.treatment && _mgmtOk(u, r.title)) p.mgmt.add(_Line(_plainLine(u.text), r.key, r.group, u.bullet));
    if (_redOk(u, r.title)) p.red.add(_Line(_plainLine(u.text), r.key, r.group, u.bullet));
    if (_clinicalCanon.contains(u.sec) || u.sec == Canon.background) {
      if (_hasDigit(u.text)) {
        final q = singleQuantity(u.text);
        if (q != null && _numberUnitOk(u)) p.nums.add(_Num(q, r.key, r.group));
      }
    }
    if (r.structured && u.sec == Canon.symptoms && u.bullet) {
      final f = _finding(u.text);
      if (f != null) p.findings.add(_Finding(f, r.key, r.group, u.text));
    }
  }
  for (final a in r.art.sections) {
    if (r.structured && canonOf(a.heading) == Canon.symptoms) {
      for (final f in _findings(a.text)) {
        p.findings.add(_Finding(f.$1, r.key, r.group, f.$2));
      }
    }
  }
  return p;
}

// ---------------------------------------------------------------- helpers for the builders

/// Candidates ordered by how close they are to the question: same group first (medium / hard), any group first (easy).
List<T> _scoped<T>(List<T> items, String Function(T) groupOf, String group, QuizLevel level, Random rnd) {
  final same = [for (final i in items) if (groupOf(i) == group) i]..shuffle(rnd);
  final other = [for (final i in items) if (groupOf(i) != group) i]..shuffle(rnd);
  if (level == QuizLevel.easy) return [...other, ...same];
  if (level == QuizLevel.hard) return same;
  return [...same, ...other];
}

QuizQ _mk(_Rd r, QKind kind, String stem, List<String> opts, String answer, String explanation, {String prompt = '', String section = ''}) {
  final shuffled = [...opts];
  return QuizQ(
    kind: kind,
    stem: stem,
    options: shuffled,
    answer: shuffled.indexOf(answer),
    explanation: explanation,
    packId: r.pid,
    title: r.art.title,
    index: r.idx,
    prompt: prompt.isEmpty ? r.title : prompt,
    level: r.level,
    section: section,
    group: r.group,
  );
}


const List<List<String>> _sameClassGroups = [
  ['defibrillation', 'cardioversion', 'pacing'],
  ['thoracostomy', 'drainage', 'thoracentesis', 'pleurodesis'],
  ['intubation', 'ventilation', 'tracheostomy', 'cricothyrotomy'],
  ['paracetamol', 'acetaminophen'],
  ['ibuprofen', 'naproxen', 'diclofenac', 'aspirin'],
  ['prednisone', 'prednisolone', 'methylprednisolone', 'dexamethasone', 'hydrocortisone'],
  ['norepinephrine', 'epinephrine', 'adrenaline', 'noradrenaline', 'dopamine', 'dobutamine', 'vasopressin', 'phenylephrine'],
  ['heparin', 'warfarin', 'enoxaparin'],
  ['morphine', 'fentanyl', 'codeine', 'tramadol', 'oxycodone', 'hydromorphone'],
  ['lorazepam', 'diazepam', 'midazolam', 'clonazepam'],
];

final RegExp _classSuffix = RegExp(r'(olol|cillin|oxacin|pril|sartan|statin|dipine|azole|cef\w+|ceph\w+|mycin|cycline|thiazide|triptan|prazole|tidine|parin|xaban)$');

/// Two drugs / procedures of the same class: either could be right, so they never stand together as options.
bool _sameClass(String a, String b) {
  final x = a.toLowerCase(), y = b.toLowerCase();
  for (final g in _sameClassGroups) {
    if (g.contains(x) && g.contains(y)) return true;
  }
  final sx = _classSuffix.firstMatch(x)?.group(0), sy = _classSuffix.firstMatch(y)?.group(0);
  if (sx != null && sy != null && (sx == sy || (x.startsWith('cef') && y.startsWith('cef')))) return true;
  return false;
}

bool _whole(String hay, String needle) => RegExp('(?<![A-Za-z0-9])${RegExp.escape(needle)}(?![A-Za-z0-9])', caseSensitive: false).hasMatch(hay);

bool _startsPronoun(String s) => RegExp(r'^(it|this|these|they|he|she|its|their|however|also|thus|therefore|in addition|as a result|such|both|those|there|other|another|the (above|following|latter|former)|on the other hand|in contrast|for example|for instance|for this reason|additionally|furthermore|moreover|in particular|specifically|alternatively|instead|similarly|likewise|meanwhile|otherwise|overall|finally|first|second|third|although|though|while|whereas|but|and|or|so|then|once|after|before|since|because|despite|unlike|like|in reality|in fact|in some|in many|in most|in these|in those|in this|in such|in addition|by contrast|rarely|sometimes|often)\b', caseSensitive: false).hasMatch(s);

// ---------------------------------------------------------------- definition

Set<String> _words(String t) {
  const stop = {'with', 'from', 'disease', 'syndrome', 'disorder', 'type', 'acute', 'chronic', 'and', 'the', 'of', 'in'};
  return {for (final w in t.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) if (w.length >= 4 && !stop.contains(w)) w};
}

List<QuizQ> _definition(_Rd r, Random rnd, _Pools pools) {
  final a = r.art;
  // the opening sentence of the article (prose; for Tulip "Key points" the first bullet that says what it is)
  String first = '';
  for (final u in r.units.take(8)) {
    if (u.sec != Canon.background) continue;
    final t = u.text;
    if (u.bullet && !RegExp(r'\b(is|are) (a|an|the|defined)|defined as\b', caseSensitive: false).hasMatch(t)) continue;
    if (t.length < 70 || t.length > 300 || !cleanFact(t) || _startsPronoun(t)) continue;
    first = t;
    break;
  }
  if (first.isEmpty) return const [];
  // hide the title and every word of it (so "basal-cell cancer" cannot give it away)
  var masked = maskTitle(first, a.title);
  if (masked == null) return const [];
  const skip = {'with', 'from', 'disease', 'syndrome', 'disorder', 'type', 'acute', 'chronic', 'and', 'the', 'of', 'in', 'medical', 'condition'};
  for (final w in r.title.split(RegExp(r'[\s\-–/]+'))) {
    if (w.length >= 4 && !skip.contains(w.toLowerCase())) masked = masked!.replaceAll(RegExp('\\b${RegExp.escape(w)}\\w*', caseSensitive: false), '____');
  }
  final stem = masked!.replaceAll(RegExp(r'(____[\s,;-]*){2,}'), '____ ').replaceAll(RegExp(r'\s+'), ' ').replaceAllMapped(RegExp(r'\s+([.,;])'), (m) => m[1]!).trim();
  // a real definition: the sentence is "<title> is / are / refers to ..."
  if ('____'.allMatches(stem).length != 1) return const [];
  if (!RegExp(r'^(an? |the )?____[^.]{0,60}?\b(is|are|refers? to|describes?|means?|denotes?|was|were)\b', caseSensitive: false).hasMatch(stem)) return const [];
  final answer = r.title;
  final stemWords = {for (final m in RegExp(r'[A-Za-z]{4,}').allMatches(stem.toLowerCase())) m.group(0)!};
  final aw = _words(answer);
  final scoped = _scoped<_TitleRef>([for (final t in pools.titles) if (t.key != r.key) t], (t) => t.group, r.group, r.level, rnd);
  final wrong = pickDistinctOptions(scoped.map((t) => t.title), answer, 3, ok: (t) => t.length >= 4 && !_whole(stem, t) && !_words(t).any(aw.contains) && !_words(t).any(stemWords.contains));
  if (wrong == null) return const [];
  return [_mk(r, QKind.definition, stem, [answer, ...wrong]..shuffle(rnd), answer, first, section: a.sections.first.heading)];
}

// ---------------------------------------------------------------- cloze and treatment

List<QuizQ> _blankTerm(_Rd r, Random rnd, _Pools pools, {required bool treatment}) {
  final out = <QuizQ>[];
  final secs = treatment ? [Canon.treatment] : _clinicalCanon.where((c) => c != Canon.treatment).toList();
  final pool = treatment ? pools.treat : pools.cloze;
  final units = [for (final u in r.units) if (secs.contains(u.sec) && (!u.bullet || r.structured) && u.text.length >= 60 && u.text.length <= 260 && cleanFact(u.text) && !_startsPronoun(u.text) && !_danglingRe.hasMatch(u.text) && !_yearRe.hasMatch(u.text) && u.text.endsWith('.')) u]..shuffle(rnd);
  for (final u in units.take(8)) {
    final terms = <(String, _TK)>[];
    for (final w in _keyTerms(u.text)) {
      final tk = _treatmentKind(w);
      if (tk != null && u.text.indexOf(w) >= 14) terms.add((w, tk));
    }
    terms.shuffle(rnd);
    final sentLow = u.text.toLowerCase();
    for (final (term, tk) in terms.take(3)) {
      final low = term.toLowerCase();
      final cands = [
        for (final t in pool)
          if (t.key != r.key && t.kind == tk && t.low != low && (t.text.length - term.length).abs() <= 8) t
      ];
      final ordered = _scoped<_Term>(cands, (t) => t.group, r.group, r.level, rnd);
      final wrong = pickDistinctOptions(ordered.map((t) => t.text), term, 3, ok: (t) {
        final l = t.toLowerCase();
        return !sentLow.contains(l) && !r.allLower.contains(l) && !_sameClass(term, t);
      });
      if (wrong == null) continue;
      final stem = u.text.replaceFirst(RegExp('\\b${RegExp.escape(term)}\\b'), '____');
      // same writing for all options: a drug name is lower case unless it is an acronym
      String cap(String s) => RegExp(r'^[A-Za-z]+$').hasMatch(s) && s.length > 3 && s.substring(1) == s.substring(1).toLowerCase() ? s.toLowerCase() : s;
      out.add(_mk(r, treatment ? QKind.treatment : QKind.cloze, stem, [cap(term), ...wrong.map(cap)]..shuffle(rnd), cap(term), u.text, section: u.heading));
      if (out.length >= 2) return out;
    }
  }
  return out;
}

List<QuizQ> _cloze(_Rd r, Random rnd, _Pools pools) => _blankTerm(r, rnd, pools, treatment: false);
List<QuizQ> _treatment(_Rd r, Random rnd, _Pools pools) => _blankTerm(r, rnd, pools, treatment: true);

// ---------------------------------------------------------------- symptom

final RegExp _notFinding = RegExp(r'\b(is|are|was|were|may|can|will|which|that|have|has|been|not|also|often|usually|typically|should|their|these|those|such|more|most|than)\b', caseSensitive: false);

String? _finding(String raw) {
  var t = raw.trim().replaceAll(RegExp(r'^(and|or|a|an|the)\s+', caseSensitive: false), '').replaceAll(RegExp(r'[\s.;:,]+$'), '').trim();
  final cut = RegExp(r'\s[–—-]\s|:\s').firstMatch(t);
  if (cut != null) t = t.substring(0, cut.start);
  if (t.length < 5 || t.length > 46) return null;
  final n = t.split(RegExp(r'\s+')).length;
  if (n == 1 && (t.length < 8 || !RegExp(r'(uria|emia|aemia|algia|pnea|plegia|paresis|edema|oedema|itis|osis|pathy|rrhea|rrhoea|cough|rash|ache|tremor|spasm|pain|ataxia|anopia|opia|cytosis|penia|megaly|mania|phobia|amnesia|aphasia|dysphagia|oliguria|anuria|myalgia|erythema|jaundice|vertigo|nystagmus)$', caseSensitive: false).hasMatch(t))) return null;
  if (RegExp(r'^(subtypes?|symptoms?|signs?|phase|stage|types?|causes?|features?|complications?|general|severe|mild|moderate|early|late|acute|chronic|critical phase|recovery phase|febrile phase)\b', caseSensitive: false).hasMatch(t)) return null;
  if (n > 5 || RegExp(r'\d').hasMatch(t) || _notFinding.hasMatch(t) || t.contains('(') || t.contains(')')) return null;
  if (isGenericFinding(t) || hasBoilerplate(t) || looksLikeCaption(t)) return null;
  if (RegExp(r'^(at|in|on|of|with|by|from|for|to|as|is|are|be|and|or|the|a|an|frequently|usually|often|rarely|mild|severe|lack|lacking|presence|absence|history|family|current|recent|prior|previous)\b', caseSensitive: false).hasMatch(t)) return null;
  if (t.split(' ').length > 4 || RegExp(r'\b(in the|of the|lacking|elderly|patients?)\b', caseSensitive: false).hasMatch(t)) return null;
  if (RegExp(r'\b[A-Z]{2,3}\b').hasMatch(t) || RegExp(r'\b(artery|arteries|vein|nerve|muscle|muscles|system|systems|tract|bone|gland|pulses?|ligament|syndrome|disease|disorder|diagnosis|differential|exam|examination|findings?|assessment|palpation|evaluation|testing|tests?|imaging|studies|check|monitor\w*)\b', caseSensitive: false).hasMatch(t)) return null;
  return t[0].toUpperCase() + t.substring(1);
}

/// Short findings (phrase, source sentence) from a "Signs and symptoms" section.
List<(String, String)> _findings(String text) {
  final out = <(String, String)>[];
  void add(String raw, String src) {
    final f = _finding(raw);
    if (f != null) out.add((f, src));
  }

  for (final b in bulletLines(text)) {
    var head = b;
    final cut = RegExp(r'\s[–—-]\s|:\s').firstMatch(head);
    if (cut != null) head = head.substring(0, cut.start);
    if (head.length > 60) continue;
    add(head, b);
  }
  final prose = text.split('\n').where((l) => !l.trim().startsWith('•')).join(' ');
  for (final snt in sentences(prose)) {
    final m = RegExp(r'\b(?:include[sd]?|including|such as|(?:symptoms|signs|features|findings) (?:are|is))\s+(.+?)[.;]?$', caseSensitive: false).firstMatch(snt);
    if (m == null) continue;
    for (final part in m.group(1)!.split(RegExp(r',\s*(?:and\s+|or\s+)?|\s+and\s+|\s+or\s+'))) {
      add(part, snt);
    }
  }
  return out;
}

List<QuizQ> _symptom(_Rd r, Random rnd, _Pools pools) {
  final a = r.art;
  if (!r.structured) return const []; // lists of findings are clean in WikEM / Tulip / CDC only
  final own = <(String, String, String)>[];
  for (final s in a.sections) {
    if (canonOf(s.heading) == Canon.symptoms) own.addAll([for (final f in _findings(s.text)) (f.$1, f.$2, s.heading)]);
  }
  if (own.isEmpty) return const [];
  own.shuffle(rnd);
  final out = <QuizQ>[];
  for (final (text, src, heading) in own.take(5)) {
    final tw = text.split(' ').length;
    final seen = <String>{};
    // wrong options come from OTHER specialties (a finding of the same specialty could also fit)
    final others = [
      for (final f in pools.findings)
        if (f.key != r.key && f.group != r.group && !r.allLower.contains(f.text.toLowerCase()) && (f.text.split(' ').length - tw).abs() <= 1 && seen.add(f.text.toLowerCase())) f
    ]..shuffle(rnd);
    final wrong = pickDistinctOptions(others.map((f) => f.text), text, 3);
    if (wrong == null) continue;
    out.add(_mk(r, QKind.symptom, 'Which of these is a recognised feature of ${r.title}?', [text, ...wrong]..shuffle(rnd), text, '$heading: $src', section: heading));
    if (out.length >= 2) break;
  }
  return out;
}

// ---------------------------------------------------------------- management and red flags

List<QuizQ> _lineQuestion(_Rd r, Random rnd, List<_Line> pool, List<_U> own, QKind kind, String stem) {
  final keys = [for (final u in own) if (kind == QKind.redflag ? _redOk(u, r.title) : _mgmtOk(u, r.title)) u]..shuffle(rnd);
  final out = <QuizQ>[];
  for (final u in keys.take(5)) {
    final key = _plainLine(u.text);
    final ratioOk = (String t) => t.length >= key.length * 0.5 && t.length <= key.length * 2.0 + 10;
    final cands = [
      for (final l in pool)
        if (l.key != r.key && l.bullet == u.bullet && ratioOk(l.text)) l
    ];
    final ordered = _scoped<_Line>(cands, (l) => l.group, r.group, r.level, rnd);
    final byText = {for (final l in ordered) l.text: l};
    final wrong = pickDistinctOptions(ordered.map((l) => l.text), key, 3, ok: (t) => byText[t]!.words.every((w) => !r.allLower.contains(w)));
    if (wrong == null) continue;
    out.add(_mk(r, kind, stem, [key, ...wrong]..shuffle(rnd), key, u.sub.isEmpty ? u.text : '${u.sub}: ${u.text}', section: u.heading));
    if (out.length >= 2) break;
  }
  return out;
}

List<QuizQ> _management(_Rd r, Random rnd, _Pools pools) {
  final own = [for (final u in r.units) if (u.sec == Canon.treatment) u];
  if (own.isEmpty) return const [];
  return _lineQuestion(r, rnd, pools.mgmt, own, QKind.management, 'Which of these is part of the management of ${r.title}?');
}

List<QuizQ> _redflag(_Rd r, Random rnd, _Pools pools) {
  final own = [for (final u in r.units) if (_redOk(u, r.title)) u];
  if (own.isEmpty) return const [];
  return _lineQuestion(r, rnd, pools.red, own, QKind.redflag, 'Which of these is described as a warning sign (red flag) in ${r.title}?');
}

// ---------------------------------------------------------------- numbers

/// Numbers (with the same unit) of other articles that can stand in for [hit].
List<_Num> _numCandidates(_Rd r, _Pools pools, QuantityHit hit, Random rnd, {double lo = 0.1, double hi = 10, double far = 0.15}) {
  final seen = <String>{};
  final same = <_Num>[], cls = <_Num>[];
  final (hc, hf) = unitClass(hit.unit);
  final hv = hit.value * hf;
  for (final n in pools.nums) {
    if (n.key == r.key || n.hit.range != hit.range) continue;
    final (nc, nf) = unitClass(n.hit.unit);
    if (nc != hc || hv == 0) continue;
    final ratio = n.hit.value * nf / hv;
    if (ratio < lo || ratio > hi || (ratio - 1).abs() < far) continue;
    if (!seen.add(n.hit.text.toLowerCase())) continue;
    (n.hit.unit == hit.unit ? same : cls).add(n);
  }
  // the same unit first, then the same kind of unit
  return [..._scoped<_Num>(same, (n) => n.group, r.group, r.level, rnd), ..._scoped<_Num>(cls, (n) => n.group, r.group, r.level, rnd)];
}

/// Numbers worth asking: a dose, a cut-off, a time window in the clinical sections (not trivia of the lead).
final RegExp _qualifier = RegExp(r'(more than|less than|at least|up to|over|under|below|above|greater than|fewer than|nearly|almost|about|around|approximately|roughly|up to|within about|no more than|no less than|maximum|minimum|max|min|exceeds?|exceeding)\s*[<>≥≤]?\s*$', caseSensitive: false);

bool _numberUnitOk(_U u) {
  final hq = singleQuantity(u.text);
  if (hq != null && _qualifier.hasMatch(u.text.substring(0, hq.start))) return false;
  if (!_clinicalCanon.contains(u.sec) || u.sec == Canon.causes) return false;
  if (_danglingRe.hasMatch(u.text) || _yearRe.hasMatch(u.text) || _narrativeRe.hasMatch(u.text)) return false;
  if (!numberSentenceOk(u.text) && !(u.bullet && cleanFact(u.text, minLen: 14, maxLen: 230) && singleQuantity(u.text) != null && !kStatWords.hasMatch(u.text))) return false;
  return _clinicalToken(u.text) || RegExp(r'\b(defined|criteria|cut-?off|threshold|level|target|goal|dose|rate|duration|within|every|per)\b', caseSensitive: false).hasMatch(u.text);
}

List<QuizQ> _number(_Rd r, Random rnd, _Pools pools) {
  final out = <QuizQ>[];
  final units = [for (final u in r.units) if (_numberUnitOk(u)) u]..shuffle(rnd);
  for (final u in units.take(6)) {
    final hit = singleQuantity(u.text)!;
    final ordered = _numCandidates(r, pools, hit, rnd);
    final wrong = pickDistinctOptions(ordered.map((n) => n.hit.text), hit.text, 3, ok: (t) => !r.allLower.contains(t.toLowerCase()));
    if (wrong == null) continue;
    var body = u.text.replaceRange(hit.start, hit.end, '____');
    if (!_whole(body, r.title) && !body.toLowerCase().contains(r.title.toLowerCase())) body = '${r.title}: $body';
    out.add(_mk(r, QKind.number, body, [hit.text, ...wrong]..shuffle(rnd), hit.text, u.sub.isEmpty ? u.text : '${u.sub}: ${u.text}', section: u.heading));
    if (out.length >= 2) break;
  }
  return out;
}

// ---------------------------------------------------------------- true / false

final RegExp _tfVerb = RegExp(r'\b(is|are|was|were|should|may|can|must|does|do|causes?|occurs?|results?|requires?|defined|characteri[sz]ed|leads?|indicates?|suggests?|increases?|decreases?|reduces?|improves?|contains?|involves?|includes?|presents?|affects?|develops?|treated|used|given|recommended)\b', caseSensitive: false);

/// A complete statement that can be true or false on its own.
bool _tfOk(_U u, _Rd r) {
  final t = u.text;
  if (!cleanFact(t, minLen: 45, maxLen: 230) || _startsPronoun(t) || _danglingRe.hasMatch(t) || kStatWords.hasMatch(t) || _yearRe.hasMatch(t) || _narrativeRe.hasMatch(t)) return false;
  if (t.contains('____') || t.endsWith('?') || t.endsWith(':')) return false;
  if (!_tfVerb.hasMatch(t) || RegExp(r'\b(regarded|accepted|believed|thought to|some (people|authors|experts)|controvers\w*|debate\w*|claimed|may prove|might|furthermore)\b', caseSensitive: false).hasMatch(t)) return false;
  if (u.bullet) {
    if (!r.structured || t.split(' ').length < 7) return false;
    if (!RegExp(r'\b(is|are|was|were|should|may|can|must|defined)\b', caseSensitive: false).hasMatch(t)) return false;
  }
  return true;
}

/// A statement that is either the real sentence, or the same sentence with a number from another article,
/// (a changed condition name is not used: the new statement could be true of the other condition). True and
/// false statements are kept balanced. The explanation always shows the original sentence.
List<QuizQ> _trueFalse(_Rd r, Random rnd, _Pools pools, List<_Rd> all) {
  final units = [for (final u in r.units) if ((_clinicalCanon.contains(u.sec) || u.sec == Canon.background) && _tfOk(u, r)) u]..shuffle(rnd);
  if (units.isEmpty) return const [];
  final wantFalse = rnd.nextBool();
  QuizQ? falseQ;
  if (wantFalse) {
    for (final u in units.take(10)) {
      final text = u.text.endsWith('.') || u.bullet ? u.text : '${u.text}.';
      final mention = _whole(text, r.title);
      String withTitle(String s) => mention ? s : '${r.title}: $s';
      String? changed;
      final hit = singleQuantity(u.text);
      if (hit != null && !_qualifier.hasMatch(u.text.substring(0, hit.start)) && !RegExp(r'\b(half|quarter|quarters|third|thirds|twice|double|triple|most|majority|all|none)\b', caseSensitive: false).hasMatch(u.text)) {
        final ordered = _numCandidates(r, pools, hit, rnd, lo: 0.4, hi: 2.5, far: 0.3);
        for (final n in ordered) {
          if (r.allLower.contains(n.hit.text.toLowerCase())) continue;
          changed = text.replaceRange(hit.start, hit.end, n.hit.text);
          break;
        }
      }
      if (changed == null) continue;
      falseQ = _mk(r, QKind.trueFalse, withTitle(changed), const ['True', 'False'], 'False', u.text, section: u.heading);
      break;
    }
  }
  if (falseQ != null) {
    pools.tfFalse++;
    return [falseQ];
  }
  // no honest false version: a true statement only while the quiz is not already full of them
  if (pools.tfTrue > pools.tfFalse) return const [];
  pools.tfTrue++;
  // the real sentence (also when no honest change was possible)
  final out = <QuizQ>[];
  for (final u in units.take(3)) {
    final text = u.text.endsWith('.') || u.bullet ? u.text : '${u.text}.';
    final mention = _whole(text, r.title);
    out.add(_mk(r, QKind.trueFalse, mention ? text : '${r.title}: $text', const ['True', 'False'], 'True', u.text, section: u.heading));
  }
  return out;
}
