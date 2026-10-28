import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:flutter/rendering.dart' show SelectedContent;

import 'data.dart';
import 'book_text.dart';
import 'i18n.dart';
import 'lib_glance.dart';
import 'lib_sheet.dart';
import 'lib_text.dart';
import 'lib_user.dart';
import 'library.dart';
import 'screens_ai_library.dart';
import 'ai/ai_api.dart' show Ai;
import 'screens_cases.dart';
import 'screens_library.dart';
import 'screens_quiz.dart';
import 'sheet_widgets.dart';
import 'ui.dart';
import 'widgets.dart';

/// Reader for one library article: picture, definition, jump chips, foldable sections,
/// your own notes, related articles and your cases about the same subject.
class ArticleScreen extends StatefulWidget {
  final String packId;
  final int index;
  /// Opens the full article, expands the section that contains this sentence, scrolls to it and highlights it briefly
  /// (quiz "Open the article at this part", citations).
  final String? focusQuote;
  const ArticleScreen({super.key, required this.packId, required this.index, this.focusQuote});
  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

/// One section card: from the study sheet (canonical order) or, in 'Original text', straight from the article.
/// Where the text comes from and how old it is, from the article's own fields only.
class ArticleProvenance {
  final String edited; // 'YYYY-MM-DD' of the source's last edit ('' when the article has no date)
  final bool outdated; // the date is more than 5 years ago
  final bool us; // CDC, or text full of United States agencies and guideline bodies
  const ArticleProvenance({this.edited = '', this.outdated = false, this.us = false});
  bool get any => edited.isNotEmpty || us;
}

final RegExp _usMarks = RegExp(r'\b(FDA|AHA|ACC|ACIP|USPSTF|CDC|NIH|Medicare|Medicaid|United States|U\.S\.|American (?:Heart|College|Academy|Thoracic|Society|Diabetes)|Joint Commission)\b');

ArticleProvenance articleProvenance(LibArticle a, String label, {DateTime? now}) {
  var edited = '', outdated = false;
  final d = a.date.length >= 10 ? DateTime.tryParse(a.date.substring(0, 10)) : null;
  if (d != null) {
    edited = a.date.substring(0, 10);
    outdated = (now ?? DateTime.now()).difference(d).inDays > 5 * 365;
  }
  var us = label == 'CDC';
  if (!us) {
    // enough different US agencies / bodies, and often (a long encyclopedia article that names the CDC once is not "US-centric")
    final seen = <String>{};
    var n = 0, chars = 0;
    for (final s in a.sections) {
      chars += s.text.length;
      for (final m in _usMarks.allMatches(s.text)) {
        seen.add(m.group(0)!);
        n++;
      }
    }
    us = seen.length >= 3 && n * 10000 >= chars * 6;
  }
  return ArticleProvenance(edited: edited, outdated: outdated, us: us);
}

class _Sec {
  final String title;
  final Canon canon;
  final SheetSec? sheet;
  final LibSection? raw;
  final Set<String> heads;
  const _Sec(this.title, this.canon, this.heads, {this.sheet, this.raw});
}

class _ArticleScreenState extends State<ArticleScreen> {
  LibArticle? _a;
  bool _missing = false;
  final _scroll = ScrollController();
  final Set<int> _open = {};
  final Map<int, GlobalKey> _keys = {};
  List<LibImage> _imgList = const [];
  List<LibHit> _related = const [];
  late final TextEditingController _note = TextEditingController();
  Timer? _noteTimer;
  String _selected = '';
  List<_Sec> _secs = const [];
  Sheet? _single;
  Sheet? _comb;
  Sheet? _sheet;
  List<SheetLink> _sibs = const [];
  bool _useCombined = true;
  bool _original = false;
  bool get _book => library.pack(widget.packId)?.kind == 'book';
  ArticleProvenance _prov = const ArticleProvenance();
  bool _forceFull = false; // focusQuote: show the full article even when the quick view is the saved choice
  String _hiQuote = ''; // normalised quote being highlighted ('' = none)
  int _hiSec = -1;
  bool _focusDone = false;
  Timer? _hiTimer;
  Set<LibTable> _inDoseCard = const {}; // dose charts shown in the dose card (not repeated in their section)

  @override
  void initState() {
    super.initState();
    final fq = widget.focusQuote == null ? '' : normQuote(widget.focusQuote!);
    if (fq.isNotEmpty) {
      _forceFull = true;
      _hiQuote = fq;
    }
    library.read(widget.packId, widget.index).then((a) {
      if (!mounted) return;
      if (a == null) {
        setState(() => _missing = true);
        return;
      }
      noteRecent(widget.packId, a.title);
      _note.text = noteFor(widget.packId, a.title);
      final p = library.pack(widget.packId);
      if (_book) { _original = true; _forceFull = true; }
      _scroll.addListener(_onScroll);
      final label = sheetLabel(widget.packId, a.title, source: a.source, packKind: p?.kind ?? '', packTitle: p?.title ?? '');
      _prov = articleProvenance(a, label);
      _single = sheetFor('s|${widget.packId}|${widget.index}', [SheetSrc(label, a)], hideCaptions: store.libCaptions);
      setState(() {
        _a = a;
        _applyMode();
        _restorePos();
        _loadImages(a.title).then((l) {
          if (mounted) setState(() => _imgList = l);
        });
      });
      if (!_book && store.libCombined) _loadSiblings(a, label);
      library.related(widget.packId, widget.index).then((r) {
        if (mounted) setState(() => _related = r);
      });
    });
  }

