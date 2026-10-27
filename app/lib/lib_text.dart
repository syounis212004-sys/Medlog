import 'package:flutter/material.dart';

/// Small text helpers for the library: abbreviations, article sections, sentences and
/// a typo-tolerant distance. Everything here is offline and works on the article text only.

const Map<String, String> kLibAbbrev = {
  'oa': 'osteoarthritis',
  'ra': 'rheumatoid arthritis',
  'mi': 'myocardial infarction',
  'acs': 'acute coronary syndrome',
  'chf': 'heart failure',
  'hf': 'heart failure',
  'af': 'atrial fibrillation',
  'afib': 'atrial fibrillation',
  'htn': 'hypertension',
  'dm': 'diabetes mellitus',
  'dka': 'diabetic ketoacidosis',
  'copd': 'chronic obstructive pulmonary disease',
  'cap': 'pneumonia',
  'pe': 'pulmonary embolism',
  'dvt': 'deep vein thrombosis',
  'uti': 'urinary tract infection',
  'ckd': 'chronic kidney disease',
  'aki': 'acute kidney injury',
  'gerd': 'gastroesophageal reflux disease',
  'ibd': 'inflammatory bowel disease',
  'ibs': 'irritable bowel syndrome',
  'tb': 'tuberculosis',
  'sle': 'systemic lupus erythematosus',
  'ms': 'multiple sclerosis',
  'cva': 'stroke',
  'tia': 'transient ischemic attack',
  'ards': 'acute respiratory distress syndrome',
  'sob': 'shortness of breath',
  'acl': 'anterior cruciate ligament',
  'pcl': 'posterior cruciate ligament',
  'orif': 'open reduction and internal fixation',
  'cts': 'carpal tunnel syndrome',
  'gbs': 'guillain barre syndrome',
  'bph': 'benign prostatic hyperplasia',
  'pid': 'pelvic inflammatory disease',
  'pcos': 'polycystic ovary syndrome',
  'ptsd': 'post-traumatic stress disorder',
  'ocd': 'obsessive compulsive disorder',
  'adhd': 'attention deficit hyperactivity disorder',
  'ecg': 'electrocardiography',
  'ekg': 'electrocardiography',
  'cxr': 'chest radiograph',
  'ct': 'computed tomography',
  'mri': 'magnetic resonance imaging',
  'nsaid': 'nonsteroidal anti-inflammatory drug',
  'gi': 'gastrointestinal',
  'hiv': 'hiv/aids',
  'dic': 'disseminated intravascular coagulation',
  'itp': 'immune thrombocytopenia',
  'ttp': 'thrombotic thrombocytopenic purpura',
  'cll': 'chronic lymphocytic leukemia',
  'aml': 'acute myeloid leukemia',
  'all': 'acute lymphoblastic leukemia',
  'cml': 'chronic myeloid leukemia',
  'nhl': 'non-hodgkin lymphoma',
  'sah': 'subarachnoid hemorrhage',
  'ich': 'intracerebral hemorrhage',
  'rds': 'respiratory distress syndrome',
  'vsd': 'ventricular septal defect',
  'asd': 'atrial septal defect',
  'pda': 'patent ductus arteriosus',
  // scores and scales: the name of the score, nothing else
  'stemi': 'st elevation myocardial infarction',
  'nstemi': 'non st elevation myocardial infarction',
  'gcs': 'glasgow coma scale',
  'sbp': 'spontaneous bacterial peritonitis|systolic blood pressure',
  'apgar': 'apgar score',
  'qsofa': 'quick sequential organ failure assessment|sequential organ failure assessment',
  'sofa': 'sequential organ failure assessment',
  'curb-65': 'confusion urea respiratory rate blood pressure age 65',
  'curb65': 'confusion urea respiratory rate blood pressure age 65',
  'cha2ds2-vasc': 'cha2ds2 vasc score',
  'cha2ds2vasc': 'cha2ds2 vasc score',
  'has-bled': 'has bled score',
  'hasbled': 'has bled score',
  'meld': 'model for end stage liver disease',
  'child-pugh': 'child pugh score',
  'wells': 'wells score',
  'perc': 'pulmonary embolism rule out criteria',
  'timi': 'thrombolysis in myocardial infarction',
  'news': 'national early warning score',
  'mews': 'modified early warning score',
  'pci': 'percutaneous coronary intervention',
  'cabg': 'coronary artery bypass',
  'acls': 'advanced cardiac life support',
  'bls': 'basic life support',
  'cpr': 'cardiopulmonary resuscitation',
  'rosc': 'return of spontaneous circulation',
  'pea': 'pulseless electrical activity',
  'hhs': 'hyperosmolar hyperglycemic state',
  'siadh': 'syndrome of inappropriate antidiuretic hormone secretion',
  'hus': 'hemolytic uremic syndrome',
  'hellp': 'hellp syndrome',
  'pph': 'postpartum hemorrhage',
  'prom': 'premature rupture of membranes',
  'gdm': 'gestational diabetes',
  'cad': 'coronary artery disease',
  'pad': 'peripheral artery disease',
  'aaa': 'abdominal aortic aneurysm',
  'hocm': 'hypertrophic cardiomyopathy',
  'lbbb': 'left bundle branch block',
  'rbbb': 'right bundle branch block',
  'wpw': 'wolff parkinson white syndrome',
  'svt': 'supraventricular tachycardia',
  'vt': 'ventricular tachycardia',
  'vf': 'ventricular fibrillation',
  'icp': 'intracranial pressure',
  'tbi': 'traumatic brain injury',
  'mrsa': 'methicillin resistant staphylococcus aureus',
  'vre': 'vancomycin resistant enterococcus',
  'cdiff': 'clostridioides difficile',
  'cmv': 'cytomegalovirus',
  'ebv': 'epstein barr virus',
  'hsv': 'herpes simplex',
  'hpv': 'human papillomavirus',
  'hbv': 'hepatitis b',
  'hcv': 'hepatitis c',
  'pcp': 'pneumocystis pneumonia',
  'als': 'amyotrophic lateral sclerosis',
  'pmr': 'polymyalgia rheumatica',
  'gca': 'giant cell arteritis',
  'cah': 'congenital adrenal hyperplasia',
  'nafld': 'non alcoholic fatty liver disease',
  'hcc': 'hepatocellular carcinoma',
  'pbc': 'primary biliary cholangitis',
  'psc': 'primary sclerosing cholangitis',
  'esrd': 'end stage renal disease',
  'ssri': 'selective serotonin reuptake inhibitor',
  'tca': 'tricyclic antidepressant',
  'maoi': 'monoamine oxidase inhibitor',
  'ect': 'electroconvulsive therapy',
  'abg': 'arterial blood gas',
  'lft': 'liver function tests',
  'esr': 'erythrocyte sedimentation rate',
  'crp': 'c reactive protein',
  'inr': 'international normalized ratio',
  'tsh': 'thyroid stimulating hormone',
  'bmi': 'body mass index',
  'bnp': 'natriuretic peptide',
  'ptt': 'partial thromboplastin time',
  'ivig': 'intravenous immunoglobulin',
  'tpa': 'tissue plasminogen activator',
  'doac': 'direct oral anticoagulant',
  'noac': 'direct oral anticoagulant',
  'arb': 'angiotensin receptor blocker',
  'ppi': 'proton pump inhibitor',
  'hrt': 'hormone replacement therapy',
  'picc': 'peripherally inserted central catheter',
  'ercp': 'endoscopic retrograde cholangiopancreatography',
  'ecmo': 'extracorporeal membrane oxygenation',
  'niv': 'non invasive ventilation',
  'cpap': 'continuous positive airway pressure',
  'rsi': 'rapid sequence intubation',
};

