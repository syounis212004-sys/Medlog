import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as mm show Text;

import 'ai/ai_api.dart';
import 'ai/ai_context.dart';
import 'ai/ai_quiz.dart';
import 'ai/ai_study_hooks.dart' show kAiWebGroup;
import 'data.dart';
import 'i18n.dart';
import 'lib_user.dart';
import 'library.dart';
import 'screens_ai_study.dart' show WrittenAnswerScreen, openAiHub;
import 'screens_library.dart' show openArticle;
import 'ui.dart';
import 'widgets.dart';

/// "AI question bank": a separate section (never mixed with the rule-based quiz). Questions are generated
/// from library passages when AI is on and online, checked locally, saved on the phone and practised offline.

const Map<String, String> _modeLabels = {
  'all': 'All saved questions',
  'core': 'Core 250 topics',
  'course': 'One course',
  'weak': 'My weak spots',
  'topic': 'A topic',
};

const Map<String, String> _levelLabels = {'mixed': 'Mixed', 'easy': 'Easy', 'medium': 'Medium', 'hard': 'Hard'};

/// Small label that marks every AI question.
class AiBadge extends StatelessWidget {
  final String label;
  const AiBadge({super.key, this.label = 'AI-generated'});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome, size: 13, color: cs.onTertiaryContainer),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ================================================================ setup

class AiQuizScreen extends StatefulWidget {
  const AiQuizScreen({super.key});
  @override
  State<AiQuizScreen> createState() => _AiQuizScreenState();
}

class _AiQuizScreenState extends State<AiQuizScreen> {
  String _mode = 'all';
  String? _pack;
  final TextEditingController _topic = TextEditingController();
  String _level = 'mixed';
  String _style = 'any';
  int _count = 10;
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _topUp();
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _topUp() async {
    final r = await maybeTopUp();
    if (r != null && mounted) setState(() => _msg = r.accepted > 0 ? trp('{n} new AI questions saved.', {'n': r.accepted}) : null);
  }

  AiPick get _pick => AiPick(mode: _mode, packId: _pack, query: _topic.text.trim(), level: _level, style: _style, count: _count);

