import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as mm show Text;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'ai/ai_api.dart';
import 'ai/ai_case_payload.dart';
import 'ai/ai_cases.dart';
import 'ai/ai_context.dart';
import 'ai/ai_doc_api.dart';
import 'ai/ai_tools.dart';
import 'calculators.dart' show CalcResult;
import 'data.dart';
import 'i18n.dart';
import 'library.dart';
import 'screens_ai_library.dart' show AskReferencesScreen;
import 'screens_ai_quiz.dart' show AiQuizScreen;
import 'screens_ai_settings.dart' show AiSettingsScreen;
import 'screens_library.dart' show openArticle;
import 'screens_notebooks.dart' show openUrl, editReflection;
import 'screens_search.dart' show pickCase;
import 'ui.dart';
import 'widgets.dart';

/// Shared UI of the AI helpers that live inside the other screens.
///
/// Rules: every AI entry is VISIBLE; when AI is off it is shown disabled with a "Turn on AI" link, when the phone is offline
/// it is disabled with a note. Every AI answer goes through [parseAiOutput] + [AiDocView] (or AiOutputCard for plain
/// paragraphs), is labelled, and nothing is written to the records without the user confirming.

void openAiSettings(BuildContext context) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AiSettingsScreen()));

/// Rebuilds on AI settings / connectivity changes. The connectivity monitor is only touched when AI is on.
class AiStateBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, bool enabled, bool online) builder;
  const AiStateBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AiStore.changes,
      builder: (context, _) {
        if (!Ai.enabled) return builder(context, false, false);
        return AiBuilder(builder: builder);
      },
    );
  }
}

Widget _aiBadge(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(6)),
    child: Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onTertiaryContainer)),
  );
}

/// A visible AI action. On: normal button. Off: disabled + "Turn on AI". Offline: disabled + note.
class AiEntry extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? feature;
  final bool filled;
  final bool compact; // no caption lines (for chips rows)
  const AiEntry({super.key, required this.label, required this.onPressed, this.icon = Icons.auto_awesome, this.feature, this.filled = false, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return AiStateBuilder(builder: (context, enabled, online) {
      final featureOk = feature == null || AiStore.groupOn(feature!);
      final ok = enabled && featureOk && online;
      final child = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 2)),
        const SizedBox(width: 6),
        _aiBadge(context),
      ]);
      final btn = filled
          ? FilledButton.tonal(onPressed: ok ? onPressed : null, child: child)
          : OutlinedButton(onPressed: ok ? onPressed : null, child: child);
      final cap = Theme.of(context).textTheme.bodySmall;
      String? note;
      if (!enabled) {
        note = 'AI is off. MedLog works fully without it.';
      } else if (!featureOk) {
        note = 'This AI feature is switched off in AI settings.';
      } else if (!online) {
        note = 'Needs internet. Saved answers can still be read.';
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: btn),
        if (note != null && !compact) ...[
          const SizedBox(height: 2),
          Text(note, style: cap),
        ],
        if ((!enabled || !featureOk) && !compact)
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 48), alignment: AlignmentDirectional.centerStart),
            onPressed: () => openAiSettings(context),
            icon: const Icon(Icons.power_settings_new, size: 18),
            label: Text(enabled ? 'Open AI settings' : 'Turn on AI'),
          ),
      ]);
    });
  }
}

