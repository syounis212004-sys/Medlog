import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'ai/ai_api.dart';
import 'ai/ai_prefs.dart';
import 'core_topics.dart';
import 'data.dart';
import 'i18n.dart';
import 'lib_user.dart';
import 'library.dart';

/// "Suggest settings for me": local rules (work offline) that look at real usage on this phone and propose changes
/// as a checklist. Nothing changes without a tap on Apply; every applied change can be undone. An optional AI pass
/// (only when AI is on and online) explains the suggestions in one short paragraph and sends nothing but counts and pack ids.

typedef UndoFn = Future<void> Function();

class TuneItem {
  final String id;
  final IconData icon;
  final String title; // English template, translated on display
  final Map<String, Object> args;
  final String why;
  final Map<String, Object> whyArgs;
  final String actionLabel;

  /// Runs the change and returns how to undo it (null = nothing to undo, e.g. "open this section").
  final Future<UndoFn?> Function() apply;
  final bool opensSection;
  const TuneItem({
    required this.id,
    required this.icon,
    required this.title,
    this.args = const {},
    required this.why,
    this.whyArgs = const {},
    this.actionLabel = 'Apply',
    required this.apply,
    this.opensSection = false,
  });
  String get titleText => trp(title, args);
  String get whyText => trp(why, whyArgs);
}

/// Everything the rules look at (injectable for tests).
class TuneCtx {
  final double widthDp;
  final double sysTextScale;
  final double libFont;
  final bool wifiOnly;
  final List<PackMeta> packs;
  final int imageCacheBytes;
  final int? freeBytes;
  final String rotationPackId; // '' when there is no current rotation or it has no matching course
  final String rotationCourse; // display name of that course
  final int missingCore; // Core 250 topics of that specialty that no installed article covers
  final bool essentialsInstalled;
  final bool aiOn;
  final Map<String, int> aiUse; // feature group -> number of logged requests
  final int aiLogged;
  final Map<String, bool> aiFeatures;
  const TuneCtx({
    this.widthDp = 412,
    this.sysTextScale = 1.0,
    this.libFont = 1.0,
    this.wifiOnly = true,
    this.packs = const [],
    this.imageCacheBytes = 0,
    this.freeBytes,
    this.rotationPackId = '',
    this.rotationCourse = '',
    this.missingCore = 0,
    this.essentialsInstalled = true,
    this.aiOn = false,
    this.aiUse = const {},
    this.aiLogged = 0,
    this.aiFeatures = const {},
  });
}

String courseName(String packId) {
  for (final p in library.packs) {
    if (p.id == packId) return p.title;
  }
  return [for (final w in packId.split('-')) w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)].join(' ');
}

Future<UndoFn?> _setLook(String key, Object value, Object previous) async {
  await store.setLook(key, value);
  return () => store.setLook(key, previous);
}

