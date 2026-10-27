import 'data.dart';

/// Offline search over everything in the logbook: cases, notes, questions,
/// procedures, pearls, tasks, feedback and references. It understands Arabic
/// spelling variants and common medical abbreviations (MI = myocardial infarction).

// ---------------------------------------------------------------- text helpers

final RegExp _diacritics = RegExp('[ً-ٰٟـ]');

/// Lower-case, Western digits, unified Arabic letters, no diacritics.
String normText(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll(_diacritics, '');
  t = t
      .replaceAll(RegExp('[أإآٱ]'), 'ا') // alef forms
      .replaceAll('ى', 'ي') // alef maqsura -> ya
      .replaceAll('ة', 'ه') // ta marbuta -> ha
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
  const ar = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < ar.length; i++) {
    t = t.replaceAll(ar[i], '$i');
  }
  return t;
}

final RegExp _splitter = RegExp(r'[^a-z0-9؀-ۿ]+');

List<String> tokens(String s) =>
    normText(s).split(_splitter).where((e) => e.length > 1).toList();

const Set<String> _stop = {
  'the', 'and', 'with', 'for', 'was', 'were', 'has', 'have', 'had', 'his', 'her', 'she', 'him', 'after',
  'from', 'that', 'this', 'there', 'are', 'not', 'but', 'any', 'all', 'day', 'days', 'old', 'year', 'years',
  'patient', 'pt', 'demo', 'case', 'no', 'in', 'on', 'of', 'to', 'at', 'by', 'is', 'as', 'or', 'an',
};

// ---------------------------------------------------------------- synonyms

/// Each group lists words that mean the same thing (English abbreviation, full
/// term, Arabic word). A search for any of them also finds the others.
const List<List<String>> kSynonyms = [
  ['mi', 'myocardial infarction', 'heart attack', 'جلطه قلبيه', 'احتشاء'],
  ['acs', 'acute coronary syndrome', 'متلازمه شريانيه تاجيه'],
  ['stemi', 'st elevation'],
  ['htn', 'hypertension', 'high blood pressure', 'ضغط مرتفع', 'ارتفاع ضغط'],
  ['dm', 'diabetes', 'diabetes mellitus', 'سكري', 'سكر'],
  ['dka', 'diabetic ketoacidosis', 'حماض كيتوني'],
  ['cap', 'community acquired pneumonia', 'pneumonia', 'التهاب رئوي', 'التهاب رءوي'],
  ['uti', 'urinary tract infection', 'التهاب بولي', 'التهاب مسالك بوليه'],
  ['sob', 'shortness of breath', 'dyspnea', 'dyspnoea', 'ضيق نفس', 'ضيق تنفس'],
  ['cp', 'chest pain', 'الم صدر', 'الم الصدر'],
  ['hf', 'chf', 'heart failure', 'قصور قلب', 'فشل قلب'],
  ['copd', 'chronic obstructive pulmonary disease', 'انسداد رئوي مزمن'],
  ['pe', 'pulmonary embolism', 'جلطه رئه', 'انصمام رئوي'],
  ['dvt', 'deep vein thrombosis', 'جلطه وريديه', 'خثار وريدي'],
  ['aki', 'acute kidney injury', 'فشل كلوي حاد'],
  ['ckd', 'chronic kidney disease', 'فشل كلوي مزمن'],
  ['af', 'afib', 'atrial fibrillation', 'رجفان اذيني'],
  ['cva', 'stroke', 'جلطه دماغيه', 'سكته', 'سكته دماغيه'],
  ['tia', 'transient ischemic attack', 'transient ischaemic attack'],
  ['fx', 'fracture', 'كسر'],
  ['appy', 'appendicitis', 'التهاب زايده', 'زايده دوديه', 'زائده'],
  ['gerd', 'reflux', 'ارتجاع'],
  ['ugib', 'upper gi bleed', 'gi bleed', 'نزيف هضمي', 'نزيف'],
  ['uri', 'urti', 'upper respiratory tract infection', 'زكام'],
  ['fever', 'pyrexia', 'حراره', 'حمي', 'سخونه'],
  ['vomiting', 'emesis', 'تقيؤ', 'قيء', 'استفراغ'],
  ['diarrhea', 'diarrhoea', 'اسهال'],
  ['headache', 'cephalgia', 'صداع'],
  ['abd', 'abdominal', 'abdomen', 'بطن'],
  ['cxr', 'chest x-ray', 'chest xray', 'اشعه صدر'],
  ['ecg', 'ekg', 'electrocardiogram', 'تخطيط قلب'],
  ['abg', 'arterial blood gas', 'غازات دم'],
  ['cbc', 'complete blood count', 'صوره دم'],
  ['lft', 'liver function', 'وظائف كبد'],
  ['kft', 'rft', 'renal function', 'kidney function', 'وظائف كلى'],
  ['ct', 'computed tomography', 'اشعه مقطعيه'],
  ['mri', 'magnetic resonance', 'رنين مغناطيسي'],
  ['iv', 'intravenous', 'وريدي'],
  ['asthma', 'ربو'],
  ['anemia', 'anaemia', 'فقر دم'],
  ['sepsis', 'septicemia', 'تسمم دم'],
  ['preeclampsia', 'pre-eclampsia', 'pet', 'تسمم حمل'],
];

