import 'package:flutter/material.dart' hide Text;

import 'data.dart';
import 'i18n.dart';
import 'ui.dart' show trUi;

// ---------------------------------------------------------------- form sheet

enum FT { text, multi, number, choice, date }

class FieldSpec {
  final String key;
  final String label;
  final FT type;
  final List<String> options;
  final String hint;
  const FieldSpec(this.key, this.label,
      {this.type = FT.text, this.options = const [], this.hint = ''});
}

/// Opens a bottom sheet with a generic form. Returns the edited map,
/// `{'__delete': true}` if the user pressed Delete, or null if cancelled.
Future<J?> showFormSheet(
  BuildContext context, {
  required String title,
  required List<FieldSpec> specs,
  J? initial,
  bool canDelete = false,
}) {
  return showModalBottomSheet<J>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _FormSheet(
      title: title,
      specs: specs,
      initial: initial ?? <String, dynamic>{},
      canDelete: canDelete,
    ),
  );
}

class _FormSheet extends StatefulWidget {
  final String title;
  final List<FieldSpec> specs;
  final J initial;
  final bool canDelete;
  const _FormSheet({
    required this.title,
    required this.specs,
    required this.initial,
    required this.canDelete,
  });

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  final Map<String, TextEditingController> _c = {};
  final Map<String, String> _v = {};
  final Set<String> _expanded = {};

  /// Suggestions for a text field: filtered by what is typed, the ones used most
  /// recently first. Matches both the English value and its Arabic display.
  List<String> _suggest(FieldSpec s) {
    final typed = (_c[s.key]?.text ?? '').trim().toLowerCase();
    final recent = store.recentsFor(s.key);
    final all = <String>[
      ...recent.where(s.options.contains),
      ...s.options.where((o) => !recent.contains(o)),
    ];
    if (typed.isEmpty) return all;
    return all.where((o) => o.toLowerCase().contains(typed) || tr(o).toLowerCase().contains(typed)).toList();
  }

  @override
  void initState() {
    super.initState();
    for (final s in widget.specs) {
      final cur = (widget.initial[s.key] ?? '').toString();
      if (s.type == FT.choice || s.type == FT.date) {
        _v[s.key] = cur;
      } else {
        _c[s.key] = TextEditingController(text: cur);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  J _result() {
    final out = Map<String, dynamic>.from(widget.initial);
    for (final s in widget.specs) {
      if (_c.containsKey(s.key)) {
        out[s.key] = _c[s.key]!.text.trim();
        if (s.options.isNotEmpty) store.noteUse(s.key, out[s.key].toString());
      } else {
        out[s.key] = _v[s.key] ?? '';
      }
    }
    return out;
  }

  Widget _field(FieldSpec s) {
    final theme = Theme.of(context);
    switch (s.type) {
      case FT.choice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in s.options)
                  ChoiceChip(
                    label: Text(o),
                    selected: _v[s.key] == o,
                    onSelected: (_) => setState(() {
                      _v[s.key] = _v[s.key] == o ? '' : o;
                    }),
                  ),
              ],
            ),
          ],
        );
      case FT.date:
        final cur = _v[s.key] ?? '';
        return Row(
          children: [
            Expanded(
              child: Text(
                '${tr(s.label)}: ${cur.isEmpty ? '—' : prettyDate(cur)}',
                style: theme.textTheme.bodyLarge,
              ),
            ),
            TextButton(
              onPressed: () async {
                final init = parseDate(cur) ?? DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: init,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _v[s.key] = fmtDate(d));
              },
              child: const Text('Pick date'),
            ),
          ],
        );
      case FT.text:
      case FT.multi:
      case FT.number:
        final multi = s.type == FT.multi;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _c[s.key],
              minLines: multi ? 2 : 1,
              maxLines: multi ? null : 1,
              keyboardType: s.type == FT.number
                  ? TextInputType.number
                  : (multi ? TextInputType.multiline : TextInputType.text),
              textCapitalization: TextCapitalization.sentences,
              onChanged: s.options.isEmpty ? null : (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr(s.label),
                hintText: s.hint.isEmpty ? null : tr(s.hint),
                alignLabelWithHint: true,
              ),
            ),
            if (s.options.isNotEmpty)
              Builder(builder: (_) {
                final sug = _suggest(s);
                final open = _expanded.contains(s.key);
                final shown = open ? sug : sug.take(8).toList();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 0,
                    children: [
                      for (final o in shown)
                        ActionChip(
                          label: Text(o),
                          onPressed: () => setState(() {
                            _c[s.key]!.text = o;
                          }),
                        ),
                      if (sug.length > shown.length)
                        ActionChip(
                          label: Text('+${sug.length - shown.length}'),
                          onPressed: () => setState(() => _expanded.add(s.key)),
                        ),
                    ],
                  ),
                );
              }),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final s in widget.specs)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _field(s),
              ),
            // wraps instead of overflowing at large text sizes
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (widget.canDelete)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, <String, dynamic>{'__delete': true}),
                    child: const Text('Delete'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _result()),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- dialogs

