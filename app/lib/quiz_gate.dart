import 'lib_text.dart';
import 'lib_user.dart' show quizHash;
import 'library.dart' show stripSource;

/// Question types and the quality gate of the self-test. Every question is made only from article text;
/// the gate drops the ones that are broken, ambiguous, trivially guessable or that leak their answer.

enum QKind { definition, cloze, treatment, symptom, number, management, redflag, trueFalse }

class QuizQ {
  final QKind kind;
  final String stem;
  final List<String> options;
  final int answer;
  final String explanation;
  final String packId;
  final String title;
  final int index;

  /// Article title used in the question line of the treatment / symptom kinds.
  final String prompt;
  final QuizLevel level;

  /// Heading of the article section the question came from ('' for the opening paragraph).
  final String section;

  /// Core 250 specialty of the article (or the course title for other articles): used by the result summary.
  final String group;
  const QuizQ({
    required this.kind,
    required this.stem,
    required this.options,
    required this.answer,
    required this.explanation,
    required this.packId,
    required this.title,
    required this.index,
    this.prompt = '',
    this.level = QuizLevel.medium,
    this.section = '',
    this.group = '',
  });

  /// The article title as shown to the learner (without " — WikEM" style suffix).
  String get shownTitle => stripSource(title);
  String get correct => options[answer];
  String get hash => quizHash(stem, correct);
  bool get isTrueFalse => kind == QKind.trueFalse;

  /// English question line used on a review card (the stem alone is not always a question).
  String get cardFront {
    final t = prompt.isEmpty ? shownTitle : prompt;
    switch (kind) {
      case QKind.definition:
        return 'Which topic is described here?\n\n$stem';
      case QKind.cloze:
        return 'Fill in the blank ($t):\n\n$stem';
      case QKind.treatment:
        return 'Treatment of $t:\n\n$stem';
      case QKind.symptom:
        return 'Which finding is described for $t?';
      case QKind.number:
        return 'Fill in the value ($t):\n\n$stem';
      case QKind.management:
      case QKind.redflag:
        return stem;
      case QKind.trueFalse:
        return 'True or false? ($t)\n\n$stem';
    }
  }

  String get cardBack => '${correct}\n\n$explanation';
}

enum QuizLevel { easy, medium, hard, auto }

// ---------------------------------------------------------------- text hygiene

final RegExp _boiler = RegExp(
    r'national library of medicine|medlineplus|\bpdq\b|this (pdq )?summary|©|copyright|all rights reserved|disclaimer|last (updated|reviewed|modified)|reviewed by|for more information|\bvisit\b|\bclick\b|www\.|https?:|@|\d{3}[-. ]\d{3,4}[-. ]\d{4}|\bcall (the|us|your|911)\b|references?:|see also|further reading|external links|source:|doi:|pmid|isbn|\bwikem\b|wikipedia|\bsubscribe\b|\bcdc\.gov\b|\bfigure \d|\bfig\.? ?\d|\btable \d|\(see (figure|table)|\bthe following (topics|links)|\bclinician outreach|\bhealth (alert|advisory)\b|\bpress release\b|\bwebsite\b|\bweb page\b|\bemail\b|\bonline (at|resource)\b|\bplease\b',
    caseSensitive: false);

final RegExp _captionStart = RegExp(
    r'^(fig(ure|\.)?\b|image\b|photo(graph)?\b|picture\b|diagram\b|illustration\b|micrograph\b|radiograph of\b|x-ray of\b|ct (scan )?of\b|mri of\b|ecg (showing|of)\b|histolog|sketch\b|drawing\b|schematic\b|chart\b|graph\b|map of\b|a (patient|man|woman|child|boy|girl) with\b|an? [a-z -]{0,40}(showing|demonstrating|revealing)\b|source\b|credit\b)',
    caseSensitive: false);
final RegExp _captionInside = RegExp(r'\((left|right|top|bottom|upper|lower|top left|top right|a|b|c|d)\)|\b(arrow|arrows|arrowhead|asterisk|pictured|shown (above|below|here)|as seen (in|on) the (image|figure))\b', caseSensitive: false);

