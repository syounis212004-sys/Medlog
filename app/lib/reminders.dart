import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'data.dart';
import 'i18n.dart';

/// Local reminders. Everything is scheduled on the phone (no internet, no server)
/// with inexact alarms, so no exact-alarm permission is needed. The texts are
/// generic on purpose: they never contain patient or clinical content.

// ------------------------------------------------------------ pure time rules

/// Next time of day (hour:minute) strictly after [now].
DateTime nextDaily(DateTime now, int hour, int minute) {
  var t = DateTime(now.year, now.month, now.day, hour, minute);
  if (!t.isAfter(now)) t = DateTime(now.year, now.month, now.day + 1, hour, minute);
  return t;
}

/// Next [weekday] (DateTime.monday..sunday) at hour:minute strictly after [now].
DateTime nextWeekly(DateTime now, int weekday, int hour, int minute) {
  var t = DateTime(now.year, now.month, now.day, hour, minute);
  final add = (weekday - now.weekday) % 7;
  t = DateTime(t.year, t.month, t.day + add, hour, minute);
  if (!t.isAfter(now)) t = DateTime(t.year, t.month, t.day + 7, hour, minute);
  return t;
}

/// When to nudge about an unfinished draft after the app was left: 3 hours later,
/// but never at night (22:00-08:00 moves to 09:00).
DateTime draftReminderAt(DateTime now) {
  final t = now.add(const Duration(hours: 3));
  if (t.hour >= 22) return DateTime(t.year, t.month, t.day + 1, 9);
  if (t.hour < 8) return DateTime(t.year, t.month, t.day, 9);
  return t;
}

// ------------------------------------------------------------ backend seam

enum Repeat { none, daily, weekly }

abstract class NotifyBackend {
  Future<void> init();

  /// Android 13+ runtime permission. True when notifications may be shown.
  Future<bool> requestPermission();
  Future<void> schedule(int id, String title, String body, DateTime when, Repeat repeat);
  Future<void> cancel(int id);
}

class PlatformNotifyBackend implements NotifyBackend {
  final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _tzOk = false;

  @override
  Future<void> init() async {
    if (_ready) return;
    await _p.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
      _tzOk = true;
    } catch (_) {
      _tzOk = false; // repeating reminders fall back to one-shot ones, refreshed at every start
    }
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await init();
      final a = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (a == null) return true;
      return (await a.requestNotificationsPermission()) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> schedule(int id, String title, String body, DateTime when, Repeat repeat) async {
    await init();
    final at = tz.TZDateTime.from(when, tz.local);
    DateTimeComponents? match;
    if (_tzOk) {
      if (repeat == Repeat.daily) match = DateTimeComponents.time;
      if (repeat == Repeat.weekly) match = DateTimeComponents.dayOfWeekAndTime;
    }
    await _p.zonedSchedule(
      id,
      title,
      body,
      at,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'medlog_reminders',
          tr('Reminders'),
          channelDescription: tr('Reminders from MedLog'),
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: match,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    await _p.cancel(id);
  }
}

// ------------------------------------------------------------ the reminders

class Reminders {
  Reminders._();

  static NotifyBackend backend = PlatformNotifyBackend();
  static DateTime Function() clock = DateTime.now;

  static const int idDaily = 41, idDraft = 42, idWeekly = 43;

  static bool get dailyOn => store.settings['remDaily'] == true;
  static int get dailyHour => _int('remDailyH', 20, 0, 23);
  static int get dailyMinute => _int('remDailyM', 0, 0, 59);
  static bool get draftOn => store.settings['remDraft'] == true;
  static bool get weeklyOn => store.settings['remWeekly'] == true;
  static int get weeklyDay => _int('remWeeklyD', DateTime.sunday, 1, 7);
  static int get weeklyHour => _int('remWeeklyH', 18, 0, 23);
  static int get weeklyMinute => _int('remWeeklyM', 0, 0, 59);

  static int _int(String k, int d, int lo, int hi) {
    final v = store.settings[k];
    return v is num ? v.toInt().clamp(lo, hi) : d;
  }

  static bool get hasDraft => store.cases.values.any((c) => c.s('status') == 'Draft');

  static Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (kDebugMode) debugPrint('reminders: $e');
    }
  }

  /// Schedules / cancels the daily and weekly reminders from the settings.
  /// Safe to call at any time; never throws.
  static Future<void> sync() async {
    final any = dailyOn || weeklyOn || draftOn;
    if (!any && store.settings['remEver'] != true) return; // nothing was ever scheduled
    if (any && store.settings['remEver'] != true) {
      await _safe(() => store.setLook('remEver', true));
    }
    final now = clock();
    await _safe(() async {
      if (dailyOn) {
        await backend.schedule(idDaily, 'MedLog', tr('Time for your MedLog review'),
            nextDaily(now, dailyHour, dailyMinute), Repeat.daily);
      } else {
        await backend.cancel(idDaily);
      }
    });
    await _safe(() async {
      if (weeklyOn) {
        await backend.schedule(idWeekly, 'MedLog', tr('Time to look at your weekly goals in MedLog'),
            nextWeekly(now, weeklyDay, weeklyHour, weeklyMinute), Repeat.weekly);
      } else {
        await backend.cancel(idWeekly);
      }
    });
    if (!draftOn) await _safe(() => backend.cancel(idDraft));
  }

  /// The app was left: nudge about an unfinished draft case.
  static Future<void> onPaused() async {
    await sync();
    await _safe(() async {
      if (draftOn && hasDraft) {
        await backend.schedule(idDraft, tr('Finish my draft case'),
            tr('You have a draft case waiting in MedLog.'), draftReminderAt(clock()), Repeat.none);
      } else {
        await backend.cancel(idDraft);
      }
    });
  }

  /// The app is open again: the draft nudge is not needed any more.
  static Future<void> onResumed() => _safe(() => backend.cancel(idDraft));

  /// Changes a reminder setting and re-schedules.
  static Future<void> set(String key, Object value) async {
    await store.setLook(key, value);
    await sync();
  }

  /// Called when a switch is turned on. False when the user refused notifications.
  static Future<bool> ensurePermission() async {
    try {
      return await backend.requestPermission();
    } catch (_) {
      return false;
    }
  }
}
