import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'data.dart';
import 'library.dart';
import 'search_index.dart' show normText;

/// The "Core 250": a fixed list of the clinical topics an intern / board candidate meets most
/// (assets/library/core250.json: topic, specialty, priority, title patterns). Each topic is resolved to
/// the best article installed on the phone (concise Essentials / WikEM / Tulip / CDC articles first,
/// long course articles and patient leaflets later). Nothing is written by the app: only titles are matched.

/// Study universe setting: 'core' (default) or 'all'.
const String kUniverseCore = 'core';
const String kUniverseAll = 'all';

String studyUniverse() => store.settings['studyUniverse'] == kUniverseAll ? kUniverseAll : kUniverseCore;

Future<void> setStudyUniverse(String v) async {
  store.settings['studyUniverse'] = v == kUniverseAll ? kUniverseAll : kUniverseCore;
  await store.saveSettings();
}

class CoreTopic {
  final String topic;
  final String specialty;
  final int priority; // 1 = more central
  final List<String> patterns;
  String? packId;
  int? index;
  String? title; // raw title of the matched article
  CoreTopic(this.topic, this.specialty, this.priority, this.patterns);

  bool get resolved => packId != null && index != null;
  String get key => '$packId|$index';
  String get label => topic.isEmpty ? topic : topic[0].toUpperCase() + topic.substring(1);

  static CoreTopic fromJson(Map j) =>
      CoreTopic('${j['t']}', '${j['s']}', (j['r'] as num?)?.toInt() ?? 2, [for (final p in (j['p'] as List? ?? const [])) '$p']);
}

List<CoreTopic>? _topics;

/// Parses the asset text (exposed for tests).
List<CoreTopic> parseCoreTopics(String json) {
  final m = jsonDecode(json) as Map;
  return [for (final e in (m['topics'] as List)) CoreTopic.fromJson(e as Map)];
}

/// Loads the list from the app bundle (falls back to the file in the source tree, for tests).
Future<List<CoreTopic>> loadCoreTopics() async {
  final hit = _topics;
  if (hit != null) return hit;
  String? text;
  try {
    text = await rootBundle.loadString('assets/library/core250.json');
  } catch (_) {}
  if (text == null) {
    for (final p in ['assets/library/core250.json', '/tmp/w/app/assets/library/core250.json']) {
      try {
        text = await File(p).readAsString();
        break;
      } catch (_) {}
    }
  }
  if (text == null) return const [];
  return _topics = parseCoreTopics(text);
}

/// Specialty names in the order of the list.
List<String> specialtiesOf(List<CoreTopic> ts) {
  final out = <String>[];
  for (final t in ts) {
    if (!out.contains(t.specialty)) out.add(t.specialty);
  }
  return out;
}

// ------------------------------------------------------------------ matching

class CoreCand {
  final String packId;
  final int index;
  final String title;
  final String source; // WikEM / CDC / ... / Wikipedia / MedlinePlus
  final bool essentials;
  double score;
  CoreCand(this.packId, this.index, this.title, this.source, this.essentials, [this.score = 0]);
}

String normTitle(String t) {
  final s = normText(stripSource(t)).replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Preference by source: concise, structured sources first.
double sourceBonus(String source, bool essentials) {
  switch (source) {
    case 'WikEM':
      return 90;
    case 'Project Tulip':
      return 70;
    case 'CDC':
      return 55;
    case 'NCI':
      return 10;
    case 'MedlinePlus':
      return -110;
    default:
      return essentials ? 50 : 0;
  }
}

/// Index of all titles: normalised title (without the source suffix) -> candidates.
class CoreIndex {
  final Map<String, List<CoreCand>> byNorm = {};
  final List<(String, CoreCand)> all = [];
  void add(CoreCand c) {
    final n = normTitle(c.title);
    if (n.isEmpty) return;
    (byNorm[n] ??= <CoreCand>[]).add(c);
    all.add((' $n ', c));
    final p = normTitle(c.title.replaceAll(RegExp(r'\s*\([^)]*\)'), ''));
    if (p != n && p.isNotEmpty) {
      (byNorm[p] ??= <CoreCand>[]).add(c);
    }
  }
}

/// Candidates for a topic, best first (no article size yet). Exact title of a pattern first (earlier
/// patterns win), then titles that contain a pattern as whole words.
List<CoreCand> shortlist(CoreTopic t, CoreIndex ix, {int limit = 6}) {
  final best = <CoreCand, double>{};
  for (var i = 0; i < t.patterns.length; i++) {
    final p = normTitle(t.patterns[i]);
    if (p.isEmpty) continue;
    for (final c in ix.byNorm[p] ?? const <CoreCand>[]) {
      final sc = 1000 - i * 20 + sourceBonus(c.source, c.essentials);
      if (sc > (best[c] ?? -1e9)) best[c] = sc;
    }
  }
  if (best.isEmpty) {
    // word-bounded containment, only for patterns of two letters or more words / long single words
    for (var i = 0; i < t.patterns.length; i++) {
      final p = normTitle(t.patterns[i]);
      if (p.length < 5 || !p.contains(' ')) continue; // one-word patterns only match exactly
      final needle = ' $p ';
      for (final (n, c) in ix.all) {
        if (!n.contains(needle)) continue;
        final extra = n.trim().split(' ').length - p.split(' ').length;
        if (extra > 1) continue;
        final sc = 300 - i * 20 - extra * 25 + sourceBonus(c.source, c.essentials);
        if (sc > (best[c] ?? -1e9)) best[c] = sc;
      }
    }
  }
  final l = best.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in l.take(limit)) e.key..score = e.value];
}

