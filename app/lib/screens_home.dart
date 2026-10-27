import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'data.dart';
import 'i18n.dart';
import 'motion.dart';
import 'quick_add.dart';
import 'screens_calendar.dart';
import 'screens_cases.dart';
import 'ai/ai_context.dart';
import 'screens_ai_cases.dart' show WeekSummaryCard;
import 'screens_ai_library.dart' show AskReferencesScreen;
import 'screens_ai_tools.dart' show MorningBriefCard, HomeAiCard;
import 'screens_learn.dart';
import 'screens_portfolio.dart';
import 'focus.dart';
import 'screens_review.dart';
import 'screens_search.dart';
import 'screens_study.dart';
import 'theme.dart';
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

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

class HomeScreen extends StatelessWidget {
  /// Lets shortcuts jump to another tab of the shell.
  final ValueChanged<int>? onOpenTab;
  const HomeScreen({super.key, this.onOpenTab});

  void _push(BuildContext context, Widget w) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final rot = store.currentRotation();
        final today = todayStr();
        final all = store.casesSorted();
        final todays = all.where((c) => c.s('date') == today).toList();
        final drafts =
            all.where((c) => c.s('status') == 'Draft').take(5).toList();
        final recent = all.take(5).toList();
        final shift = store.shiftFor(today);
        final weekAgo =
            fmtDate(DateTime.now().subtract(const Duration(days: 7)));
        final thisWeek =
            all.where((c) => c.s('date').compareTo(weekAgo) > 0).length;
        var n = 0;

        Widget stagger(Widget w) => FadeSlideIn(index: n++, child: w);
        openProceduresTabHook = () => openProceduresScreen(context);
        final focus = store.mode == 'study' ? const <FocusItem>[] : buildFocus();

