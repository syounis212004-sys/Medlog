import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'case_extras.dart';
import 'data.dart';
import 'i18n.dart';
import 'widgets.dart';

Widget _ltr(String s, {TextStyle? style}) => Directionality(textDirection: TextDirection.ltr, child: m.Text(s, style: style));

// ============================================================ same patient + outcome

class PatientSection extends StatefulWidget {
  final CaseRec rec;
  final VoidCallback onChanged;
  final Future<CaseRec?> Function() pick;
  final void Function(CaseRec) open;
  const PatientSection({super.key, required this.rec, required this.onChanged, required this.pick, required this.open});
  @override
  State<PatientSection> createState() => _PatientSectionState();
}

class _PatientSectionState extends State<PatientSection> {
  CaseRec get rec => widget.rec;

  Future<void> _link() async {
    final other = await widget.pick();
    if (other == null || !mounted) return;
    await linkSamePatient(rec, other);
    if (!mounted) return;
    widget.onChanged();
    setState(() {});
    snack(context, tr('Linked. No name or number is stored: only a shared hidden group.'));
  }

  Future<void> _unlink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove the link?'),
        content: Text('This case stays; it is only separated from the other cases of the same patient.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await unlinkPatient(rec);
    if (!mounted) return;
    widget.onChanged();
    setState(() {});
  }

