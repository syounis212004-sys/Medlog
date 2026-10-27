import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/data.dart';
import 'package:medlog/ref_data.dart';
import 'package:medlog/score_engine.dart';
import 'package:medlog/screens_calc.dart';
import 'package:medlog/screens_ref.dart';

import 'lib2_util.dart';

Future<void> settle(WidgetTester t, [int ms = 600]) async {
  await t.pump(Duration(milliseconds: ms));
  await t.pump(Duration(milliseconds: ms));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('data loads: 40 cards, 16 specialties, 400 terms, 60 golden questions', (tester) async {
    await tester.runAsync(() async {
      expect((await RefData.cards()).length, 40);
      expect(((await RefData.curriculum())['specialties'] as Map).length, 16);
      expect((await RefData.glossary()).length, 400);
      expect((await RefData.golden()).length, 60);
      expect(((await RefData.sources())['guidelines'] as List).length, greaterThan(100));
      await ScoreRepo.load();
    });
  });

  testWidgets('cards screen lists cards, searches and opens a detail', (tester) async {
    await tester.runAsync(() async {
      await initStoreLight();
      await RefData.cards();
    });
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: BedsideCardsScreen()));
    await settle(tester);
    expect(find.byKey(const ValueKey('card_Chest pain')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('cards_search')), 'jaundice');
    await settle(tester);
    expect(find.byKey(const ValueKey('card_Jaundice')), findsOneWidget);
    expect(find.byKey(const ValueKey('card_Chest pain')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('card_Jaundice')));
    await settle(tester, 800);
    expect(find.textContaining('Acute cholangitis'), findsWidgets);
  });

  testWidgets('rotation hub: pick a specialty, tick a topic, progress is saved', (tester) async {
    await tester.runAsync(() async {
      await initStoreLight();
      await RefData.curriculum();
      await RefData.cards();
    });
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: RotationHubScreen()));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('rot_Cardiology')));
    await settle(tester);
    final cur = await tester.runAsync(() => RefData.curriculum());
    final first = ((cur!['specialties'] as Map)['Cardiology']['coreTopics'] as List).first['topic'] as String;
    final box = find.byKey(ValueKey('rot_topic_$first'));
    await tester.ensureVisible(box);
    await tester.tap(box);
    await settle(tester);
    final m = store.settings['rotDone'] as Map;
    expect((m['Cardiology'] as List).contains(first), true);
  });

  testWidgets('calculators screen shows the data-driven scores and computes SOFA', (tester) async {
    await tester.runAsync(() async {
      await initStoreLight();
      await ScoreRepo.load();
    });
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    store.settings['folds'] = {'sc_phq9': true, 'sc_phq_9': true};
    await tester.pumpWidget(const MaterialApp(home: CalculatorsScreen()));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('calc_search')), 'PHQ');
    await settle(tester);
    expect(find.textContaining('PHQ-9'), findsWidgets);
    final defs = await tester.runAsync(() => ScoreRepo.load());
    final phq = defs!.firstWhere((d) => d.id.startsWith('phq'));
    // choose option 3 on the first question
    final k = ValueKey('sc_${phq.id}_${phq.inputs.first.id}_3');
    await tester.ensureVisible(find.byKey(k));
    await tester.tap(find.byKey(k));
    await settle(tester);
    expect(find.textContaining('Answer every question'), findsWidgets);
  });
}
