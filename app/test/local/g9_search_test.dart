import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/library.dart';
import '../lib2_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('search finds local book', () async {
    await initStoreLight();
    await library.init(Directory.systemTemp.createTempSync('lib_s'));
    await library.importLocalBook(['/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/d0a0a486-MedLog-Chapter1-Local.zip']);
    final t = await library.titlesOf('first-aid-emergency-medicine');
    print(t);
    for (final q in ['airway', 'shock', 'epinephrine', 'intubation']) {
      final a = await library.searchEx(q);
      print('$q title-only: ${[for (final h in a) '${h.packId}:${h.title}']}');
      final b = await library.searchEx(q, body: true);
      print('$q body: ${[for (final h in b) '${h.packId}:${h.title}']}');
    }
    await Future.delayed(const Duration(seconds: 2)); await library.ensureFts(only: 'first-aid-emergency-medicine');
    print(await library.searchEx('epinephrine', body: true).then((l) => [for (final h in l) h.title]));
    print('fts ${library.ftsIndexed}/${library.textPacks.length}');
  });
}
