/// Source-bound drug reference (schemaVersion 2) and its models. The dose engine is in dose_calc.dart.
/// Everything here is data read from the user's imported files: nothing is invented, and a regimen can only be
/// calculated after it was approved (by the file itself or by the user's own check against the source).

String _s(Object? v) => v == null ? '' : '$v'.trim();
double? _d(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
List<String> _l(Object? v) => v is List ? [for (final e in v) if (_s(e).isNotEmpty) _s(e)] : const [];

/// Label text starts with its section number and heading ("1 INDICATIONS AND USAGE ...") and is sprinkled with
/// cross references ("( 2.1 )"): both are removed for reading.
String cleanLabelText(String t) {
  var s = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'^\d+(\.\d+)*\s+(?:[A-Z][A-Z0-9&,/()\-]*\s+)+(?=[A-Z][a-z])'), '');
  s = s.replaceAll(RegExp(r'\(\s*\d+(\.\d+)*(\s*,\s*\d+(\.\d+)*)*\s*\)'), '');
  s = s.replaceAll(RegExp(r'\s{2,}'), ' ').replaceAllMapped(RegExp(r'\s+([.,;:])'), (m) => m[1]!).trim();
  return s;
}

class FSource {
  final String id, title, publisher, url, license, accessed;
  const FSource(this.id, this.title, this.publisher, this.url, this.license, this.accessed);
}

class FText {
  final String text, source;
  final String kind;
  const FText(this.text, this.source, [this.kind = '']);
}

class FInteraction {
  final String with_, effect, severity, source;
  const FInteraction(this.with_, this.effect, this.severity, this.source);
}

class FForm {
  final String id, form, strengthUnit, perUnit, component, route;
  final double? strength, per;
  final bool productMatchRequired;
  const FForm({required this.id, required this.form, this.strength, this.strengthUnit = '', this.per, this.perUnit = '', this.component = '', this.route = '', this.productMatchRequired = false});

  /// "125 mg / 5 mL"
  String get label => '${_n(strength)} $strengthUnit / ${_n(per)} $perUnit'.trim();
}

