import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'data.dart';
import 'formulary.dart';
import 'search_index.dart' show normText;

/// Drug doses and durations from the user's OWN files (JSON made from a book or a hospital protocol).
/// The files are copied into a folder on this phone and nowhere else: nothing here is bundled in the app or sent out.
///
/// File format (schemaVersion 1):
/// {"schemaVersion":1,"meta":{"id","title","source"},
///  "drugs":[{"name","aka":[],"class","routes":[],"regimens":[{"indication","population","route","dose","frequency",
///            "duration","max","notes","page","verify"}],"renal","hepatic","pregnancy","cautions":[],
///            "contraindications":[],"interactions":[],"monitoring":[],"adverse":[],"pearls":[],"page"}],
///  "durations":[{"condition","regimen","duration","notes","page"}]}

class DoseRegimen {
  final String indication, population, route, dose, frequency, duration, max, notes, page;
  final bool verify;
  const DoseRegimen({this.indication = '', this.population = '', this.route = '', this.dose = '', this.frequency = '', this.duration = '', this.max = '', this.notes = '', this.page = '', this.verify = false});
}

class DrugEntry {
  final String key, pack, name, drugClass, renal, hepatic, pregnancy, page;
  final List<String> aka, routes, cautions, contraindications, interactions, monitoring, adverse, pearls;
  final List<DoseRegimen> regimens;
  final String _hay;
  DrugEntry({
    required this.key,
    required this.pack,
    required this.name,
    this.drugClass = '',
    this.renal = '',
    this.hepatic = '',
    this.pregnancy = '',
    this.page = '',
    this.aka = const [],
    this.routes = const [],
    this.cautions = const [],
    this.contraindications = const [],
    this.interactions = const [],
    this.monitoring = const [],
    this.adverse = const [],
    this.pearls = const [],
    this.regimens = const [],
  }) : _hay = normText([name, ...aka, drugClass, for (final r in regimens) r.indication].join(' '));

  bool matches(List<String> words) => words.every((w) => _hay.contains(w));
  bool hasPopulation(String p) => regimens.any((r) => r.population.toLowerCase().contains(p));
}

class DurationEntry {
  final String pack, condition, regimen, duration, notes, page;
  final String _hay;
  DurationEntry({required this.pack, required this.condition, this.regimen = '', this.duration = '', this.notes = '', this.page = ''})
      : _hay = normText('$condition $regimen');
  bool matches(List<String> words) => words.every((w) => _hay.contains(w));
}

class DosePack {
  final String id, title, source, status;
  final int drugs, durations;
  const DosePack(this.id, this.title, this.source, this.drugs, this.durations, {this.status = ''});
}

String _s(Object? v) => v == null ? '' : '$v'.trim();
List<String> _l(Object? v) => v is List ? [for (final e in v) if (_s(e).isNotEmpty) _s(e)] : const [];

/// One regimen from the file. Some converters put the indication on the first line of the notes and leave the
/// indication empty: it is moved to where it belongs.
DoseRegimen _regimen(Map r) {
  var indication = _s(r['indication']);
  var notes = _s(r['notes']);
  if (indication.isEmpty && notes.contains('\n')) {
    final i = notes.indexOf('\n');
    final first = notes.substring(0, i).trim();
    if (first.isNotEmpty && first.length <= 160) {
      indication = first;
      notes = notes.substring(i + 1).trim();
    }
  }
  return DoseRegimen(
    indication: indication,
    population: _s(r['population']),
    route: _s(r['route']),
    dose: _s(r['dose']),
    frequency: _s(r['frequency']),
    duration: _s(r['duration']),
    max: _s(r['max']),
    notes: notes,
    page: _s(r['page']),
    verify: r['verify'] == true,
  );
}

/// Holds the imported dosing files (folder dosing/ next to the cases).
class DosingStore extends ChangeNotifier {
  Directory? _dir;
  final List<DosePack> packs = [];
  final List<DrugEntry> drugs = [];
  final List<DurationEntry> durations = [];
  final List<FDrug> fdrugs = [];
  final Map<String, FSource> fsources = {};
  bool loaded = false;

  Directory get dir => _dir ??= Directory('${store.root.path}/dosing')..createSync(recursive: true);