Future<bool> confirmDialog(BuildContext context, String message,
    {String action = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String hint = '',
  bool obscure = false,
  bool number = false,
  int maxLength = 0,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _AskDialog(
      title: title,
      hint: hint,
      obscure: obscure,
      number: number,
      maxLength: maxLength,
    ),
  );
}

class _AskDialog extends StatefulWidget {
  final String title;
  final String hint;
  final bool obscure;
  final bool number;
  final int maxLength;
  const _AskDialog({
    required this.title,
    required this.hint,
    required this.obscure,
    required this.number,
    required this.maxLength,
  });

  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        obscureText: widget.obscure,
        keyboardType: widget.number ? TextInputType.number : TextInputType.text,
        maxLength: widget.maxLength > 0 ? widget.maxLength : null,
        decoration: InputDecoration(hintText: tr(widget.hint)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _c.text.trim()),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

// ---------------------------------------------------------------- small widgets

class SectionHeader extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionHeader(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

Color statusColor(String s) {
  switch (s) {
    case 'Draft':
      return Colors.orange;
    case 'Active':
      return Colors.blue;
    case 'Discharged':
      return Colors.green;
    case 'Referred':
      return Colors.purple;
    case 'Completed':
      return Colors.teal;
    default:
      return Colors.grey;
  }
}

class StatusDot extends StatelessWidget {
  final String status;
  const StatusDot(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: statusColor(status)),
        const SizedBox(width: 4),
        Text(trUi(status), style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- PIN lock screen

class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  bool _bad = false;

  void _tap(String d) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += d;
      _bad = false;
    });
    if (_pin.length >= 4 && store.checkPin(_pin)) {
      _pin = '';
      store.unlock();
    } else if (_pin.length == 6) {
      setState(() {
        _bad = true;
        _pin = '';
      });
    }
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    if (store.checkPin(_pin)) {
      _pin = '';
      store.unlock();
    } else {
      setState(() {
        _bad = true;
        _pin = '';
      });
    }
  }

  Widget _key(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 76,
        height: 58,
        child: FilledButton.tonal(
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('MedLog is locked', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 6; i++)
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        i < _pin.length ? Icons.circle : Icons.circle_outlined,
                        size: 16,
                        color: _bad ? Colors.red : theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: 24,
                child: _bad
                    ? const Text('Wrong PIN', style: TextStyle(color: Colors.red))
                    : null,
              ),
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final d in row) _key(d, () => _tap(d))],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _key('⌫', _back),
                  _key('0', () => _tap('0')),
                  _key('OK', _submit),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- password dialog

/// Asks for a password. With [confirm] it asks twice and checks they match
/// and are at least 6 characters. Returns null if cancelled.
Future<String?> askPassword(
  BuildContext context,
  String title, {
  bool confirm = false,
  String note = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _PasswordDialog(title: title, confirm: confirm, note: note),
  );
}

