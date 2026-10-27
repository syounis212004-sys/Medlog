import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/lib_quiz.dart';
import 'package:medlog/library.dart';
import 'lib2_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('generate 300 questions', () async {
    await initStoreLight();
    final cat = jsonDecode(File('../library/catalog.json').readAsStringSync()) as Map;
    final base = installPacks([for (final e in cat['packs'] as List) if (e['kind'] != 'images') e['id'] as String]);
    await library.init(base);
    final out = <Map>[];
    final sw = Stopwatch()..start();
    var dropped = 0, generated = 0;
    final why = <String, int>{};
    Future<void> run(String label, {String? packId, QuizSource? source, QuizLevel level = QuizLevel.medium, int seed = 1, int count = 30, String? sf}) async {
      final t = sw.elapsedMilliseconds;
      final qs = await buildQuiz(packId: packId, source: source, level: level, seed: seed, count: count, sourceFilter: sf);
      dropped += lastQuizReport.dropped;
      generated += lastQuizReport.generated;
      lastQuizReport.droppedWhy.forEach((k, v) => why[k] = (why[k] ?? 0) + v);
      print('$label seed $seed: ${qs.length} q in ${sw.elapsedMilliseconds - t} ms, pool ${lastQuizReport.pool}, reads ${lastQuizReport.reads}, gen ${lastQuizReport.generated}, dropped ${lastQuizReport.dropped}, t $quizTimings');
      for (final q in qs) {
        out.add({
          'run': label, 'kind': q.kind.name, 'stem': q.stem, 'options': q.options, 'answer': q.answer, 'explanation': q.explanation,
          'title': q.title, 'group': q.group, 'level': q.level.name, 'src': library.sourceOf(q.packId, q.title), 'gate': gateQuestion(q).score,
        });
      }
    }
    for (var s = 1; s <= 4; s++) { await run('core', seed: s, level: QuizLevel.values[s % 3], count: s == 1 ? 10 : 30); }
    await run('core', seed: 9, count: 30, sf: 'WikEM');
    await run('all', source: QuizSource.all, seed: 2, count: 30);
    await run('all', source: QuizSource.all, seed: 3, count: 30);
    await run('random', source: QuizSource.random, seed: 4, count: 30);
    await run('cardiology', packId: 'cardiology', seed: 5, count: 30);
    await run('pediatrics', packId: 'pediatrics', seed: 6, count: 30);
    print('total ${out.length} in ${sw.elapsedMilliseconds} ms; generated $generated dropped $dropped');
    print('dropped why: $why');
    final kinds = <String, int>{};
    for (final q in out) { kinds[q['kind']] = (kinds[q['kind']] ?? 0) + 1; }
    print('kinds $kinds');
    Directory('test_output/eval').createSync(recursive: true);
    File('test_output/eval/quiz_v2_all.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
