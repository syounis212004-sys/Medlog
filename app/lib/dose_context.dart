import 'case_extras.dart';
import 'data.dart';

/// What the case already knows that the dose tools need, so it is not typed again: the weight, the sex and the last
/// creatinine with the day it was recorded. Age is not stored in the case (only child / adult), so it is asked.
class DoseContext {
  final String code, ageGroup, sex;
  final double? weightKg;
  final double? creatinineMgDl;
  final String creatinineDate;
  const DoseContext({this.code = '', this.ageGroup = '', this.sex = '', this.weightKg, this.creatinineMgDl, this.creatinineDate = ''});

  bool get isChild => ageGroup == 'Child';
  bool get isAdult => ageGroup == 'Adult';
  bool get female => sex.toUpperCase().startsWith('F');

  factory DoseContext.fromCase(CaseRec c) {
    final raw = c.s('v_wt').toLowerCase().replaceAll(',', '.');
    final m = RegExp(r'(\d+(\.\d+)?)').firstMatch(raw);
    var kg = m == null ? null : double.tryParse(m.group(1)!);
    if (kg != null && (raw.contains('lb') || raw.contains('pound'))) kg = kg * 0.45359237;
    double? cr;
    var date = '';
    for (final s in labSeries(c)) {
      final t = s.test.toLowerCase();
      if (t == 'cr' || t == 'scr' || t.contains('creatinine')) {
        final last = s.latest;
        cr = s.unit.toLowerCase().contains('mol') ? last.value / 88.4 : last.value;
        date = last.date;
        break;
      }
    }
    return DoseContext(code: c.s('code'), ageGroup: c.s('ageGroup'), sex: c.s('sex'), weightKg: kg, creatinineMgDl: cr, creatinineDate: date);
  }

  /// Whole days since the creatinine was recorded, or null.
  int? get creatinineAgeDays {
    final d = parseDate(creatinineDate);
    if (d == null) return null;
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  }

  /// Kidney function in mL/min from the case creatinine: Cockcroft-Gault for adults (needs age and weight), bedside
  /// Schwartz for children (needs height). Null when something needed is missing.
  ({double value, String method})? clearance({double? ageYears, double? weight, double? heightCm}) {
    final cr = creatinineMgDl;
    if (cr == null || cr <= 0 || ageYears == null) return null;
    if (ageYears >= 18) {
      final w = weight ?? weightKg;
      if (w == null) return null;
      return (value: ((140 - ageYears) * w) / (72 * cr) * (female ? 0.85 : 1.0), method: 'Cockcroft-Gault');
    }
    if (heightCm == null) return null;
    return (value: 0.413 * heightCm / cr, method: 'bedside Schwartz');
  }
}
