import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// Data-driven clinical scores. Definitions live in assets/data/scores.json and are
/// computed here, so adding a score is a data change. The AI never computes a score.

class ScoreOption {
  final String label;
  final num points;
  const ScoreOption(this.label, this.points);
}

class ScoreInput {
  final String id;
  final String label;
  final String type; // choice | bool | number
  final String unit;
  final num yes;
  final num no;
  final List<ScoreOption> options;
  const ScoreInput(this.id, this.label, this.type, this.unit, this.yes, this.no, this.options);
}

class ScoreBand {
  final num min;
  final num max;
  final String text;
  const ScoreBand(this.min, this.max, this.text);
}

class ScoreAlert {
  final String input;
  final int min;
  final String text;
  const ScoreAlert(this.input, this.min, this.text);
}

class ScoreExample {
  final Map<String, dynamic> picks;
  final num expected;
  const ScoreExample(this.picks, this.expected);
}

class ScoreDef {
  final String id;
  final String title;
  final String specialty;
  final String kind; // sum | rule | meld
  final List<ScoreInput> inputs;
  final List<ScoreBand> bands;
  final dynamic rule;
  final String source;
  final String limits;
  final List<ScoreAlert> alerts;
  final List<ScoreExample> examples;
  final num? max;
  const ScoreDef(this.id, this.title, this.specialty, this.kind, this.inputs, this.bands, this.rule, this.source, this.limits, this.alerts, this.examples, this.max);
}

class ScoreResult {
  final num total;
  final String band;
  final List<String> alerts;
  const ScoreResult(this.total, this.band, this.alerts);

  String get shown => total == total.roundToDouble() ? total.toStringAsFixed(0) : total.toStringAsFixed(1);
}

class ScoreRepo {
  static List<ScoreDef>? _cache;

  static Future<List<ScoreDef>> load() async {
    final c = _cache;
    if (c != null) return c;
    final raw = await rootBundle.loadString('assets/data/scores.json');
    return _cache = parse(raw);
  }

  static List<ScoreDef> parse(String raw) {
    final list = jsonDecode(raw) as List;
    return [for (final e in list) _def(e as Map<String, dynamic>)];
  }

  static ScoreDef _def(Map<String, dynamic> m) {
    final inputs = <ScoreInput>[];
    for (final i in (m['inputs'] as List)) {
      final im = i as Map<String, dynamic>;
      inputs.add(ScoreInput(
        im['id'] as String,
        im['label'] as String,
        im['type'] as String,
        (im['unit'] ?? '') as String,
        (im['yes'] ?? 1) as num,
        (im['no'] ?? 0) as num,
        [for (final o in (im['options'] as List? ?? const [])) ScoreOption((o as Map)['label'] as String, o['points'] as num)],
      ));
    }
    return ScoreDef(
      m['id'] as String,
      m['title'] as String,
      (m['specialty'] ?? '') as String,
      (m['kind'] ?? 'sum') as String,
      inputs,
      [for (final b in (m['bands'] as List? ?? const [])) ScoreBand((b as Map)['min'] as num, b['max'] as num, b['text'] as String)],
      m['rule'],
      (m['source'] ?? '') as String,
      (m['limits'] ?? '') as String,
      [for (final a in (m['alerts'] as List? ?? const [])) ScoreAlert((a as Map)['input'] as String, a['min'] as int, a['text'] as String)],
      [for (final e in (m['examples'] as List? ?? const [])) ScoreExample(Map<String, dynamic>.from((e as Map)['picks'] as Map), e['expected'] as num)],
      m['max'] as num?,
    );
  }

  static bool _eval(dynamic e, Map<String, dynamic> p) {
    if (e is String) return p[e] == true;
    final m = e as Map;
    if (m.containsKey('or')) return (m['or'] as List).any((x) => _eval(x, p));
    return (m['and'] as List).every((x) => _eval(x, p));
  }

  /// MELD (UNOS): floors of 1.0, creatinine capped at 4.0 (or 4.0 on dialysis), range 6-40.
  static int meld(double bili, double inr, double cr, bool dialysis) {
    final b = max(bili, 1.0);
    final i = max(inr, 1.0);
    final c = dialysis ? 4.0 : min(max(cr, 1.0), 4.0);
    final v = (3.78 * log(b) + 11.2 * log(i) + 9.57 * log(c) + 6.43).round();
    return max(6, min(40, v));
  }

  static String bandFor(ScoreDef d, num total) {
    for (final b in d.bands) {
      if (total >= b.min && total <= b.max) return b.text;
    }
    return '';
  }

  /// Returns null while an answer is missing (a missing answer is never counted as zero).
  /// Picks: choice -> option index, bool -> true/false, number -> double.
  static ScoreResult? compute(ScoreDef d, Map<String, dynamic> picks) {
    num total;
    if (d.kind == 'meld') {
      final b = picks['bilirubin'], i = picks['inr'], c = picks['creatinine'];
      if (b is! num || i is! num || c is! num || b <= 0 || i <= 0 || c <= 0) return null;
      total = meld(b.toDouble(), i.toDouble(), c.toDouble(), picks['dialysis'] == true);
    } else if (d.kind == 'rule') {
      total = _eval(d.rule, picks) ? 1 : 0;
    } else {
      total = 0;
      for (final i in d.inputs) {
        final v = picks[i.id];
        if (i.type == 'bool') {
          total += v == true ? i.yes : i.no;
        } else {
          if (v is! int || v < 0 || v >= i.options.length) return null;
          total += i.options[v].points;
        }
      }
    }
    final alerts = <String>[];
    for (final a in d.alerts) {
      final v = picks[a.input];
      if (v is int && v >= a.min) alerts.add(a.text);
    }
    return ScoreResult(total, bandFor(d, total), alerts);
  }
}
