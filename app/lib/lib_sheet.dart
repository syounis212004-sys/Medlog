import 'library.dart';
import 'lib_text.dart';

/// Study Sheet engine (pure Dart, offline, rule based).
///
/// It only arranges, tags and highlights the text of a library article: no word of the source
/// is ever changed or added. Every sheet can be switched back to the untouched article.
///
///  * headings of any source map to canonical sections in a fixed reading order ([canonOf]);
///  * the same condition from several installed packs can be shown as one combined sheet,
///    each part with its source badge and near-duplicate sentences shown once;
///  * callouts (red flags, high-yield, mnemonic, dosing line) are added only where the rules are
///    confident; false negatives are preferred over false positives;
///  * decision cards (Stable / Unstable, Mild / Moderate / Severe, If ...) and step lists.

enum SheetTag { none, redFlag, highYield, mnemonic, dose }

enum BKind { para, bullet, sub, cont }

/// A bold / highlight range in a block: t 1 = key term or drug, 2 = lead-in term, 3 = high-yield sentence.
class SRange {
  final int s, e, t;
  const SRange(this.s, this.e, this.t);
}

abstract class SItem {
  const SItem();
}

/// One line of the article: paragraph chunk, bullet (level 0..2), sub-heading ('▸ ...') or an
/// indented continuation line.
class SBlock extends SItem {
  final BKind kind;
  final int level;
  final String text;
  SheetTag tag;
  List<SRange> ranges;
  /// For a dose line nested under a drug line: the text of that parent line (shown next to the dose, never merged into it).
  String parent = '';
  SBlock(this.kind, this.level, this.text, {this.tag = SheetTag.none, this.ranges = const []});
  @override
  String toString() => '${kind.name}$level:$text';
}

enum Tone { green, amber, red, blue }

class DecisionGroup {
  final String label;
  final String rest; // text of the label line after the label ('' when it is only a label)
  final Tone tone;
  final List<SBlock> blocks; // first block is the label line itself
  const DecisionGroup(this.label, this.rest, this.tone, this.blocks);
}

/// Side-by-side condition cards. [all] keeps the plain order, used when colours are off.
class SDecision extends SItem {
  final List<DecisionGroup> groups;
  final List<SBlock> all;
  const SDecision(this.groups, this.all);
}

/// Ordered steps, shown as a vertical list with arrows. [all] keeps the plain order.
class SSteps extends SItem {
  final List<SBlock> steps;
  const SSteps(this.steps);
}

class SheetPart {
  final String src; // badge label, '' for a single source
  final String heading; // original heading
  final int orig; // index of the section in its article
  final List<SItem> items;
  final List<LibTable> tables;
  const SheetPart(this.src, this.heading, this.orig, this.items, this.tables);

  Iterable<SBlock> get blocks sync* {
    for (final it in items) {
      if (it is SBlock) {
        yield it;
      } else if (it is SDecision) {
        yield* it.all;
      } else if (it is SSteps) {
        yield* it.steps;
      }
    }
  }
}

class SheetSec {
  final Canon canon;
  final String title;
  final List<SheetPart> parts;
  const SheetSec(this.canon, this.title, this.parts);
  Iterable<String> get headings => parts.map((p) => p.heading);
  bool get isEmpty => parts.every((p) => p.items.isEmpty && p.tables.isEmpty);
}

class Sheet {
  final String title;
  final String definition; // first sentence of the lead
  final List<SheetPart> lead; // rest of the lead (single source: rendered under the definition)
  final List<SheetSec> sections;
  final List<String> sources; // badge labels of the sources used; more than one = combined
  final List<SBlock> redFlags; // up to 4, in reading order
  final List<SBlock> doses; // dose lines, in reading order
  final List<LibTable> doseTables; // tables that hold dose charts, in reading order
  const Sheet(this.title, this.definition, this.lead, this.sections, this.sources, this.redFlags, [this.doses = const [], this.doseTables = const []]);
  bool get combined => sources.length > 1;
  int count(SheetTag t) {
    var n = 0;
    for (final s in sections) {
      for (final p in s.parts) {
        for (final b in p.blocks) {
          if (b.tag == t) n++;
        }
      }
    }
    return n;
  }
}

class SheetSrc {
  final String label;
  final LibArticle article;
  const SheetSrc(this.label, this.article);
}

// ------------------------------------------------------------------------------------ parsing

List<SBlock> parseBlocks(String text) {
  final out = <SBlock>[];
  for (final raw in text.split('\n')) {
    if (raw.trim().isEmpty) continue;
    final t = raw.trimLeft();
    final indent = raw.length - t.length;
    if (t.startsWith('▸')) {
      final x = t.substring(1).trim();
      if (x.isNotEmpty) out.add(SBlock(BKind.sub, 0, x));
    } else if (t.startsWith('•')) {
      final x = t.substring(1).trim();
      if (x.isNotEmpty) out.add(SBlock(BKind.bullet, 0, x));
    } else if (indent > 0 && (t.startsWith('– ') || t.startsWith('- ') || t.startsWith('— '))) {
      out.add(SBlock(BKind.bullet, indent >= 4 ? 2 : 1, t.substring(2).trim()));
    } else if (t.startsWith('– ')) {
      out.add(SBlock(BKind.bullet, 1, t.substring(2).trim()));
    } else if (indent > 0 && out.isNotEmpty && out.last.kind != BKind.para && out.last.kind != BKind.sub) {
      out.add(SBlock(BKind.cont, (out.last.level + 1).clamp(1, 3), t.trim()));
    } else {
      out.add(SBlock(BKind.para, 0, t.trim()));
    }
  }
  return out;
}

// ------------------------------------------------------------------------------------ titles and sources

final RegExp _suffix = RegExp(r'\s*[—–-]\s*(WikEM|Wikipedia|CDC|NCI|Project Tulip|MedlinePlus)\s*$', caseSensitive: false);

/// Title without the ' — WikEM / Wikipedia / CDC / NCI / Project Tulip' source suffix.
String baseTitle(String t) => t.replaceAll(_suffix, '').trim();

/// Key used to find the same condition in several packs.
String baseTitleKey(String t) => titleKey(t);

