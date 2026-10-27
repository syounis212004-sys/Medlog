import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'lib_fts.dart';
import 'lib_text.dart';
import 'search_index.dart' show normText;

/// Offline medical library.
///
/// A pack is two files in the library folder:
///   <id>.idx   gzip(JSON): {"meta":{...},"t":[titles],"l":[lead snippets],"o":[offsets],"n":[lengths]}
///   <id>.bin   the articles, one independent gzip member each, so any article can
///              be read without loading the rest.
/// Article JSON: {"t": title, "u": source url, "s": [{"h": heading, "t": text}]}
/// Text only: no images and no tables, so a whole course is a few megabytes.

const String kLibraryCatalogUrl = 'https://raw.githubusercontent.com/syounis212004-sys/Medlog/main/library/catalog.json';

/// Where the course list is read from (tests point this at a local server).
String libraryCatalogUrl = kLibraryCatalogUrl;

class PackMeta {
  final String id;
  final String title;
  final String course;
  final int count;
  final int bytes;
  final String date;
  final String license;
  final String source;
  final String kind; // wiki | medline | user
  final String desc;
  final String forId; // image packs: the text pack they belong to
  const PackMeta({
    required this.id,
    required this.title,
    this.course = '',
    this.count = 0,
    this.bytes = 0,
    this.date = '',
    this.license = '',
    this.source = '',
    this.kind = 'wiki',
    this.desc = '',
    this.forId = '',
  });

  factory PackMeta.fromJson(Map<String, dynamic> j) => PackMeta(
        id: '${j['id']}',
        title: '${j['title'] ?? j['id']}',
        course: '${j['course'] ?? ''}',
        count: (j['count'] as num?)?.toInt() ?? 0,
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        date: '${j['date'] ?? ''}',
        license: '${j['license'] ?? ''}',
        source: '${j['source'] ?? ''}',
        kind: '${j['kind'] ?? 'wiki'}',
        desc: '${j['desc'] ?? ''}',
        forId: '${j['for'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'course': course,
        'count': count,
        'bytes': bytes,
        'date': date,
        'license': license,
        'source': source,
        'kind': kind,
        'desc': desc,
        'for': forId,
      };
}

class CatalogEntry {
  final PackMeta meta;
  final String idxUrl;
  final String binUrl;
  final String sha256Bin;
  final String sha256Idx;
  const CatalogEntry(this.meta, this.idxUrl, this.binUrl, this.sha256Bin, this.sha256Idx);
}

class LibTable {
  final String caption;
  final List<List<String>> rows; // first row is the header
  const LibTable(this.caption, this.rows);
  int get columns => rows.isEmpty ? 0 : rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);

  Map<String, dynamic> toJson() => {'c': caption, 'r': rows};

  static LibTable? fromJson(Object? j) {
    if (j is! Map) return null;
    final rows = <List<String>>[
      for (final r in (j['r'] as List? ?? const []))
        if (r is List) [for (final c in r) '${c ?? ''}'],
    ];
    if (rows.length < 2) return null;
    return LibTable('${j['c'] ?? ''}', rows);
  }
}

class LibSection {
  final String heading;
  final String text;
  final List<LibTable> tables;
  const LibSection(this.heading, this.text, [this.tables = const []]);
}

class LibArticle {
  final String title;
  final String url;
  final List<LibSection> sections;
  /// Optional per-article source line (set by packs that mix sources): name, license, authors, date.
  final String source;
  final String license;
  final String authors;
  final String date;
  final int chapter;
  const LibArticle(this.title, this.url, this.sections, {this.source = '', this.license = '', this.authors = '', this.date = '', this.chapter = 0});

  Map<String, dynamic> toJson() => {
        't': title,
        'u': url,
        's': [
          for (final s in sections) {'h': s.heading, 't': s.text, if (s.tables.isNotEmpty) 'tb': [for (final t in s.tables) t.toJson()]}
        ],
        if (source.isNotEmpty) 'src': source,
        if (license.isNotEmpty) 'lic': license,
        if (authors.isNotEmpty) 'au': authors,
        if (date.isNotEmpty) 'dt': date,
        if (chapter > 0) 'ch': chapter,
      };

  factory LibArticle.fromJson(Map<String, dynamic> j) => LibArticle(
        '${j['t'] ?? ''}',
        '${j['u'] ?? ''}',
        [
          for (final s in (j['s'] as List? ?? const []))
            LibSection('${(s as Map)['h'] ?? ''}', '${s['t'] ?? ''}', [
              for (final t in (s['tb'] as List? ?? const []))
                if (LibTable.fromJson(t) != null) LibTable.fromJson(t)!,
            ]),
        ],
        source: '${j['src'] ?? ''}',
        license: '${j['lic'] ?? ''}',
        authors: '${j['au'] ?? ''}',
        date: '${j['dt'] ?? ''}',
        chapter: (j['ch'] as num?)?.toInt() ?? 0,
      );
}

/// Optional book index metadata. The list order is the source chapter order.
class LibChapter {
  final int number;
  final String title;
  const LibChapter(this.number, this.title);
}

class LibHit {
  final String packId;
  final int index;
  final String title;
  final String lead;
  final int score;
  /// Search inside articles: the sentence that holds the words, the section it is in and the ranges to highlight
  /// (start, end, start, end ...). Empty for a hit found by title or lead.
  final String snippet;
  final String snippetHead;
  final List<int> marks;
  /// Every word of the query is in the title (false: some word was only found in the lead).
  final bool titleMatch;
  const LibHit(this.packId, this.index, this.title, this.lead, this.score, {this.snippet = '', this.snippetHead = '', this.marks = const [], this.titleMatch = true});
  bool get inText => snippet.isNotEmpty;
  LibHit withScore(int s) => LibHit(packId, index, title, lead, s, snippet: snippet, snippetHead: snippetHead, marks: marks, titleMatch: titleMatch);
}

/// normText with a fast path: normText only changes Arabic letters (and lower-cases), so any text without a character
/// of the Arabic block 0600-06FF only needs lower-casing (same result, no regex work).
String fastNorm(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x600 && c <= 0x6FF) return normText(s);
  }
  return s.toLowerCase();
}

final RegExp _sourceSuffix = RegExp(r'\s+—\s+(WikEM|Wikipedia|CDC|NCI|Project Tulip|MedlinePlus)$');

/// The source named at the end of an article title ("Sepsis — WikEM" -> "WikEM"), or null.
String? titleSource(String title) {
  final i = title.lastIndexOf(' — ');
  if (i < 0) return null;
  final m = _sourceSuffix.firstMatch(title.substring(i));
  return m?.group(1);
}

/// The title without its " — WikEM" style suffix.
String stripSource(String title) {
  final i = title.lastIndexOf(' — ');
  if (i < 0 || titleSource(title) == null) return title;
  return title.substring(0, i);
}

const List<String> _keyNames = ['wikem', 'wikipedia', 'cdc', 'nci', 'project tulip', 'medlineplus'];

