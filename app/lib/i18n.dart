import 'dart:ui' as ui;

import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';

import 'clinical_terms.dart';
import 'i18n_ar.dart';

/// Tiny built-in translation layer (English <-> Arabic), works fully offline.
///
/// * [Text] below is a drop-in replacement for Flutter's Text: every string
///   that matches a key of [kAr] is shown in Arabic when the app language is
///   Arabic. Data typed by the user never matches a key, so it is untouched.
/// * Composed sentences use [trp] ("{n} cases" style templates) and counted
///   nouns use [countLabel].
/// * Stored values (statuses, roles, tags...) always stay in English so old
///   files, backups and shared packs keep working in both languages.

const String kLangSystem = 'system';
const String kLangEn = 'en';
const String kLangAr = 'ar';

String _setting = kLangSystem;

/// Called by the store whenever the language preference changes.
void setLangSetting(String v) {
  _setting = (v == kLangEn || v == kLangAr) ? v : kLangSystem;
}

String get langSetting => _setting;

/// 'ar' or 'en' after resolving "follow the phone".
String get langCode {
  if (_setting == kLangEn) return 'en';
  if (_setting == kLangAr) return 'ar';
  return ui.PlatformDispatcher.instance.locale.languageCode == 'ar' ? 'ar' : 'en';
}

bool get isAr => langCode == 'ar';

Locale get appLocale => Locale(langCode);

/// Medical terms in the Arabic app: English by default (clinical wording is learned and
/// written in English), Arabic when the user chooses so in Settings.
bool medEnglish = true;

void setMedEnglish(bool v) => medEnglish = v;

String tr(String s) {
  if (!isAr) return s;
  if (medEnglish && kClinicalEnglish.contains(s)) return s;
  return kAr[s] ?? s;
}

final RegExp _rtlLetter = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
final RegExp _latinLetter = RegExp(r'[A-Za-z]');

/// Direction of a piece of text from its first letter: English words stay left-to-right
/// (so ":" and "(" land in the right place) even inside the Arabic app.
TextDirection? textDirectionFor(String s) {
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (_latinLetter.hasMatch(c)) return TextDirection.ltr;
    if (_rtlLetter.hasMatch(c)) return TextDirection.rtl;
  }
  return null;
}

/// Template with {name} placeholders, e.g. trp('Last backup: {n} days ago', {'n': 3}).
String trp(String template, Map<String, Object> args) {
  var out = tr(template);
  args.forEach((k, v) {
    out = out.replaceAll('{$k}', v.toString());
  });
  return out;
}

/// "3 cases" / "حالات 3": picks the right English or Arabic noun form.
/// [noun] is the singular English noun, e.g. 'case'.
String countLabel(int n, String noun) {
  if (!isAr) return '$n ${n == 1 ? noun : '${noun}s'}';
  final f = kArNouns[noun];
  if (f == null) return '$n $noun';
  // forms: [one, two, few (3-10), many (11+)]
  if (n == 0) return '0 ${f[3]}';
  if (n == 1) return f[0];
  if (n == 2) return f[1];
  if (n <= 10) return '$n ${f[2]}';
  return '$n ${f[3]}';
}

/// Range separator between two dates (a plain dash: arrows are missing from some fonts).
String get arrow => '–';

/// Keeps "#tag" in reading order inside right-to-left text.
String tagLabel(String t) => '\u200E#$t';

String weekdayName(int i) => isAr ? kArWeekdays[i] : kEnWeekdays[i];
String monthName(int i) => isAr ? kArMonths[i] : kEnMonths[i];

const List<String> kEnWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> kEnMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// Designer credit shown on the splash, home and About.
const String kDesignerEn = 'Dr. Mohammed Samir Abu Younis';
const String kDesignerAr = 'د. محمد سمير أبو يونس';
String get designerName => isAr ? kDesignerAr : kDesignerEn;
String get designedBy => isAr ? 'تصميم وتطوير' : 'Designed & developed by';

/// Drop-in replacement for Flutter's Text that translates literal UI strings.
class Text extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  const Text(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
  });

  @override
  Widget build(BuildContext context) {
    final s = tr(data);
    final dir = isAr ? textDirectionFor(s) : null;
    return m.Text(
      s,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: dir == TextDirection.ltr ? (textAlign ?? TextAlign.right) : textAlign,
      textDirection: dir == TextDirection.ltr ? TextDirection.ltr : null,
      softWrap: softWrap,
    );
  }
}
