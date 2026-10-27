import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'ai/ai_api.dart';
import 'ai/ai_prefs.dart';
import 'ai/ai_library.dart';
import 'data.dart';
import 'i18n.dart';
import 'lib_user.dart';
import 'library.dart';
import 'screens_ai_chat.dart';
import 'screens_library.dart';
import 'ui.dart';
import 'widgets.dart';

/// Optional AI layer for the library. Everything has a non-AI path: without a key or without internet the screens
/// below still work as a local search with passages and say that AI is unavailable.

const String kNotFoundText = 'Not found in your references';

// ================================================================ Ask my references

class AskReferencesScreen extends StatefulWidget {
  final String initialQuestion;
  final String? packId; // limit to one article ("Ask about this article")
  final int? index;
  final String? articleTitle;
  const AskReferencesScreen({super.key, this.initialQuestion = '', this.packId, this.index, this.articleTitle});
  @override
  State<AskReferencesScreen> createState() => _AskReferencesScreenState();
}

class _AskReferencesScreenState extends State<AskReferencesScreen> {
  late final TextEditingController _q = TextEditingController(text: widget.initialQuestion);
  bool _busy = false;
  bool _asked = false;
  Retrieval? _ret;
  AskAnswer? _ans;
  bool _aiOff = false; // the question was answered by the local search only
  List<LibHit> _local = const [];
  List<String> _try = const [];
  String _asking = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestion.trim().isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _q.text.trim();
    if (q.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _asked = true;
      _ans = null;
      _ret = null;
      _local = const [];
      _try = const [];
      _asking = q;
    });
    Retrieval r = const Retrieval([], []);
    List<LibHit> local = const [];
    try {
      r = await AiLibrary.retrieve(q, packId: widget.packId, index: widget.index);
      if (r.isEmpty && widget.packId == null && library.ready && library.textPacks.isNotEmpty) {
        local = await library.searchEx(AiLibrary.localKeywords(q).isEmpty ? q : AiLibrary.localKeywords(q), body: true, concise: true, limit: 8);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _ret = r;
      _local = local;
    });
    AskAnswer? ans;
    if (r.isEmpty) {
      ans = AskAnswer.notFound(const []); // nothing in the library supports an answer: the model is not called at all
    } else {
      try {
        ans = await AiLibrary.ask(q, r, context: context);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _ans = ans;
      _aiOff = ans == null;
      _busy = false;
    });
    if (r.isEmpty && Ai.enabled && AiPrefs.queryExpansion && widget.packId == null) {
      final t = await AiLibrary.expandQuery(AiLibrary.localKeywords(q).isEmpty ? q : AiLibrary.localKeywords(q), context: context);
      if (mounted && t.isNotEmpty) setState(() => _try = t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.articleTitle == null ? 'Ask my references' : 'Ask about this article')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (widget.articleTitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Directionality(textDirection: TextDirection.ltr, child: m.Text(widget.articleTitle!, style: theme.textTheme.titleSmall)),
            ),
          TextField(
            controller: _q,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _ask(),
            decoration: InputDecoration(
              labelText: tr('Your question'),
              hintText: tr('e.g. How is DKA managed?'),
              helperText: tr("Don't type patient names or IDs."),
              helperMaxLines: 2,
              suffixIcon: IconButton(tooltip: tr('Ask'), icon: const Icon(Icons.send), onPressed: _busy ? null : _ask),
            ),
          ),
          const SizedBox(height: 6),
          AiBuilder(builder: (context, enabled, online) {
            final msg = !enabled
                ? 'AI is off: answers come from a local search of your library. You can turn AI on in Settings.'
                : !online
                    ? 'You are offline: showing passages from your library. AI answers need internet.'
                    : 'Answers use only passages from your installed library and name their sources. Check them in the article.';
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(enabled && online ? Icons.auto_awesome : Icons.wifi_off, size: 14, color: cs.outline),
              const SizedBox(width: 6),
              Expanded(child: Text(msg, style: theme.textTheme.bodySmall?.copyWith(color: cs.outline))),
            ]);
          }),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _ask,
            icon: const Icon(Icons.search),
            label: Text('Search my references'),
          ),
          AiBuilder(builder: (context, enabled, online) {
            if (!enabled) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const ValueKey('ask_web'),
                onPressed: online ? () => openAskAi(context, question: _q.text.trim().isEmpty ? null : _q.text.trim(), mode: 'web') : null,
                icon: const Icon(Icons.public),
                label: Text('Ask with web sources (Ask AI)'),
              ),
            );
          }),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          if (!library.ready || library.textPacks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('No courses are downloaded yet. Install a course in Courses and library first.', style: theme.textTheme.bodyMedium),
            ),
          if (_asked && !_busy) ..._result(context),
        ],
      ),
    );
  }

  List<Widget> _result(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final r = _ret ?? const Retrieval([], []);
    final a = _ans;
    final out = <Widget>[const SizedBox(height: 12)];
    if (r.isEmpty) {
      out.add(AppCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.search_off, color: cs.outline),
            const SizedBox(width: 10),
            Expanded(child: Text(kNotFoundText, style: theme.textTheme.titleSmall)),
          ]),
        ),
      ));
      if (_try.isNotEmpty) out.add(TryChips(terms: _try, onPick: (t) {
        _q.text = t;
        _ask();
      }));
      if (_local.isNotEmpty) {
        out.add(SectionHeader(tr('Possibly related articles')));
        for (final h in _local) {
          out.add(_hitTile(context, h));
        }
      }
      return out;
    }
    if (a != null && a.error != null && a.text.isEmpty) {
      out.add(Text('${tr('AI could not do this')}: ${a.error}', style: theme.textTheme.bodyMedium?.copyWith(color: cs.error)));
    }
    if (a != null && a.text.isNotEmpty) {
      if (a.notFound) {
        out.add(AppCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.search_off, color: cs.outline),
              const SizedBox(width: 10),
              Expanded(child: Text(kNotFoundText, style: theme.textTheme.titleSmall)),
            ]),
          ),
        ));
      } else {
        out.add(AiOutputCard(
          text: a.text,
          feature: 'ask_refs',
          sources: [for (final n in a.cited) '[$n] ${a.passages[n - 1].title} (${a.passages[n - 1].source})'],
          footer: _sourceChips(context, a),
        ));
        if (a.unsupported.isNotEmpty) {
          out.add(_warn(context, '${tr('Check these numbers: they were not found in the passages')}: ${a.unsupported.join(', ')}'));
        }
        if (a.uncited) out.add(_warn(context, tr('This answer cites no passage. Treat it with caution and read the passages below.')));
      }
    } else if (_aiOff) {
      out.add(Row(children: [
        Icon(Icons.info_outline, size: 16, color: cs.outline),
        const SizedBox(width: 6),
        Expanded(child: Text('AI is unavailable (off or offline). Here are the matching passages from your library.', style: theme.textTheme.bodySmall)),
      ]));
    }
    out.add(SectionHeader(tr('Passages used')));
    for (final p in r.passages) {
      out.add(_passageCard(context, p));
    }
    out.add(const SizedBox(height: 8));
    out.add(Wrap(spacing: 8, runSpacing: 4, children: [
      OutlinedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LatestEvidenceScreen(topic: _topic()))),
        icon: const Icon(Icons.public, size: 18),
        label: Text('Latest evidence'),
      ),
      OutlinedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryScreen(initialQuery: AiLibrary.localKeywords(_asking)))),
        icon: const Icon(Icons.local_library_outlined, size: 18),
        label: Text('Open in library search'),
      ),
    ]));
    return out;
  }

  String _topic() {
    if (widget.articleTitle != null) return stripSource(widget.articleTitle!);
    final r = _ret;
    if (r != null && r.passages.isNotEmpty) return r.passages.first.title;
    return AiLibrary.localKeywords(_asking);
  }

  Widget _warn(BuildContext context, String t) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
        const SizedBox(width: 6),
        Expanded(child: Text(t, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.error))),
      ]),
    );
  }

  Widget _sourceChips(BuildContext context, AskAnswer a) {
    final used = a.cited.isEmpty ? [for (final p in a.passages) p.n] : a.cited;
    return Wrap(spacing: 6, runSpacing: 2, children: [
      for (final n in used)
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 80),
          child: ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.article_outlined, size: 16),
            label: Directionality(
              textDirection: TextDirection.ltr,
              child: m.Text('[$n] ${a.passages[n - 1].title} · ${a.passages[n - 1].source}', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            onPressed: () => openArticle(context, a.passages[n - 1].packId, a.passages[n - 1].index),
          ),
        ),
    ]);
  }

  Widget _passageCard(BuildContext context, Passage p) {
    final theme = Theme.of(context);
    return AppCard(
      child: InkWell(
        onTap: () => openArticle(context, p.packId, p.index),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 11, child: m.Text('${p.n}', style: const TextStyle(fontSize: 11))),
              const SizedBox(width: 8),
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: m.Text('${p.title}${p.section.isEmpty ? '' : ' › ${p.section}'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                ),
              ),
              const SizedBox(width: 6),
              SourceBadge(p.source),
            ]),
            const SizedBox(height: 6),
            Directionality(textDirection: TextDirection.ltr, child: m.Text(p.text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4))),
          ]),
        ),
      ),
    );
  }

  Widget _hitTile(BuildContext context, LibHit h) => AppCard(
        child: ListTile(
          leading: const Icon(Icons.local_library_outlined),
          title: Text(stripSource(h.title), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: hitSubtitle(h.packId, h.title, h.lead),
          onTap: () => openArticle(context, h.packId, h.index),
        ),
      );
}

