import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'data.dart';
import 'lib_text.dart';
import 'library.dart';
import 'search_index.dart' show normText;

/// Everything the user keeps about library articles: favorites, recent reading,
/// personal notes and review cards. All of it stays on the phone (in the same
/// private files as the rest of MedLog).

String _key(String packId, String title) => '$packId|$title';

bool isFavorite(String packId, String title) => store.listOf('libfav').any((e) => e['id'] == _key(packId, title));

Future<bool> toggleFavorite(String packId, String title) async {
  final k = _key(packId, title);
  if (isFavorite(packId, title)) {
    await store.removeExtra('libfav', k);
    return false;
  }
  await store.upsertExtra('libfav', {'id': k, 'pack': packId, 'title': title, 'date': nowIso()});
  return true;
}

List<J> favorites() {
  final l = [...store.listOf('libfav')];
  l.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  return l;
}

/// Last opened articles, newest first (max 12).
List<Map<String, dynamic>> recentArticles() {
  final r = store.settings['libRecent'];
  if (r is! List) return <Map<String, dynamic>>[];
  return [for (final e in r) if (e is Map) Map<String, dynamic>.from(e)];
}

void noteRecent(String packId, String title) {
  final l = recentArticles()..removeWhere((e) => e['p'] == packId && e['t'] == title);
  l.insert(0, {'p': packId, 't': title});
  store.settings['libRecent'] = l.take(12).toList();
  store.saveSettings();
}

String noteFor(String packId, String title) {
  for (final e in store.listOf('libnotes')) {
    if (e['id'] == _key(packId, title)) return '${e['text'] ?? ''}';
  }
  return '';
}

Future<void> saveNote(String packId, String title, String text) async {
  final k = _key(packId, title);
  if (text.trim().isEmpty) {
    await store.removeExtra('libnotes', k);
  } else {
    await store.upsertExtra('libnotes', {'id': k, 'pack': packId, 'title': title, 'text': text, 'date': nowIso()});
  }
}

String _cardId(String front) => md5.convert(utf8.encode(front)).toString().substring(0, 16);

/// A review card made from a library article (shows up in the spaced review).
Future<bool> addLibraryCard({required String front, required String back, required String source, String packId = '', String title = ''}) async {
  final id = _cardId(front);
  if (store.listOf('libcards').any((e) => e['id'] == id)) return false;
  await store.upsertExtra('libcards', {'id': id, 'front': front, 'back': back, 'source': source, 'pack': packId, 'title': title, 'date': nowIso()});
  return true;
}

/// "Add missed questions to review cards": on by default.
bool quizAutoCards() => store.settings['quizAutoCards'] != false;

Future<void> setQuizAutoCards(bool v) async {
  store.settings['quizAutoCards'] = v;
  await store.saveSettings();
}

/// A question the learner missed: makes the review card (once, same text = same card) and schedules it
/// for today, or sooner again (box 0, due today) when it already exists. True when a new card was made.
Future<bool> missedCard({required String front, required String back, required String source, String packId = '', String title = ''}) async {
  final made = await addLibraryCard(front: front, back: back, source: source, packId: packId, title: title);
  final key = 'l:${_cardId(front)}';
  J? st;
  for (final e in store.listOf('review')) {
    if (e['id'] == key) st = e;
  }
  final s = st ?? <String, dynamic>{'id': key, 'box': 0, 'reps': 0, 'lapses': 0};
  s['box'] = 0;
  s['lapses'] = (s['lapses'] as int? ?? 0) + (st == null ? 0 : 1);
  s['due'] = todayStr();
  s['title'] = front.split('\n').first;
  await store.upsertExtra('review', s);
  return made;
}