/// Key that is the same for one condition in every source: lower-case title without " — WikEM" and similar.
String titleKey(String t) {
  var l = t.toLowerCase().trim();
  for (final n in _keyNames) {
    if (!l.endsWith(n)) continue;
    var i = l.length - n.length;
    while (i > 0 && (l.codeUnitAt(i - 1) == 0x20 || l.codeUnitAt(i - 1) == 0xA0 || l.codeUnitAt(i - 1) == 9)) {
      i--;
    }
    if (i > 0) {
      final c = l.codeUnitAt(i - 1);
      if (c == 0x2014 || c == 0x2013 || c == 0x2D) {
        i--;
        while (i > 0 && (l.codeUnitAt(i - 1) == 0x20 || l.codeUnitAt(i - 1) == 0xA0 || l.codeUnitAt(i - 1) == 9)) {
          i--;
        }
        l = l.substring(0, i);
        break;
      }
    }
  }
  for (var i = 0; i < l.length; i++) {
    final c = l.codeUnitAt(i);
    if (c == 9 || c == 10 || c == 13 || c == 0xA0 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x3000 || (c == 0x20 && i + 1 < l.length && l.codeUnitAt(i + 1) == 0x20)) return l.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  return l;
}

/// Sources a result can come from, in the order the filter chips show them.
const List<String> kSources = ['WikEM', 'CDC', 'NCI', 'Project Tulip', 'Wikipedia', 'MedlinePlus', 'My books'];

/// Id of the concise high-yield pack (gets a small ranking bonus).
const String kEssentialsPackId = 'clinical-essentials';

class _Idx {
  final List<String> titles;
  final List<String> leads;
  final List<int> offsets;
  final List<int> lengths;
  final List<String> normLeads;
  /// Normalised titles without the " — Source" suffix (used for matching and exact-match ranking).
  final List<String> normBase;
  /// [titleKey] of every title (same condition in several sources = same key).
  final List<String> baseKeys;
  /// Words of 4+ letters of the titles with their counts (for "did you mean").
  final Map<String, int> vocab;
  final List<int> chapterNumbers;
  final List<LibChapter> chapters;
  Map<String, int>? _pos;
  _Idx(this.titles, this.leads, this.offsets, this.lengths, this.normBase, this.normLeads, this.baseKeys, this.vocab, this.chapterNumbers, this.chapters);

  factory _Idx.fromMap(Map<String, Object?> j) => _Idx(
        (j['t'] as List).cast<String>(),
        (j['l'] as List).cast<String>(),
        (j['o'] as List).cast<int>(),
        (j['n'] as List).cast<int>(),
        (j['nb'] as List).cast<String>(),
        (j['nl'] as List).cast<String>(),
        (j['bk'] as List).cast<String>(),
        (j['v'] as Map).cast<String, int>(),
        (j['ch'] as List? ?? const []).cast<int>(),
        [for (final c in (j['chapters'] as List? ?? const [])) LibChapter((c['n'] as num).toInt(), '${c['t']}')],
      );

  /// Title -> position (built on first use).
  Map<String, int> get pos => _pos ??= {for (var i = 0; i < titles.length; i++) titles[i]: i};
}

class _ImgEntry {
  final int o, n;
  final String section, caption, file, credit;
  const _ImgEntry(this.o, this.n, this.section, this.caption, this.file, this.credit);
}

/// Image pack index. Version 2 keeps several pictures per article (with the section and caption
/// each belongs to); version 1 has one picture per article.
class _ImgIdx {
  final List<String> titles;
  final List<List<_ImgEntry>> arts;
  final Map<String, int> pos;
  _ImgIdx(this.titles, this.arts) : pos = {for (var i = 0; i < titles.length; i++) titles[i]: i};
}

class LibImage {
  final Uint8List bytes;
  final String credit;
  final String file;
  final bool online;
  final String caption;
  final String section;
  const LibImage(this.bytes, this.credit, this.file, this.online, {this.caption = '', this.section = ''});
  String get filePage => 'https://commons.wikimedia.org/wiki/File:${Uri.encodeComponent(file.replaceAll(' ', '_'))}';
}

Map<String, dynamic> _decodeIdx(Uint8List gz) => jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>;

/// Background isolate job: reads and decodes several text-pack indexes ({dir, ids}) and prepares everything the search
/// needs (normalised titles and leads, title keys, title words), so the main thread only receives finished lists.
Map<String, Map<String, Object?>> _decodeBucket(Map<String, Object?> args) {
  final dir = args['dir'] as String;
  final out = <String, Map<String, Object?>>{};
  for (final id in (args['ids'] as List).cast<String>()) {
    final j = _decodeIdx(File('$dir/$id.idx').readAsBytesSync());
    final t = List<String>.from(j['t'] as List), l = List<String>.from(j['l'] as List);
    final nb = [for (final x in t) fastNorm(stripSource(x))];
    final vocab = <String, int>{};
    for (final x in nb) {
      var st = -1;
      for (var i = 0; i <= x.length; i++) {
        final c = i < x.length ? x.codeUnitAt(i) : 0;
        final w = (c >= 97 && c <= 122) || (c >= 48 && c <= 57);
        if (w) {
          if (st < 0) st = i;
        } else if (st >= 0) {
          if (i - st >= 4) {
            final k = x.substring(st, i);
            vocab[k] = (vocab[k] ?? 0) + 1;
          }
          st = -1;
        }
      }
    }
    out[id] = {
      't': t,
      'l': l,
      'o': List<int>.from(j['o'] as List),
      'n': List<int>.from(j['n'] as List),
      'nb': nb,
      'nl': [for (final x in l) fastNorm(x)],
      'bk': [for (final x in t) titleKey(x)],
      'v': vocab,
      'ch': j['ch'] as List? ?? const <int>[],
      'chapters': j['chapters'] as List? ?? const <Map<String, Object?>>[],
    };
  }
  return out;
}

// ---------------------------------------------------------------- network seam

enum NetKind { wifi, mobile, none, unknown }

Future<NetKind> _realNetKind() async {
  try {
    final r = await Connectivity().checkConnectivity();
    if (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)) return NetKind.wifi;
    if (r.contains(ConnectivityResult.mobile)) return NetKind.mobile;
    if (r.isEmpty || r.every((e) => e == ConnectivityResult.none)) return NetKind.none;
    return NetKind.unknown; // vpn, bluetooth, other
  } catch (_) {
    return NetKind.unknown; // plugin missing or failing: never block the download
  }
}

/// What kind of network the phone is on. Tests replace this function.
Future<NetKind> Function() netKindProvider = _realNetKind;

/// Safe wrapper: a throwing provider counts as "unknown".
Future<NetKind> currentNetKind() async {
  try {
    return await netKindProvider();
  } catch (_) {
    return NetKind.unknown;
  }
}

/// Downloads of at least this size (or any picture pack) honour the Wi-Fi-only setting.
const int kBigDownloadBytes = 20 * 1024 * 1024;

/// How often "Wait for Wi-Fi" looks again (tests shorten it).
Duration wifiPollEvery = const Duration(seconds: 4);

/// Polls until the phone is on Wi-Fi / ethernet (true) or [cancelled] says stop (false).
Future<bool> waitForWifi({Duration? every, bool Function()? cancelled}) async {
  final gap = every ?? wifiPollEvery;
  while (true) {
    if (cancelled != null && cancelled()) return false;
    final k = await currentNetKind();
    if (k == NetKind.wifi || k == NetKind.unknown) return true;
    await Future<void>.delayed(gap);
  }
}

class LibraryStore extends ChangeNotifier {
  Directory? _dir;
  final List<PackMeta> packs = [];
  final Map<String, _Idx> _idx = {};
  bool ready = false;