  /// Picks the sheet (single or combined) and the section cards for the current mode.
  void _applyMode() {
    final a = _a;
    if (a == null) return;
    _sheet = (_useCombined && _comb != null) ? _comb : _single;
    if (_original) {
      _secs = [
        for (var i = 1; i < a.sections.length; i++)
          _Sec(a.sections[i].heading.isEmpty ? tr('More') : a.sections[i].heading, canonOf(a.sections[i].heading), {a.sections[i].heading.trim().toLowerCase()}, raw: a.sections[i]),
      ];
    } else {
      _secs = [for (final s in _sheet!.sections) _Sec(s.title, s.canon, {for (final h in s.headings) h.trim().toLowerCase()}, sheet: s)];
    }
    _open.clear();
    _keys.clear();
    if (_hiQuote.isNotEmpty) _locateFocus();
  }

  /// Finds the section holding the focus sentence (normalised substring), opens it, scrolls to it and flashes it.
  void _locateFocus() {
    final a = _a;
    if (a == null || _hiQuote.isEmpty) return;
    var q = _hiQuote;
    int find(String qq) {
      for (var i = 0; i < _secs.length; i++) {
        final sc = _secs[i];
        final String text;
        if (sc.raw != null) {
          text = sc.raw!.text;
        } else {
          final b = StringBuffer();
          for (final p in sc.sheet!.parts) {
            for (final k in p.blocks) {
              b.write('${k.text} ');
            }
            for (final t in p.tables) {
              b.write('${t.caption} ');
              for (final r in t.rows) {
                b.write('${r.join(' ')} ');
              }
            }
          }
          text = b.toString();
        }
        if (normQuote(text).contains(qq)) return i;
      }
      // the original article section it belongs to
      for (final rs in a.sections) {
        if (normQuote(rs.text).contains(qq)) {
          final h = rs.heading.trim().toLowerCase();
          for (var i = 0; i < _secs.length; i++) {
            if (_secs[i].heads.contains(h)) return i;
          }
        }
      }
      return -1;
    }

    var idx = find(q);
    if (idx < 0) {
      final w = q.split(' ');
      if (w.length > 8) {
        q = w.take(8).join(' ');
        idx = find(q);
        if (idx >= 0) _hiQuote = q;
      }
    }
    if (idx < 0) return;
    _open.add(idx);
    _hiSec = idx;
    if (_focusDone) return;
    _focusDone = true;
    _hiTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      // the cards below the screen are not built yet: walk down until the target card exists
      for (var k = 0; k < 40 && mounted; k++) {
        final c = _keys[idx]?.currentContext;
        if (c != null) {
          await Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 380), curve: Curves.easeOut, alignment: 0.08);
          return;
        }
        if (!_scroll.hasClients) break;
        final pos = _scroll.position;
        if (pos.pixels >= pos.maxScrollExtent - 1) break;
        _scroll.jumpTo((pos.pixels + pos.viewportDimension * 0.9).clamp(0.0, pos.maxScrollExtent));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    _hiTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _hiQuote = '';
          _hiSec = -1;
        });
      }
    });
  }

  /// Other installed articles about the same condition (WikEM, Tulip, CDC, NCI, Wikipedia ...): builds the combined sheet.
  Future<void> _loadSiblings(LibArticle a, String label) async {
    try {
      final sib = await SheetIndex.siblings(library, widget.packId, a.title);
      if (!mounted || sib.isEmpty) return;
      final srcs = <SheetSrc>[SheetSrc(label, a)];
      final used = <SheetLink>[];
      for (final l in sib) {
        final x = await library.read(l.packId, l.index);
        if (x != null) {
          srcs.add(SheetSrc(l.label, x));
          used.add(l);
        }
      }
      if (!mounted || srcs.length < 2) return;
      final comb = sheetFor('c|${widget.packId}|${widget.index}|${used.map((e) => '${e.packId}:${e.index}').join(',')}', srcs, hideCaptions: store.libCaptions);
      setState(() {
        _sibs = used;
        _comb = comb;
        _applyMode();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _posTimer?.cancel();
    _savePos();
    _noteTimer?.cancel();
    _hiTimer?.cancel();
    _scroll.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<List<LibImage>> _loadImages(String title) async {
    // Book pictures use the same local packs as Wikipedia pictures.
    final kind = library.pack(widget.packId)?.kind;
    if (kind != 'wiki' && kind != 'book') return const [];
    if (store.libShowImages) {
      final l = await library.imagesFor(title, packId: kind == 'book' ? widget.packId : null);
      if (l.isNotEmpty) return l;
    }
    // Books must never request unrelated Wikipedia pictures.
    if (kind == 'wiki' && store.libOnlineImages) return library.onlineImagesFor(title);
    return const [];
  }

  bool get _quick => !_forceFull && store.settings['libQuick'] != false;

  /// Tables of a section in the full article (quick view lists them all after the key points); needs 'Show tables' on.
  List<Widget> _tablesOf(LibSection s, double scale) {
    if (_quick || !store.libShowTables || s.tables.isEmpty) return const [];  // quick view lists all tables after the key points
    return [for (final t in s.tables) if (!_inDoseCard.contains(t)) _TableCard(table: t, scale: scale)];
  }

  List<Widget> _tablesList(List<LibTable> l, double scale) {
    if (_quick || !store.libShowTables || l.isEmpty) return const [];
    return [for (final t in l) if (!_inDoseCard.contains(t)) _TableCard(table: t, scale: scale)];
  }

  Widget _bodyOf(String text, double scale) => _book ? BookBody(text, scale: scale, focus: _hiQuote) : _Body(text, scale: scale, focus: _hiQuote);

  // ---- where you stopped reading in a book: the scroll place and the open sections
  String get _posKey => '${widget.packId}|${widget.index}';
  Timer? _posTimer;

  void _savePos() {
    if (!_book || _a == null || !_scroll.hasClients) return;
    final m = <String, dynamic>{if (store.settings['bookPos'] is Map) ...Map<String, dynamic>.from(store.settings['bookPos'] as Map)};
    m[_posKey] = {'p': _scroll.position.pixels.round(), 'o': _open.toList()..sort()};
    // keep the list short: the 60 most recent chapters
    if (m.length > 60) m.remove(m.keys.first);
    store.settings['bookPos'] = m;
    store.saveSettings();
  }

  void _onScroll() {
    if (!_book) return;
    _posTimer?.cancel();
    _posTimer = Timer(const Duration(milliseconds: 700), _savePos);
  }

  void _restorePos() {
    if (!_book || _hiQuote.isNotEmpty) return;
    final saved = store.settings['bookPos'];
    final v = saved is Map ? saved[_posKey] : null;
    if (v is! Map) return;
    final px = (v['p'] as num?)?.toDouble() ?? 0;
    for (final o in (v['o'] as List? ?? const [])) {
      if (o is int && o >= 0 && o < _secs.length) _open.add(o);
    }
    if (px < 40) return;
    var tries = 0;
    void go() {
      if (!mounted || tries++ > 6) return;
      if (_scroll.hasClients && _scroll.position.maxScrollExtent >= px - 1) {
        _scroll.jumpTo(px.clamp(0.0, _scroll.position.maxScrollExtent));
      } else if (_scroll.hasClients && tries > 2) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => go());
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => go());
  }

  /// The contents of the chapter and a search inside it: tapping a section opens it, scrolls to it and marks the match.
  Future<void> _openOutline() async {
    final pick = await showModalBottomSheet<(int, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _OutlineSheet(secs: [for (final x in _secs) (x.title, x.raw?.text ?? '')], open: _open),
    );
    if (pick == null || !mounted) return;
    final (i, q) = pick;
    if (q.isNotEmpty) {
      _hiTimer?.cancel();
      setState(() {
        _hiQuote = normQuote(q);
        _hiSec = i;
      });
      _hiTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) {
          setState(() {
            _hiQuote = '';
            _hiSec = -1;
          });
        }
      });
    }
    _jump(i);
  }

  void _jump(int secIndex) {
    setState(() => _open.add(secIndex));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keys[secIndex]?.currentContext;
      if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 320), curve: Curves.easeOut, alignment: 0.04);
    });
  }

  void _onNote(String v) {
    _noteTimer?.cancel();
    _noteTimer = Timer(const Duration(milliseconds: 600), () => saveNote(widget.packId, _a!.title, v));
  }

  Future<void> _addDefinitionCard(LibArticle a) async {
    final lead = sentences(a.sections.first.text).take(2).join(' ');
    final ok = await addLibraryCard(
      front: '${tr('What is')} ${a.title}?',
      back: lead,
      source: a.title,
      packId: widget.packId,
      title: a.title,
    );
    if (mounted) snack(context, ok ? tr('Added to your review cards.') : tr('Already in your review cards.'));
  }

  Future<void> _saveSelection(LibArticle a, {required bool asPearl}) async {
    final t = _selected.trim();
    if (t.isEmpty) return;
    if (asPearl) {
      await store.upsertExtra('pearls', {'id': newId('pl'), 'date': todayStr(), 'text': t, 'topic': a.title});
      if (mounted) snack(context, tr('Saved as a pearl.'));
    } else {
      final ok = await addLibraryCard(
        front: '${a.title}\n${tr('What do you remember about this?')}',
        back: t,
        source: a.title,
        packId: widget.packId,
        title: a.title,
      );
      if (mounted) snack(context, ok ? tr('Added to your review cards.') : tr('Already in your review cards.'));
    }
  }

  Widget _menuFor(BuildContext ctx, SelectableRegionState state, LibArticle a) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        ...state.contextMenuButtonItems,
        ContextMenuButtonItem(
          label: tr('Save as pearl'),
          onPressed: () {
            ContextMenuController.removeAny();
            _saveSelection(a, asPearl: true);
          },
        ),
        if (Ai.enabled)
          ContextMenuButtonItem(
            label: tr('Explain with AI'),
            onPressed: () {
              final sel = _selected;
              ContextMenuController.removeAny();
              showArticleAiTools(context, widget.packId, widget.index, a, selected: sel);
            },
          ),
        ContextMenuButtonItem(
          label: tr('Add to review'),
          onPressed: () {
            ContextMenuController.removeAny();
            _saveSelection(a, asPearl: false);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = _a;
    final p = library.pack(widget.packId);
    final fav = a != null && isFavorite(widget.packId, a.title);
    return Scaffold(
      appBar: AppBar(
        title: Text(a?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (a != null && _secs.length >= 3 && !_quick)
            IconButton(tooltip: tr('Contents'), icon: const Icon(Icons.list_alt), onPressed: _openOutline),
          if (a != null)
            IconButton(
              tooltip: tr('Read later'),
              icon: Icon(isInReadingList(widget.packId, a.title) ? Icons.bookmark : Icons.bookmark_border),
              onPressed: () async {
                final done = toggleReadingList(widget.packId, a.title); // the list changes at once, saving follows
                setState(() {});
                final now = await done;
                if (mounted) snack(context, now ? tr('Added to your reading list.') : tr('Removed from your reading list.'));
              },
            ),
          if (a != null)
            IconButton(
              tooltip: tr('Favorite'),
              icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
              onPressed: () async {
                await toggleFavorite(widget.packId, a.title);
                if (mounted) setState(() {});
              },
            ),
          if (a != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'card') {
                  await _addDefinitionCard(a);
                } else if (v == 'ref') {
                  final dup = store.listOf('evidence').any((e) => e['title'] == a.title && e['source'] == (p?.source ?? ''));
                  if (!dup) {
                    await store.upsertExtra('evidence', {
                      'id': newId('ev'),
                      'title': a.title,
                      'source': p?.source ?? '',
                      'year': '${DateTime.now().year}',
                      'level': 'Expert opinion / textbook',
                      'link': a.url,
                      'topic': p?.title ?? '',
                      'note': '',
                      'saved': todayStr(),
                      'reviewed': todayStr(),
                    });
                  }
                  if (mounted) snack(context, dup ? tr('Already in your references.') : tr('Saved to your references.'));
                } else if (v == 'quiz') {
                  final word = _cleanForQuiz(a.title);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(packId: widget.packId, query: word, autoStart: true)));
                } else if (v == 'ask') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AskReferencesScreen(packId: widget.packId, index: widget.index, articleTitle: a.title)));
                } else if (v == 'aitools') {
                  showArticleAiTools(context, widget.packId, widget.index, a, selected: _selected);
                } else if (v == 'online') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(title: a.title, url: a.url)));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'ask', child: Text('Ask about this article')),
                if (Ai.enabled || store.listOf('ailibcache').any((e) => e['title'] == a.title)) PopupMenuItem(value: 'aitools', child: Text('AI study tools')),
                PopupMenuItem(value: 'quiz', child: Text('Test myself on this topic')),
                PopupMenuItem(value: 'card', child: Text('Add to review cards')),
                PopupMenuItem(value: 'ref', child: Text('Save to my references')),
                if (a.url.startsWith('https://en.wikipedia.org/')) PopupMenuItem(value: 'online', child: Text('Open the full online page')),
              ],
            ),
        ],
      ),
      body: _missing
          ? Center(child: Text('Could not open this article.'))
          : a == null
              ? const Center(child: CircularProgressIndicator())
              : ListenableBuilder(
                  listenable: store,
                  builder: (context, _) => SelectionArea(
                    onSelectionChanged: (SelectedContent? c) => _selected = c?.plainText ?? '',
                    contextMenuBuilder: (ctx, state) => _menuFor(ctx, state, a),
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                      children: _children(context, a, p, theme),
                    ),
                  ),
                ),
    );
  }

  String _cleanForQuiz(String t) {
    final base = t.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    final words = base.split(RegExp(r'\s+')).where((w) => w.length >= 5).toList();
    return words.isEmpty ? base : words.first;
  }

  List<Widget> _children(BuildContext context, LibArticle a, PackMeta? p, ThemeData theme) {
    final cs = theme.colorScheme;
    final lead = a.sections.first;
    final sents = sentences(lead.text);
    final sheet = _original ? null : _sheet;
    // sheet mode: the lead's first sentence only when it is prose (a bullet list has no one-line definition)
    final leadIsList = lead.text.trimLeft().startsWith('•') || lead.text.trimLeft().startsWith('▸');
    final definition = _book ? '' : sheet != null ? sheet.definition : (leadIsList || sents.isEmpty ? '' : sents.first);
    final rest = !_book && !leadIsList && sents.length > 1 ? sents.skip(1).join(' ') : '';
    final look = SheetLook.of(context, style: store.libSheetStyle, bold: store.libBold, scale: store.libFontScale, marks: store.settings['libMarks'] != false, focus: _hiQuote);
    final words = a.sections.fold<int>(0, (n, s) => n + s.text.split(RegExp(r'\s+')).length);
    final minutes = (words / 200).ceil().clamp(1, 60);
    final kinds = <Canon>[];
    for (final s in _secs) {
      if (s.canon != Canon.other && s.canon != Canon.background && !kinds.contains(s.canon)) kinds.add(s.canon);
    }
    final scale = store.libFontScale * (store.libBold ? 1.1 : 1.0);
    final cases = casesAbout(a.title);
    // pictures: in quick view all of them are at the top; in the full article the ones that belong to a
    // section are shown inside that section
    final heads = {for (final x in _secs) ...x.heads};
    bool placed(LibImage im) => im.section.trim().isNotEmpty && heads.contains(im.section.trim().toLowerCase());
    final topImages = _quick ? _imgList : [for (final im in _imgList) if (!placed(im)) im];
    final glance = buildGlance(a);
    _inDoseCard = (sheet != null && look.callouts && store.libShowTables) ? sheet.doseTables.toSet() : const {};
    return [
      if (topImages.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ImgStrip(images: topImages, all: _imgList, height: _quick ? 190 : 170),
        ),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: _book
              ? m.Text(a.title, textDirection: TextDirection.ltr, textAlign: TextAlign.left, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.25))
              : Text(a.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 4, children: [
        if (p != null) Chip(visualDensity: VisualDensity.compact, avatar: const Icon(Icons.school_outlined, size: 16), label: Text(p.title)),
        Chip(visualDensity: VisualDensity.compact, avatar: const Icon(Icons.schedule, size: 16), label: Text(trp('{n} min read', {'n': minutes}))),
      ]),
      if (_prov.any)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (_prov.edited.isNotEmpty)
              Directionality(textDirection: TextDirection.ltr, child: m.Text('${tr('Source last edited')}: ${_prov.edited}', style: theme.textTheme.labelSmall?.copyWith(color: cs.outline))),
            if (_prov.outdated)
              Tooltip(
                message: tr('The source was last edited more than 5 years ago. Check a current guideline.'),
                child: Chip(visualDensity: VisualDensity.compact, side: BorderSide(color: cs.outlineVariant), backgroundColor: Colors.transparent, avatar: const Icon(Icons.history, size: 14), label: Text('May be outdated', style: theme.textTheme.labelSmall)),
              ),
            if (_prov.us)
              Tooltip(
                message: tr('Written for the United States (agencies, drugs, guideline bodies). Local practice may differ.'),
                child: Chip(visualDensity: VisualDensity.compact, side: BorderSide(color: cs.outlineVariant), backgroundColor: Colors.transparent, avatar: const Icon(Icons.public, size: 14), label: Text('US-centric guidance', style: theme.textTheme.labelSmall)),
              ),
          ]),
        ),
      if (definition.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withAlpha(110),
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: cs.primary, width: 4)),
          ),
          child: _Para(definition, scale: scale * 1.05, bold: true),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: true, icon: const Icon(Icons.bolt, size: 18), label: Text('Quick view')),
            ButtonSegment(value: false, icon: const Icon(Icons.article_outlined, size: 18), label: Text('Full article')),
          ],
          selected: {_quick},
          onSelectionChanged: (v) {
            _forceFull = false;
            _hiQuote = '';
            _hiSec = -1;
            store.settings['libQuick'] = v.first;
            store.saveSettings();
            setState(() {});
          },
        ),
      ),
      if (!_quick && _a != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(
              avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: Text('Study sheet'),
              selected: !_original,
              onSelected: (_) => setState(() {
                _original = false;
                _applyMode();
              }),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.article_outlined, size: 16),
              label: Text('Original text'),
              selected: _original,
              onSelected: (_) => setState(() {
                _original = true;
                _applyMode();
              }),
            ),
          ]),
        ),
      if (_sibs.isNotEmpty && !_original)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilterChip(
              avatar: const Icon(Icons.layers_outlined, size: 16),
              label: Text(trp('Combined view ({n} sources)', {'n': _sibs.length + 1})),
              selected: _useCombined && !_quick,
              onSelected: (v) => setState(() {
                if (_quick) {
                  // from the quick view: open the full article in the combined view
                  store.settings['libQuick'] = false;
                  store.saveSettings();
                  _useCombined = true;
                } else {
                  _useCombined = v;
                }
                _applyMode();
              }),
            ),
            if (!_quick && sheet != null && sheet.combined) for (final l in sheet.sources) SheetSourceBadge(l),
          ]),
        ),
      if (sheet != null) RedFlagSummary(sheet: sheet, look: look),
      if (sheet != null) DoseSummary(sheet: sheet, look: look, tables: [if (store.libShowTables) for (final t in sheet.doseTables) _TableCard(table: t, scale: scale)]),
      if (_quick) ...[
        for (final g in glance)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(secIcon(g.kind), size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Directionality(textDirection: TextDirection.ltr, child: Text(secLabel(g.kind), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 6),
                for (final pt in g.points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(padding: const EdgeInsets.only(top: 7, right: 8), child: Container(width: 6, height: 6, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle))),
                        Expanded(child: Text(pt, textAlign: TextAlign.left, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * scale))),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        if (glance.isEmpty && rest.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: _Body(rest, scale: scale)),
        if (store.libShowTables)
          for (final sec in a.sections)
            for (final t in sec.tables) if (!_inDoseCard.contains(t)) _TableCard(table: t, scale: scale),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, children: [
          ActionChip(
            avatar: const Icon(Icons.quiz_outlined, size: 18),
            label: Text('Test myself on this topic'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(packId: widget.packId, query: _cleanForQuiz(a.title), autoStart: true))),
          ),
          ActionChip(avatar: const Icon(Icons.style_outlined, size: 18), label: Text('Add to review cards'), onPressed: () => _addDefinitionCard(a)),
          ActionChip(
            avatar: const Icon(Icons.article_outlined, size: 18),
            label: Text('Read the full article'),
            onPressed: () {
              store.settings['libQuick'] = false;
              store.saveSettings();
              setState(() {});
            },
          ),
        ]),
      ],
      if (!_quick && kinds.isNotEmpty) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final k in kinds)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ActionChip(
                    avatar: Icon(canonIcon(k), size: 18, color: look.style >= 1 ? canonColor(k, look.dark) : null),
                    label: Directionality(textDirection: TextDirection.ltr, child: Text(canonLabel(k))),
                    onPressed: () => _jump(_secs.indexWhere((s) => s.canon == k)),
                  ),
                ),
            ],
          ),
        ),
      ],
      if (!_quick && sheet != null)
        for (final part in sheet.lead) Padding(padding: const EdgeInsets.only(top: 6), child: SheetPartView(part: part, look: look, tablesFor: (pt) => _tablesList(pt.tables, scale))),
      if (!_quick && sheet == null && rest.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: _Body(rest, scale: scale)),
      if (sheet == null && !_quick && definition.isEmpty && lead.text.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: _bodyOf(lead.text, scale)),
      if (sheet == null) ..._tablesOf(lead, scale),
      if (!_quick && _secs.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => setState(() {
              if (_open.length == _secs.length) {
                _open.clear();
              } else {
                _open.addAll([for (var i = 0; i < _secs.length; i++) i]);
              }
            }),
            icon: Icon(_open.length == _secs.length ? Icons.unfold_less : Icons.unfold_more),
            label: Text(_open.length == _secs.length ? 'Collapse all' : 'Expand all'),
          ),
        ),
      if (!_quick)
        for (var i = 0; i < _secs.length; i++)
          _SecCard(
            key: _keys.putIfAbsent(i, () => GlobalKey()),
            title: _secs[i].title,
            literal: _book,
            icon: canonIcon(_secs[i].canon),
            accent: look.style >= 1 && !_original ? canonColor(_secs[i].canon, look.dark) : null,
            tint: look.rich && !_original,
            open: _open.contains(i),
            flash: i == _hiSec,
            onToggle: () => setState(() => _open.contains(i) ? _open.remove(i) : _open.add(i)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_imgList.any((im) => im.section.isNotEmpty && _secs[i].heads.contains(im.section.trim().toLowerCase())))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ImgStrip(
                    images: [for (final im in _imgList) if (_secs[i].heads.contains(im.section.trim().toLowerCase())) im],
                    all: _imgList,
                    height: 150,
                  ),
                ),
              if (_secs[i].raw != null) ...[
                _bodyOf(_secs[i].raw!.text, scale),
                ..._tablesOf(_secs[i].raw!, scale),
              ] else
                SheetSecBody(
                  sec: _secs[i].sheet!,
                  look: look,
                  combined: sheet?.combined ?? false,
                  tablesFor: (pt) => _tablesList(pt.tables, scale),
                ),
            ]),
          ),
      const SizedBox(height: 8),
      Fold(
        id: 'art_notes',
        title: tr('My notes on this article'),
        icon: Icons.edit_note,
        initiallyOpen: _note.text.isNotEmpty,
        children: [
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 8,
            onChanged: _onNote,
            decoration: InputDecoration(labelText: tr('Your notes (kept on this phone)')),
          ),
        ],
      ),
      if (cases.isNotEmpty)
        Fold(
          id: 'art_cases',
          title: tr('My cases about this'),
          subtitle: countLabel(cases.length, 'case'),
          icon: Icons.folder_copy_outlined,
          children: [
            for (final c in cases.take(8))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined, size: 20),
                title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(c.s('code')),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: c))),
              ),
          ],
        ),
      if (_related.isNotEmpty)
        Fold(
          id: 'art_related',
          title: tr('Related articles'),
          icon: Icons.hub_outlined,
          initiallyOpen: true,
          children: [
            for (final r in _related)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.article_outlined, size: 20),
                title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ArticleScreen(packId: r.packId, index: r.index))),
              ),
          ],
        ),
      const SizedBox(height: 8),
      AppCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Source and license', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(width: double.infinity, child: m.Text(_sourceLine(a, p), textAlign: TextAlign.left, style: theme.textTheme.bodySmall)),
            ),
            const SizedBox(height: 6),
            Text(
                _book
                    ? 'Text, tables and figures are from the supplied book edition.'
                    : a.sections.any((s) => s.tables.isNotEmpty) && store.libShowTables
                    ? 'For learning. It may be out of date and it does not replace your hospital protocols. Images are not included and long tables are shortened.'
                    : 'For learning. It may be out of date and it does not replace your hospital protocols. Images and tables are not included.',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
          ]),
        ),
      ),
    ];
  }

  /// Per-article source and license when the article carries them, otherwise the pack's.
  String _sourceLine(LibArticle a, PackMeta? p) {
    final src = a.source.isNotEmpty ? a.source : (p?.source ?? '');
    final lic = a.license.isNotEmpty ? a.license : (p?.license ?? '');
    final lines = <String>[
      if (src.isNotEmpty) src,
      if (lic.isNotEmpty) lic,
      if (a.authors.isNotEmpty) '${tr('Authors')}: ${a.authors}',
      if (a.url.isNotEmpty) a.url,
      '${tr('Downloaded')}: ${a.date.isNotEmpty ? a.date : (p?.date ?? '')}',
    ];
    return lines.join('\n');
  }
}

