import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:share_plus/share_plus.dart';

import 'ai/ai_context.dart';
import 'screens_ai_tools.dart' show PortfolioAiCard;
import 'data.dart';
import 'error_log.dart';
import 'screens_ref.dart' show PrivacyPolicyScreen;
import 'goals_signoff.dart';
import 'screens_library.dart';
import 'screens_notebooks.dart';
import 'i18n.dart';
import 'main.dart' show navKeyFor, currentNavId;
import 'motion.dart';
import 'screens_calendar.dart';
import 'screens_cases.dart';
import 'screens_home.dart';
import 'screens_privacy.dart';
import 'ai/ai_store.dart' show AiStore;
import 'screens_access.dart' show AccessSettingsSection;
import 'rotation_plan.dart';
import 'theme.dart';
import 'ui.dart';
import 'widgets.dart';

// ================================================================ rotations

Future<void> editRotation(BuildContext context, [J? r]) async {
  final res = await showFormSheet(
    context,
    title: r == null ? 'New rotation' : 'Edit rotation',
    specs: [
      FieldSpec('name', 'Rotation / specialty', options: kSpecialtyNames),
      const FieldSpec('start', 'Start date', type: FT.date),
      const FieldSpec('end', 'End date', type: FT.date),
      const FieldSpec('hospital', 'Hospital / department'),
      const FieldSpec('supervisor', 'Supervisor (optional)'),
      const FieldSpec('goals', 'Goals in words (optional; use Targets for numbers)', type: FT.multi),
      const FieldSpec('note', 'Notes', type: FT.multi),
    ],
    initial: r ??
        <String, dynamic>{
          'id': newId('r'),
          'start': todayStr(),
        },
    canDelete: r != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeFrom(store.rotations, 'rotations.json', r!['id'].toString());
  } else {
    await store.upsert(store.rotations, 'rotations.json', res);
    // a new rotation: one question, one tap to a study plan for it
    if (r == null && context.mounted && '${res['end'] ?? ''}'.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.event_note_outlined),
          title: Text('Build a study plan for this rotation?'),
          content: Text('A weekly plan from your books, between its start and end dates.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Not now')),
            FilledButton(key: const Key('rot_plan_go'), onPressed: () => Navigator.pop(ctx, true), child: Text('Build plan')),
          ],
        ),
      );
      if (go == true && context.mounted) {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => RotationPlanScreen(rotation: res)));
      }
    }
  }
}

class RotationScreen extends StatelessWidget {
  final String rotationId;
  const RotationScreen({super.key, required this.rotationId});