  Future<void> _start() async {
    setState(() => _busy = true);
    final (qs, relaxed) = await selectFromBank(_pick);
    if (!mounted) return;
    setState(() => _busy = false);
    if (qs.isEmpty) {
      setState(() => _msg = tr('No saved questions match yet. Generate some when AI is on and you are online.'));
      return;
    }
    if (relaxed) snack(context, tr('Not enough saved questions for every filter: showing the closest ones.'));
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AiSessionScreen(pick: _pick, questions: qs)));
    if (mounted) setState(() {});
  }

  Future<void> _generate() async {
    if (_mode == 'course' && _pack == null) {
      setState(() => _msg = tr('Choose a course first.'));
      return;
    }
    if (_mode == 'topic' && _topic.text.trim().isEmpty) {
      setState(() => _msg = tr('Type a topic first.'));
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final style = _style == 'any' ? 'vignette' : _style;
    final r = await generateMore(_mode, packId: _pack, query: _topic.text.trim(), style: style, level: _level, count: _count);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = r.disabled
          ? tr('AI is off. Turn it on in Settings to generate questions.')
          : r.offline
              ? tr('You are offline: practising from your saved questions.')
              : r.capped
                  ? tr('Daily limit of AI requests reached. Try again tomorrow.')
                  : r.error != null && r.generated == 0
                      ? '${tr('Could not generate questions now. Your saved questions still work.')} (${r.error})'
                      : trp('{a} saved, {d} rejected by the checks.', {'a': r.accepted, 'd': r.generated - r.accepted});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bank = aiBank();
    final seen = bank.fold<int>(0, (n, q) => n + q.seen);
    final right = bank.fold<int>(0, (n, q) => n + q.correct);
    final st = aiStats();
    final gen = (st['generated'] as num?)?.toInt() ?? 0;
    final on = Ai.enabled;
    final packs = [for (final p in library.textPacks) if (p.kind != 'user') p];
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'quiz', title: 'AI question bank'),
      child: Scaffold(
      appBar: AppBar(
        title: const Text('AI question bank'),
        actions: [IconButton(tooltip: tr('Practice history'), icon: const Icon(Icons.history), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiHistoryScreen())))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(on ? Icons.auto_awesome : Icons.cloud_off_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(on
                      ? 'AI suggestions are on. New questions need internet; saved questions work offline.'
                      : 'AI is off/offline: practising from your saved questions')),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text('Questions are written by AI from library passages and checked by the app. They may still contain mistakes: every question shows its source sentence. AI never changes your records.', style: theme.textTheme.bodySmall),
        const SectionHeader('Saved questions'),
        Text(trp('{n} saved', {'n': bank.length}) + (seen > 0 ? ' · ' + trp('{p}% correct so far', {'p': (right * 100 / seen).round()}) : '')),
        if (gen > 0) Text(trp('Generated {g}, accepted {a} ({d}% rejected by the checks)', {'g': gen, 'a': (st['accepted'] as num?)?.toInt() ?? 0, 'd': (aiDropRate() * 100).round()}), style: theme.textTheme.bodySmall),
        const SectionHeader('Practise'),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final e in _modeLabels.entries) ChoiceChip(label: Text(e.value), selected: _mode == e.key, onSelected: (_) => setState(() => _mode = e.key)),
        ]),
        if (_mode == 'course') ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _pack,
            hint: Text('Choose a course'),
            items: [for (final p in packs) DropdownMenuItem(value: p.id, child: mm.Text(p.title, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _pack = v),
          ),
        ],
        if (_mode == 'topic') ...[
          const SizedBox(height: 8),
          TextField(controller: _topic, decoration: InputDecoration(labelText: tr('Topic, e.g. pneumonia'), border: const OutlineInputBorder())),
        ],
        const SizedBox(height: 12),
        Text('Difficulty', style: theme.textTheme.labelLarge),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final e in _levelLabels.entries) ChoiceChip(label: Text(e.value), selected: _level == e.key, onSelected: (_) => setState(() => _level = e.key)),
        ]),
        const SizedBox(height: 8),
        Text('Style', style: theme.textTheme.labelLarge),
        Wrap(spacing: 8, runSpacing: 4, children: [
          ChoiceChip(label: Text('Any'), selected: _style == 'any', onSelected: (_) => setState(() => _style = 'any')),
          for (final e in kAiStyles.entries) ChoiceChip(label: Text(e.value), selected: _style == e.key, onSelected: (_) => setState(() => _style = e.key)),
        ]),
        const SizedBox(height: 8),
        Text('Number of questions', style: theme.textTheme.labelLarge),
        Wrap(spacing: 8, children: [
          for (final n in const [5, 10, 15]) ChoiceChip(label: mm.Text('$n'), selected: _count == n, onSelected: (_) => setState(() => _count = n)),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _busy ? null : _start, icon: const Icon(Icons.play_arrow), label: Text('Start practice')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy || !on ? null : _generate,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
          label: Text('Generate more when online'),
        ),
        if (!on) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Turn AI on in Settings to generate new questions.', style: theme.textTheme.bodySmall)),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, style: TextStyle(color: theme.colorScheme.primary))),
        const SectionHeader('Options'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Add missed questions to review cards'),
          value: quizAutoCards(),
          onChanged: (v) async {
            await setQuizAutoCards(v);
            if (mounted) setState(() {});
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Check each new question with a second AI pass'),
          subtitle: Text('Uses more requests; rejects questions where the check disagrees.'),
          value: aiVerifyOn(),
          onChanged: (v) async {
            await setAiVerify(v);
            if (mounted) setState(() {});
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Top up the bank when low'),
          subtitle: Text('When you open this screen online and fewer than 20 questions are saved.'),
          value: aiTopUpOn(),
          onChanged: (v) async {
            await setAiTopUp(v);
            if (mounted) setState(() {});
          },
        ),
        Text(trp('AI requests today: {n} of {c}', {'n': aiRequestsToday(), 'c': aiDailyCap()}), style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        AppCard(
          child: ListTile(
            key: const ValueKey('aiBankToHub'),
            leading: const Icon(Icons.school_outlined),
            title: Text('More AI study tools'),
            subtitle: Text('Viva / OSCE, teach me, pre-shift quiz, case of the day, guideline check'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openAiHub(context),
          ),
        ),
      ]),
    ));
  }
}

// ================================================================ session

class AiSessionScreen extends StatefulWidget {
  final AiPick pick;
  final List<AiQ> questions;
  const AiSessionScreen({super.key, required this.pick, required this.questions});
  @override
  State<AiSessionScreen> createState() => _AiSessionScreenState();
}

