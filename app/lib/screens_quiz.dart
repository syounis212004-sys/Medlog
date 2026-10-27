import 'package:flutter/material.dart' hide Text;
import 'dart:math' show min;

import 'package:flutter/material.dart' as mm show Text;

import 'core_topics.dart';
import 'data.dart';
import 'i18n.dart';
import 'lib_quiz.dart';
import 'lib_user.dart';
import 'library.dart';
import 'screens_article.dart';
import 'screens_library.dart' show SourceFilterChips;
import 'ui.dart';
import 'widgets.dart';

/// Self-test from the library: choose where the questions come from (all, my rotation, my cases,
/// favorites, weak spots), a level, a course and / or a topic; answer questions made from the
/// article text, see the source, and send what you missed to review.
class QuizScreen extends StatefulWidget {
  final String? packId;
  final String? query;
  final bool autoStart;
  final QuizSource? source;
  final QuizLevel? level;
  final int? count;
  const QuizScreen(
      {super.key,
      this.packId,
      this.query,
      this.autoStart = false,
      this.source,
      this.level,
      this.count});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

enum _Phase { setup, loading, running, done }

String quizSourceLabel(QuizSource s) => switch (s) {
      QuizSource.core => 'Core 250 (recommended)',
      QuizSource.all => 'All installed articles',
      QuizSource.rotation => 'My current rotation',
      QuizSource.cases => "My cases' diagnoses",
      QuizSource.favorites => 'Favorites + recently read',
      QuizSource.weak => 'My weak spots',
      QuizSource.random => 'Random',
    };

String quizLevelLabel(QuizLevel l) => switch (l) {
      QuizLevel.easy => 'Easy',
      QuizLevel.medium => 'Medium',
      QuizLevel.hard => 'Hard',
      QuizLevel.auto => 'Auto',
    };

class _QuizScreenState extends State<QuizScreen> {
  _Phase _phase = _Phase.setup;
  String? _pack;
  late final TextEditingController _topic =
      TextEditingController(text: widget.query ?? '');
  late int _count = widget.count ?? 10;
  late QuizSource _source = widget.source ?? defaultQuizSource();
  late String _universe = studyUniverse();
  late bool _autoCards = quizAutoCards();
  final List<(QuizQ, bool)> _results = [];
  late QuizLevel _level = widget.level ?? QuizLevel.medium;
  String? _srcFilter;
  List<QuizQ> _qs = const [];
  int _i = 0;
  int? _picked;
  final List<QuizQ> _wrong = [];
  final List<Map<String, Object>> _items = [];
  final Set<String> _ignoredNow = {};
  int _right = 0;
  bool _tooFew = false;
  double _progress = 0;
  QuizSource? _fallbackFrom;
  QuizSource _usedSource = QuizSource.core;
  QuizLevel _usedLevel = QuizLevel.medium;
  List<WeakSpot> _weak = const [];

