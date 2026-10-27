import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'choices_engine.dart';
import 'widgets.dart';
import 'data.dart';
import 'i18n.dart';
import 'motion.dart';

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
  /// Guided mode: the step on screen when the person went back to an earlier one (null = the first unanswered).
  int? _focus;
  final Set<String> _skipped = {};

  bool get _all => store.settings['choicesAll'] == true;

  Future<void> _setAll(bool v) async {
    store.settings['choicesAll'] = v;
    await store.saveSettings();
    if (mounted) {
      setState(() {
        _focus = null;
        _skipped.clear();
      });
    }
  }

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
    if (!s.multi) _focus = null; // a single answer moves on to the next question
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
        frequent: options.length > 10 ? ChoiceUsage.topPicks(widget.rec, s.id, [for (final o in options) o.v]) : const [],
        multi: s.multi,
        onToggle: (v) async {
          if (!cc.toggle(t, s, options, v)) {
            if (!await _confirmReplace()) return cc.pick(s.id).v;
            cc.toggle(t, s, options, v, confirmed: true);
          }
          if (!s.multi) _focus = null;
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
      builder: (ctx) => _AddSheet(
        title: s.label,
        options: list,
        have: have,
        action: tests ? 'Add to investigations' : 'Add to the plan',
        frequent: list.length > 10 ? ChoiceUsage.topNames(widget.rec, [for (final o in list) o.v], tests: tests) : const [],
      ),
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
    for (final s in steps) {
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
        subtitle: _en('${t.specialty}  •  $done/${steps.length}', style: theme.textTheme.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: _all ? _allChildren(cc, t, shown, resolved, hidden, theme) : _guidedChildren(cc, t, shown, steps, resolved, theme, done),
      ),
    );
  }

  Widget _groupHeader(ChStep st, ThemeData theme) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(children: [
          Icon(Icons.assignment_outlined, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(child: _en(st.group, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary))),
        ]),
      );

  /// One question at a time: the first unanswered one (or the one you went back to), with the progress above it.
  List<Widget> _guidedChildren(CaseChoices cc, ChTemplate t, List<ChStep> shown, List<ChStep> steps, Map<String, List<ChOption>> resolved, ThemeData theme, int done) {
    bool answered(ChStep st) => cc.pick(st.id).v.isNotEmpty || cc.pick(st.id).details.isNotEmpty;
    var cur = -1;
    if (_focus != null && _focus! >= 0 && _focus! < shown.length) {
      cur = _focus!;
    } else {
      for (var i = 0; i < shown.length; i++) {
        if (!answered(shown[i]) && !_skipped.contains(shown[i].id)) {
          cur = i;
          break;
        }
      }
    }
    final out = <Widget>[
      if (widget.section == 'History') _complaintBar(cc),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Row(children: [
          Expanded(child: AnimatedBar(steps.isEmpty ? 0 : done / steps.length, height: 6)),
          const SizedBox(width: 8),
          Text(cur >= 0 ? trp('Question {i} of {n}', {'i': steps.indexOf(shown[cur]) + 1, 'n': steps.length}) : '$done/${steps.length}', style: theme.textTheme.labelMedium),
        ]),
      ),
    ];
    if (cur >= 0) {
      final st = shown[cur];
      if (st.group.isNotEmpty) out.add(_groupHeader(st, theme));
      out.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          if (cur > 0) TextButton.icon(onPressed: () => setState(() => _focus = cur - 1), icon: const Icon(Icons.chevron_left, size: 18), label: Text('Back')),
          const Spacer(),
          if (answered(st))
            FilledButton.tonal(
              onPressed: () => setState(() => _focus = cur + 1 < shown.length ? cur + 1 : null),
              child: Text(cur + 1 < shown.length ? 'Next' : 'Finish'),
            )
          else
            TextButton(
              onPressed: () => setState(() {
                _skipped.add(st.id);
                _focus = null;
              }),
              child: Text('Skip'),
            ),
        ]),
      ));
      out.add(KeyedSubtree(key: ValueKey('guided_${st.id}'), child: _stepView(cc, t, st, resolved[st.id] ?? st.options, guided: true)));
    } else {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('All questions of this tab are answered or skipped.', style: theme.textTheme.bodyMedium)),
        ]),
      ));
    }
    final skippedLeft = [for (var i = 0; i < shown.length; i++) if (_skipped.contains(shown[i].id) && !answered(shown[i])) i];
    if (skippedLeft.isNotEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(trp('{n} skipped: tap to answer', {'n': skippedLeft.length}), style: theme.textTheme.labelMedium),
      ));
      out.add(Directionality(
        textDirection: TextDirection.ltr,
        child: Wrap(spacing: 6, runSpacing: 2, children: [
          for (final i in skippedLeft)
            ActionChip(
              avatar: const Icon(Icons.skip_next, size: 16),
              label: m.Text(shown[i].label),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _skipped.remove(shown[i].id);
                _focus = i;
              }),
            ),
        ]),
      ));
    }
    final doneIdx = [for (var i = 0; i < shown.length; i++) if (answered(shown[i]) && i != cur) i];
    if (doneIdx.isNotEmpty) {
      out.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text('Answered', style: theme.textTheme.labelMedium)));
      out.add(Directionality(
        textDirection: TextDirection.ltr,
        child: Wrap(spacing: 6, runSpacing: 2, children: [
          for (final i in doneIdx)
            ActionChip(
              label: m.Text('${shown[i].label}: ${cc.pick(shown[i].id).v.take(2).join(', ')}${cc.pick(shown[i].id).v.length > 2 ? '…' : ''}', overflow: TextOverflow.ellipsis),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _focus = i),
            ),
        ]),
      ));
    }
    out.add(Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(onPressed: () => _setAll(true), icon: const Icon(Icons.view_list, size: 18), label: Text('Show all questions')),
    ));
    return out;
  }

  List<Widget> _allChildren(CaseChoices cc, ChTemplate t, List<ChStep> shown, Map<String, List<ChOption>> resolved, int hidden, ThemeData theme) {
    return [
          if (widget.section == 'History') _complaintBar(cc),
          for (var i = 0; i < shown.length; i++) ...[
            if (shown[i].group.isNotEmpty && (i == 0 || shown[i - 1].group != shown[i].group))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(children: [
                  Icon(Icons.assignment_outlined, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(child: _en(shown[i].group, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary))),
                ]),
              ),
            _stepView(cc, t, shown[i], resolved[shown[i].id] ?? shown[i].options),
          ],
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('More questions appear as you choose.', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          Text('Choices record what you found or decided. An empty step means not documented.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(onPressed: () => _setAll(false), icon: const Icon(Icons.linear_scale, size: 18), label: Text('One question at a time')),
          ),
    ];
  }

  /// Complaint templates of the case (chest pain, fever, ...): the ones added, the ones the chief complaint suggests,
  /// and a button for the full list. Their questions follow the specialty's in the tabs.
  Widget _complaintBar(CaseChoices cc) {
    final theme = Theme.of(context);
    if (ChoicesRepo.complaints.isEmpty) return const SizedBox.shrink();
    final attached = cc.complaintIds;
    final sug = [for (final c in ChoicesRepo.suggest(widget.rec.s('cc'))) if (!attached.contains(c.id)) c];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Complaint templates', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Wrap(spacing: 6, runSpacing: 2, children: [
            for (final id in attached)
              if (ChoicesRepo.byId(id) != null)
                InputChip(
                  avatar: const Icon(Icons.assignment_outlined, size: 16),
                  label: m.Text(ChoicesRepo.byId(id)!.specialty),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () {
                    cc.removeComplaint(id);
                    _changed();
                  },
                ),
            for (final c in sug)
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: m.Text(c.specialty),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  cc.addComplaint(c.id);
                  _changed();
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.list_alt, size: 16),
              label: m.Text(tr('More complaints')),
              visualDensity: VisualDensity.compact,
              onPressed: () => _openComplaints(cc),
            ),
          ]),
        ),
        if (attached.isEmpty && sug.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Add a complaint template to get the questions of that presentation (for example chest pain or fever).', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ]),
    );
  }

  Future<void> _openComplaints(CaseChoices cc) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ComplaintSheet(
        specialty: widget.rec.s('specialty'),
        attached: cc.complaintIds,
        onToggle: (id, on) {
          on ? cc.addComplaint(id) : cc.removeComplaint(id);
          _changed();
          return cc.complaintIds;
        },
      ),
    );
  }

  String _optFilter = '';
  String _optFilterFor = '';

  Widget _stepView(CaseChoices cc, ChTemplate t, ChStep s, List<ChOption> options, {bool guided = false}) {
    final theme = Theme.of(context);
    final p = cc.pick(s.id);
    final stale = cc.stale(s, options);
    final adder = kChoiceAdders.contains(s.id);
    final inline = guided || options.length <= _kInlineMax;
    // a long list in guided mode: the options you use most first, and a filter box when it is very long
    if (guided && _optFilterFor != s.id) {
      _optFilterFor = s.id;
      _optFilter = '';
    }
    var shownOptions = options;
    if (guided && options.length > 10) {
      final freq = ChoiceUsage.topPicks(widget.rec, s.id, [for (final o in options) o.v]);
      shownOptions = [for (final f in freq) options.firstWhere((o) => o.v == f), for (final o in options) if (!freq.contains(o.v)) o];
    }
    if (guided && _optFilter.isNotEmpty) shownOptions = [for (final o in shownOptions) if (o.v.toLowerCase().contains(_optFilter) || p.v.contains(o.v)) o];
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
        else if (inline) ...[
          if (guided && options.length > 20)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TextField(
                key: ValueKey('filter_${s.id}'),
                decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), labelText: tr('Search')),
                onChanged: (v) => setState(() => _optFilter = v.trim().toLowerCase()),
              ),
            ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(spacing: 6, runSpacing: 2, children: [
              for (final o in shownOptions)
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
        ]
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

  /// Values you use most in your other cases: shown first under their own heading.
  final List<String> frequent;
  const _PickSheet({required this.title, required this.options, required this.selected, required this.multi, required this.closeOnPick, required this.onToggle, this.frequent = const []});
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
                if (_q.isEmpty && widget.frequent.isNotEmpty) ...[
                  _heading(context, 'Frequently used'),
                  for (final o in widget.options)
                    if (widget.frequent.contains(o.v)) _tile(o),
                  _heading(context, 'All options'),
                ],
                for (final o in list) _tile(o),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tile(ChOption o) => widget.multi
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
        );
}