/// Short badge label for the source of an article title / source line / pack.
String sourceBadge(String title, {String source = '', String packKind = '', String packTitle = ''}) {
  final m = _suffix.firstMatch(title);
  if (m != null) {
    final s = m.group(1)!.toLowerCase();
    if (s == 'project tulip') return 'Tulip';
    if (s == 'wikem') return 'WikEM';
    if (s == 'wikipedia') return 'Wikipedia';
    if (s == 'medlineplus') return 'MedlinePlus';
    return s.toUpperCase();
  }
  final l = source.toLowerCase();
  if (l.contains('wikem')) return 'WikEM';
  if (l.contains('tulip')) return 'Tulip';
  if (l.contains('cdc') || l.contains('centers for disease')) return 'CDC';
  if (l.contains('cancer institute') || l.contains('nci')) return 'NCI';
  if (l.contains('wikipedia')) return 'Wikipedia';
  if (l.contains('medlineplus')) return 'MedlinePlus';
  if (packKind == 'wiki') return 'Wikipedia';
  if (packKind == 'medline') return 'MedlinePlus';
  return packTitle.isEmpty ? 'Source' : packTitle;
}

// ------------------------------------------------------------------------------------ similarity

final RegExp _tok = RegExp(r'[a-z0-9]+');

Set<String> _tokens(String s) => {for (final m in _tok.allMatches(s.toLowerCase())) m.group(0)!};

double jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var inter = 0;
  final small = a.length < b.length ? a : b;
  final big = identical(small, a) ? b : a;
  for (final x in small) {
    if (big.contains(x)) inter++;
  }
  return inter / (a.length + b.length - inter);
}

class _Seen {
  final List<Set<String>> sets = [];
  final Set<String> exact = {};
  bool isDup(String text) {
    final tk = _tokens(text);
    if (tk.isEmpty) return false;
    final key = tk.toList()..sort();
    final k = key.join(' ');
    if (exact.contains(k)) return true;
    if (tk.length < 4) return false;
    for (final s in sets) {
      if (s.length >= 4 && jaccard(tk, s) >= 0.8) return true;
    }
    return false;
  }

  void add(String text) {
    final tk = _tokens(text);
    if (tk.isEmpty) return;
    exact.add((tk.toList()..sort()).join(' '));
    sets.add(tk);
  }
}

// ------------------------------------------------------------------------------------ rules

const String _actVerb = r'report|call|contact|notify|cover|treat|start|begin|activate|transfer|consult|refer|admit|stop|remove|give|administer|administered|obtain|perform|clamp|send|request|repeat|intubate|resuscitate|reduce|decompress|operate|image|scan|ECG';
const String _dnVerb = r'delay|wait|give|administer|use|restrain|agitate|transfuse|withdraw|attempt|rely|force|discharge|withhold|stop|start|perform|remove|insert|inflate|apply|place|leave|forget|miss|exceed|combine|push|massage|probe|clamp|lie|sedate|ignore|assume|rule out|dismiss|let|hold';
final RegExp _redStrong = RegExp(
    r'(?<![-\w])(emergent(?:ly)?|urgent(?:ly)?'
    '|immediate(?:ly)?\\s+(?:$_actVerb|attention|intervention|decompression|surgery|surgical|antibiotics?|therapy|treatment|management|evaluation|care|referral)\\b'
    '|(?:$_actVerb)\\b(?:\\s+[\\w/+-]+){0,3}\\s+immediately\\b'
    '|immediately\\s+(?:→|->|—)'
    '|(?:^|[—–;:,(]\\s*|\\bbut\\s+)do not\\s+(?:$_dnVerb)\\b)',
    caseSensitive: false);