/// "Try: a, b, c" chips (AI query expansion). Empty list renders nothing.
class TryChips extends StatelessWidget {
  final List<String> terms;
  final ValueChanged<String> onPick;
  const TryChips({super.key, required this.terms, required this.onPick});
  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, size: 14, color: theme.colorScheme.tertiary),
          const SizedBox(width: 4),
          Text('Try:', style: theme.textTheme.labelLarge),
        ]),
        for (final t in terms)
          ActionChip(
            visualDensity: VisualDensity.compact,
            label: Directionality(textDirection: TextDirection.ltr, child: m.Text(t)),
            onPressed: () => onPick(t),
          ),
      ]),
    );
  }
}

/// Loads AI query-expansion suggestions for [query] when the library found little (AI on only).
class AiTrySuggestions extends StatefulWidget {
  final String query;
  final int resultCount;
  final ValueChanged<String> onPick;
  const AiTrySuggestions({super.key, required this.query, required this.resultCount, required this.onPick});
  @override
  State<AiTrySuggestions> createState() => _AiTrySuggestionsState();
}

class _AiTrySuggestionsState extends State<AiTrySuggestions> {
  List<String> _terms = const [];
  String _for = '';
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _plan();
  }

  @override
  void didUpdateWidget(AiTrySuggestions old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query || old.resultCount != widget.resultCount) _plan();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _plan() {
    _t?.cancel();
    final q = widget.query.trim();
    if (q.length < 3 || widget.resultCount >= 3 || !Ai.enabled) {
      if (_terms.isNotEmpty) setState(() => _terms = const []);
      return;
    }
    if (_for == q) return;
    _t = Timer(const Duration(milliseconds: 900), () async {
      if (!AiPrefs.queryExpansion) return;
      final t = await AiLibrary.expandQuery(q, context: context);
      if (!mounted) return;
      setState(() {
        _terms = t;
        _for = q;
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.resultCount >= 3 ? const SizedBox.shrink() : TryChips(terms: _terms, onPick: widget.onPick);
}

/// Smart search chip for a sentence typed in a search box (level none: only the sentence leaves the phone).
/// [onQuery] gets the translated query; the normal LOCAL search then runs.
class NlSearchChip extends StatefulWidget {
  final String text;
  final bool forCases;
  final ValueChanged<String> onQuery;
  const NlSearchChip({super.key, required this.text, required this.onQuery, this.forCases = false});
  @override
  State<NlSearchChip> createState() => _NlSearchChipState();
}

class _NlSearchChipState extends State<NlSearchChip> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    if (!AiLibrary.looksNatural(widget.text)) return const SizedBox.shrink();
    return AiButton(
      label: tr(widget.forCases ? 'Turn into a case search' : 'Smart search'),
      feature: 'nl_search',
      icon: Icons.manage_search,
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              final q = await AiLibrary.naturalToQuery(widget.text, forCases: widget.forCases, context: context);
              if (!mounted) return;
              setState(() => _busy = false);
              if (q == null) {
                snack(context, tr('Could not understand the sentence: showing the normal search.'));
              } else {
                widget.onQuery(q);
              }
            },
    );
  }
}

// ================================================================ explain / simplify / translate / compare

String articleText(LibArticle a, {int max = 9000}) {
  final b = StringBuffer();
  for (final s in a.sections) {
    if (s.heading.trim().isNotEmpty) b.writeln('${s.heading.trim()}:');
    b.writeln(s.text.trim());
    b.writeln();
    if (b.length > max) break;
  }
  final t = b.toString().trim();
  return t.length > max ? t.substring(0, max) : t;
}

/// Bottom sheet with the AI study actions of an article. [selected] is the text the user marked (may be empty).
Future<void> showArticleAiTools(BuildContext context, String packId, int index, LibArticle article, {String selected = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, sc) => ArticleAiTools(packId: packId, index: index, article: article, selected: selected, controller: sc),
    ),
  );
}

