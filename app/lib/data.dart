import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'privacy.dart' show stripJpegMetadata;
import 'secure_kv.dart';
import 'templates_data.dart' show kSpecialtyFieldsExtra;
import 'ai/ai_store.dart' show AiStore;

import 'i18n.dart';
import 'motion.dart' show motionOn;

typedef J = Map<String, dynamic>;

/// Version of the file format written by this build of the app.
const int kSchema = 2;
const String kAppVersion = '3.1.0';

// ---------------------------------------------------------------- constants

const List<List<String>> kSpecialties = [
  ['Internal Medicine', 'MED'],
  ['General Surgery', 'SUR'],
  ['Pediatrics', 'PED'],
  ['OB/GYN', 'OBG'],
  ['Emergency', 'EM'],
  ['ICU', 'ICU'],
  ['Orthopedics', 'ORT'],
  ['Family Medicine', 'FAM'],
  ['Neurology', 'NEU'],
  ['Psychiatry', 'PSY'],
  ['ENT', 'ENT'],
  ['Ophthalmology', 'OPH'],
  ['Dermatology', 'DER'],
  ['Urology', 'URO'],
  ['Anesthesia', 'ANE'],
  ['Cardiology', 'CAR'],
  ['Other', 'OTH'],
];

List<String> get kSpecialtyNames => kSpecialties.map((e) => e[0]).toList();

String prefixFor(String name) {
  for (final s in kSpecialties) {
    if (s[0] == name) return s[1];
  }
  return 'OTH';
}

// Extra history fields shown per specialty: [key, label]
/// Built-in fields first, then the data-driven ones (see templates_data.dart).
List<List<String>>? specialtyFieldsFor(String specialty) => kSpecialtyFields[specialty] ?? kSpecialtyFieldsExtra[specialty];

const Map<String, List<List<String>>> kSpecialtyFields = {
  'Pediatrics': [
    ['pedsBirth', 'Birth & neonatal history'],
    ['pedsGrowth', 'Growth (weight / height / percentiles)'],
    ['pedsDev', 'Developmental milestones'],
    ['pedsFeed', 'Feeding / diet'],
    ['pedsVacc', 'Vaccination status'],
  ],
  'OB/GYN': [
    ['obGPA', 'G / P / A'],
    ['obLmp', 'LMP / EDD / gestational age'],
    ['obHx', 'Obstetric & gynecologic history'],
    ['obContra', 'Contraception'],
  ],
  'General Surgery': [
    ['surLastMeal', 'Last meal / NPO status'],
    ['surAnes', 'Previous anesthesia / complications'],
  ],
  'Anesthesia': [
    ['surLastMeal', 'Last meal / NPO status'],
    ['surAnes', 'Previous anesthesia / complications'],
  ],
  'Orthopedics': [
    ['ortMech', 'Mechanism of injury'],
    ['ortNV', 'Neurovascular status'],
    ['ortClass', 'Fracture / injury classification'],
  ],
  'Neurology': [
    ['neuGcs', 'GCS / level of consciousness'],
    ['neuCn', 'Cranial nerves'],
    ['neuMotor', 'Power / tone / reflexes'],
    ['neuSens', 'Sensation / coordination'],
  ],
  'Psychiatry': [
    ['psyMse', 'Mental state examination'],
    ['psyRisk', 'Risk assessment'],
  ],
};

const List<String> kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
const List<String> kWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const List<String> kLearningKeys = [
  'initialDx', 'whatChanged', 'learned', 'mistakes', 'questions', 'refs', 'teaching',
];

// ---------------------------------------------------------------- helpers

String two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String todayStr() => fmtDate(DateTime.now());
String nowIso() => DateTime.now().toUtc().toIso8601String();

DateTime? parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

String prettyDate(String s) {
  final d = parseDate(s);
  if (d == null) return s;
  return '${weekdayName(d.weekday - 1)} ${d.day} ${monthName(d.month - 1)} ${d.year}';
}

String newId(String prefix) {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = Random().nextInt(46656).toRadixString(36);
  return '$prefix$t$r';
}

/// Educational highlighting only. Adult ranges. RBS is assumed to be mg/dL.
bool vitalAbnormal(String key, String raw, bool adult) {
  if (!adult) return false;
  final s = raw.trim();
  if (s.isEmpty) return false;
  if (key == 'v_bp') {
    final p = s.split('/');
    if (p.length != 2) return false;
    final a = double.tryParse(p[0].trim());
    final b = double.tryParse(p[1].trim());
    if (a == null || b == null) return false;
    return a >= 140 || b >= 90 || a < 90;
  }
  final v = double.tryParse(s.replaceAll(',', '.'));
  if (v == null) return false;
  switch (key) {
    case 'v_hr':
      return v > 100 || v < 60;
    case 'v_temp':
      return v >= 38 || v < 36;
    case 'v_rr':
      return v > 20 || v < 12;
    case 'v_spo2':
      return v < 94;
    case 'v_rbs':
      // below 40 the value is almost certainly mmol/L, otherwise mg/dL
      if (v < 40) return v > 11.1 || v < 3.9;
      return v > 200 || v < 70;
    default:
      return false;
  }
}

