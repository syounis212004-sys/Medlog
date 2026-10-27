import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../i18n.dart';
import 'ai_api.dart';
import 'ai_help_faq.dart';

export 'ai_help_faq.dart' show FaqEntry, kFaq;

/// App help: a bundled offline FAQ with a LOCAL keyword search (works with no internet, no key, no AI).
/// Optional: the best-matching entries + the user's question can be rephrased by the AI (level none, ZERO user data).

const Set<String> _stop = {
  'how', 'do', 'i', 'to', 'the', 'a', 'an', 'my', 'can', 'what', 'is', 'are', 'where', 'does', 'it', 'in', 'of', 'on',
  'for', 'me', 'we', 'you', 'and', 'or', 'with', 'this', 'that', 'use', 'make', 'get', 'should', 'there', 'any', 'من',
  'في', 'على', 'عن', 'هل', 'كيف', 'ما', 'ماذا', 'أين', 'اين', 'هذا', 'هذه', 'إلى', 'الى', 'مع', 'او', 'أو', 'و',
};

final RegExp _marks = RegExp('[ً-ٰٟـ]');

/// Lower case, no Arabic diacritics/tatweel, unified alef/ya/ta marbuta, digits kept.
String normHelp(String s) {
  var t = s.toLowerCase().replaceAll(_marks, '');
  t = t.replaceAll(RegExp('[آأإ]'), 'ا').replaceAll('ى', 'ي').replaceAll('ة', 'ه');
  return t;
}

List<String> helpTokens(String q) {
  final out = <String>[];
  for (final w in normHelp(q).split(RegExp(r'[^a-z0-9؀-ۿ#+]+'))) {
    if (w.isEmpty || _stop.contains(w)) continue;
    if (w.length < 2 && !RegExp(r'[0-9+#]').hasMatch(w)) continue;
    out.add(w);
  }
  return out;
}

String _stem(String w) {
  if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.length > 4 && w.endsWith('ing')) return w.substring(0, w.length - 3);
  if (w.length > 3 && w.endsWith('es')) return w.substring(0, w.length - 2);
  if (w.length > 3 && w.endsWith('s')) return w.substring(0, w.length - 1);
  if (w.length > 4 && w.endsWith('ed')) return w.substring(0, w.length - 2);
  if (w.length > 4 && w.startsWith('ال')) return w.substring(2);
  return w;
}

class FaqHit {
  final FaqEntry entry;
  final int score;
  const FaqHit(this.entry, this.score);
}

class HelpIndex {
  final List<List<Set<String>>> _kw = [];
  final List<String> _q = [];
  final List<String> _a = [];
  final String lang;
  HelpIndex._(List<FaqEntry> faq) : lang = langCode {
    for (final e in faq) {
      // in the Arabic app the translated question and answer are searchable too
      _kw.add([_words(e.kw), _words(isAr ? '${e.q} ${tr(e.q)}' : e.q), _words(isAr ? '${e.a} ${tr(e.a)}' : e.a)]);
      _q.add(normHelp(e.q));
      _a.add(normHelp(e.a));
    }
  }

  static Set<String> _words(String s) => {
        for (final w in normHelp(s).split(RegExp(r'[^a-z0-9؀-ۿ#+]+')))
          if (w.isNotEmpty) ...{w, _stem(w)}
      };
}

HelpIndex? _index;
HelpIndex _idx() {
  final i = _index;
  if (i != null && i.lang == langCode) return i;
  return _index = HelpIndex._(kFaq);
}

/// LOCAL search: keywords (3) > question words (2) > answer words (1); prefix matches count less.
/// Arabic and English queries both work (keywords hold both languages). Never touches the network.
List<FaqHit> searchFaq(String query, {int limit = 5, List<FaqEntry>? faq}) {
  final list = faq ?? kFaq;
  final toks = helpTokens(query);
  if (toks.isEmpty) return const [];
  final idx = list == kFaq ? _idx() : HelpIndex._(list);
  final out = <FaqHit>[];
  for (var i = 0; i < list.length; i++) {
    final kw = idx._kw[i][0], qw = idx._kw[i][1], aw = idx._kw[i][2];
    var score = 0;
    var matched = 0;
    for (final t in toks) {
      final s = _stem(t);
      var best = 0;
      if (kw.contains(t) || kw.contains(s)) {
        best = 6;
      } else if (qw.contains(t) || qw.contains(s)) {
        best = 4;
      } else if (aw.contains(t) || aw.contains(s)) {
        best = 2;
      } else if (t.length >= 3) {
        if (kw.any((w) => w.startsWith(s) && s.length >= 3)) {
          best = 3;
        } else if (qw.any((w) => w.startsWith(s))) {
          best = 2;
        } else if (aw.any((w) => w.startsWith(s))) {
          best = 1;
        }
      }
      if (best > 0) matched++;
      score += best;
    }
    if (matched == 0) continue;
    // every word found: bonus
    if (matched == toks.length) score += 3;
    out.add(FaqHit(list[i], score));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  // drop weak tails (less than a third of the best)
  if (out.isEmpty) return out;
  final top = out.first.score;
  return out.where((h) => h.score * 3 >= top).take(limit).toList();
}

/// Suggestions shown before the user types.
const List<String> kHelpStarters = [
  'How do I log a case quickly?',
  'How do I back up my data?',
  'How do I download library packs?',
  'How do I export a PDF?',
  'How do I lock the app with a PIN?',
  'What is sent to the AI?',
  'What is the Ask AI button?',
  'What sources does the AI use?',
  'How does Drug check work?',
];

/// Optional AI rephrase of the best-matching entries. The model receives ONLY the question and the FAQ text:
/// no user data of any kind. Returns null when AI is off/offline/cancelled (the caller shows the local entries).
Future<String?> aiRephrase(String question, List<FaqEntry> entries) async {
  if (!Ai.enabled || entries.isEmpty) return null;
  final q = question.trim();
  if (q.isEmpty) return null;
  final b = StringBuffer();
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    b.writeln('[${i + 1}] Q: ${e.q}\nA: ${e.a}\n');
  }
  final prompt = 'User question: $q\n\nFAQ entries:\n$b';
  final key = md5.convert(utf8.encode('help|$q|${entries.map((e) => e.id).join(',')}|$langCode')).toString().substring(0, 20);
  final r = await Ai.run(AiRequest(
    feature: 'help_faq',
    system: 'You are the help assistant of MedLog, an offline medical logbook app. Answer the user question ONLY using the FAQ '
        'entries provided. Give short numbered steps. If the entries do not answer the question, say so in one sentence and '
        'point to the closest entry; never invent features, menus or settings that are not in the entries. Do not give '
        'medical advice. Reply in ${isAr ? 'Modern Standard Arabic (keep English medical terms and menu names as they are)' : 'English'}. '
        'At most 120 words.',
    prompt: prompt,
    level: AiLevel.none,
    maxTokens: 400,
    temperature: 0.1,
    cacheKey: key,
  ));
  if (!r.ok || r.text.trim().isEmpty) return null;
  return r.text.trim();
}