        // "continue where you left off": the case I edited most recently (last 3 days)
        Widget? resume;
        final lastId = (store.settings['lastCase'] ?? '').toString();
        final lastAt =
            DateTime.tryParse((store.settings['lastCaseAt'] ?? '').toString());
        final lastRec = store.cases[lastId];
        if (lastRec != null &&
            lastAt != null &&
            DateTime.now().difference(lastAt.toLocal()).inDays < 3) {
          final tab = (store.settings['lastTab'] is int)
              ? store.settings['lastTab'] as int
              : 0;
          resume = InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      CaseEditorScreen(rec: lastRec, initialTab: tab)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  Icon(Icons.play_circle_outline, size: 20, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('${lastRec.s('code')} • ${lastRec.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Text('Continue', style: theme.textTheme.bodySmall),
                  const Icon(Icons.chevron_right, size: 20),
                ]),
              ),
            ),
          );
        }

        final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.7);
        final ecg = store.settings['homeEcg'] == true;
        // room for greeting + mode switch under the always-visible toolbar row
        final extra = (122 + (ecg ? 30 : 0)) * scale;

        return AiContextScope(
          ctx: const AiScreenContext(kind: 'home', title: 'Home'),
          child: CustomScrollView(
          slivers: [
            // ---- header: collapses to one toolbar row when you scroll
            SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: false,
              toolbarHeight: 56,
              expandedHeight: 56 + extra,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              elevation: 0,
              foregroundColor: Colors.white,
              titleSpacing: 16,
              title: Row(children: [
                const MedLogMark(size: 30),
                const SizedBox(width: 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: m.Text('MedLog',
                        maxLines: 1,
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
              actions: [
                IconButton(
                  tooltip: tr('Search'),
                  onPressed: () => _push(context, const SearchScreen()),
                  icon: const Icon(Icons.search, color: Colors.white),
                ),
                IconButton(
                  tooltip: tr('Portfolio'),
                  onPressed: () => _push(context, const PortfolioScreen()),
                  icon: const Icon(Icons.insights_outlined, color: Colors.white),
                ),
                IconButton(
                  tooltip: tr('Calendar'),
                  onPressed: () => _push(context, const CalendarScreen()),
                  icon: const Icon(Icons.calendar_month_outlined,
                      color: Colors.white),
                ),
                IconButton(
                  tooltip: tr('Settings'),
                  onPressed: () => _push(context, const SettingsScreen()),
                  icon: const Icon(Icons.settings_outlined, color: Colors.white),
                ),
                const SizedBox(width: 4),
              ],
              flexibleSpace: _HeaderBackdrop(
                greeting: _greeting(),
                mode: store.mode,
                onMode: (m) => store.setLook('mode', m),
                ecg: ecg,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // ---- one-tap actions (Quick case first)
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('home_quick_case'),
                            onPressed: () => showQuickAdd(context),
                            icon: const Icon(Icons.bolt, size: 20),
                            label: Text('Quick case'),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(horizontal: 16)),
                          ),
                          for (final a in <(IconData, String, VoidCallback)>[
                            (Icons.healing_outlined, 'Log procedure', () => editProcedure(context)),
                            (Icons.edit_note, 'New note', () => editNote(context)),
                            (Icons.help_outline, 'Add question', () => editQuestion(context)),
                            (Icons.auto_awesome, 'Ask AI', () => _push(context, const AskReferencesScreen())),
                          ])
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: 8),
                              child: ActionChip(
                                avatar: Icon(a.$1, size: 18),
                                label: Text(a.$2),
                                onPressed: a.$3,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (store.mode == 'study') ...[
                      stagger(const MorningBriefCard()),
                      stagger(const HomeAiCard()),
                      ...studyHomeSections(context, onOpenTab: onOpenTab),
                    ],
                    if (store.mode != 'study') ...[
                      // ---- today: the cases of the day
                      stagger(Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Builder(builder: (context) {
                          final big =
                              MediaQuery.textScalerOf(context).scale(1.0) > 1.15;
                          final title = Text(
                              '${prettyDate(today)} • ${countLabel(todays.length, 'case')}',
                              maxLines: big ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800));
                          final duty = TextButton.icon(
                            style: TextButton.styleFrom(
                                minimumSize: const Size(0, 48)),
                            onPressed: () => editShift(
                              context,
                              today,
                              rotationId:
                                  rot == null ? '' : rot['id'].toString(),
                            ),
                            icon: shift == null
                                ? const Icon(Icons.add, size: 18)
                                : Icon(Icons.circle,
                                    size: 12,
                                    color: shiftColor(
                                        (shift['type'] ?? '').toString())),
                            label: Text(
                                shift == null
                                    ? 'Duty day'
                                    : '${tr('Duty day')} • ${tr((shift['type'] ?? '').toString())}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          );
                          return big
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [title, duty])
                              : Row(children: [
                                  Expanded(child: title),
                                  Flexible(child: duty),
                                ]);
                        }),
                      )),
                      if (todays.isEmpty)
                        stagger(Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text('No cases logged today yet.',
                                style: theme.textTheme.bodySmall),
                          ),
                        ))
                      else ...[
                        for (final c in todays.take(3))
                          stagger(CaseTile(c,
                              key: ValueKey('today_${c.id}'),
                              margin: const EdgeInsets.symmetric(vertical: 4))),
                        if (todays.length > 3)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 48)),
                              onPressed:
                                  onOpenTab == null ? null : () => onOpenTab!(1),
                              child: Text(trp('All {n}', {'n': todays.length})),
                            ),
                          ),
                      ],
                      // ---- today's focus: compact one-line rows
                      if (focus.isNotEmpty || resume != null)
                        stagger(AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    12, 4, 4, 0),
                                child: Row(children: [
                                  Icon(Icons.flag_outlined,
                                      size: 18, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text('Today’s focus',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w800)),
                                  ),
                                  if (focus.length > 3)
                                    TextButton(
                                      style: TextButton.styleFrom(
                                          minimumSize: const Size(0, 48)),
                                      onPressed: () => _push(
                                          context, const FocusScreen()),
                                      child: Text(trp('All {n}',
                                          {'n': focus.length})),
                                    )
                                  else
                                    const SizedBox(height: 40),
                                ]),
                              ),
                              if (resume != null) resume,
                              for (final f in focus.take(3)) FocusRow(f),
                            ],
                          ),
                        )),
                      // ---- stats: one row
                      stagger(AppCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                          child: Row(
                            children: [
                              Expanded(
                                  child: _StatTile(Icons.folder_copy_outlined,
                                      all.length, 'Cases')),
                              Expanded(
                                  child: _StatTile(Icons.date_range_outlined,
                                      thisWeek, 'This week')),
                              Expanded(
                                  child: _StatTile(Icons.healing_outlined,
                                      store.procedures.length, 'Procedures')),
                            ],
                          ),
                        ),
                      )),
                      // ---- morning brief (local numbers; optional AI paragraph) + AI shortcuts and question bank
                      stagger(const MorningBriefCard()),
                      stagger(const HomeAiCard()),
                      // ---- week summary (numbers on the phone; optional AI narrative)
                      if (store.cases.isNotEmpty) stagger(const WeekSummaryCard()),
                      // ---- backup reminder
                      if (store.cases.isNotEmpty &&
                          (store.daysSinceBackup == null ||
                              store.daysSinceBackup! > 7))
                        stagger(AppCard(
                          color: cs.tertiaryContainer,
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.backup_outlined),
                            title: Text(store.daysSinceBackup == null
                                ? tr('You have never made a backup')
                                : trp('Last backup was {n} days ago',
                                    {'n': store.daysSinceBackup!})),
                            subtitle: Text('Tap to back up now'),
                            onTap: () => _push(context, const SettingsScreen()),
                          ),
                        )),
                      // ---- current rotation
                      stagger(AppCard(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            if (rot == null) {
                              editRotation(context);
                            } else {
                              _push(
                                  context,
                                  RotationScreen(
                                      rotationId: rot['id'].toString()));
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: rot == null
                                ? Row(
                                    children: [
                                      const Icon(Icons.add_circle_outline),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Add your first rotation (e.g. Internal Medicine, Oct 1 – Oct 31)',
                                          style: theme.textTheme.bodyLarge,
                                        ),
                                      ),
                                    ],
                                  )
                                : _RotationSummary(rot: rot),
                          ),
                        ),
                      )),
                      if (drafts.isNotEmpty) ...[
                        SectionHeader('Unfinished drafts',
                            trailing: TextButton(
                              style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 48)),
                              onPressed:
                                  onOpenTab == null ? null : () => onOpenTab!(1),
                              child: Text('All cases'),
                            )),
                        for (final c in drafts)
                          stagger(CaseTile(c,
                              key: ValueKey('draft_${c.id}'),
                              margin: const EdgeInsets.symmetric(vertical: 4))),
                      ],
                      if (recent.isNotEmpty) ...[
                        const SectionHeader('Recent cases'),
                        for (final c in recent)
                          stagger(CaseTile(c,
                              key: ValueKey('recent_${c.id}'),
                              margin: const EdgeInsets.symmetric(vertical: 4))),
                      ],
                      if (all.isEmpty)
                        EmptyState(
                          kind: EmptyKind.cases,
                          title: 'No cases yet',
                          message: 'Tap + and write just the complaint — '
                              'you can finish the rest after the shift.',
                          action: FilledButton.icon(
                            onPressed: () => showQuickAdd(context),
                            icon: const Icon(Icons.add),
                            label: Text('New case'),
                          ),
                        ),
                    ],
                    const SizedBox(height: 28),
                    const DesignerCredit(),
                    const SizedBox(height: 24),
                  ],
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