class MedLogError implements Exception {
  final String message;
  MedLogError(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------- case record

class CaseRec {
  final J d;
  CaseRec(this.d);

  String get id => d['id'].toString();

  String s(String k) => (d[k] ?? '').toString();

  void set(String k, dynamic v) {
    d[k] = v;
  }

  List<J> lst(String k) {
    final v = d[k];
    if (v is List<J>) return v;
    final out = <J>[];
    if (v is List) {
      for (final e in v) {
        out.add(Map<String, dynamic>.from(e as Map));
      }
    }
    d[k] = out;
    return out;
  }

  List<String> get tags {
    final v = d['tags'];
    if (v is List) return v.map((e) => e.toString()).toList();
    return <String>[];
  }

  set tags(List<String> v) {
    d['tags'] = v;
  }

  bool get starred => d['starred'] == true;
  bool get review => d['review'] == true;
  bool get shared => d['shared'] == true;

  String get title {
    for (final k in ['finalDx', 'workingDx', 'cc']) {
      final v = s(k).trim();
      if (v.isNotEmpty) return v;
    }
    return '(no diagnosis yet)';
  }
}

// ---------------------------------------------------------------- search language

/// Search language (all words are combined with AND, prefix a word with - to exclude):
///   plain words        anywhere in the case
///   #rare              tag
///   dx:pneumonia       diagnosis / DDx          (use _ for spaces: dx:heart_failure)
///   cc: spec: status: role: setting: code: by: age: date: tag: learn:
///   has:image has:pending has:allergy has:question has:plan has:progress
///   is:starred is:review is:shared is:draft
bool matchesQuery(CaseRec c, String raw) {
  final q = raw.trim().toLowerCase();
  if (q.isEmpty) return true;
  final hay = [
    c.s('code'), c.s('initials'), c.s('cc'), c.s('hpi'), c.s('pmh'), c.s('workingDx'),
    c.s('finalDx'), c.s('ddx'), c.s('specialty'), c.s('learned'), c.s('problems'),
    c.s('reasoning'), c.s('author'), c.tags.join(' '),
    c.lst('inv').map((e) => (e['name'] ?? '').toString()).join(' '),
    c.lst('mgmt').map((e) => (e['text'] ?? '').toString()).join(' '),
  ].join(' ').toLowerCase();

  for (final tok in q.split(RegExp(r'\s+'))) {
    if (tok.isEmpty) continue;
    var t = tok;
    var neg = false;
    if (t.startsWith('-') && t.length > 1) {
      neg = true;
      t = t.substring(1);
    }
    final ok = _tokenMatches(c, t, hay);
    if (neg ? ok : !ok) return false;
  }
  return true;
}

bool _tokenMatches(CaseRec c, String t, String hay) {
  if (t.startsWith('#')) {
    final v = t.substring(1);
    return c.tags.any((x) => x.toLowerCase().contains(v));
  }
  final i = t.indexOf(':');
  if (i > 0) {
    final k = t.substring(0, i);
    final v = t.substring(i + 1).replaceAll('_', ' ');
    if (v.isEmpty) return true;
    switch (k) {
      case 'dx':
        return '${c.s('finalDx')} ${c.s('workingDx')} ${c.s('ddx')}'.toLowerCase().contains(v);
      case 'tag':
        return c.tags.any((x) => x.toLowerCase().contains(v));
      case 'spec':
        return c.s('specialty').toLowerCase().contains(v) ||
            prefixFor(c.s('specialty')).toLowerCase() == v;
      case 'status':
        return c.s('status').toLowerCase().startsWith(v);
      case 'role':
        return c.s('role').toLowerCase().startsWith(v);
      case 'setting':
        return c.s('setting').toLowerCase().startsWith(v);
      case 'date':
        return c.s('date').startsWith(v);
      case 'code':
        return c.s('code').toLowerCase().contains(v);
      case 'cc':
        return c.s('cc').toLowerCase().contains(v);
      case 'age':
        return c.s('ageGroup').toLowerCase().startsWith(v);
      case 'by':
        return c.s('author').toLowerCase().contains(v);
      case 'learn':
        return c.s('learned').toLowerCase().contains(v);
      case 'has':
        switch (v) {
          case 'image':
          case 'images':
            return c.lst('images').isNotEmpty;
          case 'pending':
            return c.lst('inv').any((e) => e['status'] == 'Pending');
          case 'allergy':
            final al = c.s('allergies').trim().toLowerCase();
            return al.isNotEmpty && !const ['nkda', 'none', 'no', 'nka'].contains(al);
          case 'question':
            return c.s('questions').trim().isNotEmpty;
          case 'plan':
            return c.lst('mgmt').isNotEmpty;
          case 'progress':
            return c.lst('progress').isNotEmpty;
          default:
            return false;
        }
      case 'is':
        switch (v) {
          case 'starred':
            return c.starred;
          case 'review':
            return c.review;
          case 'shared':
            return c.shared;
          case 'draft':
            return c.s('status') == 'Draft';
          default:
            return false;
        }
      default:
        return hay.contains(t);
    }
  }
  return hay.contains(t);
}

// ---------------------------------------------------------------- import plan

class ImportPlan {
  final bool isPack;
  final String author;
  final List<J> cases = [];
  final Map<String, List<int>> images = {};
  final Map<String, List<J>> lists = {};
  int newCases = 0;
  int updatedCases = 0;
  int unchanged = 0;
  ImportPlan(this.isPack, this.author);

  bool get empty => cases.isEmpty && images.isEmpty && lists.isEmpty;
}

// ---------------------------------------------------------------- store

final AppStore store = AppStore();

class AppStore extends ChangeNotifier {
  late Directory root;
  late Directory casesDir;
  late Directory imagesDir;

  List<J> rotations = [];
  List<J> shifts = [];
  List<J> procedures = [];
  List<J> notes = [];
  List<J> inbox = []; // clinical questions inbox
  /// Smaller collections that all behave the same way (one JSON list each).
  static const List<String> kExtraLists = [
    'replays', 'feedback', 'tasks', 'pearls', 'achievements', 'reflections', 'qi',
    'evidence', 'assessments', 'skillgoals', 'imaging', 'review', 'scenarios', 'encounters',
    'libfav', 'libnotes', 'libcards', 'quizlog',
    // AI study layer: question bank + logs, viva sessions, guideline checks, gradings, weak-spot memory, lessons, case of the day
    'aiquiz', 'aiquizlog', 'aiquizflags', 'aiviva', 'aichats', 'aigcheck', 'aigrade', 'aiweak', 'aiteach', 'aicod',
  ];
  final Map<String, List<J>> extra = {for (final n in kExtraLists) n: <J>[]};
  List<J> listOf(String name) => extra[name] ?? (extra[name] = <J>[]);
  List<J> get replays => listOf('replays');
  List<J> get feedback => listOf('feedback');
  int rev = 0; // bumped on every change, lets search indexes know when to rebuild
  final List<String> healthLog = [];
  J settings = <String, dynamic>{};
  final Map<String, CaseRec> cases = {};

  bool ready = false;
  bool locked = false;

  static const MethodChannel _ch = MethodChannel('medlog/secure');
  static const List<int> _magic = [0x4D, 0x4C, 0x42, 0x31]; // "MLB1"

  static final Map<String, String> _listKeys = {
    'rotations.json': 'id',
    'shifts.json': 'date',
    'procedures.json': 'id',
    'notes.json': 'id',
    'questions.json': 'id',
    for (final n in kExtraLists) '$n.json': 'id',
  };

  @override
  void notifyListeners() {
    rev++;
    super.notifyListeners();
  }

  Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    root = Directory('${base.path}/medlog');
    casesDir = Directory('${root.path}/cases');
    imagesDir = Directory('${root.path}/images');
    await casesDir.create(recursive: true);
    await imagesDir.create(recursive: true);

    rotations = await _readList('rotations.json');
    shifts = await _readList('shifts.json');
    procedures = await _readList('procedures.json');
    notes = await _readList('notes.json');
    inbox = await _readList('questions.json');
    for (final n in kExtraLists) {
      extra[n] = await _readList('$n.json');
    }
    settings = await _readMap('settings.json');

    var settingsChanged = false;
    if ((settings['deviceId'] ?? '').toString().isEmpty) {
      settings['deviceId'] = newId('d');
      settingsChanged = true;
    }
    if (settingsChanged) await saveSettings();
    _applyLook();
    await _loadPin();
    try {
      await AiStore.load(); // optional AI layer: preferences + key (never part of backups)
    } catch (_) {}

    cases.clear();
    for (final f in casesDir.listSync()) {
      if (f is File && f.path.endsWith('.json')) {
        final m = await _readJson(f);
        if (m is Map) {
          final rec = CaseRec(Map<String, dynamic>.from(m));
          cases[rec.id] = rec;
          if (_migrateCase(rec)) {
            await _write(f, jsonEncode(rec.d));
          }
        }
      }
    }
    await _write(
      File('${root.path}/manifest.json'),
      jsonEncode(<String, dynamic>{
        'app': 'medlog',
        'schema': kSchema,
        'version': kAppVersion,
        'written': nowIso(),
      }),
    );
    locked = hasPin;
    ready = true;
    notifyListeners();
  }

  /// Upgrades an older case file in place. Returns true if it changed.
  bool _migrateCase(CaseRec c) {
    final v = c.d['schema'];
    final cur = v is int ? v : 1;
    if (cur >= kSchema) return false;
    // v1 -> v2: nothing to move; new optional fields simply start empty.
    c.d['schema'] = kSchema;
    return true;
  }

  void refresh() => notifyListeners();

  // ------------------------------------------------------------ file io

  /// Reads one JSON file. If it is damaged, the previous copy (.bak) is tried;
  /// a file that cannot be read at all is moved to corrupt/ so nothing is lost silently.
  Future<dynamic> _readJson(File f) async {
    if (!await f.exists()) {
      final bak = File('${f.path}.bak');
      if (!await bak.exists()) return null;
    }
    for (final candidate in [f, File('${f.path}.bak')]) {
      try {
        if (!await candidate.exists()) continue;
        final v = jsonDecode(await candidate.readAsString());
        if (candidate.path.endsWith('.bak')) {
          healthLog.add('Recovered ${f.uri.pathSegments.last} from its backup copy');
          try {
            await candidate.copy(f.path);
          } catch (_) {}
        }
        return v;
      } catch (_) {}
    }
    try {
      final dir = Directory('${root.path}/corrupt');
      await dir.create(recursive: true);
      await f.copy('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${f.uri.pathSegments.last}');
      healthLog.add('Could not read ${f.uri.pathSegments.last}; a copy was kept in corrupt/');
    } catch (_) {}
    return null;
  }

  Future<List<J>> _readList(String name) async {
    final v = await _readJson(File('${root.path}/$name'));
    if (v is List) {
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return <J>[];
  }

  Future<J> _readMap(String name) async {
    final v = await _readJson(File('${root.path}/$name'));
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  /// Atomic write: write to a temp file, then rename over the target.
  ///
  /// Every write uses its own temporary file name and carries a sequence number:
  /// two saves started together can never share a temp file, and an older save
  /// that finishes late never overwrites a newer one.
  final Map<String, int> _wSeq = {};
  final Map<String, int> _wDone = {};

  Future<void> _write(File f, String content) async {
    final n = (_wSeq[f.path] ?? 0) + 1;
    _wSeq[f.path] = n;
    final tmp = File('${f.path}.$n.tmp');
    await tmp.writeAsString(content, flush: true);
    if ((_wDone[f.path] ?? 0) > n) {
      try {
        await tmp.delete();
      } catch (_) {}
      return; // a newer save already finished
    }
    // keep the previous good copy so a damaged write can be recovered
    try {
      if (await f.exists()) await f.copy('${f.path}.bak');
    } catch (_) {}
    if ((_wDone[f.path] ?? 0) > n) {
      try {
        await tmp.delete();
      } catch (_) {}
      return;
    }
    await tmp.rename(f.path);
    _wDone[f.path] = n;
  }

  /// Re-reads every data file and reports what is healthy. Used by Settings > Data health.
  Future<Map<String, int>> verifyData() async {
    var ok = 0, bad = 0, files = 0;
    final list = <File>[
      for (final e in root.listSync(recursive: true))
        if (e is File && e.path.endsWith('.json')) e
    ];
    for (final f in list) {
      if (f.path.contains('/corrupt/')) continue;
      files++;
      try {
        jsonDecode(await f.readAsString());
        ok++;
      } catch (_) {
        bad++;
        await _readJson(f); // tries the .bak copy and logs
      }
    }
    return {'files': files, 'ok': ok, 'bad': bad, 'cases': cases.length, 'images': imagesDir.listSync().length};
  }

  /// Saves one of the extra lists and tells listeners.
  Future<void> saveExtra(String name) async {
    await saveList('$name.json', listOf(name));
    notifyListeners();
  }

  Future<void> upsertExtra(String name, J item, {String key = 'id'}) async {
    item['updated'] = nowIso();
    final l = listOf(name);
    final i = l.indexWhere((e) => e[key] == item[key]);
    if (i >= 0) {
      l[i] = item;
    } else {
      l.add(item);
    }
    await saveExtra(name);
  }

  Future<void> removeExtra(String name, String id, {String key = 'id'}) async {
    listOf(name).removeWhere((e) => e[key] == id);
    await saveExtra(name);
  }

  Future<void> saveList(String name, List<J> data) =>
      _write(File('${root.path}/$name'), jsonEncode(data));

  Future<void> saveSettings() =>
      _write(File('${root.path}/settings.json'), jsonEncode(settings));

  // ------------------------------------------------------------ generic list ops

  Future<void> upsert(List<J> list, String file, J item, {String key = 'id'}) async {
    item['updated'] = nowIso();
    final i = list.indexWhere((e) => e[key] == item[key]);
    if (i >= 0) {
      list[i] = item;
    } else {
      list.add(item);
    }
    await saveList(file, list);
    notifyListeners();
  }

  Future<void> removeFrom(List<J> list, String file, String value, {String key = 'id'}) async {
    list.removeWhere((e) => e[key] == value);
    await saveList(file, list);
    notifyListeners();
  }

  // ------------------------------------------------------------ settings shortcuts

  String get author => (settings['author'] ?? '').toString();
  String get deviceId => (settings['deviceId'] ?? '').toString();
  bool get useInitials => settings['useInitials'] == true;

  Future<void> setAuthor(String v) async {
    settings['author'] = v.trim();
    await saveSettings();
    notifyListeners();
  }

  // ------------------------------------------------------------ look & language

  /// 'system' (follow the phone), 'en' or 'ar'.
  String get lang => (settings['lang'] ?? kLangSystem).toString();
  /// 'en' (default): medical terms stay English in the Arabic app. 'ar': translated.
  String get medLang => (settings['medLang'] ?? 'en').toString();
  double get libFontScale => ((settings['libFont'] as num?)?.toDouble() ?? 1.0).clamp(0.85, 1.5);
  bool get libShowImages => settings['libImages'] != false;
  bool get libShowTables => settings['libTables'] != false;
  /// Study sheet look: 0 Plain, 1 Light (default), 2 Rich.
  int get libSheetStyle => ((settings['libSheetStyle'] as num?)?.toInt() ?? 1).clamp(0, 2);
  /// 'Larger and bolder text' in the library articles.
  bool get libBold => settings['libBold'] == true;
  /// Combine several installed sources of the same condition into one sheet.
  bool get libCombined => settings['libCombined'] != false;
  /// Picture captions under article images and tables.
  bool get libCaptions => settings['libCaptions'] != false;
  /// Concise sources (WikEM, Tulip, CDC) before long articles in search.
  bool get libConcise => settings['libConcise'] != false;
  /// Search inside the article text (full text index).
  bool get libBodySearch => settings['libBody'] != false;
  bool get libOnlineImages => settings['libOnline'] != false;
  String get paletteId => (settings['palette'] ?? 'clinic').toString();

  /// 'system', 'light' or 'dark'.
  String get themeMode => (settings['themeMode'] ?? 'system').toString();
  bool get amoled => settings['amoled'] == true;
  String get fontAr => (settings['fontAr'] ?? 'cairo').toString();
  String get fontEn => (settings['fontEn'] ?? 'tinos').toString();
  bool get motion => settings['motion'] != false;
  double get textScale => (settings['textScale'] is num) ? (settings['textScale'] as num).toDouble() : 1.0;

  /// 'shift' (fast, minimal) or 'study' (review and practice).
  String get mode => (settings['mode'] ?? 'shift').toString();
  bool get packsAuto => settings['packsAuto'] != false;

  /// Remembers the last choices made for a field so pickers can offer them first.
  List<String> recentsFor(String key) {
    final r = settings['recents'];
    if (r is Map && r[key] is List) return (r[key] as List).map((e) => e.toString()).toList();
    return <String>[];
  }

  void noteUse(String key, String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    final r = settings['recents'] is Map
        ? Map<String, dynamic>.from(settings['recents'] as Map)
        : <String, dynamic>{};
    final l = (r[key] is List ? (r[key] as List).map((e) => e.toString()).toList() : <String>[])
      ..remove(v)
      ..insert(0, v);
    r[key] = l.take(8).toList();
    settings['recents'] = r;
    saveSettings();
  }

  void _applyLook() {
    setLangSetting(lang);
    setMedEnglish(medLang != 'ar');
    motionOn = motion;
  }

  Future<void> setLook(String key, Object value) async {
    settings[key] = value;
    _applyLook();
    await saveSettings();
    notifyListeners();
  }

  Future<void> setUseInitials(bool v) async {
    settings['useInitials'] = v;
    await saveSettings();
    notifyListeners();
  }

  int? get daysSinceBackup {
    final s = (settings['lastBackup'] ?? '').toString();
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    return DateTime.now().difference(d.toLocal()).inDays;
  }

  // ------------------------------------------------------------ rotations & shifts

  J? rotationById(String id) {
    for (final r in rotations) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  String rotationLabel(J r) {
    final h = (r['hospital'] ?? '').toString();
    final n = tr((r['name'] ?? '').toString());
    return h.isEmpty ? n : '$n • $h';
  }

  J? currentRotation() {
    final t = todayStr();
    J? best;
    for (final r in rotations) {
      final s = (r['start'] ?? '').toString();
      final e = (r['end'] ?? '').toString();
      if (s.isEmpty) continue;
      if (s.compareTo(t) <= 0 && (e.isEmpty || e.compareTo(t) >= 0)) {
        if (best == null || s.compareTo(best['start'].toString()) > 0) best = r;
      }
    }
    if (best != null) return best;
    for (final r in rotations) {
      final s = (r['start'] ?? '').toString();
      if (s.isEmpty || s.compareTo(t) > 0) continue;
      if (best == null || s.compareTo(best['start'].toString()) > 0) best = r;
    }
    if (best != null) return best;
    return rotations.isEmpty ? null : rotations.last;
  }

  J? shiftFor(String date) {
    for (final s in shifts) {
      if (s['date'] == date) return s;
    }
    return null;
  }

  // ------------------------------------------------------------ cases

  List<CaseRec> casesSorted() {
    final l = cases.values.toList();
    l.sort((a, b) {
      final c = b.s('date').compareTo(a.s('date'));
      if (c != 0) return c;
      return b.s('created').compareTo(a.s('created'));
    });
    return l;
  }

  List<CaseRec> casesOfRotation(String rotationId) =>
      cases.values.where((c) => c.s('rotationId') == rotationId).toList();

  String nextCode(String prefix) {
    var maxN = 0;
    for (final c in cases.values) {
      final code = c.s('code');
      if (code.startsWith('$prefix-')) {
        final n = int.tryParse(code.substring(prefix.length + 1)) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    return '$prefix-${(maxN + 1).toString().padLeft(4, '0')}';
  }

  CaseRec newCase() {
    final rot = currentRotation();
    final spec = (rot == null ? 'Internal Medicine' : rot['name']).toString();
    final c = CaseRec(<String, dynamic>{
      'id': newId('c'),
      'schema': kSchema,
      'created': nowIso(),
      'date': todayStr(),
      'specialty': spec,
      'rotationId': rot == null ? '' : rot['id'].toString(),
      'status': 'Draft',
      'author': author,
      'origin': deviceId,
    });
    c.d['code'] = nextCode(prefixFor(spec));
    return c;
  }

  Future<void> saveCase(CaseRec c, {bool notify = true}) async {
    c.d['updated'] = nowIso();
    cases[c.id] = c;
    await _write(File('${casesDir.path}/${c.id}.json'), jsonEncode(c.d));
    if (notify) notifyListeners();
  }

  Future<void> deleteCase(CaseRec c) async {
    for (final img in c.lst('images')) {
      await deleteImageFile(img['file'].toString());
    }
    cases.remove(c.id);
    final f = File('${casesDir.path}/${c.id}.json');
    if (await f.exists()) await f.delete();
    notifyListeners();
  }

  // ------------------------------------------------------------ images

  String imagePath(String name) => '${imagesDir.path}/$name';

  /// Copies a picked image into private storage and removes the temporary
  /// copy that image_picker left in the cache folder.
  Future<String> importImage(String srcPath, String code) async {
    final name = '${code}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    // photos carry hidden data (camera, time, GPS location): remove it before storing
    final raw = await File(srcPath).readAsBytes();
    await File(imagePath(name)).writeAsBytes(stripJpegMetadata(raw), flush: true);
    try {
      if (srcPath.contains('/cache/')) await File(srcPath).delete();
    } catch (_) {}
    return name;
  }

  Future<void> deleteImageFile(String name) async {
    try {
      final f = File(imagePath(name));
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ------------------------------------------------------------ PIN & screen security

  String _pinSalt = '';
  String _pinHash = '';

  bool get hasPin => _pinHash.isNotEmpty;

  /// The PIN hash lives in the Android Keystore (secure storage). Older versions
  /// kept it in settings.json: it is moved on first start.
  Future<void> _loadPin() async {
    final h = await SecureKv.read('pinHash');
    final sa = await SecureKv.read('pinSalt');
    if (h != null && h.isNotEmpty && sa != null && sa.isNotEmpty) {
      _pinHash = h;
      _pinSalt = sa;
      return;
    }
    final oh = (settings['pinHash'] ?? '').toString();
    final os = (settings['pinSalt'] ?? '').toString();
    if (oh.isNotEmpty && os.isNotEmpty) {
      _pinHash = oh;
      _pinSalt = os;
      if (await SecureKv.write('pinHash', oh) && await SecureKv.write('pinSalt', os)) {
        settings.remove('pinHash');
        settings.remove('pinSalt');
        await saveSettings();
      }
    }
  }
  bool get secureScreen => settings['secure'] != false;

  String _hash(String salt, String pin) =>
      hash.sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final salt = newId('s');
    _pinSalt = salt;
    _pinHash = _hash(salt, pin);
    final ok = await SecureKv.write('pinSalt', _pinSalt) && await SecureKv.write('pinHash', _pinHash);
    if (ok) {
      settings.remove('pinSalt');
      settings.remove('pinHash');
    } else {
      // no Keystore on this device: keep the (salted, hashed) PIN in settings
      settings['pinSalt'] = _pinSalt;
      settings['pinHash'] = _pinHash;
    }
    await saveSettings();
    notifyListeners();
  }

  Future<void> clearPin() async {
    _pinSalt = '';
    _pinHash = '';
    await SecureKv.delete('pinSalt');
    await SecureKv.delete('pinHash');
    settings.remove('pinSalt');
    settings.remove('pinHash');
    await saveSettings();
    notifyListeners();
  }

  bool checkPin(String pin) {
    if (!hasPin) return true;
    return _hash(_pinSalt, pin) == _pinHash;
  }

  void lock() {
    if (hasPin && !locked) {
      locked = true;
      notifyListeners();
    }
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  Future<void> setSecureScreen(bool on) async {
    settings['secure'] = on;
    await saveSettings();
    await applySecure();
    notifyListeners();
  }

  Future<void> applySecure() async {
    try {
      await _ch.invokeMethod('setSecure', <String, dynamic>{'on': secureScreen});
    } catch (_) {}
  }

  // ------------------------------------------------------------ encryption (AES-256-GCM)

  Future<SecretKey> _kdf(String password, List<int> salt) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  bool looksEncrypted(Uint8List b) {
    if (b.length < 4) return false;
    for (var i = 0; i < 4; i++) {
      if (b[i] != _magic[i]) return false;
    }
    return true;
  }

  Future<Uint8List> _seal(List<int> plain, String password) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final key = await _kdf(password, salt);
    final box = await AesGcm.with256bits().encrypt(plain, secretKey: key);
    final out = BytesBuilder();
    out.add(_magic);
    out.add(salt);
    out.add(box.concatenation());
    return out.toBytes();
  }

  Future<List<int>> _open(Uint8List data, String password) async {
    if (data.length < 4 + 16 + 12 + 16) throw MedLogError('This is not a MedLog file.');
    final salt = data.sublist(4, 20);
    final rest = data.sublist(20);
    final key = await _kdf(password, salt);
    final box = SecretBox.fromConcatenation(rest, nonceLength: 12, macLength: 16);
    try {
      return await AesGcm.with256bits().decrypt(box, secretKey: key);
    } catch (_) {
      throw MedLogError('Wrong password, or the file is damaged.');
    }
  }

  Archive _decodeZip(List<int> bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw MedLogError('This file is not a MedLog backup.');
    }
  }

  Future<File> _sealToFile(Archive arc, String password, String fileName) async {
    final data = ZipEncoder().encode(arc);
    final sealed = await _seal(data!, password);
    // verify: decrypt again and make sure every entry is there
    final check = _decodeZip(await _open(sealed, password));
    if (check.length != arc.length) {
      throw MedLogError('Verification failed. Nothing was shared; try again.');
    }
    final tmp = await getTemporaryDirectory();
    final out = File('${tmp.path}/$fileName');
    await out.writeAsBytes(sealed, flush: true);
    return out;
  }

  String _stamp() {
    final d = DateTime.now();
    return '${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}';
  }

  // ------------------------------------------------------------ full backup

  Future<File> exportBackup(String password) async {
    final arc = Archive();
    final prefix = '${root.path}/';
    for (final e in root.listSync(recursive: true)) {
      // downloaded case packs are not backed up: they are fetched again when online
      if (e is File &&
          !e.path.endsWith('.tmp') &&
          !e.path.endsWith('.bak') &&
          !e.path.startsWith('${root.path}/corrupt/') &&
          !e.path.startsWith('${root.path}/packs/')) {
        final rel = e.path.substring(prefix.length);
        if (rel.startsWith('cases/demo_')) continue; // demo data never goes into a backup
        var bytes = await e.readAsBytes();
        if (_listKeys.containsKey(rel)) {
          try {
            final l = (jsonDecode(utf8.decode(bytes)) as List).where((x) => !(x is Map && x['demo'] == true)).toList();
            bytes = Uint8List.fromList(utf8.encode(jsonEncode(l)));
          } catch (_) {}
        }
        arc.addFile(ArchiveFile(rel, bytes.length, bytes));
      }
    }
    final f = await _sealToFile(arc, password, 'MedLog-backup-${_stamp()}.medlogbak');
    settings['lastBackup'] = nowIso();
    await saveSettings();
    notifyListeners();
    return f;
  }

  // ------------------------------------------------------------ case packs (sharing with colleagues)

  /// Opens a backup file again with its password and checks that every case,
  /// image and list inside can be read, and that the counts match what is on the phone.
  Future<Map<String, int>> verifyBackupFile(File f, String password) async {
    final bytes = await f.readAsBytes();
    final zip = looksEncrypted(bytes) ? await _open(bytes, password) : bytes;
    final arc = _decodeZip(zip);
    var nCases = 0, nImages = 0, nLists = 0, bad = 0;
    for (final file in arc) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      final content = file.content as List<int>;
      if (name.startsWith('cases/') && name.endsWith('.json')) {
        try {
          jsonDecode(utf8.decode(content));
          nCases++;
        } catch (_) {
          bad++;
        }
      } else if (name.startsWith('images/')) {
        if (content.isNotEmpty) {
          nImages++;
        } else {
          bad++;
        }
      } else if (_listKeys.containsKey(name)) {
        try {
          jsonDecode(utf8.decode(content));
          nLists++;
        } catch (_) {
          bad++;
        }
      }
    }
    final localImages = imagesDir.listSync().whereType<File>().where((e) => !e.path.endsWith('.tmp')).length;
    return {
      'cases': nCases,
      'images': nImages,
      'lists': nLists,
      'bad': bad,
      'expectCases': cases.values.where((c) => !c.id.startsWith('demo_')).length,
      'expectImages': localImages,
    };
  }

  Future<File> exportPack(
    List<CaseRec> list,
    String password, {
    required bool images,
    required bool learning,
  }) async {
    final arc = Archive();
    final man = utf8.encode(jsonEncode(<String, dynamic>{
      'app': 'medlog',
      'type': 'pack',
      'schema': kSchema,
      'author': author,
      'created': nowIso(),
      'count': list.length,
    }));
    arc.addFile(ArchiveFile('manifest.json', man.length, man));

    for (final c in list) {
      final m = jsonDecode(jsonEncode(c.d)) as Map<String, dynamic>;
      // never leave the phone: initials, personal flags, rotation link
      for (final k in ['initials', 'starred', 'review', 'rotationId']) {
        m.remove(k);
      }
      if (!learning) {
        for (final k in kLearningKeys) {
          m.remove(k);
        }
        m.remove('evo');
      }
      if (!images) m.remove('images');
      if ((m['author'] ?? '').toString().isEmpty) m['author'] = author;
      final bytes = utf8.encode(jsonEncode(m));
      arc.addFile(ArchiveFile('cases/${c.id}.json', bytes.length, bytes));
      if (images) {
        for (final img in c.lst('images')) {
          final f = File(imagePath(img['file'].toString()));
          if (await f.exists()) {
            final b = await f.readAsBytes();
            arc.addFile(ArchiveFile('images/${img['file']}', b.length, b));
          }
        }
      }
    }
    return _sealToFile(arc, password, 'MedLog-cases-${_stamp()}.medlogpack');
  }

  // ------------------------------------------------------------ import: preview, then apply

  Future<ImportPlan> previewImport(Uint8List bytes, {String? password}) async {
    List<int> zipBytes = bytes;
    if (looksEncrypted(bytes)) {
      if (password == null || password.isEmpty) throw MedLogError('Password required.');
      zipBytes = await _open(bytes, password);
    }
    final arc = _decodeZip(zipBytes);

    var isPack = false;
    var packAuthor = '';
    for (final file in arc) {
      if (file.isFile && file.name == 'manifest.json') {
        try {
          final m = jsonDecode(utf8.decode(file.content as List<int>));
          if (m is Map) {
            isPack = m['type'] == 'pack';
            packAuthor = (m['author'] ?? '').toString();
          }
        } catch (_) {}
      }
    }

    final plan = ImportPlan(isPack, packAuthor);
    for (final file in arc) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      if (name.contains('..')) continue;
      final content = file.content as List<int>;

      if (name.startsWith('cases/') && name.endsWith('.json')) {
        try {
          final m = Map<String, dynamic>.from(jsonDecode(utf8.decode(content)) as Map);
          final id = m['id'].toString();
          final cur = cases[id];
          final inc = (m['updated'] ?? '').toString();
          if (cur == null) {
            if (isPack) {
              m['shared'] = true;
              m['rotationId'] = '';
            }
            m['schema'] = kSchema;
            plan.cases.add(m);
            plan.newCases++;
          } else if (isPack && !cur.shared) {
            plan.unchanged++; // never overwrite my own case with a shared copy
          } else if (inc.compareTo(cur.s('updated')) > 0) {
            if (isPack) {
              m['shared'] = true;
              m['rotationId'] = '';
            }
            m['schema'] = kSchema;
            plan.cases.add(m);
            plan.updatedCases++;
          } else {
            plan.unchanged++;
          }
        } catch (_) {}
      } else if (name.startsWith('images/')) {
        final base = name.split('/').last;
        if (base.isEmpty) continue;
        if (!await File(imagePath(base)).exists()) plan.images[base] = content;
      } else if (!isPack && _listKeys.containsKey(name)) {
        try {
          plan.lists[name] = (jsonDecode(utf8.decode(content)) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } catch (_) {}
      }
    }
    return plan;
  }

  Future<String> applyImport(ImportPlan plan) async {
    for (final e in plan.images.entries) {
      await File(imagePath(e.key)).writeAsBytes(e.value);
    }
    for (final m in plan.cases) {
      final rec = CaseRec(m);
      cases[rec.id] = rec;
      await _write(File('${casesDir.path}/${rec.id}.json'), jsonEncode(m));
    }
    for (final e in plan.lists.entries) {
      final key = _listKeys[e.key]!;
      final target = _listFor(e.key);
      for (final item in e.value) {
        final i = target.indexWhere((x) => x[key] == item[key]);
        if (i < 0) {
          target.add(item);
        } else {
          final a = (item['updated'] ?? '').toString();
          final b = (target[i]['updated'] ?? '').toString();
          if (a.compareTo(b) > 0) target[i] = item;
        }
      }
      await saveList(e.key, target);
    }
    notifyListeners();
    return 'Done: ${plan.newCases} new, ${plan.updatedCases} updated, '
        '${plan.images.length} images.';
  }

  List<J> _listFor(String name) {
    switch (name) {
      case 'rotations.json':
        return rotations;
      case 'shifts.json':
        return shifts;
      case 'procedures.json':
        return procedures;
      case 'questions.json':
        return inbox;
      default:
        final n = name.replaceAll('.json', '');
        if (extra.containsKey(n)) return extra[n]!;
        return notes;
    }
  }

  // ------------------------------------------------------------ demo data (to try the app)

  bool get hasDemo =>
      cases.values.any((c) => c.s('id').startsWith('demo_')) ||
      rotations.any((r) => r['demo'] == true);

  /// Fictional records so every screen can be tried without typing real data.
  /// They are marked, kept out of backups and removable with one tap.
  Future<void> loadDemo() async {
    if (hasDemo) return;
    final today = DateTime.now();
    String d(int back) => fmtDate(today.subtract(Duration(days: back)));
    final rot = <String, dynamic>{
      'id': 'demo_r1', 'demo': true, 'name': 'Internal Medicine', 'hospital': 'Demo Hospital',
      'start': d(14), 'end': fmtDate(today.add(const Duration(days: 16))),
      'goals': 'Demo: 10 cannulations', 'updated': nowIso(),
    };
    rotations.add(rot);
    await saveList('rotations.json', rotations);
    final titles = [
      ['Internal Medicine', 'MED', 'Demo patient A', 'Community acquired pneumonia'],
      ['Emergency', 'EM', 'Demo patient B', 'Acute coronary syndrome'],
      ['Orthopedics', 'ORT', 'Demo patient C', 'Distal radius fracture'],
      ['Pediatrics', 'PED', 'Demo patient D', 'Gastroenteritis'],
      ['General Surgery', 'SUR', 'Demo patient E', 'Acute appendicitis'],
      ['Internal Medicine', 'MED', 'Demo patient F', 'Heart failure'],
    ];
    for (var i = 0; i < titles.length; i++) {
      final t = titles[i];
      final rec = CaseRec(<String, dynamic>{
        'id': 'demo_c$i', 'demo': true, 'schema': kSchema, 'created': nowIso(), 'date': d(i),
        'specialty': t[0], 'rotationId': 'demo_r1', 'status': i % 3 == 0 ? 'Draft' : 'Active',
        'code': '${t[1]}-9${(i + 1).toString().padLeft(3, '0')}', 'ageGroup': i % 2 == 0 ? 'Adult' : 'Child',
        'cc': 'Demo complaint ${i + 1}', 'workingDx': t[3], 'setting': ['ER', 'Ward', 'Clinic'][i % 3],
        'role': ['Observed', 'Assisted', 'Supervised', 'Independent'][i % 4],
        'hpi': 'Demo record. Fictional data used to try the screens.', 'learned': i % 2 == 0 ? 'Demo learning point' : '',
        'tags': i == 0 ? ['demo'] : [],
      });
      cases[rec.id] = rec;
      await _write(File('${casesDir.path}/${rec.id}.json'), jsonEncode(rec.d));
    }
    procedures.add({'id': 'demo_p1', 'demo': true, 'name': 'IV cannulation', 'role': 'Performed under supervision', 'confidence': '3', 'date': d(1), 'assessedBy': 'Self-assessed', 'rotationId': 'demo_r1', 'updated': nowIso()});
    procedures.add({'id': 'demo_p2', 'demo': true, 'name': 'ABG', 'role': 'Assisted', 'confidence': '2', 'date': d(3), 'assessedBy': 'Self-assessed', 'rotationId': 'demo_r1', 'updated': nowIso()});
    await saveList('procedures.json', procedures);
    notes.add({'id': 'demo_n1', 'demo': true, 'title': 'Demo note', 'body': 'Fictional note.', 'date': d(1), 'updated': nowIso()});
    await saveList('notes.json', notes);
    inbox.add({'id': 'demo_q1', 'demo': true, 'question': 'Demo question: what would you like to remember?', 'status': 'Open', 'date': d(2), 'updated': nowIso()});
    await saveList('questions.json', inbox);
    for (final i in [0, 2, 4]) {
      shifts.add({'date': d(i), 'type': 'Morning', 'rotationId': 'demo_r1', 'demo': true, 'updated': nowIso()});
    }
    await saveList('shifts.json', shifts);
    notifyListeners();
  }

  Future<void> removeDemo() async {
    for (final c in cases.values.where((c) => c.s('id').startsWith('demo_')).toList()) {
      cases.remove(c.id);
      final f = File('${casesDir.path}/${c.id}.json');
      if (await f.exists()) await f.delete();
      final b = File('${f.path}.bak');
      if (await b.exists()) await b.delete();
    }
    Future<void> clean(List<J> l, String file) async {
      final before = l.length;
      l.removeWhere((e) => e['demo'] == true);
      if (l.length != before) await saveList(file, l);
    }
    await clean(rotations, 'rotations.json');
    await clean(shifts, 'shifts.json');
    await clean(procedures, 'procedures.json');
    await clean(notes, 'notes.json');
    await clean(inbox, 'questions.json');
    for (final n in kExtraLists) {
      await clean(listOf(n), '$n.json');
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ CSV export (for hospital logbooks)

  String _csv(List<List<String>> rows) {
    final b = StringBuffer('﻿');
    for (final r in rows) {
      b.writeln(r.map((v) => '"${v.replaceAll('"', '""')}"').join(','));
    }
    return b.toString();
  }

  /// Header + rows of the cases CSV. Sign-off columns hold what the user recorded
  /// (supervisor, role, level, date, signed, initials); never patient information.
  List<List<String>> casesCsvRows(List<CaseRec> list, {bool signOff = true}) {
    final rows = <List<String>>[
      [
        'Code', 'Date', 'Specialty', 'Rotation', 'Setting', 'Age group', 'My role', 'Status', 'Diagnosis', 'Tags',
        if (signOff) ...kSignHead,
      ],
    ];
    for (final c in list) {
      final rot = rotationById(c.s('rotationId'));
      rows.add([
        c.s('code'), c.s('date'), c.s('specialty'),
        rot == null ? '' : rotationLabel(rot),
        c.s('setting'), c.s('ageGroup'), c.s('role'), c.s('status'),
        c.title == '(no diagnosis yet)' ? '' : c.title,
        c.tags.join(' '),
        if (signOff) ...signRow(c.d),
      ]);
    }
    return rows;
  }

  List<List<String>> procsCsvRows(List<J> list, {bool signOff = true}) {
    final rows = <List<String>>[
      [
        'Date', 'Procedure', 'My role', 'Confidence (1-5)', 'Assessed by', 'Case code', 'Rotation',
        if (signOff) ...kSignHead,
      ],
    ];
    for (final p in list) {
      final rot = rotationById((p['rotationId'] ?? '').toString());
      rows.add([
        (p['date'] ?? '').toString(), (p['name'] ?? '').toString(),
        (p['role'] ?? '').toString(), (p['confidence'] ?? '').toString(),
        (p['assessedBy'] ?? '').toString(), (p['caseCode'] ?? '').toString(),
        rot == null ? '' : rotationLabel(rot),
        if (signOff) ...signRow(p),
      ]);
    }
    return rows;
  }

  static const List<String> kSignHead = [
    'Supervisor', 'Supervisor role', 'Level of supervision', 'Supervision date', 'Signed by supervisor', 'Supervisor initials',
  ];

  List<String> signRow(J d) => [
        (d['supName'] ?? '').toString(), (d['supRole'] ?? '').toString(), (d['supLevel'] ?? '').toString(),
        (d['supDate'] ?? '').toString(), (d['supSigned'] ?? '').toString().isEmpty ? '' : 'yes',
        (d['supInit'] ?? '').toString(),
      ];

  /// Two CSV files (cases, procedures). [onlyCases] / [onlyProcs] limit what is written.
  Future<List<File>> exportCsv({List<CaseRec>? onlyCases, List<J>? onlyProcs, bool signOff = true}) async {
    final tmp = await getTemporaryDirectory();
    final stamp = _stamp();
    final f1 = File('${tmp.path}/MedLog-cases-$stamp.csv');
    await f1.writeAsString(_csv(casesCsvRows(onlyCases ?? casesSorted(), signOff: signOff)));
    final procs = onlyProcs ??
        (List<J>.from(procedures)
          ..sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString())));
    final f2 = File('${tmp.path}/MedLog-procedures-$stamp.csv');
    await f2.writeAsString(_csv(procsCsvRows(procs, signOff: signOff)));
    return [f1, f2];
  }
}

// ---------------------------------------------------------------- text export

String caseAsText(CaseRec c) {
  final b = StringBuffer();
  void line(String label, String v) {
    if (v.trim().isNotEmpty) b.writeln('$label: ${v.trim()}');
  }

  b.writeln('CASE ${c.s('code')} - ${c.s('specialty')}');
  line('Date', c.s('date'));
  line('Age group / sex', '${c.s('ageGroup')} ${c.s('sex')}');
  line('Setting', c.s('setting'));
  line('Status', c.s('status'));
  b.writeln('');
  line('CC', c.s('cc'));
  line('HPI', c.s('hpi'));
  line('PMH', c.s('pmh'));
  line('PSH', c.s('psh'));
  line('Drugs', c.s('drugs'));
  line('Allergies', c.s('allergies'));
  line('Family', c.s('family'));
  line('Social', c.s('social'));
  line('ROS', c.s('ros'));
  final extra = specialtyFieldsFor(c.s('specialty'));
  if (extra != null) {
    for (final f in extra) {
      line(f[1], c.s(f[0]));
    }
  }
  b.writeln('');
  final vit = [
    ['BP', 'v_bp'], ['HR', 'v_hr'], ['Temp', 'v_temp'], ['RR', 'v_rr'],
    ['SpO2', 'v_spo2'], ['RBS', 'v_rbs'], ['Wt', 'v_wt'],
  ].where((e) => c.s(e[1]).trim().isNotEmpty).map((e) => '${e[0]} ${c.s(e[1])}').join(', ');
  line('Vitals', vit);
  line('General exam (${c.s('obsGeneral')})', c.s('examGeneral'));
  line('Systemic exam (${c.s('obsSystemic')})', c.s('examSystemic'));
  line('Focused exam (${c.s('obsFocused')})', c.s('examFocused'));
  b.writeln('');
  line('Problem list', c.s('problems'));
  line('DDx', c.s('ddx'));
  line('Working dx', c.s('workingDx'));
  line('Final dx', c.s('finalDx'));
  line('Red flags', c.s('redFlags'));
  line('Reasoning', c.s('reasoning'));

  final evo = c.lst('evo');
  if (evo.isNotEmpty) {
    b.writeln('\nDIAGNOSTIC EVOLUTION');
    for (final e in evo) {
      b.writeln('- ${e['step'] ?? ''} (${e['date'] ?? ''}): ${e['text'] ?? ''}');
      if ((e['evidence'] ?? '').toString().isNotEmpty) {
        b.writeln('  Because: ${e['evidence']}');
      }
    }
  }

  final inv = c.lst('inv');
  if (inv.isNotEmpty) {
    b.writeln('\nINVESTIGATIONS');
    for (final i in inv) {
      b.writeln('- ${i['name'] ?? ''} [${i['status'] ?? ''}] ${i['result'] ?? ''}');
      if ((i['interpretation'] ?? '').toString().isNotEmpty) {
        b.writeln('  Interpretation: ${i['interpretation']}');
      }
    }
  }
  final mg = c.lst('mgmt');
  if (mg.isNotEmpty) {
    b.writeln('\nMANAGEMENT');
    for (final m in mg) {
      final dose = (m['dose'] ?? '').toString();
      b.writeln('- (${m['category'] ?? ''}; ${m['by'] ?? ''}; ${m['state'] ?? ''}) '
          '${m['text'] ?? ''}${dose.isEmpty ? '' : ' [$dose]'}');
    }
  }
  final pr = c.lst('progress');
  if (pr.isNotEmpty) {
    b.writeln('\nPROGRESS');
    for (final p in pr) {
      b.writeln('${p['day'] ?? ''} (${p['date'] ?? ''})');
      line(' S', (p['s'] ?? '').toString());
      line(' O', (p['o'] ?? '').toString());
      line(' A', (p['a'] ?? '').toString());
      line(' P', (p['p'] ?? '').toString());
    }
  }
  b.writeln('');
  line('Disposition', c.s('disposition'));
  line('Follow-up', c.s('followUp'));
  line('Outcome', c.s('outcome'));
  line('Initial dx', c.s('initialDx'));
  line('What changed my diagnosis', c.s('whatChanged'));
  line('Learned', c.s('learned'));
  line('Mistakes / near-misses', c.s('mistakes'));
  line('Questions to review', c.s('questions'));
  line('References', c.s('refs'));
  line('Supervisor teaching', c.s('teaching'));
  return b.toString();
}

/// Short case-presentation summary (what you say at the morning meeting).
/// No initials, no names: only the case code.
String casePresentation(CaseRec c) {
  final b = StringBuffer();
  void line(String label, String v) {
    if (v.trim().isNotEmpty) b.writeln('$label: ${v.trim()}');
  }

  final who = [c.s('ageGroup'), c.s('sex')].where((e) => e.isNotEmpty).join(' ');
  b.writeln('CASE PRESENTATION • ${c.s('code')}${who.isEmpty ? '' : ' • $who'}');
  line('Presenting complaint', c.s('cc'));
  line('History', c.s('hpi'));
  line('Past history', [c.s('pmh'), c.s('psh')].where((e) => e.trim().isNotEmpty).join('; '));
  line('Drugs / allergies', [c.s('drugs'), c.s('allergies')].where((e) => e.trim().isNotEmpty).join(' / '));
  final vit = [
    ['BP', 'v_bp'], ['HR', 'v_hr'], ['Temp', 'v_temp'], ['RR', 'v_rr'], ['SpO2', 'v_spo2'], ['RBS', 'v_rbs'],
  ].where((e) => c.s(e[1]).trim().isNotEmpty).map((e) => '${e[0]} ${c.s(e[1])}').join(', ');
  line('Vitals', vit);
  line('Examination', [c.s('examGeneral'), c.s('examSystemic'), c.s('examFocused')]
      .where((e) => e.trim().isNotEmpty).join('; '));
  final inv = c.lst('inv').where((i) => (i['result'] ?? '').toString().isNotEmpty)
      .map((i) => '${i['name']}: ${i['result']}').join('; ');
  line('Investigations', inv);
  line('Problem list', c.s('problems'));
  line('Impression', c.s('finalDx').trim().isNotEmpty ? c.s('finalDx') : c.s('workingDx'));
  line('Differential', c.s('ddx'));
  final plan = c.lst('mgmt').map((m) => '${m['text']}${(m['dose'] ?? '').toString().isEmpty ? '' : ' (${m['dose']})'}').join('; ');
  line('Plan', plan);
  line('Disposition', c.s('disposition'));
  line('Teaching point', c.s('learned'));
  return b.toString();
}