/// Everyday phrases and the term the articles use for them (searched in addition to the words typed).
const Map<String, String> kLibPhrases = {
  'high potassium': 'hyperkalemia',
  'low potassium': 'hypokalemia',
  'high sodium': 'hypernatremia',
  'low sodium': 'hyponatremia',
  'high calcium': 'hypercalcemia',
  'low calcium': 'hypocalcemia',
  'high magnesium': 'hypermagnesemia',
  'low magnesium': 'hypomagnesemia',
  'low blood sugar': 'hypoglycemia',
  'high blood sugar': 'hyperglycemia',
  'high blood pressure': 'hypertension',
  'low blood pressure': 'hypotension',
  'heart attack': 'myocardial infarction',
  'blood clot': 'thrombosis',
  'kidney failure': 'renal failure|acute kidney injury',
  'liver failure': 'hepatic failure',
  'water on the lung': 'pleural effusion',
  'collapsed lung': 'pneumothorax',
  'fast heart rate': 'tachycardia',
  'slow heart rate': 'bradycardia',
  'irregular heartbeat': 'arrhythmia',
  'warfarin reversal': 'anticoagulant reversal',
  'paracetamol overdose': 'acetaminophen toxicity|paracetamol poisoning',
  'acetaminophen overdose': 'acetaminophen toxicity|paracetamol poisoning',
};

