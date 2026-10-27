import 'data.dart';

/// Reasoning insights computed from what the user recorded: first diagnosis,
/// confidence, and whether it turned out right. Shown as awareness, never as a grade.

/// 0 none, 1 low, 2 medium, 3 high
int confLevel(String percent) {
  final v = int.tryParse(percent.trim());
  if (v == null) return 0;
  if (v < 45) return 1;
  if (v < 75) return 2;
  return 3;
}

class CalibRow {
  final int level;
  int n = 0;
  int right = 0;
  CalibRow(this.level);
  double get rate => n == 0 ? 0 : right / n;
}

class Calibration {
  final List<CalibRow> rows = [CalibRow(1), CalibRow(2), CalibRow(3)];
  int total = 0;

  /// 'overconfident' | 'underconfident' | 'balanced' | 'few' (not enough data)
  String get verdict {
    if (total < 6) return 'few';
    final hi = rows[2], lo = rows[0];
    if (hi.n >= 3 && hi.rate < 0.6) return 'overconfident';
    if (lo.n >= 3 && lo.rate > 0.75) return 'underconfident';
    return 'balanced';
  }
}

Calibration calibration() {
  final c = Calibration();
  void add(int level, bool right) {
    if (level < 1 || level > 3) return;
    final row = c.rows[level - 1];
    row.n++;
    if (right) row.right++;
    c.total++;
  }

  for (final k in store.cases.values) {
    final r = k.s('initialRight');
    if (r == 'Right') add(confLevel(k.s('confInitial')), true);
    if (r == 'Wrong') add(confLevel(k.s('confInitial')), false);
  }
  for (final r in store.listOf('replays')) {
    final conf = (r['conf'] is List && (r['conf'] as List).isNotEmpty) ? (r['conf'] as List).first.toString() : '';
    final g = (r['grade'] ?? '').toString();
    if (g == 'Matched') add(confLevel(conf), true);
    if (g == 'Missed') add(confLevel(conf), false);
  }
  return c;
}

class JournalEntry {
  final String date;
  final String code;
  final String caseId;
  final String specialty;
  final String first; // first diagnosis / thinking
  final String conf;
  final String why;
  final String outcome; // Right / Partly / Wrong / ''
  final String changed;
  final bool fromReplay;
  const JournalEntry(this.date, this.code, this.caseId, this.specialty, this.first, this.conf, this.why, this.outcome,
      this.changed, this.fromReplay);
}

List<JournalEntry> journalEntries() {
  final out = <JournalEntry>[];
  for (final c in store.cases.values) {
    if (c.s('initialDx').trim().isEmpty) continue;
    out.add(JournalEntry(c.s('date'), c.s('code'), c.id, c.s('specialty'), c.s('initialDx'), c.s('confInitial'),
        c.s('initialWhy'), c.s('initialRight'), c.s('whatChanged'), false));
  }
  for (final r in store.listOf('replays')) {
    final answers = (r['answers'] is List) ? (r['answers'] as List).map((e) => e.toString()).toList() : <String>[];
    final first = answers.isEmpty ? '' : answers.first;
    if (first.trim().isEmpty) continue;
    final conf = (r['conf'] is List && (r['conf'] as List).isNotEmpty) ? (r['conf'] as List).first.toString() : '';
    final g = (r['grade'] ?? '').toString();
    out.add(JournalEntry((r['date'] ?? '').toString(), (r['code'] ?? '').toString(), (r['caseId'] ?? '').toString(),
        (r['specialty'] ?? '').toString(), first, conf, '', g == 'Matched' ? 'Right' : (g == 'Missed' ? 'Wrong' : (g == 'Partly' ? 'Partly' : '')),
        '', true));
  }
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}

/// Share of right first diagnoses per specialty (only specialties with 3+ judged entries).
Map<String, double> accuracyBySpecialty() {
  final n = <String, int>{}, r = <String, int>{};
  for (final e in journalEntries()) {
    if (e.outcome != 'Right' && e.outcome != 'Wrong') continue;
    n[e.specialty] = (n[e.specialty] ?? 0) + 1;
    if (e.outcome == 'Right') r[e.specialty] = (r[e.specialty] ?? 0) + 1;
  }
  final out = <String, double>{};
  n.forEach((k, v) {
    if (v >= 3 && k.isNotEmpty) out[k] = (r[k] ?? 0) / v;
  });
  return out;
}
