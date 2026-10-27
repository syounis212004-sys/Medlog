import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lib_text.dart';

/// Full-text ("search inside articles") index of one pack, kept next to the pack as <id>.fts.
///
/// What it is: for every word of every article a 32-bit hash and the list of articles that contain it (delta +
/// varint coded, the lowest bit says "also in the title, a heading or the lead"). Words are hashed, not stored, so
/// the file is small (about 20% of the pack) and a lookup is a binary search with no parsing. Only "rare terms"
/// are indexed: words of 4 letters or more, upper-case abbreviations (STEMI, GCS, SBP, CURB-65 as "curb65") and
/// letter+digit codes; pure numbers and words found in more than about a third of a pack are left out. A false
/// match (two words with one hash) is removed later, when the matching sentence is looked for in the article.
///
/// It is built by [ftsBuildJob] in a background isolate and read by [FtsReader] on the main thread.

const int kFtsMagic = 0x32464C4D; // "MLF2"

int _fnvStep(int h, int c) => ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
const int _fnvBasis = 0x811C9DC5;

/// Lower-case folding used for hashing: ASCII and Latin-1 letters.
int _fold(int c) {
  if (c >= 65 && c <= 90) return c + 32;
  if (c >= 0xC0 && c <= 0xDE && c != 0xD7) return c + 32;
  return c;
}