/// The query itself plus, for each abbreviation in it, a variant with the long form (an entry may list
/// several readings separated by "|": each one gives its own variant).
List<String> expandAbbrev(String q) {
  final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final out = <String>[q.trim()];
  final lower = q.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  for (final e in kLibPhrases.entries) {
    if (lower.contains(e.key)) {
      for (final alt in e.value.split('|')) {
        final v = lower.replaceAll(e.key, alt);
        if (!out.contains(v)) out.add(v);
      }
    }
  }
  String clean(String w) => w.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
  List<String>? alts(String w) {
    final c = clean(w);
    final v = kLibAbbrev[c] ?? kLibAbbrev[c.replaceAll('-', '')];
    return v?.split('|');
  }

  if (words.any((w) => alts(w) != null)) {
    final n = words.fold<int>(1, (m, w) => (alts(w)?.length ?? 1) > m ? alts(w)!.length : m);
    for (var k = 0; k < n; k++) {
      final v = words.map((w) {
        final a = alts(w);
        return a == null ? w : a[k < a.length ? k : 0];
      }).join(' ');
      if (!out.contains(v)) out.add(v);
    }
  }
  return out;
}

enum SecKind { lead, symptoms, causes, diagnosis, treatment, prevention, epidemiology, history, other }

SecKind secKind(String heading) {
  final h = heading.toLowerCase();
  if (RegExp(r'signs and symptoms|symptom|clinical (presentation|features)|presentation|what are the symptoms').hasMatch(h)) return SecKind.symptoms;
  if (RegExp(r'cause|etiolog|risk factor|pathophys|pathogen|mechanism|who is more likely').hasMatch(h)) return SecKind.causes;
  if (RegExp(r'diagnos|investigation|screening|classification|differential|imaging|tests').hasMatch(h)) return SecKind.diagnosis;
  if (RegExp(r'treatment|management|therap|medication|surgery|surgical|rehabilitation|what are the treatments').hasMatch(h)) return SecKind.treatment;
  if (RegExp(r'prevent|prognos|outcome|complication').hasMatch(h)) return SecKind.prevention;
  if (RegExp(r'epidemiolog|prevalence|incidence').hasMatch(h)) return SecKind.epidemiology;
  if (RegExp(r'history|society|culture|etymolog|research|other animals').hasMatch(h)) return SecKind.history;
  return SecKind.other;
}

IconData secIcon(SecKind k) {
  switch (k) {
    case SecKind.lead:
      return Icons.short_text;
    case SecKind.symptoms:
      return Icons.sick_outlined;
    case SecKind.causes:
      return Icons.account_tree_outlined;
    case SecKind.diagnosis:
      return Icons.biotech_outlined;
    case SecKind.treatment:
      return Icons.medication_outlined;
    case SecKind.prevention:
      return Icons.shield_outlined;
    case SecKind.epidemiology:
      return Icons.groups_outlined;
    case SecKind.history:
      return Icons.history_edu_outlined;
    case SecKind.other:
      return Icons.notes_outlined;
  }
}

/// Short English label for the jump chips.
String secLabel(SecKind k) {
  switch (k) {
    case SecKind.symptoms:
      return 'Symptoms';
    case SecKind.causes:
      return 'Causes';
    case SecKind.diagnosis:
      return 'Diagnosis';
    case SecKind.treatment:
      return 'Treatment';
    case SecKind.prevention:
      return 'Prognosis';
    case SecKind.epidemiology:
      return 'Epidemiology';
    case SecKind.history:
      return 'History';
    default:
      return 'More';
  }
}