// absolute contraindications only ("Warfarin contraindicated in pregnancy"), not "if / when / may be contraindicated"
// lines that start with a prohibition, and a danger-sign phrase (late / ominous sign, concerning for a dangerous condition)
final RegExp _redStart = RegExp('^(?:(?:note|nb|caution|warning)\\s*:\\s*)?(?:avoid|never|(?:do not|don.t)\\s+(?:$_dnVerb))\\b', caseSensitive: false);
const String _danger = r'peritonitis|malignancy|cancer|sepsis|septic|perforation|ischemia|infarction|hemorrhage|haemorrhage|bleeding|meningitis|abscess|torsion|rupture|obstruction|dissection|embol\w+|shock|tamponade|stroke|cord compression|compartment syndrome|necrotizing|fracture|aneurysm|pneumothorax|ectopic|appendicitis';
final RegExp _redSign = RegExp(r'\b(?:ominous|late)\s+(?:and\s+ominous\s+)?sign\b|\b(?:suggests?|concerning for|worrisome for|consistent with)\s+(?:an?\s+|the\s+)?(?:possible\s+)?(?:' + _danger + r')\b|\bwarrants?\s+(?:emergent|urgent|immediate)\b', caseSensitive: false);
final RegExp _redConditional = RegExp(r'\b(?:if|when|unless|in case)\b[^.;]{0,60}\bdo not\b|\(\s*do not use if', caseSensitive: false);
final RegExp _redContra = RegExp(r'\bcontraindicated\b', caseSensitive: false);
final RegExp _redContraNot = RegExp(r'contraindicated,?\s+or\s+not|\bineffective\b[^.;]{0,30}contraindicated|\b(?:if|when|unless|may|might|can|could|relatively|not|no|non|without|whether|where)\b[^.;]{0,50}\bcontraindicated\b', caseSensitive: false);
// life-threatening / unstable / critical nouns count only with an action next to them
final RegExp _redCond = RegExp(r'\b(life-?\s?threatening|unstable(?!\s+(?:angina|plaque|lie|gait|joint)))\b', caseSensitive: false);
final RegExp _redAct = RegExp(r'\b(immediate\w*|emergen\w*|urgent\w*|call|seek|requires?|prompt\w*|consult\w*|admit|icu|transfer|operat\w*|surg\w*|cardiovert\w*|intubat\w*)\b', caseSensitive: false);
final RegExp _redNeg = RegExp(r"\b(?:not|no|never|rarely|unlikely|without|nor|non|isn't|aren't|doesn't|don't)\b(?:\s+[\w-]+){0,2}\s+(?:life-?\s?threatening|emergent|urgent|unstable)|\b(?:not|no|never|without|nor)\b(?:\s+[\w-]+){0,6}\s+immediate(?:ly)?\b", caseSensitive: false);
final RegExp _redDoNot = RegExp(r'^(?:do not|never)\b', caseSensitive: false);
final RegExp _redWeak = RegExp(r'\b(shock|sepsis|perforation|rupture[ds]?|airway|hemorrhage|haemorrhage)\b', caseSensitive: false);
final RegExp _redCue = RegExp(r'\b(secure|activate|call|consult\w*|intubat\w*|transfer|prepare)\b', caseSensitive: false);
final RegExp _redNot = RegExp(r'rupture of (?:the )?membranes|premature rupture|prelabor|immediate[- ]release|\d\s?%|\btrial\b|\bshowed\b|follow-?\s?up|mortality|template:|e\.g\.|such as|:\s*$|\b(?:or|and)\s*$|\bunless\b|\bsee\b.{0,60}\bsection\b|\bversus\b|distinguish|differentiate|causes of|\bincluding\b|in urgent|\bexception\b|^emergent conditions|\bnon-?(?:urgent|emergent)|emergent\s+(?:presentation|setting|department|medicine)', caseSensitive: false);
final RegExp _hyRe = RegExp(r'\b(most common(?:ly)?|classic(?:ally)?|pathognomonic|hallmark|first-?\s?line|gold standard)\b', caseSensitive: false);
final RegExp _hyStrong = RegExp(r'pathognomonic|hallmark|gold standard|first-?\s?line|classic', caseSensitive: false);
// a dose with its way of giving: amount + unit, and a route, a rate or a frequency (or per kg / per day)
final RegExp _doseAmt = RegExp(r'(?<![\w.<>≥≤])\d+(?:[.,]\d+)?\s?(?:-|–|to)?\s?(?:\d+(?:[.,]\d+)?\s?)?(?:mg|mcg|µg|ug|gm|g|mL|ml|L|units?|IU|mEq|mmol|U|%|tabs?|tablets?|caps?|drops?|puffs?)(?:/(?:kg|day|d|h|hr|hrs|min|dose|m2|m²|mL|L)){0,2}(?![A-Za-z])', caseSensitive: true);
final RegExp _doseStrict = RegExp(r'\b(?:IV|IM|IO|PO|SC|SQ|NG|ETT|BID|TID|QID|QD|qHS|PRN)\b|\bq\d+\s?(?:h|hr|hrs|hours|min)\b|\d\s?(?:mcg|mg|units?|U)/(?:kg|h|hr|min)', caseSensitive: true);
final RegExp _doseHow = RegExp(r'\b(?:orally|oral|intravenous(?:ly)?|intramuscular(?:ly)?|subcutaneous(?:ly)?|intravaginally|topical(?:ly)?|nebulized|inhaled|bolus|infusion|drip|daily|once|twice|every\s+\d+|\d+\s+times\s+(?:a|per)\s+(?:day|week)|x\s?\d+\s?(?:days?|d|doses?|weeks?|h|hrs)|per\s+(?:kg|day|dose)|dose|dosing|titrate|maximum|max\b|loading)\b|/(?:kg|h|hr|min|day)\b', caseSensitive: false);
final RegExp _doseNot = RegExp(r'\b(?:trial|trials|study|studies|randomi[sz]ed|randomly|survival|mortality|response rate|levels?|concentrations?|range|reference|normal|thresholds?|criteria|available in|dosage forms?|incidence|risk of|prevalence|patients were|was given|were given|received)\b', caseSensitive: false);
final RegExp _doseLab = RegExp(r'\d\s?(?:mg|mcg|g|mmol|mEq|U|IU|ng|pg)/(?:dL|L|mL)\b|\d\s?(?:mg/dL|mmol/L|mEq/L)', caseSensitive: true);
final RegExp _mnemWord = RegExp(r'\bmnemonic\b(?!s)', caseSensitive: false);
final RegExp _capsExp = RegExp(r'\b([A-Z]{3,8})\s?(?::|=|\(|–|—|-)\s*(.{8,})');

/// True when the line spells out the letters of an ALL-CAPS word ("CAVE: Cardiac, ...").
bool isLetterExpansion(String t) {
  for (final m in _capsExp.allMatches(t)) {
    final word = m.group(1)!;
    var rest = m.group(2)!;
    if (m.start > 12) continue; // the acronym opens the line ("RICE (rest, ice, ...)"), not a sentence about something
    if (t.substring(m.start + word.length).trimLeft().startsWith('(')) {
      final close = rest.lastIndexOf(')');
      if (close < 0 || rest.substring(close + 1).trim().replaceAll(RegExp(r'[.;,]'), '').isNotEmpty) continue;
      rest = rest.substring(0, close);
    }
    final items = rest.split(RegExp(r'\s*[,;/]\s*|\s+[–—-]\s+|\s*\.\s+')).map((e) => e.trim().replaceAll(RegExp(r'^[(\[]|^(and|or)\s+'), '')).where((e) => e.isNotEmpty).toList();
    if (items.length < word.length - 1 || items.length > word.length + 3) continue;
    var hit = 0;
    for (var i = 0; i < word.length && i < items.length; i++) {
      if (items[i].isNotEmpty && items[i][0].toUpperCase() == word[i]) hit++;
    }
    if (hit >= word.length - 1 && hit >= 3) return true;
  }
  return false;
}

class _Cand {
  final SBlock block;
  final int score;
  final SRange? range; // prose high-yield: the highlighted sentence inside the block
  _Cand(this.block, this.score, {this.range});
}

class _Ctx {
  final Canon canon;
  final String heading;
  String sub = '';
  _Ctx(this.canon, this.heading);
  bool get dosing => RegExp(r'dos|administration').hasMatch(heading.toLowerCase());
  bool get subSkip => RegExp(r'differential|prognos|risk|cause|etiolog|complication|epidemiolog', caseSensitive: false).hasMatch(sub);
}

