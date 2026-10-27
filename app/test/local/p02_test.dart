import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/dose_calc.dart';
import 'package:medlog/dosing.dart';
import 'package:medlog/formulary.dart';
import '../lib2_util.dart';

const p2 = '/root/.claude/uploads/18428738-c972-5f0d-b25a-65d8d4d3c81a/4738be38-MedLog_Formulary_Part02_v2.json';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('part02 imports and examples reproduce', () async {
    await initStoreLight();
    await dosing.load();
    final p = await dosing.importFiles([p2]);
    print('drugs ${p.single.drugs}');
    var regs = 0, ex = 0, bad = 0;
    for (final d in dosing.fdrugs) {
      regs += d.regimens.length;
      for (final x in d.examples) {
        ex++;
        final rl = d.regimens.where((r) => r.id == x.regimenId);
        if (rl.isEmpty) { print('NOREG ${d.id} ${x.regimenId}'); bad++; continue; }
        final r = rl.first;
        final fl = d.forms.where((f) => f.id == x.formId);
        final res = DoseCalc.compute(r, DoseInput(weightKg: x.weightKg, ageMonths: x.ageMonths ?? (r.ageMin != null ? r.ageMin! + 1 : (r.ageMax != null ? r.ageMax! / 2 : null))), form: fl.isEmpty ? null : fl.first);
        bool within(double? lo, double? hi, double v) => lo != null && hi != null && v >= lo - 0.001 && v <= hi + 0.001;
        final okDose = x.perDose == null || (res.perDoseMin != null && res.perDoseMin! <= x.perDoseHi! + 0.001 && res.perDoseMax! >= x.perDose! - 0.001);
        final okDay = x.scheduledDaily == null || (res.dailyMin != null && res.dailyMin! <= x.scheduledDailyHi! + 0.001 && res.dailyMax! >= x.scheduledDaily! - 0.001);
        final okVol = x.volumeMl == null || within(res.volumeMin, res.volumeMax, x.volumeMl!);
        if (res.blockers.isNotEmpty || !okDose || !okDay || !okVol) {
          bad++;
          print('BAD ${d.id}/${r.id} ${x.weightKg}kg blockers=${res.blockers} dose=${res.perDoseMin}-${res.perDoseMax} vs ${x.perDose}; day=${res.dailyMin}-${res.dailyMax} vs ${x.scheduledDaily}; vol=${res.volumeMin}-${res.volumeMax} vs ${x.volumeMl}');
        }
      }
    }
    print('regimens $regs examples $ex bad $bad');
    final lbReg = dosing.fdrugs.firstWhere((d) => d.id == 'promethazine').regimens.firstWhere((r) => r.dosePer == 'lb');
    final res = DoseCalc.compute(lbReg, const DoseInput(weightKg: 10, ageMonths: 36));
    expect(res.perDoseMin, closeTo(0.5 * 22.0462262, 1e-3)); // per pound, not a flat 0.5 mg
  });
}
