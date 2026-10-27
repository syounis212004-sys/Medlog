import 'package:flutter/foundation.dart';

import '../data.dart';

/// User preferences of the AI layer that are NOT secrets (keys live in AiStore/SecureKv).
/// Stored in store.settings through store.setLook so every screen rebuilds. Contract shared by the settings
/// screen (builds the controls), the AI core (reads them for prompts and source choice) and the feature agents.
class AiPrefs {
  static const List<String> defaultDomains = [
    'nice.org.uk', 'cdc.gov', 'who.int', 'heart.org', 'ahajournals.org', 'acc.org', 'escardio.org', 'idsociety.org',
    'kdigo.org', 'goldcopd.org', 'ginasthma.org', 'sccm.org', 'pubmed.ncbi.nlm.nih.gov', 'ncbi.nlm.nih.gov',
    'cochranelibrary.com', 'aap.org', 'acog.org', 'diabetesjournals.org', 'ada.org', 'ahrq.gov', 'nih.gov', 'sign.ac.uk',
    'rcog.org.uk', 'bmj.com', 'thelancet.com', 'nejm.org', 'jamanetwork.com', 'esmo.org', 'nccn.org', 'wikem.org',
  ];

  static T _get<T>(String k, T d) {
    final v = store.settings[k];
    return v is T ? v : d;
  }

  static void _set(String k, Object v) => store.setLook(k, v);

  /// 'en' (default) | 'mixed' (Arabic explanation, English medical terms) | 'ar'
  static String get answerLang => _get<String>('aiAnswerLang', 'en');
  static set answerLang(String v) => _set('aiAnswerLang', v);

  /// 'brief' | 'standard' | 'full'
  static String get answerLength => _get<String>('aiAnswerLength', 'standard');
  static set answerLength(String v) => _set('aiAnswerLength', v);

  /// 'web' (trusted web via the provider's search tool when available) | 'library' | 'model' | 'custom'
  static String get sourceMode => _get<String>('aiSourceMode', 'web');
  static set sourceMode(String v) => _set('aiSourceMode', v);

  /// Allowed domains for 'web'/'custom' (user editable). Null/empty list = defaults.
  static List<String> get domains {
    final l = store.settings['aiDomains'];
    final out = l is List ? [for (final e in l) '$e'.trim().toLowerCase()] : <String>[];
    return out.isEmpty ? defaultDomains : out;
  }

  static set domains(List<String> v) => _set('aiDomains', v);

  /// User-only extra domains used by 'custom' mode.
  static List<String> get customDomains {
    final l = store.settings['aiCustomDomains'];
    return l is List ? [for (final e in l) '$e'.trim().toLowerCase()] : <String>[];
  }

  static set customDomains(List<String> v) => _set('aiCustomDomains', v);

  static bool get fabEnabled => _get<bool>('aiFab', true);
  static set fabEnabled(bool v) => _set('aiFab', v);

  /// 'start' | 'end' (side of the screen where the floating Ask-AI button rests by default)
  static String get fabSide => _get<String>('aiFabSide', 'start');
  static set fabSide(String v) => _set('aiFabSide', v);

  /// Last dragged position of the floating button (fraction of the screen height from the top, 0..1).
  static double get fabY => _get<num>('aiFabY', 0.78).toDouble();
  static set fabY(double v) => _set('aiFabY', v);

  /// Per-screen switch, e.g. screen 'quiz', 'case', 'article', 'calc', 'library', 'home', 'portfolio', 'search'.
  // reading an article: the floating button covered the text, so it starts off there (the article's own menu has the AI tools)
  static bool screenOn(String screen) => _get<bool>('aiScr_$screen', screen != 'article');
  static void setScreenOn(String screen, bool v) => _set('aiScr_$screen', v);

  static bool get showCitations => _get<bool>('aiCitations', true);
  static set showCitations(bool v) => _set('aiCitations', v);

  /// 'cards' (structured sheet) | 'text'
  static String get renderStyle => _get<String>('aiRender', 'cards');
  static set renderStyle(String v) => _set('aiRender', v);

  /// Max AI requests per day (app side guard on top of the provider quota).
  static int get dailyCap => _get<num>('aiDailyCap', 60).toInt();
  static set dailyCap(int v) => _set('aiDailyCap', v);

  /// Use the provider's own live web-search tool when it has one (Gemini grounding / Claude web_search / OpenAI search).
  static bool get providerSearch => _get<bool>('aiProviderSearch', true);
  static set providerSearch(bool v) => _set('aiProviderSearch', v);

  /// Library search: when a search finds little, ask the AI for synonyms ("Try: ..."). Needs AI on and online.
  static bool get queryExpansion => _get<bool>('aiQueryExpand', true);
  static set queryExpansion(bool v) => _set('aiQueryExpand', v);

  /// Region hint added to prompts for guideline choice (free text, e.g. 'Jordan / Middle East').
  static String get region => _get<String>('aiRegion', '');
  static set region(String v) => _set('aiRegion', v);

  // ---- domain list helpers used by the settings screen (additive)

  /// 'https://www.NICE.org.uk/guidance?x=1' -> 'nice.org.uk'; null when it does not look like a domain.
  static String? normalizeDomain(String raw) {
    var t = raw.trim().toLowerCase();
    if (t.isEmpty) return null;
    t = t.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
    t = t.split('/').first.split('?').first.split('#').first.split(':').first;
    if (t.startsWith('www.')) t = t.substring(4);
    if (!RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$').hasMatch(t)) return null;
    return t;
  }

  /// True when the list is the built-in default (nothing edited).
  static bool get domainsAreDefault {
    final l = store.settings['aiDomains'];
    return l is! List || l.isEmpty;
  }

  /// Adds a domain to the allowed list; returns false when it is invalid or already there.
  static bool addDomain(String raw, {bool custom = false}) {
    final d = normalizeDomain(raw);
    if (d == null) return false;
    final cur = custom ? customDomains : domains;
    if (cur.contains(d)) return false;
    final next = [...cur, d];
    if (custom) {
      customDomains = next;
    } else {
      domains = next;
    }
    return true;
  }

  static void removeDomain(String d, {bool custom = false}) {
    final cur = custom ? customDomains : domains;
    final next = [for (final e in cur) if (e != d) e];
    if (custom) {
      customDomains = next;
    } else {
      // an empty stored list means "defaults": keep at least one entry or go back to the defaults on purpose
      domains = next;
    }
  }

  static void resetDomains() {
    domains = <String>[];
    customDomains = <String>[];
  }

  /// True when [url] belongs to (or is a sub-domain of) one of the allowed domains of the current mode.
  static bool urlAllowed(String url) {
    final h = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (h.isEmpty) return false;
    final list = sourceMode == 'custom' && customDomains.isNotEmpty ? customDomains : domains;
    return list.any((d) => h == d || h.endsWith('.$d'));
  }

  /// Notifier other widgets can listen to (settings changes call store.setLook which already notifies the app).
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
}