/// A table from the article: caption, foldable, horizontally scrollable grid, full screen for wide ones.
class _TableCard extends StatefulWidget {
  final LibTable table;
  final double scale;
  const _TableCard({required this.table, required this.scale});
  @override
  State<_TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<_TableCard> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = widget.table;
    final big = t.columns > 4;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
            child: Row(children: [
              Icon(Icons.table_chart_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: t.caption.isEmpty
                    ? Text('Table', style: theme.textTheme.labelLarge)
                    : Directionality(
                        textDirection: TextDirection.ltr,
                        child: m.Text(t.caption, maxLines: _open ? 3 : 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge),
                      ),
              ),
              if (big)
                IconButton(
                  tooltip: tr('Full screen'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.fullscreen),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TableViewerScreen(table: t))),
                ),
              AnimatedRotation(turns: _open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.expand_more))),
            ]),
          ),
        ),
        if (_open)
          Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: TableGrid(table: t, scale: widget.scale),
            ),
          ),
      ]),
    );
  }
}

/// The grid itself: header row styled, striped rows, cells left-to-right unless they start with Arabic.
class TableGrid extends StatelessWidget {
  final LibTable table;
  final double scale;
  final double maxCell;
  const TableGrid({super.key, required this.table, this.scale = 1, this.maxCell = 220});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = theme.textTheme.bodySmall;
    final fs = (base?.fontSize ?? 12) * scale;
    final cols = table.columns;
    Widget cell(String txt, bool head) {
      final dir = textDirectionFor(txt) ?? TextDirection.ltr;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 56, maxWidth: maxCell),
          child: m.Text(
            txt,
            textDirection: dir,
            textAlign: dir == TextDirection.rtl ? TextAlign.right : TextAlign.left,
            style: base?.copyWith(fontSize: fs, height: 1.35, fontWeight: head ? FontWeight.w800 : null, color: head ? cs.onPrimaryContainer : null),
          ),
        ),
      );
    }

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      border: TableBorder(horizontalInside: BorderSide(color: cs.outlineVariant.withAlpha(140)), verticalInside: BorderSide(color: cs.outlineVariant.withAlpha(90))),
      children: [
        for (var r = 0; r < table.rows.length; r++)
          TableRow(
            decoration: BoxDecoration(color: r == 0 ? cs.primaryContainer : (r.isEven ? cs.surfaceContainerLow : null)),
            children: [
              for (var c = 0; c < cols; c++) cell(c < table.rows[r].length ? table.rows[r][c] : '', r == 0),
            ],
          ),
      ],
    );
  }
}

