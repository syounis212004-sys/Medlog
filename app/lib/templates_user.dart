import 'data.dart';
import 'templates.dart';

/// Built-in starters plus the ones the user saved. Saved starters live in settings
/// (so they are part of the backup) and are shown after the built-in ones.
List<CaseTemplate> userTemplatesFor(String specialty) {
  final all = store.settings['userTemplates'];
  if (all is! Map) return const [];
  final list = all[specialty];
  if (list is! List) return const [];
  return [
    for (final e in list)
      if (e is Map && (e['label'] ?? '').toString().trim().isNotEmpty)
        CaseTemplate(e['label'].toString(), hpi: (e['hpi'] ?? '').toString(), exam: (e['exam'] ?? '').toString(), mine: true),
  ];
}

List<CaseTemplate> templatesFor(String specialty) => [...builtInTemplatesFor(specialty), ...userTemplatesFor(specialty)];

Future<void> saveUserTemplate(String specialty, String label, {String hpi = '', String exam = ''}) async {
  final all = store.settings['userTemplates'];
  final map = all is Map ? Map<String, dynamic>.from(all) : <String, dynamic>{};
  final list = map[specialty] is List ? List<dynamic>.from(map[specialty] as List) : <dynamic>[];
  list.removeWhere((e) => e is Map && e['label'] == label);
  list.add({'label': label, 'hpi': hpi, 'exam': exam});
  map[specialty] = list;
  store.settings['userTemplates'] = map;
  await store.saveSettings();
}

Future<void> removeUserTemplate(String specialty, String label) async {
  final all = store.settings['userTemplates'];
  if (all is! Map) return;
  final map = Map<String, dynamic>.from(all);
  final list = map[specialty] is List ? List<dynamic>.from(map[specialty] as List) : <dynamic>[];
  list.removeWhere((e) => e is Map && e['label'] == label);
  map[specialty] = list;
  store.settings['userTemplates'] = map;
  await store.saveSettings();
}