const Set<Canon> _redCanons = {Canon.symptoms, Canon.diagnosis, Canon.treatment, Canon.complications, Canon.disposition};

/// True for a line that gives a dose: an amount with a unit and a route, a rate or a frequency, and no sign of a
/// study result, a laboratory value or a list of dosage forms.
bool _isDoseLine(String t) {
  if (t.length < 8 || !_doseAmt.hasMatch(t)) return false;
  final strict = _doseStrict.allMatches(t).map((m) => m.group(0)).toSet().length;
  if (_doseNot.hasMatch(t) && strict < 2) return false;
  if (_doseLab.hasMatch(t) && strict < 1) return false;
  return strict > 0 || _doseHow.hasMatch(t);
}

/// The tag a bullet / sentence earns, with a score (higher = more certain). Null for nothing.
({SheetTag tag, int score})? classifyUnit(String t, Canon canon, {required bool dosingSection, bool subSkip = false, bool bullet = true, int level = 0}) {
  if (t.length < 12) return null;
  if (_mnemWord.hasMatch(t) || isLetterExpansion(t)) {
    if (t.length <= 300) return (tag: SheetTag.mnemonic, score: 9);
  }
  final doseLine = canon != Canon.differential && canon != Canon.epidemiology && canon != Canon.prognosis && t.length <= 300 && _isDoseLine(t);
  if (doseLine && !_redStart.hasMatch(t)) return (tag: SheetTag.dose, score: 6);
  if (_redCanons.contains(canon) && !subSkip && t.length <= 220 && level <= 1 && !_redNot.hasMatch(t)) {
    final words = t.split(RegExp(r'\s+')).length;
    if (words >= 2 && _redStart.hasMatch(t) && !_redConditional.hasMatch(t) && !_redNeg.hasMatch(t.replaceFirst(_redStart, ''))) {
      return (tag: SheetTag.redFlag, score: 6);
    }
    if (words >= 3 && _redSign.hasMatch(t) && !_redNeg.hasMatch(t)) return (tag: SheetTag.redFlag, score: 5);
    if (words >= 4) {
      var strong = _redStrong.allMatches(t).length;
      if (_redContra.hasMatch(t) && !_redContraNot.hasMatch(t)) strong++;
      final neg = _redNeg.hasMatch(t) && !_redDoNot.hasMatch(t);
      if (neg) strong = 0;
      final cond = strong == 0 && !neg && _redCond.hasMatch(t) && _redAct.hasMatch(t.replaceAll(_redCond, ''));
      if ((strong > 0 || cond) && !(canon == Canon.complications && strong == 0 && !cond)) {
        return (tag: SheetTag.redFlag, score: 4 + strong * 2);
      }
      if (words >= 6 && canon != Canon.complications && _redWeak.hasMatch(t) && _redCue.hasMatch(t) && !neg) {
        return (tag: SheetTag.redFlag, score: 3);
      }
    }
  }
  if (doseLine) return (tag: SheetTag.dose, score: 5);
  if (canon != Canon.differential && t.length >= 25 && t.length <= 260 && _hyRe.hasMatch(t) && !t.toLowerCase().startsWith('template:')) {
    return (tag: SheetTag.highYield, score: (_redCanons.contains(canon) ? 3 : 2) + (_hyStrong.hasMatch(t) ? 1 : 0));
  }
  return null;
}

// ------------------------------------------------------------------------------------ decision cards and steps

final RegExp _toneRe = RegExp(
    r'^(?:hemodynamically\s+|haemodynamically\s+)?(stable|unstable|mild(?:\s*(?:-|to)\s*moderate)?|moderate(?:\s*(?:-|to)\s*severe)?|severe|critical|non-?severe)\b',
    caseSensitive: false);
final RegExp _ifRe = RegExp(r'^if\b', caseSensitive: false);

/// (label, tone) when the bullet starts with a condition label, otherwise null.
({String label, String rest, Tone tone, bool pure})? decisionLabel(String t) {
  final tm = _toneRe.firstMatch(t);
  final im = tm == null && _ifRe.hasMatch(t);
  if (tm == null && !im) return null;
  final seps = im ? RegExp(r':|,|\s[–—-]\s') : RegExp(r':|\s[–—-]\s');
  final sm = seps.firstMatch(t);
  final String head;
  final String rest;
  final bool pure;
  if (sm != null && sm.start <= (im ? 70 : 42)) {
    head = t.substring(0, sm.start).trim();
    rest = t.substring(sm.end).trim();
    pure = rest.isEmpty;
  } else if (t.length <= 28 && tm != null) {
    head = t.trim();
    rest = '';
    pure = true;
  } else {
    return null;
  }
  if (head.isEmpty || head.split(RegExp(r'\s+')).length > (im ? 12 : 6)) return null;
  Tone tone = Tone.blue;
  if (tm != null) {
    final w = tm.group(1)!.toLowerCase().replaceAll(RegExp(r'\s'), '');
    if (w == 'stable' || w == 'mild' || w == 'non-severe' || w == 'nonsevere') {
      tone = Tone.green;
    } else if (w == 'unstable' || w == 'severe' || w == 'critical') {
      tone = Tone.red;
    } else {
      tone = Tone.amber;
    }
  }
  return (label: head, rest: rest, tone: tone, pure: pure);
}

