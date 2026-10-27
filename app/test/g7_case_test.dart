import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/case_extras.dart';
import 'package:medlog/data.dart';
import 'package:medlog/screens_case_extras.dart';
import 'package:medlog/error_log.dart';

import 'lib2_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('link, follow-up and unlink keep groups consistent', () async {
    await initStoreLight();
    final cs = store.cases.values.toList();
    final a = cs[0], b = cs[1], c = cs[2];
    await linkSamePatient(a, b);
    expect(patientGroupOf(a), isNotNull);
    expect(patientGroupOf(a), patientGroupOf(b));
    expect(samePatient(a).map((x) => x.id), [b.id]);
    a.set('allergies', 'Penicillin');
    a.d['problemList'] = [
      {'id': 'p1', 'text': 'AKI', 'status': 'active'},
      {'id': 'p2', 'text': 'Pneumonia', 'status': 'resolved'},
    ];
    final f = await createFollowUp(a);
    expect(patientGroupOf(f), patientGroupOf(a));
    expect(f.s('followUpOf'), a.id);
    expect(f.s('allergies'), 'Penicillin');
    expect(problemList(f).map((p) => p['text']), ['AKI'], reason: 'only active problems carry over');
    expect(samePatient(a).length, 2);
    // merging two groups
    await linkSamePatient(c, a);
    expect(samePatient(c).length, 3);
    await unlinkPatient(c);
    expect(patientGroupOf(c), isNull);
    expect(samePatient(a).length, 2);
  });

  test('problem import skips duplicates and bullets', () async {
    await initStoreLight();
    final a = store.cases.values.first;
    a.set('problems', '1. Fever\n- Cough\n• Fever\n\n');
    expect(importProblemLines(a), 2);
    expect(importProblemLines(a), 0);
    expect(problemList(a).map((p) => p['text']), ['Fever', 'Cough']);
  });

  test('lab series: sorted, trend, unit', () async {
    await initStoreLight();
    final a = store.cases.values.first;
    a.d['labs'] = [
      {'id': '1', 'test': 'Hb', 'value': 12.0, 'unit': 'g/dL', 'date': '2026-10-02'},
      {'id': '2', 'test': 'Hb', 'value': 9.5, 'unit': 'g/dL', 'date': '2026-10-04'},
      {'id': '3', 'test': 'Hb', 'value': 13.0, 'unit': 'g/dL', 'date': '2026-10-01'},
      {'id': '4', 'test': 'K', 'value': '4,1', 'unit': 'mmol/L', 'date': '2026-10-01'},
      {'id': '5', 'test': 'Na', 'value': 'abc', 'date': '2026-10-01'},
    ];
    final s = labSeries(a);
    expect(s.map((x) => x.test), ['Hb', 'K']);
    expect(s.first.readings.map((r) => r.value), [13.0, 12.0, 9.5]);
    expect(s.first.trend, -1);
    expect(s.last.trend, isNull);
    expect(s.last.latest.value, 4.1);
  });

  test('error log keeps one clean line and masks long numbers', () async {
    await initStoreLight();
    ErrorLog.entries.clear();
    ErrorLog.record('Bad thing for 0791234567\nsecond line with name', StackTrace.fromString('#0 a\n#1 b'));
    expect(ErrorLog.entries.first['message'], contains('######'));
    expect(ErrorLog.entries.first['message']!.contains('second line'), false);
    for (var i = 0; i < 120; i++) {
      ErrorLog.record('e$i', null);
    }
    expect(ErrorLog.entries.length, 100);
  });

  testWidgets('problem + lab sections work in the UI', (tester) async {
    await tester.runAsync(() => initStoreLight());
    final rec = store.cases.values.first;
    var changes = 0;
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    rec.d['problemList'] = [
      {'id': 'p1', 'text': 'Chest pain', 'status': 'active', 'since': '2026-10-01'}
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          ProblemSection(rec: rec, onChanged: () => changes++),
          LabSection(rec: rec, onChanged: () => changes++),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('problem_p1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rec.lst('problemList').first['status'], 'resolved');
    expect(changes, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('add_lab')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Hb'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('lab_value')), '11.2');
    await tester.tap(find.byKey(const ValueKey('lab_save')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(rec.lst('labs').length, 1);
    expect(rec.lst('labs').first['unit'], 'g/dL');
    expect(find.byKey(const ValueKey('lab_Hb')), findsOneWidget);
  });
}
