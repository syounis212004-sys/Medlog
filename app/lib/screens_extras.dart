import 'package:flutter/material.dart' hide Text;

import 'data.dart';
import 'i18n.dart';
import 'screens_ai_help.dart' show openAppHelp;
import 'ui.dart';
import 'widgets.dart';

// ================================================================ pearls (one thing learned today)

Future<void> editPearl(BuildContext context, [J? p]) async {
  final res = await showFormSheet(
    context,
    title: p == null ? 'One pearl today' : 'Pearl',
    specs: const [
      FieldSpec('text', 'The one thing I learned today', type: FT.multi),
      FieldSpec('topic', 'Topic (optional)', hint: 'e.g. DKA'),
      FieldSpec('caseCode', 'Related case code (optional)'),
    ],
    initial: p ?? <String, dynamic>{'id': newId('pl'), 'date': todayStr()},
    canDelete: p != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeExtra('pearls', p!['id'].toString());
  } else {
    await store.upsertExtra('pearls', res);
  }
}

// ================================================================ tasks (learning to-do with due dates)

const List<String> kPriorities = ['High', 'Normal', 'Low'];

Future<void> editTask(BuildContext context, [J? t]) async {
  final res = await showFormSheet(
    context,
    title: t == null ? 'New learning task' : 'Learning task',
    specs: const [
      FieldSpec('title', 'What do I need to do?', type: FT.multi),
      FieldSpec('due', 'Due date', type: FT.date),
      FieldSpec('priority', 'Priority', type: FT.choice, options: kPriorities),
      FieldSpec('note', 'Note', type: FT.multi),
      FieldSpec('caseCode', 'Related case code (optional)'),
    ],
    initial: t ?? <String, dynamic>{'id': newId('t'), 'priority': 'Normal', 'due': todayStr()},
    canDelete: t != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeExtra('tasks', t!['id'].toString());
  } else {
    await store.upsertExtra('tasks', res);
  }
}

bool taskOverdue(J t) =>
    t['done'] != true && (t['due'] ?? '').toString().isNotEmpty && (t['due'] as String).compareTo(todayStr()) < 0;

List<J> openTasks() {
  final l = store.listOf('tasks').where((t) => t['done'] != true).toList();
  int pr(J t) => const {'High': 0, 'Normal': 1, 'Low': 2}[(t['priority'] ?? 'Normal').toString()] ?? 1;
  l.sort((a, b) {
    final d = (a['due'] ?? '9999').toString().compareTo((b['due'] ?? '9999').toString());
    return d != 0 ? d : pr(a).compareTo(pr(b));
  });
  return l;
}

class TaskTile extends StatelessWidget {
  final J t;
  const TaskTile(this.t, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = t['done'] == true;
    final over = taskOverdue(t);
    return AppCard(
      child: ListTile(
        onTap: () => editTask(context, t),
        leading: Checkbox(
          value: done,
          onChanged: (v) async {
            t['done'] = v == true;
            await store.upsertExtra('tasks', t);
          },
        ),
        title: Text((t['title'] ?? '').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(decoration: done ? TextDecoration.lineThrough : null)),
        subtitle: Text(
          [
            if ((t['due'] ?? '').toString().isNotEmpty) prettyDate(t['due'].toString()),
            tr((t['priority'] ?? 'Normal').toString()),
            if (over) tr('Overdue'),
          ].join(' • '),
          style: TextStyle(color: over ? cs.error : null),
        ),
      ),
    );
  }
}

// ================================================================ add menu (+)

