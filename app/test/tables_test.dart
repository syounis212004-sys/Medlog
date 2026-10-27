import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
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

  test('tables survive the pack round trip; old json without tb still loads', () {
    final a = LibArticle.fromJson({
      't': 'X',
      'u': 'u',
      's': [
        {'h': '', 't': 'Lead.'},
        {
          'h': 'Dosing',
          't': 'Text',
          'tb': [
            {'c': 'Cap', 'r': [['a', 'b'], ['1', '2']]},
            {'c': 'bad', 'r': [['only header']]},
          ]
        },
      ],
      'src': 'Some source',
      'lic': 'CC0',
    });
    expect(a.sections[0].tables, isEmpty);
    expect(a.sections[1].tables.length, 1);
    expect(a.sections[1].tables.first.columns, 2);
    expect(a.source, 'Some source');
    final b = LibArticle.fromJson(a.toJson());
    expect(b.sections[1].tables.first.rows[1], ['1', '2']);
    expect(b.license, 'CC0');
    expect(store.libShowTables, true);
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('tables $lang: shown in full article, hidden in quick view and when switched off', (tester) async {
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
      await tester.runAsync(() async {
        final base = Directory.systemTemp.createTempSync('medlib');
        await library.init(base);
        await library.writePack(
          const PackMeta(id: 'cardiology', title: 'Cardiology', kind: 'wiki', source: 'Wikipedia', license: 'CC BY-SA 4.0', date: '2026-10-01'),
          [
            LibArticle('Heart failure', 'https://en.wikipedia.org/wiki/Heart_failure', [
              const LibSection('', 'Heart failure is a syndrome in which the heart cannot pump enough blood. It is common in older adults.'),
              const LibSection('Signs and symptoms', '• Breathlessness\n• Ankle swelling\n• Fatigue'),
              LibSection('Diagnosis', 'Classification uses ejection fraction and symptoms.', [
                const LibTable('NYHA functional classification', [
                  ['Class', 'Patient symptoms'],
                  ['I', 'No limitation of physical activity.'],
                  ['II', 'Slight limitation. Ordinary activity results in fatigue, palpitation or dyspnea.'],
                  ['III', 'Marked limitation. Less than ordinary activity causes symptoms.'],
                  ['IV', 'Unable to carry on any physical activity without discomfort.'],
                ]),
                const LibTable('Common drugs', [
                  ['Drug', 'Class', 'Start dose', 'Target dose', 'Main effect', 'Key adverse effect'],
                  ['Enalapril', 'ACE inhibitor', '2.5 mg twice daily', '10-20 mg twice daily', 'Lower mortality', 'Cough'],
                  ['Carvedilol', 'Beta blocker', '3.125 mg twice daily', '25 mg twice daily', 'Lower mortality', 'Bradycardia'],
                  ['Spironolactone', 'MRA', '12.5 mg daily', '25-50 mg daily', 'Lower mortality', 'Hyperkalaemia'],
                ]),
              ]),
              const LibSection('Treatment', 'Diuretics relieve congestion. ACE inhibitors and beta blockers improve survival.'),
            ]),
            LibArticle('Old article', '', [
              const LibSection('', 'Old article is plain text without tables. It still opens normally.'),
              const LibSection('Treatment', 'Rest.'),
            ]),
          ],
        );
      });
      Future<void> open(int idx) async {
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push(MaterialPageRoute(builder: (_) => ArticleScreen(packId: 'cardiology', index: idx)));
        await settle(tester, 600);
        for (var k = 0; k < 30 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; k++) {
          await realWait(tester, 120);
        }
        await realWait(tester, 200);
        await settle(tester, 600);
      }

      final full = lang == 'ar' ? 'المقال كاملا' : 'Full article';
      await open(0);
      // quick view lists the tables after the key points
      expect(find.text('NYHA functional classification', skipOffstage: false), findsWidgets);
      await tester.tap(find.text(full));
      await settle(tester, 700);
      // sections are folded: open Diagnosis
      await tester.scrollUntilVisible(find.text('Diagnosis').last, 150, scrollable: find.byType(Scrollable).first);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await settle(tester, 300);
      await tester.tap(find.text('Diagnosis').last);
      await settle(tester, 700);
      expect(find.byType(TableGrid), findsWidgets);
      expect(find.text('NYHA functional classification'), findsOneWidget);
      expect(find.text('Patient symptoms'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget); // only the 6-column table
      await tester.ensureVisible(find.text('NYHA functional classification'));
      await settle(tester, 300);
      await shot(tester, 'TB_${lang}_article');
      // fold the first table
      await tester.tap(find.text('NYHA functional classification'));
      await settle(tester, 400);
      expect(find.text('Patient symptoms'), findsNothing);
      // wide table: full screen viewer
      await tester.scrollUntilVisible(find.byIcon(Icons.fullscreen), -150, scrollable: find.byType(Scrollable).first);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 350));
      await settle(tester, 300);
      await tester.tap(find.byIcon(Icons.fullscreen));
      await settle(tester, 800);
      expect(find.byType(TableViewerScreen), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsWidgets);
      expect(find.text('Key adverse effect'), findsOneWidget);
      await shot(tester, 'TB_${lang}_fullscreen');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester, 600);
      // switch tables off in the settings, reopen: nothing shown
      await tester.runAsync(() => store.setLook('libTables', false));
      expect(store.libShowTables, false);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester, 600);
      await open(0);
      expect(find.byType(TableGrid), findsNothing);
      await tester.ensureVisible(find.text('Diagnosis').last);
      await tester.tap(find.text('Diagnosis').last);
      await settle(tester, 700);
      expect(find.byType(TableGrid), findsNothing);
      expect(find.text('NYHA functional classification'), findsNothing);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester, 600);
      // old article without tables
      await tester.runAsync(() => store.setLook('libTables', true));
      await open(1);
      expect(find.byType(TableGrid), findsNothing);
      expect(find.text('Old article'), findsWidgets);
    });
  }

  testWidgets('library settings shows the Show tables switch', (tester) async {
    final dir = Directory.systemTemp.createTempSync('medlog').path;
    PathProviderPlatform.instance = FakePP(dir);
    Directory('$dir/medlog/cases').createSync(recursive: true);
    Directory('$dir/medlog/images').createSync(recursive: true);
    File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({'lang': 'en', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String()}));
    await tester.runAsync(() => store.init());
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async => library.init(Directory.systemTemp.createTempSync('medlib')));
    await tester.pumpWidget(const MaterialApp(home: LibrarySettingsScreen()));
    await settle(tester, 800);
    await tester.scrollUntilVisible(find.text('Show tables'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Show tables'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await settle(tester, 300);
    await tester.tap(find.text('Show tables'));
    await settle(tester, 300);
    expect(store.libShowTables, false);
  });
}