/// Full-screen table: pinch to zoom, drag to move around.
class TableViewerScreen extends StatelessWidget {
  final LibTable table;
  const TableViewerScreen({super.key, required this.table});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: table.caption.isEmpty ? Text('Table') : m.Text(table.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: InteractiveViewer(
            constrained: false,
            minScale: 0.4,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(120),
            child: Padding(padding: const EdgeInsets.all(8), child: SelectionArea(child: TableGrid(table: table, maxCell: 320))),
          ),
        ),
      ),
    );
  }
}

class _SecCard extends StatelessWidget {
  final bool literal;
  final String title;
  final IconData icon;
  final Color? accent;
  final bool tint;
  final bool open;
  final bool flash;
  final VoidCallback onToggle;
  final Widget child;
  const _SecCard({super.key, this.literal = false, required this.title, required this.icon, this.accent, this.tint = false, required this.open, this.flash = false, required this.onToggle, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: flash ? Color.alphaBlend(cs.tertiary.withAlpha(36), cs.surfaceContainerLow) : cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: flash ? cs.tertiary : (open ? (accent ?? cs.primary).withAlpha(120) : cs.outlineVariant), width: flash ? 2 : 1)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            color: tint && accent != null ? accent!.withAlpha(Theme.of(context).brightness == Brightness.dark ? 34 : 24) : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 20, color: accent ?? cs.primary),
              const SizedBox(width: 10),
              Expanded(child: literal
                  ? m.Text(title, textDirection: TextDirection.ltr, textAlign: TextAlign.left, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))
                  : Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.expand_more)),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: open ? Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: child) : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