  @override
  void initState() {
    super.initState();
    _pack = widget.packId;
    _weak = weakSpots();
    if (widget.autoStart)
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  /// Source chips (WikEM / CDC / ...) for the Clinical Essentials course, or for all courses when it is installed.
  bool get _showSourceFilter =>
      library.pack(kEssentialsPackId) != null &&
      (_pack == null || _pack == kEssentialsPackId);

  Future<void> _start({List<QuizPick>? articles, int? count}) async {
    setState(() {
      _phase = _Phase.loading;
      _tooFew = false;
      _progress = 0;
    });
    var last = 0.0;
    final qs = await buildQuiz(
      packId: _pack,
      query: _topic.text.trim(),
      count: count ?? _count,
      articles: articles,
      source: _source,
      level: _level,
      sourceFilter: _showSourceFilter ? _srcFilter : null,
      onProgress: (p) {
        if (mounted && p - last >= 0.04) {
          last = p;
          setState(() => _progress = p);
        }
      },
    );
    if (!mounted) return;
    _fallbackFrom = lastQuizReport.fallbackFrom;
    _usedSource = _source;
    _usedLevel = _level;
    if (qs.length < 3) {
      setState(() {
        _phase = _Phase.setup;
        _tooFew = true;
      });
      return;
    }
    setState(() {
      _qs = qs;
      _i = 0;
      _picked = null;
      _right = 0;
      _wrong.clear();
      _items.clear();
      _results.clear();
      _ignoredNow.clear();
      _phase = _Phase.running;
    });
  }

  Future<void> _finish() async {
    await store.upsertExtra('quizlog', {
      'id': newId('qz'),
      'date': nowIso(),
      'pack': _pack ?? '',
      'query': _topic.text.trim(),
      'n': _qs.length,
      'correct': _right,
      'wrong': [for (final q in _wrong) q.title],
      'items': [..._items],
      'source': _usedSource.name,
      'level': _usedLevel.name,
    });
    _weak = weakSpots();
    if (mounted) setState(() => _phase = _Phase.done);
  }

  Future<void> _addCard(QuizQ q) async {
    final ok = await addLibraryCard(
      front: q.cardFront,
      back: q.cardBack,
      source: q.title,
      packId: q.packId,
      title: q.title,
    );
    if (mounted)
      snack(
          context,
          ok
              ? tr('Added to your review cards.')
              : tr('Already in your review cards.'));
  }

  Future<void> _ignore(QuizQ q) async {
    await ignoreQuizQuestion(q.hash);
    if (!mounted) return;
    setState(() => _ignoredNow.add(q.hash));
    snack(context, tr('This question will not be asked again.'));
  }

  void _pick(int k) {
    if (_picked != null) return;
    final q = _qs[_i];
    setState(() {
      _picked = k;
      _items.add({'p': q.packId, 't': q.title, 'ok': k == q.answer, 'g': q.group, 'k': q.kind.name});
      _results.add((q, k == q.answer));
      if (k == q.answer) {
        _right++;
      } else {
        _wrong.add(q);
      }
    });
    // every missed question becomes a review card (or comes back sooner when the card exists)
    if (k != q.answer && _autoCards) {
      missedCard(front: q.cardFront, back: q.cardBack, source: q.title, packId: q.packId, title: q.title);
    }
  }

  Future<void> _openSpot(WeakSpot s) async {
    final i = await library.indexOfTitle(s.packId, s.title);
    if (i == null || !mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ArticleScreen(packId: s.packId, index: i)));
  }

  Future<void> _quizOn(WeakSpot s) async {
    final i = await library.indexOfTitle(s.packId, s.title);
    if (i == null) return;
    _start(articles: [QuizPick(s.packId, i, s.title, 1)], count: 5);
  }

  /// Practice again on the topics (articles) missed in this test.
  void _practice(List<QuizQ> qs) {
    final seen = <String>{};
    final picks = <QuizPick>[
      for (final q in qs)
        if (seen.add('${q.packId}|${q.index}')) QuizPick(q.packId, q.index, q.title, 1)
    ];
    _start(articles: picks, count: picks.length == 1 ? 5 : min(10, picks.length * 2));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Test myself')),
      body: switch (_phase) {
        _Phase.setup => _setup(theme),
        _Phase.loading => _loading(theme),
        _Phase.running => _question(theme, cs),
        _Phase.done => _done(theme, cs),
      },
    );
  }

