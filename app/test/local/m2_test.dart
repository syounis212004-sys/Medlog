import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/dose_calc.dart';
import 'package:medlog/formulary.dart';
import 'package:medlog/screens_dosing.dart';
import '../lib2_util.dart';
import 'package:medlog/data.dart';

FDrug drug(double max) => FDrug.fromJson('pack', {
      'id': 'x', 'name': 'X',
      'forms': [{'id': 'f', 'form': 'syrup', 'strength': 100, 'strengthUnit': 'mg', 'per': 5, 'perUnit': 'mL'}],
      'regimens': [
        {'id': 'r1', 'population': {'group': 'Child'}, 'route': 'PO', 'basis': 'perKg', 'dose': {'min': 10, 'max': 15, 'unit': 'mg', 'per': 'kg', 'perUnit': 'dose'}, 'frequency': {'timesPerDayMin': 3, 'timesPerDayMax': 3}, 'maxSingle': {'value': max, 'unit': 'mg'}}
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('approval is bound to the numbers', () async {
    await initStoreLight();
    final a = drug(500), b = drug(400);
    expect(doseStatus(a, a.regimens.first), DoseStatus.underReview);
    expect(doseFingerprint(a, a.regimens.first) == doseFingerprint(b, b.regimens.first), false);
    store.settings['formApprove'] = {'pack|r1': {'on': '2026-10-27', 'h': doseFingerprint(a, a.regimens.first)}};
    expect(doseStatus(a, a.regimens.first), DoseStatus.verified);
    expect(doseStatus(b, b.regimens.first), DoseStatus.invalid); // numbers changed after the approval
    store.settings['formApprove'] = {'pack|r1': '2026-10-01'}; // an approval of the older version
    expect(doseStatus(a, a.regimens.first), DoseStatus.invalid);
  });
}