  Directory get dir => _dir!;
  /// Text packs (articles). Image packs are listed separately.
  List<PackMeta> get textPacks => [for (final p in packs) if (p.kind != 'images') p];
  List<PackMeta> get imagePacks => [for (final p in packs) if (p.kind == 'images') p];
  int get totalCount => textPacks.fold(0, (a, p) => a + p.count);
  int get totalBytes => packs.fold(0, (a, p) => a + p.bytes);
  PackMeta? imagePackFor(String textPackId) {
    for (final p in imagePacks) {
      if (p.forId == textPackId) return p;
    }
    return null;
  }

  Future<void> init(Directory base, {List<String> bundled = const []}) async {
    _dir = Directory('${base.path}/library')..createSync(recursive: true);
    _idx.clear();
    _fts.clear();
    _ftsOk.clear();
    _vocab = null;
    packs.clear();
    final f = File('${dir.path}/installed.json');
    if (f.existsSync()) {
      try {
        for (final j in jsonDecode(await f.readAsString()) as List) {
          final m = PackMeta.fromJson(j as Map<String, dynamic>);
          if (File('${dir.path}/${m.id}.bin').existsSync() && File('${dir.path}/${m.id}.idx').existsSync()) packs.add(m);
        }
      } catch (_) {}
    }
    for (final id in bundled) {
      if (packs.any((p) => p.id == id)) continue;
      try {
        final idx = (await rootBundle.load('assets/library/$id.idx')).buffer.asUint8List();
        final bin = (await rootBundle.load('assets/library/$id.bin')).buffer.asUint8List();
        await File('${dir.path}/$id.idx').writeAsBytes(idx, flush: true);
        await File('${dir.path}/$id.bin').writeAsBytes(bin, flush: true);
        final meta = PackMeta.fromJson((_decodeIdx(idx)['meta'] as Map).cast<String, dynamic>());
        packs.add(PackMeta.fromJson({...meta.toJson(), 'bytes': idx.length + bin.length}));
      } catch (_) {}
    }
    await _saveInstalled();
    ready = true;
    notifyListeners();
  }

