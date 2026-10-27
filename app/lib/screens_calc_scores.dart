part of 'screens_calc.dart';

/// Generic calculator for the data-driven scores (assets/data/scores.json).
class ScoreCalc extends StatefulWidget {
  final ScoreDef def;
  const ScoreCalc({super.key, required this.def});
  @override
  State<ScoreCalc> createState() => _ScoreCalcState();
}

class _ScoreCalcState extends State<ScoreCalc> {
  final Map<String, dynamic> _picks = {};
  final Map<String, TextEditingController> _ctl = {};

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _ltr(String s, {TextStyle? style}) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(alignment: Alignment.centerLeft, child: mm.Text(s, style: style)),
      );

  Widget _input(ScoreInput i) {
    final theme = Theme.of(context);
    switch (i.type) {
      case 'bool':
        return CheckboxListTile(
          key: ValueKey('sc_${widget.def.id}_${i.id}'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Directionality(textDirection: TextDirection.ltr, child: mm.Text(i.label)),
          value: _picks[i.id] == true,
          onChanged: (v) => setState(() => _picks[i.id] = v == true),
        );
      case 'number':
        final c = _ctl.putIfAbsent(i.id, () => TextEditingController());
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            key: ValueKey('sc_${widget.def.id}_${i.id}'),
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: i.unit.isEmpty ? i.label : '${i.label} (${i.unit})'),
            onChanged: (v) => setState(() => _picks[i.id] = double.tryParse(v.trim().replaceAll(',', '.'))),
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _ltr(i.unit.isEmpty ? i.label : '${i.label}  [${i.unit}]', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (var k = 0; k < i.options.length; k++)
              InkWell(
                key: ValueKey('sc_${widget.def.id}_${i.id}_$k'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _picks[i.id] = k),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: _picks[i.id] == k ? theme.colorScheme.primaryContainer.withAlpha(140) : null,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _picks[i.id] == k ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Icon(_picks[i.id] == k ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Directionality(textDirection: TextDirection.ltr, child: mm.Text('${i.options[k].label}   (${_pts(i.options[k].points)})'))),
                  ]),
                ),
              ),
          ]),
        );
    }
  }

  /// What was chosen for each question, for the case record.
  List<String> _items() {
    final d = widget.def;
    final out = <String>[];
    for (final i in d.inputs) {
      final v = _picks[i.id];
      switch (i.type) {
        case 'bool':
          if (v == true) out.add('${i.label} (${_pts(i.yes)})');
        case 'number':
          if (v is num) out.add('${i.label}: ${v == v.roundToDouble() ? v.toStringAsFixed(0) : v}${i.unit.isEmpty ? '' : ' ${i.unit}'}');
        default:
          if (v is int && v >= 0 && v < i.options.length) out.add('${i.label}: ${i.options[v].label} (${_pts(i.options[v].points)})');
      }
    }
    return out;
  }

  static String _pts(num p) => (p > 0 ? '+' : '') + (p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toString());

  @override
  Widget build(BuildContext context) {
    final d = widget.def;
    final r = ScoreRepo.compute(d, _picks);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    String value = '';
    if (r != null) {
      if (d.kind == 'rule') {
        value = r.total > 0 ? tr('Rule positive') : tr('Rule negative');
      } else if (d.kind == 'meld') {
        value = r.shown;
      } else {
        value = d.max != null ? '${r.shown} / ${d.max!.toStringAsFixed(0)}' : r.shown;
      }
    }
    final anyBool = d.inputs.any((i) => i.type == 'bool');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (d.specialty.isNotEmpty) _ltr(d.specialty, style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
      const SizedBox(height: 6),
      for (final i in d.inputs) _input(i),
      if (anyBool) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Unticked items count as absent.', style: theme.textTheme.bodySmall)),
      if (r == null) Text('Answer every question to see the result.', style: theme.textTheme.bodySmall),
      if (r != null)
        for (final a in r.alerts)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(child: Directionality(textDirection: TextDirection.ltr, child: mm.Text(a, style: TextStyle(color: cs.onErrorContainer)))),
            ]),
          ),
      _Result(value, r?.band ?? '', d.source, items: _items()),
      if (d.limits.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Directionality(textDirection: TextDirection.ltr, child: mm.Text(d.limits, style: theme.textTheme.bodySmall)),
        ),
    ]);
  }
}
