import 'data.dart';
import 'i18n.dart';

/// Spaced review of what YOU wrote: learning points, mistakes, answered
/// questions, notes, pearls and your own cases. Nothing here is invented: the
/// engine only decides what to show you again, and when.

/// Days until the next review for each box (Leitner-style ladder).
const List<int> kLadder = [1, 3, 7, 14, 30, 60];

enum ReviewKind { caseRecall, learned, mistake, question, note, pearl, image, library }

class ReviewItem {
  final String key;
  final ReviewKind kind;
  final String refId;
  final String source; // short label shown on the card
  final String front;
  final String prompt;
  final String back;
  final String? imageFile; // image review: the picture is the question
  const ReviewItem(this.key, this.kind, this.refId, this.source, this.front, this.prompt, this.back,
      {this.imageFile});
}

String _clip(String s, int n) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length <= n ? t : '${t.substring(0, n).trimRight()}…';
}

String _lines(List<String> l) => l.where((e) => e.trim().isNotEmpty).join('\n');

List<ReviewItem> buildReviewItems() {
  final out = <ReviewItem>[];
  for (final c in store.cases.values) {
    final dx = c.s('finalDx').trim().isNotEmpty ? c.s('finalDx') : c.s('workingDx');
    final who = [c.s('ageGroup'), c.s('sex'), c.s('setting')].where((e) => e.isNotEmpty).map(tr).join(' • ');
    final vit = [
      ['BP', 'v_bp'], ['HR', 'v_hr'], ['Temp', 'v_temp'], ['RR', 'v_rr'], ['SpO2', 'v_spo2'], ['RBS', 'v_rbs'],
    ].where((e) => c.s(e[1]).trim().isNotEmpty).map((e) => '${e[0]} ${c.s(e[1])}').join(', ');
    final inv = c.lst('inv').where((i) => (i['result'] ?? '').toString().isNotEmpty).map((i) => '${i['name']}: ${i['result']}').join('; ');
    if (dx.trim().isNotEmpty && (c.s('cc').trim().isNotEmpty || c.s('hpi').trim().isNotEmpty) && c.s('status') != 'Draft') {
      out.add(ReviewItem(
        'c:${c.id}:recall', ReviewKind.caseRecall, c.id, c.s('code'),
        _lines([who, c.s('cc'), _clip(c.s('hpi'), 360), vit.isEmpty ? '' : '${tr('Vital signs')}: $vit',
          _clip('${c.s('examGeneral')} ${c.s('examSystemic')} ${c.s('examFocused')}', 260),
          inv.isEmpty ? '' : '${tr('Result')}: ${_clip(inv, 220)}']),
        tr('What is your diagnosis, and what supports it?'),
        _lines([dx, c.s('ddx').trim().isEmpty ? '' : 'DDx: ${c.s('ddx')}', _clip(c.s('reasoning'), 300),
          c.s('learned').trim().isEmpty ? '' : '${tr('What I learned')}: ${c.s('learned')}']),
      ));
    }
    // my own images with my own reading: look at the picture first, then compare
    for (final img in c.lst('images')) {
      final interp = (img['interpretation'] ?? '').toString().trim();
      final f = (img['file'] ?? '').toString();
      if (interp.isEmpty || f.isEmpty) continue;
      out.add(ReviewItem(
        'i:${c.id}:$f', ReviewKind.image, c.id, c.s('code'),
        [(img['type'] ?? '').toString(), (img['view'] ?? '').toString()].where((e) => e.isNotEmpty).map(tr).join(' • '),
        tr('Describe what you see, then check your earlier reading'),
        _lines([interp, (img['caption'] ?? '').toString(), dx.isEmpty ? '' : '${tr('Final diagnosis')}: $dx']),
        imageFile: f,
      ));
    }
    if (c.s('learned').trim().isNotEmpty) {
      out.add(ReviewItem('c:${c.id}:learned', ReviewKind.learned, c.id, c.s('code'),
          '${c.title}\n${_clip(c.s('cc'), 120)}', tr('What did this case teach you?'), c.s('learned')));
    }
    if (c.s('mistakes').trim().isNotEmpty) {
      out.add(ReviewItem('c:${c.id}:mistake', ReviewKind.mistake, c.id, c.s('code'),
          '${c.title}\n${_clip(c.s('cc'), 120)}', tr('What mistake or near-miss did you note here, and how do you avoid it?'),
          _lines([c.s('mistakes'), c.s('learned')])));
    }
  }
  for (final q in store.inbox) {
    final a = (q['answer'] ?? '').toString().trim();
    if (a.isEmpty) continue;
    out.add(ReviewItem('q:${q['id']}', ReviewKind.question, '${q['id']}', tr('Question'), '${q['question'] ?? ''}',
        tr('Can you answer it from memory?'), _lines([a, (q['reference'] ?? '').toString().isEmpty ? '' : '${tr('Reference (book, guideline, link)')}: ${q['reference']}'])));
  }
  for (final n in store.notes) {
    final b = (n['body'] ?? '').toString().trim();
    if (b.isEmpty) continue;
    out.add(ReviewItem('n:${n['id']}', ReviewKind.note, '${n['id']}', tr('Note'),
        (n['title'] ?? '').toString().isEmpty ? '(untitled)' : '${n['title']}', tr('What do you remember about this?'), b));
  }
  for (final p in store.listOf('pearls')) {
    final t = (p['text'] ?? '').toString().trim();
    if (t.isEmpty) continue;
    final topic = (p['topic'] ?? '').toString();
    out.add(ReviewItem('p:${p['id']}', ReviewKind.pearl, '${p['id']}', tr('Pearl'),
        topic.isEmpty ? '${tr('Pearl')} • ${prettyDate('${p['date'] ?? ''}')}' : topic, tr('What was the pearl?'), t));
  }
  for (final c in store.listOf('libcards')) {
    final front = (c['front'] ?? '').toString().trim();
    if (front.isEmpty) continue;
    out.add(ReviewItem('l:${c['id']}', ReviewKind.library, '${c['id']}', (c['source'] ?? tr('Library')).toString(), front,
        tr('Can you answer it from memory?'), (c['back'] ?? '').toString()));
  }
  return out;
}