  Future<void> _generate(BuildContext context, J rot) async {
    final start = parseDate((rot['start'] ?? '').toString());
    final end = parseDate((rot['end'] ?? '').toString());
    if (start == null || end == null) {
      snack(context, 'Set start and end dates for this rotation first.');
      return;
    }
    final days = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) => const _WeekdayDialog(),
    );
    if (days == null || days.isEmpty) return;
    var added = 0;
    var d = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!d.isAfter(last)) {
      if (days.contains(d.weekday) && store.shiftFor(fmtDate(d)) == null) {
        store.shifts.add(<String, dynamic>{
          'date': fmtDate(d),
          'type': 'Morning',
          'rotationId': rotationId,
          'updated': nowIso(),
        });
        added++;
      }
      d = d.add(const Duration(days: 1));
    }
    await store.saveList('shifts.json', store.shifts);
    store.refresh();
    if (context.mounted) snack(context, trp('Added {n} duty days.', {'n': added}));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final rot = store.rotationById(rotationId);
        if (rot == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Rotation not found')));
        }
        final theme = Theme.of(context);
        final cases = store.casesOfRotation(rotationId);
        final shifts = store.shifts.where((s) => s['rotationId'] == rotationId).toList();
        shifts.sort((a, b) =>
            (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
        final procs = store.procedures.where((p) => p['rotationId'] == rotationId).length;
        final perDay = <String, int>{};
        for (final c in cases) {
          perDay[c.s('date')] = (perDay[c.s('date')] ?? 0) + 1;
        }
        final signs = signCounts(rotationId: rotationId);
        final goals = (rot['goals'] ?? '').toString();
        final note = (rot['note'] ?? '').toString();
        final sup = (rot['supervisor'] ?? '').toString();

        return AiContextScope(
          ctx: const AiScreenContext(kind: 'portfolio', title: 'Rotation'),
          child: Scaffold(
          appBar: AppBar(
            title: Text(store.rotationLabel(rot)),
            actions: [
              IconButton(
                tooltip: tr('Export this rotation'),
                icon: const Icon(Icons.ios_share_outlined),
                onPressed: () => exportLogbook(context, rotationId: rotationId),
              ),
              IconButton(
                tooltip: tr('Edit'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => editRotation(context, rot),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${prettyDate((rot['start'] ?? '').toString())}'
                '${(rot['end'] ?? '').toString().isEmpty ? '' : '  $arrow  ${prettyDate(rot['end'].toString())}'}',
                style: theme.textTheme.titleMedium,
              ),
              if (sup.isNotEmpty) Text('${tr('Supervisor')}: $sup'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text(countLabel(cases.length, 'case'))),
                  Chip(label: Text(countLabel(shifts.length, 'duty day'))),
                  Chip(label: Text(countLabel(procs, 'procedure'))),
                  if (signs.total > 0)
                    ActionChip(
                      avatar: const Icon(Icons.verified_outlined, size: 18),
                      label: Text(trp('{a} of {b} signed', {'a': signs.signed, 'b': signs.total})),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignOffScreen())),
                    ),
                ],
              ),
              RotationTargets(rot: rot),
              const PortfolioAiCard(),
              if (goals.isNotEmpty) ...[
                const SectionHeader('Goals (free text)'),
                Text(goals),
              ],
              if (note.isNotEmpty) ...[
                const SectionHeader('Notes'),
                Text(note),
              ],
              SectionHeader(
                'Duty days',
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'gen') _generate(context, rot);
                    if (v == 'one') {
                      showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      ).then((d) {
                        if (d != null && context.mounted) {
                          editShift(context, fmtDate(d), rotationId: rotationId);
                        }
                      });
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'gen', child: Text('Generate by weekdays')),
                    PopupMenuItem(value: 'one', child: Text('Add one day')),
                  ],
                ),
              ),
              if (shifts.isEmpty)
                Text('No duty days yet. Use the menu to generate them by weekdays '
                    '(e.g. every Sat, Mon, Wed).'),
              for (final s in shifts)
                AppCard(
                  child: ListTile(
                    onTap: () => editShift(context, s['date'].toString(),
                        rotationId: rotationId),
                    title: Text(prettyDate(s['date'].toString())),
                    subtitle: Text([
                      tr((s['type'] ?? '').toString()),
                      countLabel(perDay[s['date']] ?? 0, 'case'),
                    ].where((e) => e.isNotEmpty).join(' • ')),
                  ),
                ),
              const SectionHeader('Cases'),
              if (cases.isEmpty) Text('No cases in this rotation yet.'),
              for (final c in (cases..sort((a, b) => b.s('date').compareTo(a.s('date')))))
                CaseTile(c),
            ],
          ),
          ),
        );
      },
    );
  }
}

class _WeekdayDialog extends StatefulWidget {
  const _WeekdayDialog();

  @override
  State<_WeekdayDialog> createState() => _WeekdayDialogState();
}

class _WeekdayDialogState extends State<_WeekdayDialog> {
  final Set<int> _sel = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Which weekdays are your duty days?'),
      content: Wrap(
        spacing: 8,
        children: [
          for (var i = 0; i < 7; i++)
            FilterChip(
              label: Text(kWeekdays[i]),
              selected: _sel.contains(i + 1),
              onSelected: (v) => setState(() {
                if (v) {
                  _sel.add(i + 1);
                } else {
                  _sel.remove(i + 1);
                }
              }),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _sel),
          child: const Text('Generate'),
        ),
      ],
    );
  }
}

