import 'package:flutter/material.dart' hide Text;

import 'data.dart';
import 'i18n.dart';
import 'motion.dart';
import 'quick_add.dart';
import 'screens_cases.dart';
import 'screens_home.dart';
import 'ui.dart';
import 'widgets.dart';

Color shiftColor(String type) {
  switch (type) {
    case 'Morning':
      return const Color(0xFFF9A825);
    case 'Evening':
      return const Color(0xFFEF6C00);
    case 'Night':
      return const Color(0xFF3949AB);
    case 'On-call':
      return const Color(0xFFD32F2F);
    default:
      return const Color(0xFF00897B);
  }
}

/// Month view of duty days and cases. Tap a day to see it, mark a duty or add a case.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  late String _sel;
  int _dir = 1; // slide direction of the last month change

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    _sel = todayStr();
  }

  void _shift(int delta) {
    setState(() {
      _dir = delta;
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  void _today() {
    final n = DateTime.now();
    final target = DateTime(n.year, n.month);
    setState(() {
      _dir = target.isAfter(_month) ? 1 : -1;
      _month = target;
      _sel = todayStr();
    });
  }

  int get _weekStart => isAr ? 6 : 1; // Saturday first in Arabic, Monday in English

  Widget _grid(BuildContext context, Map<String, int> perDay) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final first = DateTime(_month.year, _month.month, 1);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = (first.weekday - _weekStart + 7) % 7;
    final rows = ((lead + days) / 7).ceil();
    final today = todayStr();
    final maxCases = perDay.values.fold<int>(1, (a, b) => a > b ? a : b);
    final cells = <Widget>[];
    for (var r = 0; r < rows; r++) {
      final row = <Widget>[];
      for (var c = 0; c < 7; c++) {
        final idx = r * 7 + c - lead + 1;
        if (idx < 1 || idx > days) {
          row.add(const Expanded(child: SizedBox(height: 52)));
          continue;
        }
        final d = DateTime(_month.year, _month.month, idx);
        final ds = fmtDate(d);
        final shift = store.shiftFor(ds);
        final n = perDay[ds] ?? 0;
        final isSel = ds == _sel;
        final isToday = ds == today;
        final heat = n == 0 ? 0.0 : 0.18 + 0.5 * (n / maxCases);
        row.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _sel = ds),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSel
                        ? cs.primary
                        : (n > 0 ? cs.primary.withAlpha((heat * 255).round()) : null),
                    borderRadius: BorderRadius.circular(14),
                    border: isToday && !isSel ? Border.all(color: cs.primary, width: 1.6) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$idx',
                        style: TextStyle(
                          fontWeight: isToday || isSel ? FontWeight.w800 : FontWeight.w500,
                          color: isSel
                              ? cs.onPrimary
                              : (n > 0 && heat > 0.45 ? cs.onPrimary : cs.onSurface),
                        ),
                      ),
                      const SizedBox(height: 3),
                      SizedBox(
                        height: 8,
                        child: shift == null
                            ? null
                            : Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: shiftColor((shift['type'] ?? '').toString()),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: isSel ? cs.onPrimary : Colors.transparent, width: 1.2),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      cells.add(Row(children: row));
    }
    return Column(children: cells);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final perDay = <String, int>{};
        for (final c in store.cases.values) {
          final d = c.s('date');
          perDay[d] = (perDay[d] ?? 0) + 1;
        }
        final monthPrefix = '${_month.year}-${two(_month.month)}';
        final monthCases = perDay.entries
            .where((e) => e.key.startsWith(monthPrefix))
            .fold<int>(0, (a, e) => a + e.value);
        final monthDuty = store.shifts.where((s) => (s['date'] ?? '').toString().startsWith(monthPrefix)).length;
        final selCases = store.casesSorted().where((c) => c.s('date') == _sel).toList();
        final selShift = store.shiftFor(_sel);
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final slideFrom = Offset(_dir * (rtl ? -0.25 : 0.25), 0);

        return Scaffold(
          appBar: AppBar(
            title: Text('Calendar'),
            actions: [
              IconButton(
                tooltip: tr('Today'),
                icon: const Icon(Icons.today_outlined),
                onPressed: _today,
              ),
            ],
          ),
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 250) return;
              // swiping towards the reading direction goes to the next month
              final towardsEnd = rtl ? v > 0 : v < 0;
              _shift(towardsEnd ? 1 : -1);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: tr('Previous month'),
                      onPressed: () => _shift(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(begin: slideFrom, end: Offset.zero).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          '${monthName(_month.month - 1)} ${_month.year}',
                          key: ValueKey(monthPrefix),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Next month'),
                      onPressed: () => _shift(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Center(
                          child: Text(
                            weekdayName(((_weekStart - 1) + i) % 7),
                            style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: slideFrom, end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(key: ValueKey(monthPrefix), child: _grid(context, perDay)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (final t in const ['Morning', 'Evening', 'Night', 'On-call'])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 10, color: shiftColor(t)),
                          const SizedBox(width: 4),
                          Text(t, style: theme.textTheme.labelSmall),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.folder_copy_outlined, size: 18),
                      label: Text(countLabel(monthCases, 'case')),
                    ),
                    Chip(
                      avatar: const Icon(Icons.local_hospital_outlined, size: 18),
                      label: Text(countLabel(monthDuty, 'duty day')),
                    ),
                  ],
                ),
                const SectionHeader('Selected day'),
                AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(prettyDate(_sel), style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (selShift != null)
                              Chip(
                                avatar: Icon(Icons.circle,
                                    size: 12, color: shiftColor((selShift['type'] ?? '').toString())),
                                label: Text('${tr('Duty day')} • ${tr((selShift['type'] ?? '').toString())}'),
                              ),
                            OutlinedButton.icon(
                              onPressed: () {
                                final rot = store.currentRotation();
                                editShift(context, _sel,
                                    rotationId: rot == null ? '' : rot['id'].toString());
                              },
                              icon: Icon(selShift == null ? Icons.add : Icons.edit_outlined, size: 18),
                              label: Text(selShift == null ? 'Mark as duty day' : 'Edit'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => showQuickAdd(context, date: _sel),
                              icon: const Icon(Icons.add, size: 18),
                              label: Text('Add case'),
                            ),
                          ],
                        ),
                        if ((selShift?['note'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text((selShift!['note']).toString(), style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ),
                if (selCases.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('No cases on this day.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                  ),
                for (var i = 0; i < selCases.length; i++)
                  FadeSlideIn(
                    key: ValueKey('${_sel}_${selCases[i].id}'),
                    index: i,
                    child: CaseTile(selCases[i]),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
