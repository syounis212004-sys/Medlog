import 'lib_text.dart';
import 'library.dart';

/// "At a glance": the short version of an article, taken only from its own text.
/// For each key section (symptoms, causes, diagnosis, treatment, prognosis) it keeps the
/// first bullets, or the first two sentences.
class GlanceItem {
  final SecKind kind;
  final String heading;
  final List<String> points;
  const GlanceItem(this.kind, this.heading, this.points);
}

/// Key points of one section: its bullets (up to 4), or the first two sentences. Picture captions are left out and
/// a point is never cut in the middle of a sentence (a long one keeps its whole first sentences, or is skipped).
List<String> glancePoints(String text) {
  final lines = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  final bullets = <String>[];
  for (final l in lines) {
    if (!l.startsWith('• ')) continue;
    final b = l.substring(2);
    if (isCaptionLike(b)) continue;
    final f = fitSentences(b, 220);
    if (f.isNotEmpty) bullets.add(f);
  }
  if (bullets.length >= 2) return bullets.take(4).toList();
  final prose = <String>[];
  for (final s in sentences(lines.where((l) => !l.startsWith('• ')).join(' '))) {
    if (isCaptionLike(s)) continue;
    final f = fitSentences(s, 320);
    if (f.isNotEmpty) prose.add(f);
    if (prose.length == 2) break;
  }
  if (prose.isNotEmpty) return prose;
  return bullets;
}

const List<SecKind> _order = [SecKind.symptoms, SecKind.causes, SecKind.diagnosis, SecKind.treatment, SecKind.prevention];

List<GlanceItem> buildGlance(LibArticle a) {
  final out = <GlanceItem>[];
  for (final k in _order) {
    for (var i = 1; i < a.sections.length; i++) {
      final s = a.sections[i];
      if (isGalleryHeading(s.heading) || secKind(s.heading) != k) continue;
      final pts = glancePoints(s.text);
      if (pts.isEmpty) continue;
      out.add(GlanceItem(k, s.heading, pts));
      break;
    }
  }
  return out;
}