/// Finds a run of >= 2 labelled groups in [bl]; returns the new item list (decision card in place).
List<SItem> _decisionItems(List<SBlock> bl) {
  final labels = <int>[];
  for (var i = 0; i < bl.length; i++) {
    if (bl[i].kind == BKind.bullet && bl[i].level == 0 && decisionLabel(bl[i].text) != null) labels.add(i);
  }
  if (labels.length < 2) return List<SItem>.of(bl);
  // groups: a label owns following nested lines; a pure label ("Unstable:") also owns following lines until the next label or sub-heading
  final groups = <DecisionGroup>[];
  final spans = <List<int>>[];
  for (var k = 0; k < labels.length; k++) {
    final i = labels[k];
    final dl = decisionLabel(bl[i].text)!;
    var j = i + 1;
    final limit = k + 1 < labels.length ? labels[k + 1] : bl.length;
    while (j < limit && bl[j].kind != BKind.sub && (bl[j].level > 0 || bl[j].kind == BKind.cont || dl.pure)) {
      j++;
    }
    groups.add(DecisionGroup(dl.label, dl.rest, dl.tone, bl.sublist(i, j)));
    spans.add([i, j]);
  }
  // keep the longest run of groups that follow each other directly
  var bestS = 0, bestE = 0, curS = 0;
  for (var k = 1; k <= groups.length; k++) {
    if (k == groups.length || spans[k][0] != spans[k - 1][1]) {
      if (k - curS > bestE - bestS) {
        bestS = curS;
        bestE = k;
      }
      curS = k;
    }
  }
  if (bestE - bestS < 2) return List<SItem>.of(bl);
  final labs = [for (var k = bestS; k < bestE; k++) groups[k].label.toLowerCase()];
  if (labs.toSet().length != labs.length) return List<SItem>.of(bl); // "If fails ... If fails": a chain, not a choice
  final from = spans[bestS][0], to = spans[bestE - 1][1];
  return [
    ...bl.sublist(0, from),
    SDecision(groups.sublist(bestS, bestE), bl.sublist(from, to)),
    ...bl.sublist(to),
  ];
}

final RegExp _numStep = RegExp(r'^(\d{1,2})[.)]\s+\S');
final RegExp _wordStep = RegExp(r'^(first|then|next|after that|finally|lastly)\b[,:]?\s+\S', caseSensitive: false);

List<SItem> _stepItems(List<SItem> items) {
  final out = <SItem>[];
  var i = 0;
  bool isStep(SItem it, bool num) => it is SBlock && (it.kind == BKind.para || (it.kind == BKind.bullet && it.level == 0)) && (num ? _numStep.hasMatch(it.text) : _wordStep.hasMatch(it.text));
  while (i < items.length) {
    var done = false;
    for (final num in [true, false]) {
      if (isStep(items[i], num)) {
        var j = i;
        while (j < items.length && isStep(items[j], num)) {
          j++;
        }
        // numbered steps must count 1, 2, 3 ...
        var ok = j - i >= 3;
        if (ok && num) {
          for (var k = i; k < j; k++) {
            if (int.parse(_numStep.firstMatch((items[k] as SBlock).text)!.group(1)!) != k - i + 1) ok = false;
          }
        }
        if (ok) {
          out.add(SSteps([for (var k = i; k < j; k++) items[k] as SBlock]));
          i = j;
          done = true;
          break;
        }
      }
    }
    if (!done) {
      out.add(items[i]);
      i++;
    }
  }
  return out;
}

// ------------------------------------------------------------------------------------ building

const Set<String> _stopTitle = {'with', 'from', 'disease', 'syndrome', 'disorder', 'type', 'acute', 'chronic', 'and', 'the', 'of', 'in', 'for', 'due', 'peds', 'adult', 'adults'};

final RegExp _drugEnd = RegExp(
    r'(mab|pril|sartan|olol|statin|cillin|mycin|azole|vir|oxacin|cycline|triptan|dipine|prazole|tidine|epam|olam|thiazide|parin|xaban|gliptin|glitazone|formin|profen|fenac|coxib|setron|terol|navir|caine|sone|olone|penem|bactam|barbital|tinib|ciclib)$',
    caseSensitive: false);
const Set<String> _drugWords = {
  'aspirin', 'acetaminophen', 'paracetamol', 'warfarin', 'heparin', 'insulin', 'digoxin', 'amiodarone', 'adenosine', 'atropine', 'lidocaine', 'morphine', 'codeine', 'tramadol', 'oxycodone', 'fentanyl',
  'gabapentin', 'pregabalin', 'methotrexate', 'colchicine', 'allopurinol', 'hydroxychloroquine', 'tamoxifen', 'levothyroxine', 'epinephrine', 'adrenaline', 'naloxone',
  'nitroglycerin', 'dopamine', 'dobutamine', 'norepinephrine', 'vancomycin', 'ibuprofen', 'naproxen', 'diclofenac', 'prednisone', 'prednisolone', 'dexamethasone', 'furosemide', 'ketorolac', 'ondansetron',
};
const Set<String> _notDrug = {'disease', 'diseases', 'baseline', 'guideline', 'guidelines', 'service', 'tone', 'phone', 'bone', 'stone', 'alone', 'zone', 'done', 'none', 'throne', 'milestone', 'endovir'};

class _BoldCtx {
  final List<String> titleWords;
  final Set<String> usedTitle = {};
  _BoldCtx(String title)
      : titleWords = [
          for (final w in baseTitle(title).replaceAll(RegExp(r'\([^)]*\)'), ' ').split(RegExp(r'[^A-Za-z]+')))
            if (w.length >= 4 && !_stopTitle.contains(w.toLowerCase())) w,
        ];

  List<SRange> rangesFor(SBlock b, Canon canon, Set<String> usedDrugs) {
    final text = b.text;
    final out = <SRange>[];
    if (b.kind == BKind.sub) return out;
    if (usedTitle.length < titleWords.length) {
      for (final w in titleWords) {
        final key = w.toLowerCase();
        if (usedTitle.contains(key)) continue;
        final m = RegExp('\\b${RegExp.escape(w)}\\w{0,3}', caseSensitive: false).firstMatch(text);
        if (m != null) {
          usedTitle.add(key);
          out.add(SRange(m.start, m.end, 1));
        }
      }
    }
    if (canon == Canon.treatment || b.tag == SheetTag.dose) {
      for (final m in RegExp(r'\b[A-Za-z][a-z]{6,}\b').allMatches(text)) {
        final w = m.group(0)!.toLowerCase();
        if (_notDrug.contains(w)) continue;
        if (_drugWords.contains(w) || _drugEnd.hasMatch(w)) {
          if (usedDrugs.add(w)) out.add(SRange(m.start, m.end, 1));
        }
      }
    }
    // lead-in term of a bullet: "Cullen sign (...) - bleeding", "Mild: ..."
    if (b.kind == BKind.bullet && b.level <= 1) {
      final m = RegExp(r':\s|\s[–—-]\s').firstMatch(text);
      if (m != null && m.start >= 3 && m.start <= 45 && text.length - m.end >= 12 && !RegExp(r'^\d').hasMatch(text)) {
        final head = text.substring(0, m.start);
        final open = '('.allMatches(head).length, close = ')'.allMatches(head).length;
        if (open == close && head.split(RegExp(r'\s+')).length <= 6) out.add(SRange(0, m.start, 2));
      }
    }
    return out;
  }
}