/// Small "AI" chip for app bars / lists: always visible, opens [onTap] (the screen it opens explains when AI is off).
class AiChipButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;
  const AiChipButton({super.key, required this.onTap, this.tooltip = 'AI'});

  @override
  Widget build(BuildContext context) {
    return AiStateBuilder(builder: (context, enabled, online) {
      final cs = Theme.of(context).colorScheme;
      return Tooltip(
        message: tr(tooltip),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 48),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: BoxDecoration(
                  color: enabled ? cs.tertiaryContainer : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 14, color: enabled ? cs.onTertiaryContainer : cs.outline),
                  const SizedBox(width: 2),
                  mm.Text('AI', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: enabled ? cs.onTertiaryContainer : cs.outline)),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ================================================================ result view

/// A labelled AI answer: structured document (parser + renderer), a warning when a web answer has no source,
/// copy and "Report problem". [footer] holds the actions that use the answer (all of them ask first).
class AiResultView extends StatelessWidget {
  final AiResult res;
  final String feature;
  final bool narrative; // plain paragraph (no sections)
  final bool needsCites;
  final String? draftNote;
  final Widget? footer;
  const AiResultView({super.key, required this.res, required this.feature, this.narrative = false, this.needsCites = true, this.draftNote, this.footer});

  Future<void> _cite(BuildContext context, AiCite c) => openUrl(context, c.url);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (narrative) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (draftNote != null) _draftBanner(context, draftNote!),
        AiOutputCard(text: res.text.trim(), feature: feature, footer: footer),
      ]);
    }
    final doc = docOf(res);
    final warn = needsCites && needsSourceWarning(doc);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (draftNote != null) _draftBanner(context, draftNote!),
      Card(
        margin: EdgeInsets.zero,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome, size: 16, color: cs.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(res.fromCache ? 'AI-generated, not medically reviewed (saved answer)' : 'AI-generated, not medically reviewed',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ),
            ]),
            if (warn) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: cs.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text('No source was cited. Treat this as unverified and check a guideline.', style: TextStyle(color: cs.onErrorContainer, fontSize: 13))),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            AiDocView(doc: doc, onCite: (c) => _cite(context, c)),
            if (footer != null) ...[const SizedBox(height: 8), footer!],
            const SizedBox(height: 4),
            Wrap(spacing: 4, children: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: doc.raw.isEmpty ? res.text : doc.raw));
                  if (context.mounted) snack(context, tr('Copied'));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text('Copy'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Ai.flagProblem(feature);
                  if (context.mounted) snack(context, tr('Thanks, the problem was noted in the AI activity log.'));
                },
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: Text('Report problem'),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _draftBanner(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.edit_note, size: 18, color: cs.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
      ),
    );
  }
}

// ================================================================ run panel

/// AiEntry + busy + result. [build] makes the request when the button is pressed (return null to do nothing).
class AiRunPanel extends StatefulWidget {
  final String label;
  final IconData icon;
  final String feature;
  final AiRequest? Function() build;
  final bool narrative;
  final bool needsCites;
  final bool enabled; // false: the button is disabled (for example no input yet)
  final String? draftNote;
  final Widget Function(AiResult res)? footer;
  final void Function(AiResult res)? onResult;
  final bool filled;
  const AiRunPanel({
    super.key,
    required this.label,
    required this.feature,
    required this.build,
    this.icon = Icons.auto_awesome,
    this.narrative = false,
    this.needsCites = true,
    this.enabled = true,
    this.draftNote,
    this.footer,
    this.onResult,
    this.filled = true,
  });

  @override
  State<AiRunPanel> createState() => AiRunPanelState();
}

class AiRunPanelState extends State<AiRunPanel> {
  bool _busy = false;
  AiResult? _res;
  String _msg = '';

  AiResult? get result => _res;

  Future<void> run() async {
    final req = widget.build();
    if (req == null) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    final r = await Ai.run(req, context: context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.cancelled) return;
      if (r.offline) {
        _msg = tr('AI is not available right now. The local tools still work.');
      } else if (!r.ok) {
        _msg = (r.error ?? '').isEmpty ? tr('The AI request failed.') : r.error!;
      } else if (r.text.trim().isEmpty && r.json == null) {
        _msg = tr('The answer could not be read. Try again.');
      } else {
        _res = r;
      }
    });
    if (r.ok && mounted) widget.onResult?.call(r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _res;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AiEntry(label: widget.label, icon: widget.icon, feature: widget.feature, filled: widget.filled, onPressed: _busy || !widget.enabled ? null : run),
      if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: mm.Text(_msg)),
      if (r != null && !_busy)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AiResultView(
            res: r,
            feature: widget.feature,
            narrative: widget.narrative,
            needsCites: widget.needsCites,
            draftNote: widget.draftNote,
            footer: widget.footer?.call(r),
          ),
        ),
    ]);
  }
}

/// Library articles for a name (local search): "Read about it" chips.
class LibraryChips extends StatelessWidget {
  final String name;
  const LibraryChips(this.name, {super.key});

