import 'package:flutter/material.dart' hide Text;
import 'package:quick_actions/quick_actions.dart';

import 'app_lock.dart';
import 'data.dart';
import 'i18n.dart';
import 'main.dart' show navKeyFor, currentNavId, shellGoTab;
import 'screens_cases.dart';
import 'screens_quiz.dart';

/// Launcher shortcuts (long-press the app icon). The action is remembered until
/// the app is really ready (shell built, no lock on top), so a cold start works.

const String kShortNew = 'new_case', kShortTest = 'test_myself', kShortSearch = 'search_library';

abstract class ShortcutBackend {
  Future<void> init(void Function(String type) onAction);
  Future<void> setItems(List<MapEntry<String, String>> items); // type -> title
}

class PlatformShortcutBackend implements ShortcutBackend {
  final QuickActions _q = const QuickActions();
  @override
  Future<void> init(void Function(String type) onAction) => _q.initialize(onAction);
  @override
  Future<void> setItems(List<MapEntry<String, String>> items) => _q.setShortcutItems(
      [for (final e in items) ShortcutItem(type: e.key, localizedTitle: e.value)]);
}

class AppShortcuts {
  AppShortcuts._();

  static ShortcutBackend backend = PlatformShortcutBackend();
  static String? pending;
  static bool shellReady = false;
  static bool _listening = false;

  /// What a shortcut does. Replaced in tests.
  static void Function(String type) runner = _defaultRun;

  static Future<void> init() async {
    try {
      if (!_listening) {
        _listening = true;
        appLock.addListener(tryRun);
        store.addListener(tryRun);
      }
      await backend.init(dispatch);
      await refreshItems();
    } catch (_) {}
  }

  /// Titles follow the app language; call again when it changes.
  static Future<void> refreshItems() async {
    try {
      await backend.setItems([
        MapEntry(kShortNew, tr('New case')),
        MapEntry(kShortTest, tr('Test myself')),
        MapEntry(kShortSearch, tr('Search the library')),
      ]);
    } catch (_) {}
  }

  static void dispatch(String type) {
    if (type != kShortNew && type != kShortTest && type != kShortSearch) return;
    pending = type;
    tryRun();
  }

  static void tryRun() {
    final t = pending;
    if (t == null || !shellReady || !store.ready || store.locked || appLock.locked) return;
    pending = null;
    try {
      runner(t);
    } catch (_) {}
  }

  static void _defaultRun(String type) {
    final nav = navKeyFor(currentNavId).currentState;
    final ctx = navKeyFor(currentNavId).currentContext;
    if (nav == null || ctx == null) return;
    nav.popUntil((r) => r.isFirst);
    switch (type) {
      case kShortNew:
        openNewCase(ctx);
      case kShortTest:
        nav.push(MaterialPageRoute(builder: (_) => const QuizScreen()));
      case kShortSearch:
        shellGoTab?.call(2);
    }
  }
}