/// One paragraph of English article text (always left-to-right).
class _Para extends StatelessWidget {
  final String text;
  final double scale;
  final bool bold;
  const _Para(this.text, {required this.scale, this.bold = false});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          textAlign: TextAlign.left,
          style: base?.copyWith(fontSize: (base.fontSize ?? 14) * scale, height: 1.6, fontWeight: bold ? FontWeight.w600 : null),
        ),
      ),
    );
  }
}

/// Article text: paragraphs with space between them, bullets with a hanging indent.
class _Body extends StatelessWidget {
  final String text;
  final double scale;
  final String focus;
  const _Body(this.text, {required this.scale, this.focus = ''});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium;
    final fs = (base?.fontSize ?? 14) * scale;
    // long paragraphs are cut into shorter blocks (about three sentences each) so they are easier to read
    final paras = <String>[];
    for (final raw in text.split('\n').where((e) => e.trim().isNotEmpty)) {
      if (raw.startsWith('• ') || raw.length < 420) {
        paras.add(raw);
        continue;
      }
      var cur = '';
      for (final snt in sentences(raw)) {
        if (cur.isNotEmpty && cur.length + snt.length > 300) {
          paras.add(cur);
          cur = snt;
        } else {
          cur = cur.isEmpty ? snt : '$cur $snt';
        }
      }
      if (cur.isNotEmpty) paras.add(cur);
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in paras)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: focus.isNotEmpty && normQuote(t).contains(focus) ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : EdgeInsets.zero,
              decoration: focus.isNotEmpty && normQuote(t).contains(focus) ? BoxDecoration(color: theme.colorScheme.tertiary.withAlpha(60), borderRadius: BorderRadius.circular(8)) : null,
              child: t.startsWith('• ')
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: EdgeInsets.only(top: fs * 0.55, right: 10, left: 4),
                        child: Container(width: 6, height: 6, decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle)),
                      ),
                      Expanded(child: Text(t.substring(2), textAlign: TextAlign.left, style: base?.copyWith(fontSize: fs, height: 1.55))),
                    ])
                  : Text(t, textAlign: TextAlign.left, style: base?.copyWith(fontSize: fs, height: 1.6)),
            ),
        ],
      ),
    );
  }
}