class _PasswordDialog extends StatefulWidget {
  final String title;
  final bool confirm;
  final String note;
  const _PasswordDialog({required this.title, required this.confirm, required this.note});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _a = TextEditingController();
  final TextEditingController _b = TextEditingController();
  String _err = '';

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    final p = _a.text;
    if (widget.confirm) {
      if (p.length < 6) {
        setState(() => _err = 'At least 6 characters.');
        return;
      }
      if (p != _b.text) {
        setState(() => _err = 'The two passwords do not match.');
        return;
      }
    } else if (p.isEmpty) {
      setState(() => _err = 'Enter the password.');
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(widget.note, style: Theme.of(context).textTheme.bodySmall),
              ),
            TextField(
              controller: _a,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('Password')),
            ),
            if (widget.confirm)
              TextField(
                controller: _b,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('Repeat password')),
              ),
            if (_err.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _ok, child: const Text('OK')),
      ],
    );
  }
}

// ---------------------------------------------------------------- share-pack options

class PackOptions {
  final bool images;
  final bool learning;
  final String password;
  const PackOptions(this.images, this.learning, this.password);
}

Future<PackOptions?> askPackOptions(BuildContext context, int count) {
  return showDialog<PackOptions>(
    context: context,
    builder: (ctx) => _PackDialog(count: count),
  );
}

class _PackDialog extends StatefulWidget {
  final int count;
  const _PackDialog({required this.count});

  @override
  State<_PackDialog> createState() => _PackDialogState();
}

class _PackDialogState extends State<_PackDialog> {
  bool _images = false;
  bool _learning = false;
  final TextEditingController _a = TextEditingController();
  final TextEditingController _b = TextEditingController();
  String _err = '';

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(trp('Share {n}', {'n': countLabel(widget.count, 'case')})),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Initials are never included. Tell your colleagues the password '
              'in person or in a separate message.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include images'),
              value: _images,
              onChanged: (v) => setState(() => _images = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include my learning notes'),
              subtitle: const Text('Mistakes, what I learned, questions...'),
              value: _learning,
              onChanged: (v) => setState(() => _learning = v),
            ),
            TextField(
              controller: _a,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('Password (6+ characters)')),
            ),
            TextField(
              controller: _b,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('Repeat password')),
            ),
            if (_err.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_a.text.length < 6) {
              setState(() => _err = 'At least 6 characters.');
            } else if (_a.text != _b.text) {
              setState(() => _err = 'The two passwords do not match.');
            } else {
              Navigator.pop(context, PackOptions(_images, _learning, _a.text));
            }
          },
          child: const Text('Share'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- collapsible section

/// A card whose body opens and closes with an arrow. Whether it is open is
/// remembered per [id], so a screen comes back the way the user left it.
class Fold extends StatefulWidget {
  final String id;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool initiallyOpen;
  final List<Widget> children;
  final Widget? trailing;
  final ValueChanged<bool>? onToggle;
  const Fold({
    super.key,
    this.onToggle,
    required this.id,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.initiallyOpen = false,
    this.trailing,
  });

  @override
  State<Fold> createState() => _FoldState();
}

class _FoldState extends State<Fold> {
  bool get _open {
    final m = store.settings['folds'];
    if (m is Map && m.containsKey(widget.id)) return m[widget.id] == true;
    return widget.initiallyOpen;
  }

  void _set(bool v) {
    final m = store.settings['folds'];
    final map = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
    map[widget.id] = v;
    store.settings['folds'] = map;
    store.saveSettings();
    widget.onToggle?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.outlineVariant)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _open,
          onExpansionChanged: _set,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          leading: widget.icon == null ? null : Icon(widget.icon, color: cs.primary),
          title: Row(children: [
            Expanded(child: Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            if (widget.trailing != null) widget.trailing!,
          ]),
          subtitle: widget.subtitle == null ? null : Text(widget.subtitle!, style: theme.textTheme.bodySmall),
          children: widget.children,
        ),
      ),
    );
  }
}
