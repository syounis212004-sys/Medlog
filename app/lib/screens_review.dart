import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'data.dart';
import 'focus.dart';
import 'i18n.dart';
import 'motion.dart';
import 'review.dart';
import 'screens_cases.dart';
import 'screens_extras.dart';
import 'screens_learn.dart';
import 'screens_privacy.dart';
import 'ui.dart';

// ================================================================ review session

/// "3 / 10" always reads left to right, also in the Arabic app.
Widget _ltrNum(String s, TextStyle? style) =>
    Directionality(textDirection: TextDirection.ltr, child: m.Text(s, style: style));

class ReviewSessionScreen extends StatefulWidget {
  final String? topic;
  final Set<ReviewKind>? kinds;
  const ReviewSessionScreen({super.key, this.topic, this.kinds});

  @override
  State<ReviewSessionScreen> createState() => _ReviewSessionScreenState();
}

class _ReviewSessionScreenState extends State<ReviewSessionScreen> {
  late List<ReviewItem> _queue = ReviewEngine.due(topic: widget.topic, kinds: widget.kinds);
  final List<ReviewItem> _requeued = [];
  int _done = 0;
  bool _show = false;
  final List<int> _grades = [];
  late final int _start = _queue.length;

  ReviewItem? get _cur => _queue.isEmpty ? null : _queue.first;

  Future<void> _grade(int g) async {
    final it = _cur!;
    await ReviewEngine.grade(it, g);
    setState(() {
      _queue.removeAt(0);
      _grades.add(g);
      _done++;
      if (g == 0 && !_requeued.contains(it)) {
        _requeued.add(it);
        _queue.add(it); // once more at the end of this session
      }
      _show = false;
    });
  }

  String _label(int g) {
    final it = _cur!;
    final d = ReviewEngine.daysFor(it, g);
    return d == 0 ? tr('today') : trp('{n}d', {'n': d});
  }

