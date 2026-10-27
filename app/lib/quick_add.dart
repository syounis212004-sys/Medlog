import 'package:flutter/material.dart' hide Text;

import 'data.dart';
import 'i18n.dart';
import 'screens_cases.dart';
import 'ai/voice_input.dart';
import 'ui.dart';

/// The "+" button: a 30-second way to log a case now and finish it later.
Future<void> showQuickAdd(BuildContext context, {String? date}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _QuickAddSheet(date: date),
  );
}

class _QuickAddSheet extends StatefulWidget {
  final String? date;
  const _QuickAddSheet({this.date});

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  late String _spec;
  String _age = '';
  String _setting = '';
  final TextEditingController _cc = TextEditingController();

  @override
  void initState() {
    super.initState();
    final rot = store.currentRotation();
    final name = rot == null ? '' : (rot['name'] ?? '').toString();
    _spec = kSpecialtyNames.contains(name) ? name : 'Internal Medicine';
  }

  @override
  void dispose() {
    _cc.dispose();
    super.dispose();
  }

  /// Specialties used most recently come first.
  List<String> _orderedSpecialties() {
    final r = store.recentsFor('specialty').where(kSpecialtyNames.contains).toList();
    return [...r, ...kSpecialtyNames.where((e) => !r.contains(e))];
  }

  CaseRec _build() {
    store.noteUse('specialty', _spec);
    final c = store.newCase();
    c.set('specialty', _spec);
    c.set('code', store.nextCode(prefixFor(_spec)));
    if (_age.isNotEmpty) c.set('ageGroup', _age);
    if (_setting.isNotEmpty) c.set('setting', _setting);
    if (_cc.text.trim().isNotEmpty) c.set('cc', _cc.text.trim());
    if (widget.date != null) c.set('date', widget.date);
    return c;
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final c = _build();
    nav.pop(); // close first: the sheet feels instant, saving continues behind it
    await store.saveCase(c);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(trp('Saved as draft • {code}', {'code': c.s('code')})),
          action: SnackBarAction(
            label: tr('Open case'),
            onPressed: () => nav.push(MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: c))),
          ),
        ),
      );
  }

  void _full() {
    if (_saving) return;
    _saving = true;
    final nav = Navigator.of(context);
    final c = _build();
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: c)));
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(s, style: Theme.of(context).textTheme.labelLarge),
      );

  Widget _chips(List<String> options, String value, ValueChanged<String> onPick) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o),
            selected: value == o,
            onSelected: (_) => onPick(value == o ? '' : o),
          ),
      ],
    );
  }

  bool _saving = false;

  Widget _specCard(ThemeData theme, String s, double scale) {
    final sel = _spec == s;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: Semantics(
        button: true,
        selected: sel,
        label: tr(s),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _spec = s),
          child: Container(
            // wider and taller with the text size: never a fixed 92 px box
            width: 88 * scale,
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: sel ? theme.colorScheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: sel ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                width: sel ? 1.6 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SpecialtyAvatar(s, size: 34),
                const SizedBox(height: 4),
                Text(s,
                    maxLines: 3,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.7);
    final big = scale > 1.15;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    // little room left above the keyboard: drop the hint line, shrink the footer
    final tight = MediaQuery.sizeOf(context).height - kb < 460;
    final save = FilledButton.icon(
      key: const ValueKey('quick_save'),
      onPressed: _saving ? null : _save,
      icon: const Icon(Icons.bolt),
      label: Text('Save quick log'),
    );
    final full = OutlinedButton.icon(
      key: (big && tight) ? null : const ValueKey('quick_full'),
      onPressed: _saving ? null : _full,
      icon: const Icon(Icons.edit_note),
      label: Text('Full form'),
    );
    return Padding(
      // the sheet rides above the keyboard; the buttons below are a sticky footer
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quick log', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (!tight) ...[
                    const SizedBox(height: 2),
                    Text('Write the minimum now. Finish the rest after the shift.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('quick_cc'),
                    controller: _cc,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 4,
                    // Enter / Done on the keyboard saves; the text still wraps on screen
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    textCapitalization: TextCapitalization.sentences,
                    textDirection: isAr ? textDirectionFor(_cc.text) : null,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: trUi('Chief complaint or diagnosis'),
                      hintText: trUi('e.g. Chest pain 2 days'),
                      alignLabelWithHint: true,
                      suffixIcon: VoiceInputButton(controller: _cc, onChanged: () => setState(() {})),
                    ),
                  ),
                  _label('Specialty'),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final s in _orderedSpecialties()) _specCard(theme, s, scale)],
                      ),
                    ),
                  ),
                  _label('Age group'),
                  _chips(const ['Child', 'Adult'], _age, (v) => setState(() => _age = v)),
                  _label('Setting'),
                  _chips(const ['ER', 'Clinic', 'Ward', 'ICU', 'OR'], _setting, (v) => setState(() => _setting = v)),
                ],
              ),
            ),
          ),
          Material(
            color: theme.colorScheme.surface,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: (big && tight)
                  ? Row(children: [
                      IconButton.outlined(
                        key: const ValueKey('quick_full'),
                        tooltip: tr('Full form'),
                        constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
                        onPressed: _saving ? null : _full,
                        icon: const Icon(Icons.edit_note),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: save),
                    ])
                  : big
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [save, const SizedBox(height: 8), full])
                  : Row(children: [
                      Expanded(flex: 3, child: full),
                      const SizedBox(width: 12),
                      Expanded(flex: 4, child: save),
                    ]),
            ),
          ),
        ],
      ),
    );
  }
}
