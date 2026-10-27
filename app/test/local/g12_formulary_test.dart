import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/dose_calc.dart';
import 'package:medlog/dosing.dart';
import 'package:medlog/formulary.dart';
import '../lib2_util.dart';

const real = '/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/5954f736-MedLog_Formulary_Part01_v2.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('label text is cleaned for reading', () {
    expect(cleanLabelText('1 INDICATIONS AND USAGE Epinephrine is a drug ( 1.1 ) for use ( 2.2 , 2.3 ).'), 'Epinephrine is a drug for use.');
    expect(cleanLabelText('4 CONTRAINDICATIONS None. None. ( 4 )'), 'None. None.');
  });

  test('import of the real v2 file, trimmed copy, restart', () async {
    await initStoreLight();
    await dosing.load();
    final p = await dosing.importFiles([real]);
    expect(p.single.drugs, 25);
    expect(dosing.fdrugs.length, 25);
    final stored = File('${dosing.dir.path}/medlog-formulary-part-01.json');
    final full = File(real).lengthSync(), small = stored.lengthSync();
    print('full ${full ~/ 1024} KB -> kept ${small ~/ 1024} KB');
    expect(small < full, true);
    await dosing.load();
    expect(dosing.fdrugs.length, 25);
    expect(dosing.fsources.containsKey('openfda-policy'), true);
    final epi = dosing.fdrugs.firstWhere((d) => d.id == 'epinephrine');
    expect(epi.drugClass.contains('[EPC]'), false);
    expect(epi.regimens.every((r) => !r.fileApproved), true); // the file approves nothing
  });

  test('every worked example of the file is reproduced by the calculator', () async {
    await initStoreLight();
    await dosing.load();
    await dosing.importFiles([real]);
    var checked = 0;
    for (final d in dosing.fdrugs) {
      for (final x in d.examples) {
        final r = d.regimens.firstWhere((r) => r.id == x.regimenId);
        final form = d.forms.where((f) => f.id == x.formId).isEmpty ? null : d.forms.firstWhere((f) => f.id == x.formId);
        final res = DoseCalc.compute(r, DoseInput(weightKg: x.weightKg, ageMonths: x.ageMonths), form: form);
        final label = '${d.name} / ${r.id} / ${x.weightKg} kg';
        expect(res.blockers, isEmpty, reason: label);
        bool within(double? lo, double? hi, double v) => lo != null && hi != null && v >= lo - 0.001 && v <= hi + 0.001;
        if (x.perDose != null) expect(within(res.perDoseMin, res.perDoseMax, x.perDose!), true, reason: '$label per dose ${res.perDoseMin}-${res.perDoseMax} vs ${x.perDose}');
        if (x.scheduledDaily != null) expect(within(res.dailyMin, res.dailyMax, x.scheduledDaily!), true, reason: '$label daily ${res.dailyMin}-${res.dailyMax} vs ${x.scheduledDaily}');
        if (x.maxDaily != null && res.dailyMax != null) expect(res.dailyMax! <= x.maxDaily! + 0.001, true, reason: '$label max daily');
        if (x.volumeMl != null) expect(within(res.volumeMin, res.volumeMax, x.volumeMl!), true, reason: '$label volume ${res.volumeMin}-${res.volumeMax} vs ${x.volumeMl}');
        checked++;
      }
    }
    print('examples checked: $checked');
    expect(checked >= 30, true);
  });

  test('ranges, caps, units, blockers', () {
    FRegimen mk(Map<String, dynamic> over) => FRegimen.fromJson({
          'id': 'x',
          'population': {'group': 'Pediatric', 'weightMaxKg': 40, 'weightMaxInclusive': false},
          'route': 'PO',
          'basis': 'perKg',
          'dose': {'min': 10, 'max': 15, 'unit': 'mg', 'per': 'kg', 'perUnit': 'dose'},
          'frequency': {'timesPerDayMin': 3, 'timesPerDayMax': 4},
          'maxSingle': {'value': 500, 'unit': 'mg'},
          'maxDaily': {'value': 1500, 'unit': 'mg'},
          ...over,
        });
    final r = mk({});
    var res = DoseCalc.compute(r, const DoseInput(weightKg: 20));
    expect(res.perDoseMin, 200);
    expect(res.perDoseMax, 300);
    expect(res.dailyMin, 600);
    expect(res.dailyMax, 1200);
    res = DoseCalc.compute(r, const DoseInput(weightKg: 39));
    expect(res.perDoseMax, 500); // 585 capped
    expect(res.warnings.isNotEmpty, true);
    expect(res.dailyMax, 1500); // 2000 capped
    expect(DoseCalc.compute(r, const DoseInput(weightKg: 40)).blockers.isNotEmpty, true); // upper bound exclusive
    expect(DoseCalc.compute(r, const DoseInput()).blockers.isNotEmpty, true); // weight needed
    // mcg dose with a mg/mL product
    final mcg = mk({'dose': {'min': 5, 'max': 5, 'unit': 'mcg', 'per': 'kg', 'perUnit': 'dose'}, 'maxSingle': {}, 'maxDaily': {}});
    final f = const FForm(id: 'f', form: 'inj', strength: 1, strengthUnit: 'mg', per: 1, perUnit: 'mL');
    res = DoseCalc.compute(mcg, const DoseInput(weightKg: 10), form: f);
    expect(res.perDoseMin, 50);
    expect(res.volumeMin, closeTo(0.05, 1e-9));
    // per-day dose split by the interval
    final day = mk({'dose': {'min': 40, 'max': 40, 'unit': 'mg', 'per': 'kg', 'perUnit': 'day'}, 'frequency': {'intervalHoursMin': 8, 'intervalHoursMax': 8}, 'maxSingle': {}, 'maxDaily': {}});
    res = DoseCalc.compute(day, const DoseInput(weightKg: 12));
    expect(res.perDoseMin, 160);
    expect(res.dailyMax, 480);
    // age range
    final aged = mk({'population': {'group': 'Pediatric', 'ageMinMonths': 3, 'ageMinInclusive': false}});
    expect(DoseCalc.compute(aged, const DoseInput(weightKg: 6, ageMonths: 3)).blockers.isNotEmpty, true);
    expect(DoseCalc.compute(aged, const DoseInput(weightKg: 6, ageMonths: 4)).ok, true);
    expect(DoseCalc.compute(aged, const DoseInput(weightKg: 6)).blockers.isNotEmpty, true);
  });
}