  Future<void> _saveInstalled() async {
    final f = File('${dir.path}/installed.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final p in packs) p.toJson()]), flush: true);
    await tmp.rename(f.path);
  }

  PackMeta? pack(String id) {
    for (final p in packs) {
      if (p.id == id) return p;
    }
    return null;
  }

  final Map<String, Completer<_Idx>> _loading = {};

  Future<_Idx> _index(String id) {
    final hit = _idx[id];
    if (hit != null) return Future.value(hit);
    final c = _loading[id];
    if (c != null) return c.future;
    _startLoad([id]);
    return _loading[id]!.future;
  }

  /// Decodes the indexes of [ids] in one background isolate; each id completes as soon as the batch is back.
  void _startLoad(List<String> ids) {
    final comps = {for (final id in ids) id: Completer<_Idx>()};
    _loading.addAll(comps);
    () async {
      try {
        final r = await compute(_decodeBucket, <String, Object?>{'dir': dir.path, 'ids': ids});
        for (final id in ids) {
          final x = _Idx.fromMap(r[id]!);
          _idx[id] = x;
          _loading.remove(id);
          _reconcileCount(id, x.titles.length);
          comps[id]!.complete(x);
        }
      } catch (e, st) {
        for (final id in ids) {
          _loading.remove(id);
          if (!comps[id]!.isCompleted) comps[id]!.completeError(e, st);
        }
      }
    }();
  }

  /// The pack list shows the number of articles that are really in the pack.
  void _reconcileCount(String id, int n) {
    final i = packs.indexWhere((p) => p.id == id);
    if (i < 0 || packs[i].count == n) return;
    packs[i] = PackMeta.fromJson({...packs[i].toJson(), 'count': n});
    _saveInstalled().then((_) {}, onError: (_) {});
    notifyListeners();
  }

  /// Loads the indexes of all text packs at the same time (first search / quiz): the work is split over up to four
  /// background isolates of about the same size, so the main thread only receives finished lists.
  Future<void> warmUp([List<PackMeta>? only]) async {
    final want = only ?? textPacks;
    final ids = [for (final p in want) if (!_idx.containsKey(p.id) && !_loading.containsKey(p.id)) p.id];
    if (ids.isNotEmpty) {
      final sized = <(String, int)>[];
      for (final id in ids) {
        var n = 0;
        try {
          n = File('${dir.path}/$id.idx').lengthSync();
        } catch (_) {}
        sized.add((id, n));
      }
      sized.sort((a, b) => b.$2.compareTo(a.$2));
      final nb = ids.length < 4 ? ids.length : 4;
      final buckets = List.generate(nb, (_) => <String>[]);
      final load = List<int>.filled(nb, 0);
      for (final e in sized) {
        var k = 0;
        for (var i = 1; i < nb; i++) {
          if (load[i] < load[k]) k = i;
        }
        buckets[k].add(e.$1);
        load[k] += e.$2 + 1;
      }
      for (final b in buckets) {
        _startLoad(b);
      }
    }
    await Future.wait([for (final p in want) _index(p.id)]);
  }

  /// Where an article comes from: WikEM / CDC / NCI / Project Tulip / Wikipedia / MedlinePlus / My files.
  String sourceOf(String packId, String title) {
    final s = titleSource(title);
    if (s != null) return s;
    final p = pack(packId);
    if (p == null) return 'Wikipedia';
    if (p.kind == 'book') return 'My books';
    if (p.kind == 'medline') return 'MedlinePlus';
    if (p.kind == 'user') return 'My files';
    return 'Wikipedia';
  }

  /// Sources that exist in the installed packs (for the filter chips), in [kSources] order.
  List<String> availableSources() {
    final out = <String>{};
    for (final p in textPacks) {
      if (p.id == kEssentialsPackId) {
        out.addAll(['WikEM', 'CDC', 'NCI', 'Project Tulip', 'Wikipedia']);
      } else if (p.kind == 'medline') {
        out.add('MedlinePlus');
      } else if (p.kind == 'wiki') {
        out.add('Wikipedia');
      } else if (p.kind == 'book') {
        out.add('My books');
      }
    }
    return [for (final s in kSources) if (out.contains(s)) s];
  }

  Future<List<String>> titlesOf(String id) async => (await _index(id)).titles;
  /// Titles of a pack whose index is already loaded (empty list otherwise).
  List<String> titlesSync(String id) => _idx[id]?.titles ?? const [];
  /// [titleKey] of every title of the pack (same key = same condition in another source).
  Future<List<String>> baseKeysOf(String id) async => (await _index(id)).baseKeys;
  Future<List<String>> leadsOf(String id) async => (await _index(id)).leads;
  Future<List<int>> chapterNumbersOf(String id) async => (await _index(id)).chapterNumbers;
  Future<List<LibChapter>> chaptersOf(String id) async => (await _index(id)).chapters;

  Future<LibArticle?> read(String id, int i) async {
    try {
      final x = await _index(id);
      if (i < 0 || i >= x.offsets.length) return null;
      final raf = await File('${dir.path}/$id.bin').open();
      try {
        await raf.setPosition(x.offsets[i]);
        final bytes = await raf.read(x.lengths[i]);
        return LibArticle.fromJson(jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  static bool _startsWord(String t, String w) {
    var i = t.indexOf(w);
    while (i >= 0) {
      if (i == 0) return true;
      final c = t.codeUnitAt(i - 1);
      if (!((c >= 97 && c <= 122) || (c >= 48 && c <= 57))) return true;
      i = t.indexOf(w, i + 1);
    }
    return false;
  }

  /// Every word must appear in the title or the first lines. Titles count more.
  Future<List<LibHit>> search(String query, {String? packId, int limit = 60, String? source}) async {
    final words = normText(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final whole = words.join(' ');
    final hits = <LibHit>[];
    final packsToSearch = [for (final p in textPacks) if (packId == null || p.id == packId) p];
    if (packsToSearch.length > 1) await warmUp(packsToSearch);
    for (final p in packsToSearch) {
      final x = await _index(p.id);
      final bonus = p.id == kEssentialsPackId ? 6 : 0; // concise high-yield article beats a long encyclopedia one on a tie
      final fixed = p.id == kEssentialsPackId ? null : sourceOf(p.id, '');
      if (source != null && fixed != null && fixed != source) continue;
      for (var i = 0; i < x.normBase.length; i++) {
        if (source != null && fixed == null && titleSource(x.titles[i]) != source) continue;
        final t = x.normBase[i];
        var score = 0;
        var ok = true;
        var inTitle = true;
        for (final w in words) {
          // very short words (OA, MI) must start a word, so "oa" does not match "throat"
          final short = w.length <= 3;
          if (short ? ' $t'.contains(' $w') : t.contains(w)) {
            // a piece in the middle of a longer word (stemi in systemic) counts less than a word or a word start
            score += short || _startsWord(t, w) ? 20 : 9;
          } else if (short ? ' ${x.normLeads[i]}'.contains(' $w') : x.normLeads[i].contains(w)) {
            score += 4;
            inTitle = false;
          } else {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        if (t == whole) {
          score += 200;
        } else if (t.startsWith(whole)) {
          score += 80;
        } else if (words.length == 1 && ' $t '.contains(' $whole ')) {
          score += 6; // the whole word, not a piece of a longer one
        }
        score -= t.length ~/ 12; // shorter titles first
        score += bonus;
        hits.add(LibHit(p.id, i, x.titles[i], x.leads[i], score, titleMatch: inTitle));
      }
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  // ------------------------------------------------------------ search helpers

  Map<String, int>? _vocab;

  /// Words of the titles of all packs with their counts; merged from the per-pack lists made in the background.
  Future<Map<String, int>> _vocabulary() async {
    final v = _vocab;
    if (v != null) return v;
    final m = <String, int>{};
    await warmUp();
    for (final p in textPacks) {
      final x = await _index(p.id);
      x.vocab.forEach((w, n) => m[w] = (m[w] ?? 0) + n);
    }
    return _vocab = m;
  }

  /// How much a source is worth when "Concise sources first" is on (short, structured sources rank higher).
  int _conciseBonus(String packId, String title) {
    final src = sourceOf(packId, title);
    switch (src) {
      case 'WikEM':
        return 14;
      case 'Project Tulip':
        return 10;
      case 'CDC':
        return 6;
      case 'Wikipedia':
        return packId == kEssentialsPackId ? 10 : 0;
      case 'MedlinePlus':
        return -2;
      default:
        return 0;
    }
  }

  /// One result per condition and source: "Osteoarthritis" of the course pack and of the essentials pack is one row
  /// (the better ranked one stays). [sorted] must be sorted by score.
  List<LibHit> _dedupe(List<LibHit> sorted) {
    final seen = <String>{};
    final out = <LibHit>[];
    for (final h in sorted) {
      final key = '${_idx[h.packId]?.baseKeys[h.index] ?? titleKey(h.title)}|${sourceOf(h.packId, h.title)}';
      if (seen.add(key)) out.add(h);
    }
    return out;
  }

  /// Same as [search] but also understands abbreviations (OA, MI, DVT...). With [body] the words are also looked for
  /// inside the articles (needs the in-text index, see [ensureFts]): those hits come after the title hits and carry the
  /// matching sentence. [concise] puts short, structured sources (WikEM, Tulip, CDC) before long ones.
  /// One row per condition and source.
  Future<List<LibHit>> searchEx(String query, {String? packId, int limit = 60, String? source, bool body = false, bool concise = false, bool booksFirst = true, bool strict = false}) async {
    final seen = <String>{};
    final all = <LibHit>[];
    final variants = expandAbbrev(query);
    for (var vi = 0; vi < variants.length; vi++) {
      for (final h in await search(variants[vi], packId: packId, limit: limit * 2, source: source)) {
        // what an abbreviation stands for comes before accidental matches of the letters
        if (seen.add('${h.packId}|${h.index}')) all.add(vi == 0 ? h : h.withScore(h.score + 150));
      }
    }
    if (concise) {
      for (var i = 0; i < all.length; i++) {
        all[i] = all[i].withScore(all[i].score + _conciseBonus(all[i].packId, all[i].title));
      }
    }
    all.sort((a, b) => b.score.compareTo(a.score));
    final titleHits = _dedupe(all);
    List<LibHit> result;
    if (!body) {
      result = titleHits;
    } else {
      final room = limit < 20 ? limit ~/ 2 : 20;
      final inText = await _bodyHits(variants, packId: packId, source: source, skip: seen, max: room, concise: concise);
      // title matches first; hits that only have a word in the lead are ranked together with the in-text hits
      final strong = [for (final h in titleHits) if (h.titleMatch) h];
      final rest = [...[for (final h in titleHits) if (!h.titleMatch) h], ...inText]..sort((a, b) => b.score.compareTo(a.score));
      final keepStrong = strong.length > limit - inText.length ? limit - inText.length : strong.length;
      result = [...strong.take(keepStrong), ...rest.take(limit - keepStrong)];
    }
    result = _byPhrase(result, query, strict: strict);
    if (booksFirst) {
      bool isBook(LibHit h) => pack(h.packId)?.kind == 'book';
      result = [...result.where(isBook), ...result.where((h) => !isBook(h))];
    }
    return result.length > limit ? result.sublist(0, limit) : result;
  }

  /// A query of several words means that expression ("down syndrome"), not each word on its own: hits that have the
  /// whole expression in the title, the lead or the matching sentence come first, and when there are any, hits that
  /// only have the words scattered about are left out.
  List<LibHit> _byPhrase(List<LibHit> hits, String query, {bool strict = false}) {
    final words = normText(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2 || hits.isEmpty) return hits;
    final phrase = ' ${words.join(' ')} ';
    bool has(String s) => ' ${normText(s)} '.contains(phrase);
    bool allIn(String s) {
      final n = ' ${normText(s)} ';
      return words.every((w) => w.length <= 3 ? n.contains(' $w') : n.contains(w));
    }
    final strong = <LibHit>[], weak = <LibHit>[];
    for (final h in hits) {
      final inTitle = has(h.title);
      if (inTitle || has(h.lead) || (h.inText && has(h.snippet))) {
        strong.add(h.withScore(h.score + (inTitle ? 160 : 80)));
      } else if (allIn(h.title)) {
        strong.add(h);
      } else {
        weak.add(h);
      }
    }
    if (strong.isEmpty) return strict ? const [] : hits;
    strong.sort((a, b) => b.score.compareTo(a.score));
    return strong;
  }

  /// A corrected query when a word looks like a typo of a known title word, else null.
  Future<String?> didYouMean(String query) async {
    final vocab = await _vocabulary();
    if (vocab.isEmpty) return null;
    var changed = false;
    final out = <String>[];
    for (final w in normText(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      if (w.length < 5 || vocab.containsKey(w) || kLibAbbrev.containsKey(w) || await ftsKnows(w)) {
        out.add(w);
        continue;
      }
      final maxD = w.length <= 7 ? 1 : 2;
      String? best;
      var bd = maxD + 1, bc = 0;
      for (final e in vocab.entries) {
        final c = e.key;
        if ((c.length - w.length).abs() > maxD || c[0] != w[0]) continue;
        final d = editDistance(w, c, max: maxD);
        if (d < bd || (d == bd && e.value > bc)) {
          best = c;
          bd = d;
          bc = e.value;
        }
      }
      if (best != null && bd <= maxD) {
        out.add(best);
        changed = true;
      } else {
        out.add(w);
      }
    }
    return changed ? out.join(' ') : null;
  }

  // ------------------------------------------------------------ search inside articles (in-text index)

  final Map<String, FtsReader?> _fts = {};
  final Map<String, bool> _ftsOk = {};
  bool ftsBuilding = false;
  int ftsDone = 0, ftsTotal = 0;
  Future<void>? _ftsRun;

  int _ftsSigOf(PackMeta p) {
    var n = 0;
    try {
      n = File('${dir.path}/${p.id}.bin').lengthSync();
    } catch (_) {}
    return ftsSig(p.date, 0, n);
  }

  /// True when <id>.fts exists and belongs to the installed copy of the pack (reads only the 40-byte header).
  bool ftsFileOk(PackMeta p) {
    final hit = _ftsOk[p.id];
    if (hit != null) return hit;
    var ok = false;
    try {
      final f = File('${dir.path}/${p.id}.fts');
      if (f.existsSync()) {
        final raf = f.openSync();
        try {
          final h = raf.readSync(40);
          if (h.length == 40) {
            final bd = ByteData.view(h.buffer, h.offsetInBytes, 40);
            ok = bd.getUint32(0, Endian.little) == kFtsMagic && bd.getUint32(4, Endian.little) == _ftsSigOf(p) && bd.getUint32(36, Endian.little) == f.lengthSync();
          }
        } finally {
          raf.closeSync();
        }
      }
    } catch (_) {}
    return _ftsOk[p.id] = ok;
  }

  /// Text packs that have an in-text index.
  int get ftsIndexed => textPacks.where(ftsFileOk).length;

  void _ftsForget(String id) {
    _fts.remove(id);
    _ftsOk.remove(id);
  }

  /// Builds the in-text index of every text pack that has none (one background isolate, one pack at a time, concise
  /// packs first). Safe to call often: a running build is shared.
  /// With [only] just that pack (after an install); calls are queued one after the other.
  Future<void> ensureFts({String? only}) {
    final prev = _ftsRun ?? Future<void>.value();
    late Future<void> f;
    f = prev.then((_) => _buildFts(only)).whenComplete(() {
      if (identical(_ftsRun, f)) _ftsRun = null;
    });
    return _ftsRun = f;
  }

  Future<void> _buildFts(String? only) async {
    final todo = [for (final p in textPacks) if ((only == null || p.id == only) && !ftsFileOk(p)) p];
    if (todo.isEmpty) return;
    int rank(PackMeta p) => p.id == kEssentialsPackId ? 0 : (p.kind == 'medline' ? 1 : 2);
    todo.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : a.bytes.compareTo(b.bytes);
    });
    ftsTotal = todo.length;
    ftsDone = 0;
    ftsBuilding = true;
    notifyListeners();
    try {
      for (final p in todo) {
        if (pack(p.id) == null) continue;
        try {
          await compute(ftsBuildJob, <String, Object?>{'dir': dir.path, 'id': p.id, 'sig': _ftsSigOf(p)});
        } catch (_) {}
        _ftsForget(p.id);
        ftsDone++;
        notifyListeners();
      }
    } finally {
      ftsBuilding = false;
      notifyListeners();
    }
  }

  /// Loads the in-text indexes in the background (the first search inside articles is then quick).
  Future<void> warmFts() async {
    for (final p in textPacks) {
      await _ftsFor(p);
    }
  }

  Future<FtsReader?> _ftsFor(PackMeta p) async {
    if (_fts.containsKey(p.id)) return _fts[p.id];
    FtsReader? r;
    if (ftsFileOk(p)) {
      try {
        r = FtsReader.open(await File('${dir.path}/${p.id}.fts').readAsBytes(), _ftsSigOf(p));
      } catch (_) {}
    }
    return _fts[p.id] = r;
  }

  /// True when [word] is in the in-text index of some pack (so it is a real word, not a typo to "correct").
  Future<bool> ftsKnows(String word) async {
    final h = ftsHash(word);
    for (final p in textPacks) {
      final r = await _ftsFor(p);
      if (r != null && (r.has(h) || r.isStop(h))) return true;
    }
    return false;
  }

  Future<List<LibHit>> _bodyHits(List<String> variants, {String? packId, String? source, required Set<String> skip, required int max, required bool concise}) async {
    final readers = <PackMeta, FtsReader>{};
    for (final p in textPacks) {
      if (packId != null && p.id != packId) continue;
      final r = await _ftsFor(p);
      if (r != null) readers[p] = r;
    }
    if (readers.isEmpty) return const [];
    final cands = <({String pack, int doc, int score, int variant})>[];
    final parsed = [for (final v in variants) ftsParseQuery(v)];
    final best = <String, int>{}; // condition|source -> position in cands
    for (var vi = 0; vi < parsed.length; vi++) {
      if (parsed[vi].isEmpty) continue;
      for (final e in readers.entries) {
        final found = e.value.search(parsed[vi], max: 150);
        if (found.isEmpty) continue;
        final x = await _index(e.key.id);
        final fixed = e.key.id == kEssentialsPackId ? null : sourceOf(e.key.id, '');
        if (source != null && fixed != null && fixed != source) continue;
        for (final c in found) {
          if (c.doc >= x.titles.length || skip.contains('${e.key.id}|${c.doc}')) continue;
          if (source != null && fixed == null && titleSource(x.titles[c.doc]) != source) continue;
          var score = c.score - (x.lengths[c.doc] ~/ 6000).clamp(0, 8) + (e.key.id == kEssentialsPackId ? 6 : 0);
          if (concise) score += _conciseBonus(e.key.id, x.titles[c.doc]);
          final key = '${x.baseKeys[c.doc]}|${sourceOf(e.key.id, x.titles[c.doc])}';
          final at = best[key];
          if (at != null) {
            if (cands[at].score >= score) continue;
            cands[at] = (pack: e.key.id, doc: c.doc, score: score, variant: vi);
          } else {
            best[key] = cands.length;
            cands.add((pack: e.key.id, doc: c.doc, score: score, variant: vi));
          }
        }
      }
    }
    if (cands.isEmpty) return const [];
    cands.sort((a, b) => b.score.compareTo(a.score));
    // the best candidates, with their matching sentence (a few are dropped when it turns out the index hit was a false match)
    final take = cands.take(max + 6).toList();
    final out = <LibHit>[];
    final snippets = List<Map<String, Object?>?>.filled(take.length, null);
    for (var vi = 0; vi < parsed.length; vi++) {
      final idxs = [for (var i = 0; i < take.length; i++) if (take[i].variant == vi) i];
      if (idxs.isEmpty) continue;
      final jobs = <List<Object>>[];
      for (final i in idxs) {
        final x = _idx[take[i].pack]!;
        jobs.add([take[i].pack, x.offsets[take[i].doc], x.lengths[take[i].doc]]);
      }
      List<Map<String, Object?>?> r;
      try {
        r = await compute(ftsSnippetJob, <String, Object?>{
          'dir': dir.path,
          'jobs': jobs,
          'terms': [for (final t in parsed[vi]) t.alts],
          'fallbacks': [for (final t in parsed[vi]) [for (final f in t.fallback) f.alts]],
        });
      } catch (_) {
        continue;
      }
      for (var k = 0; k < idxs.length && k < r.length; k++) {
        snippets[idxs[k]] = r[k];
      }
    }
    for (var i = 0; i < take.length && out.length < max; i++) {
      final sn = snippets[i];
      if (sn == null) continue;
      final x = _idx[take[i].pack]!;
      out.add(LibHit(take[i].pack, take[i].doc, x.titles[take[i].doc], x.leads[take[i].doc], take[i].score,
          snippet: '${sn['s']}', snippetHead: '${sn['h']}', marks: (sn['m'] as List).cast<int>()));
    }
    return out;
  }

  Future<int?> indexOfTitle(String packId, String title) async => (await _index(packId)).pos[title];

  /// Other articles of the same course that share the main words of this title.
  Future<List<LibHit>> related(String packId, int index, {int limit = 6}) async {
    final x = await _index(packId);
    if (index < 0 || index >= x.titles.length) return const [];
    const stop = {'with', 'from', 'disease', 'syndrome', 'disorder', 'type', 'acute', 'chronic', 'and', 'the', 'of', 'in'};
    final words = x.normBase[index].split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 4 && !stop.contains(w)).toList();
    if (words.isEmpty) return const [];
    final hits = <LibHit>[];
    for (var i = 0; i < x.normBase.length; i++) {
      if (i == index) continue;
      var sc = 0;
      for (final w in words) {
        if (x.normBase[i].contains(w)) {
          sc += 10;
        } else if (x.normLeads[i].contains(w)) {
          sc += 1;
        }
      }
      if (sc >= 10) hits.add(LibHit(packId, i, x.titles[i], x.leads[i], sc));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  /// Article count and one deterministic pick per day for [packId] (e.g. "topic of the day").
  Future<int?> dailyPick(String packId, String seed) async {
    final x = await _index(packId);
    if (x.titles.isEmpty) return null;
    final good = [for (var i = 0; i < x.leads.length; i++) if (x.leads[i].length > 120) i];
    if (good.isEmpty) return null;
    final h = md5.convert(utf8.encode('$seed|$packId')).bytes;
    final n = (h[0] << 16) | (h[1] << 8) | h[2];
    return good[n % good.length];
  }

  // ------------------------------------------------------------ images

  final Map<String, _ImgIdx> _imgIdx = {};

  Future<_ImgIdx?> _imageIndex(String id) async {
    final hit = _imgIdx[id];
    if (hit != null) return hit;
    try {
      final j = await compute(_decodeIdx, await File('${dir.path}/$id.idx').readAsBytes());
      final t = (j['t'] as List).cast<String>();
      final arts = <List<_ImgEntry>>[];
      if (j['v'] == 2) {
        for (final a in (j['a'] as List)) {
          arts.add([
            for (final e in (a as List))
              _ImgEntry((e['o'] as num).toInt(), (e['n'] as num).toInt(), '${e['s'] ?? ''}', '${e['c'] ?? ''}', '${e['f'] ?? ''}', '${e['u'] ?? 'Wikimedia Commons'}'),
          ]);
        }
      } else {
        final o = (j['o'] as List).cast<int>(), n = (j['n'] as List).cast<int>(), c = (j['c'] as List).cast<String>(), f = (j['f'] as List).cast<String>();
        for (var i = 0; i < t.length; i++) {
          arts.add([_ImgEntry(o[i], n[i], '', '', f[i], c[i])]);
        }
      }
      return _imgIdx[id] = _ImgIdx(t, arts);
    } catch (_) {
      return null;
    }
  }

  /// All downloaded pictures of an article (each with its section, caption and credit).
  Future<List<LibImage>> imagesFor(String title, {String? packId}) async {
    final out = <LibImage>[];
    for (final p in imagePacks) {
      if (packId != null && p.forId != packId) continue;
      final x = await _imageIndex(p.id);
      final i = x?.pos[title];
      if (x == null || i == null) continue;
      final raf = await File('${dir.path}/${p.id}.bin').open();
      try {
        for (final e in x.arts[i]) {
          await raf.setPosition(e.o);
          final bytes = await raf.read(e.n);
          out.add(LibImage(Uint8List.fromList(bytes), e.credit, e.file, false, caption: e.caption, section: e.section));
        }
      } finally {
        await raf.close();
      }
    }
    return out;
  }

  /// The first downloaded picture for an article title, if an image pack has one.
  Future<LibImage?> imageFor(String title) async {
    final l = await imagesFor(title);
    return l.isEmpty ? null : l.first;
  }

  /// Pictures of an article from Wikipedia when online (up to [max], cached on the phone afterwards).
  Future<List<LibImage>> onlineImagesFor(String title, {int max = 8}) async {
    final key = md5.convert(utf8.encode(title)).toString();
    final cache = Directory('${dir.path}/imgcache')..createSync(recursive: true);
    final fMeta = File('${cache.path}/$key.json');
    if (fMeta.existsSync()) {
      try {
        final m = jsonDecode(await fMeta.readAsString()) as List;
        final out = <LibImage>[];
        for (var i = 0; i < m.length; i++) {
          final f = File('${cache.path}/${key}_$i.img');
          if (f.existsSync()) {
            final e = m[i] as Map;
            out.add(LibImage(await f.readAsBytes(), '${e['credit']}', '${e['file']}', true, caption: '${e['caption'] ?? ''}'));
          }
        }
        return out;
      } catch (_) {}
    }
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      Future<HttpClientResponse> get(String url) async {
        final req = await c.getUrl(Uri.parse(url));
        req.headers.set('User-Agent', 'MedLog/1.6 (offline medical logbook)');
        return req.close().timeout(const Duration(seconds: 15));
      }

      final res = await get('https://en.wikipedia.org/api/rest_v1/page/media-list/${Uri.encodeComponent(title.replaceAll(' ', '_'))}');
      if (res.statusCode != 200) return const [];
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final out = <LibImage>[];
      final meta = <Map<String, String>>[];
      const credit = 'Wikimedia Commons — author and license on the file page';
      for (final it in (j['items'] as List? ?? const [])) {
        if (out.length >= max) break;
        if (it is! Map || it['type'] != 'image' || it['showInGallery'] == false) continue;
        final srcset = it['srcset'] as List?;
        if (srcset == null || srcset.isEmpty) continue;
        var src = '${(srcset.first as Map)['src']}';
        if (src.startsWith('//')) src = 'https:$src';
        if (src.toLowerCase().contains('.svg')) continue;
        final r2 = await get(src);
        if (r2.statusCode != 200) continue;
        final b = BytesBuilder(copy: false);
        var tooBig = false;
        await for (final ch in r2) {
          b.add(ch);
          if (b.length > 500 * 1024) {
            tooBig = true;
            break;
          }
        }
        if (tooBig) continue;
        final bytes = b.takeBytes();
        final file = '${it['title'] ?? ''}'.replaceFirst(RegExp(r'^File:'), '');
        final cap = '${(it['caption'] as Map?)?['text'] ?? ''}';
        await File('${cache.path}/${key}_${out.length}.img').writeAsBytes(bytes, flush: true);
        meta.add({'credit': credit, 'file': file, 'caption': cap});
        out.add(LibImage(bytes, credit, file, true, caption: cap));
      }
      await fMeta.writeAsString(jsonEncode(meta));
      return out;
    } catch (_) {
      return const [];
    } finally {
      c.close(force: true);
    }
  }

  Future<int> imageCacheBytes() async {
    if (_dir == null) return 0; // the library is still starting
    final d = Directory('${dir.path}/imgcache');
    if (!d.existsSync()) return 0;
    var n = 0;
    for (final f in d.listSync()) {
      if (f is File) n += f.lengthSync();
    }
    return n;
  }

  Future<void> clearImageCache() async {
    final d = Directory('${dir.path}/imgcache');
    if (d.existsSync()) await d.delete(recursive: true);
  }

  // ------------------------------------------------------------ writing packs

  /// Writes a pack from articles already in memory (used for the user's own files).
  Future<PackMeta> writePack(PackMeta meta, List<LibArticle> articles) async {
    final sorted = [...articles]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final bin = BytesBuilder(copy: false);
    final titles = <String>[], leads = <String>[], offsets = <int>[], lengths = <int>[];
    for (final a in sorted) {
      final member = gzip.encode(utf8.encode(jsonEncode(a.toJson())));
      titles.add(a.title);
      leads.add(_lead(a));
      offsets.add(bin.length);
      lengths.add(member.length);
      bin.add(member);
    }
    final binBytes = bin.takeBytes();
    final full = PackMeta.fromJson({...meta.toJson(), 'count': sorted.length});
    final idxBytes = gzip.encode(utf8.encode(jsonEncode({'meta': full.toJson(), 't': titles, 'l': leads, 'o': offsets, 'n': lengths})));
    await File('${dir.path}/${meta.id}.bin').writeAsBytes(binBytes, flush: true);
    await File('${dir.path}/${meta.id}.idx').writeAsBytes(idxBytes, flush: true);
    final done = PackMeta.fromJson({...full.toJson(), 'bytes': binBytes.length + idxBytes.length});
    _idx.remove(meta.id);
    _ftsForget(meta.id);
    _vocab = null;
    packs.removeWhere((p) => p.id == meta.id);
    packs.add(done);
    await _saveInstalled();
    notifyListeners();
    ensureFts(only: meta.id).then((_) {}, onError: (_) {});
    return done;
  }

  static String _lead(LibArticle a) {
    for (final s in a.sections) {
      final t = s.text.replaceAll('\n', ' ').trim();
      if (t.isNotEmpty) return t.length > 180 ? '${t.substring(0, 180)}…' : t;
    }
    return '';
  }

  /// Import one local book and its image pair without contacting the public catalog.
  Future<void> importLocalBook(List<String> paths) async {
    late final String id;
    late final String imageId;
    if (!ready) throw StateError('Library is not ready');
    if (_localBookImporting) throw StateError('A local import is already running');
    _localBookImporting = true;
    Directory? staging;
    final previousPacks = List<PackMeta>.of(packs);
    final backups = <String, String>{};
    final written = <String>[];
    try {
      final files = <String, File>{};
      bool candidate(String name) => name.endsWith('.local.json') ||
          ['.bin', '.idx', '.img', '.imx'].any(name.endsWith);
      for (final path in paths) {
        final name = path.split(Platform.pathSeparator).last;
        if (name.toLowerCase().endsWith('.zip')) {
          // Keep only possible pack files. The manifest determines the exact five names below.
          staging ??= await dir.createTemp('.local-book-');
          final zip = ZipDecoder().decodeBytes(await File(path).readAsBytes());
          for (final entry in zip.files) {
            final base = entry.name.split('/').last;
            if (!entry.isFile || !candidate(base) || entry.name.contains('..')) continue;
            if (files.containsKey(base)) throw FormatException('Duplicate file: $base');
            final out = File('${staging.path}/zip_$base');
            await out.writeAsBytes(entry.content as List<int>, flush: true);
            files[base] = out;
          }
          continue;
        }
        if (!candidate(name)) continue;
        if (files.containsKey(name)) throw FormatException('Duplicate file: $name');
        files[name] = File(path);
      }
      Future<Uint8List> readFile(String name) async {
        final file = files[name];
        if (file == null) throw FormatException('Select all five files. Missing: $name');
        return file.readAsBytes();
      }

      final manifests = files.keys.where((name) => name.endsWith('.local.json')).toList();
      if (manifests.length != 1) throw const FormatException('Select one local book manifest');
      final manifest = jsonDecode(utf8.decode(await readFile(manifests.single))) as Map<String, dynamic>;
      final entries = manifest['packs'] as List;
      if (manifest['version'] != 1 || entries.length != 1) throw const FormatException('Invalid local manifest');
      final text = (entries.single as Map).cast<String, dynamic>();
      final images = (text['images'] as Map).cast<String, dynamic>();
      id = '${text['id'] ?? ''}';
      imageId = '$id-images';
      if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id) || manifests.single != '$id.local.json' ||
          text['kind'] != 'book' || images['id'] != imageId || images['kind'] != 'images' || images['for'] != id) {
        throw const FormatException('Wrong local course');
      }
      final data = <String, Uint8List>{};
      final imported = <PackMeta>[];
      for (final entry in [text, images]) {
        final isImage = entry['kind'] == 'images';
        final packId = isImage ? imageId : id;
        final existing = pack(packId);
        if (existing != null && (existing.kind != entry['kind'] || (isImage && existing.forId != id))) {
          throw FormatException('Pack id already belongs to another course: $packId');
        }
        final binName = '$packId.${isImage ? 'img' : 'bin'}';
        final idxName = '$packId.${isImage ? 'imx' : 'idx'}';
        if (entry[isImage ? 'img' : 'bin'] != binName || entry[isImage ? 'imx' : 'idx'] != idxName) {
          throw const FormatException('Unexpected pack filenames');
        }
        final bin = await readFile(binName), idx = await readFile(idxName);
        if (sha256.convert(bin).toString() != entry['sha256_bin'] || sha256.convert(idx).toString() != entry['sha256_idx']) {
          throw FormatException('Checksum mismatch: $packId');
        }
        final decoded = _decodeIdx(idx);
        final meta = PackMeta.fromJson((decoded['meta'] as Map).cast<String, dynamic>());
        if (meta.id != packId || meta.kind != entry['kind'] || (isImage && (meta.forId != id || decoded['v'] != 2))) {
          throw FormatException('Invalid index: $packId');
        }
        if (!isImage && decoded['ch'] != null) {
          final numbers = List<int>.from(decoded['ch'] as List);
          final chapters = (decoded['chapters'] as List).cast<Map>();
          final declared = {for (final chapter in chapters) chapter['n']};
          if (numbers.length != (decoded['t'] as List).length || declared.length != chapters.length ||
              chapters.any((chapter) => chapter['n'] is! int || (chapter['n'] as int) <= 0 || '${chapter['t'] ?? ''}'.trim().isEmpty) ||
              numbers.any((number) => !declared.contains(number))) {
            throw const FormatException('Invalid book chapter metadata');
          }
        }
        data['$packId.bin'] = bin;
        data['$packId.idx'] = idx;
        imported.add(PackMeta.fromJson({...meta.toJson(), 'bytes': bin.length + idx.length}));
      }
      // Validate both pairs before replacing anything. Keep backups for I/O errors.
      staging ??= await dir.createTemp('.local-book-');
      for (final e in data.entries) {
        await File('${staging.path}/${e.key}').writeAsBytes(e.value, flush: true);
      }
      for (final name in data.keys) {
        final destination = '${dir.path}/$name';
        if (await File(destination).exists()) {
          final backup = '${staging.path}/$name.backup';
          await File(destination).rename(backup);
          backups[destination] = backup;
        }
        await File('${staging.path}/$name').rename(destination);
        written.add(destination);
      }
      packs.removeWhere((p) => p.id == id || p.id == imageId);
      packs.addAll(imported);
      await _saveInstalled();
    } catch (_) {
      for (final path in written.reversed) {
        if (await File(path).exists()) await File(path).delete();
      }
      for (final e in backups.entries) {
        await File(e.value).rename(e.key);
      }
      packs..clear()..addAll(previousPacks);
      rethrow;
    } finally {
      _localBookImporting = false;
      if (staging != null) {
        try { await staging.delete(recursive: true); } catch (_) {}
      }
    }
    for (final packId in [id, imageId]) {
      _idx.remove(packId);
      _imgIdx.remove(packId);
      _ftsForget(packId);
      for (final extension in ['fts', 'fts.part', 'qw']) {
        try { await File('${dir.path}/$packId.$extension').delete(); } catch (_) {}
      }
    }
    _vocab = null;
    notifyListeners();
    ensureFts(only: id).then((_) {}, onError: (_) {});
  }

  bool _localBookImporting = false;

  static const String userPackId = 'user_files';

  /// Turns the user's own text / markdown files into articles of one pack ("My files").
  Future<int> importTextFiles(List<String> paths) async {
    final articles = <LibArticle>[];
    final existing = pack(userPackId);
    if (existing != null) {
      final x = await _index(userPackId);
      for (var i = 0; i < x.titles.length; i++) {
        final a = await read(userPackId, i);
        if (a != null) articles.add(a);
      }
    }
    var added = 0;
    for (final p in paths) {
      try {
        final text = utf8.decode(await File(p).readAsBytes(), allowMalformed: true);
        final name = p.split(Platform.pathSeparator).last.replaceAll(RegExp(r'\.[^.]*$'), '');
        articles.removeWhere((a) => a.title == name);
        articles.add(LibArticle(name, '', parseSections(text)));
        added++;
      } catch (_) {}
    }
    if (added > 0) {
      await writePack(
        PackMeta(id: userPackId, title: 'My files', kind: 'user', date: DateTime.now().toIso8601String().substring(0, 10), source: 'Imported by you', license: 'Your own files'),
        articles,
      );
    }
    return added;
  }

  /// Markdown-style headings (# ...) start a new section; anything else is body text.
  static List<LibSection> parseSections(String text) {
    final out = <LibSection>[];
    var head = '';
    final buf = <String>[];
    void flush() {
      final t = buf.join('\n').trim();
      if (t.isNotEmpty) out.add(LibSection(head, t));
      buf.clear();
    }

    for (final line in text.replaceAll('\r', '').split('\n')) {
      final m = RegExp(r'^\s{0,3}#{1,4}\s+(.*)$').firstMatch(line);
      if (m != null) {
        flush();
        head = m.group(1)!.trim();
      } else {
        buf.add(line);
      }
    }
    flush();
    return out;
  }

  Future<void> remove(String id) async {
    for (final ext in ['idx', 'bin', 'qw', 'fts', 'fts.part']) {
      final f = File('${dir.path}/$id.$ext');
      if (f.existsSync()) await f.delete();
    }
    _idx.remove(id);
    _ftsForget(id);
    _imgIdx.remove(id);
    _vocab = null;
    packs.removeWhere((p) => p.id == id);
    await _saveInstalled();
    notifyListeners();
  }

  // ------------------------------------------------------------ catalog + download

  Future<List<CatalogEntry>> fetchCatalog({String? catalogUrl}) async {
    final url = catalogUrl ?? libraryCatalogUrl;
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await c.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'MedLog');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final base = url.substring(0, url.lastIndexOf('/') + 1);
      String abs(String s) => s.startsWith('http') ? s : '$base$s';
      return [
        for (final e in (j['packs'] as List))
          CatalogEntry(
            PackMeta.fromJson((e as Map).cast<String, dynamic>()),
            abs('${e['imx'] ?? e['idx'] ?? '${e['id']}.idx'}'),
            abs('${e['img'] ?? e['bin'] ?? '${e['id']}.bin'}'),
            '${e['sha256_bin'] ?? ''}',
            '${e['sha256_idx'] ?? ''}',
          ),
      ];
    } finally {
      c.close(force: true);
    }
  }

  /// True when the catalog has a newer date than the installed copy.
  bool hasUpdate(CatalogEntry e) {
    final p = pack(e.meta.id);
    return p != null && e.meta.date.compareTo(p.date) > 0;
  }

  Future<String> _download(String url, File to, void Function(int) onBytes) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await c.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'MedLog');
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final sink = to.openWrite();
      final out = AccumulatorSink<Digest>();
      final hasher = sha256.startChunkedConversion(out);
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          hasher.add(chunk);
          onBytes(chunk.length);
        }
      } finally {
        await sink.close();
      }
      hasher.close();
      return out.events.single.toString();
    } finally {
      c.close(force: true);
    }
  }

