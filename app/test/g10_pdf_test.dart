import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/choices_engine.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart';
import 'package:medlog/pdf_export.dart';
import 'lib2_util.dart';
import 'pdf2_test.dart' show loadFont;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pdf lists the documented choices', () async {
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_700Bold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
    ChoicesRepo.parse(jsonDecode(File('assets/data/choices.json').readAsStringSync()) as Map);
    await initStoreLight();
    final c = CaseRec({'id': 'a', 'code': 'ORT-0003', 'date': '2026-10-24', 'specialty': 'Orthopedics', 'cc': 'Rt elbow pain'});
    final cc = CaseChoices(c);
    final t = cc.template()!;
    var res = cc.resolve(t);
    cc.toggle(t, t.step('site')!, res['site']!, 'Elbow');
    cc.toggle(t, t.step('side')!, res['side']!, 'Right');
    res = cc.resolve(t);
    cc.toggle(t, t.step('problem')!, res['problem']!, 'Injury');
    res = cc.resolve(t);
    cc.toggle(t, t.step('mechanism')!, res['mechanism']!, 'FOOSH');
    cc.setDetails(t, 'mechanism', 'fell on outstretched hand yesterday');
    setLangSetting('en');
    await Future(() {});
    final pages = await casesDoc([c]).render();
    File('test_output/shots/G10_pdf.png').writeAsBytesSync(pages.first);
  });
}
