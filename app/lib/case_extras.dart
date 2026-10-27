import 'data.dart';

/// Logic for three case add-ons: the same-patient link (no identifiers: only a shared random group id),
/// the structured problem list, and numeric lab readings with trends.

const List<String> kOutcomes = ['Improved', 'Stable', 'Worse', 'Referred', 'Discharged', 'Died', 'Lost to follow-up'];

String? patientGroupOf(CaseRec c) {
  final g = c.s('pgroup');
  return g.isEmpty ? null : g;
}

/// Other cases of the same patient, oldest first.
List<CaseRec> samePatient(CaseRec c) {
  final g = patientGroupOf(c);
  if (g == null) return const [];
  final l = store.cases.values.where((x) => x.id != c.id && x.s('pgroup') == g).toList();
  l.sort((a, b) => a.s('date').compareTo(b.s('date')));
  return l;
}

Future<void> linkSamePatient(CaseRec a, CaseRec b) async {
  final ga = patientGroupOf(a), gb = patientGroupOf(b);
  final gid = ga ?? gb ?? newId('pg');
  final changed = <CaseRec>{a, b};
  for (final old in {ga, gb}) {
    if (old != null && old != gid) {
      changed.addAll(store.cases.values.where((x) => x.s('pgroup') == old));
    }
  }
  for (final c in changed) {
    c.set('pgroup', gid);
    await store.saveCase(c, notify: false);
  }
  store.notifyListeners();
}

Future<void> unlinkPatient(CaseRec c) async {
  final g = patientGroupOf(c);
  c.d.remove('pgroup');
  c.d.remove('followUpOf');
  await store.saveCase(c, notify: false);
  if (g != null) {
    final rest = store.cases.values.where((x) => x.s('pgroup') == g).toList();
    if (rest.length == 1) {
      rest.first.d.remove('pgroup');
      await store.saveCase(rest.first, notify: false);
    }
  }
  store.notifyListeners();
}

/// A new draft case for the same patient: background history is carried over, nothing identifying is copied.
Future<CaseRec> createFollowUp(CaseRec from) async {
  final gid = patientGroupOf(from) ?? newId('pg');
  from.set('pgroup', gid);
  await store.saveCase(from, notify: false);
  final n = store.newCase();
  n.set('specialty', from.s('specialty'));
  n.d['code'] = store.nextCode(prefixFor(from.s('specialty')));
  for (final k in ['ageGroup', 'sex', 'allergies', 'pmh', 'psh', 'drugs', 'family', 'social']) {
    if (from.s(k).isNotEmpty) n.set(k, from.s(k));
  }
  n.set('pgroup', gid);
  n.set('followUpOf', from.id);
  n.set('cc', 'Follow-up');
  final carried = [for (final p in problemList(from)) if (p['status'] != 'resolved') Map<String, dynamic>.from(p)..['id'] = newId('pb')];
  if (carried.isNotEmpty) n.d['problemList'] = carried;
  await store.saveCase(n, notify: false);
  store.notifyListeners();
  return n;
}

// ---------------------------------------------------------------- problem list

List<J> problemList(CaseRec c) => c.lst('problemList');

/// Active problems first, then resolved; each group keeps the order they were added.
List<J> problemsSorted(CaseRec c) {
  final l = problemList(c);
  return [...l.where((p) => p['status'] != 'resolved'), ...l.where((p) => p['status'] == 'resolved')];
}

/// Turns the free-text problem list (one per line) into structured items, skipping ones already there.
int importProblemLines(CaseRec c) {
  final have = problemList(c).map((p) => (p['text'] ?? '').toString().trim().toLowerCase()).toSet();
  var n = 0;
  for (final raw in c.s('problems').split('\n')) {
    final t = raw.replaceFirst(RegExp(r'^\s*(?:[-•*]|\d+[.)])\s*'), '').trim();
    if (t.isEmpty || have.contains(t.toLowerCase())) continue;
    problemList(c).add({'id': newId('pb'), 'text': t, 'status': 'active', 'since': c.s('date')});
    have.add(t.toLowerCase());
    n++;
  }
  return n;
}

// ---------------------------------------------------------------- lab readings

class LabTest {
  final String name;
  final String unit;
  const LabTest(this.name, this.unit);
}

/// Names and the unit most people use; the unit is editable because labs differ by country.
const List<LabTest> kLabCatalog = [
  LabTest('Hb', 'g/dL'),
  LabTest('WBC', '×10⁹/L'),
  LabTest('Platelets', '×10⁹/L'),
  LabTest('Na', 'mmol/L'),
  LabTest('K', 'mmol/L'),
  LabTest('Creatinine', 'mg/dL'),
  LabTest('Urea', 'mmol/L'),
  LabTest('Glucose', 'mg/dL'),
  LabTest('CRP', 'mg/L'),
  LabTest('Bilirubin', 'mg/dL'),
  LabTest('ALT', 'U/L'),
  LabTest('INR', ''),
  LabTest('Troponin', 'ng/L'),
  LabTest('Lactate', 'mmol/L'),
  LabTest('pH', ''),
  LabTest('HbA1c', '%'),
];

class LabReading {
  final String id;
  final String date;
  final double value;
  const LabReading(this.id, this.date, this.value);
}

class LabSeries {
  final String test;
  final String unit;
  final List<LabReading> readings; // oldest first
  const LabSeries(this.test, this.unit, this.readings);

  LabReading get latest => readings.last;
  LabReading? get previous => readings.length > 1 ? readings[readings.length - 2] : null;

  /// -1 falling, 0 steady (within 2%), 1 rising; null with a single reading.
  int? get trend {
    final p = previous;
    if (p == null) return null;
    final d = latest.value - p.value;
    final base = p.value.abs() < 1e-9 ? 1.0 : p.value.abs();
    if (d.abs() / base < 0.02) return 0;
    return d > 0 ? 1 : -1;
  }
}

List<LabSeries> labSeries(CaseRec c) {
  final by = <String, List<LabReading>>{};
  final units = <String, String>{};
  for (final r in c.lst('labs')) {
    final t = (r['test'] ?? '').toString().trim();
    final v = r['value'] is num ? (r['value'] as num).toDouble() : double.tryParse((r['value'] ?? '').toString().replaceAll(',', '.'));
    if (t.isEmpty || v == null) continue;
    by.putIfAbsent(t, () => []).add(LabReading((r['id'] ?? '').toString(), (r['date'] ?? '').toString(), v));
    units[t] = (r['unit'] ?? units[t] ?? '').toString();
  }
  final out = [
    for (final e in by.entries) LabSeries(e.key, units[e.key] ?? '', e.value..sort((a, b) => a.date.compareTo(b.date))),
  ];
  out.sort((a, b) => a.test.compareTo(b.test));
  return out;
}
