import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'ai_api.dart';
import 'ai_doc_api.dart';
import 'ai_engine.dart';
import 'ai_prefs.dart';
import 'ai_render.dart' show citeFromText, docToText;

export 'ai_engine.dart' show AiPrompt;

/// Rebuilds when the AI settings or the connection change.
class AiBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool enabled, bool online) builder;
  const AiBuilder({super.key, required this.builder});

  @override
  State<AiBuilder> createState() => _AiBuilderState();
}

class _AiBuilderState extends State<AiBuilder> {
  void _r() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AiStore.changes.addListener(_r);
    AiEngine.online.addListener(_r);
    AiStore.ensureLoaded();
    AiEngine.startMonitor();
    AiEngine.refreshOnline();
  }

  @override
  void dispose() {
    AiStore.changes.removeListener(_r);
    AiEngine.online.removeListener(_r);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, AiEngine.enabled, AiEngine.online.value);
}

/// Button for an AI action. Hidden when AI is off (nothing to show), disabled with a tooltip when offline.
/// [feature] is the same id given to AiRequest.feature, so the per-feature switch is respected.
class AiButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? feature;
  final bool filled;
  final bool hideWhenOff;

  const AiButton({super.key, required this.label, this.icon = Icons.auto_awesome, required this.onPressed, this.feature, this.filled = false, this.hideWhenOff = true});

  @override
  Widget build(BuildContext context) {
    return AiBuilder(builder: (context, enabled, online) {
      final featureOk = feature == null || AiStore.groupOn(feature!);
      if (hideWhenOff && (!enabled || !featureOk)) return const SizedBox.shrink();
      final ok = enabled && featureOk && online;
      final cs = Theme.of(context).colorScheme;
      final badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(6)),
        child: Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onTertiaryContainer)),
      );
      final child = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        badge,
      ]);
      final btn = filled
          ? FilledButton.tonal(onPressed: ok ? onPressed : null, child: child)
          : OutlinedButton(onPressed: ok ? onPressed : null, child: child);
      return Tooltip(message: ok ? tr('AI suggestion: check before use') : tr('Needs internet / AI off'), child: btn);
    });
  }
}

/// Shows AI text with the review label, copy, "Report problem" and optional sources. The text goes through the
/// formatting engine (parseAiOutput + AiDocView) unless the user chose the plain 'text' style.
class AiOutputCard extends StatefulWidget {
  final String text;
  final String feature;
  final List<String> sources;
  final Widget? footer;
  final void Function(AiCite cite)? onCite;
  const AiOutputCard({super.key, required this.text, this.feature = 'ai', this.sources = const [], this.footer, this.onCite});

  @override
  State<AiOutputCard> createState() => _AiOutputCardState();
}

class _AiOutputCardState extends State<AiOutputCard> {
  AiDoc? _doc;
  String _key = '';

  AiDoc _parse() {
    final k = '${widget.text}\u0001${widget.sources.join('\u0002')}';
    if (_doc != null && k == _key) return _doc!;
    var d = parseAiOutput(widget.text);
    if (widget.sources.isNotEmpty) {
      final have = {for (final c in d.citations) c.label.toLowerCase()};
      final extra = [for (final s in widget.sources) if (!have.contains(s.toLowerCase())) citeFromText(s)];
      if (extra.isNotEmpty) {
        d = AiDoc(sections: d.sections, citations: [...d.citations, ...extra], raw: d.raw, structured: d.structured, title: d.title, uncertainties: d.uncertainties, disclaimer: d.disclaimer);
      }
    }
    _key = k;
    return _doc = d;
  }

  String get _style {
    try {
      return AiPrefs.renderStyle;
    } catch (_) {
      return 'cards';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final doc = _parse();
    final cards = _style != 'text';
    final plain = docToText(doc, markdown: false, footer: false);
    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome, size: 16, color: cs.tertiary),
            const SizedBox(width: 6),
            Expanded(child: Text('AI-generated, not medically reviewed', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          if (cards)
            AiDocView(doc: doc, onCite: widget.onCite, showCopy: false, showDisclaimer: false)
          else ...[
            SelectableText(plain, textDirection: textDirectionFor(plain), style: const TextStyle(height: 1.45)),
            if (widget.sources.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Sources', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              for (final s in widget.sources) Padding(padding: const EdgeInsets.only(top: 2), child: m.Text('• $s', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
            ],
          ],
          if (widget.footer != null) ...[const SizedBox(height: 8), widget.footer!],
          const SizedBox(height: 4),
          Wrap(spacing: 4, children: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: aiDocToPlain(doc)));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(tr('Copied'))));
                }
              },
              icon: const Icon(Icons.copy, size: 16),
              label: Text('Copy'),
            ),
            TextButton.icon(
              onPressed: () async {
                await AiEngine.flag(widget.feature);
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(tr('Thanks, the problem was noted in the AI activity log.'))));
                }
              },
              icon: const Icon(Icons.flag_outlined, size: 16),
              label: Text('Report problem'),
            ),
          ]),
        ]),
      ),
    );
  }
}

String _lvl(String s) => tr(s);

/// Shows exactly what would leave the phone. Returns the labels the user keeps, or null when cancelled.
Future<Set<String>?> showAiPreview(BuildContext context, {required Map<String, String> fields, required List<String> removed, required String feature}) {
  final keep = {...fields.keys};
  return showDialog<Set<String>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(tr('Check before sending')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(tr('This de-identified summary will be sent to {p}. Untick anything you do not want to send.').replaceAll('{p}', AiProviders.label(AiStore.provider)),
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              if (fields.isEmpty) Text(tr('Only your question is sent.')),
              for (final e in fields.entries)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: keep.contains(e.key),
                  onChanged: (v) => set(() => v == true ? keep.add(e.key) : keep.remove(e.key)),
                  title: Text(tr(e.key), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  subtitle: m.Text(e.value, textDirection: textDirectionFor(e.value), style: TextStyle(color: cs.onSurface)),
                ),
              if (removed.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(tr('Removed automatically:'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text(removed.join(', '), style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 8),
              Text(tr('Never sent: names, ids, phone numbers, addresses, hospital or doctor names, images, exact dates.'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_lvl('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, keep), child: Text(_lvl('Send'))),
        ],
      );
    }),
  );
}

/// One-time consent for sharing a de-identified case summary. Turns the case-data level on when accepted.
Future<bool> showAiCaseConsent(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Allow case summaries?')),
      content: SingleChildScrollView(
        child: Text(tr('For case help, a short de-identified summary (age band, sex, findings, labs in words) can be sent to your AI provider. Names, ids, phone numbers, addresses, hospital or doctor names, images and exact dates are never sent. You see and approve every summary first, and you can switch this off any time in AI settings.')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Not now'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Allow'))),
      ],
    ),
  );
  if (ok == true) {
    AiStore.caseConsented = true;
    AiStore.allowCase = true;
    await AiStore.save();
    return true;
  }
  return false;
}
