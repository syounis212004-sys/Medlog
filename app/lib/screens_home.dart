import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'data.dart';
import 'i18n.dart';
import 'motion.dart';
import 'quick_add.dart';
import 'screens_cases.dart';
import 'ai/ai_context.dart';
import 'screens_learn.dart';
import 'screens_portfolio.dart';
import 'focus.dart';
import 'review.dart';
import 'screens_review.dart';
import 'screens_search.dart';
import 'app_icons.dart';
import 'home_hero.dart';
import 'ui.dart';
import 'widgets.dart';

const List<FieldSpec> kShiftSpecs = [
  FieldSpec('type', 'Shift type',
      type: FT.choice, options: ['Morning', 'Evening', 'Night', 'On-call']),
  FieldSpec('note', 'Note about the day', type: FT.multi),
];

Future<void> editShift(BuildContext context, String date,
    {String rotationId = ''}) async {
  final cur = store.shiftFor(date);
  final res = await showFormSheet(
    context,
    title: '${tr('Duty day')} • ${prettyDate(date)}',
    specs: kShiftSpecs,
    initial: cur ??
        <String, dynamic>{
          'date': date,
          'type': 'Morning',
          'rotationId': rotationId,
        },
    canDelete: cur != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeFrom(store.shifts, 'shifts.json', date, key: 'date');
  } else {
    await store.upsert(store.shifts, 'shifts.json', res, key: 'date');
  }
}


class HomeScreen extends StatelessWidget {
  /// Lets shortcuts jump to another tab of the shell.
  final ValueChanged<int>? onOpenTab;
  const HomeScreen({super.key, this.onOpenTab});