/// Gradient behind the toolbar: greeting and mode switch fade out as it collapses.
class _HeaderBackdrop extends StatelessWidget {
  final String greeting;
  final String mode;
  final ValueChanged<String> onMode;
  final bool ecg;
  const _HeaderBackdrop({
    required this.greeting,
    required this.mode,
    required this.onMode,
    required this.ecg,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = store.author;
    final top = MediaQuery.paddingOf(context).top;
    return LayoutBuilder(builder: (context, c) {
      final minH = top + 56;
      final maxH = c.maxHeight;
      // 1 = fully expanded, 0 = collapsed to the toolbar
      final t = maxH <= minH + 1 ? 0.0 : ((maxH - minH) / (maxH - minH + 40)).clamp(0.0, 1.0);
      final open = Curves.easeIn.transform(((maxH - minH - 8) / 60).clamp(0.0, 1.0));
      return Container(
        decoration: BoxDecoration(
          gradient: paletteGradient(context),
          borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(8 + 20 * (t > 0 ? 1.0 : 0.0))),
        ),
        child: ClipRect(
          child: Padding(
            padding: EdgeInsets.only(top: minH),
            child: Opacity(
              opacity: open,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        who.isEmpty ? tr(greeting) : '${tr(greeting)}, $who',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                      Text(prettyDate(todayStr()),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.white.withAlpha(230))),
                      const SizedBox(height: 8),
                      _ModeToggle(mode: mode, onChanged: onMode),
                      if (ecg) EcgBanner(color: Colors.white, height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  const _StatTile(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            CountUp(value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}

/// "Designed by ..." line shown at the bottom of Home and in About.
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
class _ModeToggle extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  Widget _seg(BuildContext context, String id, IconData icon, String label) {
    final sel = mode == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: sel ? Colors.black87 : Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.black87 : Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(46),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          _seg(context, 'shift', Icons.bolt, 'Shift'),
          _seg(context, 'study', Icons.school_outlined, 'Study'),
        ],
      ),
    );
  }
}