class _AiSessionScreenState extends State<AiSessionScreen> {
  int _i = 0;
  int? _picked;
  bool _revealed = false; // short answer / after answering
  bool _done = false;
  final List<(AiQ, bool)> _results = [];
  String? _explain;
  bool _explaining = false;

  AiQ get _q => widget.questions[_i];

  Future<void> _answer(bool ok, {int? picked}) async {
    final q = _q;
    setState(() {
      _picked = picked ?? -1;
      _revealed = true;
      _results.add((q, ok));
    });
    await aiRecord(q, ok);
    if (!ok) {
      final made = await aiMissToCard(q);
      if (made && mounted) snack(context, tr('Added to your review cards.'));
    }
  }

  Future<void> _next() async {
    if (_i + 1 >= widget.questions.length) {
      await aiSaveSession(pick: widget.pick, results: _results);
      if (mounted) setState(() => _done = true);
    } else {
      setState(() {
        _i++;
        _picked = null;
        _revealed = false;
        _explain = null;
      });
    }
  }

  Future<void> _flag() async {
    await aiFlag(_q);
    if (mounted) snack(context, tr('Flagged: this question will not be asked again.'));
  }

  Future<void> _card() async {
    final q = _q;
    final ok = await addLibraryCard(front: q.cardFront, back: q.cardBack, source: q.title, packId: q.packId, title: q.title);
    if (mounted) snack(context, ok ? tr('Added to your review cards.') : tr('Already in your review cards.'));
  }

