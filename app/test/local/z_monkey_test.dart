import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../g5_test.dart' show boot, settle;

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
  }
  await l.load();
}

class Finding {
  final String text, trail;
  Finding(this.text, this.trail);
}

final findings = <String, Finding>{};

String _key(String s) {
  final t = s.split('\n').take(3).join(' ').replaceAll(RegExp(r'[0-9]+(\.[0-9]+)?'), '#');
  return t.substring(0, min(160, t.length));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final configs = [
    ('en', const Size(360, 640), 1.0),
    ('ar', const Size(360, 640), 1.0),
    ('en', const Size(412, 892), 1.3),
    ('ar', const Size(412, 892), 1.3),
    ('ar', const Size(320, 568), 1.0),
  ];
  setUpAll(() async {
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Tajawal', ['$fd/Tajawal_400Regular.ttf', '$fd/Tajawal_500Medium.ttf', '$fd/Tajawal_700Bold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
  });
  tearDownAll(() {
    final b = StringBuffer();
    b.writeln('UNIQUE FINDINGS: ${findings.length}');
    for (final f in findings.values) {
      b.writeln('---');
      b.writeln(f.text);
      b.writeln('TRAIL: ${f.trail}');
    }
    File('/tmp/monkey_report.txt').writeAsStringSync(b.toString());
  });

  final only = Platform.environment['MONKEY_ONLY'];
  for (final cfg in configs) {
    if (only != null && '${cfg.$1}${cfg.$2.width.toInt()}' != only) continue;
    testWidgets('monkey ${cfg.$1} ${cfg.$2.width.toInt()} x${cfg.$3}', (tester) async {
      final rnd = Random(cfg.$1.hashCode ^ cfg.$2.width.toInt() ^ (cfg.$3 * 10).toInt());
      final trail = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final msg = d.exceptionAsString();
        if (msg.contains('MissingPluginException') || msg.contains('PlatformException') || msg.contains('A Timer is still pending')) return;
        final k = '${cfg.$1}/${cfg.$2.width.toInt()}/${cfg.$3}: ${_key(msg)}';
        final frames = d.stack.toString().split('\n').where((l) => l.contains('package:medlog') || l.contains('lib/')).take(6).join('\n');
        findings.putIfAbsent(k, () => Finding('[$k]\n${msg.split('\n').take(8).join('\n')}\nSTACK:\n$frames', trail.reversed.take(8).toList().reversed.join(' > ')));
      };
      addTearDown(() => FlutterError.onError = prev);
      await boot(tester, cfg.$1, size: cfg.$2, scale: cfg.$3);

      Iterable<Element> hittable(Finder f) sync* {
        final size = tester.view.physicalSize;
        for (final e in f.evaluate()) {
          final ro = e.renderObject;
          if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
          final c = ro.localToGlobal(ro.size.center(Offset.zero));
          if (c.dx < 0 || c.dy < 0 || c.dx > size.width || c.dy > size.height) continue;
          yield e;
        }
      }

      final tappables = [
        find.byType(InkWell), find.byType(FilledButton), find.byType(TextButton), find.byType(OutlinedButton), find.byType(IconButton),
        find.byType(ListTile), find.byType(ActionChip), find.byType(ChoiceChip), find.byType(FilterChip), find.byType(Tab),
        find.byType(NavigationDestination), find.byType(FloatingActionButton), find.byType(Checkbox), find.byType(Switch),
      ];
      const words = ['chest pain', 'ألم صدري', '12', '0.5', 'fever 3 days', 'سكري', 'x' , '', 'Dr. Test', '37.5', 'amox'];
      var stuck = 0;
      for (var step = 0; step < 220; step++) {
        final r = rnd.nextInt(100);
        try {
          if (r < 62) {
            final all = <Element>[for (final f in tappables) ...hittable(f)];
            if (all.isEmpty) {
              stuck++;
              final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
              await nav.maybePop();
            } else {
              final e = all[rnd.nextInt(all.length)];
              final label = e.widget.runtimeType.toString();
              trail.add('tap $label@${e.renderObject!.paintBounds.size.width.toInt()}');
              await tester.tap(find.byWidget(e.widget).first, warnIfMissed: false);
            }
          } else if (r < 78) {
            final tf = [...hittable(find.byType(TextField))];
            if (tf.isNotEmpty) {
              final e = tf[rnd.nextInt(tf.length)];
              final w = words[rnd.nextInt(words.length)];
              trail.add('type "$w"');
              await tester.enterText(find.byWidget(e.widget).first, w);
            }
          } else if (r < 90) {
            final sc = [...hittable(find.byType(Scrollable))];
            if (sc.isNotEmpty) {
              final e = sc[rnd.nextInt(sc.length)];
              final dy = rnd.nextBool() ? -300.0 : 250.0;
              trail.add('scroll $dy');
              await tester.drag(find.byWidget(e.widget).first, Offset(0, dy), warnIfMissed: false);
            }
          } else {
            trail.add('back');
            final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
            await nav.maybePop();
          }
          await tester.pump(const Duration(milliseconds: 500));
          // dialogs / sheets left open by chance are closed now and then
          if (step % 9 == 8) {
            final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
            await nav.maybePop();
            await tester.pump(const Duration(milliseconds: 300));
          }
        } catch (e) {
          final k = '${cfg.$1}/${cfg.$2.width.toInt()}/${cfg.$3}: EXC ${e.toString().split('\n').first}';
          findings.putIfAbsent(k, () => Finding('[$k]\n${e.toString().split('\n').take(8).join('\n')}', trail.reversed.take(8).toList().reversed.join(' > ')));
          await tester.pump(const Duration(milliseconds: 300));
        }
      }
    }, timeout: const Timeout(Duration(minutes: 25)));
  }
}
