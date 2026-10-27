import '../i18n.dart';
import 'ai_api.dart';

/// De-identification heuristics (HIPAA Safe Harbor style) for text that may leave the phone.
/// Heuristic, not a guarantee: the preview dialog is the second line of defence.
class AiPrivacyImpl {
  static const String _d = '[0-9٠-٩۰-۹]';
  static const String _dc = '0-9\u0660-\u0669\u06F0-\u06F9';
  static const String _ar = '[ء-ي]';
  static const String _months =
      '(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)';
  static const String _arMonths =
      '(?:يناير|فبراير|مارس|أبريل|ابريل|مايو|يونيو|يوليو|أغسطس|اغسطس|سبتمبر|أكتوبر|اكتوبر|نوفمبر|ديسمبر|كانون الثاني|كانون الأول|شباط|آذار|نيسان|أيار|حزيران|تموز|آب|أيلول|تشرين الأول|تشرين الثاني)';

  static final List<_Rule> _rules = _build();

  static List<_Rule> _build() {
    RegExp r(String s, {bool ci = false}) => RegExp(s, caseSensitive: !ci, unicode: false);
    return [
      _Rule('Email', r(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'), '[email]'),
      _Rule('Web address', r(r'(?:https?://|www\.)[^\s<>"]+', ci: true), '[url]'),
      _Rule('IP address', r(r'\b\d{1,3}(?:\.\d{1,3}){3}\b'), '[ip]'),
      // exact dates
      _Rule('Date', r('\\b\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}\\b'), '[date]'),
      _Rule('Date', r('(?<![\\d/.\\-])$_d{1,2}[/.\\-]$_d{1,2}[/.\\-]$_d{2,4}(?![\\d/\\-]|\\.\\d)'), '[date]'),
      _Rule('Date', r('\\b\\d{1,2}(?:st|nd|rd|th)?\\s+(?:of\\s+)?$_months\\.?,?(?:\\s+\\d{4})?\\b', ci: true), '[date]'),
      _Rule('Date', r('\\b$_months\\.?\\s+\\d{1,2}(?:st|nd|rd|th)?\\b(?:,?\\s+\\d{4})?', ci: true), '[date]'),
      _Rule('Date', r('$_d{1,2}\\s+$_arMonths(?:\\s+$_d{4})?'), '[date]'),
      _Rule('Date', r('$_arMonths\\s+$_d{1,2}(?:\\s*,?\\s*$_d{4})?'), '[date]'),
      // phones
      _Rule('Phone number', r('(?:\\+|\\b00)\\d{1,3}[\\s\\-.()]*\\d[\\d\\s\\-.()]{6,14}\\d'), '[phone]'),
      _Rule('Phone number', r('(?<![\\d])(?:0?7[789])[\\s\\-]?\\d{3}[\\s\\-]?\\d{4}(?!\\d)'), '[phone]'),
      _Rule('Phone number', r('(?<![\\d])05\\d[\\s\\-]?\\d{3}[\\s\\-]?\\d{4}(?!\\d)'), '[phone]'),
      _Rule('Phone number', r('(?<![\\d])\\(?\\d{3}\\)?[\\s.\\-]\\d{3}[\\s.\\-]\\d{4}(?!\\d)'), '[phone]'),
      _Rule('Phone number', r('(?<![\\d])0$_d[\\s\\-]?$_d{3}[\\s\\-]?$_d{4}(?!\\d)'), '[phone]'),
      // labelled identifiers (short numbers too)
      _Rule(
          'ID number',
          r('(?<![A-Za-z])(?:MRN|M\\.R\\.N|file\\s*(?:no|number|#)|record\\s*(?:no|number|#)|patient\\s*(?:id|no|number)|national\\s*id|ID\\s*(?:no|number|#)?|SSN|passport|رقم الملف|الرقم الوطني|رقم الهوية|رقم المريض|الهوية|جواز)\\s*[:#.\\-]?\\s*[A-Za-z]{0,3}[0-9٠-٩][A-Za-z0-9٠-٩\\-]*', ci: true),
          '[id]'),
      _Rule('ID number', r('(?<![\\w.])[A-Za-z]{0,3}$_d[$_dc\\-]{5,}(?![\\w])'), '[id]'),
      // hospitals / clinics
      _Rule('Hospital', r("\\b(?:(?:[A-Z][\\w'&\\-]*\\.?\\s+){1,4}(?:Hospital|Medical (?:City|Center|Centre)|Clinics?|Health (?:Center|Centre)|Cancer (?:Center|Centre)|Polyclinic)|Hospital of (?:[A-Z][\\w'&\\-]*\\s?){1,3})\\b"), '[hospital]'),
      // addresses
      _Rule('Address', r("\\b\\d{1,5}\\s+(?:[A-Z][\\w'\\-]*\\s+){1,3}(?:Street|St|Road|Rd|Avenue|Ave|Boulevard|Blvd|Lane|Ln|Drive|Dr)\\b\\.?"), '[address]'),
      _Rule('Address', r("\\b(?:[A-Z][\\w'\\-]*\\s+){1,3}(?:Street|Road|Avenue|Boulevard)\\b"), '[address]'),
      _Rule('Address', r('\\bP\\.?\\s?O\\.?\\s*Box\\s*\\d+', ci: true), '[address]'),
      _Rule('Address', r('(?:شارع|حي|ص\\.ب\\.?|صندوق بريد)\\s+[ء-ي0-9٠-٩]+(?:\\s+[ء-ي0-9٠-٩]+){0,2}'), '[address]'),
      // ages over 89
      _Rule('Age over 89', r('\\b(?:9\\d|1[01]\\d)[\\s\\-]?(?:years?|yrs?|y/o|yo|year-old)(?:\\s+old)?\\b', ci: true), '90+ years'),
    ];
  }

  static const Set<String> _enStop = {
    'Is', 'Was', 'Has', 'Had', 'With', 'Presents', 'Presented', 'Denies', 'Reports', 'Admitted', 'Not', 'No', 'History', 'Male', 'Female', 'Of',
    'The', 'A', 'An', 'In', 'On', 'Complains', 'Known', 'And', 'Who', 'Came', 'Comes', 'Aged', 'Age', 'Diagnosed', 'Underwent', 'Seen', 'Referred',
    'Under', 'After', 'Before', 'Due', 'For', 'To', 'From', 'At', 'By', 'Presenting', 'Developed', 'Became', 'Suffering', 'Gave', 'Takes', 'Taking',
  };
  static const Set<String> _arStop = {
    'يعاني', 'تعاني', 'عمره', 'عمرها', 'البالغ', 'البالغة', 'مصاب', 'مصابة', 'لديه', 'لديها', 'في', 'من', 'الذي', 'التي', 'يشكو', 'تشكو', 'عمر',
    'ذو', 'ذات', 'حضر', 'حضرت', 'جاء', 'جاءت', 'ويعاني', 'وتعاني', 'على', 'إلى', 'الى', 'بعد', 'قبل', 'مع', 'بدون', 'ذكر', 'أنثى', 'يبلغ', 'تبلغ',
    'مريض', 'مريضة', 'أدخل', 'أدخلت', 'دخل', 'دخلت', 'راجع', 'راجعت', 'شخص', 'شخصت', 'تم', 'كان', 'كانت', 'لا', 'ما', 'هو', 'هي',
  };

  static final RegExp _enTitle = RegExp(
      r"\b(?:[Mm]r|[Mm]rs|[Mm]s|[Mm]iss|[Dd]r|[Pp]rof|Professor|MR|MRS|DR)\b\.?\s+([A-Z][a-z'\-]+(?:\s+[A-Z][a-z'\-]+){0,2})");
  static final RegExp _enCue = RegExp(
      r"\b(?:[Pp]atient|[Pp]t|[Nn]ame is|[Nn]amed|[Cc]alled|[Hh]is name|[Hh]er name|[Nn]ame|[Ss]on of|[Dd]aughter of|[Ww]ife of|[Hh]usband of|[Mm]other|[Ff]ather|[Bb]rother|[Ss]ister|[Ss]pouse|[Nn]ext of kin|NOK)\s*[:\-]?\s*((?:[A-Z][a-z'\-]+)(?:\s+[A-Z][a-z'\-]+){0,3})");
  static final RegExp _arTitle = RegExp(
      '(?:للسيد|السيد|السيدة|الآنسة|الدكتورة|الدكتور|دكتورة|دكتور|الأستاذ|الاستاذ|الحاج|الحاجة|د\\.|الشيخ)\\s*($_ar+(?:\\s+$_ar+){0,3})');
  static final RegExp _arCue = RegExp('(?:اسمه|اسمها|يدعى|تدعى|المدعو|المدعوة|اسم المريض|اسم المريضة|زوجة|زوج|ابن|ابنة|والد|والدة)\\s*[:\\-]?\\s*($_ar+(?:\\s+$_ar+){0,3})');
  static final RegExp _arHospWords = RegExp('(?:مستشفى|مركز)\\s+($_ar+(?:\\s+$_ar+){0,3})');

  static ScrubResult scrub(String text) {
    var t = text;
    final counts = <String, int>{};
    void hit(String label) => counts[label] = (counts[label] ?? 0) + 1;

    // names first: they contain no digits; stop at stop-words so clinical text is not eaten
    t = t.replaceAllMapped(_enTitle, (m) {
      final words = _takeEn(m.group(1)!);
      if (words.isEmpty) return m.group(0)!;
      hit('Name');
      final rest = m.group(1)!.substring(words.join(' ').length);
      return '[name]$rest';
    });
    t = t.replaceAllMapped(_enCue, (m) {
      final words = _takeEn(m.group(1)!);
      if (words.isEmpty) return m.group(0)!;
      hit('Name');
      final taken = words.join(' ');
      final whole = m.group(0)!;
      final i = whole.lastIndexOf(m.group(1)!);
      return '${whole.substring(0, i)}[name]${m.group(1)!.substring(taken.length)}';
    });
    t = t.replaceAllMapped(_arTitle, (m) => _arRepl(m, hit));
    t = t.replaceAllMapped(_arCue, (m) => _arRepl(m, hit));
    // Arabic hospital names ("عيادة" alone is too generic: only with a following name that is not a stop-word)
    t = t.replaceAllMapped(_arHospWords, (m) {
      final words = _takeAr(m.group(1)!);
      if (words.isEmpty) return m.group(0)!;
      hit('Hospital');
      final whole = m.group(0)!;
      final i = whole.lastIndexOf(m.group(1)!);
      return '${whole.substring(0, i)}[hospital]${m.group(1)!.substring(words.join(' ').length)}';
    });

    for (final rule in _rules) {
      t = t.replaceAllMapped(rule.re, (m) {
        hit(rule.label);
        return rule.repl;
      });
    }
    final removed = <String>[
      for (final e in counts.entries) e.value > 1 ? '${tr(e.key)} ×${e.value}' : tr(e.key),
    ];
    return ScrubResult(t, removed);
  }

  static List<String> _takeEn(String s) {
    final out = <String>[];
    for (final w in s.split(RegExp(r'\s+'))) {
      if (_enStop.contains(w)) break;
      out.add(w);
    }
    return out;
  }

  static List<String> _takeAr(String s) {
    final out = <String>[];
    for (final w in s.split(RegExp(r'\s+'))) {
      if (_arStop.contains(w) || w.startsWith('و') && _arStop.contains(w.substring(1))) break;
      out.add(w);
    }
    return out;
  }

  static String _arRepl(Match m, void Function(String) hit) {
    final words = _takeAr(m.group(1)!);
    if (words.isEmpty) return m.group(0)!;
    hit('Name');
    final whole = m.group(0)!;
    final i = whole.lastIndexOf(m.group(1)!);
    return '${whole.substring(0, i)}[name]${m.group(1)!.substring(words.join(' ').length)}';
  }
}

class _Rule {
  final String label;
  final RegExp re;
  final String repl;
  _Rule(this.label, this.re, this.repl);
}