/// What the central "+" opens: every way of adding something in one place.
Future<void> showAddMenu(BuildContext context, {required VoidCallback onQuickCase, required VoidCallback onFullCase}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true, // room for the entries added by other layers (4 rows)
    builder: (ctx) {
      final theme = Theme.of(ctx);
      Widget item(IconData icon, String label, VoidCallback fn, {bool primary = false}) {
        final cs = theme.colorScheme;
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.pop(ctx);
            fn();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            decoration: BoxDecoration(
              color: primary ? cs.primaryContainer : cs.secondaryContainer.withAlpha(110),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: primary ? cs.onPrimaryContainer : cs.onSecondaryContainer),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: primary ? cs.onPrimaryContainer : cs.onSecondaryContainer,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.1,
              children: [
                item(Icons.bolt, 'Quick case', onQuickCase, primary: true),
                item(Icons.edit_note, 'Full case', onFullCase, primary: true),
                item(Icons.healing_outlined, 'Procedure', () => addProcedure(context)),
                item(Icons.sticky_note_2_outlined, 'Note', () => addNote(context)),
                item(Icons.help_outline, 'Question', () => addQuestion(context)),
                item(Icons.lightbulb_outline, 'Pearl', () => editPearl(context)),
                item(Icons.task_alt, 'Task', () => editTask(context)),
                item(Icons.support_agent, 'App help', () => openAppHelp(context)),
                // entries added by other layers (the AI core adds "Ask AI" and "AI question bank")
                for (final e in addMenuExtras) item(e.icon, e.label, () => e.open(context)),
              ],
            ),
            ),
          ],
        ),
      );
    },
  );
}

/// Extra entries of the "+" menu, registered in main().
class AddMenuExtra {
  final IconData icon;
  final String label;
  final void Function(BuildContext context) open;
  const AddMenuExtra(this.icon, this.label, this.open);
}

List<AddMenuExtra> addMenuExtras = [];

// set by screens_learn (avoids a circular import)
Future<void> Function(BuildContext) addProcedure = (c) async {};
Future<void> Function(BuildContext) addNote = (c) async {};
Future<void> Function(BuildContext) addQuestion = (c) async {};

// ================================================================ small sections used by Study home

class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;
  const SectionCard({super.key, required this.title, required this.icon, required this.children, this.trailing});

  /// Collapsible (arrow), open by default, remembers how the user left it.
  @override
  Widget build(BuildContext context) {
    return Fold(
      id: 'sc_$title',
      title: tr(title),
      icon: icon,
      initiallyOpen: true,
      trailing: trailing,
      children: children,
    );
  }
}

class PearlCard extends StatelessWidget {
  final J p;
  const PearlCard(this.p, {super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListTile(
        onTap: () => editPearl(context, p),
        leading: const Icon(Icons.lightbulb_outline),
        title: Text((p['text'] ?? '').toString(), maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          prettyDate((p['date'] ?? '').toString()),
          if ((p['topic'] ?? '').toString().isNotEmpty) (p['topic']).toString(),
        ].join(' • ')),
      ),
    );
  }
}

/// Today's pearl status + streak of consecutive days with a pearl.
int pearlStreak() {
  final days = store.listOf('pearls').map((p) => (p['date'] ?? '').toString()).toSet();
  var d = DateTime.now();
  if (!days.contains(fmtDate(d))) d = d.subtract(const Duration(days: 1));
  var n = 0;
  while (days.contains(fmtDate(d))) {
    n++;
    d = d.subtract(const Duration(days: 1));
  }
  return n;
}

Widget pearlPrompt(BuildContext context) {
  final theme = Theme.of(context);
  final has = store.listOf('pearls').any((p) => p['date'] == todayStr());
  final streak = pearlStreak();
  return AppCard(
    color: has ? theme.colorScheme.secondaryContainer.withAlpha(120) : null,
    child: ListTile(
      onTap: () => editPearl(context),
      leading: Icon(has ? Icons.check_circle : Icons.lightbulb_outline, color: theme.colorScheme.primary),
      title: Text(has ? 'Today’s pearl is saved' : 'One pearl a day'),
      subtitle: Text(streak > 0 ? trp('{n}-day streak', {'n': streak}) : 'Write the one thing you learned today.'),
      trailing: const Icon(Icons.add),
    ),
  );
}