String _n(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');

class FRegimen {
  final String id, indication, group, route, basis, doseUnit, dosePer, dosePerUnit, freqText, durationText, administration, notes, source, component, formId, renalPolicy;
  final double? ageMin, ageMax, weightMin, weightMax, doseMin, doseMax, maxSingle, maxDaily, maxDailyPerKg, tpdMin, tpdMax, intMin, intMax, durMin, durMax;
  final bool ageMinIncl, ageMaxIncl, weightMinIncl, weightMaxIncl, fileApproved, verify, once;
  final String maxSingleUnit, maxDailyUnit, maxDailyPerKgUnit, durUnit, reviewReason;
  const FRegimen({
    required this.id,
    this.indication = '',
    this.group = '',
    this.route = '',
    this.basis = '',
    this.doseUnit = '',
    this.dosePer = '',
    this.dosePerUnit = '',
    this.freqText = '',
    this.durationText = '',
    this.administration = '',
    this.notes = '',
    this.source = '',
    this.component = '',
    this.formId = '',
    this.renalPolicy = '',
    this.ageMin,
    this.ageMax,
    this.weightMin,
    this.weightMax,
    this.doseMin,
    this.doseMax,
    this.maxSingle,
    this.maxDaily,
    this.maxDailyPerKg,
    this.tpdMin,
    this.tpdMax,
    this.intMin,
    this.intMax,
    this.durMin,
    this.durMax,
    this.ageMinIncl = true,
    this.ageMaxIncl = false,
    this.weightMinIncl = true,
    this.weightMaxIncl = false,
    this.fileApproved = false,
    this.verify = false,
    this.once = false,
    this.maxSingleUnit = '',
    this.maxDailyUnit = '',
    this.maxDailyPerKgUnit = '',
    this.durUnit = '',
    this.reviewReason = '',
  });

  String get label => [indication.isEmpty ? id : indication, if (group.isNotEmpty) group, if (route.isNotEmpty) route].join(' • ');

  factory FRegimen.fromJson(Map r) {
    final pop = r['population'] is Map ? r['population'] as Map : const {};
    final dose = r['dose'] is Map ? r['dose'] as Map : const {};
    final fr = r['frequency'] is Map ? r['frequency'] as Map : const {};
    final ms = r['maxSingle'] is Map ? r['maxSingle'] as Map : const {};
    final md = r['maxDaily'] is Map ? r['maxDaily'] as Map : const {};
    final mk = r['maxDailyPerKg'] is Map ? r['maxDailyPerKg'] as Map : const {};
    final du = r['duration'] is Map ? r['duration'] as Map : const {};
    final rv = r['clinicalReview'] is Map ? r['clinicalReview'] as Map : const {};
    return FRegimen(
      id: _s(r['id']),
      indication: _s(r['indication']),
      group: _s(pop['group']),
      route: _s(r['route']),
      basis: _s(r['basis']),
      doseUnit: _s(dose['unit']),
      dosePer: _s(dose['per']),
      dosePerUnit: _s(dose['perUnit']),
      freqText: _s(fr['text']),
      durationText: _s(du['text']),
      administration: _s(r['administration']),
      notes: _s(r['notes']),
      source: _s(r['source']),
      component: _s(r['component']),
      formId: _s(r['formId']),
      renalPolicy: _s(r['renalPolicy']),
      ageMin: _d(pop['ageMinMonths']),
      ageMax: _d(pop['ageMaxMonths']),
      weightMin: _d(pop['weightMinKg']),
      weightMax: _d(pop['weightMaxKg']),
      doseMin: _d(dose['min']),
      doseMax: _d(dose['max']),
      maxSingle: _d(ms['value']),
      maxDaily: _d(md['value']),
      maxDailyPerKg: _d(mk['value']),
      tpdMin: _d(fr['timesPerDayMin']),
      tpdMax: _d(fr['timesPerDayMax']),
      intMin: _d(fr['intervalHoursMin']),
      intMax: _d(fr['intervalHoursMax']),
      durMin: _d(du['min']),
      durMax: _d(du['max']),
      ageMinIncl: pop['ageMinInclusive'] != false,
      ageMaxIncl: pop['ageMaxInclusive'] == true,
      weightMinIncl: pop['weightMinInclusive'] != false,
      weightMaxIncl: pop['weightMaxInclusive'] == true,
      fileApproved: r['calculationEnabled'] == true && _s(rv['status']) == 'approved',
      verify: r['verify'] == true,
      once: r['once'] == true,
      maxSingleUnit: _s(ms['unit']),
      maxDailyUnit: _s(md['unit']),
      maxDailyPerKgUnit: _s(mk['unit']),
      durUnit: _s(du['unit']),
      reviewReason: _s(rv['reason']),
    );
  }
}

class FExample {
  final String regimenId, formId;
  final double? weightKg, ageMonths, perDose, scheduledDaily, maxDaily, volumeMl;
  const FExample(this.regimenId, this.formId, this.weightKg, this.ageMonths, this.perDose, this.scheduledDaily, this.maxDaily, this.volumeMl);
}

class FDrug {
  final String key, pack, id, name, drugClass, reviewStatus, source;
  final List<String> aka, monitoring;
  final List<FForm> forms;
  final List<FText> indications, contraindications, cautions, pregnancy, lactation, adverse, renal, hepatic, dosingText;
  final List<FInteraction> interactions;
  final List<FRegimen> regimens;
  final List<FExample> examples;
  final List<(String, String, double, double)> durations;
  const FDrug({
    required this.key,
    required this.pack,
    required this.id,
    required this.name,
    this.drugClass = '',
    this.reviewStatus = '',
    this.source = '',
    this.aka = const [],
    this.monitoring = const [],
    this.forms = const [],
    this.indications = const [],
    this.contraindications = const [],
    this.cautions = const [],
    this.pregnancy = const [],
    this.lactation = const [],
    this.adverse = const [],
    this.renal = const [],
    this.hepatic = const [],
    this.dosingText = const [],
    this.interactions = const [],
    this.regimens = const [],
    this.examples = const [],
    this.durations = const [],
  });

  bool get hasRegimens => regimens.isNotEmpty;

  /// Source ids used by this drug (the part before '#').
  Set<String> get sourceIds {
    final out = <String>{};
    void add(String s) {
      final i = s.indexOf('#');
      final id = i < 0 ? s : s.substring(0, i);
      if (id.isNotEmpty) out.add(id);
    }
    add(source);
    for (final r in regimens) {
      add(r.source);
    }
    for (final list in [indications, contraindications, cautions, pregnancy, lactation, adverse, dosingText]) {
      for (final t in list) {
        add(t.source);
      }
    }
    return out;
  }

  static List<FText> _texts(Object? v) {
    if (v is Map) {
      final t = _s(v['text']);
      return t.isEmpty ? const [] : [FText(t, _s(v['source']))];
    }
    if (v is List) {
      return [
        for (final e in v)
          if (e is Map && _s(e['text']).isNotEmpty) FText(_s(e['text']), _s(e['source']), _s(e['kind']))
          else if (e is String && e.trim().isNotEmpty) FText(e.trim(), '')
      ];
    }
    return const [];
  }

  factory FDrug.fromJson(String pack, Map e) {
    final adv = e['adverse'];
    final advTexts = <FText>[];
    if (adv is Map) {
      for (final k in ['serious', 'common', 'unclassified']) {
        advTexts.addAll(_texts(adv[k]));
      }
    } else {
      advTexts.addAll(_texts(adv));
    }
    final rev = e['review'] is Map ? e['review'] as Map : const {};
    return FDrug(
      key: '$pack|${_s(e['id'])}',
      pack: pack,
      id: _s(e['id']),
      name: _s(e['name']),
      drugClass: _s(e['class']).replaceAll(RegExp(r'\s*\[[A-Z]{2,4}\]'), ''),
      reviewStatus: _s(rev['status']),
      source: _s(e['source']),
      aka: [for (final a in _l(e['aka'])) if (a.toLowerCase() != _s(e['name']).toLowerCase()) a],
      monitoring: _l(e['monitoring']),
      forms: [
        for (final f in (e['forms'] is List ? e['forms'] as List : const []))
          if (f is Map)
            FForm(
              id: _s(f['id']),
              form: _s(f['form']),
              strength: _d(f['strength']),
              strengthUnit: _s(f['strengthUnit']),
              per: _d(f['per']),
              perUnit: _s(f['perUnit']),
              component: _s(f['component']),
              route: _s(f['route']),
              productMatchRequired: f['productMatchRequired'] == true,
            )
      ],
      indications: _texts(e['indications']),
      contraindications: _texts(e['contraindications']),
      cautions: _texts(e['cautions']),
      pregnancy: _texts(e['pregnancy']),
      lactation: _texts(e['lactation']),
      adverse: advTexts,
      renal: _texts(e['renal']),
      hepatic: _texts(e['hepatic']),
      dosingText: _texts(e['unstructuredDosing']),
      interactions: [
        for (final i in (e['interactions'] is List ? e['interactions'] as List : const []))
          if (i is Map && (_s(i['effect']).isNotEmpty || _s(i['with']).isNotEmpty)) FInteraction(_s(i['with']), _s(i['effect']), _s(i['severity']), _s(i['source']))
      ],
      regimens: [
        for (final r in (e['regimens'] is List ? e['regimens'] as List : const []))
          if (r is Map && _s(r['id']).isNotEmpty) FRegimen.fromJson(r)
      ],
      examples: [
        for (final x in (e['examples'] is List ? e['examples'] as List : const []))
          if (x is Map)
            FExample(_s(x['regimenId']), _s(x['formId']), _d(x['weightKg']), _d(x['ageMonths']), _d(x['expectedPerDose']), _d(x['expectedScheduledDaily']),
                _d(x['expectedMaxDaily']), _d(x['expectedVolumeMl']))
      ],
    );
  }

  /// A smaller copy of a drug entry of the file for storing on the phone: the full label sections and the identity
  /// records are not kept.
  static Map<String, dynamic> trim(Map e) {
    const keep = [
      'id', 'name', 'aka', 'class', 'atc', 'forms', 'indications', 'contraindications', 'cautions', 'interactions', 'pregnancy', 'lactation', 'adverse',
      'monitoring', 'regimens', 'renal', 'hepatic', 'durations', 'examples', 'unstructuredDosing', 'review', 'source'
    ];
    final out = <String, dynamic>{for (final k in keep) if (e.containsKey(k)) k: e[k]};
    final regs = out['regimens'];
    if (regs is List) {
      out['regimens'] = [
        for (final r in regs)
          if (r is Map) {for (final x in r.entries) if (x.key != 'fieldSources') x.key: x.value}
      ];
    }
    return out;
  }
}


/// Sentences of the label that talk about the kidneys (renal impairment, creatinine clearance, dialysis...), so the
/// reader finds them without reading the whole text.
List<String> renalSentences(FDrug d, {int max = 6}) {
  final re = RegExp(r'renal|kidney|creatinine|\bCrCl\b|\bGFR\b|dialysis', caseSensitive: false);
  final seen = <String>{};
  final out = <String>[];
  for (final list in [d.dosingText, d.renal, d.cautions, d.contraindications]) {
    for (final t in list) {
      final text = cleanLabelText(t.text);
      for (final sentence in text.split(RegExp(r'(?<=[.!?])\s+(?=[A-Z]|\d+(\.\d+)+\s+[A-Z])'))) {
        final x = sentence.replaceFirst(RegExp(r'^\d+(\.\d+)*\s+'), '').trim();
        if (x.length < 25 || x.length > 600 || !re.hasMatch(x)) continue;
        if (seen.add(x.toLowerCase())) out.add(x);
        if (out.length >= max) return out;
      }
    }
  }
  return out;
}