  static final RegExp _idRe = RegExp(r'^[a-z0-9][a-z0-9-]{1,60}$');

  Future<void> load() async {
    packs.clear();
    drugs.clear();
    durations.clear();
    fdrugs.clear();
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        _add(jsonDecode(await f.readAsString()) as Map);
      } catch (_) {}
    }
    drugs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    loaded = true;
    notifyListeners();
  }

  /// Parses and registers one file; throws a [FormatException] with a plain reason when it is not usable.
  DosePack _add(Map j) {
    if (j['schemaVersion'] == 2) return _addFormulary(j);
    if (j['schemaVersion'] != 1) throw const FormatException('This is not a MedLog dosing file (schemaVersion 1 or 2).');
    final meta = (j['meta'] is Map ? j['meta'] as Map : const {});
    final id = _s(meta['id']);
    if (!_idRe.hasMatch(id)) throw const FormatException('The file needs meta.id: lowercase letters, numbers and hyphens.');
    final title = _s(meta['title']).isEmpty ? id : _s(meta['title']);
    final rawDrugs = j['drugs'] is List ? j['drugs'] as List : const [];
    final rawDur = j['durations'] is List ? j['durations'] as List : const [];
    if (rawDrugs.isEmpty && rawDur.isEmpty) throw const FormatException('The file has no drugs and no durations.');
    // a pack with the same id is replaced
    drugs.removeWhere((d) => d.pack == id);
    durations.removeWhere((d) => d.pack == id);
    packs.removeWhere((p) => p.id == id);
    var n = 0;
    for (final e in rawDrugs) {
      if (e is! Map || _s(e['name']).isEmpty) continue;
      final regs = <DoseRegimen>[
        for (final r in (e['regimens'] is List ? e['regimens'] as List : const []))
          if (r is Map)
            _regimen(r)
      ];
      drugs.add(DrugEntry(
        key: '$id|${_s(e['name']).toLowerCase()}',
        pack: id,
        name: _s(e['name']),
        drugClass: _s(e['class']),
        renal: _s(e['renal']),
        hepatic: _s(e['hepatic']),
        pregnancy: _s(e['pregnancy']),
        page: _s(e['page']),
        aka: _l(e['aka']),
        routes: _l(e['routes']),
        cautions: _l(e['cautions']),
        contraindications: _l(e['contraindications']),
        interactions: _l(e['interactions']),
        monitoring: _l(e['monitoring']),
        adverse: _l(e['adverse']),
        pearls: _l(e['pearls']),
        regimens: regs,
      ));
      n++;
    }
    var m = 0;
    for (final e in rawDur) {
      if (e is! Map || _s(e['condition']).isEmpty) continue;
      durations.add(DurationEntry(pack: id, condition: _s(e['condition']), regimen: _s(e['regimen']), duration: _s(e['duration']), notes: _s(e['notes']), page: _s(e['page'])));
      m++;
    }
    final p = DosePack(id, title, _s(meta['source']), n, m);
    packs.add(p);
    return p;
  }

  /// A source-bound drug reference (schemaVersion 2): drugs with structured regimens and the label text around them.
  DosePack _addFormulary(Map j) {
    final meta = (j['meta'] is Map ? j['meta'] as Map : const {});
    final id = _s(meta['id']);
    if (!_idRe.hasMatch(id)) throw const FormatException('The file needs meta.id: lowercase letters, numbers and hyphens.');
    final raw = j['drugs'] is List ? j['drugs'] as List : const [];
    if (raw.isEmpty) throw const FormatException('The file has no drugs.');
    fdrugs.removeWhere((d) => d.pack == id);
    drugs.removeWhere((d) => d.pack == id);
    durations.removeWhere((d) => d.pack == id);
    packs.removeWhere((p) => p.id == id);
    for (final s in (meta['sources'] is List ? meta['sources'] as List : const [])) {
      if (s is Map && _s(s['id']).isNotEmpty) {
        fsources[_s(s['id'])] = FSource(_s(s['id']), _s(s['title']), _s(s['publisher']), _s(s['url']), _s(s['license']), _s(s['accessed']));
      }
    }
    var n = 0;
    for (final e in raw) {
      if (e is! Map || _s(e['name']).isEmpty || _s(e['id']).isEmpty) continue;
      fdrugs.add(FDrug.fromJson(id, e));
      n++;
    }
    final p = DosePack(id, _s(meta['title']).isEmpty ? id : _s(meta['title']), '', n, 0, status: _s(meta['status']));
    packs.add(p);
    return p;
  }

  /// The smaller file kept on the phone for a schemaVersion 2 file.
  static List<int> _trimmedBytes(Map j) {
    final out = <String, dynamic>{
      'schemaVersion': 2,
      'meta': {
        for (final k in ['id', 'title', 'status', 'sources', 'notes', 'generated']) if ((j['meta'] as Map).containsKey(k)) k: (j['meta'] as Map)[k]
      },
      'drugs': [for (final e in (j['drugs'] as List)) if (e is Map) FDrug.trim(e)],
    };
    return utf8.encode(jsonEncode(out));
  }

  /// Imports JSON files (or a ZIP of them). Returns the packs added.
  Future<List<DosePack>> importFiles(List<String> paths) async {
    final added = <DosePack>[];
    final problems = <String>[];
    for (final path in paths) {
      final blobs = <String, List<int>>{};
      if (path.toLowerCase().endsWith('.zip')) {
        for (final f in ZipDecoder().decodeBytes(await File(path).readAsBytes()).files) {
          if (f.isFile && f.name.toLowerCase().endsWith('.json')) blobs[f.name] = f.content as List<int>;
        }
      } else {
        blobs[path] = await File(path).readAsBytes();
      }
      for (final e in blobs.entries) {
        try {
          final map = jsonDecode(utf8.decode(e.value)) as Map;
          final p = _add(map);
          await File('${dir.path}/${p.id}.json').writeAsBytes(map['schemaVersion'] == 2 ? _trimmedBytes(map) : e.value, flush: true);
          added.add(p);
        } catch (err) {
          problems.add('${e.key.split('/').last}: ${err is FormatException ? err.message : 'not readable'}');
        }
      }
    }
    drugs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    loaded = true;
    notifyListeners();
    if (added.isEmpty && problems.isNotEmpty) throw FormatException(problems.join('\n'));
    return added;
  }

  Future<void> remove(String id) async {
    drugs.removeWhere((d) => d.pack == id);
    durations.removeWhere((d) => d.pack == id);
    fdrugs.removeWhere((d) => d.pack == id);
    packs.removeWhere((p) => p.id == id);
    try {
      await File('${dir.path}/$id.json').delete();
    } catch (_) {}
    notifyListeners();
  }

  static List<String> _words(String q) => normText(q).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  /// Drugs whose name, brand names, class or indication contain every word typed; name matches first.
  List<DrugEntry> searchDrugs(String q, {String population = ''}) {
    final w = _words(q);
    final out = <DrugEntry>[];
    for (final d in drugs) {
      if (population.isNotEmpty && !d.hasPopulation(population)) continue;
      if (w.isEmpty || d.matches(w)) out.add(d);
    }
    if (w.isNotEmpty) {
      int rank(DrugEntry d) {
        final n = normText(d.name);
        if (n == w.join(' ')) return 0;
        if (n.startsWith(w.first)) return 1;
        if (w.every(n.contains)) return 2;
        return 3;
      }
      out.sort((a, b) => rank(a).compareTo(rank(b)));
    }
    return out;
  }

  /// Source-bound drugs: name, brand names, class or indication contain every word typed.
  List<FDrug> searchFormulary(String q, {String population = ''}) {
    final w = _words(q);
    final out = <FDrug>[];
    for (final d in fdrugs) {
      if (population.isNotEmpty && !d.regimens.any((r) => r.group.toLowerCase().contains(population))) continue;
      final hay = normText([d.name, ...d.aka, d.drugClass, for (final r in d.regimens) r.indication, for (final i in d.indications.take(1)) i.text.substring(0, i.text.length.clamp(0, 400))].join(' '));
      if (w.isEmpty || w.every(hay.contains)) out.add(d);
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  List<DurationEntry> searchDurations(String q) {
    final w = _words(q);
    return [for (final d in durations) if (w.isEmpty || d.matches(w)) d];
  }
}

final DosingStore dosing = DosingStore();
