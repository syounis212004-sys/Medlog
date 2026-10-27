import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/choices_engine.dart';
import 'package:medlog/data.dart';
import 'package:medlog/screens_cases.dart';

import 'g5_test.dart' show boot, push, settle, shot;
import 'lib2_util.dart' show openPage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('complaint templates: parsed, suggested from the chief complaint, merged after the specialty steps', () {
    ChoicesRepo.parse(jsonDecode(File('assets/data/choices.json').readAsStringSync()) as Map);
    ChoicesRepo.parseComplaints(jsonDecode(File('assets/data/complaints_01.json').readAsStringSync()) as Map);
    expect(ChoicesRepo.complaints.length, 5);
    expect(ChoicesRepo.suggest('Chest pain on exertion').map((t) => t.id), ['complaint-chest-pain']);
    expect(ChoicesRepo.suggest('SOB since 2 days').map((t) => t.id), contains('complaint-dyspnea'));
    expect(ChoicesRepo.suggest('xx'), isEmpty);
    expect(ChoicesRepo.complaintsFor('Pediatrics').length, 5);
    final rec = CaseRec({'id': 'a', 'specialty': 'Cardiology', 'cc': 'Chest pain'});
    final cc = CaseChoices(rec);
    final base = cc.template()!.steps.length;
    cc.addComplaint('complaint-chest-pain');
    cc.addComplaint('complaint-chest-pain'); // twice: once
    final t = cc.template()!;
    expect(t.steps.length, base + 20);
    expect(t.id, cc.baseTemplate()!.id); // picks stay stamped with the specialty template
    final site = t.step('cp-site')!;
    expect(site.group, 'Chest pain');
    // an untouched complaint documents nothing
    expect(cc.isEmpty, true);
    var res = cc.resolve(t);
    cc.toggle(t, t.step('cp-character')!, res['cp-character']!, 'Pleuritic');
    res = cc.resolve(t);
    expect(res['cp-respiratory']!.map((o) => o.v), contains('Hemoptysis')); // branch of the complaint
    expect(cc.enabled(t, t.step('cp-respiratory')!), true);
    cc.toggle(t, site, res['cp-site']!, 'Central chest');
    final lines = cc.lines(section: 'History');
    expect(lines.any((l) => l[0] == 'Chest pain: Pain site' && l[1] == 'Central chest'), true);
    // removing the template keeps the picks in the data
    cc.removeComplaint('complaint-chest-pain');
    expect(cc.template()!.steps.length, base);
    expect(cc.lines(section: 'History').any((l) => l[0].startsWith('Chest pain')), false);
    cc.addComplaint('complaint-chest-pain');
    expect(cc.pick('cp-site').v, ['Central chest']);
    final saved = jsonDecode(jsonEncode(rec.d['choices'])) as Map;
    expect(saved['x'], ['complaint-chest-pain']);
  });

  testWidgets('complaint bar in the History tab', (tester) async {
    await tester.runAsync(() => ChoicesRepo.load());
    await boot(tester, 'en');
    store.settings['choicesAll'] = true;
    final c = store.cases.values.firstWhere((x) => x.id == 'cA');
    c.d['specialty'] = 'Emergency';
    c.d['cc'] = 'Chest pain';
    await push(tester, CaseEditorScreen(rec: c));
    await openPage(tester, Icons.forum_outlined);
    await settle(tester, 700);
    expect(find.text('Complaint templates'), findsOneWidget);
    expect(find.text('Chest pain'), findsWidgets);
    await shot(tester, 'G11_complaint_bar');
    await tester.tap(find.widgetWithText(ActionChip, 'Chest pain').first);
    await settle(tester, 600);
    expect(CaseChoices(c).complaintIds, ['complaint-chest-pain']);
    expect(find.text('Pain site'), findsWidgets);
    await shot(tester, 'G11_complaint_added');
    await tester.tap(find.widgetWithText(ActionChip, 'More complaints'));
    await settle(tester, 600);
    await shot(tester, 'G11_complaint_sheet');
    expect(tester.takeException(), isNull);
  });

  testWidgets('guided mode: one question at a time, auto-advance, skip, back, show all', (tester) async {
    await tester.runAsync(() => ChoicesRepo.load());
    await boot(tester, 'en');
    store.settings['choicesAll'] = false;
    final c = store.cases.values.firstWhere((x) => x.id == 'cA');
    c.d['specialty'] = 'Orthopedics';
    c.d.remove('choices');
    await push(tester, CaseEditorScreen(rec: c));
    await openPage(tester, Icons.forum_outlined);
    await settle(tester, 700);
    expect(find.textContaining('Question 1 of'), findsOneWidget);
    await shot(tester, 'G11_guided_1');
    expect(find.text('Choose'), findsNothing); // no sheet: the options of the question are on the page
    expect(find.text('Elbow'), findsWidgets);
    await tester.drag(find.byType(ListView).first, const Offset(0, -260));
    await settle(tester, 300);
    await tester.tap(find.text('Elbow').first);
    await settle(tester, 600);
    expect(CaseChoices(c).pick('site').v, ['Elbow']);
    expect(find.textContaining('Question 2 of'), findsOneWidget); // moved on by itself
    await shot(tester, 'G11_guided_2');
    await tester.ensureVisible(find.text('Skip').first);
    await tester.tap(find.text('Skip').first);
    await settle(tester, 500);
    expect(find.textContaining('Question 3 of'), findsOneWidget); // skipping moves on
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await settle(tester, 300);
    await tester.tap(find.text('Show all questions').first);
    await settle(tester, 600);
    expect(store.settings['choicesAll'], true);
    expect(find.textContaining('Question 2 of'), findsNothing);
    await shot(tester, 'G11_guided_all');
    expect(tester.takeException(), isNull);
  });
}
