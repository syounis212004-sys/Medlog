import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/choices_engine.dart';
import 'package:medlog/data.dart';

void main() {
  setUpAll(() => ChoicesRepo.parse(jsonDecode(File('assets/data/choices.json').readAsStringSync()) as Map));

  test('every app specialty has a template, unknown ones get the generic one', () {
    for (final n in kSpecialtyNames) {
      expect(ChoicesRepo.forSpecialty(n), isNotNull, reason: n);
    }
    expect(ChoicesRepo.forSpecialty('OB/GYN')!.id, 'obstetrics_and_gynecology');
    expect(ChoicesRepo.forSpecialty('ICU')!.id, 'intensive_care');
    expect(ChoicesRepo.forSpecialty('Ortho')!.id, 'orthopedics');
    expect(ChoicesRepo.forSpecialty('Podiatry')!.id, 'custom');
  });

  test('orthopedics: nothing is selected, branches replace lists, dependsOn opens steps, stale is flagged', () {
    final rec = CaseRec({'id': 'a', 'specialty': 'Orthopedics'});
    final cc = CaseChoices(rec);
    final t = cc.template()!;
    expect(cc.isEmpty, true);
    final site = t.step('site')!;
    final prob = t.step('problem')!;
    final mech = t.step('mechanism')!;
    expect(cc.enabled(t, prob), false); // depends on site
    var res = cc.resolve(t);
    final baseProblem = res['problem']!.map((o) => o.v).toList();
    cc.toggle(t, site, res['site']!, 'Elbow');
    expect(cc.enabled(t, prob), true);
    res = cc.resolve(t);
    final elbowProblem = res['problem']!.map((o) => o.v).toList();
    expect(elbowProblem, isNot(baseProblem));
    // injury branch (3rd level) replaces mechanism
    final before = res['mechanism']!.map((o) => o.v).toList();
    cc.toggle(t, prob, res['problem']!, 'Injury');
    res = cc.resolve(t);
    expect(res['mechanism']!.map((o) => o.v).toList(), isNot(before));
    expect(res['mechanism']!.any((o) => o.v == 'FOOSH'), true);
    cc.toggle(t, mech, res['mechanism']!, 'FOOSH');
    expect(cc.pick('mechanism').v, ['FOOSH']);
    // the site changes: FOOSH may no longer be offered -> kept and flagged, never removed
    cc.toggle(t, site, res['site']!, 'Elbow'); // deselect
    cc.toggle(t, site, res['site']!, 'Hip');
    res = cc.resolve(t);
    expect(cc.pick('mechanism').v, ['FOOSH']);
    final stale = cc.stale(mech, res['mechanism']!);
    print('stale after Elbow->Hip: $stale; hip mech: ${res['mechanism']!.map((o) => o.v).take(6)}');
    // persisted shape
    final saved = jsonDecode(jsonEncode(rec.d['choices'])) as Map;
    expect(saved['t'], 'orthopedics');
    expect(saved['v'], 1);
    expect((saved['s'] as Map).containsKey('site'), true);
    expect(cc.lines(section: 'History').first[0], 'Site');
  });

  test('exclusive options need confirmation and never coexist', () {
    final rec = CaseRec({'id': 'b', 'specialty': 'Orthopedics'});
    final cc = CaseChoices(rec);
    final t = cc.template()!;
    final st = t.step('exam_look')!;
    final opts = st.options;
    final normal = opts.firstWhere((o) => o.exclusive).v;
    final other = opts.firstWhere((o) => !o.exclusive).v;
    expect(cc.toggle(t, st, opts, other), true);
    expect(cc.toggle(t, st, opts, normal), false); // would clear -> confirm first
    expect(cc.pick('exam_look').v, [other]);
    expect(cc.toggle(t, st, opts, normal, confirmed: true), true);
    expect(cc.pick('exam_look').v, [normal]);
    expect(cc.toggle(t, st, opts, other), true); // leaving an exclusive one loses nothing
    expect(cc.pick('exam_look').v, [other]);
    // single: replaces and a second tap clears
    final side = t.step('side')!;
    cc.toggle(t, side, side.options, 'Left');
    cc.toggle(t, side, side.options, 'Right');
    expect(cc.pick('side').v, ['Right']);
    cc.toggle(t, side, side.options, 'Right');
    expect(cc.pick('side').v, isEmpty);
  });

  test('all 27 templates resolve with a selection in every first step without errors', () {
    for (final n in kSpecialtyNames) {
      final rec = CaseRec({'id': n, 'specialty': n});
      final cc = CaseChoices(rec);
      final t = cc.template()!;
      for (final s in t.steps) {
        final res = cc.resolve(t);
        final o = res[s.id]!;
        if (cc.enabled(t, s) && o.isNotEmpty) cc.toggle(t, s, o, o.first.v, confirmed: true);
      }
      expect(cc.isEmpty, false, reason: n);
      expect(cc.lines(section: 'History').isNotEmpty || cc.lines(section: 'Examination').isNotEmpty, true);
    }
  });
  test('a confirmed diagnosis fills the final diagnosis; typed text is never overwritten; tests and plan go to the lists', () {
    final rec = CaseRec({'id': 'c', 'specialty': 'Orthopedics'});
    final cc = CaseChoices(rec);
    final t = cc.template()!;
    final written = <String, String>{};
    void write(String k, String v) {
      rec.set(k, v);
      written[k] = v;
    }
    var res = cc.resolve(t);
    cc.toggle(t, t.step('site')!, res['site']!, 'Elbow');
    res = cc.resolve(t);
    final dxOpts = res['assessment']!;
    final first = dxOpts.firstWhere((o) => !o.exclusive && o.v != 'Other').v;
    cc.toggle(t, t.step('assessment')!, dxOpts, first);
    cc.toggle(t, t.step('diagnostic_certainty')!, res['diagnostic_certainty']!, 'Confirmed');
    expect(ChoicesSync.derive(rec, write), true);
    expect(rec.s('finalDx'), first);
    expect(rec.s('ddx'), first);
    expect(rec.s('workingDx'), '');
    // suspected -> working diagnosis
    cc.toggle(t, t.step('diagnostic_certainty')!, res['diagnostic_certainty']!, 'Suspected', confirmed: true);
    ChoicesSync.derive(rec, write);
    expect(rec.s('workingDx'), first);
    // the user types a final diagnosis himself: a later choice never replaces it
    rec.set('finalDx', 'My own words');
    cc.toggle(t, t.step('diagnostic_certainty')!, res['diagnostic_certainty']!, 'Confirmed', confirmed: true);
    ChoicesSync.derive(rec, write);
    expect(rec.s('finalDx'), 'My own words');
    // adders
    expect(ChoicesSync.addTests(rec, ['Elbow X-ray AP and lateral', 'CT elbow if indicated']), 2);
    expect(ChoicesSync.addTests(rec, ['Elbow X-ray AP and lateral']), 0); // no duplicate
    expect(rec.lst('inv').first['requestedBy'], '');
    expect(ChoicesSync.addPlanItems(rec, ['Analgesia']), 1);
    expect(rec.lst('mgmt').first['by'], '');
    // moved steps do not repeat in the PDF lines
    expect(cc.lines(section: 'Assessment'), isEmpty);
    expect(cc.lines(section: 'Management'), isEmpty);
  });
}