  IconData _icon(ReviewKind k) {
    switch (k) {
      case ReviewKind.caseRecall:
        return Icons.folder_copy_outlined;
      case ReviewKind.learned:
        return Icons.school_outlined;
      case ReviewKind.mistake:
        return Icons.report_gmailerrorred_outlined;
      case ReviewKind.question:
        return Icons.help_outline;
      case ReviewKind.note:
        return Icons.sticky_note_2_outlined;
      case ReviewKind.pearl:
        return Icons.lightbulb_outline;
      case ReviewKind.image:
        return Icons.image_outlined;
      case ReviewKind.library:
        return Icons.local_library_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final it = _cur;
    return Scaffold(
      appBar: AppBar(
        title: Text('Review'),
        actions: [
          if (_start > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Center(child: _ltrNum('${math.min(_done + 1, _start)} / $_start', theme.textTheme.labelLarge)),
            ),
        ],
      ),
      body: it == null
          ? _summary(context)
          : Column(
              children: [
                if (_start > 0) AnimatedBar(_done / (_start + _requeued.length), height: 4),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    ),
                    child: ListView(
                      key: ValueKey('${it.key}_${_done}'),
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(children: [
                          Icon(_icon(it.kind), size: 18, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(it.source, style: theme.textTheme.labelLarge?.copyWith(color: cs.primary)),
                        ]),
                        const SizedBox(height: 10),
                        AppCard(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (it.imageFile != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        height: 280,
                                        width: double.infinity,
                                        child: InteractiveViewer(
                                          maxScale: 5,
                                          child: Image.file(
                                            File(store.imagePath(it.imageFile!)),
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                DirText(it.front, style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w500)),
                                const Divider(height: 28),
                                Text(it.prompt, style: theme.textTheme.titleMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _show
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: AppCard(
                                    color: cs.primaryContainer.withAlpha(110),
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: DirText(it.back, style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w500)),
                                    ),
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: !_show
                        ? SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => setState(() => _show = true),
                              icon: const Icon(Icons.visibility_outlined),
                              label: Text('Show answer'),
                            ),
                          )
                        : Row(
                            children: [
                              for (final g in const [0, 1, 2, 3])
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 3),
                                    child: FilledButton.tonal(
                                      onPressed: () => _grade(g),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                                        backgroundColor: [cs.errorContainer, cs.tertiaryContainer, cs.primaryContainer, cs.secondaryContainer][g],
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(const ['Again', 'Hard', 'Good', 'Easy'][g],
                                              style: const TextStyle(fontWeight: FontWeight.w700)),
                                          Text(_label(g), style: const TextStyle(fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final st = ReviewEngine.stats();
    final good = _grades.where((g) => g >= 2).length;
    return EmptyState(
      kind: EmptyKind.learn,
      title: _grades.isEmpty ? 'Nothing to review now' : 'Review finished',
      message: _grades.isEmpty
          ? 'Cards appear here from what you write: learning points, mistakes, answered questions, notes and pearls.'
          : '${trp('{a} of {b} remembered well', {'a': good, 'b': _grades.length})}\n${trp('{n} items in your review deck', {'n': st['started']!})}',
      action: FilledButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.check),
        label: Text('Done', style: theme.textTheme.labelLarge),
      ),
    );
  }
}

// ================================================================ replay of my own cases

class _ReplayStage {
  final String title;
  final String info;
  final String prompt;
  const _ReplayStage(this.title, this.info, this.prompt);
}

List<_ReplayStage> _stagesFor(CaseRec c) {
  final out = <_ReplayStage>[];
  String lines(List<String> l) => l.where((e) => e.trim().isNotEmpty).join('\n');
  final who = [c.s('ageGroup'), c.s('sex'), c.s('setting')].where((e) => e.isNotEmpty).map(tr).join(' • ');
  final p1 = lines([who, c.s('cc'), c.s('hpi'), c.s('pmh').isEmpty ? '' : '${tr('Past medical history')}: ${c.s('pmh')}',
    c.s('drugs').isEmpty ? '' : '${tr('Drug history (name, dose)')}: ${c.s('drugs')}']);
  if (p1.trim().isNotEmpty) out.add(_ReplayStage('Presentation', p1, 'What is your differential diagnosis at this point?'));
  final vit = [['BP', 'v_bp'], ['HR', 'v_hr'], ['Temp', 'v_temp'], ['RR', 'v_rr'], ['SpO2', 'v_spo2'], ['RBS', 'v_rbs']]
      .where((e) => c.s(e[1]).trim().isNotEmpty).map((e) => '${e[0]} ${c.s(e[1])}').join(', ');
  final p2 = lines([vit, c.s('examGeneral'), c.s('examSystemic'), c.s('examFocused')]);
  if (p2.trim().isNotEmpty) out.add(_ReplayStage('Examination', p2, 'Update your thinking. What would you investigate next?'));
  final inv = c.lst('inv').map((i) => '${i['name'] ?? ''}${(i['result'] ?? '').toString().isEmpty ? '' : ': ${i['result']}'}').join('\n');
  if (inv.trim().isNotEmpty) out.add(_ReplayStage('Investigations', inv, 'How do the results change your diagnosis?'));
  return out;
}

class OwnReplayScreen extends StatefulWidget {
  final CaseRec rec;
  const OwnReplayScreen({super.key, required this.rec});

  @override
  State<OwnReplayScreen> createState() => _OwnReplayScreenState();
}

class _OwnReplayScreenState extends State<OwnReplayScreen> {
  late final List<_ReplayStage> _stages = _stagesFor(widget.rec);
  int _i = 0;
  final List<String> _answers = [];
  final List<int> _conf = [];
  final TextEditingController _c = TextEditingController();
  int _level = 0; // 0 none, 1 low, 2 medium, 3 high
  bool _reveal = false;
  String _grade = '';
  bool _saved = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _next() {
    _answers.add(_c.text.trim());
    _conf.add(const [0, 30, 60, 85][_level]);
    _c.clear();
    _level = 0;
    if (_i + 1 >= _stages.length) {
      setState(() => _reveal = true);
    } else {
      setState(() => _i++);
    }
  }

  Future<void> _finish() async {
    if (_saved) return;
    _saved = true;
    final c = widget.rec;
    await store.upsertExtra('replays', {
      'id': newId('rp'),
      'caseId': c.id,
      'code': c.s('code'),
      'specialty': c.s('specialty'),
      'date': todayStr(),
      'answers': _answers,
      'conf': _conf,
      'grade': _grade,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = widget.rec;
    if (_stages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Replay')),
        body: const EmptyState(kind: EmptyKind.cases, title: 'Not enough recorded to replay this case'),
      );
    }
    if (_reveal) return _revealView(context);
    final st = _stages[_i];
    return Scaffold(
      appBar: AppBar(
        title: Text('${tr('Replay')} • ${c.s('code')}'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Center(child: _ltrNum('${_i + 1} / ${_stages.length}', theme.textTheme.labelLarge)),
          ),
        ],
      ),
      body: Column(
        children: [
          AnimatedBar((_i + 1) / (_stages.length + 1), height: 4),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: ListView(
                key: ValueKey(_i),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(st.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DirText(st.info, style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(st.prompt, style: theme.textTheme.titleMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _c,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: tr('Your answer')),
                  ),
                  const SizedBox(height: 12),
                  Text('How sure are you?', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    for (final e in const [[1, 'Not sure'], [2, 'Fairly sure'], [3, 'Very sure']])
                      ChoiceChip(
                        label: Text(e[1] as String),
                        selected: _level == e[0],
                        onSelected: (_) => setState(() => _level = e[0] as int),
                      ),
                  ]),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_i + 1 >= _stages.length ? 'Reveal what I recorded' : 'Next'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _revealView(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = widget.rec;
    Widget block(String title, String body) => body.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.labelLarge?.copyWith(color: cs.primary)),
                    const SizedBox(height: 4),
                    DirText(body, style: TextStyle(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          );
    final dx = c.s('finalDx').trim().isNotEmpty ? c.s('finalDx') : c.s('workingDx');
    return Scaffold(
      appBar: AppBar(title: Text('${tr('Replay')} • ${c.s('code')}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('You said', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (var i = 0; i < _answers.length; i++)
            block('${tr(_stages[i].title)}${_conf[i] > 0 ? ' • ${_conf[i]}%' : ''}', _answers[i].isEmpty ? '—' : _answers[i]),
          const Divider(height: 28),
          Text('What I recorded', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          block(tr('Final diagnosis'), dx),
          block(tr('Differential diagnosis (most likely first)'), c.s('ddx')),
          block(tr('Clinical reasoning: what supports / argues against?'), c.s('reasoning')),
          block(tr('What changed my diagnosis?'), c.s('whatChanged')),
          block(tr('What I learned'), c.s('learned')),
          block(tr('Mistakes / near-misses (mine or others) — for learning'), c.s('mistakes')),
          const SizedBox(height: 8),
          Text('Compared with what I recorded, my thinking was…', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final g in const ['Matched', 'Partly', 'Missed'])
              ChoiceChip(label: Text(g), selected: _grade == g, onSelected: (_) => setState(() => _grade = g)),
          ]),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _grade.isEmpty
                ? null
                : () async {
                    await _finish();
                    if (context.mounted) Navigator.pop(context);
                  },
            icon: const Icon(Icons.check),
            label: Text('Save and finish'),
          ),
        ],
      ),
    );
  }
}

class ReplayLibraryScreen extends StatelessWidget {
  const ReplayLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final list = replayCandidates();
    return Scaffold(
      appBar: AppBar(title: Text('Replay my cases')),
      body: list.isEmpty
          ? const EmptyState(
              kind: EmptyKind.cases,
              title: 'No case ready to replay',
              message: 'A case needs a story (complaint or history) and a diagnosis.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                for (var i = 0; i < list.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: AppCard(
                      child: ListTile(
                        leading: SpecialtyAvatar(list[i].s('specialty'), size: 38),
                        title: Text('${list[i].s('code')} • ${list[i].title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(lastReplayOf(list[i].id).isEmpty
                            ? tr('Never replayed')
                            : '${tr('Last replay')}: ${prettyDate(lastReplayOf(list[i].id))}'),
                        trailing: const Icon(Icons.play_arrow_rounded),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => OwnReplayScreen(rec: list[i]))),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ================================================================ focus

({String title, String subtitle}) focusText(FocusItem f) {
  final id = f.id;
  final code = f.title;
  if (id == 'review') return (title: tr('Review what you wrote'), subtitle: trp('{n} due', {'n': f.subtitle}));
  if (id.startsWith('draft:')) return (title: trp('Finish draft {code}', {'code': code}), subtitle: f.subtitle);
  if (id.startsWith('pend:')) return (title: trp('Result pending in {code}', {'code': code}), subtitle: f.subtitle);
  if (id.startsWith('dx:')) return (title: trp('Add a diagnosis to {code}', {'code': code}), subtitle: f.subtitle);
  if (id.startsWith('learn:')) return (title: trp('What did you learn from {code}?', {'code': code}), subtitle: f.subtitle);
  if (id.startsWith('cq:')) return (title: trp('Unanswered question in {code}', {'code': code}), subtitle: f.subtitle);
  if (id.startsWith('proc:')) return (title: trp('Move beyond observing: {name}', {'name': tr(code)}), subtitle: tr(f.subtitle));
  if (id.startsWith('priv:')) return (title: trp('Possible identifiers in {code}', {'code': code}), subtitle: trp('{n} found', {'n': f.subtitle}));
  if (id.startsWith('replay:')) return (title: trp('Replay case {code}', {'code': code}), subtitle: f.subtitle);
  if (id == 'pearl') return (title: tr('One pearl a day'), subtitle: tr('Write the one thing you learned today.'));
  return (title: f.title, subtitle: tr(f.subtitle));
}

IconData focusIcon(FocusItem f) {
  switch (f.key) {
    case 'task':
      return Icons.task_alt;
    case 'feedback':
      return Icons.record_voice_over_outlined;
    case 'review':
      return Icons.style_outlined;
    case 'draft':
      return Icons.edit_note;
    case 'pending':
      return Icons.hourglass_empty;
    case 'dx':
      return Icons.psychology_outlined;
    case 'learn':
      return Icons.school_outlined;
    case 'question':
      return Icons.help_outline;
    case 'proc':
      return Icons.healing_outlined;
    case 'pearl':
      return Icons.lightbulb_outline;
    case 'evidence':
      return Icons.menu_book_outlined;
    case 'replay':
      return Icons.replay;
    case 'privacy':
      return Icons.privacy_tip_outlined;
    default:
      return Icons.flag_outlined;
  }
}

/// Hooks other screens register (feedback screen, evidence screen, procedures tab).
void Function(BuildContext)? openFeedbackHook;
void Function(BuildContext)? openEvidenceHook;
void Function()? openProceduresTabHook;

void runFocus(BuildContext context, FocusItem f) {
  switch (f.action) {
    case FocusAction.openCase:
      final c = store.cases[f.ref];
      if (c != null) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: c, initialTab: f.tab)));
      }
      return;
    case FocusAction.openTask:
      final t = store.listOf('tasks').cast<J?>().firstWhere((e) => e!['id'] == f.ref, orElse: () => null);
      editTask(context, t);
      return;
    case FocusAction.openQuestion:
      final q = store.inbox.cast<J?>().firstWhere((e) => e!['id'] == f.ref, orElse: () => null);
      editQuestion(context, q);
      return;
    case FocusAction.startReview:
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewSessionScreen()));
      return;
    case FocusAction.openFeedback:
      openFeedbackHook?.call(context);
      return;
    case FocusAction.addPearl:
      editPearl(context);
      return;
    case FocusAction.openProcedures:
      openProceduresTabHook?.call();
      return;
    case FocusAction.openEvidence:
      openEvidenceHook?.call(context);
      return;
    case FocusAction.privacyCheck:
      final pc = store.cases[f.ref];
      if (pc != null) Navigator.push(context, MaterialPageRoute(builder: (_) => PrivacyCheckScreen(rec: pc)));
      return;
    case FocusAction.replayCase:
      final c = store.cases[f.ref];
      if (c != null) Navigator.push(context, MaterialPageRoute(builder: (_) => OwnReplayScreen(rec: c)));
      return;
  }
}

class FocusTile extends StatelessWidget {
  final FocusItem f;
  const FocusTile(this.f, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = focusText(f);
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: f.weight >= 70 ? cs.errorContainer : cs.primaryContainer,
          foregroundColor: f.weight >= 70 ? cs.onErrorContainer : cs.onPrimaryContainer,
          child: Icon(focusIcon(f), size: 20),
        ),
        title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: t.subtitle.isEmpty ? null : Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => runFocus(context, f),
      ),
    );
  }
}

/// Single-line version of [FocusTile] for Home: one 48 dp row per gap.
class FocusRow extends StatelessWidget {
  final FocusItem f;
  const FocusRow(this.f, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = focusText(f);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final urgent = f.weight >= 70;
    return InkWell(
      onTap: () => runFocus(context, f),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(focusIcon(f), size: 20, color: urgent ? cs.error : cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (t.subtitle.isNotEmpty) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.28),
                  child: Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ),
              ],
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final list = buildFocus();
    return Scaffold(
      appBar: AppBar(title: Text('Today’s focus')),
      body: list.isEmpty
          ? const EmptyState(kind: EmptyKind.generic, title: 'All caught up', message: 'No gaps found in your records.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                for (var i = 0; i < list.length; i++) FadeSlideIn(index: i, child: FocusTile(list[i])),
              ],
            ),
    );
  }
}
