import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'data.dart';

/// Selectable documentation vocabulary per specialty (assets/data/choices.json) and the rules that resolve it.
/// An untouched step means "not documented": nothing is ever filled in, assumed normal or turned into a diagnosis.

class ChOption {
  final String v;
  final bool exclusive;
  final Map<String, List<ChOption>> next;
  const ChOption(this.v, this.exclusive, this.next);

  factory ChOption.fromJson(Map j) => ChOption(
        '${j['v']}',
        j['exclusive'] == true,
        {
          for (final e in ((j['next'] as Map?) ?? const {}).entries)
            '${e.key}': [for (final o in ((e.value as Map)['options'] as List? ?? const [])) ChOption.fromJson(o as Map)]
        },
      );
}

class ChStep {
  final String id, label, section;
  final bool multi;
  final List<String> dependsOn;
  final List<ChOption> options;
  final String detailsLabel;
  const ChStep(this.id, this.label, this.section, this.multi, this.dependsOn, this.options, this.detailsLabel);

  factory ChStep.fromJson(Map j) => ChStep(
        '${j['id']}',
        '${j['label']}',
        '${j['section']}',
        j['type'] == 'multi',
        [for (final x in (j['dependsOn'] as List? ?? const [])) '$x'],
        [for (final o in (j['options'] as List? ?? const [])) ChOption.fromJson(o as Map)],
        '${((j['details'] as Map?) ?? const {})['label'] ?? 'Details'}',
      );
}

class ChTemplate {
  final String id, specialty;
  final List<String> aliases;
  final List<ChStep> steps;
  const ChTemplate(this.id, this.specialty, this.aliases, this.steps);