class ArticleAiTools extends StatefulWidget {
  final String packId;
  final int index;
  final LibArticle article;
  final String selected;
  final ScrollController? controller;
  const ArticleAiTools({super.key, required this.packId, required this.index, required this.article, this.selected = '', this.controller});
  @override
  State<ArticleAiTools> createState() => _ArticleAiToolsState();
}

class _ArticleAiToolsState extends State<ArticleAiTools> {
  int _scope = 0; // 0 = selected text (when there is one) / whole article, then one entry per section
  String _action = '';
  bool _busy = false;
  ActionResult? _res;
  String _otherTitle = '';

  bool get _hasSel => widget.selected.trim().length >= 20;

  List<String> get _scopes => [
        if (_hasSel) 'Selected text',
        'Whole article (quick view)',
        for (final s in widget.article.sections)
          if (s.heading.trim().isNotEmpty && s.text.trim().length > 40) s.heading.trim(),
      ];

  (String, String) _scopeText() {
    final names = _scopes;
    final i = _scope.clamp(0, names.length - 1);
    final n = names[i];
    if (_hasSel && i == 0) return ('Selection', widget.selected.trim());
    if (n == 'Whole article (quick view)') return ('', articleText(widget.article));
    for (final s in widget.article.sections) {
      if (s.heading.trim() == n) return (n, s.text.trim());
    }
    return ('', articleText(widget.article));
  }

