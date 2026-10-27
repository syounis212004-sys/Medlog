import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../secure_kv.dart';

enum AiProviderId { gemini, anthropic, openai }

/// Feature groups with their own on/off switch in the AI settings.
const List<String> kAiGroups = ['ask', 'explain', 'quiz', 'case', 'reports', 'help'];

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Per-phone AI preferences, the API keys (Android Keystore through [SecureKv]), the activity log and the answer cache.
///
/// Everything lives in `<documents>/medlog_ai/` (a sibling of the `medlog/` data folder that backups and exports
/// read), and keys in secure storage: nothing here is ever part of a backup, an export, settings.json or analytics.
class AiStore {
  static final _Ping _changes = _Ping();
  static ChangeNotifier get changes => _changes;

  /// Tests: keep everything in memory (no files, no secure storage).
  static bool memoryOnly = false;

  static bool master = false;
  static AiProviderId provider = AiProviderId.gemini;
  static final Map<String, String> models = {}; // provider name -> chosen model id
  static String openaiBase = 'https://api.openai.com/v1';
  static final Map<String, bool> features = {for (final g in kAiGroups) g: true};
  static bool allowLibrary = true;
  static bool allowCase = false; // turned on only after the consent dialog
  static bool caseConsented = false;
  static String previewMode = 'always'; // 'always' | 'session'
  static String _today = '';
  static int todayCount = 0;
  static String quotaHitDay = '';

  /// provider name -> 'day|note': live search refused for this key today (memory only, retried tomorrow / after restart).
  static final Map<String, String> searchOff = {};
  static String searchOffNote(AiProviderId p) {
    final v = searchOff[p.name];
    if (v == null) return '';
    final i = v.indexOf('|');
    return i > 0 && v.substring(0, i) == _day() ? v.substring(i + 1) : '';
  }

  static void markSearchOff(AiProviderId p, String note) => searchOff[p.name] = '${_day()}|$note';

  static final Map<String, String> _keys = {};
  static bool loaded = false;
  static Future<void>? _loading;
  static Directory? _dir;

  static String _day() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String _keyName(AiProviderId p) => 'ai_key_${p.name}';

