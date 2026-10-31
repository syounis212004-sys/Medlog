import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/ai/ai_engine.dart' show AiEngine;
import 'package:medlog/data.dart';
import 'package:medlog/main.dart';
import 'package:medlog/screens_cases.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'lib2_util.dart' show openPage;

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

Future<void> boot(WidgetTester tester, String lang) async {
  final dir = Directory.systemTemp.createTempSync('medlog').path;
  PathProviderPlatform.instance = FakePP(dir);
  Directory('$dir/medlog/cases').createSync(recursive: true);
  Directory('$dir/medlog/images').createSync(recursive: true);
  File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({
    'lang': lang, 'author': 'Dr. M', 'palette': 'clinic', 'deviceId': 'x',
    'lastBackup': DateTime.now().toIso8601String(),
  }));
  File('$dir/medlog/cases/c0.json').writeAsStringSync(jsonEncode({
    'id': 'c0', 'schema': 2, 'created': '2026-10-10T08:00:00Z', 'date': '2026-10-10',
    'specialty': 'Internal Medicine', 'ageGroup': 'Adult', 'status': 'Active',
    'cc': 'Chest pain 2 days', 'hpi': 'Pain started...', 'pmh': 'Hypertension',
    'allergies': 'Penicillin', 'v_bp': '150/90', 'v_hr': '',
  }));
  AiEngine.debugOnline = true;
  await tester.runAsync(() => store.init());
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(412, 892);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
  await settle(tester, 3800);
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute(
      builder: (_) => CaseEditorScreen(rec: store.cases['c0']!, initialTab: 1)));
  await settle(tester, 1500);
}

Future<void> fill(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton).first);
  await settle(tester, 600);
  await tester.tap(find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
  await settle(tester, 800);
}

void main() {
  setUpAll(() async {
    final rb = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
    await loadFont('Tajawal', ['$fd/Tajawal_400Regular.ttf', '$fd/Tajawal_500Medium.ttf', '$fd/Tajawal_700Bold.ttf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  testWidgets('history fill keeps typed, fills empty, vitals untouched, undo restores', (tester) async {
    await boot(tester, 'en');
    final rec = store.cases['c0']!;
    final before = jsonEncode(Map<String, dynamic>.from(rec.d)..remove('updated'));
    await fill(tester);
    expect(rec.s('pmh'), 'Hypertension');
    expect(rec.s('allergies'), 'Penicillin');
    expect(rec.s('cc'), 'Chest pain 2 days');
    expect(rec.s('drugs'), 'No regular medications');
    expect(rec.s('family'), 'Non-contributory');
    expect(rec.s('ros'), 'ROS negative except as above');
    expect(rec.s('v_bp'), '150/90');
    expect(rec.s('v_hr'), '');
    expect(rec.s('examGeneral'), '');
    expect((rec.d['autoNormal'] as List).toSet(), {'drugs', 'family', 'ros'});
    expect(find.text('Filled automatically - confirm you examined this', skipOffstage: false), findsWidgets);
    await shot(tester, 'QF_en_history');
    await tester.tap(find.text('Undo').last);
    await settle(tester, 800);
    final now = Map<String, dynamic>.from(rec.d)..remove('updated');
    expect(jsonEncode(now), before);
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await settle(tester, 1000);
  });

  testWidgets('exam fill: systems normal, vitals untouched', (tester) async {
    await boot(tester, 'en');
    final rec = store.cases['c0']!;
    await openPage(tester, Icons.monitor_heart_outlined);
    await settle(tester, 1000);
    await fill(tester);
    final sys = rec.d['sys'] as Map;
    for (final n in ['General', 'CVS', 'Respiratory', 'Abdomen', 'CNS', 'MSK', 'ENT', 'Skin']) {
      expect((sys[n] as Map)['s'], 'Normal');
    }
    expect(rec.s('examGeneral'), startsWith('Conscious, alert'));
    expect(rec.s('examSystemic'), startsWith('S1 S2 normal'));
    expect(rec.s('v_bp'), '150/90');
    expect(rec.s('v_temp'), '');
    expect(rec.s('pmh'), 'Hypertension');
    await shot(tester, 'QF_en_exam');
  });

  testWidgets('menu: fill everything normal', (tester) async {
    await boot(tester, 'en');
    final rec = store.cases['c0']!;
    await tester.tap(find.byKey(const ValueKey('case_menu')));
    await settle(tester, 600);
    await tester.tap(find.byKey(const ValueKey('menu_more')));
    await settle(tester, 400);
    await tester.tap(find.text('Fill everything normal (empty fields only)'));
    await settle(tester, 600);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await settle(tester, 800);
    expect(rec.s('drugs'), 'No regular medications');
    expect(rec.s('examSystemic'), startsWith('S1 S2'));
    expect((rec.d['sys'] as Map).length, 8);
    expect(rec.s('v_hr'), '');
  });

  testWidgets('arabic layout', (tester) async {
    await boot(tester, 'ar');
    await shot(tester, 'QF_ar_history_before');
    await fill(tester);
    await shot(tester, 'QF_ar_history');
    await openPage(tester, Icons.monitor_heart_outlined);
    await settle(tester, 1000);
    await shot(tester, 'QF_ar_exam');
    await fill(tester);
    await shot(tester, 'QF_ar_exam_filled');
  });
}