  Future<void> _followUp() async {
    final n = await createFollowUp(rec);
    if (!mounted) return;
    widget.onChanged();
    widget.open(n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others = samePatient(rec);
    final outcome = rec.s('outcomeCat');
    return Fold(
      id: 'case_samepatient',
      title: tr('Same patient and outcome'),
      icon: Icons.link,
      subtitle: others.isEmpty ? null : trp('{n} linked cases', {'n': others.length}),
      initiallyOpen: others.isNotEmpty || outcome.isNotEmpty,
      children: [
        Text('How did this case end?', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 0, children: [
          for (final o in kOutcomes)
            ChoiceChip(
              key: ValueKey('outcome_$o'),
              label: Text(o),
              selected: outcome == o,
              onSelected: (v) {
                rec.set('outcomeCat', v ? o : '');
                widget.onChanged();
                setState(() {});
              },
            ),
        ]),
        const SizedBox(height: 10),
        Text('Cases of the same patient', style: theme.textTheme.labelLarge),
        const SizedBox(height: 2),
        Text('Linking joins cases without any name or number, so you can follow one patient over time.', style: theme.textTheme.bodySmall),
        for (final c in others)
          ListTile(
            key: ValueKey('linked_${c.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.assignment_outlined),
            title: _ltr('${c.s('code')}  ${c.s('workingDx').isNotEmpty ? c.s('workingDx') : c.s('cc')}'),
            subtitle: m.Text([prettyDate(c.s('date')), if (c.s('outcomeCat').isNotEmpty) tr(c.s('outcomeCat'))].join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => widget.open(c),
          ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
            key: const ValueKey('link_patient'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _link,
            icon: const Icon(Icons.add_link, size: 18),
            label: Text('Link another case'),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('new_followup'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _followUp,
            icon: const Icon(Icons.event_repeat, size: 18),
            label: Text('Add a follow-up case'),
          ),
          if (patientGroupOf(rec) != null)
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _unlink,
              icon: const Icon(Icons.link_off, size: 18),
              label: Text('Remove the link'),
            ),
        ]),
      ],
    );
  }
}

// ============================================================ structured problem list

class ProblemSection extends StatefulWidget {
  final CaseRec rec;
  final VoidCallback onChanged;
  const ProblemSection({super.key, required this.rec, required this.onChanged});
  @override
  State<ProblemSection> createState() => _ProblemSectionState();
}

class _ProblemSectionState extends State<ProblemSection> {
  CaseRec get rec => widget.rec;

  Future<void> _edit([J? p]) async {
    final res = await showFormSheet(
      context,
      title: p == null ? 'New problem' : 'Problem',
      specs: const [
        FieldSpec('text', 'Problem', type: FT.multi, hint: 'e.g. Acute kidney injury, stage 2'),
        FieldSpec('status', 'Status', type: FT.choice, options: ['active', 'resolved']),
        FieldSpec('since', 'Since', type: FT.date),
      ],
      initial: p ?? <String, dynamic>{'id': newId('pb'), 'status': 'active', 'since': rec.s('date')},
      canDelete: p != null,
    );
    if (res == null) return;
    final list = problemList(rec);
    if (res['__delete'] == true) {
      list.removeWhere((x) => x['id'] == p!['id']);
    } else if ((res['text'] ?? '').toString().trim().isNotEmpty) {
      final i = list.indexWhere((x) => x['id'] == res['id']);
      if (i >= 0) {
        list[i] = res;
      } else {
        list.add(res);
      }
    }
    widget.onChanged();
    if (mounted) setState(() {});
  }

  void _toggle(J p) {
    p['status'] = p['status'] == 'resolved' ? 'active' : 'resolved';
    widget.onChanged();
    setState(() {});
  }

  void _import() {
    final n = importProblemLines(rec);
    widget.onChanged();
    setState(() {});
    snack(context, n == 0 ? tr('Nothing new to import.') : trp('{n} problems imported.', {'n': n}));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = problemsSorted(rec);
    final active = list.where((p) => p['status'] != 'resolved').length;
    return Fold(
      id: 'case_problems',
      title: tr('Problem list'),
      icon: Icons.format_list_numbered,
      subtitle: list.isEmpty ? null : trp('{a} active, {r} resolved', {'a': active, 'r': list.length - active}),
      initiallyOpen: true,
      trailing: IconButton(
        key: const ValueKey('add_problem'),
        tooltip: tr('Add'),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.add),
        onPressed: () => _edit(),
      ),
      children: [
        if (list.isEmpty) Text('One line per problem. Tick it when it is resolved.', style: theme.textTheme.bodySmall),
        for (final p in list)
          CheckboxListTile(
            key: ValueKey('problem_${p['id']}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: p['status'] == 'resolved',
            onChanged: (_) => _toggle(p),
            title: Directionality(
              textDirection: TextDirection.ltr,
              child: m.Text((p['text'] ?? '').toString(),
                  style: p['status'] == 'resolved' ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
            ),
            subtitle: (p['since'] ?? '').toString().isEmpty ? null : m.Text(prettyDate(p['since'].toString())),
            secondary: IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: tr('Edit'), onPressed: () => _edit(p)),
          ),
        if (rec.s('problems').trim().isNotEmpty)
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _import,
            icon: const Icon(Icons.playlist_add, size: 18),
            label: Text('Import the lines from the text below'),
          ),
      ],
    );
  }
}

// ============================================================ lab readings and trends

class _Spark extends CustomPainter {
  final List<double> v;
  final Color color;
  _Spark(this.v, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final lo = v.reduce((a, b) => a < b ? a : b), hi = v.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height - (v[i] - lo) / span * (size.height - 6) - 3;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round);
    final last = Offset(size.width, size.height - (v.last - lo) / span * (size.height - 6) - 3);
    canvas.drawCircle(last, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _Spark old) => old.v != v || old.color != color;
}

class LabSection extends StatefulWidget {
  final CaseRec rec;
  final VoidCallback onChanged;
  const LabSection({super.key, required this.rec, required this.onChanged});
  @override
  State<LabSection> createState() => _LabSectionState();
}

class _LabSectionState extends State<LabSection> {
  CaseRec get rec => widget.rec;

