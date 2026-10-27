import 'package:flutter/material.dart' hide Text;

import 'data.dart';
import 'i18n.dart';
import 'motion.dart';
import 'reasoning.dart';
import 'screens_cases.dart';
import 'ui.dart';
import 'widgets.dart';

/// Awareness card: how sure I was vs how often I was right.
class CalibrationCard extends StatelessWidget {
  const CalibrationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = calibration();
    final names = const ['Not sure', 'Fairly sure', 'Very sure'];
    final msg = switch (c.verdict) {
      'overconfident' => 'When you are very sure you are right less often than that. Pause and look for what does not fit.',
      'underconfident' => 'You are right more often than you feel when unsure. Trust your reasoning a little more.',
      'balanced' => 'Your confidence matches how often you are right. Keep recording.',
      _ => 'Record your first diagnosis, how sure you are and whether it was right. After a few cases this shows how well your confidence matches.',
    };
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.psychology_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Confidence vs accuracy', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 96, child: Text(names[i], style: theme.textTheme.bodySmall)),
                  Expanded(child: AnimatedBar(c.rows[i].n == 0 ? 0 : c.rows[i].rate, height: 8)),
                  SizedBox(
                    width: 64,
                    child: Text(
                      c.rows[i].n == 0 ? '—' : '${(c.rows[i].rate * 100).round()}% (${c.rows[i].n})',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 6),
            Text(msg, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('For awareness only. A few cases do not prove anything.',
                style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
          ],
        ),
      ),
    );
  }
}

class DecisionJournalScreen extends StatefulWidget {
  const DecisionJournalScreen({super.key});

  @override
  State<DecisionJournalScreen> createState() => _DecisionJournalScreenState();
}

class _DecisionJournalScreenState extends State<DecisionJournalScreen> {
  String _filter = '';

  Color _col(String o) => o == 'Right' ? Colors.green : (o == 'Wrong' ? Colors.red : (o == 'Partly' ? Colors.orange : Colors.grey));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = journalEntries();
    final list = _filter.isEmpty ? all : all.where((e) => e.outcome == _filter).toList();
    final acc = accuracyBySpecialty();
    return Scaffold(
      appBar: AppBar(title: Text('Decision journal')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          const CalibrationCard(),
          if (acc.isNotEmpty) ...[
            const SectionHeader('First diagnosis right, by specialty'),
            for (final e in acc.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 120, child: Text(tr(e.key), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Expanded(child: AnimatedBar(e.value, height: 8)),
                  SizedBox(width: 44, child: Text('${(e.value * 100).round()}%', textAlign: TextAlign.end)),
                ]),
              ),
          ],
          const SectionHeader('Entries'),
          Wrap(spacing: 8, children: [
            for (final f in const ['', 'Right', 'Partly', 'Wrong'])
              ChoiceChip(label: Text(f.isEmpty ? 'All' : f), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
          ]),
          if (list.isEmpty)
            const EmptyState(
              kind: EmptyKind.learn,
              title: 'No journal entries yet',
              message: 'Write “My first diagnosis” in the Learning tab of a case, or replay a case.',
            ),
          for (var i = 0; i < list.length; i++)
            FadeSlideIn(
              index: i,
              child: AppCard(
                child: ListTile(
                  leading: Icon(Icons.circle, size: 14, color: _col(list[i].outcome)),
                  title: Text(list[i].first, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    list[i].code,
                    if (list[i].date.isNotEmpty) prettyDate(list[i].date),
                    if (list[i].conf.isNotEmpty) '${list[i].conf}%',
                    if (list[i].outcome.isNotEmpty) tr(list[i].outcome),
                    if (list[i].fromReplay) tr('Replay'),
                  ].join(' • ')),
                  onTap: () {
                    final c = store.cases[list[i].caseId];
                    if (c != null) Navigator.push(context, MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: c, initialTab: 7)));
                  },
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Your own words, kept private on this phone.', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
