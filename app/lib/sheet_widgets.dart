import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'i18n.dart';
import 'lib_sheet.dart';
import 'lib_text.dart' show normQuote;

/// Widgets of the Study Sheet. English article text is always left-to-right; the card chrome
/// (icons, labels, badges) follows the app language.

/// How the sheet looks: 0 Plain, 1 Light, 2 Rich; [bold] = larger and bolder text.
class SheetLook {
  final int style;
  final bool bold;
  final double scale;
  final bool dark;
  /// 'Highlight doses and red flags': off = no callout cards and no summaries, whatever the style.
  final bool marks;
  /// Normalised sentence to highlight (see normQuote): the block that contains it gets a soft background.
  final String focus;
  const SheetLook({required this.style, required this.bold, required this.scale, required this.dark, this.marks = true, this.focus = ''});

  factory SheetLook.of(BuildContext context, {required int style, required bool bold, required double scale, bool marks = true, String focus = ''}) =>
      SheetLook(style: style, bold: bold, scale: scale, dark: Theme.of(context).brightness == Brightness.dark, marks: marks, focus: focus);

  bool get callouts => style >= 1 && marks;
  bool get rich => style >= 2;
  double get fs => scale * (bold ? 1.1 : 1.0);
}

Color tagColor(SheetTag t, bool dark) {
  switch (t) {
    case SheetTag.redFlag:
      return dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828);
    case SheetTag.dose:
      return dark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);
    case SheetTag.highYield:
      return dark ? const Color(0xFFFFD54F) : const Color(0xFF9A6200);
    case SheetTag.mnemonic:
      return dark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A);
    case SheetTag.none:
      return Colors.grey;
  }
}

IconData tagIcon(SheetTag t) {
  switch (t) {
    case SheetTag.redFlag:
      return Icons.flag_outlined;
    case SheetTag.dose:
      return Icons.medication_outlined;
    case SheetTag.highYield:
      return Icons.star_border;
    case SheetTag.mnemonic:
      return Icons.lightbulb_outline;
    case SheetTag.none:
      return Icons.circle;
  }
}

String tagLabelKey(SheetTag t) {
  switch (t) {
    case SheetTag.redFlag:
      return 'Red flag';
    case SheetTag.dose:
      return 'Dose';
    case SheetTag.highYield:
      return 'High-yield';
    case SheetTag.mnemonic:
      return 'Mnemonic';
    case SheetTag.none:
      return '';
  }
}

Color toneColor(Tone t, bool dark) {
  switch (t) {
    case Tone.green:
      return dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    case Tone.amber:
      return dark ? const Color(0xFFFFB74D) : const Color(0xFFB26A00);
    case Tone.red:
      return dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828);
    case Tone.blue:
      return dark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);
  }
}

IconData toneIcon(Tone t) {
  switch (t) {
    case Tone.green:
      return Icons.check_circle_outline;
    case Tone.amber:
      return Icons.error_outline;
    case Tone.red:
      return Icons.priority_high;
    case Tone.blue:
      return Icons.call_split;
  }
}

/// Text with bold key terms / lead-in terms and highlighted sentences, depending on the look.
InlineSpan sheetSpan(String text, List<SRange> ranges, SheetLook look, TextStyle base) {
  final use = [
    for (final r in ranges)
      if ((r.t == 1 && look.style >= 1) || (r.t == 2 && look.style >= 2) || (r.t == 3 && look.style >= 2)) r,
  ];
  if (use.isEmpty) return TextSpan(text: text, style: base);
  final cuts = <int>{0, text.length};
  for (final r in use) {
    cuts.add(r.s.clamp(0, text.length));
    cuts.add(r.e.clamp(0, text.length));
  }
  final pts = cuts.toList()..sort();
  final boldW = look.bold ? FontWeight.w800 : FontWeight.w700;
  final hl = look.dark ? const Color(0x44FFD54F) : const Color(0x55FFE082);
  final spans = <InlineSpan>[];
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = pts[i], b = pts[i + 1];
    if (a == b) continue;
    var isBold = false, isHl = false;
    for (final r in use) {
      if (r.s <= a && r.e >= b) {
        if (r.t == 3) {
          isHl = true;
        } else {
          isBold = true;
        }
      }
    }
    spans.add(TextSpan(text: text.substring(a, b), style: (isBold || isHl) ? base.copyWith(fontWeight: isBold ? boldW : null, backgroundColor: isHl ? hl : null) : null));
  }
  return TextSpan(style: base, children: spans);
}

