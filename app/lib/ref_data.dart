import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Reference data bundled in assets/data (cards, rotation curriculum, guideline map,
/// glossary, AI quality questions). Loaded once and cached.
class RefData {
  static final Map<String, Object?> _cache = {};

  static Future<dynamic> _load(String name) async {
    if (_cache.containsKey(name)) return _cache[name];
    final raw = await rootBundle.loadString('assets/data/$name.json');
    return _cache[name] = jsonDecode(raw);
  }

  static Future<List<Map<String, dynamic>>> cards() async =>
      [for (final c in ((await _load('cards')) as Map)['cards'] as List) Map<String, dynamic>.from(c as Map)];

  static Future<Map<String, dynamic>> curriculum() async => Map<String, dynamic>.from((await _load('curriculum')) as Map);

  static Future<Map<String, dynamic>> sources() async => Map<String, dynamic>.from((await _load('sources')) as Map);

  static Future<List<Map<String, dynamic>>> glossary() async =>
      [for (final t in ((await _load('glossary')) as Map)['terms'] as List) Map<String, dynamic>.from(t as Map)];

  static Future<List<Map<String, dynamic>>> golden() async =>
      [for (final q in ((await _load('golden')) as Map)['questions'] as List) Map<String, dynamic>.from(q as Map)];

  static Future<Map<String, dynamic>> privacy() async => Map<String, dynamic>.from((await _load('privacy')) as Map);

  static List<String> strings(Object? v) => v is List ? [for (final e in v) e.toString()] : const [];

  /// Does the card belong to a specialty? Card specialty names are broader than the app's list.
  static bool cardMatches(Map<String, dynamic> card, String appSpecialty) {
    final aliases = _aliases[appSpecialty] ?? [appSpecialty];
    final sp = strings(card['specialties']).map((s) => s.toLowerCase());
    return aliases.any((a) => sp.any((s) => s.contains(a.toLowerCase())));
  }

  static const Map<String, List<String>> _aliases = {
    'Internal Medicine': ['Internal Medicine'],
    'General Surgery': ['Surgery'],
    'Pediatrics': ['Pediatrics', 'Neonatology'],
    'OB/GYN': ['Obstetrics', 'Gynecology'],
    'Emergency': ['Emergency'],
    'ICU': ['Intensive Care'],
    'Orthopedics': ['Orthopedics'],
    'Family Medicine': ['Family Medicine'],
    'Neurology': ['Neurology'],
    'Psychiatry': ['Psychiatry'],
    'ENT': ['ENT'],
    'Ophthalmology': ['Ophthalmology'],
    'Dermatology': ['Dermatology'],
    'Urology': ['Urology'],
    'Anesthesia': ['Anesthesia'],
    'Cardiology': ['Cardiology'],
  };
}