/// Splits long paragraphs into ~300 character chunks, cuts out tagged sentences as their own blocks.
List<SBlock> _chunkPara(SBlock b, _Ctx ctx, List<_Cand> red, List<_Cand> hy, List<_Cand> dose, List<_Cand> mn) {
  final text = b.text;
  final sents = sentences(text);
  final out = <SBlock>[];
  var cur = StringBuffer();
  var hl = <SRange>[];
  var hlScore = <int>[];
  void flush() {
    if (cur.isEmpty) return;
    final nb = SBlock(BKind.para, 0, cur.toString(), ranges: hl);
    for (var i = 0; i < hl.length; i++) {
      hy.add(_Cand(nb, hlScore[i], range: hl[i]));
    }
    out.add(nb);
    cur = StringBuffer();
    hl = <SRange>[];
    hlScore = <int>[];
  }

  for (final s in sents) {
    final c = classifyUnit(s, ctx.canon, dosingSection: ctx.dosing, subSkip: ctx.subSkip, bullet: false);
    if (c != null && c.tag != SheetTag.highYield && s.length <= 260) {
      flush();
      final nb = SBlock(BKind.para, 0, s, tag: c.tag);
      _register(nb, c, red, hy, dose, mn);
      out.add(nb);
      continue;
    }
    if (cur.isNotEmpty && cur.length + s.length > 300) flush();
    if (cur.isNotEmpty) cur.write(' ');
    final start = cur.length;
    cur.write(s);
    if (c != null && c.tag == SheetTag.highYield && s.length <= 260) {
      hl.add(SRange(start, start + s.length, 3));
      hlScore.add(c.score);
    }
  }
  flush();
  return out.isEmpty ? [b] : out;
}

void _register(SBlock b, ({SheetTag tag, int score}) c, List<_Cand> red, List<_Cand> hy, List<_Cand> dose, List<_Cand> mn) {
  final cand = _Cand(b, c.score);
  switch (c.tag) {
    case SheetTag.redFlag:
      red.add(cand);
    case SheetTag.highYield:
      hy.add(cand);
    case SheetTag.dose:
      dose.add(cand);
    case SheetTag.mnemonic:
      mn.add(cand);
    case SheetTag.none:
      break;
  }
}

void _cap(List<_Cand> l, int max, {void Function(SBlock)? onDrop}) {
  if (l.length <= max) return;
  final order = [for (var i = 0; i < l.length; i++) i]..sort((a, b) {
      final c = l[b].score.compareTo(l[a].score);
      return c != 0 ? c : a.compareTo(b);
    });
  for (final i in order.skip(max)) {
    l[i].block.tag = SheetTag.none;
    if (l[i].range != null) l[i].block.ranges.remove(l[i].range);
    onDrop?.call(l[i].block);
  }
}

/// One section's text -> items. [skipFirstSentence] removes the (already shown) definition.
List<SItem> _buildItems(List<SBlock> raw, _Ctx ctx, List<_Cand> red, List<_Cand> hy, List<_Cand> dose, List<_Cand> mn) {
  final bl = <SBlock>[];
  final stack = <SBlock>[]; // bullets above the current one: the drug a nested dose line belongs to
  for (final b in raw) {
    SBlock? top0;
    if (b.kind == BKind.bullet) {
      while (stack.isNotEmpty && stack.last.level >= b.level) {
        stack.removeLast();
      }
      top0 = stack.isEmpty ? null : stack.last;
      stack.add(b);
    }
    if (b.kind == BKind.sub) {
      ctx.sub = b.text;
      bl.add(b);
    } else if (b.kind == BKind.para) {
      bl.addAll(_chunkPara(b, ctx, red, hy, dose, mn));
    } else {
      if (b.kind == BKind.bullet) {
        final c = classifyUnit(b.text, ctx.canon, dosingSection: ctx.dosing, subSkip: ctx.subSkip, level: b.level);
        if (c != null) {
          b.tag = c.tag;
          if (c.tag == SheetTag.dose && b.level > 0 && top0 != null && top0.text.length <= 80) b.parent = top0.text;
          _register(b, c, red, hy, dose, mn);
        }
      }
      bl.add(b);
    }
  }
  var items = ctx.canon == Canon.treatment ? _decisionItems(bl) : List<SItem>.of(bl);
  if (ctx.canon == Canon.treatment || ctx.canon == Canon.diagnosis || ctx.canon == Canon.other) items = _stepItems(items);
  return items;
}

/// Removes sentences that [seen] already holds; keeps a parent line when one of its children stays.
List<SBlock> _dedupe(List<SBlock> bl, _Seen seen) {
  final out = <SBlock>[];
  for (var i = 0; i < bl.length; i++) {
    final b = bl[i];
    if (b.kind == BKind.sub) {
      out.add(b);
    } else if (b.kind == BKind.para) {
      final keep = <String>[];
      for (final s in sentences(b.text)) {
        if (!seen.isDup(s)) keep.add(s);
      }
      if (keep.isEmpty) continue;
      out.add(keep.length == sentences(b.text).length ? b : SBlock(BKind.para, 0, keep.join(' ')));
    } else {
      if (!seen.isDup(b.text)) {
        out.add(b);
      } else {
        var childKept = false;
        for (var j = i + 1; j < bl.length && bl[j].level > b.level && bl[j].kind != BKind.sub && bl[j].kind != BKind.para; j++) {
          if (!seen.isDup(bl[j].text)) childKept = true;
        }
        if (childKept) out.add(b);
      }
    }
  }
  // drop sub-headings left without anything under them
  final res = <SBlock>[];
  for (var i = 0; i < out.length; i++) {
    if (out[i].kind == BKind.sub && (i + 1 >= out.length || out[i + 1].kind == BKind.sub)) continue;
    res.add(out[i]);
  }
  return res;
}