  Future<List<(String, int, String)>> _find() async {
    try {
      if (!library.ready) return const [];
      final hits = await library.searchEx(name, limit: 6, strict: true);
      final good = hits.where((h) => h.titleMatch).toList();
      return [for (final h in (good.isNotEmpty ? good : hits).take(3)) (h.packId, h.index, h.title)];
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (name.trim().isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<(String, int, String)>>(
      future: _find(),
      builder: (context, snap) {
        final l = snap.data ?? const [];
        if (l.isEmpty) return const SizedBox.shrink();
        return Wrap(spacing: 6, runSpacing: 4, children: [
          for (final k in l)
            ActionChip(
              avatar: const Icon(Icons.menu_book_outlined, size: 16),
              label: mm.Text('${tr('Read about it')}: ${k.$3}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onPressed: () => openArticle(context, k.$1, k.$2),
            ),
        ]);
      },
    );
  }
}

Widget _gap([double h = 8]) => SizedBox(height: h);

// ================================================================ generic tool screen

class AiToolScreen extends StatefulWidget {
  final String title;
  final String kind;
  final String intro;
  final String feature;
  final String runLabel;
  final IconData icon;
  final String? inputLabel;
  final String initialInput;
  final AiRequest? Function(String input) build;
  final bool narrative;
  final bool needsCites;
  final String? draftNote;
  final Widget Function(BuildContext context)? top;
  final Widget Function(BuildContext context, String input)? local;
  final Widget Function(AiResult res)? footer;
  const AiToolScreen({
    super.key,
    required this.title,
    required this.feature,
    required this.runLabel,
    required this.build,
    this.kind = 'other',
    this.intro = '',
    this.icon = Icons.auto_awesome,
    this.inputLabel,
    this.initialInput = '',
    this.narrative = false,
    this.needsCites = true,
    this.draftNote,
    this.top,
    this.local,
    this.footer,
  });

  @override
  State<AiToolScreen> createState() => _AiToolScreenState();
}

class _AiToolScreenState extends State<AiToolScreen> {
  late final TextEditingController _c = TextEditingController(text: widget.initialInput);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AiContextScope(
      ctx: AiScreenContext(kind: widget.kind, title: widget.title),
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          if (widget.intro.isNotEmpty) Text(widget.intro, style: Theme.of(context).textTheme.bodyMedium),
          if (widget.top != null) ...[_gap(), widget.top!(context)],
          if (widget.inputLabel != null) ...[
            _gap(12),
            TextField(
              controller: _c,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: tr(widget.inputLabel!)),
            ),
          ],
          _gap(12),
          AiRunPanel(
            label: widget.runLabel,
            icon: widget.icon,
            feature: widget.feature,
            enabled: widget.inputLabel == null || _c.text.trim().isNotEmpty,
            narrative: widget.narrative,
            needsCites: widget.needsCites,
            draftNote: widget.draftNote,
            footer: widget.footer,
            build: () => widget.build(_c.text.trim()),
          ),
          if (widget.local != null) ...[_gap(12), widget.local!(context, _c.text.trim())],
        ]),
      ),
    );
  }
}

// ================================================================ procedures / skills

Future<void> openProcedureDeepDive(BuildContext context, String procedure) => Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AiToolScreen(
          title: tr('Procedure deep-dive'),
          kind: 'other',
          intro: tr('Steps, complications and consent points for a procedure, with sources. For learning: always be supervised until you are signed off.'),
          feature: 'ask_procedure',
          runLabel: tr('Explain this procedure'),
          inputLabel: 'Procedure',
          initialInput: procedure,
          build: (s) => s.isEmpty ? null : procedureRequest(s),
          local: (ctx, s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Without AI: read about it in your library', style: const TextStyle(fontWeight: FontWeight.w800)),
            _gap(4),
            LibraryChips(s),
          ]),
        ),
      ),
    );

// ================================================================ calculators

/// "Which score fits this case?": a typed description (no case data) or a chosen case (de-identified, previewed).
class WhichScoreScreen extends StatefulWidget {
  const WhichScoreScreen({super.key});
  @override
  State<WhichScoreScreen> createState() => _WhichScoreScreenState();
}