  static Future<Directory?> _dirOf() async {
    if (memoryOnly) return null;
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationDocumentsDirectory();
      final d = Directory('${base.path}/medlog_ai');
      await d.create(recursive: true);
      return _dir = d;
    } catch (_) {
      return null;
    }
  }

  /// Forget the cached folder (tests that switch the documents folder).
  static void resetForTests() {
    _dir = null;
    loaded = false;
    _loading = null;
    master = false;
    provider = AiProviderId.gemini;
    models.clear();
    openaiBase = 'https://api.openai.com/v1';
    for (final g in kAiGroups) {
      features[g] = true;
    }
    allowLibrary = true;
    allowCase = false;
    caseConsented = false;
    previewMode = 'always';
    _today = '';
    todayCount = 0;
    quotaHitDay = '';
    searchOff.clear();
    _keys.clear();
    AiAudit.entries.clear();
    AiAudit._d = null;
    AiCache._m.clear();
    AiCache._d = null;
    sessionApproved = false;
  }

  /// True after the user approved one preview in this app run (preview mode 'session').
  static bool sessionApproved = false;

  static Future<void> ensureLoaded() => loaded ? Future<void>.value() : (_loading ??= load());

  static Future<void> load() async {
    final d = await _dirOf();
    if (d != null) {
      try {
        final f = File('${d.path}/ai_settings.json');
        if (await f.exists()) {
          final m = jsonDecode(await f.readAsString());
          if (m is Map) {
            master = m['master'] == true;
            final pn = m['provider']?.toString();
            provider = AiProviderId.values.firstWhere((e) => e.name == pn, orElse: () => AiProviderId.gemini);
            final mm = m['models'];
            if (mm is Map) {
              models
                ..clear()
                ..addAll(mm.map((k, v) => MapEntry(k.toString(), v.toString())));
            }
            openaiBase = (m['openaiBase'] ?? openaiBase).toString();
            final ff = m['features'];
            if (ff is Map) {
              for (final g in kAiGroups) {
                if (ff[g] is bool) features[g] = ff[g] as bool;
              }
            }
            allowLibrary = m['allowLibrary'] != false;
            allowCase = m['allowCase'] == true;
            caseConsented = m['caseConsented'] == true;
            previewMode = m['previewMode'] == 'session' ? 'session' : 'always';
            _today = (m['today'] ?? '').toString();
            todayCount = (m['count'] is int) ? m['count'] as int : 0;
            quotaHitDay = (m['quotaHitDay'] ?? '').toString();
          }
        }
      } catch (_) {}
      await AiAudit.load(d);
      await AiCache.load(d);
    }
    if (!memoryOnly) {
      for (final p in AiProviderId.values) {
        final k = await SecureKv.read(_keyName(p));
        if (k != null && k.isNotEmpty) _keys[p.name] = k;
      }
    }
    loaded = true;
    _changes.ping();
  }

  static Future<void> save() async {
    _changes.ping();
    final d = await _dirOf();
    if (d == null) return;
    try {
      await File('${d.path}/ai_settings.json').writeAsString(jsonEncode({
        'master': master,
        'provider': provider.name,
        'models': models,
        'openaiBase': openaiBase,
        'features': features,
        'allowLibrary': allowLibrary,
        'allowCase': allowCase,
        'caseConsented': caseConsented,
        'previewMode': previewMode,
        'today': _today,
        'count': todayCount,
        'quotaHitDay': quotaHitDay,
      }), flush: true);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- keys

  static String keyOf(AiProviderId p) => _keys[p.name] ?? '';
  static bool hasKey([AiProviderId? p]) => keyOf(p ?? provider).isNotEmpty;

  static Future<void> setKey(AiProviderId p, String key) async {
    final k = key.trim();
    if (k.isEmpty) {
      _keys.remove(p.name);
      if (!memoryOnly) await SecureKv.delete(_keyName(p));
    } else {
      _keys[p.name] = k;
      if (!memoryOnly) await SecureKv.write(_keyName(p), k);
    }
    _changes.ping();
  }

  static String modelOf(AiProviderId p) => models[p.name] ?? '';

  // ---------------------------------------------------------------- usage counter

  static int get requestsToday => _today == _day() ? todayCount : 0;

  static Future<void> countRequest() async {
    final d = _day();
    if (_today != d) {
      _today = d;
      todayCount = 0;
    }
    todayCount++;
    await save();
  }

  static Future<void> markQuotaHit() async {
    quotaHitDay = _day();
    await save();
  }

  static bool get quotaHitToday => quotaHitDay == _day();

  static String groupOf(String feature) {
    final f = feature.toLowerCase();
    if (f.startsWith('ask')) return 'ask';
    if (f.startsWith('explain') || f.startsWith('translate') || f.startsWith('define')) return 'explain';
    if (f.startsWith('quiz')) return 'quiz';
    if (f.startsWith('case')) return 'case';
    if (f.startsWith('report') || f.startsWith('summary') || f.startsWith('summar')) return 'reports';
    if (f.startsWith('help')) return 'help';
    return '';
  }

  static bool groupOn(String feature) {
    final g = groupOf(feature);
    return g.isEmpty || features[g] != false;
  }

  /// Clears local AI data (not keys): cache and activity log are separate calls.
  static Future<void> removeKeyEverywhere() async {
    for (final p in AiProviderId.values) {
      await setKey(p, '');
    }
  }
}

/// What left the phone: a local log, newest last, at most 500 entries. Never holds prompts or answers.
class AiAudit {
  static final List<Map<String, dynamic>> entries = [];
  static const int max = 500;
  static Directory? _d;

  static Future<void> load(Directory d) async {
    _d = d;
    try {
      final f = File('${d.path}/ai_audit.json');
      if (await f.exists()) {
        final v = jsonDecode(await f.readAsString());
        if (v is List) {
          entries
            ..clear()
            ..addAll(v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        }
      }
    } catch (_) {}
  }

  static Future<void> add(Map<String, dynamic> e) async {
    e['t'] = DateTime.now().toIso8601String();
    entries.add(e);
    while (entries.length > max) {
      entries.removeAt(0);
    }
    await _save();
    AiStore._changes.ping();
  }

  static Future<void> clear() async {
    entries.clear();
    await _save();
    AiStore._changes.ping();
  }

  static Future<void> _save() async {
    if (AiStore.memoryOnly) return;
    final d = _d ?? await AiStore._dirOf();
    if (d == null) return;
    _d = d;
    try {
      await File('${d.path}/ai_audit.json').writeAsString(jsonEncode(entries), flush: true);
    } catch (_) {}
  }
}

/// Answers kept on the phone by cache key so repeats (and offline replays) cost nothing.
class AiCache {
  static final Map<String, Map<String, dynamic>> _m = {};
  static const int max = 300;
  static Directory? _d;

  static int get count => _m.length;

  static Future<void> load(Directory d) async {
    _d = d;
    try {
      final f = File('${d.path}/ai_cache.json');
      if (await f.exists()) {
        final v = jsonDecode(await f.readAsString());
        if (v is Map) {
          _m
            ..clear()
            ..addAll(v.map((k, e) => MapEntry(k.toString(), Map<String, dynamic>.from(e as Map))));
        }
      }
    } catch (_) {}
  }

  static Map<String, dynamic>? get(String key) => _m[key];

  static Future<void> put(String key, String text, Map<String, dynamic>? json) async {
    _m.remove(key);
    _m[key] = {'t': DateTime.now().toIso8601String(), 'text': text, if (json != null) 'json': json};
    while (_m.length > max) {
      _m.remove(_m.keys.first);
    }
    await _save();
  }

  static Future<void> clear() async {
    _m.clear();
    await _save();
    AiStore._changes.ping();
  }

  static Future<void> _save() async {
    if (AiStore.memoryOnly) return;
    final d = _d ?? await AiStore._dirOf();
    if (d == null) return;
    _d = d;
    try {
      await File('${d.path}/ai_cache.json').writeAsString(jsonEncode(_m), flush: true);
    } catch (_) {}
  }
}