/// True for text that looks like a picture caption, a heading fragment or a source line.
bool looksLikeCaption(String s) {
  final t = s.trim();
  if (_captionStart.hasMatch(t)) return true;
  if (_captionInside.hasMatch(t)) return true;
  return false;
}

bool hasBoilerplate(String s) => _boiler.hasMatch(s);

/// A sentence or bullet that can be used as a fact: readable, not a caption, not boilerplate.
bool cleanFact(String s, {int minLen = 15, int maxLen = 420}) {
  final t = s.trim();
  if (t.length < minLen || t.length > maxLen) return false;
  if (hasBoilerplate(t) || looksLikeCaption(t)) return false;
  if (t.contains('▸') || t.contains('|') || t.contains('[') || t.contains(']') || t.contains('{')) return false;
  var letters = 0;
  for (final c in t.runes) {
    if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c > 191) letters++;
  }
  if (letters < t.length * 0.62) return false;
  if (!RegExp(r'^[A-Z0-9αβγ"(≥≤><]').hasMatch(t)) return false;
  return true;
}

/// Light clean-up of a source sentence (phonetics, citations, double spaces).
String tidy(String s) => s
    .replaceAll(RegExp(r'\s*\([^)]*[/ˈˌ][^)]*\)'), '')
    .replaceAll(RegExp(r'\[\d+\]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r'\s+([.,;])'), (m) => m[1]!)
    .trim();

// ---------------------------------------------------------------- distinctive words

const Set<String> kGenericWords = {
  'treatment', 'patients', 'patient', 'consider', 'considered', 'monitor', 'monitoring', 'therapy', 'medical', 'within', 'should', 'would', 'could', 'during', 'before', 'after', 'because',
  'however', 'including', 'include', 'includes', 'usually', 'typically', 'commonly', 'often', 'given', 'indicated', 'management', 'evaluation', 'consult', 'consultation', 'admit', 'admission',
  'discharge', 'follow', 'followup', 'assess', 'assessment', 'support', 'supportive', 'severe', 'moderate', 'symptoms', 'symptom', 'disease', 'diseases', 'condition', 'conditions', 'clinical',
  'diagnosis', 'oxygen', 'fluids', 'resuscitation', 'maintain', 'avoid', 'repeat', 'continue', 'immediate', 'immediately', 'urgent', 'emergent', 'blood', 'pressure', 'history', 'physical',
  'examination', 'laboratory', 'testing', 'tests', 'result', 'results', 'increase', 'increased', 'decrease', 'decreased', 'associated', 'related', 'present', 'presents', 'presentation',
  'chronic', 'acute', 'primary', 'secondary', 'people', 'children', 'adults', 'doctor', 'health', 'hospital', 'emergency', 'department', 'underlying', 'cause', 'causes', 'caused',
  'require', 'requires', 'required', 'recommended', 'recommend', 'recommendations', 'prevent', 'prevention', 'complications', 'complication', 'severity', 'stable', 'unstable',
};

/// Lower-case words of at least six letters that are not generic (the "distinctive" words of a line).
Set<String> distinctiveWords(String s) {
  final out = <String>{};
  for (final m in RegExp(r"[A-Za-z][A-Za-z\-]{5,}").allMatches(s)) {
    final w = m.group(0)!.toLowerCase();
    if (!kGenericWords.contains(w)) out.add(w);
  }
  return out;
}

// ---------------------------------------------------------------- option conflation

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('ae', 'e')
    .replaceAll('oe', 'e')
    .replaceAll(RegExp(r'\b(hours?|hrs?)\b'), 'hour')
    .replaceAll(RegExp(r'\b(minutes?|mins?)\b'), 'minute')
    .replaceAll(RegExp(r'\b(seconds?|secs?)\b'), 'second')
    .replaceAll(RegExp(r'\b(grams?)\b'), 'g')
    .replaceAll(RegExp(r'[^a-z0-9α-ω]+'), ' ')
    .trim();

String _stem(String w) => w.length > 4 && w.endsWith('s') && !w.endsWith('ss') ? w.substring(0, w.length - 1) : w;

Set<String> _contentWords(String s) => {for (final w in _norm(s).split(' ')) if (w.length >= 4) _stem(w)};

bool _wholeWord(String hay, String needle) {
  if (needle.isEmpty) return false;
  return ' $hay '.contains(' $needle ');
}

/// True when two options could be the same answer: equal, one inside the other, plural / spelling
/// variants, an abbreviation of the other, or almost the same words.
bool optionsConflate(String a, String b) {
  var x = _norm(a), y = _norm(b);
  if (x.isEmpty || y.isEmpty) return x == y;
  if (x == y) return true;
  final ex = kLibAbbrev[x], ey = kLibAbbrev[y];
  if (ex != null && (_norm(ex) == y || _wholeWord(y, _norm(ex)) || _wholeWord(_norm(ex), y))) return true;
  if (ey != null && (_norm(ey) == x || _wholeWord(x, _norm(ey)) || _wholeWord(_norm(ey), x))) return true;
  if (x.length >= 3 && y.length >= 3 && (_wholeWord(x, y) || _wholeWord(y, x))) return true;
  if (x.length >= 4 && y.length >= 4 && (x.contains(y) || y.contains(x))) return true;
  final sx = x.split(' ').map(_stem).join(' '), sy = y.split(' ').map(_stem).join(' ');
  if (sx == sy) return true;
  String initials(String t) => t.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).join();
  if (!x.contains(' ') && x.length >= 2 && x.length <= 6 && y.contains(' ') && initials(y) == x) return true;
  if (!y.contains(' ') && y.length >= 2 && y.length <= 6 && x.contains(' ') && initials(x) == y) return true;
  if (x.length >= 7 && y.length >= 7 && x.length <= 40 && y.length <= 40 && (x.length - y.length).abs() <= 2 && editDistance(x, y, max: 2) <= 2) return true;
  final cx = _contentWords(a), cy = _contentWords(b);
  if (cx.length >= 2 && cy.length >= 2) {
    final inter = cx.intersection(cy).length;
    final uni = cx.union(cy).length;
    if (inter / uni >= 0.75) return true;
  }
  return false;
}

/// First [need] options that are distinct from [answer] and from each other (no synonyms / abbreviations / substrings).
List<String>? pickDistinctOptions(Iterable<String> ordered, String answer, int need, {bool Function(String)? ok}) {
  final out = <String>[];
  for (final c in ordered) {
    final t = c.trim();
    if (t.isEmpty || optionsConflate(t, answer)) continue;
    if (out.any((e) => optionsConflate(e, t))) continue;
    if (ok != null && !ok(t)) continue;
    out.add(t);
    if (out.length == need) return out;
  }
  return null;
}

/// Findings so common that they fit almost any condition: never used as key or as wrong option of "which finding".
const Set<String> kGenericFindings = {
  'fatigue', 'fever', 'pain', 'nausea', 'vomiting', 'headache', 'dizziness', 'weakness', 'malaise', 'chest pain', 'shortness of breath', 'weight loss', 'weight gain', 'cough', 'diarrhea',
  'diarrhoea', 'constipation', 'abdominal pain', 'swelling', 'rash', 'anxiety', 'depression', 'confusion', 'sweating', 'chills', 'loss of appetite', 'tiredness', 'palpitations', 'syncope',
  'back pain', 'joint pain', 'muscle pain', 'sleep problems', 'insomnia', 'irritability', 'lethargy', 'dyspnea', 'dyspnoea', 'tachycardia', 'hypotension', 'hypertension', 'bleeding',
  'itching', 'pruritus', 'edema', 'oedema', 'cramps', 'numbness', 'tingling', 'seizures', 'seizure', 'coma', 'death', 'loss of consciousness', 'difficulty breathing', 'muscle weakness',
  'interest', 'cardiac', 'neurologic', 'vascular', 'pulmonary', 'abdominal', 'respiratory', 'neurological', 'stones', 'assessment', 'circulatory shock', 'shock', 'cardiac arrest', 'respiratory failure', 'hypoxia', 'sepsis', 'altered mental status', 'dehydration', 'hypovolemia', 'acidosis', 'hypoglycemia', 'hyperglycemia', 'organ failure', 'kidney failure', 'renal failure', 'heart failure', 'respiratory distress', 'cyanosis', 'tachypnea', 'hypotonia',
  'blurred vision', 'vision problems', 'hair loss', 'fainting', 'agitation', 'restlessness', 'poor appetite', 'abdominal discomfort', 'discomfort', 'tenderness', 'redness', 'jaundice',
};

bool isGenericFinding(String s) => kGenericFindings.contains(_norm(s));

// ---------------------------------------------------------------- the gate

class GateResult {
  final int score;
  final List<String> issues;
  final bool hard;
  const GateResult(this.score, this.issues, this.hard);
  bool get ok => !hard && score >= kGateMin;
  @override
  String toString() => '$score ${issues.join(', ')}';
}

const int kGateMin = 75;

bool _leaks(String stem, String option) {
  final st = _norm(stem);
  final o = _norm(option);
  if (o.length < 3) return false;
  if (_wholeWord(st, o)) return true;
  final words = distinctiveWords(option);
  if (words.isNotEmpty) {
    var hit = 0;
    for (final w in words) {
      // a word of the answer (or its plural / near form) inside the stem
      if (st.contains(w.length > 7 ? w.substring(0, w.length - 2) : w)) hit++;
    }
    if (hit == words.length && words.length >= 1 && o.split(' ').length <= 4) return true;
  }
  return false;
}

/// Scores a generated question (0..100) and lists what is wrong. Hard failures (broken, ambiguous, leaking)
/// always drop the question; soft problems lower the score under [kGateMin].
GateResult gateQuestion(QuizQ q) {
  final issues = <String>[];
  var score = 100;
  var hard = false;
  void fail(String m) {
    hard = true;
    issues.add('X:$m');
  }

  void pen(int n, String m) {
    score -= n;
    issues.add('-$n:$m');
  }

  final stem = q.stem.trim();
  final opts = q.options;
  if (q.isTrueFalse) {
    if (opts.length != 2 || opts[0] != 'True' || opts[1] != 'False') fail('tf options');
  } else if (opts.length != 4) {
    fail('need 4 options');
  }
  if (q.answer < 0 || q.answer >= opts.length) {
    fail('answer index');
    return GateResult(0, issues, true);
  }
  final correct = opts[q.answer];
  if (q.explanation.trim().isEmpty) fail('no explanation');
  if (q.title.isEmpty || q.packId.isEmpty) fail('no source');

  // stem hygiene
  final plain = stem.replaceAll('____', ' ');
  final words = plain.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (stem.length < 20) fail('stem too short');
  if (stem.length > 430) fail('stem too long');
  if (words < 5) fail('stem has fewer than 5 words');
  if (hasBoilerplate(stem)) fail('boilerplate in stem');
  if (looksLikeCaption(stem) && q.kind != QKind.management && q.kind != QKind.redflag) fail('caption-like stem');
  if (RegExp(r'[▸•|\[\]{}]').hasMatch(stem)) fail('debris in stem');
  if (stem.endsWith(':') && q.kind != QKind.management && q.kind != QKind.redflag) fail('stem ends with colon');
  if (RegExp(r'^[a-z]').hasMatch(stem) && q.kind != QKind.symptom) pen(10, 'stem starts lowercase');

  final blanks = '____'.allMatches(stem).length;
  switch (q.kind) {
    case QKind.cloze:
    case QKind.treatment:
    case QKind.number:
      if (blanks != 1) fail('needs exactly one blank');
      if (stem.startsWith('____') && q.kind != QKind.definition) pen(10, 'blank first');
      break;
    case QKind.definition:
      if (blanks < 1 || blanks > 2) fail('definition blanks');
      if (words < 9) fail('definition too short');
      break;
    case QKind.symptom:
      break;
    default:
      if (blanks > 0) fail('unexpected blank');
  }
  if (q.kind == QKind.number && words < 7) fail('number stem too short');
  if (q.kind == QKind.cloze || q.kind == QKind.treatment) {
    if (words < 9) fail('too little context');
    if (distinctiveWords(plain).isEmpty) pen(15, 'no distinctive word in stem');
  }

  // options
  for (final o in opts) {
    if (o.trim().isEmpty) fail('empty option');
    if (o.length > 175) fail('option too long');
    if (o.contains('____')) fail('blank in option');
    if (hasBoilerplate(o)) fail('boilerplate option');
    if (RegExp(r'[▸•|\[\]{}]').hasMatch(o)) fail('debris in option');
    if (!q.isTrueFalse && o.trim().length < 2) fail('option too short');
  }
  if (!q.isTrueFalse) {
    for (var i = 0; i < opts.length; i++) {
      for (var j = i + 1; j < opts.length; j++) {
        if (optionsConflate(opts[i], opts[j])) fail('options conflate: "${opts[i]}" ~ "${opts[j]}"');
      }
    }
    // leakage
    if (q.kind != QKind.number) {
      if (_leaks(stem, correct)) fail('answer appears in the stem');
    }
    for (var i = 0; i < opts.length; i++) {
      if (i == q.answer) continue;
      if (q.kind != QKind.number && _leaks(stem, opts[i])) fail('wrong option appears in the stem: "${opts[i]}"');
    }
    // shape cues
    final lens = [for (final o in opts) o.length];
    final minL = lens.reduce((a, b) => a < b ? a : b), maxL = lens.reduce((a, b) => a > b ? a : b);
    if (minL > 0 && maxL / minL > 3.5 && maxL > 30) pen(20, 'option lengths differ a lot');
    final others = [for (var i = 0; i < opts.length; i++) if (i != q.answer) lens[i]];
    final maxOther = others.reduce((a, b) => a > b ? a : b);
    if (correct.length > 30 && correct.length > maxOther * 1.7) pen(15, 'the longest option is the answer');
    final upper = RegExp(r'^[A-Z]');
    final aUp = upper.hasMatch(correct);
    if (opts.asMap().entries.where((e) => e.key != q.answer).every((e) => upper.hasMatch(e.value) != aUp)) pen(10, 'capitalisation cue');
    final aDig = RegExp(r'\d').hasMatch(correct);
    if (opts.asMap().entries.where((e) => e.key != q.answer).every((e) => RegExp(r'\d').hasMatch(e.value) != aDig)) pen(15, 'digit cue');
    final aw = correct.split(' ').length;
    if (opts.asMap().entries.where((e) => e.key != q.answer).every((e) => (e.value.split(' ').length - aw).abs() >= 4)) pen(10, 'word-count cue');
    if (q.kind == QKind.symptom || q.kind == QKind.redflag) {
      for (final o in opts) {
        if (isGenericFinding(o)) pen(30, 'generic finding "$o"');
      }
    }
    if (q.kind == QKind.definition) {
      final stemLow = _norm(stem);
      for (final o in opts) {
        if (_wholeWord(stemLow, _norm(o))) fail('title inside definition stem');
      }
    }
  }
  if (score < 0) score = 0;
  return GateResult(score, issues, hard);
}

// ---------------------------------------------------------------- numbers with units

const String _unitAlt =
    r'mg/kg/day|mg/kg/dose|mg/kg/h(?:r|our)?|mg/kg|mcg/kg/min|mcg/kg/h(?:r|our)?|mcg/kg|µg/kg|mg/dL|mg/L|g/dL|g/L|mmol/L|mEq/L|mEq|mmHg|mL/kg/h(?:r|our)?|mL/kg|mL/h(?:r|our)?|units/kg/h(?:r|our)?|units/kg|units/h(?:r|our)?|units|IU/kg|IU|mcg|µg|μg|mg|grams?|g|mL|ml|L|%|bpm|°C|°F|minutes?|mins?|hours?|hrs?|days?|weeks?|seconds?|secs?|cm|mm|kg|J/kg|joules|J|breaths/min|beats/min|/min|cGy|Gy|mOsm/kg|mOsm/L|U/L|IU/L|ng/mL|pg/mL|mcg/mL|mcg/dL|mmol/mol';

final RegExp _quantity = RegExp(r'(?<![\w.,/\-])((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?)(?:\s?[–-]\s?(\d+(?:\.\d+)?))?\s?(' + _unitAlt + r')(?![A-Za-z/])', caseSensitive: false);

final RegExp _otherNumber = RegExp(r'(?<![A-Za-z\-\d.,/])\d+(?:[.,]\d+)?(?![A-Za-z\-\d/])');
final RegExp _labelNumber = RegExp(r'\b(type|grade|stage|class|group|factor|phase|step|number|level|lead|leads|zone|tier|category|score|trimester|generation|day|week)\s+\d+', caseSensitive: false);

/// One "number with unit" fact found in a sentence.
class QuantityHit {
  final String text; // as it will be shown: "0.3–0.5 mg"
  final String unit; // canonical unit
  final double value;
  final bool range;
  final int start, end; // inside the sentence
  const QuantityHit(this.text, this.unit, this.value, this.range, this.start, this.end);
}

String canonUnit(String u) {
  final l = u.toLowerCase();
  if (RegExp(r'^(hours?|hrs?)$').hasMatch(l)) return 'hours';
  if (RegExp(r'^(minutes?|mins?)$').hasMatch(l)) return 'minutes';
  if (RegExp(r'^(seconds?|secs?)$').hasMatch(l)) return 'seconds';
  if (RegExp(r'^days?$').hasMatch(l)) return 'days';
  if (RegExp(r'^weeks?$').hasMatch(l)) return 'weeks';
  if (RegExp(r'^(grams?|g)$').hasMatch(l)) return 'g';
  if (l == 'ml') return 'ml';
  if (l == 'µg' || l == 'μg') return 'mcg';
  return l.replaceAll('hour', 'h').replaceAll('hr', 'h');
}

/// Kind of unit and the factor to its base unit: times in minutes, masses in mg ("6 hours" and "3 days" can
/// stand in for each other as wrong options; "mg" and "mEq/L" cannot).
(String, double) unitClass(String unit) {
  switch (unit) {
    case 'seconds':
      return ('time', 1 / 60);
    case 'minutes':
      return ('time', 1);
    case 'hours':
      return ('time', 60);
    case 'days':
      return ('time', 1440);
    case 'weeks':
      return ('time', 10080);
    case 'mcg':
      return ('mass', 0.001);
    case 'mg':
      return ('mass', 1);
    case 'g':
      return ('mass', 1000);
    default:
      return (unit, 1);
  }
}

/// The single clean "number with unit" quantity of a sentence, or null when it has none or several
/// (or other loose numbers): only clean facts make good number questions.
QuantityHit? singleQuantity(String sentence) {
  final ms = _quantity.allMatches(sentence).toList();
  if (ms.length != 1) return null;
  final m = ms.first;
  if (RegExp(r'^\s?[–-]\s?\d').hasMatch(sentence.substring(m.end))) return null; // "30%-40%": a range written with a unit on both sides
  final rest = (sentence.substring(0, m.start) + ' ' + sentence.substring(m.end)).replaceAll(_labelNumber, ' ');
  if (_otherNumber.hasMatch(rest)) return null;
  final unitRaw = m.group(3)!;
  final unit = canonUnit(unitRaw);
  final a = m.group(1)!, b = m.group(2);
  final value = double.tryParse(a.replaceAll(',', '')) ?? 0;
  final sep = (unit == '%' || unit.startsWith('°')) ? '' : ' ';
  final text = '${b == null ? a : '$a–$b'}$sep$unitRaw';
  return QuantityHit(text, unit, value, b != null, m.start, m.end);
}

/// Words that make a number sentence a statistic, not a recall fact.
final RegExp kStatWords = RegExp(r'\b(prevalence|incidence|affects?|worldwide|per 100|per 1000|cases per|mortality|death rate|survival|risk of|odds|hazard|trial|study|studies|meta-analysis|randomi[sz]ed|confidence interval|compared with|compared to|reduced the|increase[sd]? the risk|percent of (people|patients|cases)|of (people|patients|cases|those|women|men|children|adults)|about half|approximately half|in the united states|in the us\b|each year|per year|annually)\b', caseSensitive: false);

/// A sentence or bullet is usable for a number question: one clean quantity, no statistics words, enough context.
bool numberSentenceOk(String s) {
  if (!cleanFact(s, minLen: 30, maxLen: 230)) return false;
  if (kStatWords.hasMatch(s)) return false;
  if (RegExp(r'\b(may|might|can|could|some|several|varies|vary|depending|sometimes|rarely|occasionally|generally|approximately|about|around|roughly)\b', caseSensitive: false).hasMatch(s)) return false;
  return singleQuantity(s) != null;
}
