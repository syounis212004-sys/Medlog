import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'choices_engine.dart';
import 'widgets.dart';
import 'data.dart';
import 'i18n.dart';

bool _hasArabic(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

/// English medical text keeps its own direction; a string that also has Arabic words follows the app direction.
Widget _en(String s, {TextStyle? style}) => _hasArabic(s) ? m.Text(s, style: style) : Directionality(textDirection: TextDirection.ltr, child: m.Text(s, style: style));

/// Lists up to this many options are shown as chips on the page; longer ones open a searchable sheet.
const int _kInlineMax = 7;

/// The quick choices of one case tab (History, Examination, Investigations, Assessment or Management).
/// Every step starts empty; choosing nothing documents nothing. Steps that would repeat something the case already
/// has (disposition, the tests list, the plan list, the diagnosis fields) feed that place instead of being stored twice.
class ChoicesSection extends StatefulWidget {
  final CaseRec rec;
  final String section;
  final VoidCallback onChanged;

  /// Stores a derived value in the case and in its text field.
  final void Function(String key, String value) write;
  const ChoicesSection({super.key, required this.rec, required this.section, required this.onChanged, required this.write});
  @override
  State<ChoicesSection> createState() => _ChoicesSectionState();
}

class _ChoicesSectionState extends State<ChoicesSection> {
  @override
  void initState() {
    super.initState();
    if (!ChoicesRepo.loaded) {
      ChoicesRepo.load().then((_) {
        if (mounted) setState(() {});
      }, onError: (_) {});
    }
  }

  void _changed() {
    ChoicesSync.derive(widget.rec, widget.write);
    widget.onChanged();
    setState(() {});
  }

  Future<bool> _confirmReplace() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Replace your other choices?'),
        content: Text('This option cannot be combined with the others. They will be removed from this step.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Replace')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _tap(CaseChoices cc, ChTemplate t, ChStep s, List<ChOption> options, String v) async {
    if (!cc.toggle(t, s, options, v)) {
      if (!await _confirmReplace()) return;
      cc.toggle(t, s, options, v, confirmed: true);
    }
    _changed();
  }

  /// A searchable sheet for a long list. Single steps pick one and close; multi steps keep a checklist.
  Future<void> _openSheet(CaseChoices cc, ChTemplate t, ChStep s, List<ChOption> options) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PickSheet(
        title: s.label,
        options: options,
        selected: cc.pick(s.id).v,
        multi: s.multi,
        onToggle: (v) async {
          if (!cc.toggle(t, s, options, v)) {
            if (!await _confirmReplace()) return cc.pick(s.id).v;
            cc.toggle(t, s, options, v, confirmed: true);
          }
          _changed();
          return cc.pick(s.id).v;
        },
        closeOnPick: !s.multi,
      ),
    );
  }

  /// Tests / plan items: choosing adds them to the case's own list.
  Future<void> _openAdder(CaseChoices cc, ChStep s, List<ChOption> options, bool tests) async {
    final have = <String>{
      for (final e in widget.rec.lst(tests ? 'inv' : 'mgmt')) '${e[tests ? 'name' : 'text']}'.toLowerCase(),
    };
    final list = [for (final o in options) if (!o.exclusive && o.v != 'Other') o];
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _AddSheet(title: s.label, options: list, have: have, action: tests ? 'Add to investigations' : 'Add to the plan'),
    );
    if (picked == null || picked.isEmpty) return;
    final n = tests ? ChoicesSync.addTests(widget.rec, picked) : ChoicesSync.addPlanItems(widget.rec, picked);
    if (n > 0) {
      widget.onChanged();
      if (mounted) {
        setState(() {});
        snack(context, tests ? tr('Added to the investigations list. Set the status and who requested it there.') : tr('Added to the plan. Set who decided and the status there.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ChoicesRepo.loaded) return const SizedBox.shrink();
    final cc = CaseChoices(widget.rec);
    final t = cc.template();
    if (t == null) return const SizedBox.shrink();
    final resolved = cc.resolve(t);
    final steps = [for (final s in t.steps) if (s.section == widget.section && !kChoiceHidden.contains(s.id)) s];
    if (steps.isEmpty) return const SizedBox.shrink();
    final shown = <ChStep>[];
    var hidden = 0;
    for (final s in steps) {
      final has = cc.pick(s.id).v.isNotEmpty || cc.pick(s.id).details.isNotEmpty;
      if (cc.enabled(t, s) || has) {
        shown.add(s);
      } else {
        hidden++;
      }
    }
    final theme = Theme.of(context);
    if (shown.isEmpty) {
      // nothing to ask yet: a single line instead of an empty card
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(Icons.touch_app_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text('Choose the site and the problem in History: the quick choices of this tab then appear.', style: theme.textTheme.bodySmall)),
        ]),
      );
    }
    var done = 0;
    for (final s in shown) {
      if (cc.pick(s.id).v.isNotEmpty) done++;
    }
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: PageStorageKey('choices_${t.id}_${widget.section}'),
        initiallyExpanded: widget.section == 'History' || widget.section == 'Assessment',
        leading: const Icon(Icons.touch_app_outlined),
        title: Text('Quick choices', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: _en('${t.specialty}  •  $done/${shown.length}', style: theme.textTheme.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in shown) _stepView(cc, t, s, resolved[s.id] ?? s.options),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('More questions appear as you choose.', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          Text('Choices record what you found or decided. An empty step means not documented.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _stepView(CaseChoices cc, ChTemplate t, ChStep s, List<ChOption> options) {
    final theme = Theme.of(context);
    final p = cc.pick(s.id);
    final stale = cc.stale(s, options);
    final adder = kChoiceAdders.contains(s.id);
    final inline = options.length <= _kInlineMax;
    final selected = [for (final o in options) if (p.v.contains(o.v)) o];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: _en(s.label, style: theme.textTheme.labelLarge))),
          if (!adder && !inline)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => _openSheet(cc, t, s, options),
              child: Text(p.v.isEmpty ? 'Choose' : 'Change'),
            ),
          if (adder)
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => _openAdder(cc, s, options, s.id == 'investigations'),
              icon: const Icon(Icons.add, size: 18),
              label: Text(s.id == 'investigations' ? 'Add tests' : 'Add plan items'),
            ),
        ]),
        if (adder)
          Text(s.id == 'investigations' ? 'Chosen tests go to the investigations list below.' : 'Chosen items go to the plan list below.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else if (inline)
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(spacing: 6, runSpacing: 2, children: [
              for (final o in options)
                s.multi
                    ? FilterChip(
                        label: m.Text(o.v),
                        selected: p.v.contains(o.v),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _tap(cc, t, s, options, o.v),
                      )
                    : ChoiceChip(
                        label: m.Text(o.v),
                        selected: p.v.contains(o.v),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _tap(cc, t, s, options, o.v),
                      ),
            ]),
          )
        else if (selected.isNotEmpty)
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(spacing: 6, runSpacing: 2, children: [
              for (final o in selected)
                InputChip(
                  label: m.Text(o.v),
                  visualDensity: VisualDensity.compact,
                  selected: true,
                  showCheckmark: false,
                  onPressed: () => _openSheet(cc, t, s, options),
                  onDeleted: () {
                    cc.setValues(t, s.id, [for (final x in p.v) if (x != o.v) x]);
                    _changed();
                  },
                ),
            ]),
          )
        else
          Text('Nothing chosen', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (s.id == 'diagnostic_certainty' && p.v.isNotEmpty) _certaintyNote(cc, theme),
        if (stale.isNotEmpty && !adder) ...[
          const SizedBox(height: 4),
          Text('No longer in this list after you changed an earlier answer. Tap to remove or keep as it is.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(spacing: 6, children: [
              for (final v in stale)
                InputChip(
                  avatar: const Icon(Icons.warning_amber_rounded, size: 16),
                  label: m.Text(v),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () {
                    cc.setValues(t, s.id, [for (final x in p.v) if (x != v) x]);
                    _changed();
                  },
                ),
            ]),
          ),
        ],
        if (!adder && p.v.contains('Other'))
          _DetailField(
            key: ValueKey('${s.id}_other'),
            label: tr('Other: details'),
            initial: p.optionDetails['Other'] ?? '',
            onChanged: (x) {
              cc.setOptionDetails(t, s.id, 'Other', x);
              ChoicesSync.derive(widget.rec, widget.write);
              widget.onChanged();
            },
          ),
        if (!adder)
          _DetailsToggle(
            key: ValueKey('${s.id}_d'),
            label: s.detailsLabel,
            initial: p.details,
            onChanged: (x) {
              cc.setDetails(t, s.id, x);
              widget.onChanged();
            },
          ),
      ]),
    );
  }

  /// Says where the diagnosis you chose went, so nothing has to be typed twice.
  Widget _certaintyNote(CaseChoices cc, ThemeData theme) {
    final c = cc.pick('diagnostic_certainty').v;
    final where = c.contains('Confirmed')
        ? 'Final diagnosis'
        : (c.contains('Suspected') || c.contains('Provisional'))
            ? 'Working / provisional diagnosis'
            : 'Differential diagnosis';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('${tr('Filled in')}: ${tr(where)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class _PickSheet extends StatefulWidget {
  final String title;
  final List<ChOption> options;
  final List<String> selected;
  final bool multi, closeOnPick;
  final Future<List<String>> Function(String v) onToggle;
  const _PickSheet({required this.title, required this.options, required this.selected, required this.multi, required this.closeOnPick, required this.onToggle});
  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  late List<String> _sel = List<String>.from(widget.selected);
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = [for (final o in widget.options) if (_q.isEmpty || o.v.toLowerCase().contains(_q)) o];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: _en(widget.title, style: Theme.of(context).textTheme.titleMedium)),
                if (widget.multi) FilledButton(onPressed: () => Navigator.pop(context), child: Text('Done')),
              ]),
            ),
            if (widget.options.length > 10)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), labelText: tr('Search')),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
              ),
            Expanded(
              child: ListView(children: [
                for (final o in list)
                  widget.multi
                      ? CheckboxListTile(
                          dense: true,
                          value: _sel.contains(o.v),
                          title: _en(o.v),
                          onChanged: (_) async {
                            final r = await widget.onToggle(o.v);
                            if (mounted) setState(() => _sel = List<String>.from(r));
                          },
                        )
                      : ListTile(
                          dense: true,
                          title: _en(o.v),
                          trailing: _sel.contains(o.v) ? const Icon(Icons.check) : null,
                          onTap: () async {
                            await widget.onToggle(o.v);
                            if (mounted) Navigator.pop(context);
                          },
                        ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _AddSheet extends StatefulWidget {
  final String title, action;
  final List<ChOption> options;
  final Set<String> have;
  const _AddSheet({required this.title, required this.options, required this.have, required this.action});
  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _sel = <String>{};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = [for (final o in widget.options) if (_q.isEmpty || o.v.toLowerCase().contains(_q)) o];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: _en(widget.title, style: Theme.of(context).textTheme.titleMedium)),
                FilledButton(onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _sel.toList()), child: Text(widget.action)),
              ]),
            ),
            if (widget.options.length > 10)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), labelText: tr('Search')),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
              ),
            Expanded(
              child: ListView(children: [
                for (final o in list)
                  CheckboxListTile(
                    dense: true,
                    value: widget.have.contains(o.v.toLowerCase()) || _sel.contains(o.v),
                    title: _en(o.v),
                    subtitle: widget.have.contains(o.v.toLowerCase()) ? Text('Already in the list') : null,
                    onChanged: widget.have.contains(o.v.toLowerCase())
                        ? null
                        : (v) => setState(() => v == true ? _sel.add(o.v) : _sel.remove(o.v)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DetailsToggle extends StatefulWidget {
  final String label, initial;
  final ValueChanged<String> onChanged;
  const _DetailsToggle({super.key, required this.label, required this.initial, required this.onChanged});
  @override
  State<_DetailsToggle> createState() => _DetailsToggleState();
}

class _DetailsToggleState extends State<_DetailsToggle> {
  late bool _open = widget.initial.isNotEmpty;
  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () => setState(() => _open = true),
          icon: const Icon(Icons.add, size: 16),
          label: Text('Add details'),
        ),
      );
    }
    return _DetailField(label: tr('Details'), initial: widget.initial, onChanged: widget.onChanged);
  }
}

class _DetailField extends StatefulWidget {
  final String label, initial;
  final ValueChanged<String> onChanged;
  const _DetailField({super.key, required this.label, required this.initial, required this.onChanged});
  @override
  State<_DetailField> createState() => _DetailFieldState();
}

class _DetailFieldState extends State<_DetailField> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: TextField(
          controller: _c,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(labelText: widget.label, isDense: true),
          onChanged: widget.onChanged,
        ),
      );
}