bool _isWordUnit(int c) =>
    (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || (c >= 0xC0 && c <= 0x24F && c != 0xD7 && c != 0xF7);

bool _isDash(int c) => c == 0x2D || c == 0x2013 || c == 0x2011;

/// Hash of a word as the index stores it (lower-cased).
int ftsHash(String w) {
  var h = _fnvBasis;
  for (var i = 0; i < w.length; i++) {
    h = _fnvStep(h, _fold(w.codeUnitAt(i)));
  }
  return h;
}

/// Calls [emit] for every indexable word of [s] with its hash and its range; [joined] is true for a compound such as
/// "CURB-65" -> "curb65" (emitted in addition to its parts). [query] accepts short lower-case words too.
void scanTokens(String s, void Function(int hash, int st, int en, bool joined) emit, {bool query = false}) {
  final n = s.length;
  var i = 0;
  // the word before a dash, kept for compounds
  var pendActive = false, pendH = 0, pendEnd = 0, pendDigit = false, pendUpper = false, pendLen = 0, pendSt = 0;
  while (i < n) {
    var c = s.codeUnitAt(i);
    if (!_isWordUnit(c)) {
      i++;
      continue;
    }
    final st = i;
    var h = _fnvBasis;
    var hasUpper = false, hasLower = false, hasDigit = false;
    while (i < n) {
      c = s.codeUnitAt(i);
      if (c >= 97 && c <= 122) {
        hasLower = true;
      } else if (c >= 65 && c <= 90) {
        hasUpper = true;
      } else if (c >= 48 && c <= 57) {
        hasDigit = true;
      } else if (!(c >= 0xC0 && c <= 0x24F && c != 0xD7 && c != 0xF7)) {
        break;
      } else if (c < 0xE0) {
        hasUpper = true;
      } else {
        hasLower = true;
      }
      h = _fnvStep(h, _fold(c));
      i++;
    }
    final len = i - st;
    final upperOnly = hasUpper && !hasLower;
    // compound with the word before the dash
    if (pendActive && pendEnd + 1 == st) {
      final ok = pendDigit || hasDigit || (pendUpper && upperOnly && pendLen <= 8 && len <= 8);
      if (ok && pendLen + len <= 24) {
        var j = pendH;
        for (var k = st; k < i; k++) {
          j = _fnvStep(j, _fold(s.codeUnitAt(k)));
        }
        emit(j, pendSt, i, true);
      }
    }
    pendActive = false;
    if (i + 1 < n && _isDash(s.codeUnitAt(i)) && _isWordUnit(s.codeUnitAt(i + 1))) {
      pendActive = true;
      pendH = h;
      pendEnd = i;
      pendDigit = hasDigit;
      pendUpper = upperOnly;
      pendLen = len;
      pendSt = st;
    }
    if (len < 2 || len > 24) continue;
    if (!hasUpper && !hasLower) continue; // digits only
    if (hasDigit && len > 12) continue; // identifiers
    if (!query && len <= 3 && !hasDigit && !upperOnly) continue; // short words count only as abbreviations
    emit(h, st, i, false);
  }
}

// ------------------------------------------------------------------------------------------ building

class _U32Buf {
  Uint32List _a = Uint32List(1 << 16);
  int n = 0;
  void add(int v) {
    if (n == _a.length) {
      final b = Uint32List(_a.length * 2);
      b.setRange(0, n, _a);
      _a = b;
    }
    _a[n++] = v;
  }

  int operator [](int i) => _a[i];
}

/// Fingerprint of a pack file pair: when it changes the index is rebuilt.
int ftsSig(String date, int count, int binBytes) => ftsHash('$date|$count|$binBytes');

/// Isolate job: builds <id>.fts from <id>.idx / <id>.bin. [args] = {dir, id, sig}. Returns {bytes, tokens, ms}.
Map<String, int> ftsBuildJob(Map<String, Object?> args) {
  final sw = Stopwatch()..start();
  final dir = args['dir'] as String, id = args['id'] as String, sig = args['sig'] as int;
  final idx = jsonDecode(utf8.decode(gzip.decode(File('$dir/$id.idx').readAsBytesSync()))) as Map<String, dynamic>;
  final offs = (idx['o'] as List).cast<int>(), lens = (idx['n'] as List).cast<int>();
  final nDocs = offs.length;
  final bin = File('$dir/$id.bin').readAsBytesSync();
  final vocab = <int, int>{}; // hash -> token id
  final tokHash = <int>[];
  final stamp = <int>[]; // token id -> last document + 1 that was added
  final pt = _U32Buf(), pd = _U32Buf();

  for (var d = 0; d < nDocs; d++) {
    Map<String, dynamic> a;
    try {
      a = jsonDecode(utf8.decode(gzip.decode(Uint8List.sublistView(bin, offs[d], offs[d] + lens[d])))) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    void add(String text, int flag) {
      scanTokens(text, (h, st, en, joined) {
        var tid = vocab[h];
        if (tid == null) {
          tid = tokHash.length;
          vocab[h] = tid;
          tokHash.add(h);
          stamp.add(0);
        }
        if (stamp[tid] == d + 1) return;
        stamp[tid] = d + 1;
        pt.add(tid);
        pd.add((d << 1) | flag);
      });
    }

    add('${a['t'] ?? ''}', 1);
    final secs = (a['s'] as List?) ?? const [];
    for (var k = 0; k < secs.length; k++) {
      final s = secs[k] as Map;
      final flag = k == 0 ? 1 : 0;
      add('${s['h'] ?? ''}', 1);
      add('${s['t'] ?? ''}', flag);
      for (final tb in (s['tb'] as List?) ?? const []) {
        if (tb is! Map) continue;
        add('${tb['c'] ?? ''}', 0);
        for (final r in (tb['r'] as List?) ?? const []) {
          if (r is List) {
            for (final c in r) {
              add('$c', 0);
            }
          }
        }
      }
    }
  }

  final nTid = tokHash.length;
  final df = Uint32List(nTid);
  for (var i = 0; i < pt.n; i++) {
    df[pt[i]]++;
  }
  final cap = nDocs * 3 ~/ 10 > 200 ? nDocs * 3 ~/ 10 : 200;
  final keep = <int>[], stops = <int>[];
  for (var t = 0; t < nTid; t++) {
    (df[t] > cap ? stops : keep).add(t);
  }
  keep.sort((x, y) => tokHash[x].compareTo(tokHash[y]));
  stops.sort((x, y) => tokHash[x].compareTo(tokHash[y]));
  // slots per token in hash order
  final start = Uint32List(nTid + 1);
  final rank = Int32List(nTid)..fillRange(0, nTid, -1);
  var total = 0;
  for (var r = 0; r < keep.length; r++) {
    rank[keep[r]] = r;
    start[r] = total;
    total += df[keep[r]];
  }
  start[keep.length] = total;
  final fill = Uint32List(keep.length);
  final slots = Uint32List(total);
  for (var i = 0; i < pt.n; i++) {
    final r = rank[pt[i]];
    if (r < 0) continue;
    slots[start[r] + fill[r]++] = pd[i];
  }
  // postings blob
  final post = BytesBuilder(copy: false);
  final offTab = Uint32List(keep.length + 1);
  for (var r = 0; r < keep.length; r++) {
    offTab[r] = post.length;
    var prev = 0;
    for (var k = start[r]; k < start[r + 1]; k++) {
      final v = slots[k];
      final doc = v >> 1;
      var x = ((doc - prev) << 1) | (v & 1);
      prev = doc;
      while (x >= 0x80) {
        post.addByte((x & 0x7F) | 0x80);
        x >>= 7;
      }
      post.addByte(x);
    }
  }
  offTab[keep.length] = post.length;
  final postBytes = post.takeBytes();

  final nTok = keep.length, nStop = stops.length;
  final hOff = 40, oOff = hOff + nTok * 4, sOff = oOff + (nTok + 1) * 4, pOff = sOff + nStop * 4, end = pOff + postBytes.length;
  final out = Uint8List(end);
  final bd = ByteData.view(out.buffer);
  bd.setUint32(0, kFtsMagic, Endian.little);
  bd.setUint32(4, sig, Endian.little);
  bd.setUint32(8, nDocs, Endian.little);
  bd.setUint32(12, nTok, Endian.little);
  bd.setUint32(16, nStop, Endian.little);
  bd.setUint32(20, hOff, Endian.little);
  bd.setUint32(24, oOff, Endian.little);
  bd.setUint32(28, sOff, Endian.little);
  bd.setUint32(32, pOff, Endian.little);
  bd.setUint32(36, end, Endian.little);
  for (var r = 0; r < nTok; r++) {
    bd.setUint32(hOff + r * 4, tokHash[keep[r]], Endian.little);
  }
  for (var r = 0; r <= nTok; r++) {
    bd.setUint32(oOff + r * 4, offTab[r], Endian.little);
  }
  for (var r = 0; r < nStop; r++) {
    bd.setUint32(sOff + r * 4, tokHash[stops[r]], Endian.little);
  }
  out.setRange(pOff, end, postBytes);
  final tmpFile = File('$dir/$id.fts.part');
  tmpFile.writeAsBytesSync(out, flush: true);
  tmpFile.renameSync('$dir/$id.fts');
  return {'bytes': end, 'tokens': nTok, 'stops': nStop, 'ms': sw.elapsedMilliseconds};
}

// ------------------------------------------------------------------------------------------ reading

/// One query word: the hashes it can have (the word, simple plurals, a compound), and what to use when the
/// compound is not in the index (its parts).
class FtsTerm {
  final List<int> alts;
  final List<FtsTerm> fallback;
  final String text;
  const FtsTerm(this.alts, this.text, [this.fallback = const []]);
}

/// Words of a query as index terms. Numbers alone are not indexed, so they are dropped.
List<FtsTerm> ftsParseQuery(String q) {
  final raw = <({int h, int st, int en, bool joined})>[];
  scanTokens(q, (h, st, en, joined) => raw.add((h: h, st: st, en: en, joined: joined)), query: true);
  List<int> variants(String w) {
    final out = <int>[ftsHash(w)];
    if (w.length >= 4) {
      out.add(ftsHash('${w}s'));
      out.add(ftsHash('${w}es'));
      if (w.endsWith('s')) out.add(ftsHash(w.substring(0, w.length - 1)));
      if (w.endsWith('es')) out.add(ftsHash(w.substring(0, w.length - 2)));
      if (w.endsWith('ies')) out.add(ftsHash('${w.substring(0, w.length - 3)}y'));
    }
    return out;
  }

  final terms = <FtsTerm>[];
  final used = <int>{};
  for (var i = 0; i < raw.length; i++) {
    final r = raw[i];
    if (!r.joined) continue;
    final parts = <FtsTerm>[];
    for (var j = 0; j < raw.length; j++) {
      final p = raw[j];
      if (!p.joined && p.st >= r.st && p.en <= r.en) {
        used.add(j);
        final w = q.substring(p.st, p.en).toLowerCase();
        parts.add(FtsTerm(variants(w), w));
      }
    }
    terms.add(FtsTerm([r.h], q.substring(r.st, r.en).toLowerCase(), parts));
    used.add(i);
  }
  for (var i = 0; i < raw.length; i++) {
    if (used.contains(i)) continue;
    final w = q.substring(raw[i].st, raw[i].en).toLowerCase();
    terms.add(FtsTerm(variants(w), w));
  }
  return terms;
}

class FtsCand {
  final int doc;
  final int score;
  const FtsCand(this.doc, this.score);
}

class FtsReader {
  final Uint8List b;
  final ByteData d;
  late final int sig, nDocs, nTok, nStop, hOff, oOff, sOff, pOff;
  FtsReader._(this.b) : d = ByteData.view(b.buffer, b.offsetInBytes, b.length) {
    sig = d.getUint32(4, Endian.little);
    nDocs = d.getUint32(8, Endian.little);
    nTok = d.getUint32(12, Endian.little);
    nStop = d.getUint32(16, Endian.little);
    hOff = d.getUint32(20, Endian.little);
    oOff = d.getUint32(24, Endian.little);
    sOff = d.getUint32(28, Endian.little);
    pOff = d.getUint32(32, Endian.little);
  }

  /// The reader of an index file, or null when it is missing, damaged or built for another version of the pack.
  static FtsReader? open(Uint8List bytes, int expectSig) {
    if (bytes.length < 40) return null;
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    if (bd.getUint32(0, Endian.little) != kFtsMagic || bd.getUint32(36, Endian.little) != bytes.length) return null;
    if (expectSig != 0 && bd.getUint32(4, Endian.little) != expectSig) return null;
    return FtsReader._(bytes);
  }

  int _find(int base, int count, int h) {
    var lo = 0, hi = count - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = d.getUint32(base + mid * 4, Endian.little);
      if (v == h) return mid;
      if (v < h) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  bool isStop(int h) => _find(sOff, nStop, h) >= 0;
  bool has(int h) => _find(hOff, nTok, h) >= 0;

  /// Document -> flag (1 = in the title, a heading or the lead) of every article that has the word, or null.
  Map<int, int>? docsOf(int h) {
    final r = _find(hOff, nTok, h);
    if (r < 0) return null;
    var p = pOff + d.getUint32(oOff + r * 4, Endian.little);
    final end = pOff + d.getUint32(oOff + (r + 1) * 4, Endian.little);
    final out = <int, int>{};
    var doc = 0;
    while (p < end) {
      var x = 0, shift = 0;
      while (true) {
        final c = b[p++];
        x |= (c & 0x7F) << shift;
        if (c < 0x80) break;
        shift += 7;
      }
      doc += x >> 1;
      out[doc] = x & 1;
    }
    return out;
  }

  /// true when every non-stop word of [terms] is known and at least one of them is indexed here
  List<FtsCand> search(List<FtsTerm> terms, {int max = 400}) {
    final lists = <Map<int, int>>[];
    var ok = true;
    void need(FtsTerm t) {
      final u = <int, int>{};
      var found = false, stop = false;
      for (final h in t.alts) {
        if (isStop(h)) stop = true;
        final m = docsOf(h);
        if (m == null) continue;
        found = true;
        m.forEach((k, v) => u[k] = (u[k] ?? 0) | v);
      }
      if (found) {
        lists.add(u);
      } else if (t.fallback.isNotEmpty) {
        t.fallback.forEach(need);
      } else if (!stop) {
        ok = false;
      }
    }

    for (final t in terms) {
      need(t);
    }
    if (!ok || lists.isEmpty) return const [];
    lists.sort((a, b) => a.length.compareTo(b.length));
    final out = <FtsCand>[];
    for (final e in lists.first.entries) {
      var s = e.value == 1 ? 14 : 8;
      var all = true;
      for (var k = 1; k < lists.length; k++) {
        final f = lists[k][e.key];
        if (f == null) {
          all = false;
          break;
        }
        s += f == 1 ? 14 : 8;
      }
      if (all) out.add(FtsCand(e.key, s));
    }
    out.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.doc.compareTo(b.doc);
    });
    return out.length > max ? out.sublist(0, max) : out;
  }
}

// ------------------------------------------------------------------------------------------ snippets

/// What the snippet isolate returns for one article.
class FtsSnippet {
  final String text;
  final String heading;
  final List<int> marks; // start, end, start, end ...
  const FtsSnippet(this.text, this.heading, this.marks);
}

/// Isolate job: for each requested article (dir/id/offset/length) the sentence that holds the most query words, with the
/// ranges to highlight. [args] = {dir, jobs: [[id, offset, length]...], terms: [[hash...]...]}. A null entry = no sentence
/// has the words (a false match of the index), so the hit is dropped.
List<Map<String, Object?>?> ftsSnippetJob(Map<String, Object?> args) {
  final dir = args['dir'] as String;
  final jobs = (args['jobs'] as List).cast<List>();
  final terms = [for (final t in (args['terms'] as List)) (t as List).cast<int>()];
  final fallbacks = [for (final t in (args['fallbacks'] as List)) [for (final f in (t as List)) (f as List).cast<int>()]];
  final out = <Map<String, Object?>?>[];
  final files = <String, RandomAccessFile>{};
  try {
    for (final j in jobs) {
      final id = j[0] as String;
      final raf = files[id] ??= File('$dir/$id.bin').openSync();
      try {
        raf.setPositionSync(j[1] as int);
        final a = jsonDecode(utf8.decode(gzip.decode(raf.readSync(j[2] as int)))) as Map<String, dynamic>;
        out.add(_bestSentence(a, terms, fallbacks));
      } catch (_) {
        out.add(null);
      }
    }
  } finally {
    for (final f in files.values) {
      f.closeSync();
    }
  }
  return out;
}

Map<String, Object?>? _bestSentence(Map<String, dynamic> a, List<List<int>> terms, List<List<List<int>>> fallbacks) {
  if (terms.isEmpty) return null;
  String bestText = '', bestHead = '';
  var bestScore = -1;
  var bestMarks = <int>[];
  final secs = (a['s'] as List?) ?? const [];
  for (var k = 0; k < secs.length; k++) {
    final s = secs[k] as Map;
    final head = '${s['h'] ?? ''}';
    if (isGalleryHeading(head)) continue;
    final units = <String>[];
    for (final line in '${s['t'] ?? ''}'.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('•') || t.startsWith('▸') || t.startsWith('–')) {
        units.add(t.substring(1).trim());
      } else {
        units.addAll(sentences(t));
      }
    }
    for (final u in units) {
      if (u.length < 5 || u.length > 700 || isCaptionLike(u)) continue;
      final seen = <int, List<int>>{};
      scanTokens(u, (h, st, en, joined) => (seen[h] ??= <int>[]).addAll([st, en]), query: true);
      var matched = 0;
      final marks = <int>[];
      for (var t = 0; t < terms.length; t++) {
        var hit = false;
        for (final h in terms[t]) {
          final r = seen[h];
          if (r != null) {
            hit = true;
            marks.addAll(r);
          }
        }
        if (!hit) {
          // a compound that is not indexed whole: all its parts must be there
          final fb = fallbacks[t];
          if (fb.isNotEmpty) {
            var all = true;
            final m2 = <int>[];
            for (final part in fb) {
              var ph = false;
              for (final h in part) {
                final r = seen[h];
                if (r != null) {
                  ph = true;
                  m2.addAll(r);
                }
              }
              if (!ph) all = false;
            }
            if (all) {
              hit = true;
              marks.addAll(m2);
            }
          }
        }
        if (hit) matched++;
      }
      if (matched == 0) continue;
      // all the words in one unit beats more words spread out; a very short or very long unit is a poor snippet
      var score = matched * 100 - (u.length > 260 ? 20 : 0) - (u.length < 25 ? 15 : 0) - u.length ~/ 40;
      if (matched == terms.length) score += 60;
      if (score > bestScore) {
        bestScore = score;
        bestText = u;
        bestHead = head;
        bestMarks = marks;
      }
    }
  }
  if (bestScore < 0) return null;
  // merge and order the highlight ranges
  final pairs = <List<int>>[for (var i = 0; i + 1 < bestMarks.length; i += 2) [bestMarks[i], bestMarks[i + 1]]]..sort((x, y) => x[0].compareTo(y[0]));
  final flat = <int>[];
  for (final p in pairs) {
    if (flat.isNotEmpty && p[0] < flat.last) {
      if (p[1] > flat.last) flat[flat.length - 1] = p[1];
    } else {
      flat.addAll(p);
    }
  }
  return {'s': bestText, 'h': bestHead, 'm': flat};
}
