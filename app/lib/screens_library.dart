import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:webview_flutter/webview_flutter.dart';

import 'data.dart';
import 'i18n.dart';
import 'lib_text.dart' show kTopicRules, kTopicOther, topicOfTitle;
import 'lib_user.dart';
import 'library.dart';
import 'lib_sheet.dart' show SBlock, BKind, SheetTag, SRange;
import 'ai/ai_api.dart' show AiStore;
import 'ai/ai_prefs.dart';
import 'screens_ai_settings.dart' show AiSettingsBody;
import 'settings_tuner.dart';
import 'settings_widgets.dart';
import 'med_terms.dart';
import 'screens_ai_library.dart';
import 'screens_article.dart';
import 'sheet_widgets.dart';
import 'ui.dart';
import 'widgets.dart';

// ================================================================ library home (also the Library tab)

class LibraryScreen extends StatefulWidget {
  final String initialQuery;
  final bool embedded;
  const LibraryScreen({super.key, this.initialQuery = '', this.embedded = false});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final TextEditingController _q = TextEditingController(text: widget.initialQuery);
  List<LibHit> _hits = const [];
  String? _fix;
  bool _busy = false;
  Timer? _debounce;
  Future<LibHit?>? _today;
  int _todayKey = -1;
  String? _source;
  Timer? _ftsTimer;

  bool get _body => store.settings['libBody'] != false;
  bool get _concise => store.settings['libConcise'] != false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) _run();
    // the in-text index is built in the background a moment after the library opens
    if (_body) _ftsTimer = Timer(const Duration(seconds: 2), () => library.ensureFts().then((_) => library.warmFts(), onError: (_) {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ftsTimer?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
    setState(() {});
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() {
        _hits = const [];
        _fix = null;
      });
      return;
    }
    setState(() => _busy = true);
    var h = await library.searchEx(q, source: _source, body: _body, concise: _concise);
    String? fix;
    if (h.length < 3) {
      fix = await library.didYouMean(q);
      if (fix != null) {
        final more = await library.searchEx(fix, source: _source, body: _body, concise: _concise);
        if (more.length > h.length) h = more;
      }
    }
    if (mounted && q == _q.text.trim()) {
      setState(() {
        _hits = h;
        _fix = fix;
        _busy = false;
      });
    }
  }

  /// One row of the study tools card: round icon, title and a one-line hint.
  Widget _shelfTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      );

  Future<void> _openByTitle(String packId, String title) async {
    final i = await library.indexOfTitle(packId, title);
    if (i != null && mounted) openArticle(context, packId, i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([library, store]),
      builder: (context, _) {
        final packs = library.textPacks;
        final searching = _q.text.trim().isNotEmpty;
        final favs = favorites();
        final recents = recentArticles();
        final later = readingList();
        if (_todayKey != library.packs.length) {
          _todayKey = library.packs.length;
          _today = topicOfTheDay();
        }
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !widget.embedded,
            title: Text('Library'),
            actions: [
              if (packs.isNotEmpty)
                IconButton(
                  key: const Key('lib_ask'),
                  tooltip: tr('Ask my references'),
                  icon: const Icon(Icons.question_answer_outlined),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AskReferencesScreen(initialQuestion: _q.text.trim()))),
                ),
              IconButton(
                tooltip: tr('Courses and library'),
                icon: const Icon(Icons.download_for_offline_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PackManagerScreen())),
              ),
              IconButton(
                tooltip: tr('Library settings'),
                icon: const Icon(Icons.tune),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibrarySettingsScreen())),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextField(
                controller: _q,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _run(),
                decoration: InputDecoration(
                  labelText: tr('Search the library'),
                  hintText: 'osteoarthritis, OA, ACL…',
                  suffixIcon: _q.text.isEmpty
                      ? const Icon(Icons.search)
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _q.clear();
                            _run();
                          },
                        ),
                ),
              ),
              const SizedBox(height: 8),
              if (searching) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: NlSearchChip(
                    text: _q.text,
                    onQuery: (q) {
                      _q.text = q;
                      _run();
                    },
                  ),
                ),
                SourceFilterChips(
                  sources: library.availableSources(),
                  selected: _source,
                  onChanged: (v) {
                    setState(() => _source = v);
                    _run();
                  },
                ),
                Wrap(spacing: 6, children: [
                  FilterChip(
                    avatar: const Icon(Icons.manage_search, size: 16),
                    label: Text('Search inside articles'),
                    selected: _body,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) {
                      store.settings['libBody'] = v;
                      store.saveSettings();
                      if (v) library.ensureFts().then((_) {}, onError: (_) {});
                      setState(() {});
                      _run();
                    },
                  ),
                  FilterChip(
                    avatar: const Icon(Icons.short_text, size: 16),
                    label: Text('Concise sources first'),
                    selected: _concise,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) {
                      store.settings['libConcise'] = v;
                      store.saveSettings();
                      setState(() {});
                      _run();
                    },
                  ),
                ]),
                if (_body && library.ftsBuilding)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(trp('Preparing text search: {a} of {b} courses', {'a': library.ftsDone, 'b': library.ftsTotal}), style: theme.textTheme.bodySmall),
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (_fix != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${tr('Showing results for')}: $_fix', style: theme.textTheme.bodySmall),
                  ),
                if (!_busy && _hits.isEmpty)
                  Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Nothing found in your downloaded courses.'))),
                if (!_busy)
                  AiTrySuggestions(
                    query: _q.text,
                    resultCount: _hits.length,
                    onPick: (t) {
                      _q.text = t;
                      _run();
                    },
                  ),
                for (final h in _hits)
                  AppCard(
                    child: ListTile(
                      title: Text(stripSource(h.title), maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: hitSubtitle(h.packId, h.title, h.lead, hit: h),
                      trailing: isFavorite(h.packId, h.title) ? const Icon(Icons.star, size: 18, color: Colors.amber) : null,
                      onTap: () => openHit(context, h),
                    ),
                  ),
              ] else ...[
                const SizedBox(height: 8),
                FutureBuilder<LibHit?>(
                  future: _today,
                  builder: (context, snap) {
                    final t = snap.data;
                    if (t == null) return const SizedBox.shrink();
                    return AppCard(
                      color: theme.colorScheme.primaryContainer.withAlpha(90),
                      child: ListTile(
                        leading: const Icon(Icons.wb_sunny_outlined),
                        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Topic of the day', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
                          Directionality(textDirection: TextDirection.ltr, child: Text(t.lead, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ]),
                        onTap: () => openArticle(context, t.packId, t.index),
                      ),
                    );
                  },
                ),
                if (packs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      const Icon(Icons.menu_book_outlined, size: 48),
                      const SizedBox(height: 8),
                      Text('No courses downloaded yet. Start with the essentials: short summaries that work offline.', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PackManagerScreen())),
                        icon: const Icon(Icons.download),
                        label: Text('Get courses'),
                      ),
                    ]),
                  ),
                if (recents.isNotEmpty) ...[
                  _shelfTitle(tr('Continue reading')),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      key: const Key('lib_shelf'),
                      scrollDirection: Axis.horizontal,
                      itemCount: recents.take(8).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final r = recents[i];
                        return SizedBox(
                          width: 200,
                          child: Material(
                            color: theme.colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openByTitle('${r['p']}', '${r['t']}'),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(child: Directionality(textDirection: TextDirection.ltr, child: Text(stripSource('${r['t']}'), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)))),
                                  Text(library.pack('${r['p']}')?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                                ]),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (packs.isNotEmpty) ...[
                  Builder(builder: (context) {
                    final cs = theme.colorScheme;
                    final mine = [for (final p in packs) if (p.kind == 'book' || p.kind == 'user') p];
                    final courses = [for (final p in packs) if (p.kind != 'book' && p.kind != 'user') p];
                    Widget row(PackMeta p) => ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: Icon(p.kind == 'user' ? Icons.folder_outlined : Icons.menu_book_outlined, color: cs.primary),
                          title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${p.count} ${tr('articles')}'),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackBrowseScreen(pack: p))),
                        );
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (mine.isNotEmpty) ...[
                        _shelfTitle(tr('My books')),
                        AppCard(child: Column(children: [for (var i = 0; i < mine.length; i++) ...[if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12), row(mine[i])]])),
                      ],
                      if (courses.isNotEmpty)
                        Fold(
                          id: 'lib_courses_all',
                          title: trp('Courses ({n})', {'n': courses.length}),
                          subtitle: tr('Specialties and references'),
                          icon: Icons.school_outlined,
                          children: [for (final p in courses) row(p)],
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const Key('lib_add_course'),
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PackManagerScreen())),
                          icon: const Icon(Icons.add_circle_outline),
                          label: Text('Add course'),
                        ),
                      ),
                    ]);
                  }),
                ],
                if (later.isNotEmpty)
                  Fold(
                    id: 'lib_readlater',
                    title: tr('Read later'),
                    subtitle: trp('{n} articles', {'n': later.length}),
                    icon: Icons.bookmark_outline,
                    initiallyOpen: true,
                    children: [
                      for (final r in later)
                        Dismissible(
                          key: ValueKey('later_${r['p']}|${r['t']}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: theme.colorScheme.errorContainer,
                            alignment: AlignmentDirectional.centerEnd,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Icon(Icons.bookmark_remove_outlined, color: theme.colorScheme.onErrorContainer),
                          ),
                          onDismissed: (_) {
                            // the list changes at once (saving continues in the background): a dismissed row must leave the tree now
                            toggleReadingList('${r['p']}', '${r['t']}');
                            setState(() {});
                          },
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.bookmark, size: 20),
                            title: Text(stripSource('${r['t']}'), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(library.pack('${r['p']}')?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              tooltip: tr('Remove'),
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                toggleReadingList('${r['p']}', '${r['t']}');
                                setState(() {});
                              },
                            ),
                            onTap: () => _openByTitle('${r['p']}', '${r['t']}'),
                          ),
                        ),
                    ],
                  ),
                if (favs.isNotEmpty)
                  Fold(
                    id: 'lib_favs',
                    title: tr('Favorites'),
                    icon: Icons.star_outline,
                    children: [
                      for (final f in favs)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.star, size: 20, color: Colors.amber),
                          title: Text('${f['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _openByTitle('${f['pack']}', '${f['title']}'),
                        ),
                    ],
                  ),
                if (packs.isNotEmpty)
                  Text(
                    trp('{n} articles • {size} on this phone', {'n': library.totalCount, 'size': fmtBytes(library.totalBytes)}),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                Fold(
                  id: 'lib_online',
                  title: tr('Online library'),
                  subtitle: tr('Opens inside the app'),
                  icon: Icons.public,
                  children: [
                    for (final group in kSiteGroups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                        child: Text(group.title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                      ),
                      for (final s in group.sites)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.travel_explore, size: 20),
                          title: Text(s.name),
                          subtitle: Text(s.about),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(title: s.name, url: s.url))),
                        ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

void openArticle(BuildContext context, String packId, int index, {String? focusQuote}) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleScreen(packId: packId, index: index, focusQuote: focusQuote)));
}