// ================================================================ portfolio / stats

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  Widget _bars(BuildContext context, Map<String, int> data, {int top = 10, bool translate = false}) {
    if (data.isEmpty) return const Text('—');
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final shown = entries.take(top).toList();
    final maxV = shown.first.value;
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++)
          FadeSlideIn(
            index: i,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(translate ? tr(shown[i].key) : shown[i].key,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(child: AnimatedBar(shown[i].value / maxV)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    child: CountUp(shown[i].value, style: Theme.of(context).textTheme.labelLarge),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cases = store.cases.values.toList();
        final bySpec = <String, int>{};
        final byRole = <String, int>{};
        final byDx = <String, int>{};
        final perDay = <String, int>{};
        for (final c in cases) {
          final sp = c.s('specialty');
          if (sp.isNotEmpty) bySpec[sp] = (bySpec[sp] ?? 0) + 1;
          final ro = c.s('role');
          if (ro.isNotEmpty) byRole[ro] = (byRole[ro] ?? 0) + 1;
          var dx = c.s('finalDx').trim();
          if (dx.isEmpty) dx = c.s('workingDx').trim();
          if (dx.isNotEmpty) {
            final k = dx.toLowerCase();
            byDx[k] = (byDx[k] ?? 0) + 1;
          }
          final d = c.s('date');
          if (d.isNotEmpty) perDay[d] = (perDay[d] ?? 0) + 1;
        }
        final byProc = <String, int>{};
        for (final p in store.procedures) {
          final n = (p['name'] ?? '').toString();
          if (n.isNotEmpty) byProc[n] = (byProc[n] ?? 0) + 1;
        }
        final rots = List<J>.from(store.rotations)
          ..sort((a, b) =>
              (b['start'] ?? '').toString().compareTo((a['start'] ?? '').toString()));

        return AiContextScope(
          ctx: const AiScreenContext(kind: 'portfolio', title: 'Portfolio'),
          child: Scaffold(
          appBar: AppBar(
            title: const Text('Portfolio'),
            actions: [
              IconButton(
                tooltip: tr('Calendar'),
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                ),
              ),
              IconButton(
                tooltip: tr('Notebooks and tools'),
                icon: const Icon(Icons.library_books_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotebooksScreen()),
                ),
              ),
              IconButton(
                tooltip: tr('Settings'),
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              FadeSlideIn(
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.25,
                  children: [
                    _Big(Icons.folder_copy_outlined, cases.length, 'Cases'),
                    _Big(Icons.local_hospital_outlined, store.shifts.length, 'Duty days'),
                    _Big(Icons.healing_outlined, store.procedures.length, 'Procedures'),
                    _Big(Icons.edit_note, store.notes.length, 'Notes'),
                    _Big(Icons.swap_horiz, store.rotations.length, 'Rotations'),
                    _Big(Icons.star_outline, cases.where((c) => c.starred).length, 'Starred'),
                  ],
                ),
              ),
              const SectionHeader('Activity (last 16 weeks)'),
              FadeSlideIn(index: 1, child: _Heatmap(perDay)),
              Builder(builder: (context) {
                final sc = signCounts();
                return AppCard(
                  child: ListTile(
                    leading: const Icon(Icons.verified_outlined),
                    title: const Text('Supervisor sign-off'),
                    subtitle: Text(sc.total == 0
                        ? tr('Record who supervised each procedure and case')
                        : trp('{a} of {b} signed by a supervisor', {'a': sc.signed, 'b': sc.total})),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignOffScreen())),
                  ),
                );
              }),
              const PortfolioAiCard(),
              SectionHeader(
                'Rotations',
                trailing: TextButton.icon(
                  onPressed: () => editRotation(context),
                  icon: const Icon(Icons.add),
                  label: Text('Add'),
                ),
              ),
              if (rots.isEmpty) const Text('No rotations yet.'),
              for (var i = 0; i < rots.length; i++)
                FadeSlideIn(
                  index: i,
                  child: AppCard(
                    child: ListTile(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RotationScreen(rotationId: rots[i]['id'].toString()),
                        ),
                      ),
                      title: Text(store.rotationLabel(rots[i])),
                      subtitle: Text(
                        '${prettyDate((rots[i]['start'] ?? '').toString())}'
                        '${(rots[i]['end'] ?? '').toString().isEmpty ? '' : ' $arrow ${prettyDate(rots[i]['end'].toString())}'}'
                        '\n${countLabel(store.casesOfRotation(rots[i]['id'].toString()).length, 'case')}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
              const SectionHeader('Cases by specialty'),
              _bars(context, bySpec, translate: true),
              const SectionHeader('My role in cases'),
              _bars(context, byRole, translate: true),
              const SectionHeader('Most frequent diagnoses'),
              _bars(context, byDx, top: 8),
              const SectionHeader('Procedures'),
              _bars(context, byProc, translate: true),
              const SizedBox(height: 8),
              Text(
                'Counts show what you saw and did. They do not prove competence by themselves.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}

class _Big extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  const _Big(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        // scales down a little instead of overflowing when the font is taller (Arabic, large text)
        child: FittedBox(
          alignment: AlignmentDirectional.centerStart,
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(height: 4),
              CountUp(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(label, maxLines: 1, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// GitHub-style activity grid: one square per day, darker = more cases.
class _Heatmap extends StatelessWidget {
  final Map<String, int> perDay;
  const _Heatmap(this.perDay);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const weeks = 16;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // week columns end on today's week; Monday first (rows are Mon..Sun)
    final endMonday = today.subtract(Duration(days: today.weekday - 1));
    final start = endMonday.subtract(const Duration(days: 7 * (weeks - 1)));
    var maxV = 1;
    for (final v in perDay.values) {
      if (v > maxV) maxV = v;
    }
    final on = animOn(context);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Directionality(
          textDirection: Directionality.of(context),
          child: Row(
            children: [
              for (var w = 0; w < weeks; w++)
                Expanded(
                  child: Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Builder(builder: (_) {
                          final day = start.add(Duration(days: w * 7 + d));
                          final future = day.isAfter(today);
                          final n = perDay[fmtDate(day)] ?? 0;
                          final base = future
                              ? Colors.transparent
                              : (n == 0
                                  ? cs.surfaceContainerHighest
                                  : cs.primary.withAlpha((70 + 185 * (n / maxV)).round()));
                          return TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: on ? 0 : 1, end: 1),
                            duration: Duration(milliseconds: on ? 300 + w * 35 : 0),
                            curve: Curves.easeOut,
                            builder: (_, v, __) => Container(
                              margin: const EdgeInsets.all(1.5),
                              height: 14,
                              decoration: BoxDecoration(
                                color: base.withAlpha((base.a * 255 * v).round()),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================ settings

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _setPin() async {
    final a = await askText(context, 'New PIN (4–6 digits)',
        obscure: true, number: true, maxLength: 6);
    if (a == null) return;
    if (a.length < 4) {
      if (mounted) snack(context, 'PIN must be at least 4 digits.');
      return;
    }
    if (!mounted) return;
    final b = await askText(context, 'Repeat PIN', obscure: true, number: true, maxLength: 6);
    if (b == null) return;
    if (a != b) {
      if (mounted) snack(context, 'PINs do not match.');
      return;
    }
    await store.setPin(a);
    if (mounted) snack(context, 'PIN is set.');
  }

  Future<bool> _verifyPin() async {
    final cur = await askText(context, 'Enter current PIN',
        obscure: true, number: true, maxLength: 6);
    if (cur == null) return false;
    if (!store.checkPin(cur)) {
      if (mounted) snack(context, 'Wrong PIN.');
      return false;
    }
    return true;
  }

  Future<void> _removePin() async {
    if (!await _verifyPin()) return;
    await store.clearPin();
    if (mounted) snack(context, 'PIN removed.');
  }

  Future<void> _changePin() async {
    if (!await _verifyPin()) return;
    await _setPin();
  }

  Future<void> _editAuthor() async {
    final v = await askText(context, 'Your name for shared cases', hint: 'e.g. Dr. Sara');
    if (v == null) return;
    await store.setAuthor(v);
  }

  Future<void> _export() async {
    final pw = await askPassword(
      context,
      'Backup password',
      confirm: true,
      note: 'The backup is encrypted. If you forget this password nobody can open '
          'it — not even me. Write it down somewhere safe.',
    );
    if (pw == null) return;
    setState(() => _busy = true);
    try {
      final f = await store.exportBackup(pw);
      // re-open the file with the password before trusting it
      final v = await store.verifyBackupFile(f, pw);
      final good = v['bad'] == 0 && v['cases'] == v['expectCases'] && v['images'] == v['expectImages'];
      if (mounted) setState(() => _busy = false);
      if (!good) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.error_outline, color: Colors.red),
              title: Text('Backup check failed'),
              content: Text(trp(
                  'The file was created but does not match your data ({a}/{b} cases, {c}/{d} images, {e} damaged). Do not rely on it. Try again.',
                  {'a': v['cases']!, 'b': v['expectCases']!, 'c': v['images']!, 'd': v['expectImages']!, 'e': v['bad']!})),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK'))],
            ),
          );
        }
        return;
      }
      store.settings['lastBackupVerified'] = nowIso();
      await store.saveSettings();
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.verified_outlined, color: Colors.green),
            title: Text('Backup verified'),
            content: Text(trp(
                'The file opens with your password and contains {a} cases and {b} images. Now choose where to save or send it.',
                {'a': v['cases']!, 'b': v['images']!})),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Continue'))],
          ),
        );
      }
      await Share.shareXFiles([XFile(f.path)], text: 'MedLog backup');
    } catch (e) {
      if (mounted) snack(context, '${tr('Export failed')}: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    if (r == null || r.files.isEmpty || r.files.single.path == null) return;
    final bytes = await File(r.files.single.path!).readAsBytes();
    if (!mounted) return;
    String? pw;
    if (store.looksEncrypted(bytes)) {
      pw = await askPassword(context, 'Password of this file');
      if (pw == null) return;
    }
    setState(() => _busy = true);
    ImportPlan plan;
    try {
      plan = await store.previewImport(bytes, password: pw);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, '$e');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (plan.empty) {
      snack(context, trp('Nothing new in this file ({n} already up to date).', {'n': plan.unchanged}));
      return;
    }
    final ok = await confirmDialog(
      context,
      '${plan.isPack ? (plan.author.isEmpty ? tr('Cases shared') : trp('Cases shared by {name}', {'name': plan.author})) : tr('Backup')}:\n'
      '• ${trp('{n} new cases', {'n': plan.newCases})}\n'
      '• ${trp('{n} updated', {'n': plan.updatedCases})}\n'
      '• ${trp('{n} unchanged', {'n': plan.unchanged})}\n'
      '• ${trp('{n} new images', {'n': plan.images.length})}\n\n'
      '${plan.isPack ? tr('Your own cases are never overwritten.') : tr('The newer version of each item wins.')}',
      action: 'Import',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final msg = await store.applyImport(plan);
      if (mounted) snack(context, msg);
    } catch (e) {
      if (mounted) snack(context, '${tr('Import failed')}: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  final TextEditingController _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// "Last backup: 3 days ago" / "Never backed up".
  String _backupText() {
    final days = store.daysSinceBackup;
    return days == null
        ? tr('Never backed up')
        : '${tr('Last backup')}: ${days == 0 ? tr('today') : days == 1 ? tr('yesterday') : trp('{n} days ago', {'n': days})}';
  }

  Widget _backupNudge(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final days = store.daysSinceBackup;
    final old = days == null || days >= 14;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: old ? cs.tertiaryContainer.withAlpha(150) : cs.primaryContainer.withAlpha(90),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(old ? Icons.cloud_upload_outlined : Icons.verified_outlined, color: old ? cs.onTertiaryContainer : cs.primary),
            const SizedBox(width: 10),
            Expanded(child: m.Text(_backupText(), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          if (old)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('A backup protects your logbook if you lose, reset or replace this phone.', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Back up now'),
            ),
          ),
        ]),
      ),
    );
  }

  List<_SetSection> _sections(BuildContext context) {
    final images = store.imagesDir.listSync().length;
    final fontsNow = '${tr(arFontById(store.fontAr).label)} • ${tr(enFontById(store.fontEn).label)}';
    return [
      _SetSection(
        id: 'set_appearance',
        title: 'Appearance',
        icon: Icons.palette_outlined,
        subtitle: '${tr('Fonts')}: $fontsNow',
        terms: ['Appearance', 'Fonts', 'Arabic font', 'English font', 'Cairo', 'Tajawal', 'Times', 'Default', 'Mode', 'Light', 'Dark',
          'Theme', 'Text size', 'Pure black dark mode', 'Animations', 'colour color palette'],
        children: const [_AppearanceSection()],
      ),
      _SetSection(
        id: 'set_language',
        title: 'Language',
        icon: Icons.translate,
        initiallyOpen: true,
        terms: ['Language', 'English', 'العربية', 'Arabic', 'Auto', 'Medical terms language'],
        children: const [_LanguageSection()],
      ),
      _SetSection(
        id: 'set_library',
        title: 'Library',
        icon: Icons.local_library_outlined,
        initiallyOpen: true,
        terms: ['Library', 'Courses and library', 'Download medical courses to read offline', 'packs', 'offline'],
        children: [
          ListTile(
            leading: const Icon(Icons.local_library_outlined),
            title: const Text('Courses and library'),
            subtitle: const Text('Download medical courses to read offline'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PackManagerScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Library & AI settings'),
            subtitle: const Text('Reading, study sheet, search, downloads, AI'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibrarySettingsScreen())),
          ),
        ],
      ),
      _SetSection(
        id: 'set_security',
        title: 'Privacy & security',
        icon: Icons.lock_outline,
        terms: ['Privacy & security', 'Security', 'App lock (PIN)', 'PIN', 'Lock the app', 'fingerprint', 'face', 'Lock after',
          'Block screenshots & hide in recent apps', 'screenshots'],
        children: [
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('App lock (PIN)'),
            subtitle: Text(store.hasPin ? 'On' : 'Off'),
            onTap: store.hasPin ? null : _setPin,
            trailing: store.hasPin
                ? Wrap(
                    children: [
                      TextButton(onPressed: _changePin, child: const Text('Change')),
                      TextButton(onPressed: _removePin, child: const Text('Remove')),
                    ],
                  )
                : null,
          ),
          const SysSettingsSection(reminders: false, folds: false),
          SwitchListTile(
            secondary: const Icon(Icons.screen_lock_portrait_outlined),
            title: const Text('Block screenshots & hide in recent apps'),
            value: store.secureScreen,
            onChanged: (v) => store.setSecureScreen(v),
          ),
        ],
      ),
      _SetSection(
        id: 'set_sharing',
        title: 'Sharing',
        icon: Icons.share_outlined,
        terms: ['Sharing', 'My name on shared cases', 'Store patient initials on this phone', 'initials', 'author'],
        children: [
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('My name on shared cases'),
            subtitle: Text(store.author.isEmpty ? 'Not set' : store.author),
            onTap: _editAuthor,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.person_outline),
            title: const Text('Store patient initials on this phone'),
            subtitle: const Text('Off by default. Initials are never sent when sharing.'),
            value: store.useInitials,
            onChanged: (v) => store.setUseInitials(v),
          ),
        ],
      ),
      _SetSection(
        id: 'set_reminders',
        title: 'Reminders',
        icon: Icons.notifications_outlined,
        terms: ['Reminders', 'Daily review reminder', 'Remind me to finish my draft case', 'Weekly goals reminder', 'notifications'],
        children: const [SysSettingsSection(lock: false, folds: false)],
      ),
      _SetSection(
        id: 'set_ai',
        title: 'AI assistant',
        icon: Icons.auto_awesome_outlined,
        subtitle: AiStore.master && AiStore.hasKey() ? 'On' : 'Off',
        terms: ['AI assistant', 'AI', 'artificial intelligence', 'Gemini', 'Claude', 'OpenAI', 'API key', 'Activity log', 'Clear AI cache'],
        children: [
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI assistant'),
            subtitle: const Text('Optional. Your own key, stored only on this phone.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibrarySettingsScreen())),
          ),
        ],
      ),
      _SetSection(
        id: 'set_access',
        title: 'Access & members',
        icon: Icons.verified_user_outlined,
        terms: ['Access & members', 'Administrator', 'approval', 'Sign out', 'Members', 'Access requests'],
        children: const [AccessSettingsSection()],
      ),
      _SetSection(
        id: 'set_backup',
        title: 'Backup & export',
        icon: Icons.backup_outlined,
        subtitle: _backupText(),
        terms: ['Backup & export', 'Backup', 'Backup & import', 'Back up now', 'Export encrypted backup', 'Import backup or shared cases', 'Export logbook',
          'PDF', 'CSV', 'sign-off', 'supervisor', 'Last backup'],
        children: [
          _backupNudge(context),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export encrypted backup'),
            subtitle: Text(_backupText()),
            onTap: _busy ? null : _export,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Import backup or shared cases'),
            subtitle: const Text('.medlogbak, .medlogpack or an old ZIP — you see a preview first'),
            onTap: _busy ? null : _import,
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Export logbook (PDF or CSV)'),
            subtitle: const Text('Choose the range, add supervisor sign-off lines'),
            onTap: _busy ? null : () => exportLogbook(context),
          ),
        ],
      ),
      _SetSection(
        id: 'set_data',
        title: 'Data & recovery',
        icon: Icons.storage_outlined,
        terms: ['Data & recovery', 'Data health', 'Error log', 'Clean photo metadata', 'Load demo data', 'Remove demo data', 'On this phone'],
        children: [
          ListTile(
            leading: const Icon(Icons.health_and_safety_outlined),
            title: const Text('Data health'),
            subtitle: const Text('Check that every file can be read; recover from the last good copy'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataHealthScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Error log'),
            subtitle: const Text('Unexpected errors kept on this phone, to copy when reporting a problem'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ErrorLogScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.hide_image_outlined),
            title: const Text('Clean photo metadata'),
            subtitle: const Text('Remove hidden camera, time and GPS data from stored photos'),
            onTap: () async {
              final n = await cleanAllPhotoMetadata();
              if (mounted) snack(context, trp('{n} photos cleaned', {'n': n}));
            },
          ),
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: Text(store.hasDemo ? 'Remove demo data' : 'Load demo data'),
            subtitle: const Text('Fictional records to try every screen. Never included in backups.'),
            onTap: () async {
              if (store.hasDemo) {
                await store.removeDemo();
              } else {
                await store.loadDemo();
              }
              if (mounted) snack(context, store.hasDemo ? tr('Demo data loaded') : tr('Demo data removed'));
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('On this phone'),
            subtitle: Text('${countLabel(store.cases.length, 'case')} • ${trp('{n} image files', {'n': images})}\n'
                '${tr('Stored privately inside the app. Not in the gallery, not synced.')}\n'
                '${tr('Data format')} v$kSchema • ${tr('app')} $kAppVersion'),
            isThreeLine: true,
          ),
        ],
      ),
      _SetSection(
        id: 'set_about',
        title: 'About',
        icon: Icons.info_outline,
        terms: ['About', 'Version', 'Privacy reminders', 'Privacy policy', 'MedLog'],
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Privacy reminders\n'
              '• No names, ID numbers or exact ages.\n'
              '• Cover names / file numbers on any photo before capturing.\n'
              '• Be careful with exact dates and rare details that could identify a patient.\n'
              '• This is a personal learning log, not the official medical record.\n'
              '• Ask your hospital about its documentation and photo policy.\n'
              '• Keep backups somewhere private. A forgotten backup password cannot be recovered.\n'
              '• Voice typing on the keyboard may send audio to the internet: do not dictate patient details.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            subtitle: const Text('What stays on this phone and what is sent when you use optional features'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
          ),
          const _AboutCard(),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final q = _q.trim().toLowerCase();
        final all = _sections(context);
        final shown = q.isEmpty ? all : all.where((e) => e.matches(q)).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Settings & backup')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              if (_busy) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _q = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr('Search settings'),
                    suffixIcon: _q.isEmpty
                        ? null
                        : IconButton(
                            tooltip: tr('Clear'),
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _search.clear();
                              _q = '';
                            }),
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('No settings match your search.', style: theme.textTheme.bodyMedium)),
                ),
              for (final sec in shown)
                q.isEmpty
                    ? Fold(
                        key: ValueKey(sec.id),
                        id: sec.id,
                        title: tr(sec.title),
                        icon: sec.icon,
                        subtitle: sec.subtitle,
                        initiallyOpen: sec.initiallyOpen,
                        children: sec.children,
                      )
                    : _OpenSection(sec),
            ],
          ),
        );
      },
    );
  }
}

