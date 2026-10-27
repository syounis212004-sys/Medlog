import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/app_lock.dart';
import 'package:medlog/data.dart';
import 'package:medlog/main.dart';
import 'package:medlog/reminders.dart';
import 'package:medlog/shortcuts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePP extends PathProviderPlatform {
  final String dir;
  FakePP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

class FakeAuth implements LockAuth {
  bool isSupported = true;
  bool result = true;
  int calls = 0;
  @override
  Future<bool> supported() async => isSupported;
  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    return result;
  }
}

class Sched {
  final int id;
  final String title, body;
  final DateTime when;
  final Repeat repeat;
  Sched(this.id, this.title, this.body, this.when, this.repeat);
}

class FakeNotify implements NotifyBackend {
  final Map<int, Sched> live = {};
  bool permission = true;
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<void> schedule(int id, String title, String body, DateTime when, Repeat repeat) async {
    live[id] = Sched(id, title, body, when, repeat);
  }

  @override
  Future<void> cancel(int id) async => live.remove(id);
}

Future<void> initStore(Map<String, dynamic> settings) async {
  final dir = Directory.systemTemp.createTempSync('medlogsys').path;
  PathProviderPlatform.instance = FakePP(dir);
  Directory('$dir/medlog/cases').createSync(recursive: true);
  Directory('$dir/medlog/images').createSync(recursive: true);
  File('$dir/medlog/settings.json')
      .writeAsStringSync(jsonEncode({'lang': 'en', 'deviceId': 'x', 'libOnline': false, ...settings}));
  await store.init();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reminder times', () {
    test('nextDaily', () {
      expect(nextDaily(DateTime(2026, 3, 1, 10, 0), 20, 30), DateTime(2026, 3, 1, 20, 30));
      expect(nextDaily(DateTime(2026, 3, 1, 20, 30), 20, 30), DateTime(2026, 3, 2, 20, 30)); // not in the past / same instant
      expect(nextDaily(DateTime(2026, 3, 31, 23, 0), 7, 5), DateTime(2026, 4, 1, 7, 5));
    });
    test('nextWeekly', () {
      // 2026-03-01 is a Sunday
      expect(DateTime(2026, 3, 1).weekday, DateTime.sunday);
      expect(nextWeekly(DateTime(2026, 3, 1, 10), DateTime.sunday, 18, 0), DateTime(2026, 3, 1, 18));
      expect(nextWeekly(DateTime(2026, 3, 1, 19), DateTime.sunday, 18, 0), DateTime(2026, 3, 8, 18));
      expect(nextWeekly(DateTime(2026, 3, 1, 10), DateTime.wednesday, 9, 15), DateTime(2026, 3, 4, 9, 15));
      expect(nextWeekly(DateTime(2026, 3, 4, 12), DateTime.monday, 9, 0), DateTime(2026, 3, 9, 9));
      expect(nextWeekly(DateTime(2026, 12, 30, 12), DateTime.friday, 9, 0), DateTime(2027, 1, 1, 9));
    });
    test('draftReminderAt avoids the night', () {
      expect(draftReminderAt(DateTime(2026, 3, 1, 10)), DateTime(2026, 3, 1, 13));
      expect(draftReminderAt(DateTime(2026, 3, 1, 20)), DateTime(2026, 3, 2, 9)); // 23:00 -> next morning
      expect(draftReminderAt(DateTime(2026, 3, 1, 23)), DateTime(2026, 3, 2, 9)); // 02:00 -> 09:00
      expect(draftReminderAt(DateTime(2026, 3, 1, 3)), DateTime(2026, 3, 1, 9)); // 06:00 -> 09:00
    });
  });

  group('app lock logic', () {
    late FakeAuth auth;
    late AppLock lock;
    late DateTime now;
    setUp(() async {
      await initStore({});
      auth = FakeAuth();
      lockAuth = auth;
      lock = AppLock();
      now = DateTime(2026, 3, 1, 12);
      lock.clock = () => now;
    });

    test('cannot be enabled unless authenticate succeeds', () async {
      auth.result = false;
      expect(await lock.enable(), LockEnable.failed);
      expect(lock.enabled, false);
      auth.result = true;
      auth.isSupported = false;
      expect(await lock.enable(), LockEnable.unsupported);
      expect(lock.enabled, false);
      auth.isSupported = true;
      expect(await lock.enable(), LockEnable.ok);
      expect(lock.enabled, true);
      await lock.disable();
      expect(lock.enabled, false);
    });

    test('immediately: locks on pause; unlock needs the system prompt', () async {
      await lock.enable();
      lock.onPaused();
      expect(lock.locked, true);
      lock.onResumed();
      expect(lock.locked, true);
      auth.result = false;
      expect(await lock.unlock(), false);
      expect(lock.locked, true);
      auth.result = true;
      expect(await lock.unlock(), true);
      expect(lock.locked, false);
    });

    test('lock after 1 minute', () async {
      await lock.enable();
      await lock.setDelay(60);
      lock.onPaused();
      expect(lock.locked, false);
      now = now.add(const Duration(seconds: 30));
      lock.onResumed();
      expect(lock.locked, false);
      lock.onPaused();
      now = now.add(const Duration(seconds: 61));
      lock.onResumed();
      expect(lock.locked, true);
    });

    test('does nothing when disabled; cold start is locked when enabled', () async {
      lock.onPaused();
      lock.onResumed();
      expect(lock.locked, false);
      lock.startup();
      expect(lock.locked, false);
      await lock.enable();
      lock.startup();
      expect(lock.locked, true);
    });

    test('phone lost its screen lock: switches off instead of locking out', () async {
      await lock.enable();
      lock.startup();
      auth.isSupported = false;
      expect(await lock.unlock(), true);
      expect(lock.locked, false);
      expect(lock.enabled, false);
    });
  });

  group('reminders scheduling', () {
    late FakeNotify n;
    setUp(() async {
      n = FakeNotify();
      Reminders.backend = n;
      Reminders.clock = () => DateTime(2026, 3, 1, 21, 0); // Sunday evening
    });

    test('nothing scheduled and backend untouched when never used', () async {
      await initStore({});
      await Reminders.sync();
      expect(n.live, isEmpty);
    });

    test('daily + weekly, then cancel', () async {
      await initStore({'remDaily': true, 'remDailyH': 8, 'remDailyM': 15, 'remWeekly': true, 'remWeeklyD': 3, 'remWeeklyH': 9, 'remWeeklyM': 0});
      await Reminders.sync();
      expect(n.live[Reminders.idDaily]!.when, DateTime(2026, 3, 2, 8, 15));
      expect(n.live[Reminders.idDaily]!.repeat, Repeat.daily);
      expect(n.live[Reminders.idDaily]!.body, 'Time for your MedLog review');
      expect(n.live[Reminders.idWeekly]!.when, DateTime(2026, 3, 4, 9, 0));
      expect(n.live[Reminders.idWeekly]!.repeat, Repeat.weekly);
      await Reminders.set('remDaily', false);
      expect(n.live.containsKey(Reminders.idDaily), false);
      expect(n.live.containsKey(Reminders.idWeekly), true);
    });

    test('draft reminder only when a draft exists, removed on resume', () async {
      await initStore({'remDraft': true});
      await Reminders.onPaused();
      expect(n.live.containsKey(Reminders.idDraft), false);
      final c = store.newCase();
      c.set('status', 'Draft');
      store.cases[c.id] = c;
      await Reminders.onPaused();
      final d = n.live[Reminders.idDraft]!;
      expect(d.title, 'Finish my draft case');
      expect(d.when, DateTime(2026, 3, 2, 9));
      await Reminders.onResumed();
      expect(n.live.containsKey(Reminders.idDraft), false);
    });

    test('a failing backend never throws', () async {
      await initStore({'remDaily': true});
      Reminders.backend = _Boom();
      await Reminders.sync();
      await Reminders.onPaused();
      expect(await Reminders.ensurePermission(), false);
    });
  });

  group('shortcut routing', () {
    late List<String> ran;
    setUp(() async {
      await initStore({});
      lockAuth = FakeAuth();
      ran = [];
      AppShortcuts.runner = ran.add;
      AppShortcuts.pending = null;
      AppShortcuts.shellReady = false;
      appLock.locked = false;
    });

    test('cold start: waits for the shell, then runs once', () {
      AppShortcuts.dispatch(kShortTest);
      expect(ran, isEmpty);
      AppShortcuts.shellReady = true;
      AppShortcuts.tryRun();
      expect(ran, [kShortTest]);
      AppShortcuts.tryRun();
      expect(ran, [kShortTest]);
    });

    test('waits while locked, runs after unlock', () {
      AppShortcuts.shellReady = true;
      appLock.locked = true;
      AppShortcuts.dispatch(kShortNew);
      expect(ran, isEmpty);
      appLock.locked = false;
      AppShortcuts.tryRun();
      expect(ran, [kShortNew]);
    });

    test('unknown types ignored; running app runs at once', () {
      AppShortcuts.shellReady = true;
      AppShortcuts.dispatch('bogus');
      AppShortcuts.dispatch(kShortSearch);
      expect(ran, [kShortSearch]);
    });
  });

  group('lock overlay in the app', () {
    testWidgets('cold start shows the cover, Unlock removes it; leaving the app covers it again', (tester) async {
      await tester.runAsync(() => initStore({'bioLock': true, 'bioLockDelay': 0, 'libOnline': false}));
      final auth = FakeAuth()..result = false;
      lockAuth = auth;
      Reminders.backend = FakeNotify();
      appLock.locked = false;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 892);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MedLogApp());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 100));
      // the real app start (main's init) is the one that locks; simulate its cold-start call
      appLock.startup();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('app-lock')), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(auth.calls, greaterThan(0)); // the prompt opened by itself, was refused
      expect(find.byKey(const ValueKey('app-lock')), findsOneWidget);

      auth.result = true;
      await tester.tap(find.text('Unlock'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('app-lock')), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('app-lock')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('app-lock')), findsNothing); // auto prompt succeeded
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _Boom implements NotifyBackend {
  @override
  Future<void> init() async => throw StateError('x');
  @override
  Future<bool> requestPermission() async => throw StateError('x');
  @override
  Future<void> schedule(int id, String title, String body, DateTime when, Repeat repeat) async => throw StateError('x');
  @override
  Future<void> cancel(int id) async => throw StateError('x');
}