/// Horizontal strip of pictures (tap one to open it full screen).
class _ImgStrip extends StatelessWidget {
  final List<LibImage> images;
  final List<LibImage> all;
  final double height;
  const _ImgStrip({required this.images, required this.all, required this.height});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
      height: height + 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final im = images[i];
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewerScreen(images: all, index: all.indexOf(im).clamp(0, all.length - 1)))),
            child: SizedBox(
              width: height * 1.25,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: height,
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant)),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(im.bytes, fit: BoxFit.contain, gaplessPlayback: true),
                ),
                const SizedBox(height: 4),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: im.file.startsWith('book:')
                      ? m.Text(im.caption.isEmpty ? im.file : im.caption, textDirection: TextDirection.ltr, textAlign: TextAlign.left, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: cs.outline))
                      : Text(im.caption.isEmpty ? im.file : im.caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
                ),
              ]),
            ),
          );
        },
      ),
    ));
  }
}

/// Full-screen picture viewer: swipe between the article's pictures, pinch to zoom.
class ImageViewerScreen extends StatefulWidget {
  final List<LibImage> images;
  final int index;
  const ImageViewerScreen({super.key, required this.images, required this.index});
  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _pc = PageController(initialPage: widget.index);
  late int _i = widget.index;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final im = widget.images[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_i + 1} / ${widget.images.length}'),
        actions: [
          if (!im.file.startsWith('book:')) IconButton(
            tooltip: tr('Image details'),
            icon: const Icon(Icons.open_in_new),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(title: im.file, url: im.filePage))),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _pc,
            itemCount: widget.images.length,
            onPageChanged: (v) => setState(() => _i = v),
            itemBuilder: (context, k) => InteractiveViewer(minScale: 1, maxScale: 6, child: Center(child: Image.memory(widget.images[k].bytes, fit: BoxFit.contain))),
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (im.caption.isNotEmpty)
                if (im.file.startsWith('book:')) m.Text(im.caption, textAlign: TextAlign.left, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white))
                else Text(im.caption, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              if (im.file.startsWith('book:')) m.Text(im.credit, textAlign: TextAlign.left, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70))
              else Text('${im.file} — ${im.credit}', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
            ]),
          ),
        ),
      ]),
    );
  }
}