  Future<void> _add([String? preset]) async {
    final test = TextEditingController(text: preset ?? '');
    final value = TextEditingController();
    final unit = TextEditingController(text: kLabCatalog.where((t) => t.name == preset).map((t) => t.unit).firstOrNull ?? '');
    var date = todayStr();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Add a result'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 0, children: [
                for (final t in kLabCatalog)
                  ActionChip(
                    label: m.Text(t.name),
                    onPressed: () => setD(() {
                      test.text = t.name;
                      unit.text = t.unit;
                    }),
                  ),
              ]),
              TextField(key: const ValueKey('lab_test'), controller: test, decoration: InputDecoration(labelText: tr('Test'))),
              TextField(
                key: const ValueKey('lab_value'),
                controller: value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Value')),
              ),
              TextField(key: const ValueKey('lab_unit'), controller: unit, decoration: InputDecoration(labelText: tr('Unit (as your lab reports it)'))),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: m.Text(prettyDate(date)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.tryParse(date) ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d != null) setD(() => date = fmtDate(d));
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
            FilledButton(key: const ValueKey('lab_save'), onPressed: () => Navigator.pop(ctx, true), child: Text('Save')),
          ],
        ),
      ),
    );
    final v = double.tryParse(value.text.trim().replaceAll(',', '.'));
    final name = test.text.trim();
    final u = unit.text.trim();
    // the dialog is still animating out here, so the controllers are left to the garbage collector
    if (ok != true || v == null || name.isEmpty) return;
    rec.lst('labs').add({'id': newId('lb'), 'test': name, 'value': v, 'unit': u, 'date': date});
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _open(LabSeries s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final cur = labSeries(rec).where((x) => x.test == s.test).firstOrNull;
          return ListView(padding: const EdgeInsets.all(16), children: [
            _ltr('${s.test}${s.unit.isEmpty ? '' : ' (${s.unit})'}', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (cur == null) Text('No results left.'),
            if (cur != null)
              for (final r in cur.readings.reversed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: _ltr(_fmt(r.value)),
                  subtitle: m.Text(prettyDate(r.date)),
                  trailing: IconButton(
                    tooltip: tr('Delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      rec.lst('labs').removeWhere((x) => x['id'] == r.id);
                      widget.onChanged();
                      setS(() {});
                      if (mounted) setState(() {});
                    },
                  ),
                ),
          ]);
        },
      ),
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(v.abs() < 10 ? 2 : 1).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final series = labSeries(rec);
    return Fold(
      id: 'case_labs',
      title: tr('Lab results and trends'),
      icon: Icons.show_chart,
      subtitle: series.isEmpty ? null : trp('{n} tests', {'n': series.length}),
      initiallyOpen: true,
      trailing: IconButton(
        key: const ValueKey('add_lab'),
        tooltip: tr('Add'),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.add),
        onPressed: () => _add(),
      ),
      children: [
        if (series.isEmpty) Text('Add numbers (for example Hb, creatinine, CRP) on different days to see how they move.', style: theme.textTheme.bodySmall),
        for (final s in series)
          InkWell(
            key: ValueKey('lab_${s.test}'),
            onTap: () => _open(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _ltr(s.test, style: const TextStyle(fontWeight: FontWeight.w700)),
                    _ltr('${_fmt(s.latest.value)}${s.unit.isEmpty ? '' : ' ${s.unit}'}', style: theme.textTheme.bodyMedium),
                  ]),
                ),
                SizedBox(width: 90, height: 34, child: CustomPaint(painter: _Spark([for (final r in s.readings) r.value], cs.primary))),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: s.previous == null
                      ? m.Text('1', textAlign: TextAlign.center, style: theme.textTheme.bodySmall)
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(s.trend == 1 ? Icons.arrow_upward : s.trend == -1 ? Icons.arrow_downward : Icons.arrow_forward, size: 18),
                          const SizedBox(width: 2),
                          Flexible(child: _ltr(_fmt((s.latest.value - s.previous!.value).abs()), style: theme.textTheme.bodySmall)),
                        ]),
                ),
              ]),
            ),
          ),
        if (series.isNotEmpty) Text('Arrows compare the last result with the one before. They are not normal or abnormal flags.', style: theme.textTheme.bodySmall),
      ],
    );
  }
}