/// Splits text into sentences (keeps common abbreviations and decimals together).
List<String> sentences(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return const [];
  final protected = t
      .replaceAllMapped(RegExp(r'\b(e\.g|i\.e|vs|Dr|Fig|approx|ca|cf|et al|No|St|Mr|Mrs)\.', caseSensitive: false), (m) => '${m[1]}\u0001')
      .replaceAllMapped(RegExp(r'(\d)\.(\d)'), (m) => '${m[1]}\u0002${m[2]}');
  final out = <String>[];
  for (final s in protected.split(RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9"(])'))) {
    final x = s.replaceAll('\u0001', '.').replaceAll('\u0002', '.').trim();
    if (x.isNotEmpty) out.add(x);
  }
  return out;
}

String firstSentence(String text) {
  final s = sentences(text);
  return s.isEmpty ? '' : s.first;
}

/// Edit distance with adjacent swaps, stops early above [max].
int editDistance(String a, String b, {int max = 3}) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prev2 = List<int>.filled(b.length + 1, 0);
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        final t = prev2[j - 2] + 1;
        if (t < v) v = t;
      }
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    prev2 = prev;
    prev = cur;
  }
  return prev[b.length];
}

/// Lines of a section that are bullets ("• item"), without the bullet sign.
List<String> bulletLines(String text) {
  final out = <String>[];
  for (final l in text.split('\n')) {
    final t = l.trim();
    if (t.startsWith('•')) {
      final x = t.substring(1).trim();
      if (x.isNotEmpty) out.add(x);
    }
  }
  return out;
}

/// Sentences and bullet lines of a section, each as one unit (bullets keep their own line).
List<String> textUnits(String text) {
  final out = <String>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) out.addAll(sentences(buf.toString()));
    buf.clear();
  }

  for (final l in text.split('\n')) {
    final t = l.trim();
    if (t.startsWith('•')) {
      flush();
      final x = t.substring(1).trim();
      if (x.isNotEmpty) out.add(x);
    } else if (t.isNotEmpty) {
      buf.write('$t ');
    }
  }
  flush();
  return out;
}

// ---------------------------------------------------------------------------------------------
// Canonical sections for the Study Sheet: every heading of every source maps to one of these,
// in this fixed reading order. [secKind] above is unchanged for the older callers.

enum Canon { background, causes, pathophys, epidemiology, symptoms, differential, diagnosis, treatment, disposition, complications, prognosis, prevention, other, history }

const List<Canon> kCanonOrder = [
  Canon.background,
  Canon.causes,
  Canon.pathophys,
  Canon.epidemiology,
  Canon.symptoms,
  Canon.differential,
  Canon.diagnosis,
  Canon.treatment,
  Canon.disposition,
  Canon.complications,
  Canon.prognosis,
  Canon.prevention,
  Canon.other,
  Canon.history,
];

final RegExp _cDiff = RegExp(r'differential');
final RegExp _cDisp = RegExp(r'dispositi|follow-?\s?up|admission|referral');
final RegExp _cSym = RegExp(r'signs and symptoms|symptom|clinical (presentation|features)|presentation|^findings|history and physical|what are the symptoms');
final RegExp _cTreat = RegExp(r'treatment|management|therap|medications?$|^medications?|surgery|surgical|rehabilitation|what are the treatments|^recovery');
final RegExp _cDiag = RegExp(r'diagnos|evaluation|work-?\s?up|investigation|screening|classification|imaging|tests?$|testing|recommended tests|laborator|^interpretation|^tests');
final RegExp _cComp = RegExp(r'complication');
final RegExp _cProg = RegExp(r'prognos|outcome');
final RegExp _cPrev = RegExp(r'prevent');
final RegExp _cEpi = RegExp(r'epidemiolog|prevalence|incidence|disease rates');
final RegExp _cCause = RegExp(r'cause|etiolog|risk factor|who is more likely|how it spreads');
final RegExp _cPath = RegExp(r'pathophys|pathogen|^mechanism$|^mechanism of disease|pathology');
final RegExp _cHist = RegExp(r'history|society|culture|etymolog|research|other animals');
final RegExp _cBack = RegExp(r'^(background|general|overview|definition|introduction|summary|key points|at a glance|about|what is|description)');