  Widget _loading(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(
                value: _progress <= 0 ? null : _progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 14),
            Text('Preparing your questions…',
                style: theme.textTheme.bodyMedium),
          ]),
        ),
      );

  String _sourceChipLabel(QuizSource s) => s == QuizSource.weak
      ? trp('My weak spots ({n})', {'n': _weak.length})
      : tr(quizSourceLabel(s));

  Widget _setup(ThemeData theme) {
    final packs = [
      for (final p in library.textPacks)
        if (p.kind != 'medline') p,
      ...[
        for (final p in library.textPacks)
          if (p.kind == 'medline') p
      ]
    ];
    final log = [...store.listOf('quizlog')]
      ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
            'Questions are made from the text of the articles you downloaded. After each answer you see the source sentence.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (packs.isEmpty)
          AppCard(
              child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text('Download a course first (Library → Courses).')))
        else ...[
          Text('Study universe', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(spacing: 8, children: [
            ChoiceChip(
                label: Text('Core 250 (recommended)'),
                selected: _universe == kUniverseCore,
                onSelected: (_) => _setUniverse(kUniverseCore)),
            ChoiceChip(
                label: Text('All installed articles'),
                selected: _universe == kUniverseAll,
                onSelected: (_) => _setUniverse(kUniverseAll)),
          ]),
          const SizedBox(height: 12),
          Text('Questions from', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 0, children: [
            for (final s in QuizSource.values)
              ChoiceChip(
                  label: Text(_sourceChipLabel(s)),
                  selected: _source == s,
                  onSelected: (_) => setState(() => _source = s)),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: packs.any((p) => p.id == _pack) ? _pack : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Course')),
            items: [
              DropdownMenuItem<String?>(
                  value: null, child: Text('All my courses')),
              for (final p in packs)
                DropdownMenuItem<String?>(value: p.id, child: Text(p.title)),
            ],
            onChanged: (v) => setState(() => _pack = v),
          ),
          if (_showSourceFilter) ...[
            const SizedBox(height: 8),
            Text('Source', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SourceFilterChips(
                sources: const [
                  'WikEM',
                  'CDC',
                  'NCI',
                  'Project Tulip',
                  'Wikipedia'
                ],
                selected: _srcFilter,
                onChanged: (v) => setState(() => _srcFilter = v)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _topic,
            decoration: InputDecoration(
                labelText: tr('Topic (optional)'),
                hintText: 'knee, sepsis, fracture…'),
          ),
          const SizedBox(height: 12),
          Text('Level', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(spacing: 8, children: [
            for (final l in QuizLevel.values)
              ChoiceChip(
                  label: Text(quizLevelLabel(l)),
                  selected: _level == l,
                  onSelected: (_) => setState(() => _level = l)),
          ]),
          if (_level == QuizLevel.auto)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Auto: easier for your weak spots, harder for topics you answered correctly.',
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 12),
          Text(tr('Number of questions'), style: theme.textTheme.labelLarge),
          Wrap(spacing: 8, children: [
            for (final n in const [5, 10, 20])
              ChoiceChip(
                  label: m('$n'),
                  selected: _count == n,
                  onSelected: (_) => setState(() => _count = n)),
          ]),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Add missed questions to review cards'),
              value: _autoCards,
              onChanged: (v) {
                setState(() => _autoCards = v);
                setQuizAutoCards(v);
              }),
          const SizedBox(height: 8),
          if (_tooFew)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                  'Not enough text to make questions here. Try another topic, or download more courses.',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.play_arrow),
              label: Text('Start')),
        ],
        if (_weak.isNotEmpty)
          Fold(
            id: 'qz_weak',
            title: trp('My weak spots ({n})', {'n': _weak.length}),
            icon: Icons.flag_outlined,
            initiallyOpen: true,
            children: _weakTiles(theme, 5),
          ),
        if (log.isNotEmpty)
          Fold(
            id: 'qz_log',
            title: tr('My results'),
            icon: Icons.history,
            initiallyOpen: true,
            children: [
              for (final l in log.take(8))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                      radius: 16,
                      child: m(
                          '${((l['correct'] as num) / (l['n'] as num) * 100).round()}%',
                          style: const TextStyle(fontSize: 11))),
                  title: Text(
                      '\u2066${l['correct']}/${l['n']}\u2069 • ${(l['query'] ?? '').toString().isEmpty ? (library.pack('${l['pack']}')?.title ?? tr('All my courses')) : l['query']}'),
                  subtitle: Text(prettyDate('${l['date']}'.substring(0, 10))),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _setUniverse(String u) async {
    await setStudyUniverse(u);
    if (!mounted) return;
    setState(() {
      _universe = u;
      if (_source == QuizSource.core || _source == QuizSource.all) _source = defaultQuizSource();
    });
  }

  List<Widget> _weakTiles(ThemeData theme, int max) => [
        for (final s in _weak.take(max))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Raw(stripSource(s.title), style: theme.textTheme.titleSmall),
              if (library.pack(s.packId) != null)
                _Raw(library.pack(s.packId)!.title,
                    style: theme.textTheme.bodySmall),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                    onPressed: () => _openSpot(s),
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: Text('Open article')),
                TextButton.icon(
                    onPressed: () => _quizOn(s),
                    icon: const Icon(Icons.quiz_outlined, size: 18),
                    label: Text('Quiz me on this')),
              ]),
            ]),
          ),
        if (_weak.length > max)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(trp('and {n} more', {'n': _weak.length - max}),
                  style: theme.textTheme.bodySmall)),
      ];

  String _expl(QuizQ q) => q.isTrueFalse ? '${tr('The source says')}: ${q.explanation}' : q.explanation;

  /// A plain Flutter text for values that must never be translated.
  Widget m(String s, {TextStyle? style}) => _Raw(s, style: style);

  Widget _heading(QuizQ q, ThemeData theme, ColorScheme cs) {
    final st = theme.textTheme.labelLarge?.copyWith(color: cs.primary);
    switch (q.kind) {
      case QKind.definition:
        return Text('Which topic is described here?', style: st);
      case QKind.cloze:
        return Text('Fill in the blank', style: st);
      case QKind.treatment:
        return Text(
            trp('Which of these is mentioned in the treatment of {t}?',
                {'t': q.prompt}),
            style: st);
      case QKind.symptom:
        return Text('Clinical features', style: st);
      case QKind.number:
        return Text('Fill in the number', style: st);
      case QKind.management:
        return Text('Management', style: st);
      case QKind.redflag:
        return Text('Red flags', style: st);
      case QKind.trueFalse:
        return Text('True or false?', style: st);
    }
  }

  Widget _notice(ThemeData theme) {
    final f = _fallbackFrom;
    if (f == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(Icons.info_outline, size: 18, color: theme.colorScheme.tertiary),
        const SizedBox(width: 6),
        Expanded(
            child: Text(
                trp('Not enough from {x}, mixed with other topics',
                    {'x': tr(quizSourceLabel(f))}),
                style: theme.textTheme.bodySmall)),
      ]),
    );
  }

  Widget _question(ThemeData theme, ColorScheme cs) {
    final q = _qs[_i];
    final answered = _picked != null;
    final ignored = _ignoredNow.contains(q.hash);
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_i == 0) _notice(theme),
            LinearProgressIndicator(
                value: (_i + (answered ? 1 : 0)) / _qs.length,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 4),
            Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _Raw('${_i + 1} / ${_qs.length}',
                    style: theme.textTheme.labelMedium)),
            const SizedBox(height: 6),
            _heading(q, theme, cs),
            const SizedBox(height: 8),
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: _Raw(q.stem,
                        style:
                            theme.textTheme.bodyLarge?.copyWith(height: 1.55))),
              ),
            ),
            const SizedBox(height: 8),
            for (var k = 0; k < q.options.length; k++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    backgroundColor: !answered
                        ? null
                        : k == q.answer
                            ? Colors.green.withAlpha(50)
                            : k == _picked
                                ? Colors.red.withAlpha(50)
                                : null,
                    side: BorderSide(
                        color: !answered
                            ? cs.outline
                            : (k == q.answer
                                ? Colors.green
                                : (k == _picked
                                    ? Colors.red
                                    : cs.outlineVariant)),
                        width: answered && (k == q.answer || k == _picked)
                            ? 2
                            : 1),
                  ),
                  onPressed: answered ? null : () => _pick(k),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(children: [
                      Expanded(
                          child: q.isTrueFalse
                              ? Text(q.options[k],
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: cs.onSurface))
                              : _Raw(q.options[k],
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: cs.onSurface))),
                      if (answered && k == q.answer)
                        const Icon(Icons.check_circle, color: Colors.green),
                      if (answered && k == _picked && k != q.answer)
                        const Icon(Icons.cancel, color: Colors.red),
                    ]),
                  ),
                ),
              ),
            if (answered) ...[
              const SizedBox(height: 8),
              AppCard(
                color: cs.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_picked == q.answer ? 'Correct' : 'Not quite',
                            style: theme.textTheme.titleSmall?.copyWith(
                                color: _picked == q.answer
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.w800)),
                        if (_picked == q.answer) ...[
                          const SizedBox(height: 6),
                          Directionality(
                              textDirection: TextDirection.ltr,
                              child: _Raw(_expl(q),
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(height: 1.5))),
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, children: [
                            ActionChip(
                              avatar:
                                  const Icon(Icons.article_outlined, size: 18),
                              label: _Raw(q.shownTitle),
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => ArticleScreen(
                                          packId: q.packId, index: q.index))),
                            ),
                            ActionChip(
                                avatar:
                                    const Icon(Icons.style_outlined, size: 18),
                                label: Text('Add to review cards'),
                                onPressed: () => _addCard(q)),
                            ActionChip(
                              avatar: Icon(
                                  ignored
                                      ? Icons.check
                                      : Icons.visibility_off_outlined,
                                  size: 18),
                              label: Text(
                                  ignored ? 'Ignored' : 'Ignore this question'),
                              onPressed: ignored ? null : () => _ignore(q),
                            ),
                          ]),
                        ] else
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ActionChip(
                              avatar: Icon(
                                  ignored
                                      ? Icons.check
                                      : Icons.visibility_off_outlined,
                                  size: 18),
                              label: Text(
                                  ignored ? 'Ignored' : 'Ignore this question'),
                              onPressed: ignored ? null : () => _ignore(q),
                            ),
                          ),
                      ]),
                ),
              ),
              if (_picked != q.answer) ...[
                const SizedBox(height: 8),
                _whyCard(q, theme, cs),
              ],
            ],
          ],
        ),
      ),
      // Next / Finish stays pinned at the bottom: always visible, even under a long explanation
      if (answered)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (_i + 1 >= _qs.length) {
                    _finish();
                  } else {
                    setState(() {
                      _i++;
                      _picked = null;
                    });
                  }
                },
                child: Text(_i + 1 >= _qs.length ? 'Finish' : 'Next'),
              ),
            ),
          ),
        ),
    ]);
  }

  /// After a wrong answer: where the question came from (article, section, the source sentence).
  Widget _whyCard(QuizQ q, ThemeData theme, ColorScheme cs) {
    return AppCard(
      color: cs.errorContainer.withAlpha(60),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Why did I miss this?',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.article_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
                child: _Raw(
                    q.section.trim().isEmpty
                        ? q.shownTitle
                        : '${q.shownTitle} • ${q.section.trim()}',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: cs.primary))),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(
                border: Border(left: BorderSide(color: cs.primary, width: 3))),
            child: Directionality(
                textDirection: TextDirection.ltr,
                child: _Raw(_expl(q),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5))),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            TextButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ArticleScreen(packId: q.packId, index: q.index))),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text('Open the article at this part'),
            ),
            OutlinedButton.icon(
                onPressed: () => _addCard(q),
                icon: const Icon(Icons.style_outlined, size: 18),
                label: Text('Add to review cards')),
          ]),
        ]),
      ),
    );
  }

  /// Result by topic (specialty) and the topics to practise again.
  Widget _summary(ThemeData theme, ColorScheme cs) {
    final byGroup = <String, (int, int)>{};
    for (final (q, ok) in _results) {
      final g = q.group.isEmpty ? q.shownTitle : q.group;
      final c = byGroup[g] ?? (0, 0);
      byGroup[g] = (c.$1 + (ok ? 1 : 0), c.$2 + 1);
    }
    final rows = byGroup.entries.toList()
      ..sort((a, b) => (a.value.$1 / a.value.$2).compareTo(b.value.$1 / b.value.$2));
    final missed = <String, List<QuizQ>>{};
    for (final q in _wrong) {
      (missed['${q.packId}|${q.index}'] ??= <QuizQ>[]).add(q);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Fold(
        id: 'qz_topics',
        title: tr('Results by topic'),
        icon: Icons.donut_small_outlined,
        initiallyOpen: true,
        children: [
          for (final e in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: _Raw(e.key, style: theme.textTheme.bodyMedium)),
                  _Raw('${e.value.$1} / ${e.value.$2}', style: theme.textTheme.labelLarge),
                ]),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                    value: e.value.$1 / e.value.$2,
                    minHeight: 6,
                    color: e.value.$1 == e.value.$2 ? Colors.green : (e.value.$1 / e.value.$2 < 0.5 ? Colors.red : cs.primary),
                    borderRadius: BorderRadius.circular(6)),
              ]),
            ),
        ],
      ),
      if (missed.isNotEmpty)
        Fold(
          id: 'qz_wrong',
          title: tr('Weak topics'),
          subtitle: countLabel(missed.length, 'topic'),
          icon: Icons.flag_outlined,
          initiallyOpen: true,
          children: [
            if (_autoCards)
              Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Missed questions were added to your review cards.', style: theme.textTheme.bodySmall)),
            for (final e in missed.values)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: _Raw(e.first.shownTitle),
                subtitle: _Raw('${e.first.group} • ${tr('Answer')}: ${e.first.correct}'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleScreen(packId: e.first.packId, index: e.first.index))),
                trailing: TextButton(onPressed: () => _practice(e), child: Text('Practice again')),
              ),
            Wrap(spacing: 8, children: [
              if (missed.length > 1)
                FilledButton.tonalIcon(
                    onPressed: () => _practice(_wrong), icon: const Icon(Icons.replay), label: Text('Practice all weak topics')),
              TextButton.icon(
                onPressed: () async {
                  var n = 0;
                  for (final q in _wrong) {
                    if (await addLibraryCard(front: q.cardFront, back: q.cardBack, source: q.title, packId: q.packId, title: q.title)) n++;
                  }
                  if (mounted) snack(context, trp('{n} cards added to your review.', {'n': n}));
                },
                icon: const Icon(Icons.style_outlined),
                label: Text('Add all to review cards'),
              ),
            ]),
          ],
        ),
    ]);
  }

  Widget _done(ThemeData theme, ColorScheme cs) {
    final pct = _qs.isEmpty ? 0.0 : _right / _qs.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              SizedBox(
                width: 110,
                height: 110,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                      child: CircularProgressIndicator(
                          value: pct,
                          strokeWidth: 10,
                          backgroundColor: cs.surfaceContainerHighest)),
                  _Raw('${(pct * 100).round()}%',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(height: 10),
              _Raw('$_right / ${_qs.length}',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(
                        avatar: const Icon(Icons.source_outlined, size: 16),
                        label: Text(tr(quizSourceLabel(_usedSource))),
                        visualDensity: VisualDensity.compact),
                    Chip(
                        avatar: const Icon(Icons.speed, size: 16),
                        label: Text(tr(quizLevelLabel(_usedLevel))),
                        visualDensity: VisualDensity.compact),
                  ]),
            ]),
          ),
        ),
        if (_fallbackFrom != null)
          Padding(
              padding: const EdgeInsets.only(top: 8), child: _notice(theme)),
        _summary(theme, cs),
        if (_weak.isNotEmpty)
          Fold(
            id: 'qz_weak_done',
            title: trp('My weak spots ({n})', {'n': _weak.length}),
            icon: Icons.track_changes,
            initiallyOpen: true,
            children: _weakTiles(theme, 5),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => setState(() => _phase = _Phase.setup),
                  child: Text('New test'))),
          const SizedBox(width: 10),
          Expanded(
              child: FilledButton(onPressed: _start, child: Text('Try again'))),
        ]),
      ],
    );
  }
}

/// Text that is shown exactly as it is (article words, numbers).
class _Raw extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const _Raw(this.text, {this.style});
  @override
  Widget build(BuildContext context) => mm.Text(text,
      style: style,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left);
}
