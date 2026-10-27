import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/score_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final defs = ScoreRepo.parse(File('assets/data/scores.json').readAsStringSync());

  test('28 data-driven scores load', () {
    expect(defs.length, 28);
    expect(defs.map((d) => d.id).toSet().length, 28);
  });

  test('every worked example from the source files matches', () {
    var n = 0;
    for (final d in defs) {
      for (final e in d.examples) {
        final r = ScoreRepo.compute(d, e.picks);
        expect(r, isNotNull, reason: d.id);
        expect(r!.total, e.expected, reason: '${d.id} ${e.picks}');
        n++;
      }
    }
    expect(n, greaterThan(70));
  });

  test('missing answers block the result (never counted as zero)', () {
    final sofa = defs.firstWhere((d) => d.id == 'sofa');
    expect(ScoreRepo.compute(sofa, {}), isNull);
    final meld = defs.firstWhere((d) => d.id == 'meld');
    expect(ScoreRepo.compute(meld, {'bilirubin': 2.0}), isNull);
  });

  test('every band range covers the possible totals of sum scores', () {
    for (final d in defs.where((d) => d.kind == 'sum')) {
      var lo = 0.0, hi = 0.0;
      for (final i in d.inputs) {
        final vals = i.type == 'bool' ? [i.no, i.yes] : i.options.map((o) => o.points).toList();
        lo += vals.reduce((a, b) => a < b ? a : b);
        hi += vals.reduce((a, b) => a > b ? a : b);
      }
      for (var t = lo.toInt(); t <= hi.toInt(); t++) {
        expect(ScoreRepo.bandFor(d, t), isNotEmpty, reason: '${d.id} total $t');
      }
    }
  });

  test('MELD floors, cap and dialysis rule', () {
    expect(ScoreRepo.meld(0.5, 0.9, 0.4, false), 6);
    expect(ScoreRepo.meld(8, 2.5, 3.2, true), 38);
    expect(ScoreRepo.meld(50, 8, 9, false), 40);
  });

  test('PHQ-9 raises the safety alert on item 9', () {
    final phq = defs.firstWhere((d) => d.id == 'phq9' || d.id == 'phq_9');
    final picks = <String, dynamic>{for (final i in phq.inputs) i.id: 0};
    picks['deathSelfHarm'] = 1;
    final r = ScoreRepo.compute(phq, picks)!;
    expect(r.alerts, isNotEmpty);
    picks['deathSelfHarm'] = 0;
    expect(ScoreRepo.compute(phq, picks)!.alerts, isEmpty);
  });
}