/// Opens a search hit: a hit found inside the text opens the article at that very sentence.
void openHit(BuildContext context, LibHit h) => openArticle(context, h.packId, h.index, focusQuote: h.inText ? h.snippet : null);

// ================================================================ sources (badges + filter chips)

Color sourceColor(String s) => switch (s) {
      'WikEM' => const Color(0xFFC62828),
      'CDC' => const Color(0xFF1565C0),
      'NCI' => const Color(0xFF6A1B9A),
      'Project Tulip' => const Color(0xFF00796B),
      'Wikipedia' => const Color(0xFF546E7A),
      'MedlinePlus' => const Color(0xFF2E7D32),
      _ => const Color(0xFF757575),
    };

/// Small coloured label that says where an article comes from.
class SourceBadge extends StatelessWidget {
  final String source;
  const SourceBadge(this.source, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = sourceColor(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(6), border: Border.all(color: c.withAlpha(120))),
      child: Text(source, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

/// "All / WikEM / CDC ..." chips. [selected] null means All.
class SourceFilterChips extends StatelessWidget {
  final List<String> sources;
  final String? selected;
  final ValueChanged<String?> onChanged;
  const SourceFilterChips({super.key, required this.sources, required this.selected, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    if (sources.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          ChoiceChip(label: Text('All'), selected: selected == null, visualDensity: VisualDensity.compact, onSelected: (_) => onChanged(null)),
          for (final s in sources)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: ChoiceChip(label: Text(s), selected: selected == s, visualDensity: VisualDensity.compact, onSelected: (_) => onChanged(selected == s ? null : s)),
            ),
        ]),
      ),
    );
  }
}

