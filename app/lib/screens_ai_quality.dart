import 'dart:math';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'ai/ai_context.dart';
import 'ai/ai_quality.dart';
import 'i18n.dart';
import 'ref_data.dart';

/// Runs the fixed golden questions against the user's own key and model and reports how many answers contained the key facts
/// and avoided the unsafe ones. Questions contain no patient data. Each question is one request to the user's own provider.
class AiQualityScreen extends StatefulWidget {
  const AiQualityScreen({super.key});
  @override
  State<AiQualityScreen> createState() => _AiQualityScreenState();
}

class _AiQualityScreenState extends State<AiQualityScreen> {
  int _count = 10;
  bool _running = false;
  bool _stop = false;
  int _done = 0;
  int _total = 0;
  List<GoldenResult> _res = const [];

  Future<void> _run() async {
    final all = [for (final q in await RefData.golden()) GoldenQ.fromJson(q)];
    // the safety traps are always included; the rest is a random sample
    final traps = all.where((q) => q.category == 'safety-trap').toList();
    final rest = all.where((q) => q.category != 'safety-trap').toList()..shuffle(Random(DateTime.now().day));
    final pick = _count >= all.length ? all : [...traps.take(min(traps.length, max(2, _count ~/ 4))), ...rest].take(_count).toList();
    setState(() {
      _running = true;
      _stop = false;
      _done = 0;
      _total = pick.length;
      _res = const [];
    });
    final r = await AiQuality.run(pick, onProgress: (d, t) {
      if (mounted) setState(() => _done = d);
    }, cancelled: () => _stop);
    if (mounted) {
      setState(() {
        _running = false;
        _res = r;
      });
    }
  }

  String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final overall = AiQuality.passRate(_res);
    final traps = AiQuality.passRate(_res, where: (q) => q.category == 'safety-trap');
    final failedReq = _res.where((r) => r.failedToAnswer).length;
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'errors', title: 'AI quality check'),
      child: Scaffold(
        appBar: AppBar(title: Text('AI quality check')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Text(
              'Sends fixed medical test questions (no patient data) to your own AI key and checks whether the answers contain the key facts and avoid unsafe statements. Use it to compare models. A pass is a keyword match, not a clinical judgement.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final n in const [10, 30, 60])
              ChoiceChip(
                key: ValueKey('qc_$n'),
                label: Text(n == 60 ? 'All 60' : '$n questions'),
                selected: _count == n,
                onSelected: _running ? null : (_) => setState(() => _count = n),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            FilledButton.icon(
              key: const ValueKey('qc_run'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text('Run the check'),
            ),
            const SizedBox(width: 8),
            if (_running) OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: () => setState(() => _stop = true), child: Text('Stop')),
          ]),
          if (_running) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total, minHeight: 8, borderRadius: BorderRadius.circular(8)),
            const SizedBox(height: 4),
            Directionality(textDirection: TextDirection.ltr, child: m.Text('$_done / $_total')),
          ],
          if (!_running && _res.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _stat(theme, 'Passed', _pct(overall))),
              const SizedBox(width: 8),
              Expanded(child: _stat(theme, 'Safety traps', _pct(traps))),
            ]),
            if (failedReq > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(trp('{n} requests failed (connection or key). They are not counted.', {'n': failedReq}), style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
              ),
            const SizedBox(height: 8),
            for (final r in _res.where((r) => !r.pass))
              Card(
                elevation: 0,
                child: ExpansionTile(
                  key: ValueKey('qc_fail_${r.q.id}'),
                  title: Directionality(textDirection: TextDirection.ltr, child: m.Text(r.q.question, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  subtitle: r.failedToAnswer ? Text('No answer') : Text(r.q.category),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.missing.isNotEmpty) Directionality(textDirection: TextDirection.ltr, child: m.Text('Missing: ${r.missing.join('  /  ')}')),
                    if (r.forbidden.isNotEmpty) Directionality(textDirection: TextDirection.ltr, child: m.Text('Said what it should not: ${r.forbidden.join('  /  ')}', style: TextStyle(color: cs.error))),
                    const SizedBox(height: 6),
                    Directionality(textDirection: TextDirection.ltr, child: m.Text(r.answer, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _stat(ThemeData theme, String label, String value) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withAlpha(110), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          m.Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: theme.textTheme.bodySmall),
        ]),
      );
}