/// One group of the Settings screen. [terms] are what the search box looks for (English; the
/// Arabic text of each term is searched too).
class _SetSection {
  final String id;
  final String title;
  final IconData icon;
  final String? subtitle;
  final bool initiallyOpen;
  final List<String> terms;
  final List<Widget> children;
  const _SetSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.terms,
    required this.children,
    this.subtitle,
    this.initiallyOpen = false,
  });

  bool matches(String q) {
    final hay = [title, ...terms].expand((t) => [t, tr(t)]).join(' | ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }
}

/// A section shown fully open (used while searching).
class _OpenSection extends StatelessWidget {
  final _SetSection sec;
  const _OpenSection(this.sec);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(sec.icon, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(sec.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 6),
          ...sec.children,
        ]),
      ),
    );
  }
}

// ================================================================ appearance & about

class _LanguageSection extends StatelessWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: kLangSystem, label: Text('Auto')),
                ButtonSegment(value: kLangEn, label: Text('English')),
                ButtonSegment(value: kLangAr, label: Text('العربية')),
              ],
              selected: {store.lang},
              onSelectionChanged: (v) async {
                await store.setLook('lang', v.first);
                // the whole app restarts in the new language: come back to Settings
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  navKeyFor(currentNavId).currentState?.push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                });
              },
            ),
          ),
        ),
        if (isAr) const _MedTermsLanguage(),
      ],
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  Widget _seg(BuildContext context, String title, Widget control) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: control),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // fonts first: the most asked-for setting
        const _FontPicker(),
        _seg(
          context,
          tr('Mode'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto), label: Text('Auto')),
              ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
              ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
            ],
            selected: {store.themeMode},
            onSelectionChanged: (v) => store.setLook('themeMode', v.first),
          ),
        ),
        const _TextSizePicker(),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Text('Theme', style: Theme.of(context).textTheme.labelLarge),
        ),
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final p in kPalettes)
                _PaletteCard(p, selected: store.paletteId == p.id, dark: dark),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.contrast),
          title: const Text('Pure black dark mode'),
          subtitle: const Text('Saves battery on OLED screens'),
          value: store.amoled,
          onChanged: (v) => store.setLook('amoled', v),
        ),
        SwitchListTile(
          secondary: Icon(Icons.animation, color: cs.onSurfaceVariant),
          title: const Text('Animations'),
          subtitle: const Text('Heartbeat motion, transitions and counters'),
          value: store.motion,
          onChanged: (v) => store.setLook('motion', v),
        ),
      ],
    );
  }
}