final Map<String, Set<String>> _synIndex = () {
  final m = <String, Set<String>>{};
  for (final g in kSynonyms) {
    final norm = g.map(normText).toSet();
    for (final w in norm) {
      (m[w] ??= <String>{}).addAll(norm);
    }
  }
  return m;
}();

/// A query token plus everything it can mean.
Set<String> expandToken(String t) => _synIndex[t] ?? {t};

// ---------------------------------------------------------------- documents

enum DocType { caseRec, note, question, procedure, pearl, task, feedback, evidence }

class Doc {
  final DocType type;
  final String id;
  final String title;
  final String subtitle;
  final String date;
  final String body; // normalized
  final String head; // normalized title + tags
  final Set<String> words;
  const Doc(this.type, this.id, this.title, this.subtitle, this.date, this.body, this.head, this.words);
}

class Hit {
  final Doc doc;
  final double score;
  const Hit(this.doc, this.score);
}

class SearchIndex {
  List<Doc> docs = [];
  int _rev = -1;

  /// Rebuilds only when something in the store changed.
  void ensureFresh() {
    if (_rev == store.rev && docs.isNotEmpty) return;
    _rev = store.rev;
    docs = _build();
  }

  Doc _make(DocType t, String id, String title, String sub, String date, List<String> head, List<String> body) {
    final h = normText(head.where((e) => e.isNotEmpty).join(' '));
    final b = normText(body.where((e) => e.isNotEmpty).join(' '));
    final w = <String>{...tokens('$h $b')}..removeAll(_stop);
    return Doc(t, id, title, sub, date, b, h, w);
  }

  List<Doc> _build() {
    final out = <Doc>[];
    for (final c in store.cases.values) {
      final inv = c.lst('inv').map((e) => '${e['name'] ?? ''} ${e['result'] ?? ''}').join(' ');
      final mg = c.lst('mgmt').map((e) => '${e['text'] ?? ''}').join(' ');
      out.add(_make(
        DocType.caseRec,
        c.id,
        '${c.s('code')} • ${c.title}',
        [c.s('specialty'), c.s('status')].where((e) => e.isNotEmpty).join(' • '),
        c.s('date'),
        [c.s('code'), c.s('cc'), c.s('workingDx'), c.s('finalDx'), c.s('ddx'), ...c.tags, c.s('specialty')],
        [c.s('hpi'), c.s('pmh'), c.s('problems'), c.s('reasoning'), c.s('learned'), c.s('mistakes'),
          c.s('questions'), c.s('refs'), c.s('teaching'), inv, mg],
      ));
    }
    for (final n in store.notes) {
      out.add(_make(DocType.note, '${n['id']}', '${(n['title'] ?? '').toString().isEmpty ? '(untitled)' : n['title']}',
          'Note', '${n['date'] ?? ''}', ['${n['title'] ?? ''}', '${n['tags'] ?? ''}'], ['${n['body'] ?? ''}']));
    }
    for (final q in store.inbox) {
      out.add(_make(DocType.question, '${q['id']}', '${q['question'] ?? ''}', 'Question', '${q['date'] ?? ''}',
          ['${q['question'] ?? ''}'], ['${q['answer'] ?? ''}', '${q['reference'] ?? ''}']));
    }
    for (final p in store.procedures) {
      out.add(_make(DocType.procedure, '${p['id']}', '${p['name'] ?? ''}', 'Procedure', '${p['date'] ?? ''}',
          ['${p['name'] ?? ''}'], ['${p['outcome'] ?? ''}', '${p['feedback'] ?? ''}']));
    }
    for (final p in store.listOf('pearls')) {
      out.add(_make(DocType.pearl, '${p['id']}', '${p['text'] ?? ''}', 'Pearl', '${p['date'] ?? ''}',
          ['${p['topic'] ?? ''}'], ['${p['text'] ?? ''}']));
    }
    for (final t in store.listOf('tasks')) {
      out.add(_make(DocType.task, '${t['id']}', '${t['title'] ?? ''}', 'Task', '${t['due'] ?? ''}',
          ['${t['title'] ?? ''}'], ['${t['note'] ?? ''}']));
    }
    for (final f in store.listOf('feedback')) {
      out.add(_make(DocType.feedback, '${f['id']}', '${f['said'] ?? ''}', 'Feedback', '${f['date'] ?? ''}',
          ['${f['said'] ?? ''}'], ['${f['action'] ?? ''}', '${f['from'] ?? ''}']));
    }
    for (final e in store.listOf('evidence')) {
      out.add(_make(DocType.evidence, '${e['id']}', '${e['title'] ?? ''}', 'Reference', '${e['saved'] ?? ''}',
          ['${e['title'] ?? ''}', '${e['topic'] ?? ''}'], ['${e['note'] ?? ''}', '${e['source'] ?? ''}']));
    }
    return out;
  }