/// Course (pack id) that matches the name of a rotation, e.g. "Orthopedics" -> "orthopedics".
String? packIdForRotation(String name) {
  final n = name.toLowerCase();
  const rules = <List<String>>[
    ['orthop', 'orthopedics'],
    ['cardio', 'cardiology'],
    ['pulmon', 'pulmonology'],
    ['chest', 'pulmonology'],
    ['gastro', 'gastroenterology'],
    ['nephro', 'nephrology-urology'],
    ['urolog', 'nephrology-urology'],
    ['endocr', 'endocrinology'],
    ['neuro', 'neurology'],
    ['psych', 'psychiatry'],
    ['infect', 'infectious-diseases'],
    ['hemat', 'hematology-oncology'],
    ['oncol', 'hematology-oncology'],
    ['pediat', 'pediatrics'],
    ['paediat', 'pediatrics'],
    ['ob/gyn', 'obstetrics-gynecology'],
    ['obstet', 'obstetrics-gynecology'],
    ['gyn', 'obstetrics-gynecology'],
    ['emergency', 'emergency-critical-care'],
    ['icu', 'emergency-critical-care'],
    ['intensive', 'emergency-critical-care'],
    ['derm', 'dermatology'],
    ['ophthal', 'ophthalmology'],
    ['ent', 'ent'],
    ['otolaryn', 'ent'],
    ['anesth', 'anesthesiology'],
    ['radiolog', 'radiology'],
    ['rheumat', 'rheumatology-immunology'],
    ['surg', 'surgery'],
    ['internal', 'general-medicine'],
    ['family', 'general-medicine'],
  ];
  for (final r in rules) {
    if (n.contains(r[0])) return r[1];
  }
  return null;
}

/// One article per day from the course of the current rotation (or any course you have).
Future<LibHit?> topicOfTheDay() async {
  if (!library.ready || library.textPacks.isEmpty) return null;
  final rot = store.currentRotation();
  var id = rot == null ? null : packIdForRotation('${rot['name'] ?? ''}');
  if (id == null || library.pack(id) == null) {
    final list = library.textPacks.where((p) => p.kind == 'wiki').toList();
    if (list.isEmpty) return null;
    list.sort((a, b) => a.id.compareTo(b.id));
    id = list[DateTime.now().day % list.length].id;
  }
  final i = await library.dailyPick(id, todayStr());
  if (i == null) return null;
  final titles = await library.titlesOf(id);
  final leads = await library.leadsOf(id);
  return LibHit(id, i, titles[i], leads[i], 0);
}

final Map<String, List<LibHit>> _caseHitCache = {};
String _caseHitSig = '';

/// Articles that talk about what the case is about (final or working diagnosis).
Future<List<LibHit>> articlesForCase(CaseRec c) async {
  final dx = [c.s('finalDx'), c.s('workingDx')].firstWhere((e) => e.trim().isNotEmpty, orElse: () => '');
  final q = dx.trim().isNotEmpty ? dx : c.s('cc');
  if (q.trim().isEmpty || !library.ready) return const [];
  // the same diagnosis is looked up again and again (quizzes, case screens): remember it until the packs change
  final sig = [for (final p in library.packs) '${p.id}${p.count}${p.date}'].join(',');
  if (sig != _caseHitSig) {
    _caseHitCache.clear();
    _caseHitSig = sig;
  }
  final hit = _caseHitCache[q.trim().toLowerCase()];
  if (hit != null) return hit;
  var hits = await library.searchEx(q, limit: 8);
  if (hits.isEmpty) {
    final fix = await library.didYouMean(q);
    if (fix != null) hits = await library.searchEx(fix, limit: 8);
  }
  return _caseHitCache[q.trim().toLowerCase()] = hits;
}

/// Your cases whose diagnosis or complaint mentions the article's subject.
List<CaseRec> casesAbout(String title) {
  final t = normText(title).trim();
  if (t.length < 4) return const [];
  final out = <CaseRec>[];
  for (final c in store.cases.values) {
    final hay = normText('${c.s('finalDx')} ${c.s('workingDx')} ${c.s('ddx')} ${c.s('cc')}');
    if (hay.contains(t) || (kLibAbbrev.values.contains(t) && hay.contains(t))) out.add(c);
  }
  return out;
}

// ------------------------------------------------------------------ quiz memory

/// An article the user missed in self-tests and has not answered correctly since.
class WeakSpot {
  final String packId;
  final String title;
  final int wrongRecent; // wrong answers among the last 5 tries
  final bool lastWrong;
  final String lastDate;
  const WeakSpot(this.packId, this.title, this.wrongRecent, this.lastWrong, this.lastDate);
}

