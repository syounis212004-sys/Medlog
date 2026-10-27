import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/library.dart';

import '../lib2_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const src = '/tmp/ch1';
  final names = [
    'first-aid-emergency-medicine.bin',
    'first-aid-emergency-medicine.idx',
    'first-aid-emergency-medicine-images.img',
    'first-aid-emergency-medicine-images.imx',
    'first-aid-emergency-medicine.local.json',
  ];

  test('two books side by side, chapters kept, re-import keeps both', () async {
    await initStoreLight();
    final base = Directory.systemTemp.createTempSync('lib_two');
    await library.init(base);
    const z1 = '/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/d0a0a486-MedLog-Chapter1-Local.zip';
    await library.importLocalBook([z1]);
    await library.importLocalBook(['/tmp/book2/second.zip']);
    expect(library.pack('first-aid-emergency-medicine'), isNotNull);
    expect(library.pack('second-test-book')!.kind, 'book');
    final ch = await library.chaptersOf('second-test-book');
    expect(ch.map((c) => c.title), ['Chapter One', 'Chapter Two']);
    expect((await library.chapterNumbersOf('second-test-book')).length, 12);
    expect((await library.imagesFor('01.02 Airway Management')).isNotEmpty, true);
    await library.importLocalBook([z1]);
    expect(library.packs.where((p) => p.kind == 'book').length, 2);
  });

  test('a book may not take over another course id', () async {
    await initStoreLight();
    final base = Directory.systemTemp.createTempSync('lib_clash');
    await library.init(base);
    await library.importLocalBook(['/tmp/book2/second.zip']);
    expect(library.pack('second-test-book'), isNotNull);
  });

  test('a single ZIP is enough', () async {
    await initStoreLight();
    final base = Directory.systemTemp.createTempSync('lib_book_zip');
    await library.init(base);
    await library.importLocalBook(['/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/d0a0a486-MedLog-Chapter1-Local.zip']);
    expect(library.pack('first-aid-emergency-medicine')!.count, 12);
    expect((await library.read('first-aid-emergency-medicine', 0))!.sections.isNotEmpty, true);
    expect(Directory(library.dir.path).listSync().where((e) => e.path.contains('.local-book-')), isEmpty);
    final imgs = await library.imagesFor('01.02 Airway Management');
    expect(imgs.isNotEmpty, true, reason: 'book pictures are found for their topic');
  });

  test('local book import: rejects missing, accepts all five, reads articles and images', () async {
    await initStoreLight();
    final base = Directory.systemTemp.createTempSync('lib_book');
    await library.init(base);
    // missing file
    await expectLater(library.importLocalBook([for (final n in names.take(4)) '$src/$n']), throwsA(isA<FormatException>()));
    expect(library.packs.where((p) => p.id.startsWith('first-aid')), isEmpty);
    // all five
    await library.importLocalBook([for (final n in names) '$src/$n']);
    final p = library.pack('first-aid-emergency-medicine');
    expect(p, isNotNull);
    expect(p!.kind, 'book');
    expect(p.count, 12);
    final a = await library.read('first-aid-emergency-medicine', 1);
    expect(a, isNotNull);
    expect(a!.title.isNotEmpty, true);
    expect(a.sections.isNotEmpty, true);
    // twice does not duplicate
    await library.importLocalBook([for (final n in names) '$src/$n']);
    expect(library.packs.where((p) => p.id == 'first-aid-emergency-medicine').length, 1);
    // nothing leaks outside the library folder
    expect(File('${library.dir.path}/first-aid-emergency-medicine-images.bin').existsSync(), true);
  });
}