  /// Every word must be found (in any of its spellings or synonyms).
  /// Matches in the title/tags count more than matches in the body.
  List<Hit> search(String query, {Set<DocType>? only, int limit = 60}) {
    ensureFresh();
    final qt = tokens(query);
    // phrase groups: a multi-word synonym (e.g. "chest pain") is matched as a phrase too
    final nq = normText(query).trim();
    if (qt.isEmpty) return const [];
    final groups = [for (final t in qt) expandToken(t)];
    final phrase = _synIndex[nq];
    final hits = <Hit>[];
    for (final d in docs) {
      if (only != null && !only.contains(d.type)) continue;
      var score = 0.0;
      var ok = true;
      for (final g in groups) {
        var best = 0.0;
        for (final v in g) {
          if (d.head.contains(v)) {
            best = best < 3 ? 3 : best;
          } else if (d.body.contains(v)) {
            best = best < 1 ? 1 : best;
          }
        }
        if (best == 0) {
          ok = false;
          break;
        }
        score += best;
      }
      if (!ok && phrase != null) {
        for (final v in phrase) {
          if (d.head.contains(v) || d.body.contains(v)) {
            ok = true;
            score = d.head.contains(v) ? 3 : 1;
            break;
          }
        }
      }
      if (!ok) continue;
      hits.add(Hit(d, score));
    }
    hits.sort((a, b) {
      final s = b.score.compareTo(a.score);
      return s != 0 ? s : b.doc.date.compareTo(a.doc.date);
    });
    return hits.take(limit).toList();
  }

  /// Cases that look like this one: shared diagnosis words, tags and complaint.
  List<Hit> similarCases(CaseRec c, {int limit = 8}) {
    ensureFresh();
    Doc? me;
    for (final d in docs) {
      if (d.type == DocType.caseRec && d.id == c.id) me = d;
    }
    if (me == null) return const [];
    final key = <String>{
      ...tokens('${c.s('workingDx')} ${c.s('finalDx')} ${c.s('cc')} ${c.tags.join(' ')}')
    }..removeAll(_stop);
    final out = <Hit>[];
    for (final d in docs) {
      if (d.type != DocType.caseRec || d.id == c.id) continue;
      final other = store.cases[d.id]!;
      var score = 0.0;
      final inter = key.intersection(d.words).length;
      if (inter == 0 && other.s('specialty') != c.s('specialty')) continue;
      score += inter * 2.0;
      final union = key.union(d.words).length;
      if (union > 0) score += 4 * (me.words.intersection(d.words).length / union);
      if (other.s('specialty') == c.s('specialty')) score += 0.5;
      final dx1 = normText(c.s('finalDx').isNotEmpty ? c.s('finalDx') : c.s('workingDx'));
      final dx2 = normText(other.s('finalDx').isNotEmpty ? other.s('finalDx') : other.s('workingDx'));
      if (dx1.isNotEmpty && dx1 == dx2) score += 4;
      if (score >= 1.5) out.add(Hit(d, score));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(limit).toList();
  }

  /// Notes, questions, pearls and references that share words with a case.
  List<Hit> relatedKnowledge(CaseRec c, {int limit = 8}) {
    ensureFresh();
    final key = <String>{
      ...tokens('${c.s('workingDx')} ${c.s('finalDx')} ${c.tags.join(' ')} ${c.s('cc')}')
    }..removeAll(_stop);
    if (key.isEmpty) return const [];
    final out = <Hit>[];
    for (final d in docs) {
      if (d.type == DocType.caseRec || d.type == DocType.task || d.type == DocType.procedure) continue;
      final inter = key.intersection(d.words).length;
      if (inter > 0) out.add(Hit(d, inter.toDouble()));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(limit).toList();
  }

  /// Most used diagnoses and tags, offered as one-tap topics.
  List<String> suggestedTopics({int limit = 12}) {
    final count = <String, int>{};
    void add(String s) {
      final v = s.trim();
      if (v.length < 3) return;
      count[v] = (count[v] ?? 0) + 1;
    }

    for (final c in store.cases.values) {
      for (final t in c.tags) {
        add(t.replaceAll('_', ' '));
      }
      final dx = c.s('finalDx').isNotEmpty ? c.s('finalDx') : c.s('workingDx');
      if (dx.trim().isNotEmpty) add(dx.trim());
    }
    for (final p in store.listOf('pearls')) {
      add('${p['topic'] ?? ''}');
    }
    final l = count.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return l.take(limit).map((e) => e.key).toList();
  }
}

final SearchIndex searchIndex = SearchIndex();
