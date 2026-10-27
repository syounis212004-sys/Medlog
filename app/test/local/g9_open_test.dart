import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/library.dart';
import 'package:medlog/screens_article.dart';
import 'package:medlog/screens_library.dart';
import '../lib2_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('open imported first-aid book: browse + article', (tester) async {
    await tester.runAsync(() async {
      await initStoreLight();
      final base = Directory.systemTemp.createTempSync('lib_open');
      await library.init(base);
      const z1 = '/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/d0a0a486-MedLog-Chapter1-Local.zip';
      await library.importLocalBook([z1]);
    });
    final p = library.pack('first-aid-emergency-medicine')!;
    await tester.pumpWidget(MaterialApp(home: PackBrowseScreen(pack: p)));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(home: ArticleScreen(packId: p.id, index: 1)));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 800)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
