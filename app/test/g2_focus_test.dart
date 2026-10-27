import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' hide Text;
import 'package:medlog/library.dart';
import 'package:medlog/lib_text.dart';
import 'package:medlog/screens_article.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _PP extends PathProviderPlatform {
  final String dir;
  _PP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

Directory _installAll(List<String> only) {
  final base = Directory.systemTemp.createTempSync('g2fbase');
  final lib = Directory('${base.path}/library')..createSync(recursive: true);
  final cat = jsonDecode(File('../library/catalog.json').readAsStringSync()) as Map;
  final metas = <Map>[];
  for (final e in cat['packs'] as List) {
    if (e['kind'] == 'images') continue;
    final id = e['id'];
    if (!only.contains(id)) continue;
    for (final ext in ['idx', 'bin']) {
      Link('${lib.path}/$id.$ext').createSync('../library/$id.$ext');
    }
    metas.add({...(e as Map), 'bytes': File('../library/$id.bin').lengthSync() + File('../library/$id.idx').lengthSync()});
  }
  File('${lib.path}/installed.json').writeAsStringSync(jsonEncode(metas));
  return base;
}

final GlobalKey shotKey = GlobalKey();

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
  }
  await l.load();
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final b = shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('test_output/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> pumpReal(WidgetTester t, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    const rb = '/opt/flutter/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('g2fs').path;
    PathProviderPlatform.instance = _PP(dir);
    Directory('$dir/medlog/cases').createSync(recursive: true);
    File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({'lang': 'en', 'deviceId': 'x', 'libOnline': false, 'libQuick': true, 'lastBackup': DateTime.now().toIso8601String()}));
    await store.init();
    await library.init(_installAll(['clinical-essentials']));
    await library.ensureFts();
  });

  testWidgets('focusQuote opens the full article at the sentence', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final i = await tester.runAsync(() => library.indexOfTitle('clinical-essentials', 'Hyperkalemia — WikEM'));
    final art = await tester.runAsync(() => library.read('clinical-essentials', i!));
    // a sentence from a late section
    String quote = '';
    for (final s in art!.sections.reversed) {
      final sn = sentences(s.text).where((e) => e.length > 40 && e.length < 200).toList();
      if (sn.isNotEmpty) {
        quote = sn.first;
        break;
      }
    }
    expect(quote.isNotEmpty, true);
    await tester.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        locale: appLocale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
        home: ArticleScreen(packId: 'clinical-essentials', index: i!, focusQuote: quote),
      ),
    ));
    await pumpReal(tester, 14);
    for (var k = 0; k < 20; k++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    await shot(tester, 'g2_focus_article');
    await shot(tester, 'g2_focus_article');
    final head = normQuote(quote).split(' ').take(4).join(' ');
    final found = find.byWidgetPredicate((w) => w is RichText && normQuote(w.text.toPlainText()).contains(head));
    expect(found, findsWidgets);
    await shot(tester, 'g2_focus_article');
    await pumpReal(tester, 55); // highlight times out
    expect(tester.takeException(), isNull);
  });
}