/// Subtitle of a library result: source badge (when several sources are installed) above the lead, or, for a hit found
/// inside the article, the matching sentence with the words highlighted.
Widget hitSubtitle(String packId, String title, String lead, {int lines = 2, LibHit? hit}) {
  final showBadge = library.availableSources().length > 1;
  Widget lt;
  if (hit != null && hit.inText) {
    lt = Builder(builder: (context) {
      final theme = Theme.of(context);
      final base = theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant);
      final t = hit.snippet;
      final spans = <TextSpan>[];
      var at = 0;
      for (var i = 0; i + 1 < hit.marks.length; i += 2) {
        final a = hit.marks[i].clamp(0, t.length), b = hit.marks[i + 1].clamp(0, t.length);
        if (a < at || b <= a) continue;
        if (a > at) spans.add(TextSpan(text: t.substring(at, a)));
        spans.add(TextSpan(text: t.substring(a, b), style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface, backgroundColor: const Color(0x55FFE082))));
        at = b;
      }
      if (at < t.length) spans.add(TextSpan(text: t.substring(at)));
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hit.snippetHead.trim().isNotEmpty) Text('${tr('In')} ${hit.snippetHead}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
          RichText(maxLines: lines + 1, overflow: TextOverflow.ellipsis, text: TextSpan(style: base, children: spans)),
        ]),
      );
    });
  } else {
    lt = Text(lead, maxLines: lines, overflow: TextOverflow.ellipsis);
  }
  if (!showBadge) return lt;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(top: 2, bottom: 3), child: SourceBadge(library.sourceOf(packId, title))),
    lt,
  ]);
}

// ================================================================ big downloads on mobile data

/// Before a big download: when the phone is on mobile data (and "Download on Wi-Fi only" is on)
/// asks "Download anyway?". Returns true when the download may start now (also after waiting for Wi-Fi).
/// A plugin that fails never blocks the download.
Future<bool> allowDownloadNow(BuildContext context, {required int bytes, bool images = false, VoidCallback? onWaiting, bool Function()? cancelled}) async {
  if (!needsWifiCheck(bytes: bytes, images: images)) return true;
  if (await currentNetKind() != NetKind.mobile) return true;
  if (!context.mounted) return false;
  final c = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Mobile data'),
      content: Text('You are on mobile data. Download anyway?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, 'wait'), child: Text('Wait for Wi-Fi')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'once'), child: Text('Download once')),
      ],
    ),
  );
  if (c == 'once') return true;
  if (c == 'wait') {
    onWaiting?.call();
    return waitForWifi(cancelled: cancelled);
  }
  return false;
}

// ================================================================ browsing one course

class PackBrowseScreen extends StatefulWidget {
  final PackMeta pack;
  const PackBrowseScreen({super.key, required this.pack});
  @override
  State<PackBrowseScreen> createState() => _PackBrowseScreenState();
}

const double _kRowH = 76;

class _PackBrowseScreenState extends State<PackBrowseScreen> {
  List<String> _titles = const [];
  List<String> _leads = const [];
  List<int> _chapterNumbers = const [];
  List<LibChapter> _chapters = const [];
  List<int> _order = const []; // every article, A-Z by shown title (or concise sources first)
  List<int> _shown = const [];
  final _q = TextEditingController();
  final _scroll = ScrollController();
  String? _source;
  bool _az = false;
  bool _conciseFirst = true;

  /// The concise essentials pack mixes sources: it gets the same filter chips as the search.
  bool get _mixed => widget.pack.id == kEssentialsPackId;
  bool get _book => widget.pack.kind == 'book';

  String _name(int i) => _mixed ? stripSource(_titles[i]) : _titles[i];

  @override
  void initState() {
    super.initState();
    _az = !_book && widget.pack.count < 120; // books retain their source chapter order
    () async {
      final t = await library.titlesOf(widget.pack.id);
      final l = await library.leadsOf(widget.pack.id);
      final chapterNumbers = _book ? await library.chapterNumbersOf(widget.pack.id) : const <int>[];
      final chapters = _book ? await library.chaptersOf(widget.pack.id) : const <LibChapter>[];
      if (mounted) {
        setState(() {
          _titles = t;
          _leads = l;
          _chapterNumbers = chapterNumbers;
          _chapters = chapters;
          _resort();
        });
      }
    }();
  }

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static int _srcRank(String? s) => switch (s) { 'WikEM' => 0, 'Project Tulip' => 1, 'CDC' => 2, 'NCI' => 4, _ => 3 };

  void _resort() {
    final idx = List<int>.generate(_titles.length, (i) => i);
    if (!_book) idx.sort((a, b) {
      if (_mixed && _conciseFirst) {
        final c = _srcRank(titleSource(_titles[a])).compareTo(_srcRank(titleSource(_titles[b])));
        if (c != 0) return c;
      }
      return _name(a).toLowerCase().compareTo(_name(b).toLowerCase());
    });
    _order = idx;
    _filter(_q.text);
  }

  void _filter(String s) {
    final q = s.trim().toLowerCase();
    setState(() {
      _shown = [
        for (final i in _order)
          if ((q.isEmpty || _titles[i].toLowerCase().contains(q)) && (_source == null || titleSource(_titles[i]) == _source)) i
      ];
    });
  }

  static String _letter(String t) {
    for (var i = 0; i < t.length; i++) {
      final c = t[i].toUpperCase();
      if (RegExp(r'[A-Z]').hasMatch(c)) return c;
      if (RegExp(r'[0-9]').hasMatch(c)) return '#';
    }
    return '#';
  }