/// The rules. Pure: the same context gives the same list.
List<TuneItem> tuneRules(TuneCtx c) {
  final out = <TuneItem>[];

  // 1) the current rotation -> the course to have on the phone
  if (c.rotationPackId.isNotEmpty && !c.packs.any((p) => p.id == c.rotationPackId)) {
    out.add(TuneItem(
      id: 'pack_${c.rotationPackId}',
      icon: Icons.download_for_offline_outlined,
      title: 'Download the {course} course',
      args: {'course': c.rotationCourse},
      why: 'It matches your current rotation and is not on this phone yet.',
      actionLabel: 'Open',
      opensSection: true,
      apply: () async => null,
    ));
  }
  if (c.missingCore >= 3 && !c.essentialsInstalled) {
    out.add(TuneItem(
      id: 'pack_essentials',
      icon: Icons.checklist,
      title: 'Download Clinical essentials',
      why: '{n} Core 250 topics of your rotation have no article on this phone yet.',
      whyArgs: {'n': c.missingCore},
      actionLabel: 'Open',
      opensSection: true,
      apply: () async => null,
    ));
  }

  // 2) article text size against the screen
  final big = c.libFont > 1.15;
  if (c.widthDp <= 380 && c.libFont > 1.2) {
    out.add(TuneItem(
      id: 'font_narrow',
      icon: Icons.text_fields,
      title: 'Set the article text size to 100%',
      why: 'On a narrow screen ({w} px wide) large text makes very short lines.',
      whyArgs: {'w': c.widthDp.round()},
      apply: () => _setLook('libFont', 1.0, c.libFont),
    ));
  } else if (c.sysTextScale >= 1.3 && big) {
    out.add(TuneItem(
      id: 'font_double',
      icon: Icons.text_fields,
      title: 'Set the article text size to 100%',
      why: 'Your phone text size is already large; the article size adds to it.',
      apply: () => _setLook('libFont', 1.0, c.libFont),
    ));
  } else if (c.widthDp >= 600 && c.libFont < 1.0) {
    out.add(TuneItem(
      id: 'font_wide',
      icon: Icons.text_fields,
      title: 'Set the article text size to 110%',
      why: 'The screen is wide ({w} px); a larger size is easier to read.',
      whyArgs: {'w': c.widthDp.round()},
      apply: () => _setLook('libFont', 1.1, c.libFont),
    ));
  }

  // 3) storage
  final free = c.freeBytes;
  if (free != null && free < 1024 * 1024 * 1024) {
    out.add(TuneItem(
      id: 'storage_low',
      icon: Icons.sd_storage_outlined,
      title: 'Free some space',
      why: 'Only {free} left on the phone. Pictures cache: {cache}.',
      whyArgs: {'free': fmtBytes(free), 'cache': fmtBytes(c.imageCacheBytes)},
      actionLabel: 'Open',
      opensSection: true,
      apply: () async => null,
    ));
  } else if (c.imageCacheBytes > 150 * 1024 * 1024) {
    out.add(TuneItem(
      id: 'cache_big',
      icon: Icons.cleaning_services_outlined,
      title: 'Clear the downloaded pictures cache',
      why: 'The pictures cache uses {cache}.',
      whyArgs: {'cache': fmtBytes(c.imageCacheBytes)},
      actionLabel: 'Open',
      opensSection: true,
      apply: () async => null,
    ));
  }

  // 4) Wi-Fi only
  final packBytes = c.packs.fold<int>(0, (a, p) => a + p.bytes);
  if (!c.wifiOnly && (packBytes > 50 * 1024 * 1024 || c.packs.any((p) => p.kind == 'images'))) {
    out.add(TuneItem(
      id: 'wifi_only',
      icon: Icons.wifi,
      title: 'Download on Wi-Fi only',
      why: 'Your courses and pictures are large ({size}); this avoids using mobile data by accident.',
      whyArgs: {'size': fmtBytes(packBytes)},
      apply: () async {
        await setLibWifiOnly(true);
        return () => setLibWifiOnly(false);
      },
    ));
  }

  // 5) AI features that were never used
  if (c.aiOn && c.aiLogged >= 5) {
    final unused = [for (final g in kAiGroups) if (c.aiFeatures[g] != false && (c.aiUse[g] ?? 0) == 0) g];
    if (unused.isNotEmpty && unused.length < kAiGroups.length) {
      out.add(TuneItem(
        id: 'ai_unused',
        icon: Icons.auto_awesome_outlined,
        title: 'Turn off AI features you never used',
        why: 'Not used so far: {list}.',
        whyArgs: {'list': unused.map((g) => tr(kAiGroupNames[g] ?? g)).join(', ')},
        apply: () async {
          final prev = {for (final g in unused) g: AiStore.features[g] != false};
          for (final g in unused) {
            AiStore.features[g] = false;
          }
          await AiStore.save();
          return () async {
            prev.forEach((g, v) => AiStore.features[g] = v);
            await AiStore.save();
          };
        },
      ));
    }
  }
  return out;
}

const Map<String, String> kAiGroupNames = {
  'ask': 'Ask my references',
  'explain': 'Explain / translate',
  'quiz': 'Question bank',
  'case': 'Case assistant',
  'reports': 'Reports & summaries',
  'help': 'App help',
};

