import 'dart:math' as math;

import 'formulary.dart';

/// The arithmetic of one regimen for one patient. It only multiplies and caps what the file says: it never picks a
/// regimen, never fills a missing number, and every cap that was applied is reported.

class DoseInput {
  final double? weightKg, ageMonths, heightCm;
  const DoseInput({this.weightKg, this.ageMonths, this.heightCm});
}

class DoseResult {
  /// Why the regimen cannot be calculated for this patient (empty when it can).
  final List<String> blockers;
  final List<String> notes, warnings;
  final String unit;
  final double? perDoseMin, perDoseMax, dailyMin, dailyMax, volumeMin, volumeMax;
  final String volumeUnit;
  final String formula;
  const DoseResult({
    this.blockers = const [],
    this.notes = const [],
    this.warnings = const [],
    this.unit = '',
    this.perDoseMin,
    this.perDoseMax,
    this.dailyMin,
    this.dailyMax,
    this.volumeMin,
    this.volumeMax,
    this.volumeUnit = '',
    this.formula = '',
  });
  bool get ok => blockers.isEmpty && perDoseMin != null;
}

class DoseCalc {
  static const Map<String, double> _toMg = {'mg': 1, 'g': 1000, 'mcg': 0.001, 'ug': 0.001, 'µg': 0.001};

  /// Converts [v] between mass units (mg, g, mcg); null when the units are not both masses of the same kind.
  static double? convert(double v, String from, String to) {
    final a = from.toLowerCase(), b = to.toLowerCase();
    if (a == b) return v;
    final fa = _toMg[a], fb = _toMg[b];
    if (fa == null || fb == null) return null;
    return v * fa / fb;
  }

  static double bsaMosteller(double kg, double cm) => math.sqrt(kg * cm / 3600);

  static bool _ageOk(FRegimen r, double m, List<String> why) {
    if (r.ageMin != null && (r.ageMinIncl ? m < r.ageMin! : m <= r.ageMin!)) {
      why.add('Age is below the range of this regimen.');
      return false;
    }
    if (r.ageMax != null && (r.ageMaxIncl ? m > r.ageMax! : m >= r.ageMax!)) {
      why.add('Age is above the range of this regimen.');
      return false;
    }
    return true;
  }

  static bool _weightOk(FRegimen r, double kg, List<String> why) {
    if (r.weightMin != null && (r.weightMinIncl ? kg < r.weightMin! : kg <= r.weightMin!)) {
      why.add('Weight is below the range of this regimen.');
      return false;
    }
    if (r.weightMax != null && (r.weightMaxIncl ? kg > r.weightMax! : kg >= r.weightMax!)) {
      why.add('Weight is above the range of this regimen.');
      return false;
    }
    return true;
  }

  /// Doses per day from the frequency fields: (min, max) or null when the file does not say.
  static (double, double)? dosesPerDay(FRegimen r) {
    if (r.once) return (1, 1);
    double? lo = r.tpdMin, hi = r.tpdMax;
    if (lo == null && hi == null && (r.intMin != null || r.intMax != null)) {
      final a = r.intMax ?? r.intMin, b = r.intMin ?? r.intMax; // longer interval = fewer doses
      lo = 24 / a!;
      hi = 24 / b!;
    }
    lo ??= hi;
    hi ??= lo;
    if (lo == null || hi == null) return null;
    return (math.min(lo, hi), math.max(lo, hi));
  }