class _MedTermsLanguage extends StatelessWidget {
  const _MedTermsLanguage();

  Future<void> _setMed(String v) async {
    await store.setLook('medLang', v);
    // like a language change: every screen is rebuilt, so come back to Settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navKeyFor(currentNavId).currentState?.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Medical terms language'), style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            ChoiceChip(selected: store.medLang != 'ar', onSelected: (_) => _setMed('en'), label: m.Text('English')),
            ChoiceChip(selected: store.medLang == 'ar', onSelected: (_) => _setMed('ar'), label: m.Text('العربية')),
          ]),
        ],
      ),
    );
  }
}

class _FontPicker extends StatelessWidget {
  const _FontPicker();

  Widget _row(BuildContext context, String title, String sample, List<FontChoice> options, String selected, String key) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in options)
                ChoiceChip(
                  selected: selected == f.id,
                  onSelected: (_) => store.setLook(key, f.id),
                  // every option is drawn in its own font so you can compare
                  label: m.Text(
                    '${f.id == 'tinos' ? f.label : tr(f.label)}  $sample',
                    style: TextStyle(fontFamily: f.family, fontSize: 16),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(context, tr('Arabic font'), 'سجلّي الطبي', kArFonts, store.fontAr, 'fontAr'),
        _row(context, tr('English font'), 'Clinical Logbook', kEnFonts, store.fontEn, 'fontEn'),
      ],
    );
  }
}