/// Maps a section heading ('' = the lead) to its canonical section.
Canon canonOf(String heading) {
  final h = heading.toLowerCase().trim();
  if (h.isEmpty) return Canon.background;
  if (_cDiff.hasMatch(h)) return Canon.differential;
  if (_cDisp.hasMatch(h)) return Canon.disposition;
  if (_cSym.hasMatch(h)) return Canon.symptoms;
  if (_cTreat.hasMatch(h)) return Canon.treatment;
  if (_cDiag.hasMatch(h)) return Canon.diagnosis;
  if (_cComp.hasMatch(h)) return Canon.complications;
  if (_cProg.hasMatch(h)) return Canon.prognosis;
  if (_cPrev.hasMatch(h)) return Canon.prevention;
  if (_cEpi.hasMatch(h)) return Canon.epidemiology;
  if (_cCause.hasMatch(h)) return Canon.causes;
  if (_cPath.hasMatch(h)) return Canon.pathophys;
  if (_cHist.hasMatch(h) && !h.startsWith('history and')) return Canon.history;
  if (_cBack.hasMatch(h)) return Canon.background;
  return Canon.other;
}

/// English label (wrap with tr() when shown).
String canonLabel(Canon c) {
  switch (c) {
    case Canon.background:
      return 'Background';
    case Canon.causes:
      return 'Causes';
    case Canon.pathophys:
      return 'Pathophysiology';
    case Canon.epidemiology:
      return 'Epidemiology';
    case Canon.symptoms:
      return 'Symptoms';
    case Canon.differential:
      return 'Differential';
    case Canon.diagnosis:
      return 'Diagnosis';
    case Canon.treatment:
      return 'Treatment';
    case Canon.disposition:
      return 'Disposition';
    case Canon.complications:
      return 'Complications';
    case Canon.prognosis:
      return 'Prognosis';
    case Canon.prevention:
      return 'Prevention';
    case Canon.history:
      return 'History';
    case Canon.other:
      return 'More';
  }
}

IconData canonIcon(Canon c) {
  switch (c) {
    case Canon.background:
      return Icons.short_text;
    case Canon.causes:
      return Icons.account_tree_outlined;
    case Canon.pathophys:
      return Icons.science_outlined;
    case Canon.epidemiology:
      return Icons.groups_outlined;
    case Canon.symptoms:
      return Icons.sick_outlined;
    case Canon.differential:
      return Icons.compare_arrows;
    case Canon.diagnosis:
      return Icons.biotech_outlined;
    case Canon.treatment:
      return Icons.medication_outlined;
    case Canon.disposition:
      return Icons.local_hospital_outlined;
    case Canon.complications:
      return Icons.warning_amber_outlined;
    case Canon.prognosis:
      return Icons.trending_up;
    case Canon.prevention:
      return Icons.shield_outlined;
    case Canon.history:
      return Icons.history_edu_outlined;
    case Canon.other:
      return Icons.notes_outlined;
  }
}

/// Accent colour of a canonical section (a lighter tone on dark backgrounds).
Color canonColor(Canon c, bool dark) {
  int light, dk;
  switch (c) {
    case Canon.background:
      light = 0xFF3B6EA8;
      dk = 0xFF8DB4E8;
    case Canon.causes:
      light = 0xFF7B5EA7;
      dk = 0xFFBBA3E3;
    case Canon.pathophys:
      light = 0xFF2A8C8C;
      dk = 0xFF7FD0D0;
    case Canon.epidemiology:
      light = 0xFF5F7487;
      dk = 0xFFA9BCCB;
    case Canon.symptoms:
      light = 0xFFC2630F;
      dk = 0xFFF2A765;
    case Canon.differential:
      light = 0xFF8A6D00;
      dk = 0xFFE3C95E;
    case Canon.diagnosis:
      light = 0xFF3F51B5;
      dk = 0xFFA3AEF2;
    case Canon.treatment:
      light = 0xFF2E7D4F;
      dk = 0xFF7FD3A0;
    case Canon.disposition:
      light = 0xFF00796B;
      dk = 0xFF6FD5C8;
    case Canon.complications:
      light = 0xFFB3402D;
      dk = 0xFFF29585;
    case Canon.prognosis:
      light = 0xFF7A5646;
      dk = 0xFFD1B0A2;
    case Canon.prevention:
      light = 0xFF1B8A6B;
      dk = 0xFF76D6B8;
    case Canon.history:
    case Canon.other:
      light = 0xFF607080;
      dk = 0xFFB0BDC9;
  }
  return Color(dark ? dk : light);
}

