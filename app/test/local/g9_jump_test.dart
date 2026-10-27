import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/library.dart';
import 'package:medlog/screens_article.dart';
import '../lib2_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('hit opens the article at the sentence', (tester) async {
    late LibHit hit;
    await tester.runAsync(() async {
      await initStoreLight();
      await library.init(Directory.systemTemp.createTempSync('lib_j'));
      await library.importLocalBook(['/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/d0a0a486-MedLog-Chapter1-Local.zip']);
      await library.ensureFts(only: 'first-aid-emergency-medicine');
      hit = (await library.searchEx('epinephrine', body: true)).firstWhere((h) => h.inText);
    });
    print('snippet: ${hit.snippet}');
    await tester.pumpWidget(MaterialApp(home: ArticleScreen(packId: hit.packId, index: hit.index, focusQuote: hit.snippet)));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 800)));
    for (var i = 0; i < 20; i++) { await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60))); await tester.pump(const Duration(milliseconds: 100)); }
    expect(tester.takeException(), isNull);
    print(tester.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).where((t) => t.length > 40).take(6).toList());
    expect(find.textContaining('pinephrine', findRichText: true), findsWidgets);
  });
}
