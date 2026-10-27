import '../data.dart';
import '../lib_user.dart';
import 'ai_doc_api.dart';
import 'ai_quiz.dart';

/// Turns a formatted AI answer ([AiDoc]) into study material, locally and deterministically (no extra AI call).
///  * [makeCards]: question/answer review cards (source "AI answer" + the guideline names of the answer).
///  * [makeQuestions]: bank questions ONLY from facts that carry a citation (the bank rule for web answers is
///    "citation present" instead of "quote inside a library passage"). Label: `AI (web answer)`.
/// AI only suggests: the caller asks the user before calling these.

const String kAiWebGroup = 'AI (web answer)';

class AiFact {
  final String text; // one sentence / bullet
  final String section;
  final List<AiCite> cites;
  const AiFact(this.text, this.section, this.cites);
}

class AiStudyHooks {
  static final RegExp _marker = RegExp(r'\[(\d{1,2})\]');

  static String _clean(String s) => s.replaceAll(_marker, '').replaceAll(RegExp(r'[*_`#]+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static List<AiCite> _inline(String s, AiDoc doc) {
    final out = <AiCite>[];
    for (final m in _marker.allMatches(s)) {
      final i = int.parse(m.group(1)!) - 1;
      if (i >= 0 && i < doc.citations.length) out.add(doc.citations[i]);
    }
    return out;
  }

  static String citeLabel(AiCite c) {
    if (c.label.trim().isNotEmpty) return c.label.trim();
    final s = [c.org.trim(), c.year.trim()].where((e) => e.isNotEmpty).join(' ');
    return s.isNotEmpty ? s : c.url.trim();
  }

  /// All guideline names mentioned by the doc (sections' cites + the global list), without repeats.
  static List<String> guidelineNames(AiDoc doc) {
    final seen = <String>{};
    final out = <String>[];
    for (final c in [...doc.citations, for (final s in doc.sections) ...s.cites]) {
      final l = citeLabel(c);
      if (l.isNotEmpty && seen.add(l.toLowerCase())) out.add(l);
    }
    return out;
  }

  static bool _skip(AiDocSection s) => const {'references', 'note'}.contains(s.kind);

  /// Facts that have a citation: the section's own cites, or an inline [n] marker that points into doc.citations.
  static List<AiFact> citedFacts(AiDoc doc) {
    final out = <AiFact>[];
    for (final s in doc.sections) {
      if (_skip(s)) continue;
      final title = s.title.trim();
      void add(String raw, List<AiCite> extra) {
        final cites = [...s.cites, ...extra, ..._inline(raw, doc)];
        final t = _clean(raw);
        if (cites.isEmpty || t.length < 20) return;
        out.add(AiFact(t, title, cites));
      }
      for (final b in s.bullets) {
        add(b, const []);
      }
      if (s.bullets.isEmpty && s.text.trim().isNotEmpty) {
        for (final sent in s.text.split(RegExp(r'(?<=[.!?])\s+'))) {
          add(sent, const []);
        }
      }
    }
    return out;
  }

  // ------------------------------------------------------------ cards

  static List<(String, String)> cardPairs(AiDoc doc, String topic) {
    final out = <(String, String)>[];
    for (final s in doc.sections) {
      if (_skip(s)) continue;
      final title = s.title.trim().isEmpty ? s.kind.replaceAll('_', ' ') : s.title.trim();
      final head = topic.isEmpty ? title : '$title: $topic';
      if (s.table.length >= 2) {
        final hdr = s.table.first;
        for (final row in s.table.skip(1).take(8)) {
          if (row.length < 2 || _clean(row.first).isEmpty) continue;
          final back = [for (var i = 1; i < row.length; i++) '${i < hdr.length ? '${_clean(hdr[i])}: ' : ''}${_clean(row[i])}'].join('\n');
          out.add(('${_clean(row.first)} ($head)', back));
        }
      } else if (s.bullets.isNotEmpty) {
        final b = [for (final x in s.bullets.take(6)) '• ${_clean(x)}'].where((e) => e.length > 3).toList();
        if (b.isNotEmpty) out.add((head.endsWith('?') ? head : '$head?', b.join('\n')));
      } else if (s.text.trim().length >= 20) {
        final t = _clean(s.text);
        out.add((head.endsWith('?') ? head : '$head?', t.length > 420 ? '${t.substring(0, 417)}...' : t));
      }
    }
    return out;
  }

  /// Returns how many NEW cards were added to the review deck.
  static Future<int> makeCards(AiDoc doc, {String source = ''}) async {
    final names = guidelineNames(doc);
    final src = names.isEmpty ? 'AI answer' : 'AI answer · ${names.take(3).join(', ')}';
    final topic = source.trim();
    var n = 0;
    for (final (q, a) in cardPairs(doc, topic)) {
      final back = names.isEmpty ? a : '$a\n\n(${names.take(3).join(', ')})';
      if (await addLibraryCard(front: '$q\n\n(AI answer)', back: back, source: src, title: topic.isEmpty ? 'AI answer' : topic)) n++;
    }
    return n;
  }

  // ------------------------------------------------------------ questions

  static final RegExp _number = RegExp(r'\d+(?:[.,]\d+)?(?:\s?[-–]\s?\d+(?:[.,]\d+)?)?\s?(?:mg/kg|mg/dl|mmol/l|mmhg|mcg|mg|ml|g|%|hours?|hrs?|h|days?|weeks?|months?|years?|minutes?|min)?', caseSensitive: false);
  static final RegExp _word = RegExp(r"[A-Za-z][A-Za-z'\-]{5,}");
  static const Set<String> _weak = {'patients', 'patient', 'should', 'recommended', 'recommend', 'treatment', 'management', 'guideline', 'guidelines', 'because', 'however', 'including', 'therapy', 'according', 'following', 'adults', 'children', 'consider', 'considered', 'usually', 'generally', 'before', 'during', 'between', 'within', 'without'};

  /// The key term of a fact that becomes the blank (a number with unit, else a drug-like / long word).
  static String? keyTerm(String fact) {
    final nums = [for (final m in _number.allMatches(fact)) m.group(0)!.trim()].where((e) => RegExp(r'\d').hasMatch(e) && e.length <= 24).toList();
    if (nums.isNotEmpty) {
      nums.sort((a, b) => b.length.compareTo(a.length));
      return nums.first;
    }
    final words = [for (final m in _word.allMatches(fact)) m.group(0)!].where((w) => !_weak.contains(w.toLowerCase())).toList();
    if (words.isEmpty) return null;
    // a capitalised word that is not the first word (a drug or a disease name) beats a plain long word
    final caps = words.where((w) => w[0] == w[0].toUpperCase() && fact.indexOf(w) > 0).toList();
    final pool = caps.isNotEmpty ? caps : words;
    pool.sort((a, b) => b.length.compareTo(a.length));
    return pool.first;
  }

  static Map<String, dynamic>? _questionOf(AiFact f) {
    if (f.text.length > 260) return null;
    final term = keyTerm(f.text);
    if (term == null) return null;
    final idx = f.text.indexOf(term);
    if (idx < 0) return null;
    final blank = f.text.replaceRange(idx, idx + term.length, '______');
    final c = f.cites.first;
    final label = citeLabel(c);
    final stem = 'Complete the statement ($label): $blank';
    return {
      'id': quizHash(stem, term),
      'stem': stem,
      'options': <String>[],
      'answer': 0,
      'answerText': term,
      'expl': 'From the cited answer (${f.section.isEmpty ? 'AI answer' : f.section}): ${f.text}',
      'quote': f.text,
      'p': '',
      'i': -1,
      'title': label,
      'section': f.section,
      'topic': f.section.isEmpty ? label : f.section,
      'group': kAiWebGroup,
      'diff': 'medium',
      'style': 'short',
      'src': 'web',
      'cite': label,
      'url': c.url,
      'seen': 0,
      'correct': 0,
      'flagged': false,
      'createdAt': nowIso(),
    };
  }

  static List<Map<String, dynamic>> questionMaps(AiDoc doc) {
    final out = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final f in citedFacts(doc)) {
      final m = _questionOf(f);
      if (m != null && ids.add('${m['id']}')) out.add(m);
    }
    // table rows with a citation on the section: "item -> current"
    for (final s in doc.sections) {
      if (_skip(s) || s.table.length < 2 || s.cites.isEmpty) continue;
      final hdr = s.table.first;
      final label = citeLabel(s.cites.first);
      for (final row in s.table.skip(1).take(8)) {
        if (row.length < 2 || _clean(row.first).isEmpty || _clean(row.last).length < 2) continue;
        final stem = 'According to $label: ${_clean(row.first)} - ${_clean(hdr.length == row.length ? hdr.last : 'recommendation')}?';
        final ans = _clean(row.last);
        if (ans.length > 120) continue;
        final id = quizHash(stem, ans);
        if (!ids.add(id)) continue;
        out.add({
          'id': id, 'stem': stem, 'options': <String>[], 'answer': 0, 'answerText': ans,
          'expl': 'From the cited answer (${s.title}): ${row.map(_clean).join(' | ')}',
          'quote': row.map(_clean).join(' | '), 'p': '', 'i': -1, 'title': label, 'section': s.title,
          'topic': s.title.isEmpty ? label : s.title, 'group': kAiWebGroup, 'diff': 'medium', 'style': 'short', 'src': 'web',
          'cite': label, 'url': s.cites.first.url, 'seen': 0, 'correct': 0, 'flagged': false, 'createdAt': nowIso(),
        });
      }
    }
    return out;
  }

  /// Saves questions made from cited facts only; returns how many NEW questions were added to the AI bank.
  static Future<int> makeQuestions(AiDoc doc) async {
    final have = {for (final q in aiBank(includeFlagged: true)) q.id};
    var n = 0;
    for (final m in questionMaps(doc)) {
      if (have.contains(m['id'])) continue;
      await aiSaveQ(m);
      have.add('${m['id']}');
      n++;
    }
    return n;
  }
}
