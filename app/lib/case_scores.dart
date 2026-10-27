import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'data.dart';
import 'i18n.dart';
import 'ui.dart';

/// A calculator result kept inside a case: the number, what it means and the items that made it, with the day and
/// time, so "why did this patient get 3?" can be answered from the case itself.
class CaseScore {
  final String id, name, value, meaning, formula, date, time;
  final List<String> items;
  const CaseScore({required this.id, required this.name, required this.value, this.meaning = '', this.formula = '', this.date = '', this.time = '', this.items = const []});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'value': value, 'meaning': meaning, 'formula': formula, 'date': date, 'time': time, 'items': items};

  factory CaseScore.fromJson(Map j) => CaseScore(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        value: '${j['value'] ?? ''}',
        meaning: '${j['meaning'] ?? ''}',
        formula: '${j['formula'] ?? ''}',
        date: '${j['date'] ?? ''}',
        time: '${j['time'] ?? ''}',
        items: [for (final e in (j['items'] is List ? j['items'] as List : const [])) '$e'],
      );
}

List<CaseScore> scoresOf(CaseRec c) => [for (final e in c.lst('scores')) CaseScore.fromJson(e)];

/// Adds a result to the case (newest last). The case is saved by the caller's store flow.
Future<void> attachScore(CaseRec c, CaseScore s) async {
  c.lst('scores').add(s.toJson());
  await store.saveCase(c);
}

CaseScore newScore({required String name, required String value, String meaning = '', String formula = '', List<String> items = const []}) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return CaseScore(
    id: 's${now.microsecondsSinceEpoch}',
    name: name,
    value: value,
    meaning: meaning,
    formula: formula,
    date: fmtDate(now),
    time: '${two(now.hour)}:${two(now.minute)}',
    items: items,
  );
}

/// "Why this number": the items behind a result and what it means.
void showScoreSheet(BuildContext context, CaseScore s, {VoidCallback? onDelete}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Directionality(textDirection: TextDirection.ltr, child: m.Text(s.name, style: Theme.of(ctx).textTheme.titleMedium)),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.ltr,
            child: m.Text(s.value, style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: Theme.of(ctx).colorScheme.primary)),
          ),
          if (s.meaning.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: m.Text(s.meaning)),
          Padding(padding: const EdgeInsets.only(top: 4), child: m.Text('${s.date} ${s.time}', style: Theme.of(ctx).textTheme.bodySmall)),
          if (s.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('What was chosen', style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final i in s.items) Padding(padding: const EdgeInsets.only(top: 4), child: Directionality(textDirection: TextDirection.ltr, child: m.Text('• $i'))),
          ],
          if (s.formula.isNotEmpty) ...[
            const SizedBox(height: 12),
            Directionality(textDirection: TextDirection.ltr, child: m.Text(s.formula, style: Theme.of(ctx).textTheme.bodySmall)),
          ],
          if (onDelete != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  onDelete();
                },
                icon: const Icon(Icons.delete_outline),
                label: Text('Remove from this case'),
              ),
            ),
        ]),
      ),
    ),
  );
}

/// The results kept in this case, on its Assessment tab.
class ScoresSection extends StatelessWidget {
  final CaseRec rec;
  final VoidCallback onChanged;
  const ScoresSection({super.key, required this.rec, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final list = scoresOf(rec);
    if (list.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.fact_check_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Scores and results in this case', style: theme.textTheme.titleSmall),
            ]),
            for (final s in list)
              InkWell(
                onTap: () => showScoreSheet(context, s, onDelete: () {
                  rec.lst('scores').removeWhere((e) => e['id'] == s.id);
                  onChanged();
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Directionality(textDirection: TextDirection.ltr, child: m.Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Directionality(textDirection: TextDirection.ltr, child: m.Text('${s.date} ${s.time}', style: theme.textTheme.bodySmall)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: m.Text(s.value, style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
                    ),
                    const Icon(Icons.chevron_right, size: 18),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