TextStyle sheetBase(BuildContext context, SheetLook look) {
  final theme = Theme.of(context);
  final b = theme.textTheme.bodyMedium!;
  return b.copyWith(
    fontSize: (b.fontSize ?? 14) * look.fs,
    height: 1.55,
    fontWeight: look.bold ? FontWeight.w500 : null,
    color: look.bold ? theme.colorScheme.onSurface : null,
  );
}

class SheetSourceBadge extends StatelessWidget {
  final String label;
  const SheetSourceBadge(this.label, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: m.Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSecondaryContainer)),
      ),
    );
  }
}

/// Tinted card with an accent strip on the start side.
class _Tinted extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Tinted({required this.color, required this.child});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: color.withAlpha(dark ? 38 : 26), borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: color),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 8), child: child)),
        ]),
      ),
    );
  }
}

/// One block of the article: paragraph, bullet, nested bullet, sub-heading, or a callout card.
class SheetBlockView extends StatelessWidget {
  final SBlock b;
  final SheetLook look;
  final int baseLevel;
  const SheetBlockView(this.b, this.look, {super.key, this.baseLevel = 0});

  @override
  Widget build(BuildContext context) {
    final w = _inner(context);
    if (look.focus.isEmpty || !normQuote(b.text).contains(look.focus)) return w;
    final c = Theme.of(context).colorScheme.tertiary;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(color: c.withAlpha(look.dark ? 70 : 55), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withAlpha(150))),
      child: w,
    );
  }

  Widget _inner(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = sheetBase(context, look);
    final level = (b.level - baseLevel).clamp(0, 3);
    if (b.kind == BKind.sub) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.centerLeft,
            child: m.Text(b.text, style: base.copyWith(fontWeight: FontWeight.w800, color: look.style >= 1 ? cs.primary : null, fontSize: (base.fontSize ?? 14) * 0.98)),
          ),
        ),
      );
    }
    final tagged = b.tag != SheetTag.none && look.callouts && (b.tag != SheetTag.highYield || look.rich);
    final span = sheetSpan(b.text, b.ranges, look, base);
    Widget body;
    if (b.kind == BKind.bullet) {
      final dot = level == 0 ? 6.0 : 5.0;
      body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 14.0 * level + 2),
        Padding(
          padding: EdgeInsets.only(top: (base.fontSize ?? 14) * 0.72, right: 9),
          child: level == 0
              ? Container(width: dot, height: dot, decoration: BoxDecoration(color: look.style >= 1 ? cs.primary : cs.onSurfaceVariant, shape: BoxShape.circle))
              : Container(width: dot + 2, height: 2, color: cs.outline),
        ),
        Expanded(child: m.Text.rich(span, textAlign: TextAlign.left)),
      ]);
    } else if (b.kind == BKind.cont) {
      body = Padding(padding: EdgeInsets.only(left: 14.0 * level + 17), child: m.Text.rich(span, textAlign: TextAlign.left));
    } else {
      body = m.Text.rich(span, textAlign: TextAlign.left);
    }
    if (!tagged) {
      return Padding(padding: const EdgeInsets.only(bottom: 7), child: Directionality(textDirection: TextDirection.ltr, child: body));
    }
    final c = tagColor(b.tag, look.dark);
    final plain = b.kind == BKind.bullet ? m.Text.rich(span, textAlign: TextAlign.left) : body;
    return _Tinted(
      color: c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(tagIcon(b.tag), size: 16, color: c),
          const SizedBox(width: 6),
          m.Text(tr(tagLabelKey(b.tag)), style: theme.textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 3),
        Directionality(textDirection: TextDirection.ltr, child: Padding(padding: EdgeInsets.only(left: 14.0 * level), child: plain)),
      ]),
    );
  }
}