/// Size correction: stubs and very long course articles are less useful for a quick study.
double sizeAdjust(int chars) {
  if (chars < 1200) return -120;
  if (chars < 2500) return -25;
  if (chars <= 15000) return 25;
  if (chars <= 30000) return -15;
  return -50;
}

String _sig() => [for (final p in library.textPacks) '${p.id}${p.count}${p.date}'].join(',');

String _resSig = '';
List<CoreTopic> _resolved = const [];

/// Fresh copies of the Core 250 topics with the installed article of each (when there is one).
/// Cached until the installed packs change.
Future<List<CoreTopic>> resolveCore250({bool force = false}) async {
  final sig = _sig();
  if (!force && sig == _resSig && _resolved.isNotEmpty) return _resolved;
  final base = await loadCoreTopics();
  if (base.isEmpty || !library.ready) return const [];
  // the answer is kept in a small file next to the packs until they (or the list) change
  final fsig = '$sig|${base.length}|${base.fold<int>(0, (n, t) => n + t.patterns.length)}';
  final file = File('${library.dir.path}/core250.res');
  if (!force) {
    try {
      final j = jsonDecode(await file.readAsString()) as Map;
      if (j['sig'] == fsig) {
        final byTopic = {for (final e in (j['items'] as List)) '${(e as List)[0]}': e};
        final out = <CoreTopic>[];
        for (final b in base) {
          final t = CoreTopic(b.topic, b.specialty, b.priority, b.patterns);
          final e = byTopic[b.topic];
          if (e != null && e.length >= 4) {
            t.packId = '${e[1]}';
            t.index = (e[2] as num).toInt();
            t.title = '${e[3]}';
          }
          out.add(t);
        }
        _resSig = sig;
        return _resolved = out;
      }
    } catch (_) {}
  }
  final ix = CoreIndex();
  for (final p in library.textPacks) {
    if (p.kind == 'user') continue;
    final titles = await library.titlesOf(p.id);
    for (var i = 0; i < titles.length; i++) {
      ix.add(CoreCand(p.id, i, titles[i], library.sourceOf(p.id, titles[i]), p.id == kEssentialsPackId));
    }
  }
  final out = <CoreTopic>[];
  for (final b in base) {
    final t = CoreTopic(b.topic, b.specialty, b.priority, b.patterns);
    final sl = shortlist(t, ix, limit: 4);
    CoreCand? best;
    var bestScore = -1e9;
    for (final c in sl) {
      final a = await library.read(c.packId, c.index);
      if (a == null) continue;
      final chars = a.sections.fold<int>(0, (n, s) => n + s.text.length);
      final sc = c.score + sizeAdjust(chars);
      if (sc > bestScore) {
        bestScore = sc;
        best = c;
      }
    }
    if (best != null) {
      t.packId = best.packId;
      t.index = best.index;
      t.title = best.title;
    }
    out.add(t);
  }
  _resSig = sig;
  try {
    await file.writeAsString(jsonEncode({
      'sig': fsig,
      'items': [for (final t in out) if (t.resolved) [t.topic, t.packId, t.index, t.title]],
    }));
  } catch (_) {}
  return _resolved = out;
}

/// Resolved topic by 'pack|index' key.
Future<Map<String, CoreTopic>> coreByKey() async => {for (final t in await resolveCore250()) if (t.resolved) t.key: t};

/// Resolved topics of one specialty.
Future<List<CoreTopic>> coreOfSpecialty(String specialty) async => [for (final t in await resolveCore250()) if (t.resolved && t.specialty == specialty) t];

/// Specialty (Core 250 group) of an installed article, or null when it is not a core article.
Future<String?> coreSpecialtyOf(String packId, int index) async {
  final m = await coreByKey();
  return m['$packId|$index']?.specialty;
}

/// Core 250 specialty that matches the name of a rotation ("Orthopedics" -> "Orthopedics"), or null.
String? specialtyForRotation(String name) {
  final n = name.toLowerCase();
  const rules = <List<String>>[
    ['cardio', 'Cardiology'],
    ['pulmon', 'Pulmonology'],
    ['chest', 'Pulmonology'],
    ['gastro', 'Gastroenterology'],
    ['endocr', 'Endocrine/Metabolic'],
    ['diabet', 'Endocrine/Metabolic'],
    ['nephro', 'Nephrology/Fluids'],
    ['renal', 'Nephrology/Fluids'],
    ['urolog', 'Nephrology/Fluids'],
    ['hemat', 'Hematology/Oncology'],
    ['oncol', 'Hematology/Oncology'],
    ['infect', 'Infectious disease'],
    ['neuro', 'Neurology'],
    ['psych', 'Psychiatry'],
    ['emerg', 'Emergency/Critical care/Tox'],
    ['icu', 'Emergency/Critical care/Tox'],
    ['intensive', 'Emergency/Critical care/Tox'],
    ['critical', 'Emergency/Critical care/Tox'],
    ['anesth', 'Emergency/Critical care/Tox'],
    ['surg', 'Surgery'],
    ['orthop', 'Orthopedics'],
    ['rheum', 'Rheum/Immunology/Derm'],
    ['derm', 'Rheum/Immunology/Derm'],
    ['pediat', 'Pediatrics'],
    ['paediat', 'Pediatrics'],
    ['neonat', 'Pediatrics'],
    ['ob/gyn', 'OB/GYN'],
    ['obst', 'OB/GYN'],
    ['gyn', 'OB/GYN'],
    ['radiol', 'Radiology/Lab/Skills'],
    ['pharm', 'Pharmacology'],
  ];
  for (final r in rules) {
    if (n.contains(r[0])) return r[1];
  }
  return null;
}