  static DoseResult compute(FRegimen r, DoseInput p, {FForm? form}) {
    final block = <String>[];
    final notes = <String>[];
    final warn = <String>[];

    // who the regimen is for
    if (r.ageMin != null || r.ageMax != null) {
      if (p.ageMonths == null) {
        block.add('Enter the age: this regimen has an age range.');
      } else {
        _ageOk(r, p.ageMonths!, block);
      }
    }
    final needsWeight = r.dosePer == 'kg' || r.weightMin != null || r.weightMax != null || r.maxDailyPerKg != null || r.basis == 'bsa';
    if (needsWeight && p.weightKg == null) {
      block.add('Enter the weight.');
    } else if (p.weightKg != null && (r.weightMin != null || r.weightMax != null)) {
      _weightOk(r, p.weightKg!, block);
    }
    if (r.basis == 'bsa' && p.heightCm == null) block.add('Enter the height: this regimen is per body surface area.');
    if (r.doseMin == null && r.doseMax == null) block.add('The file gives no dose number for this regimen.');
    if (block.isNotEmpty) return DoseResult(blockers: block);

    final unit = r.doseUnit;
    final lo = r.doseMin ?? r.doseMax!, hi = r.doseMax ?? r.doseMin!;
    double factor = 1;
    var formula = '${_f(lo)}${lo == hi ? '' : '–${_f(hi)}'} $unit';
    if (r.dosePer == 'kg') {
      factor = p.weightKg!;
      formula += ' × ${_f(p.weightKg!)} kg';
    } else if (r.basis == 'bsa' || r.dosePer == 'm2') {
      factor = bsaMosteller(p.weightKg!, p.heightCm!);
      formula += ' × ${_f(factor)} m² (BSA)';
    }
    var aMin = lo * factor, aMax = hi * factor; // amount per dose or per day, as the regimen states

    final n = dosesPerDay(r);
    double? perMin, perMax, dayMin, dayMax;
    if (r.dosePerUnit == 'day') {
      dayMin = aMin;
      dayMax = aMax;
      if (n != null) {
        // the smallest dose uses the most doses per day and the largest dose the fewest
        perMin = aMin / n.$2;
        perMax = aMax / n.$1;
        if (n.$1 != n.$2) notes.add('The frequency is a range; the per-dose amount spans it.');
      } else {
        notes.add('The file gives no frequency, so only the daily total is shown.');
      }
    } else {
      perMin = aMin;
      perMax = aMax;
      if (n != null && !r.once) {
        dayMin = aMin * n.$1;
        dayMax = aMax * n.$2;
      }
    }

    // caps stated by the file
    if (r.maxSingle != null && perMax != null) {
      final cap = convert(r.maxSingle!, r.maxSingleUnit.isEmpty ? unit : r.maxSingleUnit, unit);
      if (cap == null) {
        warn.add('The single-dose maximum is in a unit that could not be compared: check it.');
      } else {
        if (perMin! > cap) perMin = cap;
        if (perMax > cap) {
          perMax = cap;
          warn.add('Capped at the single-dose maximum of ${_f(r.maxSingle!)} ${r.maxSingleUnit}.');
        }
      }
    }
    // the day follows the (capped) dose
    if (r.dosePerUnit != 'day' && n != null && !r.once && perMin != null && perMax != null) {
      dayMin = perMin * n.$1;
      dayMax = perMax * n.$2;
    }
    double? dailyCap;
    if (r.maxDaily != null) dailyCap = convert(r.maxDaily!, r.maxDailyUnit.isEmpty ? unit : r.maxDailyUnit, unit);
    if (r.maxDailyPerKg != null && p.weightKg != null) {
      final unitPerKg = r.maxDailyPerKgUnit.split('/').first.trim();
      final c = convert(r.maxDailyPerKg! * p.weightKg!, unitPerKg.isEmpty ? unit : unitPerKg, unit);
      if (c != null && (dailyCap == null || c < dailyCap)) dailyCap = c;
    }
    if (dailyCap != null && dayMax != null) {
      if (dayMax > dailyCap) warn.add('The daily total exceeds the stated maximum of ${_f(dailyCap)} $unit/day. The file’s limit applies.');
      if (dayMin! > dailyCap) dayMin = dailyCap;
      if (dayMax > dailyCap) dayMax = dailyCap;
      // a dose is never more than the capped day divided over the doses
      if (r.dosePerUnit == 'day' && n != null && perMin != null && perMax != null) {
        perMax = math.min(perMax, dailyCap / n.$1);
        perMin = math.min(perMin, dailyCap / n.$2);
      }
    }

    // volume or number of units from a product
    double? vMin, vMax;
    var vUnit = '';
    if (form != null && form.strength != null && form.per != null && perMin != null && perMax != null) {
      final perStrength = convert(perMin, unit, form.strengthUnit);
      final perStrengthMax = convert(perMax, unit, form.strengthUnit);
      if (perStrength == null || perStrengthMax == null) {
        warn.add('The product strength is in a unit that could not be compared with the dose.');
      } else {
        vMin = perStrength / form.strength! * form.per!;
        vMax = perStrengthMax / form.strength! * form.per!;
        vUnit = form.perUnit;
        if (form.productMatchRequired) notes.add('Check that your real product has this strength.');
      }
    }
    return DoseResult(
      notes: notes,
      warnings: warn,
      unit: unit,
      perDoseMin: perMin,
      perDoseMax: perMax,
      dailyMin: dayMin,
      dailyMax: dayMax,
      volumeMin: vMin,
      volumeMax: vMax,
      volumeUnit: vUnit,
      formula: formula,
    );
  }

  static String _f(double v) => fmt(v);

  /// Up to two decimals, without trailing zeros.
  static String fmt(double v) {
    var t = v.toStringAsFixed(2);
    if (t.contains('.')) t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return t;
  }
}