  ChStep? step(String id) {
    for (final s in steps) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// What the user chose in one step.
class ChPick {
  final List<String> v;
  final String details;
  final Map<String, String> optionDetails;
  const ChPick(this.v, this.details, this.optionDetails);
}

class ChResolved {
  final Map<String, List<ChOption>> options;
  ChResolved(this.options);
}

class ChoicesRepo {
  static const int schema = 1;
  static List<ChTemplate> _all = const [];
  static String reviewStatus = '';
  static bool loaded = false;

  static Future<void> load() async {
    if (loaded) return;
    final j = jsonDecode(await rootBundle.loadString('assets/data/choices.json')) as Map;
    parse(j);
  }

  static void parse(Map j) {
    _all = [
      for (final t in j['templates'] as List)
        ChTemplate('${(t as Map)['id']}', '${t['specialty']}', [for (final a in (t['aliases'] as List? ?? const [])) '$a'],
            [for (final s in t['steps'] as List) ChStep.fromJson(s as Map)])
    ];
    reviewStatus = '${((j['meta'] as Map?) ?? const {})['reviewStatus'] ?? ''}';
    loaded = true;
  }

  static const Map<String, String> _appToId = {
    'OB/GYN': 'obstetrics_and_gynecology',
    'Emergency': 'emergency_medicine',
    'ICU': 'intensive_care',
    'Other': 'custom',
  };

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// The template of an app specialty: by id, name or alias; the generic one for anything else.
  static ChTemplate? forSpecialty(String specialty) {
    if (_all.isEmpty) return null;
    final key = _norm(_appToId[specialty] ?? specialty);
    for (final t in _all) {
      if (_norm(t.id) == key || _norm(t.specialty) == key || t.aliases.any((a) => _norm(a) == key)) return t;
    }
    for (final t in _all) {
      if (t.id == 'custom') return t;
    }
    return null;
  }

  static ChTemplate? byId(String id) {
    for (final t in _all) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// The picks of a case, stored as plain data under the case key 'choices':
/// {t: templateId, v: schema, s: {stepId: {v: [..], d: 'details', od: {option: 'details'}}}}.
class CaseChoices {
  final CaseRec rec;
  CaseChoices(this.rec);

  Map<String, dynamic> get _root {
    final v = rec.d['choices'];
    if (v is Map<String, dynamic>) return v;
    final m = <String, dynamic>{};
    if (v is Map) m.addAll(Map<String, dynamic>.from(v));
    rec.d['choices'] = m;
    return m;
  }

  bool get isEmpty {
    final v = rec.d['choices'];
    if (v is! Map) return true;
    final s = v['s'];
    if (s is! Map) return true;
    return s.values.every((e) => e is! Map || (((e['v'] as List?) ?? const []).isEmpty && '${e['d'] ?? ''}'.trim().isEmpty));
  }

  /// The template the picks were made with (kept even if the case specialty changes later), else the specialty's.
  ChTemplate? template() {
    final saved = rec.d['choices'];
    if (saved is Map && saved['t'] != null) {
      final t = ChoicesRepo.byId('${saved['t']}');
      if (t != null) return t;
    }
    return ChoicesRepo.forSpecialty(rec.s('specialty'));
  }

  Map<String, dynamic> _stepMap(String id) {
    final s = (_root['s'] ??= <String, dynamic>{}) as Map;
    final m = s[id];
    if (m is Map<String, dynamic>) return m;
    final n = <String, dynamic>{'v': <String>[], 'd': '', 'od': <String, dynamic>{}};
    if (m is Map) n.addAll(Map<String, dynamic>.from(m));
    s[id] = n;
    return n;
  }

  ChPick pick(String id) {
    final s = (rec.d['choices'] is Map ? (rec.d['choices'] as Map)['s'] : null);
    final m = s is Map ? s[id] : null;
    if (m is! Map) return const ChPick([], '', {});
    return ChPick([for (final x in (m['v'] as List? ?? const [])) '$x'], '${m['d'] ?? ''}',
        {for (final e in ((m['od'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'});
  }

  void _stamp(ChTemplate t) {
    final r = _root;
    r['t'] = t.id;
    r['v'] = ChoicesRepo.schema;
  }

  void setValues(ChTemplate t, String id, List<String> v) {
    _stamp(t);
    _stepMap(id)['v'] = List<String>.from(v);
  }

  void setDetails(ChTemplate t, String id, String text) {
    _stamp(t);
    _stepMap(id)['d'] = text;
  }

  void setOptionDetails(ChTemplate t, String id, String option, String text) {
    _stamp(t);
    final od = (_stepMap(id)['od'] ??= <String, dynamic>{}) as Map;
    if (text.trim().isEmpty) {
      od.remove(option);
    } else {
      od[option] = text;
    }
  }

  /// Options of every step after applying the branches of the active selections, in step order. A branch only
  /// replaces the option list of a later step; it never selects anything.
  Map<String, List<ChOption>> resolve(ChTemplate t) {
    final opts = {for (final s in t.steps) s.id: s.options};
    for (final s in t.steps) {
      for (final v in pick(s.id).v) {
        for (final o in opts[s.id]!) {
          if (o.v != v) continue;
          o.next.forEach((target, list) {
            if (opts.containsKey(target)) opts[target] = list;
          });
        }
      }
    }
    return opts;
  }

  /// A step is open once every step it depends on has some selection ("Not assessed" and "Other" count).
  bool enabled(ChTemplate t, ChStep s) => s.dependsOn.every((d) => pick(d).v.isNotEmpty);

  /// Selected values that are no longer offered (a parent changed): kept and flagged, never removed silently.
  List<String> stale(ChStep s, List<ChOption> options) {
    final have = {for (final o in options) o.v};
    return [for (final v in pick(s.id).v) if (!have.contains(v)) v];
  }

  /// Toggles [v] in [step]. Returns false when an exclusive option would clear other choices and [confirmed] is false.
  bool toggle(ChTemplate t, ChStep s, List<ChOption> options, String v, {bool confirmed = false}) {
    final cur = pick(s.id).v;
    ChOption? opt;
    for (final o in options) {
      if (o.v == v) opt = o;
    }
    if (cur.contains(v)) {
      setValues(t, s.id, [for (final x in cur) if (x != v) x]);
      return true;
    }
    if (!s.multi) {
      setValues(t, s.id, [v]);
      return true;
    }
    final exclusiveNow = {for (final o in options) if (o.exclusive) o.v};
    if (opt != null && opt.exclusive) {
      if (cur.isNotEmpty && !confirmed) return false;
      setValues(t, s.id, [v]);
      return true;
    }
    setValues(t, s.id, [for (final x in cur) if (!exclusiveNow.contains(x)) x, v]);
    return true;
  }

  /// Readable lines for the PDF and summaries of one section: [label, selections, details]. Steps whose answer lives
  /// elsewhere (disposition, the tests list, the plan list, the diagnosis fields) only show an explicit
  /// "Not assessed" / "Unable to assess".
  List<List<String>> lines({String? section}) {
    final t = template();
    if (t == null) return const [];
    const moved = {...kChoiceAdders, 'assessment', 'diagnostic_certainty'};
    final out = <List<String>>[];
    for (final s in t.steps) {
      if (section != null && s.section != section) continue;
      if (kChoiceHidden.contains(s.id)) continue;
      final p = pick(s.id);
      var vals = p.v;
      if (moved.contains(s.id)) vals = [for (final v in vals) if (v == 'Not assessed' || v == 'Unable to assess') v];
      final details = moved.contains(s.id) && vals.isEmpty ? '' : p.details.trim();
      if (vals.isEmpty && details.isEmpty) continue;
      final shown = [for (final v in vals) p.optionDetails[v]?.trim().isNotEmpty == true ? '$v (${p.optionDetails[v]!.trim()})' : v];
      out.add([s.label, shown.join(', '), details]);
    }
    return out;
  }
}

/// Steps that duplicate something the case already has. They are not shown as plain choices:
/// - disposition: the Disposition chips of the Management tab already do this.
/// - investigations / management: choosing a test or action ADDS it to the case's own list (status/author stay blank
///   for you to set), so nothing is written twice.
/// - assessment + diagnostic_certainty: fill the working / final / differential fields (see [ChoicesSync]).
const Set<String> kChoiceHidden = {'disposition', 'investigation_status'};
const Set<String> kChoiceAdders = {'investigations', 'management'};

/// Writes what the picks mean into the case's own fields, but only into fields that are empty or still hold the
/// value written here earlier, so anything typed by the user is never overwritten.
class ChoicesSync {
  /// Fields filled from choices: key -> last value written here.
  static Map<String, dynamic> _auto(CaseRec rec) {
    final v = rec.d['choicesAuto'];
    if (v is Map<String, dynamic>) return v;
    final m = <String, dynamic>{};
    if (v is Map) m.addAll(Map<String, dynamic>.from(v));
    rec.d['choicesAuto'] = m;
    return m;
  }

  static bool _put(CaseRec rec, String key, String value, void Function(String, String) write) {
    final auto = _auto(rec);
    final cur = rec.s(key).trim();
    final last = '${auto[key] ?? ''}'.trim();
    if (cur.isNotEmpty && cur != last) return false; // typed by the user: keep
    if (cur == value.trim()) {
      auto[key] = value;
      return false;
    }
    write(key, value);
    auto[key] = value;
    return true;
  }

  static List<String> _real(CaseChoices cc, ChTemplate t, String id) {
    final step = t.step(id);
    if (step == null) return const [];
    final exclusive = {for (final o in step.options) if (o.exclusive) o.v};
    // options of the current branch, to also catch exclusives of an overridden list
    final res = cc.resolve(t)[id] ?? step.options;
    for (final o in res) {
      if (o.exclusive) exclusive.add(o.v);
    }
    return [for (final v in cc.pick(id).v) if (!exclusive.contains(v) && v != 'Other') v];
  }

  /// assessment + diagnostic_certainty -> ddx / workingDx / finalDx; red_flags -> redFlags.
  /// [write] stores the value in the case and in its text field. Returns true when anything changed.
  static bool derive(CaseRec rec, void Function(String key, String value) write) {
    final t = CaseChoices(rec).template();
    if (t == null) return false;
    final cc = CaseChoices(rec);
    var changed = false;
    final dx = _real(cc, t, 'assessment');
    final other = cc.pick('assessment').optionDetails['Other']?.trim() ?? '';
    final list = [...dx, if (cc.pick('assessment').v.contains('Other') && other.isNotEmpty) other];
    if (list.isNotEmpty) {
      final certainty = cc.pick('diagnostic_certainty').v.where((v) => const {'Suspected', 'Provisional', 'Confirmed', 'Not established'}.contains(v)).toList();
      final c = certainty.isEmpty ? '' : certainty.first;
      changed |= _put(rec, 'ddx', list.join('\n'), write);
      if (c == 'Confirmed') {
        changed |= _put(rec, 'finalDx', list.first, write);
      } else if (c == 'Suspected' || c == 'Provisional') {
        changed |= _put(rec, 'workingDx', list.first, write);
      }
    }
    final flags = _real(cc, t, 'red_flags').where((v) => !const {'None reported', 'Not assessed', 'Unable to assess'}.contains(v)).toList();
    if (flags.isNotEmpty) changed |= _put(rec, 'redFlags', flags.join('\n'), write);
    return changed;
  }

  /// The tests / actions the user picked from the list that are not yet in the case's own list: added with the
  /// status and author left for the user to set. Returns the number added.
  static int addTests(CaseRec rec, List<String> names) {
    final inv = rec.lst('inv');
    var n = 0;
    for (final name in names) {
      if (inv.any((e) => '${e['name']}'.toLowerCase() == name.toLowerCase())) continue;
      inv.add(<String, dynamic>{'id': 'i${DateTime.now().microsecondsSinceEpoch}$n', 'name': name, 'status': 'Pending', 'requestedBy': '', 'date': fmtDate(DateTime.now()), 'fromChoices': true});
      n++;
    }
    return n;
  }

  static int addPlanItems(CaseRec rec, List<String> items) {
    final list = rec.lst('mgmt');
    var n = 0;
    for (final it in items) {
      if (list.any((e) => '${e['text']}'.toLowerCase() == it.toLowerCase())) continue;
      list.add(<String, dynamic>{'id': 'm${DateTime.now().microsecondsSinceEpoch}$n', 'text': it, 'state': '', 'by': '', 'fromChoices': true});
      n++;
    }
    return n;
  }
}