  Widget _row(int i) => SizedBox(
        height: _kRowH,
        child: ListTile(
          title: _book
              ? m.Text(_name(i), textDirection: TextDirection.ltr, textAlign: TextAlign.left, maxLines: 2, overflow: TextOverflow.ellipsis)
              : Text(_name(i), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: _book ? null : _mixed ? hitSubtitle(widget.pack.id, _titles[i], _leads[i]) : Text(_leads[i], maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => openArticle(context, widget.pack.id, i),
        ),
      );

  Widget _azList() {
    // first row of every letter, for the jump bar
    final first = <String, int>{};
    for (var k = 0; k < _shown.length; k++) {
      first.putIfAbsent(_letter(_name(_shown[k])), () => k);
    }
    final letters = first.keys.toList()..sort((a, b) => a == '#' ? -1 : (b == '#' ? 1 : a.compareTo(b)));
    return Row(children: [
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 24),
          itemExtent: _kRowH,
          itemCount: _shown.length,
          itemBuilder: (context, k) => _row(_shown[k]),
        ),
      ),
      if (_q.text.isEmpty && letters.length > 1)
        SizedBox(
          width: 26,
          child: LayoutBuilder(builder: (context, c) {
            final step = (c.maxHeight / letters.length).clamp(14.0, 28.0);
            void jump(double dy) {
              final k = (dy / step).floor().clamp(0, letters.length - 1);
              final row = first[letters[k]]!;
              _scroll.jumpTo((row * _kRowH).clamp(0.0, _scroll.position.maxScrollExtent));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => jump(d.localPosition.dy),
              onVerticalDragUpdate: (d) => jump(d.localPosition.dy),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final l in letters)
                  SizedBox(height: step, child: Center(child: Text(l, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)))),
              ]),
            );
          }),
        ),
    ]);
  }

  Widget _topicList() {
    if (_book) return _chapterList();
    final groups = <String, List<int>>{};
    for (final i in _shown) {
      (groups[topicOfTitle(_name(i))] ??= []).add(i);
    }
    final names = [for (final r in kTopicRules) r.$1, kTopicOther].where(groups.containsKey).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final n in names)
          Card(
            elevation: 0,
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: ExpansionTile(
              title: Text(tr(n), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${groups[n]!.length}'),
              children: [for (final i in groups[n]!) _row(i)],
            ),
          ),
      ],
    );
  }

  Widget _chapterList() {
    final groups = <int, List<int>>{};
    for (final i in _shown) {
      final chapter = i < _chapterNumbers.length ? _chapterNumbers[i] : 0;
      (groups[chapter] ??= []).add(i);
    }
    final labels = {for (final chapter in _chapters) chapter.number: chapter.title};
    final order = [
      for (final chapter in _chapters) if (groups.containsKey(chapter.number)) chapter.number,
      for (final number in groups.keys) if (!labels.containsKey(number)) number,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final number in order)
          Card(
            elevation: 0,
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: ExpansionTile(
              title: m.Text(labels[number] ?? (number == 0 ? widget.pack.title : 'Chapter $number'),
                  textDirection: TextDirection.ltr, textAlign: TextAlign.left,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              children: [for (final i in groups[number]!) _row(i)],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _q.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(widget.pack.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _q,
              onChanged: _filter,
              decoration: InputDecoration(labelText: tr('Filter titles'), suffixIcon: const Icon(Icons.filter_list)),
            ),
          ),
          if (_mixed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SourceFilterChips(
                sources: const ['WikEM', 'CDC', 'NCI', 'Project Tulip', 'Wikipedia'],
                selected: _source,
                onChanged: (v) {
                  _source = v;
                  _filter(_q.text);
                },
              ),
            ),
          if (!searching && !_book)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(value: false, icon: const Icon(Icons.category_outlined, size: 16), label: Text('By type')),
                    ButtonSegment(value: true, icon: const Icon(Icons.sort_by_alpha, size: 16), label: Text('A–Z')),
                  ],
                  selected: {_az},
                  onSelectionChanged: (v) => setState(() => _az = v.first),
                ),
                if (_mixed) ...[
                  FilterChip(
                    label: Text('Concise sources first'),
                    selected: _conciseFirst,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) {
                      _conciseFirst = v;
                      _resort();
                    },
                  ),
                ],
              ]),
            ),
          Expanded(child: _shown.isEmpty ? const SizedBox() : (searching || _az || _source != null) ? _azList() : _topicList()),
        ],
      ),
    );
  }
}

// ================================================================ get / manage courses

class PackManagerScreen extends StatefulWidget {
  const PackManagerScreen({super.key});
  @override
  State<PackManagerScreen> createState() => _PackManagerScreenState();
}

