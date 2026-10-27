import 'dart:math';

/// Clinical calculators. Formulas are the standard published ones; each one names
/// its source so it can be checked. For learning: always confirm with your hospital's protocol.

class CalcResult {
  final String value;
  final String meaning;
  const CalcResult(this.value, this.meaning);
}

double bmi(double kg, double cm) => kg / pow(cm / 100, 2);

String bmiClass(double v) {
  if (v < 18.5) return 'Underweight';
  if (v < 25) return 'Normal weight';
  if (v < 30) return 'Overweight';
  return 'Obesity';
}

double map(double sbp, double dbp) => (sbp + 2 * dbp) / 3;

double anionGap(double na, double cl, double hco3) => na - (cl + hco3);

/// Corrected calcium (mg/dL) for albumin in g/dL: Ca + 0.8 x (4.0 - albumin).
double correctedCalcium(double ca, double albumin) => ca + 0.8 * (4.0 - albumin);

/// Bazett: QT / sqrt(RR in seconds). [hr] beats per minute.
double qtcBazett(double qtMs, double hr) => qtMs / sqrt(60 / hr);

/// CKD-EPI 2021 creatinine equation (no race coefficient). Scr in mg/dL.
double egfrCkdEpi2021(double scr, int age, bool female) {
  final k = female ? 0.7 : 0.9;
  final a = female ? -0.241 : -0.302;
  final r = scr / k;
  return 142 * pow(min(r, 1.0), a) * pow(max(r, 1.0), -1.200) * pow(0.9938, age) * (female ? 1.012 : 1.0);
}

/// Cockcroft-Gault creatinine clearance (mL/min), actual body weight in kg, Scr in mg/dL.
double cockcroftGault(int age, double kg, double scr, bool female) => ((140 - age) * kg) / (72 * scr) * (female ? 0.85 : 1.0);

int gcs(int eye, int verbal, int motor) => eye + verbal + motor;

String gcsClass(int v) {
  if (v >= 13) return 'Mild (13-15)';
  if (v >= 9) return 'Moderate (9-12)';
  return 'Severe (3-8)';
}

/// CURB-65: confusion, urea > 7 mmol/L (BUN > 19 mg/dL), RR >= 30, SBP < 90 or DBP <= 60, age >= 65.
int curb65({required bool confusion, required bool urea, required bool rr, required bool bp, required bool age}) =>
    [confusion, urea, rr, bp, age].where((e) => e).length;

String curb65Risk(int s) => s <= 1 ? 'Low risk (0-1)' : (s == 2 ? 'Moderate risk (2)' : 'High risk (3-5)');

/// Wells criteria for DVT (two-level): 2 or more = DVT likely.
const List<List<Object>> kWellsDvt = [
  ['Active cancer (treatment within 6 months or palliative)', 1],
  ['Paralysis, paresis or recent plaster immobilisation of the leg', 1],
  ['Bedridden 3+ days or major surgery within 12 weeks', 1],
  ['Localised tenderness along the deep venous system', 1],
  ['Entire leg swollen', 1],
  ['Calf swelling more than 3 cm compared with the other leg', 1],
  ['Pitting oedema confined to the symptomatic leg', 1],
  ['Collateral superficial veins (non-varicose)', 1],
  ['Previously documented DVT', 1],
  ['Alternative diagnosis at least as likely as DVT', -2],
];

/// Wells criteria for PE (two-level): more than 4 = PE likely.
const List<List<Object>> kWellsPe = [
  ['Clinical signs and symptoms of DVT', 3],
  ['PE is the most likely diagnosis (or equally likely)', 3],
  ['Heart rate above 100', 1.5],
  ['Immobilisation (3+ days) or surgery in the previous 4 weeks', 1.5],
  ['Previous PE or DVT', 1.5],
  ['Haemoptysis', 1],
  ['Malignancy (treatment within 6 months or palliative)', 1],
];

/// CHA2DS2-VASc for stroke risk in atrial fibrillation.
const List<List<Object>> kChadsVasc = [
  ['Congestive heart failure / LV dysfunction', 1],
  ['Hypertension', 1],
  ['Age 75 or more', 2],
  ['Diabetes mellitus', 1],
  ['Prior stroke / TIA / thromboembolism', 2],
  ['Vascular disease (prior MI, PAD, aortic plaque)', 1],
  ['Age 65-74', 1],
  ['Female sex', 1],
];

double sumChecked(List<List<Object>> items, Set<int> checked) {
  var t = 0.0;
  for (final i in checked) {
    t += (items[i][1] as num).toDouble();
  }
  return t;
}

/// Maintenance fluid for children by the 4-2-1 rule (mL/hour).
double maintenanceFluid421(double kg) {
  if (kg <= 10) return 4 * kg;
  if (kg <= 20) return 40 + 2 * (kg - 10);
  return 60 + (kg - 20);
}

/// Naegele's rule: expected date of delivery = LMP + 280 days.
DateTime eddFromLmp(DateTime lmp) => lmp.add(const Duration(days: 280));

/// Gestational age on [today] as (weeks, days).
(int, int) gestationalAge(DateTime lmp, DateTime today) {
  final d = today.difference(lmp).inDays;
  return (d ~/ 7, d % 7);
}
