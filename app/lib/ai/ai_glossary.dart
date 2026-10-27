import '../ref_data.dart';

/// Arabic glossary hints for answers written in Arabic. The app finds the glossary terms that appear in the question and
/// asks the model to use those translations, so the same word is rendered the same way every time.
class AiGlossary {
  static Map<String, String>? _terms; // lower-case English -> Arabic (only terms that are not "keep in English")
  static bool _loading = false;

  static Future<void> ensure() async {
    if (_terms != null || _loading) return;
    _loading = true;
    try {
      _terms = {
        for (final t in await RefData.glossary())
          if (t['keepEnglish'] != true && (t['ar'] ?? '').toString().isNotEmpty && t['ar'] != 'UNSURE') (t['en'] as String).toLowerCase(): t['ar'] as String,
      };
    } catch (_) {
      _terms = {};
    } finally {
      _loading = false;
    }
  }

  /// A short instruction line, or '' when no term matches or the language is English.
  static String hintFor(String text, String lang, {int max = 24}) {
    final terms = _terms;
    if (terms == null || terms.isEmpty || lang == 'en') return '';
    final low = text.toLowerCase();
    final hits = <String>[];
    for (final e in terms.entries) {
      if (e.key.length < 4) continue;
      if (RegExp('\\b${RegExp.escape(e.key)}\\b').hasMatch(low)) {
        hits.add('${e.key} = ${e.value}');
        if (hits.length >= max) break;
      }
    }
    if (hits.isEmpty) return '';
    return 'GLOSSARY: when you write these terms in Arabic, use exactly these Arabic words: ${hits.join('; ')}.';
  }
}
