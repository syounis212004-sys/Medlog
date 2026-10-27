import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/library.dart';
import '../lib2_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a multi-word query means the expression', () async {
    await initStoreLight();
    await library.init(Directory.systemTemp.createTempSync('lib_ph'));
    await library.importLocalBook(['/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/d0a0a486-MedLog-Chapter1-Local.zip']);
    await library.ensureFts(only: 'first-aid-emergency-medicine');
    final a = await library.searchEx('cardiac arrest', body: true);
    print('cardiac arrest: ${[for (final h in a) '${h.title} | ${h.inText ? h.snippet.substring(0, h.snippet.length.clamp(0, 60)) : '-'}']}');
    expect(a.isNotEmpty, true);
    expect(a.first.title.toLowerCase().contains('cardiac arrest'), true);
    final b = await library.searchEx('arrest airway', body: true); // both words, not an expression
    print('arrest airway: ${[for (final h in b) h.title]}');
    final c = await library.searchEx('shock cardiac', strict: true);
    print('strict shock cardiac: ${[for (final h in c) h.title]}');
    final d = await library.searchEx('airway', strict: true);
    expect(d.isNotEmpty, true);
  });
}