/// Per-article results from the last [rows] quiz rows, newest first: key "pack|title" -> list of ok flags.
Map<String, List<bool>> quizResultsByArticle({int rows = 40}) {
  final log = [...store.listOf('quizlog')]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  final res = <String, List<bool>>{};
  for (final r in log.take(rows)) {
    final items = r['items'];
    if (items is List) {
      for (final it in items) {
        if (it is! Map) continue;
        final p = '${it['p'] ?? ''}', t = '${it['t'] ?? ''}';
        if (p.isEmpty || t.isEmpty) continue;
        (res[_key(p, t)] ??= <bool>[]).add(it['ok'] == true);
      }
    } else if (r['wrong'] is List && '${r['pack'] ?? ''}'.isNotEmpty) {
      for (final t in r['wrong'] as List) {
        (res[_key('${r['pack']}', '$t')] ??= <bool>[]).add(false);
      }
    }
  }
  return res;
}

/// Weak spots: last result wrong, or wrong at least twice in the last 5 tries.
List<WeakSpot> weakSpots() {
  final log = [...store.listOf('quizlog')]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  final dates = <String, String>{};
  for (final r in log.take(40)) {
    final items = r['items'];
    if (items is List) {
      for (final it in items) {
        if (it is Map) dates.putIfAbsent(_key('${it['p'] ?? ''}', '${it['t'] ?? ''}'), () => '${r['date'] ?? ''}');
      }
    } else if (r['wrong'] is List) {
      for (final t in r['wrong'] as List) {
        dates.putIfAbsent(_key('${r['pack'] ?? ''}', '$t'), () => '${r['date'] ?? ''}');
      }
    }
  }
  final out = <WeakSpot>[];
  quizResultsByArticle().forEach((k, v) {
    final recent = v.take(5).toList();
    final wrong = recent.where((e) => !e).length;
    final lastWrong = !v.first;
    if (lastWrong || wrong >= 2) {
      final i = k.indexOf('|');
      out.add(WeakSpot(k.substring(0, i), k.substring(i + 1), wrong, lastWrong, dates[k] ?? ''));
    }
  });
  out.sort((a, b) {
    final c = b.lastDate.compareTo(a.lastDate);
    return c != 0 ? c : b.wrongRecent.compareTo(a.wrongRecent);
  });
  return out;
}

/// Hash that identifies a question (used to never ask an ignored question again).
String quizHash(String stem, String correct) => md5.convert(utf8.encode('$stem|$correct')).toString().substring(0, 12);

Set<String> quizIgnored() {
  final l = store.settings['quizIgnored'];
  return l is List ? {for (final e in l) '$e'} : <String>{};
}

Future<void> ignoreQuizQuestion(String hash) async {
  final l = quizIgnored().toList()..add(hash);
  store.settings['quizIgnored'] = l.length > 3000 ? l.sublist(l.length - 3000) : l;
  await store.saveSettings();
}

// ------------------------------------------------------------------ reading list

/// Articles saved to read later (separate from favorites): newest first.
List<Map<String, dynamic>> readingList() {
  final r = store.settings['libReadLater'];
  if (r is! List) return <Map<String, dynamic>>[];
  return [for (final e in r) if (e is Map) Map<String, dynamic>.from(e)];
}

bool isInReadingList(String packId, String title) => readingList().any((e) => e['p'] == packId && e['t'] == title);

/// Adds or removes an article; returns true when it is now in the list.
Future<bool> toggleReadingList(String packId, String title) async {
  final l = readingList();
  final had = l.any((e) => e['p'] == packId && e['t'] == title);
  l.removeWhere((e) => e['p'] == packId && e['t'] == title);
  if (!had) l.insert(0, {'p': packId, 't': title, 'd': nowIso()});
  store.settings['libReadLater'] = l.take(200).toList();
  await store.saveSettings();
  return !had;
}

// ------------------------------------------------------------------ downloads on mobile data

/// "Download on Wi-Fi only": on by default. It applies to picture packs and to downloads over 20 MB.
bool libWifiOnly() => store.settings['libWifiOnly'] != false;

Future<void> setLibWifiOnly(bool v) async {
  store.settings['libWifiOnly'] = v;
  await store.saveSettings();
}

/// True when a download of [bytes] (or any picture pack) must ask before using mobile data.
bool needsWifiCheck({required int bytes, bool images = false}) => libWifiOnly() && (images || bytes > kBigDownloadBytes);