class _WhichScoreScreenState extends State<WhichScoreScreen> {
  final TextEditingController _c = TextEditingController();
  CaseRec? _case;
  bool _useCase = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final c = await pickCase(context);
    if (c != null && mounted) setState(() => _case = c);
  }

  AiRequest? _req() {
    if (_useCase) {
      final c = _case;
      if (c == null) return null;
      final p = buildCasePayload(c);
      if (p.blocked) {
        snack(context, tr('This case is marked "Never send this case to AI". Turn it off in the case Info tab to use these tools.'));
        return null;
      }
      if (p.isEmpty) return null;
      return scoreFinderRequest(p: p);
    }
    final t = _c.text.trim();
    return t.length < 8 ? null : scoreFinderRequest(description: t);
  }

  @override
  Widget build(BuildContext context) {
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'calc', title: 'Which score fits?'),
      child: Scaffold(
        appBar: AppBar(title: Text('Which score fits this case?')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Text('Describe the situation in your own words (no names), or pick one of your cases. The app calculates every number itself: the AI only suggests which score fits and where it comes from.'),
          _gap(12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text('Type a description')),
              ButtonSegment(value: true, label: Text('Use one of my cases')),
            ],
            selected: {_useCase},
            onSelectionChanged: (v) => setState(() => _useCase = v.first),
          ),
          _gap(12),
          if (!_useCase)
            TextField(
              controller: _c,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: tr('Clinical picture (no names or ids)'), hintText: tr('e.g. 70 year old with cough, fever, confusion and low blood pressure')),
            )
          else ...[
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.folder_open),
              label: mm.Text(_case == null ? tr('Choose a case') : '${_case!.s('code')} • ${_case!.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            _gap(4),
            Text('Only de-identified fields are sent, and you see them before sending.', style: Theme.of(context).textTheme.bodySmall),
          ],
          _gap(12),
          AiRunPanel(
            label: tr('Which score fits?'),
            feature: 'ask_score',
            icon: Icons.calculate_outlined,
            enabled: _useCase ? _case != null : _c.text.trim().length >= 8,
            build: _req,
            footer: (res) {
              final ids = calcIdsMentioned(res.text);
              if (ids.isEmpty) return const SizedBox.shrink();
              return Wrap(spacing: 6, runSpacing: 4, children: [
                for (final id in ids)
                  ActionChip(
                    avatar: const Icon(Icons.calculate_outlined, size: 16),
                    label: mm.Text('${tr('Open calculator')}: ${tr(kCalcTitles[id]!)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: () => Navigator.pop(context, id),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

/// "Interpret my result" under a calculator result. Only the calculator, the value and the app meaning are sent.
class InterpretResult extends StatelessWidget {
  final String calc;
  final CalcResult result;
  const InterpretResult({super.key, required this.calc, required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AiRunPanel(
        label: tr('Interpret my result'),
        feature: 'ask_calc_interpret',
        icon: Icons.fact_check_outlined,
        filled: false,
        build: () => interpretRequest(calc: calc, value: result.value, meaning: result.meaning),
      ),
    );
  }
}

// ================================================================ drug check

class DrugCheckScreen extends StatefulWidget {
  const DrugCheckScreen({super.key});
  @override
  State<DrugCheckScreen> createState() => _DrugCheckScreenState();
}

class _DrugCheckScreenState extends State<DrugCheckScreen> {
  DrugKind _kind = DrugKind.interaction;
  final TextEditingController _a = TextEditingController();
  final TextEditingController _b = TextEditingController();
  final TextEditingController _ctx = TextEditingController();
  bool _busy = false;
  DrugAnswer? _ans;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _ctx.dispose();
    super.dispose();
  }

  DrugQuery get _q => DrugQuery(_kind, [_a.text, if (_kind == DrugKind.interaction) _b.text], context: _ctx.text);

  Future<void> _run() async {
    final q = _q;
    if (!q.valid) return;
    setState(() {
      _busy = true;
      _ans = null;
    });
    final a = await runDrugCheck(q, context: context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ans = a.status == DrugStatus.cancelled ? null : a;
    });
  }

  Widget _banner() {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Drug information from AI can be wrong or out of date. It is shown only when a named source supports it. Verify every drug, dose and interaction in your hospital formulary or national formulary before acting. This tool is never combined with a patient case.',
              style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _noSource(String reason) {
    final cs = Theme.of(context).colorScheme;
    final why = switch (reason) {
      'mode' => 'The source mode is set to the model only. Switch to trusted web or to your library in AI settings: drug questions are answered only with a source.',
      'library' => 'Your installed library has no passage that covers this. Install a drug reference pack, or switch the source to trusted web in AI settings.',
      'input' => 'Write the drug name (two names for an interaction).',
      _ => 'The search found nothing from the trusted sources that answers this with a citation.',
    };
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.search_off, color: cs.error),
            const SizedBox(width: 8),
            Expanded(child: Text('No verified source found', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
          _gap(6),
          Text(why),
          _gap(6),
          Text('Please check your hospital formulary.', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _result() {
    final a = _ans;
    if (a == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    switch (a.status) {
      case DrugStatus.off:
        return const SizedBox.shrink();
      case DrugStatus.offline:
        return mm.Text(tr('AI is not available right now. The local tools still work.'));
      case DrugStatus.error:
        return mm.Text(a.reason.isEmpty ? tr('The AI request failed.') : a.reason);
      case DrugStatus.noSource:
      case DrugStatus.cancelled:
        return _noSource(a.reason);
      case DrugStatus.answered:
        return AppCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.auto_awesome, size: 16, color: cs.tertiary),
                const SizedBox(width: 6),
                Expanded(child: Text('AI-generated, not medically reviewed', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
              ]),
              _gap(8),
              for (final f in a.findings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    DirText(f.text, style: const TextStyle(height: 1.4)),
                    _gap(4),
                    ActionChip(
                      avatar: const Icon(Icons.link, size: 16),
                      label: mm.Text('${f.cite.org} ${f.cite.year}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPressed: () => openUrl(context, f.cite.url),
                    ),
                    Directionality(textDirection: TextDirection.ltr, child: Text(f.cite.url, style: Theme.of(context).textTheme.bodySmall)),
                  ]),
                ),
              if (a.findings.isNotEmpty && !a.searched)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('The live web search did not run, so these links are not confirmed. Open each source and check it.', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              if (a.libraryText.isNotEmpty) ...[
                DirText(a.libraryText, style: const TextStyle(height: 1.4)),
                _gap(8),
                Text('Sources from your library', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                for (final p in a.passages)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ActionChip(
                      avatar: const Icon(Icons.menu_book_outlined, size: 16),
                      label: mm.Text('[${p.n}] ${p.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPressed: () => openArticle(context, p.packId, p.index),
                    ),
                  ),
              ],
              _gap(6),
              Text('Verify in your hospital formulary.', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inter = _kind == DrugKind.interaction;
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'calc', title: 'Drug check'),
      child: Scaffold(
        appBar: AppBar(title: Text('Drug check')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          _banner(),
          _gap(8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in DrugKind.values)
              ChoiceChip(label: Text(kDrugKindLabel[k]!), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ]),
          _gap(12),
          TextField(key: const ValueKey('drug_a'), controller: _a, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: tr(inter ? 'First drug' : 'Drug'))),
          if (inter) ...[
            _gap(8),
            TextField(key: const ValueKey('drug_b'), controller: _b, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: tr('Second drug'))),
          ],
          _gap(8),
          TextField(
            controller: _ctx,
            maxLength: 120,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('Extra detail (optional, no patient data)'), hintText: tr('e.g. eGFR 30, third trimester')),
          ),
          _gap(4),
          AiEntry(label: tr('Check with sources'), icon: Icons.medication_outlined, feature: 'ask_drug', filled: true, onPressed: _busy || !_q.valid ? null : _run),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          _gap(8),
          _result(),
          _gap(8),
          Text('Sources come from the allowed list in AI settings (trusted web) or from your own library packs. Without a source there is no answer.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

// ================================================================ bulk tag suggestions

class BulkTagsScreen extends StatefulWidget {
  const BulkTagsScreen({super.key});
  @override
  State<BulkTagsScreen> createState() => _BulkTagsScreenState();
}

class _Sug {
  final CaseRec rec;
  final List<String> tags;
  bool apply = true;
  AiUndo? undo;
  bool done = false;
  _Sug(this.rec, this.tags);
}

class _BulkTagsScreenState extends State<BulkTagsScreen> {
  late List<CaseRec> _cases = untaggedCases();
  List<_Sug> _sug = [];
  bool _busy = false;
  String _msg = '';

  Future<void> _run() async {
    final batch = _cases.take(kBulkTagBatch).toList();
    if (batch.isEmpty) return;
    setState(() {
      _busy = true;
      _msg = '';
    });
    final r = await Ai.run(bulkTagsRequest(batch), context: context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.cancelled) return;
      if (r.offline) {
        _msg = tr('AI is not available right now. The local tools still work.');
      } else if (!r.ok) {
        _msg = (r.error ?? '').isEmpty ? tr('The AI request failed.') : r.error!;
      } else {
        // positions in the preview are the batch positions that had content
        final shown = [for (var i = 0; i < batch.length; i++) if (bulkLine(batch[i]).isNotEmpty) batch[i]];
        final byN = parseBulkTags(r.json, batch.length);
        _sug = [];
        byN.forEach((n, tags) {
          final rec = batch[n - 1];
          if (shown.contains(rec)) _sug.add(_Sug(rec, tags));
        });
        if (_sug.isEmpty) _msg = tr('Nothing new to suggest from this note.');
      }
    });
  }

  /// Refreshes the screen first, then writes the files (the UI never waits for the disk).
  Future<void> _apply() async {
    final done = <CaseRec>[];
    for (final s in _sug.where((e) => e.apply && !e.done)) {
      s.undo = applySuggestions(s.rec, [FieldSuggestion('tags', 'Tags', s.rec.tags.join(', '), s.tags.join(', '), apply: true)]);
      s.done = true;
      done.add(s.rec);
    }
    setState(() => _cases = untaggedCases());
    snack(context, trp('Tags added to {n} cases.', {'n': done.length}));
    for (final c in done) {
      await store.saveCase(c);
    }
  }

  Future<void> _undoAll() async {
    final done = <CaseRec>[];
    for (final s in _sug.where((e) => e.done && e.undo != null)) {
      undoSuggestions(s.rec, s.undo!);
      s.undo = null;
      s.done = false;
      done.add(s.rec);
    }
    setState(() => _cases = untaggedCases());
    snack(context, tr('Undone.'));
    for (final c in done) {
      await store.saveCase(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final any = _sug.any((e) => e.apply && !e.done);
    final undoable = _sug.any((e) => e.done && e.undo != null);
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'case', title: 'Suggest tags'),
      child: Scaffold(
        appBar: AppBar(title: Text('Suggest tags for untagged cases')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Text(trp('{n} cases have no tags.', {'n': _cases.length})),
          _gap(4),
          Text('The AI sees a short de-identified line per case (age group, sex, specialty, complaint, diagnosis). Cases marked "Never send this case to AI" are skipped. You see it before it is sent, and nothing is saved until you tap Apply.',
              style: Theme.of(context).textTheme.bodySmall),
          _gap(8),
          if (_cases.isNotEmpty)
            AiEntry(
              label: trp('Suggest tags ({n} cases)', {'n': _cases.length > kBulkTagBatch ? kBulkTagBatch : _cases.length}),
              feature: 'case_tags_bulk',
              filled: true,
              onPressed: _busy ? null : _run,
            )
          else
            Text('All your cases have tags.'),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: mm.Text(_msg)),
          for (final s in _sug)
            AppCard(
              child: CheckboxListTile(
                value: s.apply,
                onChanged: s.done ? null : (v) => setState(() => s.apply = v == true),
                controlAffinity: ListTileControlAffinity.leading,
                title: DirText('${s.rec.s('code')} • ${s.rec.title}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Wrap(spacing: 6, children: [for (final t in s.tags) Chip(visualDensity: VisualDensity.compact, label: mm.Text(tagLabel(t)))]),
              ),
            ),
          if (_sug.isNotEmpty) ...[
            _gap(6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.icon(onPressed: any ? _apply : null, icon: const Icon(Icons.done_all), label: Text('Apply selected')),
              if (undoable) OutlinedButton.icon(onPressed: _undoAll, icon: const Icon(Icons.undo), label: Text('Undo')),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ================================================================ home: morning brief + shortcuts

final Map<String, String> _briefMemo = {};

class MorningBriefCard extends StatefulWidget {
  const MorningBriefCard({super.key});
  @override
  State<MorningBriefCard> createState() => _MorningBriefCardState();
}

class _MorningBriefCardState extends State<MorningBriefCard> {
  bool _busy = false;
  String _err = '';

  Future<void> _write(MorningBrief b) async {
    setState(() {
      _busy = true;
      _err = '';
    });
    final r = await Ai.run(briefRequest(b), context: context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok && r.text.trim().isNotEmpty) {
        _briefMemo[b.digest] = r.text.trim();
      } else if (!r.cancelled) {
        _err = tr('AI is not available right now. The local tools still work.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = buildMorningBrief();
    final theme = Theme.of(context);
    final memo = _briefMemo[b.digest];
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.wb_sunny_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text('Morning brief', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          _gap(6),
          for (final l in b.lines())
            Padding(padding: const EdgeInsets.only(bottom: 2), child: DirText('• $l')),
          _gap(6),
          if (memo != null)
            AiOutputCard(text: memo, feature: 'summary_brief')
          else ...[
            AiEntry(label: tr('Write my brief'), feature: 'summary_brief', onPressed: _busy ? null : () => _write(b)),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: mm.Text(_err)),
            AiStateBuilder(
              builder: (context, enabled, online) => !enabled
                  ? const SizedBox.shrink()
                  : Padding(padding: const EdgeInsets.only(top: 2), child: Text('Only the numbers above are sent, never case content.', style: theme.textTheme.bodySmall)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// AI question bank link + Ask AI / Case of the day / Pre-shift quiz shortcuts.
class HomeAiCard extends StatelessWidget {
  const HomeAiCard({super.key});

  void _go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    int bank = 0;
    try {
      bank = store.listOf('aiquiz').length;
    } catch (_) {}
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome),
            const SizedBox(width: 8),
            Expanded(child: Text('AI helper', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          _gap(6),
          AiStateBuilder(builder: (context, enabled, online) {
            if (!enabled) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI is off. MedLog works fully without it.', style: theme.textTheme.bodySmall),
                TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => openAiSettings(context),
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: Text('Turn on AI'),
                ),
              ]);
            }
            return Wrap(spacing: 8, runSpacing: 4, children: [
              ActionChip(
                key: const ValueKey('home_ask_ai'),
                avatar: const Icon(Icons.question_answer_outlined, size: 18),
                label: Text('Ask AI'),
                onPressed: () => _go(context, const AskReferencesScreen()),
              ),
              ActionChip(
                key: const ValueKey('home_case_of_day'),
                avatar: const Icon(Icons.local_hospital_outlined, size: 18),
                label: Text('Case of the day'),
                onPressed: () => _go(context, const CaseOfDayScreen()),
              ),
              ActionChip(
                key: const ValueKey('home_preshift'),
                avatar: const Icon(Icons.quiz_outlined, size: 18),
                label: Text('Pre-shift quiz'),
                onPressed: () => _go(context, const AiQuizScreen()),
              ),
            ]);
          }),
          ListTile(
            key: const ValueKey('home_ai_bank'),
            contentPadding: EdgeInsets.zero,
            minVerticalPadding: 8,
            leading: const Icon(Icons.psychology_alt_outlined),
            title: Text('AI question bank'),
            subtitle: Text(bank == 0 ? tr('Make practice questions from your library') : trp('{n} questions saved', {'n': bank})),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _go(context, const AiQuizScreen()),
          ),
        ]),
      ),
    );
  }
}

class CaseOfDayScreen extends StatelessWidget {
  const CaseOfDayScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final topic = caseOfDayTopic();
    return AiToolScreen(
      title: tr('Case of the day'),
      kind: 'home',
      intro: '${tr('A short fictional teaching case on a topic from your weak spots or your main specialty')}: ${topic.isEmpty ? '-' : topic}',
      feature: 'quiz_case_of_day',
      runLabel: tr('Make today\'s case'),
      icon: Icons.local_hospital_outlined,
      build: (_) => caseOfDayRequest(topic),
    );
  }
}

// ================================================================ search

/// Prominent "Ask AI about this query" card under the search box.
class SearchAskAiCard extends StatelessWidget {
  final String query;
  const SearchAskAiCard({super.key, required this.query});

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      color: cs.tertiaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome),
            const SizedBox(width: 8),
            Expanded(child: mm.Text(q, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          _gap(6),
          AiEntry(
            label: tr('Ask AI about this query'),
            icon: Icons.question_answer_outlined,
            feature: 'ask_refs',
            filled: true,
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AskReferencesScreen(initialQuestion: q))),
          ),
        ]),
      ),
    );
  }
}

// ================================================================ portfolio

/// Portfolio AI tools: reflection draft, goal-gap analysis, CV text. All entries are visible; the screens explain when AI is off.
class PortfolioAiCard extends StatelessWidget {
  const PortfolioAiCard({super.key});

  void _go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome),
            const SizedBox(width: 8),
            Expanded(child: Text('AI portfolio tools', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            AiStateBuilder(builder: (c, enabled, online) => enabled ? const SizedBox.shrink() : Text('AI is off', style: theme.textTheme.bodySmall)),
          ]),
          _gap(6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            ActionChip(key: const ValueKey('pf_reflection'), avatar: const Icon(Icons.self_improvement, size: 18), label: Text('Reflection draft'), onPressed: () => _go(context, const ReflectionDraftScreen())),
            ActionChip(key: const ValueKey('pf_gap'), avatar: const Icon(Icons.flag_outlined, size: 18), label: Text('Goal gap analysis'), onPressed: () => _go(context, const GoalGapScreen())),
            ActionChip(key: const ValueKey('pf_cv'), avatar: const Icon(Icons.description_outlined, size: 18), label: Text('CV summary'), onPressed: () => _go(context, const CvSummaryScreen())),
          ]),
        ]),
      ),
    );
  }
}

class ReflectionDraftScreen extends StatefulWidget {
  const ReflectionDraftScreen({super.key});
  @override
  State<ReflectionDraftScreen> createState() => _ReflectionDraftScreenState();
}

class _ReflectionDraftScreenState extends State<ReflectionDraftScreen> {
  CaseRec? _case;

  Future<void> _pick() async {
    final c = await pickCase(context);
    if (c != null && mounted) setState(() => _case = c);
  }

  AiRequest? _req() {
    final c = _case;
    if (c == null) return null;
    final p = buildCasePayload(c);
    if (p.blocked) {
      snack(context, tr('This case is marked "Never send this case to AI". Turn it off in the case Info tab to use these tools.'));
      return null;
    }
    return p.isEmpty ? null : reflectionDraftRequest(p);
  }

  @override
  Widget build(BuildContext context) {
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'portfolio', title: 'Reflection draft'),
      child: Scaffold(
        appBar: AppBar(title: Text('Reflection draft')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Text('Pick one of your own cases and get a first draft of a reflection to start from. It is a DRAFT: you edit it and write it in your own words before it counts as your reflection.'),
          _gap(12),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.folder_open),
            label: mm.Text(_case == null ? tr('Choose a case') : '${_case!.s('code')} • ${_case!.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          _gap(4),
          Text('Only de-identified fields are sent, and you see them before sending.', style: Theme.of(context).textTheme.bodySmall),
          _gap(12),
          AiRunPanel(
            label: tr('Draft my reflection'),
            feature: 'report_reflection',
            icon: Icons.self_improvement,
            enabled: _case != null,
            needsCites: false,
            draftNote: tr('DRAFT written by AI. Edit it and make it yours before you rely on it.'),
            build: _req,
            footer: (res) {
              final j = res.json;
              if (j == null) return const SizedBox.shrink();
              final e = reflectionEntryFrom(j);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final k in const ['happened', 'felt', 'learned', 'next'])
                  if ((e[k] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(switch (k) { 'happened' => 'What happened', 'felt' => 'How I felt', 'learned' => 'What I learned', _ => 'What I will do next time' }, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                        DirText(e[k].toString()),
                      ]),
                    ),
                FilledButton.icon(
                  onPressed: () => editReflection(context, e),
                  icon: const Icon(Icons.edit_note),
                  label: Text('Edit and save as my reflection'),
                ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

class GoalGapScreen extends StatelessWidget {
  const GoalGapScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final gaps = goalGaps();
    final stats = weekStats();
    return AiToolScreen(
      title: tr('Goal gap analysis'),
      kind: 'portfolio',
      intro: tr('Your goals against the days left, calculated on your phone. The AI only suggests next actions from these numbers.'),
      feature: 'report_gap',
      runLabel: tr('Suggest next actions'),
      icon: Icons.flag_outlined,
      needsCites: false,
      draftNote: tr('Suggestions from your own numbers. You decide what to do.'),
      top: (c) => gaps.isEmpty
          ? Text('Add targets to your current rotation to see the gaps.')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final g in gaps) Padding(padding: const EdgeInsets.only(bottom: 4), child: DirText('• ${g.line()}'))]),
      build: (_) => gaps.isEmpty ? null : goalGapRequest(gaps, stats),
    );
  }
}

class CvSummaryScreen extends StatefulWidget {
  const CvSummaryScreen({super.key});
  @override
  State<CvSummaryScreen> createState() => _CvSummaryScreenState();
}

class _CvSummaryScreenState extends State<CvSummaryScreen> {
  String _rot = '';

  List<J> get _rots => store.rotations.where((r) => r['demo'] != true).toList();

  AiStats _stats() {
    if (_rot.isNotEmpty) {
      final r = _rots.where((e) => e['id'].toString() == _rot);
      if (r.isNotEmpty) return rotationStats(r.first);
    }
    final cases = store.cases.values.where((c) => c.d['demo'] != true && !c.id.startsWith('demo_')).toList();
    final procs = store.procedures.where((p) => p['demo'] != true).toList();
    return statsOfCases(cases, procs, title: 'All logged work');
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats();
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'portfolio', title: 'CV summary'),
      child: Scaffold(
        appBar: AppBar(title: Text('CV summary')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Text('A summary paragraph for your CV, written from the counts of your logbook (no case content). Edit it before you use it.'),
          _gap(8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            ChoiceChip(label: Text('Everything'), selected: _rot.isEmpty, onSelected: (_) => setState(() => _rot = '')),
            for (final r in _rots) ChoiceChip(label: mm.Text(store.rotationLabel(r)), selected: _rot == r['id'].toString(), onSelected: (_) => setState(() => _rot = r['id'].toString())),
          ]),
          _gap(8),
          AppCard(child: Padding(padding: const EdgeInsets.all(12), child: DirText(s.isEmpty ? tr('Nothing logged yet.') : s.plainText()))),
          _gap(8),
          AiRunPanel(
            label: tr('Write CV text'),
            feature: 'report_cv',
            icon: Icons.description_outlined,
            narrative: true,
            needsCites: false,
            enabled: !s.isEmpty,
            draftNote: tr('DRAFT written by AI from your counts. Check every number and edit it.'),
            build: () => cvRequest(s),
          ),
        ]),
      ),
    );
  }
}

// ================================================================ reports: optional narrative paragraph

/// Optional AI paragraph under a set of numbers (analytics, logbook). Aggregated counts only; marked as AI-generated.
class PeriodNarrativeCard extends StatelessWidget {
  final AiStats stats;
  final String kind; // 'analytics' | 'logbook'
  const PeriodNarrativeCard({super.key, required this.stats, this.kind = 'analytics'});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AiRunPanel(
        label: tr('Write a short summary'),
        feature: 'report_$kind',
        icon: Icons.notes_outlined,
        filled: false,
        narrative: true,
        needsCites: false,
        build: () => periodNarrativeRequest(stats, kind: kind),
      ),
    );
  }
}