class _DecisionView extends StatelessWidget {
  final SDecision d;
  final SheetLook look;
  const _DecisionView(this.d, this.look);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = sheetBase(context, look);
    Widget card(DecisionGroup g) {
      final c = toneColor(g.tone, look.dark);
      return Container(
        decoration: BoxDecoration(
          color: c.withAlpha(look.dark ? 38 : 26),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withAlpha(150)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(toneIcon(g.tone), size: 16, color: c),
              const SizedBox(width: 6),
              Expanded(child: m.Text(g.label, style: theme.textTheme.labelLarge?.copyWith(color: c, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 4),
            if (g.rest.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: m.Text(g.rest, style: base)),
            for (final b in g.blocks.skip(1)) SheetBlockView(b, look, baseLevel: 1),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(builder: (context, c) {
        final n = d.groups.length;
        final side = n <= 3 && c.maxWidth / n >= 150;
        if (side) {
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: card(d.groups[i])),
              ],
            ]),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            card(d.groups[i]),
          ],
        ]);
      }),
    );
  }
}

final RegExp _numPrefix = RegExp(r'^\d{1,2}[.)]\s+');

class _StepsView extends StatelessWidget {
  final SSteps s;
  final SheetLook look;
  const _StepsView(this.s, this.look);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = sheetBase(context, look);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < s.steps.length; i++) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                child: m.Text('${i + 1}', style: theme.textTheme.labelMedium?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: m.Text(s.steps[i].text.replaceFirst(_numPrefix, ''), style: base))),
            ]),
            if (i + 1 < s.steps.length)
              Padding(padding: const EdgeInsets.only(left: 4, top: 1, bottom: 1), child: Icon(Icons.arrow_downward, size: 16, color: cs.outline)),
          ],
        ]),
      ),
    );
  }
}

/// All items of one part (a section of one source).
class SheetPartView extends StatelessWidget {
  final SheetPart part;
  final SheetLook look;
  final bool badge;
  final String? sectionTitle;
  final List<Widget> Function(SheetPart part)? tablesFor;
  const SheetPartView({super.key, required this.part, required this.look, this.badge = false, this.sectionTitle, this.tablesFor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final showHead = badge && part.heading.isNotEmpty && part.heading.toLowerCase() != (sectionTitle ?? '').toLowerCase();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (badge && part.src.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: Row(children: [
            SheetSourceBadge(part.src),
            if (showHead) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: m.Text(part.heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
                ),
              ),
            ],
          ]),
        ),
      for (final it in part.items)
        if (it is SDecision && look.callouts)
          _DecisionView(it, look)
        else if (it is SDecision)
          for (final b in it.all) SheetBlockView(b, look)
        else if (it is SSteps && look.rich)
          _StepsView(it, look)
        else if (it is SSteps)
          for (final b in it.steps) SheetBlockView(b, look)
        else if (it is SBlock)
          SheetBlockView(it, look),
      if (tablesFor != null) ...tablesFor!(part),
    ]);
  }
}

/// The body of one canonical section: one part per source (with badges when combined).
class SheetSecBody extends StatelessWidget {
  final SheetSec sec;
  final SheetLook look;
  final bool combined;
  final List<Widget> Function(SheetPart part)? tablesFor;
  const SheetSecBody({super.key, required this.sec, required this.look, this.combined = false, this.tablesFor});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < sec.parts.length; i++) ...[
        if (i > 0 && combined) const SizedBox(height: 6),
        SheetPartView(part: sec.parts[i], look: look, badge: combined, sectionTitle: sec.title, tablesFor: tablesFor),
      ],
    ]);
  }
}