class _PackManagerScreenState extends State<PackManagerScreen> {
  List<CatalogEntry>? _catalog;
  String? _error;
  final Map<String, double> _progress = {};
  bool _all = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _catalog = null;
    });
    try {
      final c = await library.fetchCatalog();
      if (mounted) setState(() => _catalog = c);
    } catch (_) {
      if (mounted) setState(() => _error = tr('Could not reach the course list. Check your internet connection.'));
    }
  }

  Future<void> _install(CatalogEntry e, {bool ask = true}) async {
    if (ask) {
      final go = await allowDownloadNow(context, bytes: e.meta.bytes, images: e.meta.kind == 'images', onWaiting: () {
        if (mounted) setState(() => _progress[e.meta.id] = 0);
      }, cancelled: () => !mounted);
      if (!go || !mounted) {
        if (mounted) setState(() => _progress.remove(e.meta.id));
        return;
      }
    }
    setState(() => _progress[e.meta.id] = 0);
    try {
      await library.install(e, onProgress: (v) {
        if (mounted) setState(() => _progress[e.meta.id] = v);
      });
    } catch (_) {
      if (mounted) snack(context, '${tr('Download failed')}: ${e.meta.title}');
    } finally {
      if (mounted) setState(() => _progress.remove(e.meta.id));
    }
  }

  Future<void> _downloadAll({bool images = false}) async {
    final todo = [
      for (final e in _catalog ?? <CatalogEntry>[])
        if ((e.meta.kind == 'images') == images && (library.pack(e.meta.id) == null || library.hasUpdate(e))) e
    ];
    if (todo.isEmpty) return;
    final mb = todo.fold<int>(0, (a, e) => a + e.meta.bytes);
    final ok = await confirmDialog(context, trp('Download {n} courses ({size})?', {'n': todo.length, 'size': fmtBytes(mb)}), action: tr('Download'));
    if (!ok || !mounted) return;
    final go = await allowDownloadNow(context, bytes: mb, images: images, cancelled: () => !mounted);
    if (!go || !mounted) return;
    setState(() => _all = true);
    for (final e in todo) {
      if (!mounted) return;
      await _install(e, ask: false);
    }
    if (mounted) setState(() => _all = false);
  }

  String _find = '';
  bool _importingLocalBook = false;

  Future<void> _importLocalBook() async {
    setState(() => _importingLocalBook = true);
    try {
      // FileType.any also shows .idx/.imx files on Android document providers.
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
      if (result == null) return;
      final paths = [for (final file in result.files) if (file.path != null) file.path!];
      await library.importLocalBook(paths);
      if (mounted) snack(context, 'Book imported. Available offline in Library.');
    } catch (error) {
      if (mounted) snack(context, 'Local import failed: $error');
    } finally {
      if (mounted) setState(() => _importingLocalBook = false);
    }
  }

  Future<void> _importFiles() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['txt', 'md', 'markdown', 'text']);
    if (r == null) return;
    final paths = [for (final f in r.files) if (f.path != null) f.path!];
    final n = await library.importTextFiles(paths);
    if (mounted) snack(context, trp('{n} files added to My files.', {'n': n}));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final cat = _catalog;
        final wiki = [for (final e in cat ?? <CatalogEntry>[]) if (e.meta.kind == 'wiki') e];
        final other = [for (final e in cat ?? <CatalogEntry>[]) if (e.meta.kind != 'wiki' && e.meta.kind != 'images') e];
        final images = [for (final e in cat ?? <CatalogEntry>[]) if (e.meta.kind == 'images') e];
        final totalMb = wiki.fold<int>(0, (a, e) => a + e.meta.bytes);
        Widget row(CatalogEntry e) {
          final installed = library.pack(e.meta.id);
          final prog = _progress[e.meta.id];
          final upd = library.hasUpdate(e);
          final cs = theme.colorScheme;
          Widget action() {
            if (prog != null) {
              return SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, value: prog <= 0 ? null : prog));
            }
            if (installed == null) {
              return FilledButton.tonal(
                key: Key('dl_${e.meta.id}'),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _install(e),
                child: Text('Download'),
              );
            }
            if (upd) {
              return FilledButton(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _install(e),
                child: Text('Update'),
              );
            }
            return Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
              const SizedBox(width: 4),
              Text('Installed', style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              IconButton(
                tooltip: tr('Delete'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  if (await confirmDialog(context, 'Delete this course from the phone?')) await library.remove(e.meta.id);
                },
              ),
            ]);
          }

          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.meta.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${installed?.count ?? e.meta.count} ${tr('articles')} • ${fmtBytes(e.meta.bytes)}'),
            trailing: action(),
          );
        }

        final essentials = [for (final e in cat ?? <CatalogEntry>[]) if (e.meta.id == kEssentialsPackId) e];
        final q = _find.trim().toLowerCase();
        final wikiShown = [for (final e in wiki) if (e.meta.id != kEssentialsPackId && (q.isEmpty || e.meta.title.toLowerCase().contains(q))) e];

        return Scaffold(
          appBar: AppBar(title: Text('Courses and library')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (_error != null)
                AppCard(
                  child: ListTile(
                    leading: const Icon(Icons.wifi_off),
                    title: Text(_error!),
                    trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
                  ),
                ),
              if (cat == null && _error == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (cat != null) ...[
                if (essentials.isNotEmpty)
                  AppCard(
                    color: theme.colorScheme.primaryContainer.withAlpha(110),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.bolt),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Start here', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                        ]),
                        const SizedBox(height: 6),
                        Text('Short, practical summaries for the ward. Works offline. Download this first.', style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        row(essentials.first),
                      ]),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
                  child: Text('Courses by specialty', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TextField(
                    key: const Key('dl_find'),
                    onChanged: (v) => setState(() => _find = v),
                    decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tr('Find a course')),
                  ),
                ),
                for (final e in wikiShown) row(e),
                if (wikiShown.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('Nothing found')),
                Fold(
                  id: 'pk_more',
                  title: tr('More downloads'),
                  subtitle: tr('Everything at once, patient information, pictures'),
                  icon: Icons.tune,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.tonalIcon(
                        onPressed: _all ? null : _downloadAll,
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: Text(trp('Download all ({size})', {'size': fmtBytes(totalMb)})),
                      ),
                    ),
                    for (final e in other) if (e.meta.id != kEssentialsPackId) row(e),
                    if (images.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('Pictures for the articles (optional). Each shows its author and license.', style: theme.textTheme.bodySmall),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _all ? null : () => _downloadAll(images: true),
                          icon: const Icon(Icons.download_for_offline_outlined),
                          label: Text(trp('Download all ({size})', {'size': fmtBytes(images.fold<int>(0, (a, e) => a + e.meta.bytes))})),
                        ),
                      ),
                      for (final e in images) row(e),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Fold(
                id: 'pk_import',
                title: tr('Import my own files'),
                icon: Icons.upload_file_outlined,
                children: [
              AppCard(
                child: ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const m.Text('Import local book pack'),
                  subtitle: const m.Text('Select the ZIP file you were given (or the five files together).'),
                  onTap: _importingLocalBook ? null : _importLocalBook,
                ),
              ),
              AppCard(
                child: ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: Text('Import my own files'),
                  subtitle: Text('Text or Markdown notes become articles in "My files". They stay on this phone.'),
                  onTap: _importFiles,
                ),
              ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ================================================================ online library (in-app browser)

class Site {
  final String name;
  final String url;
  final String about;
  const Site(this.name, this.url, this.about);
}

class SiteGroup {
  final String title;
  final List<Site> sites;
  const SiteGroup(this.title, this.sites);
}

const List<SiteGroup> kSiteGroups = [
  SiteGroup('Internship and clinical practice', [
    Site('Geeky Medics', 'https://geekymedics.com/', 'Clinical skills, OSCE and procedures'),
    Site('Merck Manual (professional)', 'https://www.msdmanuals.com/professional', 'Short clinical topics'),
    Site('Medscape Reference', 'https://emedicine.medscape.com/', 'Clinical overviews'),
    Site('Mayo Clinic', 'https://www.mayoclinic.org/diseases-conditions', 'Diseases and conditions'),
    Site('NHS conditions', 'https://www.nhs.uk/conditions/', 'Plain-language conditions A to Z'),
    Site('StatPearls', 'https://www.ncbi.nlm.nih.gov/books/NBK430685/', 'Clinical articles (NCBI Bookshelf)'),
  ]),
  SiteGroup('Board preparation', [
    Site('Orthobullets', 'https://www.orthobullets.com/', 'Orthopedics: short topics and questions'),
    Site('Medbullets', 'https://step2.medbullets.com/', 'Concise topics for exams'),
    Site('AMBOSS', 'https://www.amboss.com/', 'Needs your own subscription'),
  ]),
  SiteGroup('Emergency and critical care', [
    Site('Life in the Fast Lane (LITFL)', 'https://litfl.com/', 'ECG, toxicology, critical care'),
    Site('EMCrit', 'https://emcrit.org/', 'Emergency and critical care'),
    Site('First10EM', 'https://first10em.com/', 'Evidence-based emergency medicine'),
    Site('WikEM', 'https://wikem.org/wiki/Main_Page', 'Emergency medicine in short points'),
  ]),
  SiteGroup('Imaging', [
    Site('Radiopaedia', 'https://radiopaedia.org/', 'Radiology articles and cases'),
  ]),
  SiteGroup('Guidelines', [
    Site('WHO guidelines', 'https://www.who.int/publications/guidelines', 'World Health Organization'),
    Site('CDC', 'https://www.cdc.gov/', 'Infectious disease and public health'),
    Site('NICE', 'https://www.nice.org.uk/guidance', 'UK clinical guidelines'),
  ]),
  SiteGroup('Drugs', [
    Site('DailyMed', 'https://dailymed.nlm.nih.gov/dailymed/', 'Official drug labels'),
  ]),
  SiteGroup('Reading and research', [
    Site('MedlinePlus', 'https://medlineplus.gov/', 'Patient-friendly health information'),
    Site('Wikipedia Medicine', 'https://en.wikipedia.org/wiki/Portal:Medicine', 'Wikipedia medical portal'),
    Site('PubMed', 'https://pubmed.ncbi.nlm.nih.gov/', 'Research articles'),
    Site('Cochrane Library', 'https://www.cochranelibrary.com/', 'Systematic reviews'),
  ]),
];

/// Pages the in-app browser may show. Anything else is blocked, and nothing from
/// the user's cases is ever passed to the page.
const List<String> kAllowedHosts = [
  'ncbi.nlm.nih.gov',
  'nlm.nih.gov',
  'medlineplus.gov',
  'wikipedia.org',
  'wikem.org',
  'who.int',
  'cdc.gov',
  'nice.org.uk',
  'cochranelibrary.com',
  'cochrane.org',
  'wikimedia.org',
  'wiley.com',
  'amboss.com',
  'geekymedics.com',
  'msdmanuals.com',
  'medscape.com',
  'mayoclinic.org',
  'nhs.uk',
  'orthobullets.com',
  'medbullets.com',
  'litfl.com',
  'emcrit.org',
  'first10em.com',
  'radiopaedia.org',
  'nccn.org',
  'esmo.org',
  'jamanetwork.com',
  'nejm.org',
  'thelancet.com',
  'bmj.com',
  'rcog.org.uk',
  'sign.ac.uk',
  'nih.gov',
  'ahrq.gov',
  'ada.org',
  'diabetesjournals.org',
  'acog.org',
  'aap.org',
  'sccm.org',
  'ginasthma.org',
  'goldcopd.org',
  'kdigo.org',
  'idsociety.org',
  'escardio.org',
  'acc.org',
  'ahajournals.org',
  'heart.org',
];

bool hostAllowed(String host) {
  final h = host.toLowerCase();
  return kAllowedHosts.any((a) => h == a || h.endsWith('.$a'));
}

class BrowserScreen extends StatefulWidget {
  final String title;
  final String url;
  const BrowserScreen({super.key, required this.title, required this.url});
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  WebViewController? _c;
  int _progress = 0;
  String _blocked = '';
  String _current = '';

  @override
  void initState() {
    super.initState();
    final uri = Uri.parse(widget.url);
    if (uri.scheme != 'https' || !hostAllowed(uri.host)) {
      _blocked = widget.url;
      return;
    }
    _current = widget.url;
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        onUrlChange: (c) => _current = c.url ?? _current,
        onNavigationRequest: (r) {
          final u = Uri.tryParse(r.url);
          if (u != null && u.scheme == 'https' && hostAllowed(u.host)) return NavigationDecision.navigate;
          if (mounted) setState(() => _blocked = r.url);
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(uri);
  }

  Future<void> _clear() async {
    await _c?.clearCache();
    await _c?.clearLocalStorage();
    await WebViewCookieManager().clearCookies();
    if (mounted) snack(context, tr('Browsing data cleared.'));
  }

  Future<void> _saveRef() async {
    final title = await _c?.getTitle() ?? widget.title;
    await store.upsertExtra('evidence', {
      'id': newId('ev'),
      'title': title,
      'source': Uri.tryParse(_current)?.host ?? '',
      'year': '${DateTime.now().year}',
      'level': 'Not sure',
      'link': _current,
      'topic': widget.title,
      'note': '',
      'saved': todayStr(),
      'reviewed': todayStr(),
    });
    if (mounted) snack(context, tr('Saved to your references.'));
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (c != null) IconButton(tooltip: tr('Back'), icon: const Icon(Icons.arrow_back), onPressed: () async => await c.canGoBack() ? c.goBack() : Navigator.pop(context)),
          if (c != null) IconButton(tooltip: tr('Save to my references'), icon: const Icon(Icons.bookmark_add_outlined), onPressed: _saveRef),
          if (c != null)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'clear' ? _clear() : c.reload(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'reload', child: Text('Reload')),
                PopupMenuItem(value: 'clear', child: Text('Clear browsing data')),
              ],
            ),
        ],
        bottom: c != null && _progress < 100 ? PreferredSize(preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(value: _progress / 100)) : null,
      ),
      body: Column(
        children: [
          if (_blocked.isNotEmpty)
            MaterialBanner(
              content: Text('This page is outside the trusted list, so it was not opened.'),
              actions: [TextButton(onPressed: () => setState(() => _blocked = ''), child: Text('OK'))],
            ),
          Expanded(child: c == null ? const SizedBox() : WebViewWidget(controller: c)),
        ],
      ),
    );
  }
}