int _canonRank(Canon c) => kCanonOrder.indexOf(c);
final RegExp _tailHead = RegExp(r'^(source|source and disclaimer|clips|calculators|reporting cases)$', caseSensitive: false);
int _secRank(SheetSec s) => s.canon == Canon.other && _tailHead.hasMatch(s.title.trim()) ? 99 : _canonRank(s.canon);

/// Builds the sheet of one article or, with several sources, the combined sheet.
/// Removes picture captions (whole sentences / bullets only; the article itself is not changed).
List<SBlock> _stripCaptions(List<SBlock> bl) {
  final out = <SBlock>[];
  for (final b in bl) {
    if (b.kind == BKind.sub) {
      out.add(b);
    } else if (b.kind == BKind.para) {
      final ss = sentences(b.text);
      final keep = [for (final x in ss) if (!isCaptionLike(x)) x];
      if (keep.isEmpty) continue;
      out.add(keep.length == ss.length ? b : SBlock(BKind.para, 0, keep.join(' ')));
    } else if (!isCaptionLike(b.text)) {
      out.add(b);
    }
  }
  return out;
}

Sheet buildSheet(List<SheetSrc> srcs, {bool hideCaptions = false}) {
  final primary = srcs.first.article;
  final combined = srcs.length > 1;
  final red = <_Cand>[], hy = <_Cand>[], dose = <_Cand>[], mn = <_Cand>[];
  // 1. definition: first sentence of the primary lead when it is prose
  var definition = '';
  var leadBlocks0 = primary.sections.isEmpty ? <SBlock>[] : parseBlocks(primary.sections.first.text);
  if (hideCaptions) leadBlocks0 = _stripCaptions(leadBlocks0);
  if (leadBlocks0.isNotEmpty && leadBlocks0.first.kind == BKind.para) {
    final ss = sentences(leadBlocks0.first.text);
    if (ss.isNotEmpty) {
      definition = ss.first;
      final rest = ss.skip(1).join(' ');
      if (rest.isEmpty) {
        leadBlocks0.removeAt(0);
      } else {
        leadBlocks0[0] = SBlock(BKind.para, 0, rest);
      }
    }
  }
  final defSeen = _Seen();
  if (definition.isNotEmpty) defSeen.add(definition);

  // 2. gather (canon, source, section) entries
  final entries = <({Canon canon, String src, LibSection sec, int orig, List<SBlock> raw})>[];
  for (var si = 0; si < srcs.length; si++) {
    final a = srcs[si].article;
    for (var i = 0; i < a.sections.length; i++) {
      final s = a.sections[i];
      final isLead = si == 0 && i == 0;
      if (hideCaptions && !isLead && isGalleryHeading(s.heading)) continue;
      final raw = isLead ? leadBlocks0 : (hideCaptions ? _stripCaptions(parseBlocks(s.text)) : parseBlocks(s.text));
      if (raw.isEmpty && s.tables.isEmpty) continue;
      entries.add((canon: canonOf(s.heading), src: srcs[si].label, sec: s, orig: i, raw: raw));
    }
  }

  // 3. sections
  final secs = <SheetSec>[];
  final lead = <SheetPart>[];
  if (!combined) {
    for (final e in entries) {
      final ctx = _Ctx(e.canon, e.sec.heading);
      final items = _buildItems(e.raw, ctx, red, hy, dose, mn);
      final part = SheetPart('', e.sec.heading, e.orig, items, e.sec.tables);
      if (e.orig == 0 && e.sec.heading.isEmpty) {
        lead.add(part); // rest of the lead: shown under the definition
      } else {
        secs.add(SheetSec(e.canon, e.sec.heading.isEmpty ? 'More' : e.sec.heading, [part]));
      }
    }
    // stable sort into the canonical order
    final idx = {for (var i = 0; i < secs.length; i++) secs[i]: i};
    secs.sort((x, y) {
      final c = _secRank(x).compareTo(_secRank(y));
      return c != 0 ? c : idx[x]!.compareTo(idx[y]!);
    });
  } else {
    // group by canonical section; 'other' sections stay apart by heading
    final order = <String>[];
    final groups = <String, List<({Canon canon, String src, LibSection sec, int orig, List<SBlock> raw})>>{};
    for (final e in entries) {
      final key = e.canon == Canon.other ? 'other:${e.sec.heading.toLowerCase().trim()}' : e.canon.name;
      groups.putIfAbsent(key, () {
        order.add(key);
        return [];
      }).add(e);
    }
    for (final key in order) {
      final g = groups[key]!;
      final canon = g.first.canon;
      final seen = _Seen();
      if (canon == Canon.background && definition.isNotEmpty) seen.sets.addAll(defSeen.sets);
      final parts = <SheetPart>[];
      String? firstSrc;
      for (final e in g) {
        var bl = e.raw;
        if (firstSrc != null && firstSrc != e.src) bl = _dedupe(bl, seen);
        for (final b in bl) {
          if (b.kind == BKind.para) {
            for (final x in sentences(b.text)) {
              seen.add(x);
            }
          } else if (b.kind != BKind.sub) {
            seen.add(b.text);
          }
        }
        firstSrc ??= e.src;
        if (bl.isEmpty && e.sec.tables.isEmpty) continue;
        final ctx = _Ctx(e.canon, e.sec.heading);
        parts.add(SheetPart(e.src, e.sec.heading, e.orig, _buildItems(bl, ctx, red, hy, dose, mn), e.sec.tables));
      }
      if (parts.isEmpty) continue;
      secs.add(SheetSec(canon, canon == Canon.other ? (g.first.sec.heading.isEmpty ? 'More' : g.first.sec.heading) : canonLabel(canon), parts));
    }
    secs.sort((x, y) => _secRank(x).compareTo(_secRank(y)));
  }

  // 4. caps (only the most certain callouts survive)
  _cap(red, 8);
  _cap(hy, 5);
  _cap(dose, 40);
  _cap(mn, 3);

  // 5. bold ranges, in reading order
  final bold = _BoldCtx(primary.title);
  void boldPart(SheetPart p, Canon canon) {
    final usedDrugs = <String>{};
    for (final b in p.blocks) {
      final r = bold.rangesFor(b, canon, usedDrugs);
      if (r.isNotEmpty) b.ranges = [...b.ranges, ...r];
    }
  }

  for (final p in lead) {
    boldPart(p, Canon.background);
  }
  for (final s in secs) {
    for (final p in s.parts) {
      boldPart(p, s.canon);
    }
  }

  // 6. summaries in reading order: the 4 most certain red flags, all dose lines, tables that hold dose charts
  final flags = <SBlock>[];
  final doses = <SBlock>[];
  final doseTables = <LibTable>[];
  for (final s in secs) {
    for (final p in s.parts) {
      for (final b in p.blocks) {
        if (b.tag == SheetTag.redFlag) flags.add(b);
        if (b.tag == SheetTag.dose) doses.add(b);
      }
      for (final t in p.tables) {
        if (isDoseTable(t)) doseTables.add(t);
      }
    }
  }
  final score = {for (final c in red) c.block: c.score};
  final keep = [...flags]..sort((a, b) => (score[b] ?? 0).compareTo(score[a] ?? 0));
  final top = keep.take(4).toSet();
  return Sheet(primary.title, definition, lead, secs, [for (final s in srcs) s.label], [for (final f in flags) if (top.contains(f)) f], doses, doseTables);
}