  Future<void> _run(String action, {String? otherTitle, String? otherText}) async {
    final (sec, text) = _scopeText();
    setState(() {
      _busy = true;
      _action = action;
      _res = null;
      _otherTitle = otherTitle ?? '';
    });
    final r = await AiLibrary.runAction(action, widget.packId, widget.article.title, sec, text, otherTitle: otherTitle, otherText: otherText, context: context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _res = r;
    });
  }

  Future<void> _compare() async {
    final picked = await showDialog<(String, String)>(context: context, builder: (_) => _PickArticleDialog(exclude: widget.article.title));
    if (picked == null || !mounted) return;
    await _run('compare', otherTitle: picked.$1, otherText: picked.$2);
  }

  Future<void> _saveNote() async {
    final r = _res;
    if (r == null || r.text.isEmpty) return;
    final old = noteFor(widget.packId, widget.article.title);
    final head = '[AI ${_label(_action)}${_otherTitle.isEmpty ? '' : ' / ${stripSource(_otherTitle)}'}]';
    await saveNote(widget.packId, widget.article.title, '${old.trim().isEmpty ? '' : '${old.trim()}\n\n'}$head\n${r.text.trim()}');
    if (mounted) snack(context, tr('Saved to your notes for this article.'));
  }

  String _label(String a) => switch (a) {
        'explain' => 'Explain simply',
        'summarize' => 'Summarize',
        'translate' => 'Translate to Arabic',
        'compare' => 'Comparison table',
        _ => a,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final names = _scopes;
    final scope = _scope.clamp(0, names.length - 1);
    final (sec, text) = _scopeText();
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(children: [
          Icon(Icons.auto_awesome, color: cs.tertiary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('AI study tools', style: theme.textTheme.titleMedium)),
        ]),
        const SizedBox(height: 4),
        Text('AI only helps you study. It never changes the article, and it uses only the text of this library.', style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
        const SizedBox(height: 10),
        InputDecorator(
          decoration: InputDecoration(labelText: tr('Text to use')),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: scope,
              items: [
                for (var i = 0; i < names.length; i++)
                  DropdownMenuItem(value: i, child: Directionality(textDirection: TextDirection.ltr, child: m.Text(i < 2 && (names[i] == 'Selected text' || names[i] == 'Whole article (quick view)') ? tr(names[i]) : names[i], overflow: TextOverflow.ellipsis))),
              ],
              onChanged: _busy ? null : (v) => setState(() {
                    _scope = v ?? 0;
                    _res = null;
                  }),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(trp('{n} characters', {'n': text.length}), style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
        const SizedBox(height: 8),
        AiBuilder(builder: (context, enabled, online) {
          final off = !enabled;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in const ['explain', 'summarize', 'translate'])
                _actionBtn(a, _label(a), a == 'explain' ? Icons.lightbulb_outline : a == 'summarize' ? Icons.short_text : Icons.translate, enabled && online),
              _actionBtn('compare', 'Compare with another condition', Icons.table_chart_outlined, enabled && online, onTap: _compare),
            ]),
            if (off || !online)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(off ? 'AI is off. Results you saved before still open here.' : 'You are offline. Results you saved before still open here.', style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
              ),
          ]);
        }),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (_res != null) ..._resultWidgets(context, sec, text),
        _savedList(context),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => AskReferencesScreen(packId: widget.packId, index: widget.index, articleTitle: widget.article.title)));
            },
            icon: const Icon(Icons.question_answer_outlined, size: 18),
            label: Text('Ask about this article'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => LatestEvidenceScreen(topic: stripSource(widget.article.title))));
            },
            icon: const Icon(Icons.public, size: 18),
            label: Text('Latest evidence'),
          ),
        ]),
      ],
    );
  }

  Widget _actionBtn(String a, String label, IconData icon, bool usable, {VoidCallback? onTap}) {
    // an action with a saved result stays usable without AI
    final (sec, text) = _scopeText();
    final key = a == 'compare' ? null : AiLibrary.actionKey(a, widget.packId, widget.article.title, sec, text);
    final hasSaved = key != null && (AiLibrary.saved(key) ?? '').isNotEmpty;
    return OutlinedButton.icon(
      onPressed: (_busy || !(usable || hasSaved)) ? null : (onTap ?? () => _run(a)),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  List<Widget> _resultWidgets(BuildContext context, String sec, String text) {
    final r = _res!;
    final theme = Theme.of(context);
    if (r.offline) {
      return [Padding(padding: const EdgeInsets.only(top: 12), child: Text('AI is unavailable right now (off or offline). The article is unchanged.', style: theme.textTheme.bodyMedium))];
    }
    if (r.error != null) {
      return [Padding(padding: const EdgeInsets.only(top: 12), child: Text('${tr('AI could not do this')}: ${r.error}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)))];
    }
    return [
      const SizedBox(height: 12),
      Row(children: [
        Chip(visualDensity: VisualDensity.compact, avatar: const Icon(Icons.auto_awesome, size: 14), label: Text(r.saved ? 'AI, saved result' : 'AI')),
        const SizedBox(width: 8),
        Expanded(child: Text(_label(_action), style: theme.textTheme.labelLarge)),
      ]),
      AiOutputCard(
        text: r.text,
        feature: _action == 'translate' ? 'translate_lib' : 'explain_$_action',
        footer: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(onPressed: _saveNote, icon: const Icon(Icons.note_add_outlined, size: 18), label: Text('Save as note')),
        ),
      ),
    ];
  }

  Widget _savedList(BuildContext context) {
    final mine = [
      for (final e in store.listOf('ailibcache'))
        if ('${e['title']}' == widget.article.title) e
    ];
    if (mine.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(trp('Saved AI results ({n})', {'n': mine.length})),
        children: [
          for (final e in mine.reversed.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AiOutputCard(text: '${e['text']}', feature: 'explain_${e['kind']}'),
            ),
        ],
      ),
    );
  }
}

/// Search another article to compare with: returns (title, text).
class _PickArticleDialog extends StatefulWidget {
  final String exclude;
  const _PickArticleDialog({required this.exclude});
  @override
  State<_PickArticleDialog> createState() => _PickArticleDialogState();
}

class _PickArticleDialogState extends State<_PickArticleDialog> {
  final _c = TextEditingController();
  List<LibHit> _hits = const [];
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _go(String v) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 250), () async {
      final h = v.trim().isEmpty ? <LibHit>[] : await library.searchEx(v, limit: 12, concise: true);
      if (mounted) setState(() => _hits = [for (final x in h) if (x.title != widget.exclude) x]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Compare with'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _c, autofocus: true, onChanged: _go, decoration: InputDecoration(labelText: tr('Another condition'))),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final h in _hits)
                ListTile(
                  dense: true,
                  title: Text(stripSource(h.title), maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(library.sourceOf(h.packId, h.title)),
                  onTap: () async {
                    final a = await library.read(h.packId, h.index);
                    if (a != null && context.mounted) Navigator.pop(context, (a.title, articleText(a, max: 6000)));
                  },
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel'))],
    );
  }
}

// ================================================================ latest evidence (PubMed)

class LatestEvidenceScreen extends StatefulWidget {
  final String topic;
  const LatestEvidenceScreen({super.key, required this.topic});
  @override
  State<LatestEvidenceScreen> createState() => _LatestEvidenceScreenState();
}

class _LatestEvidenceScreenState extends State<LatestEvidenceScreen> {
  late final TextEditingController _t = TextEditingController(text: widget.topic);
  List<PubmedArticle> _arts = const [];
  String _summary = '';
  bool _busy = false;
  String _msg = '';
  bool _saved = false; // showing a saved result
  bool _summaryOffline = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    if (_arts.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _loadSaved() {
    final a = Pubmed.savedArticles(_t.text);
    if (a.isNotEmpty) {
      _arts = a;
      _summary = Pubmed.savedSummary(_t.text);
      _saved = true;
    }
  }

  Future<void> _fetch() async {
    final term = _t.text.trim();
    if (term.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _msg = '';
    });
    List<PubmedArticle>? arts;
    try {
      arts = await Pubmed.fetch(term);
    } catch (_) {
      arts = null;
    }
    if (!mounted) return;
    if (arts == null) {
      // no connection: keep showing what was saved
      final s = Pubmed.savedArticles(term);
      setState(() {
        _busy = false;
        if (s.isNotEmpty) {
          _arts = s;
          _summary = Pubmed.savedSummary(term);
          _saved = true;
          _msg = 'No connection: showing what you saved earlier.';
        } else {
          _msg = 'No connection. Latest evidence needs internet.';
        }
      });
      return;
    }
    if (arts.isEmpty) {
      setState(() {
        _busy = false;
        _arts = const [];
        _summary = '';
        _msg = 'No recent PubMed abstracts found for this topic.';
      });
      return;
    }
    setState(() {
      _arts = arts!;
      _saved = false;
      _summary = '';
      _summaryOffline = false;
    });
    var summary = '';
    if (Ai.enabled) {
      final res = await Ai.run(Pubmed.summaryRequest(term, arts), context: context);
      if (!mounted) return;
      if (res.ok && res.text.trim().isNotEmpty) {
        summary = res.text.trim();
      } else if (res.offline) {
        _summaryOffline = true;
      }
    }
    await Pubmed.saveEvidence(term, arts, summary);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Latest evidence')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _t,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _fetch(),
            decoration: InputDecoration(
              labelText: tr('Topic to look up in PubMed'),
              helperText: tr("Don't type patient names or IDs."),
              suffixIcon: IconButton(tooltip: tr('Search'), icon: const Icon(Icons.search), onPressed: _busy ? null : _fetch),
            ),
          ),
          const SizedBox(height: 6),
          Text('Abstracts come from PubMed (NCBI) of the last 5 years. Only the topic words are sent.', style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg, style: theme.textTheme.bodyMedium)),
          if (_summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            AiOutputCard(
              text: _summary,
              feature: 'summary_evidence',
              footer: Text('AI summary of abstracts, verify in the source.', style: theme.textTheme.labelMedium?.copyWith(color: cs.tertiary)),
            ),
          ] else if (_arts.isNotEmpty && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_summaryOffline || !Ai.enabled ? 'AI summary is unavailable (off or offline). The abstracts are listed below.' : 'No AI summary. The abstracts are listed below.', style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
            ),
          if (_saved && _arts.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('Saved result. Press search to refresh.', style: theme.textTheme.labelSmall?.copyWith(color: cs.outline))),
          if (_arts.isNotEmpty) SectionHeader(tr('Abstracts')),
          for (final a in _arts) _artCard(context, a),
        ],
      ),
    );
  }

  Widget _artCard(BuildContext context, PubmedArticle a) {
    final theme = Theme.of(context);
    final study = [for (final t in a.types) if (t != 'Journal Article') t];
    return AppCard(
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserScreen(title: 'PMID ${a.pmid}', url: a.link))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Directionality(textDirection: TextDirection.ltr, child: m.Text(a.title, style: theme.textTheme.titleSmall)),
            const SizedBox(height: 4),
            Directionality(
              textDirection: TextDirection.ltr,
              child: m.Text('PMID ${a.pmid} · ${a.year}${a.journal.isEmpty ? '' : ' · ${a.journal}'}', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
            ),
            if (study.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, runSpacing: 0, children: [
                  for (final s in study.take(3)) Chip(visualDensity: VisualDensity.compact, label: Directionality(textDirection: TextDirection.ltr, child: m.Text(s, style: const TextStyle(fontSize: 11)))),
                ]),
              ),
            if (a.abstract.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Abstract', style: theme.textTheme.labelLarge),
                children: [Directionality(textDirection: TextDirection.ltr, child: Align(alignment: Alignment.centerLeft, child: m.Text(a.abstract, style: theme.textTheme.bodySmall?.copyWith(height: 1.4))))],
              ),
          ]),
        ),
      ),
    );
  }
}