/// Free space of the documents volume, or null when it cannot be read (the rule is then skipped).
Future<int?> freeStorageBytes() async {
  try {
    if (!Platform.isAndroid && !Platform.isLinux && !Platform.isMacOS) return null;
    final dir = library.ready ? library.dir.path : Directory.systemTemp.path;
    final r = await Process.run('df', ['-k', dir]).timeout(const Duration(seconds: 2));
    if (r.exitCode != 0) return null;
    final lines = (r.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final cols = lines.last.trim().split(RegExp(r'\s+'));
    if (cols.length < 4) return null;
    final kb = int.tryParse(cols[3]);
    return kb == null ? null : kb * 1024;
  } catch (_) {
    return null;
  }
}

/// Reads the real state of the phone into a [TuneCtx].
Future<TuneCtx> gatherTuneCtx(BuildContext context) async {
  final mq = MediaQuery.of(context);
  final rot = store.currentRotation();
  final rname = '${rot?['name'] ?? ''}';
  final packId = rname.isEmpty ? '' : (packIdForRotation(rname) ?? '');
  var missing = 0;
  if (packId.isNotEmpty) {
    try {
      final topics = await resolveCore250();
      missing = topics.where((t) => !t.resolved && packIdForRotation(t.specialty) == packId).length;
    } catch (_) {}
  }
  var cache = 0;
  try {
    cache = await library.imageCacheBytes();
  } catch (_) {}
  final use = <String, int>{};
  for (final e in AiAudit.entries) {
    if (e['k'] == 'flag') continue;
    final g = AiStore.groupOf('${e['f'] ?? ''}');
    use[g] = (use[g] ?? 0) + 1;
  }
  return TuneCtx(
    widthDp: mq.size.width,
    sysTextScale: mq.textScaler.scale(10) / 10,
    libFont: store.libFontScale,
    wifiOnly: libWifiOnly(),
    packs: List.of(library.packs),
    imageCacheBytes: cache,
    freeBytes: await freeStorageBytes(),
    rotationPackId: packId,
    rotationCourse: packId.isEmpty ? '' : courseName(packId),
    missingCore: missing,
    essentialsInstalled: library.pack(kEssentialsPackId) != null,
    aiOn: Ai.enabled,
    aiUse: use,
    aiLogged: use.values.fold(0, (a, b) => a + b),
    aiFeatures: Map.of(AiStore.features),
  );
}

/// The only data the optional AI pass gets: ids and counts, never case or log text.
Map<String, Object> aggregateForAi(TuneCtx c, List<TuneItem> items) => {
      'suggestionIds': [for (final i in items) i.id],
      'settings': {
        'articleTextScale': (c.libFont * 100).round(),
        'sheetStyle': store.libSheetStyle,
        'wifiOnly': c.wifiOnly,
        'screenWidthDp': c.widthDp.round(),
        'systemTextScale': double.parse(c.sysTextScale.toStringAsFixed(2)),
        'aiAnswerLang': AiPrefs.answerLang,
        'aiAnswerLength': AiPrefs.answerLength,
        'aiSourceMode': AiPrefs.sourceMode,
      },
      'installedPackIds': [for (final p in c.packs) p.id],
      'rotationCourseId': c.rotationPackId,
      'packCount': c.packs.length,
    };

/// One short paragraph from the AI. Returns null when AI is off/offline/declined or failed (the checklist stays).
Future<String?> explainSuggestionsWithAi(BuildContext context, TuneCtx c, List<TuneItem> items) async {
  if (items.isEmpty || !Ai.enabled) return null;
  final lang = AiPrefs.answerLang == 'en' ? 'English' : 'Arabic (keep medical and app terms in English)';
  final r = await Ai.run(
    AiRequest(
      feature: 'help_settings_tune',
      system: 'You explain app-setting suggestions to a medical trainee. Write ONE short paragraph (at most 70 words) in $lang, plain words, '
          'no markdown, no medical advice. Say why the listed suggestions help and that nothing changes unless the user taps Apply.',
      prompt: 'Aggregated, non-identifying data about the settings and the suggestions (JSON):\n${jsonEncode(aggregateForAi(c, items))}',
      level: AiLevel.none,
      maxTokens: 220,
    ),
    context: context,
  );
  if (!r.ok || r.text.trim().isEmpty) return null;
  return r.text.trim();
}

// ============================================================================ UI

class TunerCard extends StatefulWidget {
  /// Opens the settings section that the suggestion points to (id of the item).
  final void Function(String itemId) onOpen;

  /// Tests inject a context instead of reading the phone.
  final Future<TuneCtx> Function(BuildContext)? gather;
  const TunerCard({super.key, required this.onOpen, this.gather});
  @override
  State<TunerCard> createState() => _TunerCardState();
}

class _TunerCardState extends State<TunerCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // the checklist survives scrolling away (e.g. after "Open")

  List<TuneItem>? _items;
  TuneCtx? _ctx;
  bool _busy = false;
  bool _aiBusy = false;
  String _aiText = '';
  final Map<String, UndoFn?> _undo = {};
  final Set<String> _done = {};

  @override
  void initState() {
    super.initState();
    if (Ai.enabled) Ai.isOnline(); // refreshes Ai.online (the AI explanation button needs it)
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _aiText = '';
    });
    final ctx = await (widget.gather ?? gatherTuneCtx)(context);
    if (!mounted) return;
    setState(() {
      _ctx = ctx;
      _items = tuneRules(ctx);
      _undo.clear();
      _done.clear();
      _busy = false;
    });
  }

  Future<void> _apply(TuneItem it) async {
    final u = await it.apply();
    if (!mounted) return;
    if (it.opensSection) {
      widget.onOpen(it.id);
      return;
    }
    setState(() {
      _undo[it.id] = u;
      _done.add(it.id);
    });
  }

  Future<void> _undoIt(TuneItem it) async {
    final u = _undo[it.id];
    if (u != null) await u();
    if (!mounted) return;
    setState(() {
      _done.remove(it.id);
      _undo.remove(it.id);
    });
  }

  Future<void> _applyAll() async {
    for (final it in List.of(_items ?? const <TuneItem>[])) {
      if (!it.opensSection && !_done.contains(it.id)) await _apply(it);
    }
  }

  Future<void> _explain() async {
    final items = _items;
    final ctx = _ctx;
    if (items == null || ctx == null) return;
    setState(() => _aiBusy = true);
    final t = await explainSuggestionsWithAi(context, ctx, items);
    if (!mounted) return;
    setState(() {
      _aiBusy = false;
      _aiText = t ?? '';
    });
    if (t == null) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('The AI explanation is not available now. The suggestions above still work.')));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final items = _items;
    final canApplyAll = items != null && items.where((i) => !i.opensSection && !_done.contains(i.id)).length > 1;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: cs.primaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.primary.withValues(alpha: 0.35))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.tune, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Suggest settings for me', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          Text('Looks at how you use MedLog on this phone (rotation, courses, screen, storage). Nothing changes until you tap Apply, and you can undo.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: const Key('tune_run'),
              onPressed: _busy ? null : _run,
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high, size: 18),
              label: Text(items == null ? 'Suggest settings for me' : 'Check again'),
            ),
          ),
          if (items != null && items.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text('Your settings already look good for how you use the app.', style: theme.textTheme.bodyMedium)),
          if (items != null)
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(_done.contains(it.id) ? Icons.check_circle : it.icon, size: 20, color: _done.contains(it.id) ? Colors.green : cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          m.Text(it.titleText, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          m.Text(it.whyText, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: _done.contains(it.id)
                          ? TextButton.icon(key: Key('tune_undo_${it.id}'), onPressed: () => _undoIt(it), icon: const Icon(Icons.undo, size: 18), label: Text('Undo'))
                          : FilledButton.tonal(key: Key('tune_apply_${it.id}'), onPressed: () => _apply(it), child: Text(it.actionLabel)),
                    ),
                  ]),
                ),
              ),
          if (canApplyAll)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(key: const Key('tune_apply_all'), onPressed: _applyAll, child: Text('Apply all'))),
            ),
          if (items != null && items.isNotEmpty)
            ValueListenableBuilder<bool>(
              valueListenable: Ai.online,
              builder: (context, online, _) {
                if (!Ai.enabled || !online) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: const Key('tune_ai'),
                      onPressed: _aiBusy ? null : _explain,
                      icon: _aiBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 18),
                      label: Text('Explain with AI'),
                    ),
                  ),
                );
              },
            ),
          if (_aiText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: cs.tertiaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  m.Text(_aiText, key: const Key('tune_ai_text')),
                  const SizedBox(height: 4),
                  Text('AI-generated, not medically reviewed', style: theme.textTheme.labelSmall),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