  /// Downloads, verifies and installs a pack. [onProgress] gets 0..1.
  Future<void> install(CatalogEntry e, {void Function(double)? onProgress}) async {
    final id = e.meta.id;
    final binPart = File('${dir.path}/$id.bin.part');
    final idxPart = File('${dir.path}/$id.idx.part');
    final total = e.meta.bytes <= 0 ? 1 : e.meta.bytes;
    var got = 0;
    void tick(int n) {
      got += n;
      onProgress?.call((got / total).clamp(0.0, 0.99));
    }

    try {
      final hIdx = await _download(e.idxUrl, idxPart, tick);
      final hBin = await _download(e.binUrl, binPart, tick);
      if (e.sha256Idx.isNotEmpty && e.sha256Idx != hIdx) throw const FormatException('Index checksum mismatch');
      if (e.sha256Bin.isNotEmpty && e.sha256Bin != hBin) throw const FormatException('Pack checksum mismatch');
      // check the index really decodes before replacing a working copy
      _decodeIdx(await idxPart.readAsBytes());
      await binPart.rename('${dir.path}/$id.bin');
      await idxPart.rename('${dir.path}/$id.idx');
    } catch (_) {
      for (final f in [binPart, idxPart]) {
        if (f.existsSync()) await f.delete();
      }
      rethrow;
    }
    _idx.remove(id);
    _ftsForget(id);
    try {
      File('${dir.path}/$id.fts').deleteSync();
    } catch (_) {}
    _imgIdx.remove(id);
    _vocab = null;
    final size = File('${dir.path}/$id.bin').lengthSync() + File('${dir.path}/$id.idx').lengthSync();
    packs.removeWhere((p) => p.id == id);
    packs.add(PackMeta.fromJson({...e.meta.toJson(), 'bytes': size}));
    await _saveInstalled();
    onProgress?.call(1);
    notifyListeners();
    if (e.meta.kind != 'images') ensureFts(only: id).then((_) {}, onError: (_) {});
  }
}

/// Collects the single digest of a chunked hash.
class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];
  @override
  void add(T data) => events.add(data);
  @override
  void close() {}
}

final LibraryStore library = LibraryStore();

String fmtBytes(int b) {
  // wrapped as a left-to-right isolate so "76 MB" never flips inside Arabic text
  String wrap(String x) => '\u2066$x\u2069';
  if (b >= 1024 * 1024) return wrap('${(b / 1024 / 1024).toStringAsFixed(b >= 10 * 1024 * 1024 ? 0 : 1)} MB');
  if (b >= 1024) return wrap('${(b / 1024).round()} KB');
  return wrap('$b B');
}