// ---------------------------------------------------------------------------------------------
// Figure captions and sentence-safe clipping (Quick view and Study Sheet; the original text is never changed).

const String _capDesc = r'(?:MRI|CT|CAT|PET|SPECT|X-?rays?|radiographs?|photographs?|photos?|photomicrographs?|micrographs?|diagrams?|illustrations?|drawings?|schematics?|ultrasounds?|sonograms?|histology|histopathology|pathology|angiograms?|images?|pictures?|scans?|sections?|specimens?|views?|slides?|cross-sections?|anatomy|dissection|charts?|graphs?|maps?|timeline|animation|endoscopy|laparoscopy|colonoscopy|ECG|EKG|tracing|smear|biopsy|film|cytology|appearance)';
final RegExp _capStart = RegExp(
    r'^(?:(?:A|An|The)\s+)?(?:(?!(?:the|of|and|in|to|for|with|by|that|which)\b)[\w\-/]+\s+){0,3}?\b' + _capDesc + r'\b(?:\s+(?:image|view|scan|photograph))?\s*(?:of|showing|depicting|illustrating|demonstrating|from|:|–|—)(?:\s|$)',
    caseSensitive: false);
final RegExp _capFig = RegExp(r'^\W*(?:Fig(?:ure)?\.?\s*\d+[A-Za-z]?\b|Image:|File:|Photo:|Picture:)', caseSensitive: false);
final RegExp _capStrong = RegExp(
    r'\((?:white |black |red |yellow |blue |green |small |large )?(?:arrow|arrows|arrowheads?|asterisks?)\)|\bH\s?&\s?E(?: stain(?:ed)?)?\.?\)?\s*$|\bcourtesy of\b|©|\bCC[ -]BY\b|Wikimedia Commons|\((?:Image|Photo|Photograph|Credit|Courtesy|Source)\b[:\s][^)]{0,80}\)\s*\.?$|\bimage by\b|\bphoto by\b|\bphotograph by\b|\barrows?\)',
    caseSensitive: false);
final RegExp _capWeak = RegExp(r'\((?:top |bottom |upper |lower )?(?:left|right|top|bottom|upper|lower|inset)(?: panel| image)?\)', caseSensitive: false);
final RegExp _capEnum = RegExp(r'^\(?[a-dA-D]\)\s+\S');
final RegExp _capCue = RegExp(r'\b(?:' + _capDesc + r'|arrows?|shows?|showing|axial|coronal|sagittal)\b', caseSensitive: false);
final RegExp _capVerb = RegExp(
    r'\b(?:is|are|was|were|be|been|can|may|should|will|would|has|have|had|does|do|did|must|could|might|provides?|allows?|used|uses|helps?|remains?|occurs?|results?|causes?|requires?|include|includes|involves?|consists?|appears?|becomes?|reveals?|detects?|identif(?:y|ies)|differentiates?|show|shows|shown|looks?|illustrates?|depicts?)\b',
    caseSensitive: false);

/// True for a sentence or bullet that is a picture caption (figure descriptors, arrows, stain notes,
/// credits). Precision first: ordinary clinical sentences that mention an image are kept.
bool isCaptionLike(String text) {
  final t = text.trim();
  if (t.length < 6) return false;
  final w = t.split(RegExp(r'\s+')).length;
  if (_capFig.hasMatch(t)) return true;
  if (w <= 70 && _capStrong.hasMatch(t)) return true;
  if (w <= 70 && _capEnum.hasMatch(t) && _capCue.hasMatch(t)) return true;
  if (w <= 40 && _capWeak.hasMatch(t) && !_capVerb.hasMatch(t)) return true;
  if (w <= (t.endsWith('.') ? 14 : 30) && _capStart.hasMatch(t) && !_capVerb.hasMatch(t)) return true;
  return false;
}