Widget _heading(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Text(t, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );

class _AddSheet extends StatefulWidget {
  final String title, action;
  final List<ChOption> options;
  final Set<String> have;
  final List<String> frequent;
  const _AddSheet({required this.title, required this.options, required this.have, required this.action, this.frequent = const []});
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
                if (_q.isEmpty && widget.frequent.isNotEmpty) ...[
                  _heading(context, 'Frequently used'),
                  for (final o in widget.options)
                    if (widget.frequent.contains(o.v)) _tile(o),
                  _heading(context, 'All options'),
                ],
                for (final o in list) _tile(o),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tile(ChOption o) => CheckboxListTile(
        dense: true,
        value: widget.have.contains(o.v.toLowerCase()) || _sel.contains(o.v),
        title: _en(o.v),
        subtitle: widget.have.contains(o.v.toLowerCase()) ? Text('Already in the list') : null,
        onChanged: widget.have.contains(o.v.toLowerCase()) ? null : (v) => setState(() => v == true ? _sel.add(o.v) : _sel.remove(o.v)),
      );
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


class _ComplaintSheet extends StatefulWidget {
  final String specialty;
  final List<String> attached;
  final List<String> Function(String id, bool on) onToggle;
  const _ComplaintSheet({required this.specialty, required this.attached, required this.onToggle});
  @override
  State<_ComplaintSheet> createState() => _ComplaintSheetState();
}

class _ComplaintSheetState extends State<_ComplaintSheet> {
  late List<String> _sel = List<String>.from(widget.attached);
  String _q = '';

  String _sourceLine(ChTemplate t) {
    final names = <String>[];
    for (final id in t.sourceIds) {
      final pub = ChoicesRepo.sources[id]?['publisher'] ?? '';
      final short = pub.contains('NICE') || pub.contains('National Institute for Health and Care') ? 'NICE' : (pub.contains('National Heart') ? 'NHLBI' : (pub.contains('Centers for Disease') ? 'CDC' : (pub.contains('British Thoracic') ? 'BTS' : '')));
      if (short.isNotEmpty && !names.contains(short)) names.add(short);
    }
    return names.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = ChoicesRepo.complaintsFor(widget.specialty);
    final list = [
      for (final t in all)
        if (_q.isEmpty || t.specialty.toLowerCase().contains(_q) || t.aliases.any((a) => a.toLowerCase().contains(_q))) t
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: Text('Complaint templates', style: theme.textTheme.titleMedium)),
                FilledButton(onPressed: () => Navigator.pop(context), child: Text('Done')),
              ]),
            ),
            if (ChoicesRepo.complaintStatus.contains('pending'))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Draft content: it has not been through a clinical review yet. It lists what to document; it is not advice.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), labelText: tr('Search')),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: ListView(children: [
                for (final t in list)
                  CheckboxListTile(
                    dense: true,
                    value: _sel.contains(t.id),
                    title: _en(t.specialty),
                    subtitle: _en([trp('{n} questions', {'n': t.steps.length}), _sourceLine(t)].where((e) => e.isNotEmpty).join('  •  ')),
                    onChanged: (v) => setState(() => _sel = widget.onToggle(t.id, v == true)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
