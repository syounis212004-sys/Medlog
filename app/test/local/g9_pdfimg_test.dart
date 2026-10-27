import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart';
import 'package:medlog/pdf_export.dart';
import '../lib2_util.dart';
import '../pdf2_test.dart' show loadFont;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pdf has the case images', () async {
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_700Bold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
    await initStoreLight();
    File(store.imagePath('x1.jpg')).writeAsBytesSync(File('/tmp/xray_test.jpg').readAsBytesSync());
    File(store.imagePath('x2.jpg')).writeAsBytesSync(File('/tmp/xray_test.jpg').readAsBytesSync());
    final c = CaseRec({'id': 'a', 'code': 'ORT-0003', 'date': '2026-10-24', 'specialty': 'Orthopedics', 'cc': 'Rt elbow pain',
      'images': [
        {'file': 'x1.jpg', 'type': 'X-ray', 'view': 'AP', 'caption': 'X-ray Ap of Elbow', 'date': '2026-10-24'},
        {'file': 'x2.jpg', 'type': 'X-ray', 'caption': 'Lateral'},
        {'file': 'gone.jpg', 'type': 'CT', 'caption': 'deleted file'},
      ]});
    setLangSetting('en');
    await Future(() {});
    final pages = await casesDoc([c]).render();
    for (var i = 0; i < pages.length; i++) File('test_output/shots/PDFIMG_p${i + 1}.png').writeAsBytesSync(pages[i]);
    print('pages ${pages.length}');
  });
}