/// Contents of a chapter with a search over its sections.
class _OutlineSheet extends StatefulWidget {
  final List<(String, String)> secs;
  final Set<int> open;
  const _OutlineSheet({required this.secs, required this.open});
  @override
  State<_OutlineSheet> createState() => _OutlineSheetState();
}

class _OutlineSheetState extends State<_OutlineSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nq = normQuote(_q);
    final rows = <(int, String, int)>[]; // index, title, matches
    for (var i = 0; i < widget.secs.length; i++) {
      final (title, text) = widget.secs[i];
      if (nq.isEmpty) {
        rows.add((i, title, 0));
        continue;
      }
      final hay = normQuote(text);
      var n = 0;
      for (var at = hay.indexOf(nq); at >= 0 && n < 99; at = hay.indexOf(nq, at + nq.length)) {
        n++;
      }
      if (n > 0 || normQuote(title).contains(nq)) rows.add((i, title, n));
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), labelText: tr('Search in this chapter')),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text('No match', style: theme.textTheme.bodyMedium))
                  : ListView(children: [
                      for (final (i, title, n) in rows)
                        ListTile(
                          dense: true,
                          leading: Icon(widget.open.contains(i) ? Icons.folder_open : Icons.folder_outlined, size: 20),
                          title: m.Text(title, textDirection: TextDirection.ltr, textAlign: TextAlign.left, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: n > 0 ? Chip(label: m.Text('$n'), visualDensity: VisualDensity.compact) : null,
                          onTap: () => Navigator.pop(context, (i, _q)),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}