// ================================================================ medical terms

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});
  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final items = lookupTerms(_q);
    return Scaffold(
      appBar: AppBar(title: Text('Medical terms')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(labelText: tr('English or Arabic'), suffixIcon: const Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: items.length,
              itemBuilder: (context, i) => ListTile(
                dense: true,
                title: Directionality(textDirection: TextDirection.ltr, child: Text(items[i].key, style: const TextStyle(fontWeight: FontWeight.w700))),
                subtitle: Text(items[i].value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ================================================================ library & AI settings

/// "Library & AI settings": every reading, study-sheet, search, download and AI option in one page with foldable
/// sections. Every control writes through store.setLook / AiPrefs / AiStore and the page is redrawn from the stores,
/// so a change shows immediately (no section is a const subtree: a const child is never rebuilt by its parent).
class LibrarySettingsScreen extends StatefulWidget {
  /// Tests: replaces the reading of the phone for the "Suggest settings" card.
  final Future<TuneCtx> Function(BuildContext)? tuneGather;
  const LibrarySettingsScreen({super.key, this.tuneGather});
  @override
  State<LibrarySettingsScreen> createState() => _LibrarySettingsScreenState();
}

class _LibrarySettingsScreenState extends State<LibrarySettingsScreen> {
  int _cache = 0;
  int _gen = 0;
  final GlobalKey _packsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    library.imageCacheBytes().then((v) {
      if (mounted) setState(() => _cache = v);
    });
  }

  /// A suggestion points at a section: open it (saved fold state) and bring it into view.
  void _openFor(String itemId) {
    final fold = (itemId.startsWith('pack_') || itemId == 'storage_low' || itemId == 'cache_big') ? 'ls_packs' : null;
    if (fold == null) return;
    final fs = store.settings['folds'];
    final map = fs is Map ? Map<String, dynamic>.from(fs) : <String, dynamic>{};
    map[fold] = true;
    store.settings['folds'] = map;
    store.saveSettings();
    setState(() => _gen++);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _packsKey.currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250), alignment: 0.05);
    });
  }

  Key _fk(String id) => ValueKey('${id}_$_gen');

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([library, store, AiStore.changes]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text('Library & AI settings')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TunerCard(onOpen: _openFor, gather: widget.tuneGather),
              _reading(context),
              _sheet(context),
              _images(context),
              _search(context),
              KeyedSubtree(key: _packsKey, child: _packs(context)),
              AiSettingsBody(foldGen: _gen),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- Reading

  Widget _reading(BuildContext context) {
    final theme = Theme.of(context);
    final scale = store.libFontScale;
    final bold = store.libBold;
    return Fold(
      key: _fk('ls_reading'),
      id: 'ls_reading',
      title: tr('Reading'),
      icon: Icons.text_fields,
      initiallyOpen: true,
      children: [
        OptSlider(
          title: 'Article text size',
          help: 'Size of the text inside library articles.',
          info: 'Changes only the text of library articles and study sheets, not the whole app. The phone text size (Android settings) is applied on top of it.',
          value: scale,
          min: 0.85,
          max: 1.5,
          divisions: 13,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => store.setLook('libFont', v),
        ),
        OptSwitch(
          title: 'Larger and bolder text',
          help: 'A little bigger and heavier, easier in bright light.',
          info: 'Makes article text about 10% larger and a bit heavier. It helps when reading on a phone in bright light or during a shift.',
          value: bold,
          onChanged: (v) => store.setLook('libBold', v),
        ),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            key: const Key('reading_preview'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: theme.colorScheme.outlineVariant)),
            child: m.Text('Osteoarthritis is a degenerative joint disease.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * scale * (bold ? 1.1 : 1.0),
                    fontWeight: bold ? FontWeight.w600 : null,
                    height: 1.55)),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- Study sheet

  Widget _sheet(BuildContext context) {
    final style = store.libSheetStyle;
    final marks = store.settings['libMarks'] != false;
    return Fold(
      key: _fk('ls_sheet'),
      id: 'ls_sheet',
      title: tr('Study sheet'),
      icon: Icons.auto_awesome_outlined,
      initiallyOpen: true,
      children: [
        OptChoice<int>(
          title: 'Sheet style',
          help: 'Plain: text only. Light: callout cards. Rich: cards, icons and colour.',
          info: 'The study sheet is the structured view of an article. Plain keeps simple text. Light adds coloured cards for doses and red flags. Rich adds more colour, icons and highlighted key sentences. The preview below changes as you choose.',
          segmented: true,
          value: style,
          items: [OptItem(0, tr('Plain')), OptItem(1, tr('Light')), OptItem(2, tr('Rich'))],
          onChanged: (v) => store.setLook('libSheetStyle', v),
        ),
        const SizedBox(height: 8),
        _SheetPreview(style: style, marks: marks, bold: store.libBold, scale: store.libFontScale),
        OptSwitch(
          title: 'Highlight doses and red flags',
          help: 'Callout cards and a summary for dose lines and warning signs (Light and Rich styles).',
          info: 'Finds lines with drug doses and warning signs in the article and shows them as coloured cards, with a short summary at the top of the sheet. Works in the Light and Rich styles only. The detection is automatic, so always read the full text for decisions.',
          value: marks,
          onChanged: (v) => store.setLook('libMarks', v),
        ),
        OptSwitch(
          title: 'Combined view of several sources',
          help: 'When the same condition is in more than one installed course, show them together.',
          info: 'If WikEM, Wikipedia and another course all have an article about the same condition, the sheet puts them together in one view with the source named on each part, instead of making you open each one.',
          value: store.libCombined,
          onChanged: (v) => store.setLook('libCombined', v),
        ),
        OptSwitch(
          title: 'Show captions',
          help: 'Text under pictures and above tables.',
          info: 'Shows the caption under each picture and above each table. Turn it off for a cleaner page when you only need the picture or the table.',
          value: store.libCaptions,
          onChanged: (v) => store.setLook('libCaptions', v),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- Images & tables

  Widget _images(BuildContext context) {
    return Fold(
      key: _fk('ls_images'),
      id: 'ls_images',
      title: tr('Images & tables'),
      icon: Icons.image_outlined,
      initiallyOpen: true,
      children: [
        OptSwitch(
          title: 'Show downloaded images',
          help: 'Pictures from the picture packs you installed.',
          info: 'Shows the pictures that come with your downloaded picture packs inside articles. Turn it off to read faster or save battery.',
          value: store.libShowImages,
          onChanged: (v) => store.setLook('libImages', v),
        ),
        OptSwitch(
          title: 'Show tables',
          help: 'Tables from the articles, in the full article view.',
          info: 'Shows the tables of an article in the full article view. Wide tables scroll sideways and open full screen when you tap them.',
          value: store.libShowTables,
          onChanged: (v) => store.setLook('libTables', v),
        ),
        OptSwitch(
          title: 'Load pictures from the internet',
          help: 'Only the article title is sent to Wikipedia. Pictures are kept on the phone afterwards.',
          info: 'When an article has no picture on the phone, the app can look for one on Wikipedia using only the article title. The picture is saved on the phone, so it works offline next time. Turn it off to stay fully offline.',
          value: store.libOnlineImages,
          onChanged: (v) => store.setLook('libOnline', v),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text('Clear downloaded pictures cache'),
          subtitle: m.Text(fmtBytes(_cache)),
          onTap: () async {
            await library.clearImageCache();
            final v = await library.imageCacheBytes();
            if (mounted) setState(() => _cache = v);
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- Search

  Widget _search(BuildContext context) {
    return Fold(
      key: _fk('ls_search'),
      id: 'ls_search',
      title: tr('Search'),
      icon: Icons.manage_search,
      children: [
        OptSwitch(
          title: 'Search inside articles',
          help: library.ftsBuilding
              ? trp('Preparing text search: {a} of {b} courses', {'a': library.ftsDone, 'b': library.ftsTotal})
              : trp('{a} of {b} courses ready for text search', {'a': library.ftsIndexed, 'b': library.textPacks.length}),
          info: 'Besides titles, the search also looks inside the article text. The first time it prepares an index on the phone, which takes a little while and some storage. Everything stays on the phone.',
          value: store.libBodySearch,
          onChanged: (v) {
            store.setLook('libBody', v);
            if (v) library.ensureFts().then((_) {}, onError: (_) {});
          },
        ),
        OptSwitch(
          title: 'Concise sources first',
          help: 'Short, structured sources (WikEM, Tulip, CDC) before long articles.',
          info: 'Puts short, structured sources at the top of the results, so you reach the practical summary before the long encyclopedia article.',
          value: store.libConcise,
          onChanged: (v) => store.setLook('libConcise', v),
        ),
        OptSwitch(
          title: 'Suggest other search words',
          help: 'When a search finds little, the AI can suggest synonyms. Needs AI and internet.',
          info: 'If a search finds few results, the AI can suggest other words, such as the full name of an abbreviation. Only the short search words are sent, never your cases. It does nothing when AI is off or you are offline.',
          value: AiPrefs.queryExpansion,
          onChanged: (v) => AiPrefs.queryExpansion = v,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- Packs & downloads

  Widget _packs(BuildContext context) {
    return Fold(
      key: _fk('ls_packs'),
      id: 'ls_packs',
      title: tr('Packs & downloads'),
      subtitle: fmtBytes(library.totalBytes),
      icon: Icons.storage_outlined,
      children: [
        OptSwitch(
          title: 'Download on Wi-Fi only',
          help: 'Ask before big downloads (pictures, courses over 20 MB) on mobile data.',
          info: 'Protects your mobile data. With this on, the app asks before downloading picture packs or courses larger than 20 MB when you are not on Wi-Fi.',
          value: libWifiOnly(),
          onChanged: (v) async {
            await setLibWifiOnly(v);
            if (mounted) setState(() {});
          },
        ),
        OptGroupTitle(tr('Storage used by each pack')),
        for (final p in library.packs)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(p.kind == 'images' ? Icons.image_outlined : Icons.article_outlined),
            title: Text(p.title),
            subtitle: Text('${p.count} • ${fmtBytes(p.bytes)} • ${p.date}'),
            trailing: p.id == 'medlineplus'
                ? null
                : IconButton(
                    tooltip: tr('Delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirmDialog(context, 'Delete this course from the phone?')) await library.remove(p.id);
                    },
                  ),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.system_update_alt),
          title: Text('Check for course updates'),
          onTap: () async {
            try {
              final cat = await library.fetchCatalog();
              final n = cat.where(library.hasUpdate).length;
              if (context.mounted) snack(context, n == 0 ? tr('All courses are up to date.') : trp('{n} courses have updates.', {'n': n}));
            } catch (_) {
              if (context.mounted) snack(context, tr('Could not reach the course list. Check your internet connection.'));
            }
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.download_for_offline_outlined),
          title: Text('Courses and library'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PackManagerScreen())),
        ),
      ],
    );
  }
}

/// Live preview of the study sheet: redrawn from the chosen style and toggles (Plain shows no cards, Light cards, Rich more).
class _SheetPreview extends StatelessWidget {
  final int style;
  final bool marks;
  final bool bold;
  final double scale;
  const _SheetPreview({required this.style, required this.marks, required this.bold, required this.scale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = SheetLook.of(context, style: style, bold: bold, scale: scale, marks: marks);
    final blocks = <SBlock>[
      SBlock(BKind.sub, 0, 'Anaphylaxis'),
      SBlock(BKind.bullet, 0, 'Treatment: epinephrine 0.3-0.5 mg IM', tag: SheetTag.dose, ranges: const [SRange(0, 9, 2), SRange(11, 22, 1)]),
      SBlock(BKind.bullet, 0, 'Do not delay treatment while waiting for results', tag: SheetTag.redFlag),
      SBlock(BKind.bullet, 0, 'Most common trigger: food, drugs and insect stings', tag: SheetTag.highYield),
    ];
    final desc = style == 0 ? 'Plain text, no colours.' : (style == 1 ? 'Light: callout cards for doses and red flags.' : 'Rich: cards, icons and highlighted key points.');
    return Container(
      key: const Key('sheet_preview'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: theme.colorScheme.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final b in blocks) SheetBlockView(b, look),
        Text(desc, key: Key('sheet_preview_desc_$style'), style: theme.textTheme.bodySmall),
      ]),
    );
  }
}