class ReviewEngine {
  static J? stateOf(String key) {
    for (final e in store.listOf('review')) {
      if (e['id'] == key) return e;
    }
    return null;
  }

  static bool isDue(ReviewItem it) {
    final s = stateOf(it.key);
    if (s == null) return true; // new
    return (s['due'] ?? '').toString().compareTo(todayStr()) <= 0;
  }

  /// Items to review now: due ones first (oldest due first), then a few new ones.
  static List<ReviewItem> due({int max = 12, int maxNew = 5, String? topic, Set<ReviewKind>? kinds}) {
    var items = buildReviewItems();
    if (kinds != null) items = items.where((i) => kinds.contains(i.kind)).toList();
    if (topic != null && topic.trim().isNotEmpty) {
      final t = topic.toLowerCase();
      items = items.where((i) => '${i.front} ${i.back}'.toLowerCase().contains(t)).toList();
    }
    final dueOld = <ReviewItem>[];
    final fresh = <ReviewItem>[];
    for (final it in items) {
      final s = stateOf(it.key);
      if (s == null) {
        fresh.add(it);
      } else if ((s['due'] ?? '').toString().compareTo(todayStr()) <= 0) {
        dueOld.add(it);
      }
    }
    dueOld.sort((a, b) => (stateOf(a.key)!['due'] as String).compareTo(stateOf(b.key)!['due'] as String));
    final res = <ReviewItem>[...dueOld.take(max), ...fresh.take(maxNew)];
    return res.take(max).toList();
  }

  static int dueCount() {
    var n = 0, fresh = 0;
    for (final it in buildReviewItems()) {
      final s = stateOf(it.key);
      if (s == null) {
        fresh++;
      } else if ((s['due'] ?? '').toString().compareTo(todayStr()) <= 0) {
        n++;
      }
    }
    return n + (fresh > 5 ? 5 : fresh);
  }

  /// 0 = again, 1 = hard, 2 = good, 3 = easy
  static int nextBox(int box, int grade) {
    switch (grade) {
      case 0:
        return 0;
      case 1:
        return box;
      case 2:
        return (box + 1).clamp(0, kLadder.length - 1);
      default:
        return (box + 2).clamp(0, kLadder.length - 1);
    }
  }

  static int daysFor(ReviewItem it, int grade) {
    final s = stateOf(it.key);
    final box = s == null ? 0 : (s['box'] as int? ?? 0);
    if (grade == 0) return 0; // again: seen again today
    return kLadder[nextBox(box, grade)];
  }

  static Future<void> grade(ReviewItem it, int grade) async {
    final s = stateOf(it.key) ?? <String, dynamic>{'id': it.key, 'box': 0, 'reps': 0, 'lapses': 0};
    final box = nextBox(s['box'] as int? ?? 0, grade);
    s['box'] = box;
    s['reps'] = (s['reps'] as int? ?? 0) + 1;
    if (grade == 0) s['lapses'] = (s['lapses'] as int? ?? 0) + 1;
    final days = grade == 0 ? 0 : kLadder[box];
    s['due'] = fmtDate(DateTime.now().add(Duration(days: days)));
    s['last'] = todayStr();
    s['title'] = it.front.split('\n').first;
    await store.upsertExtra('review', s);
  }

  static bool hasImages() => buildReviewItems().any((i) => i.kind == ReviewKind.image);

  static Map<String, int> stats() {
    final items = buildReviewItems();
    var learned = 0, started = 0;
    for (final it in items) {
      final s = stateOf(it.key);
      if (s != null) {
        started++;
        if ((s['box'] as int? ?? 0) >= 3) learned++;
      }
    }
    return {'items': items.length, 'started': started, 'learned': learned, 'due': dueCount()};
  }
}
