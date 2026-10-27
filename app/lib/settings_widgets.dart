import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'i18n.dart';

/// Building blocks of the unified "Library & AI settings" page. Every control is a plain widget that gets its
/// value and its callback from the caller on every build (nothing is cached in a const subtree), so a change in
/// the store is always drawn again. Each option has a short helper line and an (i) button that opens a plain
/// explanation in a bottom sheet (static text, works offline).

/// Bottom sheet "Explain this option".
Future<void> showOptionHelp(BuildContext context, String title, String body) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.info_outline, size: 20, color: Theme.of(ctx).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Explain this option', style: Theme.of(ctx).textTheme.labelMedium)),
            ]),
            const SizedBox(height: 6),
            Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body, style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.5)),
            const SizedBox(height: 12),
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close'))),
          ]),
        ),
      ),
    ),
  );
}

class OptInfoButton extends StatelessWidget {
  final String title;
  final String info;
  const OptInfoButton({super.key, required this.title, required this.info});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tr('Explain this option'),
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
        icon: Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.outline),
        onPressed: () => showOptionHelp(context, tr(title), tr(info)),
      );
}

/// Title + helper line + (i) button. Used above sliders, choices and fields.
class OptHead extends StatelessWidget {
  final String title;
  final String? help;
  final String? info;
  const OptHead({super.key, required this.title, this.help, this.info});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              if (help != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(help!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
            ]),
          ),
        ),
        if (info != null) OptInfoButton(title: title, info: info!),
      ]),
    );
  }
}

/// A switch with helper text and the (i) button.
class OptSwitch extends StatelessWidget {
  final String title;
  final String? help;
  final String? info;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? extra;
  const OptSwitch({super.key, required this.title, this.help, this.info, required this.value, required this.onChanged, this.extra});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            subtitle: help == null ? null : Text(help!),
            value: value,
            onChanged: onChanged,
          ),
        ),
        if (info != null) OptInfoButton(title: title, info: info!),
      ]),
      if (extra != null) extra!,
    ]);
  }
}

class OptItem<T> {
  final T value;
  final String label;
  final String? sub;
  const OptItem(this.value, this.label, [this.sub]);
}

/// One choice out of a few. [segmented] draws a SegmentedButton (short labels only); otherwise a list of tappable rows.
class OptChoice<T> extends StatelessWidget {
  final String title;
  final String? help;
  final String? info;
  final T value;
  final List<OptItem<T>> items;
  final ValueChanged<T> onChanged;
  final bool segmented;
  const OptChoice({super.key, required this.title, this.help, this.info, required this.value, required this.items, required this.onChanged, this.segmented = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OptHead(title: title, help: help, info: info),
      const SizedBox(height: 6),
      if (segmented)
        SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [for (final o in items) ButtonSegment<T>(value: o.value, label: Center(child: Text(o.label, textAlign: TextAlign.center)))],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        )
      else
        for (final o in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            minVerticalPadding: 4,
            selected: o.value == value,
            leading: Icon(o.value == value ? Icons.radio_button_checked : Icons.radio_button_off, color: o.value == value ? cs.primary : null),
            title: Text(o.label),
            subtitle: o.sub == null ? null : Text(o.sub!),
            onTap: () => onChanged(o.value),
          ),
    ]);
  }
}

class OptSlider extends StatelessWidget {
  final String title;
  final String? help;
  final String? info;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  const OptSlider({super.key, required this.title, this.help, this.info, required this.value, required this.min, required this.max, this.divisions, required this.format, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OptHead(title: title, help: help, info: info),
      Row(children: [
        Expanded(child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, divisions: divisions, label: format(value), onChanged: onChanged)),
        SizedBox(width: 52, child: Directionality(textDirection: TextDirection.ltr, child: m.Text(format(value), textAlign: TextAlign.end, style: Theme.of(context).textTheme.labelLarge))),
      ]),
    ]);
  }
}

/// A tappable row that opens another screen.
class OptLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? help;
  final VoidCallback onTap;
  const OptLink({super.key, required this.icon, required this.title, this.help, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: help == null ? null : Text(help!),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

/// Small sub-heading inside a fold.
class OptGroupTitle extends StatelessWidget {
  final String text;
  const OptGroupTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
      );
}
