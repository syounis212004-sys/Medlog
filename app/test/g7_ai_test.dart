import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/ai/ai_glossary.dart';
import 'package:medlog/ai/ai_quality.dart';
import 'package:medlog/ref_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GoldenQ q({List<String> inc = const [], List<String> no = const [], bool warn = false}) => GoldenQ(1, 'management', 'x', 'q', inc, no, warn);

  test('matching: alternatives, case, forbidden phrases', () {
    final g = q(inc: ['adrenaline|epinephrine', 'intramuscular|im'], no: ['intravenous bolus']);
    expect(AiQuality.evaluate(g, 'Give IM Epinephrine at once.').pass, true);
    final bad = AiQuality.evaluate(g, 'Give adrenaline as an intravenous bolus, intramuscular later.');
    expect(bad.pass, false);
    expect(bad.forbidden, ['intravenous bolus']);
    final miss = AiQuality.evaluate(g, 'Call for help.');
    expect(miss.missing.length, 2);
  });

  test('pass rate ignores failed requests', () {
    final a = AiQuality.evaluate(q(inc: ['x']), 'x');
    final b = AiQuality.evaluate(q(inc: ['y']), 'x');
    const c = GoldenResult(GoldenQ(2, 'a', 'b', 'c', [], [], false), '', [], [], failedToAnswer: true);
    expect(AiQuality.passRate([a, b, c]), 0.5);
    expect(AiQuality.passRate([c]), isNull);
  });

  test('every golden question is well formed and passable by a perfect answer', () async {
    final qs = await RefData.golden();
    expect(qs.length, 60);
    expect(qs.where((e) => e['category'] == 'safety-trap').length, greaterThanOrEqualTo(10));
    for (final j in qs) {
      final g = GoldenQ.fromJson(j);
      expect(g.mustInclude, isNotEmpty, reason: 'q${g.id}');
      // an answer made of the first alternative of each required item must pass (the check is satisfiable)
      final perfect = g.mustInclude.map((m) => m.split('|').first).join(' ');
      final r = AiQuality.evaluate(g, perfect);
      expect(r.missing, isEmpty, reason: 'q${g.id}');
      // and no required phrase is also forbidden
      for (final n in g.mustNotInclude) {
        expect(AiQuality.evaluate(GoldenQ(0, '', '', '', const [], [n], false), perfect).forbidden, isEmpty, reason: 'q${g.id} forbids its own required text');
      }
    }
  });

  test('glossary hint finds terms and is silent for English', () async {
    await AiGlossary.ensure();
    final h = AiGlossary.hintFor('Patient with pneumonia and pleural effusion', 'ar');
    expect(h, contains('pneumonia'));
    expect(h, contains('التهاب رئوي'));
    expect(AiGlossary.hintFor('Patient with pneumonia', 'en'), '');
    expect(AiGlossary.hintFor('nothing relevant here', 'ar'), '');
  });
}
