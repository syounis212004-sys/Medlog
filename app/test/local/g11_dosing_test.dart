import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/dosing.dart';
import 'package:medlog/screens_dosing.dart';
import '../lib2_util.dart';
import '../g5_test.dart' show boot, push, settle, shot;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('import, search, replace, remove, bad file', () async {
    await initStoreLight();
    await dosing.load();
    expect(dosing.packs, isEmpty);
    expect(() => dosing.importFiles(['/tmp/dose/bad.json']), throwsA(isA<FormatException>()));
    final added = await dosing.importFiles(['/tmp/dose/good.json']);
    expect(added.single.drugs, 2);
    expect(added.single.durations, 1);
    expect(dosing.searchDrugs('fixo').single.name, 'Fixturecillin'); // brand name
    expect(dosing.searchDrugs('test antibiotic').length, 1); // class
    expect(dosing.searchDrugs('', population: 'pediatric').single.name, 'Fixturecillin');
    expect(dosing.searchDurations('cystitis').single.duration, '3 days');
    await dosing.importFiles(['/tmp/dose/good.json']); // same id replaces
    expect(dosing.packs.length, 1);
    expect(dosing.drugs.length, 2);
    // survives a restart
    await dosing.load();
    expect(dosing.drugs.length, 2);
    expect(File('${dosing.dir.path}/test-dosing.json').existsSync(), true);
    await dosing.remove('test-dosing');
    expect(dosing.drugs, isEmpty);
    expect(File('${dosing.dir.path}/test-dosing.json').existsSync(), false);
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('dosing ui $lang', (tester) async {
      await boot(tester, lang);
      await tester.runAsync(() async {
        await dosing.load();
        await dosing.importFiles(['/tmp/dose/good.json']);
      });
      await push(tester, const DosingScreen());
      await shot(tester, 'G11_${lang}_list');
      await tester.tap(find.text('Fixturecillin'));
      await settle(tester, 700);
      await shot(tester, 'G11_${lang}_detail');
      expect(tester.takeException(), isNull);
    });
  }
}