final RegExp _doseHead = RegExp(r'dos|\bmg\b|regimen|route|frequency|drug|medication|antibiotic|treatment|agent', caseSensitive: false);

/// A table that is a dose chart: a header that names doses or drugs, and cells that hold amounts with units.
bool isDoseTable(LibTable t) {
  if (t.rows.length < 2) return false;
  var amounts = 0;
  for (final r in t.rows.skip(1)) {
    for (final c in r) {
      if (_doseAmt.hasMatch(c)) {
        amounts++;
        break;
      }
    }
  }
  final head = t.rows.first.join(' ');
  return amounts >= 2 && amounts * 2 >= t.rows.length - 1 && (_doseHead.hasMatch(head) || _doseHead.hasMatch(t.caption));
}

// ------------------------------------------------------------------------------------ siblings (other packs, same condition)

class SheetLink {
  final String packId;
  final int index;
  final String title;
  final String label;
  const SheetLink(this.packId, this.index, this.title, this.label);
}

/// Source label of an article for the sheet badges. The concise Wikipedia version in the essentials pack is told apart
/// from a full Wikipedia course article ("Wikipedia (concise)"), so both can be shown together.
String sheetLabel(String packId, String title, {String source = '', String packKind = '', String packTitle = ''}) {
  final l = sourceBadge(title, source: source, packKind: packKind, packTitle: packTitle);
  return packId == kEssentialsPackId && l == 'Wikipedia' ? 'Wikipedia (concise)' : l;
}

/// Per-session map base title -> articles of that title in the installed packs. Built once (from the title keys the
/// background isolates already made, so it only walks lists of strings), and only keeps titles that exist in two
/// or more places.
class SheetIndex {
  static String _sig = '';
  static Future<Map<String, List<SheetLink>>>? _building;

  static void reset() {
    _sig = '';
    _building = null;
  }

  static Future<Map<String, List<SheetLink>>> _build(LibraryStore lib) async {
    await lib.warmUp();
    final all = <String, List<(String, int)>>{};
    for (final p in lib.textPacks) {
      final keys = await lib.baseKeysOf(p.id);
      for (var i = 0; i < keys.length; i++) {
        final k = keys[i];
        if (k.length < 3) continue;
        (all[k] ??= []).add((p.id, i));
      }
    }
    final out = <String, List<SheetLink>>{};
    final titles = <String, List<String>>{};
    for (final e in all.entries) {
      if (e.value.length < 2) continue;
      out[e.key] = [
        for (final (pid, i) in e.value)
          () {
            final p = lib.pack(pid);
            final t = (titles[pid] ??= lib.titlesSync(pid))[i];
            return SheetLink(pid, i, t, sheetLabel(pid, t, packKind: p?.kind ?? '', packTitle: p?.title ?? ''));
          }(),
      ];
    }
    return out;
  }

  /// Other articles about the same condition (not the one given), best sources first.
  static Future<List<SheetLink>> siblings(LibraryStore lib, String packId, String title) async {
    final sig = lib.textPacks.map((p) => '${p.id}:${p.date}:${p.count}').join('|');
    if (_building == null || _sig != sig) {
      _sig = sig;
      final f = _build(lib);
      _building = f;
      f.then((_) {}, onError: (_) {
        if (identical(_building, f)) _building = null;
      });
    }
    final Map<String, List<SheetLink>> map;
    try {
      map = await _building!;
    } catch (_) {
      return const [];
    }
    final self = baseTitleKey(title);
    final out = <SheetLink>[
      for (final x in map[self] ?? const <SheetLink>[])
        if (!(x.packId == packId && x.title == title)) x,
    ];
    const pref = ['WikEM', 'Tulip', 'CDC', 'NCI', 'Wikipedia (concise)', 'Wikipedia', 'MedlinePlus'];
    int rank(SheetLink x) {
      final i = pref.indexOf(x.label);
      return i < 0 ? 9 : i;
    }

    out.sort((a, b) => rank(a).compareTo(rank(b)));
    // one article per source label
    final seen = <String>{};
    return [for (final x in out) if (seen.add(x.label)) x].take(4).toList();
  }
}

final Map<String, Sheet> _sheetCache = {};

/// Sheet of [srcs], cached per article (and per combination of sources).
Sheet sheetFor(String key, List<SheetSrc> srcs, {bool hideCaptions = true}) {
  final k = hideCaptions ? key : '$key|raw';
  final hit = _sheetCache[k];
  if (hit != null) return hit;
  if (_sheetCache.length > 24) _sheetCache.remove(_sheetCache.keys.first);
  return _sheetCache[k] = buildSheet(srcs, hideCaptions: hideCaptions);
}

void clearSheetCache() => _sheetCache.clear();