class _PaletteCard extends StatelessWidget {
  final AppPalette p;
  final bool selected;
  final bool dark;
  const _PaletteCard(this.p, {required this.selected, required this.dark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: GestureDetector(
        onTap: () => store.setLook('palette', p.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          width: 92,
          padding: const EdgeInsets.all(6),
          transform: Matrix4.diagonal3Values(selected ? 1.0 : 0.94, selected ? 1.0 : 0.94, 1),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2.4 : 1,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [p.seed, p.accent],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    PositionedDirectional(
                      top: 6,
                      end: 6,
                      child: AnimatedOpacity(
                        opacity: selected ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.check, size: 14, color: Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isAr ? p.nameAr : p.nameEn,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const MedLogMark(size: 72),
              const SizedBox(height: 12),
              Text('MedLog',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text('v$kAppVersion', style: theme.textTheme.labelMedium?.copyWith(color: cs.outline)),
              const SizedBox(height: 14),
              Text(designedBy,
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(designerName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              EcgBanner(color: cs.primary, height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextSizePicker extends StatelessWidget {
  const _TextSizePicker();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Text size', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<double>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0.9, label: Text('A-')),
                ButtonSegment(value: 1.0, label: Text('A')),
                ButtonSegment(value: 1.15, label: Text('A+')),
                ButtonSegment(value: 1.3, label: Text('A++')),
              ],
              selected: {
                [0.9, 1.0, 1.15, 1.3].reduce((a, b) => (a - store.textScale).abs() < (b - store.textScale).abs() ? a : b)
              },
              onSelectionChanged: (v) => store.setLook('textScale', v.first),
            ),
          ),
        ],
      ),
    );
  }
}

class DataHealthScreen extends StatefulWidget {
  const DataHealthScreen({super.key});

  @override
  State<DataHealthScreen> createState() => _DataHealthScreenState();
}

class _DataHealthScreenState extends State<DataHealthScreen> {
  Map<String, int>? _r;
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    final r = await store.verifyData();
    if (mounted) {
      setState(() {
        _r = r;
        _busy = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _r;
    final bad = r?['bad'] ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Data health')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (r != null)
            AppCard(
              color: bad == 0 ? cs.primaryContainer.withAlpha(120) : cs.errorContainer,
              child: ListTile(
                leading: Icon(bad == 0 ? Icons.verified_outlined : Icons.warning_amber_rounded),
                title: Text(bad == 0 ? 'Everything can be read' : 'Some files needed recovery'),
                subtitle: Text(
                    '${trp('{n} data files', {'n': r['files']!})} • ${countLabel(r['cases']!, 'case')} • ${trp('{n} image files', {'n': r['images']!})}'),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Every save keeps the previous good copy. If a file is damaged, the app uses that copy automatically. '
            'Files that cannot be read are kept in a corrupt folder, never deleted.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (store.healthLog.isNotEmpty) ...[
            const SectionHeader('Recovery log'),
            for (final l in store.healthLog) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: m.Text(l)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.refresh),
            label: Text('Check again'),
          ),
        ],
      ),
    );
  }
}
