import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/ai/ai_engine.dart';
import 'package:medlog/library.dart';
import 'package:medlog/lib_glance.dart';
import 'package:medlog/lib_text.dart';
import 'package:medlog/main.dart';
import 'package:medlog/screens_article.dart';
import 'package:medlog/screens_library.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePP extends PathProviderPlatform {
  final String dir;
  FakePP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
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

Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> realWait(WidgetTester tester, [int ms = 300]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<Uint8List> png(Color c, int w, int h) async {
  final rec = ui.PictureRecorder();
  final cv = Canvas(rec);
  cv.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = c);
  cv.drawCircle(Offset(w / 2, h / 2), h / 3, Paint()..color = Colors.white70);
  final img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  AiEngine.debugOnline = false;
  test('glance keeps bullets and first sentences only', () {
    final a = LibArticle('Test disease', '', const [
      LibSection('', 'Test disease is a disorder of testing. It is rare.'),
      LibSection('Signs and symptoms', '• Fever\n• Cough\n• Pain when you move\n• Fatigue\n• Rash'),
      LibSection('Treatment', 'First line is rest. Second line is more rest. Third sentence is ignored.'),
      LibSection('History', 'Not needed in the glance.'),
    ]);
    final g = buildGlance(a);
    expect(g.map((e) => e.kind), [SecKind.symptoms, SecKind.treatment]);
    expect(g.first.points.length, 4);
    expect(g.last.points.length, 2);
  });

  setUpAll(() async {
    const rb = '/opt/flutter/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('ui16 $lang: 4 tabs, portfolio in header, tools card, multi-image article, quick view', (tester) async {
      final dir = Directory.systemTemp.createTempSync('medlog').path;
      PathProviderPlatform.instance = FakePP(dir);
      Directory('$dir/medlog/cases').createSync(recursive: true);
      Directory('$dir/medlog/images').createSync(recursive: true);
      File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({'lang': lang, 'author': 'Dr. M', 'palette': 'clinic', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false}));
      await tester.runAsync(() => store.init());
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 892);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
      // synthetic text pack + v2 image pack with 3 pictures (two belong to a section)
      await tester.runAsync(() async {
        final base = Directory.systemTemp.createTempSync('medlib');
        await library.init(base);
        await library.writePack(
          const PackMeta(id: 'orthopedics', title: 'Orthopedics', kind: 'wiki', source: 'Wikipedia', license: 'CC BY-SA 4.0', date: '2026-10-01'),
          [
            LibArticle('Knee disease', 'https://en.wikipedia.org/wiki/Knee_disease', [
              const LibSection('', 'Knee disease is a condition of the knee joint. It is common in older adults. More text follows here to make a longer lead paragraph for the article.'),
              const LibSection('Signs and symptoms', '• Pain on walking\n• Swelling of the joint\n• Morning stiffness\n• Reduced range of motion'),
              const LibSection('Diagnosis', 'Diagnosis is clinical. Imaging may support the diagnosis. Blood tests exclude other causes.'),
              const LibSection('Treatment', 'Exercise and weight loss are first line. Analgesics may be used. Surgery is rare.'),
            ]),
          ],
        );
        final b1 = await png(Colors.teal, 300, 200), b2 = await png(Colors.indigo, 300, 220), b3 = await png(Colors.orange, 280, 200);
        final blob = BytesBuilder()..add(b1)..add(b2)..add(b3);
        final imx = gzip.encode(utf8.encode(jsonEncode({
          'meta': {'id': 'orthopedics-images', 'kind': 'images', 'for': 'orthopedics', 'v': 2},
          'v': 2,
          't': ['Knee disease'],
          'a': [
            [
              {'o': 0, 'n': b1.length, 's': '', 'c': 'A swollen knee in an older adult', 'f': 'Knee_one.jpg', 'u': 'Dr Author — CC BY-SA 4.0'},
              {'o': b1.length, 'n': b2.length, 's': 'Diagnosis', 'c': 'X-ray showing narrowed joint space', 'f': 'Knee_xray.jpg', 'u': 'Wikimedia Commons'},
              {'o': b1.length + b2.length, 'n': b3.length, 's': 'Treatment', 'c': 'Physiotherapy exercise', 'f': 'Exercise.jpg', 'u': 'Someone — CC0'},
            ]
          ],
        })));
        await File('${library.dir.path}/orthopedics-images.idx').writeAsBytes(imx);
        await File('${library.dir.path}/orthopedics-images.bin').writeAsBytes(blob.takeBytes());
        await File('${library.dir.path}/installed.json').writeAsString(jsonEncode([
          for (final p in library.packs) p.toJson(),
          {'id': 'orthopedics-images', 'title': 'Orthopedics images', 'kind': 'images', 'for': 'orthopedics', 'count': 3, 'bytes': 1000, 'date': '2026-10-01'},
        ]));
        await library.init(base);
        final imgs = await library.imagesFor('Knee disease');
        expect(imgs.length, 3);
        expect(imgs[1].section, 'Diagnosis');
        expect(imgs[1].caption, 'X-ray showing narrowed joint space');
        expect(imgs[1].credit, 'Wikimedia Commons');
      });
      await settle(tester, 3800);
      // bottom bar: four tabs, add button in the middle, no Portfolio tab
      final home = lang == 'ar' ? 'الرئيسية' : 'Home';
      expect(find.descendant(of: find.byType(AppNavBar), matching: find.text(home)), findsOneWidget);
      expect(find.descendant(of: find.byType(AppNavBar), matching: find.text(lang == 'ar' ? 'الملف' : 'Portfolio')), findsNothing);
      final addC = tester.getCenter(find.byIcon(Icons.add_rounded).first);
      expect((addC.dx - 206).abs() < 12, true, reason: 'add button is centred: ${addC.dx}');
      expect(find.byIcon(Icons.insights_outlined), findsWidgets);
      await shot(tester, 'U16_${lang}_home');
      // library tab with the tools card
      await tester.tap(find.descendant(of: find.byType(AppNavBar), matching: find.text(lang == 'ar' ? 'المكتبة' : 'Library')));
      await settle(tester, 1200);
      for (var k = 0; k < 8; k++) {
        await realWait(tester, 120);
      }
      await settle(tester, 600);
      await shot(tester, 'U16_${lang}_library');
      // article: quick view by default with glance + all pictures at the top
      final nav0 = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav0.push(MaterialPageRoute(builder: (_) => const ArticleScreen(packId: 'orthopedics', index: 0)));
      await settle(tester, 600);
      for (var k = 0; k < 30 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; k++) {
        await realWait(tester, 120);
      }
      for (var k = 0; k < 8; k++) {
        await realWait(tester, 120);
      }
      await settle(tester, 800);
      await shot(tester, 'U16_${lang}_article_quick');
      expect(find.text('A swollen knee in an older adult'), findsOneWidget);
      expect(find.text('X-ray showing narrowed joint space'), findsOneWidget);
      // full article: the picture of a section moves into its section
      await tester.tap(find.text(lang == 'ar' ? 'المقال كاملا' : 'Full article'));
      await settle(tester, 700);
      await shot(tester, 'U16_${lang}_article_full');
      expect(find.text('X-ray showing narrowed joint space'), findsNothing); // folded in the closed Diagnosis section
      await tester.ensureVisible(find.byIcon(Icons.biotech_outlined).last);
      await settle(tester, 300);
      await tester.tap(find.text('Diagnosis').last);
      await settle(tester, 700);
      expect(find.text('X-ray showing narrowed joint space'), findsOneWidget);
      await shot(tester, 'U16_${lang}_article_section');
      // tap a picture: full-screen viewer
      await tester.tap(find.text('X-ray showing narrowed joint space'));
      await settle(tester, 800);
      expect(find.byType(ImageViewerScreen), findsOneWidget);
      await shot(tester, 'U16_${lang}_viewer');
    });
  }
}