/// Summary of the red flags found in the article (max 4), each with the section it comes from.
class RedFlagSummary extends StatelessWidget {
  final Sheet sheet;
  final SheetLook look;
  const RedFlagSummary({super.key, required this.sheet, required this.look});
  @override
  Widget build(BuildContext context) {
    if (sheet.redFlags.isEmpty || !look.callouts) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final c = tagColor(SheetTag.redFlag, look.dark);
    final base = sheetBase(context, look);
    return _Tinted(
      color: c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.flag_outlined, size: 18, color: c),
          const SizedBox(width: 6),
          m.Text(tr('Red flags'), style: theme.textTheme.titleSmall?.copyWith(color: c, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final f in sheet.redFlags)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: EdgeInsets.only(top: (base.fontSize ?? 14) * 0.72, right: 8), child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle))),
                  Expanded(child: m.Text.rich(sheetSpan(f.text, const [], look, base), textAlign: TextAlign.left)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Dose lines of the article in one card (each with the drug line it sits under, when it is nested) and the dose
/// charts of the article's tables ([tables] are built by the caller). Shows the first [max] lines.
class DoseSummary extends StatefulWidget {
  final Sheet sheet;
  final SheetLook look;
  final List<Widget> tables;
  final int max;
  const DoseSummary({super.key, required this.sheet, required this.look, this.tables = const [], this.max = 8});
  @override
  State<DoseSummary> createState() => _DoseSummaryState();
}

class _DoseSummaryState extends State<DoseSummary> {
  bool _all = false;
  @override
  Widget build(BuildContext context) {
    final sheet = widget.sheet, look = widget.look;
    if ((sheet.doses.isEmpty && widget.tables.isEmpty) || !look.callouts) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final c = tagColor(SheetTag.dose, look.dark);
    final base = sheetBase(context, look);
    final shown = _all ? sheet.doses : sheet.doses.take(widget.max).toList();
    return _Tinted(
      color: c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.medication_outlined, size: 18, color: c),
          const SizedBox(width: 6),
          m.Text(tr('Doses in this article'), style: theme.textTheme.titleSmall?.copyWith(color: c, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final d in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: EdgeInsets.only(top: (base.fontSize ?? 14) * 0.72, right: 8), child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (d.parent.isNotEmpty) m.Text(d.parent, style: base.copyWith(fontSize: (base.fontSize ?? 14) * 0.85, color: theme.colorScheme.outline)),
                      m.Text.rich(sheetSpan(d.text, const [], look, base), textAlign: TextAlign.left),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
        if (sheet.doses.length > widget.max)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: () => setState(() => _all = !_all), child: m.Text(_all ? tr('Show fewer') : trp('Show all {n} dose lines', {'n': sheet.doses.length}))),
          ),
        ...widget.tables,
        m.Text(tr('Check your local protocol before using any dose.'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      ]),
    );
  }
}

/// Small legend for the settings: what the callouts look like at the chosen style.
class SheetLegend extends StatelessWidget {
  final SheetLook look;
  const SheetLegend({super.key, required this.look});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = sheetBase(context, look);
    final samples = <SBlock>[
      SBlock(BKind.bullet, 0, 'Treatment: epinephrine 0.3-0.5 mg IM', tag: SheetTag.dose, ranges: const [SRange(0, 9, 2), SRange(11, 22, 1)]),
      SBlock(BKind.bullet, 0, 'Do not delay treatment while waiting for results', tag: SheetTag.redFlag),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (look.style == 0)
        Directionality(textDirection: TextDirection.ltr, child: m.Text('Treatment: epinephrine 0.3-0.5 mg IM', style: base)),
      if (look.style > 0) ...[for (final b in samples) SheetBlockView(b, look)],
      if (look.style == 0) m.Text(tr('Plain text, no colours.'), style: theme.textTheme.bodySmall),
    ]);
  }
}