  void _push(BuildContext context, Widget w) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  Widget _big(BuildContext context, IconData icon, String title, String sub, VoidCallback onTap, {Key? key}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      key: key,
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(radius: 22, backgroundColor: cs.primaryContainer, child: Icon(icon, color: cs.onPrimaryContainer)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                m.Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (sub.isNotEmpty) m.Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final rot = store.currentRotation();
        final all = store.casesSorted();
        final drafts = all.where((c) => c.s('status') == 'Draft').take(3).toList();
        final recent = all.take(3).toList();
        var n = 0;

        Widget stagger(Widget w) => FadeSlideIn(index: n++, child: w);
        openProceduresTabHook = () => openProceduresScreen(context);
        final focus = buildFocus();
        final due = ReviewEngine.dueCount();

        // "continue where you left off": the case I edited most recently (last 3 days)
        Widget? resume;
        final lastId = (store.settings['lastCase'] ?? '').toString();
        final lastAt = DateTime.tryParse((store.settings['lastCaseAt'] ?? '').toString());
        final lastRec = store.cases[lastId];
        if (lastRec != null && lastRec.s('status') != 'Completed' && lastAt != null && DateTime.now().difference(lastAt.toLocal()).inDays < 3) {
          final tab = (store.settings['lastTab'] is int) ? store.settings['lastTab'] as int : 0;
          resume = InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: lastRec, initialTab: tab))),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  Icon(Icons.play_circle_outline, size: 20, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(child: m.Text('${lastRec.s('code')} • ${lastRec.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Text('Continue', style: theme.textTheme.bodySmall),
                  const Icon(Icons.chevron_right, size: 20),
                ]),
              ),
            ),
          );
        }

        return AiContextScope(
          ctx: const AiScreenContext(kind: 'home', title: 'Home'),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                automaticallyImplyLeading: false,
                toolbarHeight: 60,
                titleSpacing: 16,
                title: Row(children: [
                  const MedLogMark(size: 32),
                  const SizedBox(width: 10),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: m.Text('MedLog', maxLines: 1, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)))),
                ]),
                actions: [
                  IconButton(tooltip: tr('Search'), onPressed: () => _push(context, const SearchScreen()), icon: const Icon(Icons.search)),
                  IconButton(tooltip: tr('Settings'), onPressed: () => _push(context, const SettingsScreen()), icon: const Icon(Icons.settings_outlined)),
                  const SizedBox(width: 4),
                ],
              ),
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        stagger(HomeHero(now: DateTime.now())),
                        const SizedBox(height: 14),
                        // ---- what needs me now: at most three things, nothing when there is nothing
                        if (focus.isNotEmpty || resume != null)
                          stagger(AppCard(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 0),
                                child: Row(children: [
                                  Icon(Icons.flag_outlined, size: 18, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text('Today’s focus', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                                  if (focus.length > 3)
                                    TextButton(
                                      style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                                      onPressed: () => _push(context, const FocusScreen()),
                                      child: Text(trp('All {n}', {'n': focus.length})),
                                    )
                                  else
                                    const SizedBox(height: 40),
                                ]),
                              ),
                              if (resume != null) resume,
                              for (final f in focus.take(3)) FocusRow(f),
                            ]),
                          )),
                        const SizedBox(height: 4),
                        // ---- four big doors
                        stagger(Column(children: [
                          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Expanded(child: _big(context, AppIcons.cases, tr('Cases'), trp('{n} cases', {'n': all.length}), () => onOpenTab?.call(1), key: const Key('home_cases'))),
                            const SizedBox(width: 10),
                            Expanded(child: _big(context, AppIcons.library, tr('Library'), tr('Your books and courses'), () => onOpenTab?.call(2), key: const Key('home_library'))),
                          ])),
                          const SizedBox(height: 10),
                          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Expanded(child: _big(context, AppIcons.learn, tr('Learn'), due > 0 ? trp('{n} cards to review', {'n': due}) : tr('Review and practise'), () => _push(context, const LearnScreen()), key: const Key('home_learn'))),
                            const SizedBox(width: 10),
                            Expanded(child: _big(context, AppIcons.tools, tr('Tools'), tr('Calculators, doses, search'), () => onOpenTab?.call(3), key: const Key('home_tools'))),
                          ])),
                        ])),
                        const SizedBox(height: 6),
                        // ---- backup reminder
                        if (store.cases.isNotEmpty && (store.daysSinceBackup == null || store.daysSinceBackup! > 7))
                          stagger(AppCard(
                            color: cs.tertiaryContainer,
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.backup_outlined),
                              title: Text(store.daysSinceBackup == null ? tr('You have never made a backup') : trp('Last backup was {n} days ago', {'n': store.daysSinceBackup!})),
                              subtitle: Text('Tap to back up now'),
                              onTap: () => _push(context, const SettingsScreen()),
                            ),
                          )),
                        // ---- current rotation (and a way to add the next one)
                        stagger(AppCard(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              if (rot == null) {
                                editRotation(context);
                              } else {
                                _push(context, RotationScreen(rotationId: rot['id'].toString()));
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: rot == null
                                  ? Row(children: [
                                      const Icon(Icons.add_circle_outline),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text('Add your first rotation (e.g. Internal Medicine, Oct 1 – Oct 31)', style: theme.textTheme.bodyLarge)),
                                    ])
                                  : Row(children: [
                                      Expanded(child: _RotationSummary(rot: rot)),
                                      IconButton(
                                        key: const Key('home_new_rotation'),
                                        tooltip: tr('New rotation'),
                                        icon: const Icon(Icons.add_circle_outline),
                                        onPressed: () => editRotation(context),
                                      ),
                                    ]),
                            ),
                          ),
                        )),
                        if (drafts.isNotEmpty) ...[
                          SectionHeader('Unfinished drafts',
                              trailing: TextButton(
                                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                                onPressed: () => onOpenTab?.call(1),
                                child: Text('All cases'),
                              )),
                          for (final c in drafts) stagger(CaseTile(c, key: ValueKey('draft_${c.id}'), margin: const EdgeInsets.symmetric(vertical: 4))),
                        ],
                        if (recent.isNotEmpty) ...[
                          const SectionHeader('Recent cases'),
                          for (final c in recent) stagger(CaseTile(c, key: ValueKey('recent_${c.id}'), margin: const EdgeInsets.symmetric(vertical: 4))),
                        ],
                        if (all.isEmpty)
                          EmptyState(
                            kind: EmptyKind.cases,
                            title: 'No cases yet',
                            message: 'Tap + and write just the complaint — you can finish the rest after the shift.',
                            action: FilledButton.icon(onPressed: () => showQuickAdd(context), icon: const Icon(Icons.add), label: Text('New case')),
                          ),
                        const SizedBox(height: 28),
                        const DesignerCredit(),
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DesignerCredit extends StatelessWidget {
  const DesignerCredit({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        Divider(color: cs.outlineVariant),
        const SizedBox(height: 8),
        Text(designedBy,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(designerName,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('MedLog v$kAppVersion',
            style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
      ],
    );
  }
}

class _RotationSummary extends StatelessWidget {
  final J rot;
  const _RotationSummary({required this.rot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = rot['id'].toString();
    final cases = store.casesOfRotation(id).length;
    final days = store.shifts.where((s) => s['rotationId'] == id).length;
    final procs = store.procedures.where((p) => p['rotationId'] == id).length;
    final start = (rot['start'] ?? '').toString();
    final end = (rot['end'] ?? '').toString();

    // how far through the rotation we are
    double? progress;
    final sd = parseDate(start);
    final ed = parseDate(end);
    if (sd != null && ed != null && ed.isAfter(sd)) {
      final total = ed.difference(sd).inHours;
      final done = DateTime.now().difference(sd).inHours;
      progress = (done / total).clamp(0.0, 1.0);
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current rotation', style: theme.textTheme.labelMedium),
              Text(store.rotationLabel(rot), style: theme.textTheme.titleLarge),
              if (start.isNotEmpty)
                Text(
                    '${prettyDate(start)}${end.isEmpty ? '' : '  $arrow  ${prettyDate(end)}'}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                children: [
                  Text(countLabel(cases, 'case')),
                  Text(countLabel(days, 'duty day')),
                  Text(countLabel(procs, 'procedure')),
                ],
              ),
            ],
          ),
        ),
        if (progress != null) ...[
          const SizedBox(width: 12),
          AnimatedRing(
            progress,
            size: 64,
            center: Text('${(progress * 100).round()}%',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ],
      ],
    );
  }
}

/// Shift (fast documentation) / Study (practice and review) switch in the header.