  Future<void> _explainIt() async {
    setState(() => _explaining = true);
    final q = _q;
    final picked = _picked != null && _picked! >= 0 && _picked! < q.options.length ? q.options[_picked!] : tr('(did not know)');
    final r = await explainMistake(q, picked);
    if (!mounted) return;
    setState(() {
      _explaining = false;
      _explain = r.ok && r.text.trim().isNotEmpty ? r.text.trim() : tr('No explanation available now (offline or AI off). The source sentence above is the reference.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AiContextScope(ctx: const AiScreenContext(kind: 'quiz', title: 'AI practice'), child: _body(context));
  }

  Widget _body(BuildContext context) {
    if (_done) return _results_(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = _q;
    final ok = _results.isNotEmpty && _revealed && _results.last.$1 == q ? _results.last.$2 : false;
    return Scaffold(
      appBar: AppBar(title: Text(trp('Question {i} of {n}', {'i': _i + 1, 'n': widget.questions.length}))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        LinearProgressIndicator(value: (_i + (_revealed ? 1 : 0)) / widget.questions.length),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AiBadge(label: q.isWeb ? kAiWebGroup : 'AI-generated'),
          mm.Text(q.shownTitle, style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 12),
        mm.Text(q.stem, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (q.isShort) ...[
          if (!_revealed) FilledButton(onPressed: () => setState(() => _revealed = true), child: Text('Show the answer')),
        ] else
          for (var i = 0; i < q.options.length; i++) _option(q, i, cs),
        if (_revealed) ...[
          const SizedBox(height: 12),
          if (q.isShort) _shortResult(q),
          if (!q.isShort)
            Row(children: [
              Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : cs.error),
              const SizedBox(width: 8),
              Expanded(child: Text(ok ? 'Correct' : 'Not quite')),
            ]),
          const SizedBox(height: 8),
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (q.isShort) mm.Text(q.answerText, style: const TextStyle(fontWeight: FontWeight.bold)),
                mm.Text(q.explanation),
                const SizedBox(height: 8),
                Text(q.isWeb ? 'Cited fact' : 'Source sentence', style: theme.textTheme.labelLarge),
                mm.Text('“${q.quote}”', style: const TextStyle(fontStyle: FontStyle.italic)),
                mm.Text('${q.shownTitle}${q.section.isEmpty ? '' : ' · ${q.section}'}', style: theme.textTheme.bodySmall),
                if (q.isWeb && q.citeUrl.isNotEmpty) mm.Text(q.citeUrl, style: theme.textTheme.bodySmall?.copyWith(color: cs.primary), textDirection: TextDirection.ltr),
              ]),
            ),
          ),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (q.packId.isNotEmpty) TextButton.icon(onPressed: () => openArticle(context, q.packId, q.index), icon: const Icon(Icons.article_outlined), label: Text('Open the article')),
            if (q.quote.length >= 25)
              TextButton.icon(
                key: const ValueKey('writeAnswer'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WrittenAnswerScreen(question: q.stem, reference: '${q.quote}\n${q.explanation}\n${q.isShort ? q.answerText : q.correctText}', sourceLabel: q.shownTitle))),
                icon: const Icon(Icons.edit_note, size: 20),
                label: Text('Write my answer (AI grades)'),
              ),
            TextButton.icon(onPressed: _card, icon: const Icon(Icons.style_outlined), label: Text('Add to review cards')),
            TextButton.icon(onPressed: _flag, icon: const Icon(Icons.flag_outlined), label: Text('Flag as wrong')),
            if (!ok && Ai.enabled)
              TextButton.icon(onPressed: _explaining ? null : _explainIt, icon: const Icon(Icons.auto_awesome, size: 18), label: Text('Explain my mistake')),
          ]),
          if (_explaining) const LinearProgressIndicator(),
          if (_explain != null)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const AiBadge(), const SizedBox(height: 6), mm.Text(_explain!)]),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _next, child: Text(_i + 1 >= widget.questions.length ? 'Finish' : 'Next question')),
        ],
      ]),
    );
  }

  Widget _shortResult(AiQ q) {
    if (_results.isNotEmpty && _results.last.$1 == q && _picked != null) return const SizedBox.shrink();
    return Wrap(spacing: 8, children: [
      FilledButton(onPressed: () => _answer(true), child: Text('I knew it')),
      OutlinedButton(onPressed: () => _answer(false), child: Text('I missed it')),
    ]);
  }

  Widget _option(AiQ q, int i, ColorScheme cs) {
    final answered = _revealed;
    final isKey = i == q.answer;
    final isPick = _picked == i;
    Color? bg;
    if (answered && isKey) bg = Colors.green.withValues(alpha: 0.18);
    if (answered && isPick && !isKey) bg = cs.errorContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: bg ?? cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: isPick ? cs.primary : cs.outlineVariant)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: answered ? null : () => _answer(i == q.answer, picked: i),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              mm.Text(q.isTf ? '' : '${String.fromCharCode(65 + i)}.  '),
              Expanded(child: mm.Text(q.options[i])),
              if (answered && isKey) const Icon(Icons.check, color: Colors.green, size: 20),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _results_(BuildContext context) {
    final theme = Theme.of(context);
    final right = _results.where((r) => r.$2).length;
    final by = <String, List<bool>>{};
    for (final r in _results) {
      (by[r.$1.topic] ??= []).add(r.$2);
    }
    final topics = by.entries.toList()..sort((a, b) => (a.value.where((x) => x).length / a.value.length).compareTo(b.value.where((x) => x).length / b.value.length));
    final missed = [for (final r in _results) if (!r.$2) r.$1];
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const AiBadge(),
        const SizedBox(height: 8),
        mm.Text('$right / ${_results.length}', style: theme.textTheme.displaySmall),
        const SectionHeader('By topic'),
        for (final t in topics)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: mm.Text(t.key),
            trailing: mm.Text('${t.value.where((x) => x).length}/${t.value.length}'),
          ),
        if (missed.isNotEmpty) ...[
          const SectionHeader('To revise'),
          for (final q in missed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: mm.Text(q.stem, maxLines: 3, overflow: TextOverflow.ellipsis),
              subtitle: mm.Text(q.shownTitle),
              onTap: q.packId.isEmpty ? null : () => openArticle(context, q.packId, q.index),
            ),
        ],
        const SizedBox(height: 12),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text('Done')),
      ]),
    );
  }
}

// ================================================================ history

class AiHistoryScreen extends StatelessWidget {
  const AiHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final log = [...store.listOf(kAiLog)]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    final flags = store.listOf(kAiFlags).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Practice history')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (log.isEmpty) Text('No AI practice sessions yet.'),
        for (final r in log)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_awesome),
            title: mm.Text('${r['correct']} / ${r['n']}'),
            subtitle: mm.Text('${'${r['date']}'.split('T').first} · ${tr(_modeLabels['${r['mode']}'] ?? 'All')}${'${r['query']}'.isEmpty ? '' : ' · ${r['query']}'}'),
          ),
        if (flags > 0) Padding(padding: const EdgeInsets.only(top: 12), child: Text(trp('{n} questions flagged as wrong and excluded.', {'n': flags}))),
      ]),
    );
  }
}
