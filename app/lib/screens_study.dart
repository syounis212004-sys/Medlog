import 'package:flutter/material.dart' hide Text;

import 'data.dart';
import 'i18n.dart';
import 'motion.dart';
import 'screens_cases.dart';
import 'screens_extras.dart';
import 'focus.dart';
import 'review.dart';
import 'screens_reasoning.dart';
import 'screens_library.dart';
import 'screens_quiz.dart';
import 'screens_notebooks.dart';
import 'screens_trainer.dart';
import 'screens_learn.dart';
import 'screens_review.dart';
import 'screens_search.dart';
import 'search_index.dart';
import 'ui.dart';
import 'widgets.dart';

/// Home content for Study mode: practice and review, not documentation.
/// (Shift mode keeps Home short: rotation, today, quick actions.)
List<Widget> studyHomeSections(BuildContext context, {ValueChanged<int>? onOpenTab}) {
  final theme = Theme.of(context);
  final tasks = openTasks();
  final openQuestions = store.inbox.where((q) => (q['status'] ?? 'Open') != 'Answered').toList();
  final flagged = store.casesSorted().where((c) => c.review).take(3).toList();
  final pearls = [...store.listOf('pearls')]
    ..sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
  var n = 0;
  Widget st(Widget w) => FadeSlideIn(index: n++, child: w);

  final focus = buildFocus();
  final dueN = ReviewEngine.dueCount();
  final topics = searchIndex.suggestedTopics(limit: 8);
  return [
    st(SectionCard(
      title: 'Today’s focus',
      icon: Icons.flag_outlined,
      trailing: focus.length > 5
          ? TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FocusScreen())),
              child: Text(trp('All {n}', {'n': focus.length})),
            )
          : null,
      children: [
        if (focus.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('All caught up. No gaps found in your records.', style: theme.textTheme.bodySmall),
          ),
        for (final f in focus.take(5)) FocusTile(f),
      ],
    )),
    st(Row(
      children: [
        Expanded(
          child: _BigAction(
            icon: Icons.style_outlined,
            title: 'Review',
            subtitle: dueN == 0 ? tr('Nothing due') : trp('{n} due', {'n': dueN}),
            highlight: dueN > 0,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewSessionScreen())),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BigAction(
            icon: Icons.replay,
            title: 'Replay my cases',
            subtitle: trp('{n} ready', {'n': replayCandidates().length}),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReplayLibraryScreen())),
          ),
        ),
      ],
    )),
    if (ReviewEngine.hasImages())
      st(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: AppCard(
          child: ListTile(
            leading: const Icon(Icons.image_search_outlined),
            title: Text('Image review'),
            subtitle: Text('Look at your own images first, then compare with your reading'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReviewSessionScreen(kinds: {ReviewKind.image})),
            ),
          ),
        ),
      )),
    st(Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AppCard(
        child: ListTile(
          leading: const Icon(Icons.search),
          title: Text('Search everything'),
          subtitle: Text('Cases, notes, questions, pearls — Arabic and English'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
        ),
      ),
    )),
    if (topics.isNotEmpty)
      st(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 8, runSpacing: 0, children: [
          for (final t in topics)
            ActionChip(
              avatar: const Icon(Icons.tag, size: 16),
              label: Text(t),
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TopicScreen(topic: t))),
            ),
        ]),
      )),
    st(pearlPrompt(context)),
    st(Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _MissionCard(),
    )),
    st(Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: _BigAction(
              icon: Icons.timer_outlined,
              title: 'Practice presenting',
              subtitle: 'Timer and templates',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PresentationTrainerScreen())),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BigAction(
              icon: Icons.forum_outlined,
              title: 'Communication practice',
              subtitle: 'Scenarios and checklists',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunicationPracticeScreen())),
            ),
          ),
        ],
      ),
    )),
    st(Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AppCard(
        child: ListTile(
          leading: const Icon(Icons.quiz_outlined),
          title: Text('Test myself'),
          subtitle: Text('Questions made from the library articles'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuizScreen())),
        ),
      ),
    )),
    st(Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AppCard(
        child: ListTile(
          leading: const Icon(Icons.local_library_outlined),
          title: Text('Library'),
          subtitle: Text('Articles, tests, calculators — offline'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryScreen())),
        ),
      ),
    )),
    st(Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AppCard(
        child: ListTile(
          leading: const Icon(Icons.library_books_outlined),
          title: Text('Notebooks and tools'),
          subtitle: Text('Achievements, reflections, references, analytics, PDF'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotebooksScreen())),
        ),
      ),
    )),
    st(Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AppCard(
        child: ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: Text('Decision journal'),
          subtitle: Text('Why I decided, what happened, what I would change'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DecisionJournalScreen())),
        ),
      ),
    )),
    st(const Padding(padding: EdgeInsets.only(top: 10), child: CalibrationCard())),
    st(SectionCard(
      title: 'Learning tasks',
      icon: Icons.task_alt,
      trailing: TextButton.icon(
        onPressed: () => editTask(context),
        icon: const Icon(Icons.add, size: 18),
        label: Text('Add'),
      ),
      children: [
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Nothing due. Add what you want to read or practise.',
                style: theme.textTheme.bodySmall),
          ),
        for (final t in tasks.take(4)) TaskTile(t),
      ],
    )),
    st(SectionCard(
      title: 'Open questions',
      icon: Icons.help_outline,
      trailing: TextButton(
        onPressed: onOpenTab == null ? null : () => onOpenTab(3),
        child: Text('${openQuestions.length}'),
      ),
      children: [
        if (openQuestions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('No open questions.', style: theme.textTheme.bodySmall),
          ),
        for (final q in openQuestions.take(3))
          AppCard(
            child: ListTile(
              onTap: () => editQuestion(context, q),
              leading: const Icon(Icons.help_outline),
              title: Text((q['question'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
    )),
    if (flagged.isNotEmpty)
      st(SectionCard(
        title: 'Cases to review',
        icon: Icons.bookmark_border,
        children: [for (final c in flagged) CaseTile(c)],
      )),
    if (pearls.isNotEmpty)
      st(SectionCard(
        title: 'Recent pearls',
        icon: Icons.lightbulb_outline,
        children: [for (final p in pearls.take(3)) PearlCard(p)],
      )),
  ];
}

class _BigAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlight;
  final VoidCallback onTap;
  const _BigAction({required this.icon, required this.title, required this.subtitle, required this.onTap, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlight ? cs.primaryContainer : cs.secondaryContainer.withAlpha(110),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: highlight ? cs.onPrimaryContainer : cs.onSecondaryContainer),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(subtitle, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Tomorrow's mission: one sentence chosen today, shown until it is done.
class _MissionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = store.settings['mission'];
    final text = (m is Map ? (m['text'] ?? '') : '').toString();
    final done = m is Map && m['done'] == true;
    return AppCard(
      child: ListTile(
        leading: Icon(done ? Icons.check_circle : Icons.rocket_launch_outlined, color: theme.colorScheme.primary),
        title: Text(text.isEmpty ? 'Tomorrow’s mission' : text,
            style: done ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
        subtitle: Text(text.isEmpty ? 'Choose one thing to learn or practise tomorrow.' : 'Tap to change. Long-press to mark done.'),
        onLongPress: text.isEmpty
            ? null
            : () {
                store.settings['mission'] = {'text': text, 'done': !done};
                store.saveSettings();
              },
        onTap: () async {
          final res = await showFormSheet(
            context,
            title: 'Tomorrow’s mission',
            specs: const [FieldSpec('text', 'What will you do?', type: FT.multi)],
            initial: <String, dynamic>{'text': text},
          );
          if (res == null) return;
          store.settings['mission'] = {'text': (res['text'] ?? '').toString().trim(), 'done': false};
          await store.saveSettings();
        },
      ),
    );
  }
}
