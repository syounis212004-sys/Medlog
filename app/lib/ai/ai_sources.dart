import 'ai_doc_api.dart';
import 'ai_prefs.dart';

/// Source handling of the AI layer: which sites are allowed, and the check of every citation the model gives.
/// The model can only SUGGEST a source; the app decides whether the address is acceptable (host on the allow-list,
/// https, no look-alike domain) and marks the rest, so a made-up or off-list link is never shown as verified.

/// A source returned by the provider's live search (not written by the model).
class AiSource {
  final String title;
  final String url;

  /// Real host of the page. Gemini returns a redirect address and puts the domain in the title: then [host] is the title.
  final String host;
  const AiSource({this.title = '', this.url = '', this.host = ''});

  Map<String, dynamic> toJson() => {'title': title, 'url': url, 'host': host};
  factory AiSource.fromJson(Map j) => AiSource(title: '${j['title'] ?? ''}', url: '${j['url'] ?? ''}', host: '${j['host'] ?? ''}');
}

enum CiteStatus {
  /// https, host on the allow-list (and, when the search returned its sources, the search found that host too).
  verified,

  /// host on the allow-list but the live search did not return that host: the model may have recalled it from memory.
  unconfirmed,

  /// host not on the allow-list (or look-alike domain): shown marked, never opened from the answer.
  notAllowed,

  /// not a usable address (empty, not https, no host).
  noLink,
}

class CheckedCite {
  final AiCite cite;
  final CiteStatus status;
  final String host;
  const CheckedCite(this.cite, this.status, this.host);
  bool get opensInApp => status == CiteStatus.verified || status == CiteStatus.unconfirmed;
}

class SourceCheck {
  final List<CheckedCite> items;
  const SourceCheck(this.items);
  int get verified => items.where((e) => e.status == CiteStatus.verified).length;
  int get unconfirmed => items.where((e) => e.status == CiteStatus.unconfirmed).length;
  int get notAllowed => items.where((e) => e.status == CiteStatus.notAllowed).length;
  int get noLink => items.where((e) => e.status == CiteStatus.noLink).length;
  bool get allVerified => items.isNotEmpty && items.every((e) => e.status == CiteStatus.verified);
  CheckedCite? of(AiCite c) {
    for (final i in items) {
      if (identical(i.cite, c) || (i.cite.url == c.url && i.cite.label == c.label)) return i;
    }
    return null;
  }
}

class AiSources {
  /// Bare, lower-case host of a domain entry typed by a user ("https://www.CDC.gov/path" -> "cdc.gov").
  static String normDomain(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    s = s.replaceFirst(RegExp(r'^[a-z][a-z0-9+.\-]*://'), '');
    s = s.split(RegExp(r'[/?#]')).first;
    s = s.split('@').last;
    s = s.replaceFirst(RegExp(r':\d+$'), '');
    s = s.replaceAll(RegExp(r'\.+$'), '');
    if (s.startsWith('www.')) s = s.substring(4);
    if (!RegExp(r'^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$').hasMatch(s)) return '';
    return s;
  }

  /// The allow-list used for a source mode: web = AiPrefs.domains; custom = the user's own list (AiPrefs.customDomains)
  /// when it has entries, else AiPrefs.domains. Library/model modes have no web sources.
  static List<String> allowedFor(String mode) {
    if (mode == 'library' || mode == 'model') return const [];
    final src = mode == 'custom' && AiPrefs.customDomains.isNotEmpty ? AiPrefs.customDomains : AiPrefs.domains;
    final out = <String>[];
    for (final d in src) {
      final n = normDomain(d);
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
    }
    return out;
  }

  /// Host of an https address (lower case, no trailing dot, userinfo/port ignored); '' when unusable.
  static String hostOf(String url, {bool requireHttps = true}) {
    final u = Uri.tryParse(url.trim());
    if (u == null) return '';
    if (requireHttps && u.scheme != 'https') return '';
    if (!requireHttps && u.scheme != 'https' && u.scheme != 'http') return '';
    var h = u.host.toLowerCase();
    while (h.endsWith('.')) {
      h = h.substring(0, h.length - 1);
    }
    return h;
  }

  /// Exact match or sub-domain (never a suffix of a longer name: "evilcdc.gov" and "cdc.gov.evil.com" do not match "cdc.gov").
  static bool hostMatches(String host, Iterable<String> allow) {
    final h = host.toLowerCase();
    if (h.isEmpty) return false;
    for (final a in allow) {
      if (a.isEmpty) continue;
      if (h == a || h.endsWith('.$a')) return true;
    }
    return false;
  }

  /// Checks citations against [allow] (default: the web allow-list). [seenHosts]: hosts the provider's live search
  /// returned; when given (non-empty), an allowed host that is not among them is only 'unconfirmed'.
  static SourceCheck verify(List<AiCite> cites, {Iterable<String>? allow, Iterable<String> seenHosts = const []}) {
    final al = allow == null ? allowedFor('web') : [for (final d in allow) normDomain(d)].where((e) => e.isNotEmpty).toList();
    final seen = [for (final s in seenHosts) normDomain(s)].where((e) => e.isNotEmpty).toList();
    final out = <CheckedCite>[];
    for (final c in cites) {
      final host = hostOf(c.url);
      if (host.isEmpty) {
        out.add(CheckedCite(c, CiteStatus.noLink, ''));
        continue;
      }
      if (!hostMatches(host, al)) {
        out.add(CheckedCite(c, CiteStatus.notAllowed, host));
        continue;
      }
      final confirmed = seen.isEmpty || seen.any((s) => host == s || host.endsWith('.$s') || s.endsWith('.$host'));
      out.add(CheckedCite(c, confirmed ? CiteStatus.verified : CiteStatus.unconfirmed, host));
    }
    return SourceCheck(out);
  }

  /// All citations of a document (global list and per section), without repeats.
  static List<AiCite> citesOf(AiDoc doc) {
    final seen = <String>{};
    final out = <AiCite>[];
    for (final c in [...doc.citations, for (final s in doc.sections) ...s.cites]) {
      final k = '${c.url.trim().toLowerCase()}|${c.label.trim().toLowerCase()}|${c.org.toLowerCase()}|${c.year}';
      if (seen.add(k)) out.add(c);
    }
    return out;
  }
}

/// `SourceCheck verify(List<AiCite>)` as named in the AI core contract.
SourceCheck verify(List<AiCite> cites, {Iterable<String>? allow, Iterable<String> seenHosts = const []}) =>
    AiSources.verify(cites, allow: allow, seenHosts: seenHosts);