final RegExp _galleryHead = RegExp(r'^(additional images|additional pictures|gallery|images?|image gallery|figures?|illustrations?|media|photo gallery|multimedia|diagrams?)$', caseSensitive: false);

/// Section headings that only hold picture captions.
bool isGalleryHeading(String heading) => _galleryHead.hasMatch(heading.trim());

/// Whole sentences of [text] that fit in [max] characters (never cut inside a sentence).
/// When even the first sentence is longer than [max] it is kept whole up to 2 x [max], else dropped.
String fitSentences(String text, int max) {
  final t = text.trim();
  if (t.length <= max) return t;
  final ss = sentences(t);
  if (ss.isEmpty) return '';
  final b = StringBuffer();
  for (final s in ss) {
    final next = b.isEmpty ? s.length : b.length + 1 + s.length;
    if (next > max) break;
    if (b.isNotEmpty) b.write(' ');
    b.write(s);
  }
  if (b.isNotEmpty) return b.toString();
  return ss.first.length <= max * 2 ? ss.first : '';
}

// ---------------------------------------------------------------------------------------------
// Browsing a pack by type: the title words decide the group (arranging titles only, nothing is added).

const List<(String, String)> kTopicRules = [
  ('Fractures and injuries', r'fractur|injur|dislocation|sprain|trauma|wound|\bburns?\b|laceration'),
  ('Cancers and tumours', r'cancer|carcinoma|tumou?r|lymphoma|leuk(?:a)?emia|sarcoma|neoplas|melanoma|metasta|myeloma|blastoma|oncolog'),
  ('Infections', r'infect|virus|viral|bacteri|fung|sepsis|malaria|tubercul|\bhiv\b|hepatitis|pneumonia|abscess|syphilis|herpes|influenza|covid|parasit|cellulitis|meningitis'),
  ('Drugs and treatments', r'therapy|surgery|ectomy|otomy|plasty|scopy|transplant|vaccin|antibiotic|inhibitor|blocker|agonist|antagonist|\bdrug|/|(?:mab|pril|sartan|olol|statin|cillin|mycin|azole|vir|oxacin|cycline|dipine|prazole|tidine|epam|olam|parin|xaban|gliptin|formin|profen|fenac|coxib|setron|caine|sone|tinib)$'),
  ('Tests, scores and imaging', r'\btests?\b|\bscan\b|imaging|ultrasound|radiograph|x-ray|\bmri\b|biopsy|\bscores?\b|\bscale\b|criteria|\bindex\b|\bsign\b|reflex|examination|assay|graphy\b|tomography|\bcalculator'),
  ('Anatomy', r'muscle|artery|\bveins?\b|nerve|\bbone\b|ligament|tendon|\bjoint\b|gland|\blobe\b|\bduct\b|valve|plexus|fascia|cortex|nucleus|ganglion|membrane|vessel|sulcus|fossa|foramen|\bcell\b|tissue'),
  ('Inflammation and autoimmune', r'itis\b|lupus|vasculitis|autoimmun|sclerosis'),
  ('Syndromes and disorders', r'syndrome|disease|disorder|deficiency|dysplasia|anomaly|defect|failure|insufficiency|dystrophy|pathy\b|\bpain\b|\bdisorders?\b'),
];

final List<(String, RegExp)> _topicRx = [for (final r in kTopicRules) (r.$1, RegExp(r.$2, caseSensitive: false))];
const String kTopicOther = 'Other topics';

/// The group a title belongs to when a pack is browsed "by type" (first matching rule wins).
String topicOfTitle(String title) {
  for (final r in _topicRx) {
    if (r.$2.hasMatch(title)) return r.$1;
  }
  return kTopicOther;
}


/// Lower-case letters and digits separated by single spaces: used to find a quoted sentence inside article text.
String normQuote(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
