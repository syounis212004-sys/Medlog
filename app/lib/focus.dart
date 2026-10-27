import 'data.dart';
import 'privacy.dart';
import 'review.dart';

/// "Today's focus": a short list of what is worth doing now, found by looking at
/// gaps in YOUR own records (unfinished drafts, pending results, unanswered
/// questions, overdue tasks...). It never suggests clinical actions.

enum FocusAction { openCase, openTask, openQuestion, startReview, openFeedback, addPearl, openProcedures, openEvidence, replayCase, privacyCheck }

class FocusItem {
  final String id;
  final FocusAction action;
  final String ref; // case id / task id / ...
  final int tab; // case editor tab to open
  final int icon; // codepoint name key (mapped in UI)
  final String key; // icon key
  final String title;
  final String subtitle;
  final int weight;
  const FocusItem(this.id, this.action, this.ref, this.tab, this.icon, this.key, this.title, this.subtitle, this.weight);
}

int daysSince(String date) {
  final d = parseDate(date);
  if (d == null) return 0;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
}

/// Supervision stage of a logged procedure role (1 = observed ... 4 = independent).
int stageOfRole(String role) {
  switch (role) {
    case 'Observed':
      return 1;
    case 'Assisted':
      return 2;
    case 'Performed under supervision':
      return 3;
    case 'Performed independently':
      return 4;
    default:
      return 0;
  }
}

bool _okUnknown(CaseRec c, String field) {
  final st = c.s('st_$field');
  return st == 'Unknown' || st == 'Not assessed' || st == 'Pending';
}

List<FocusItem> buildFocus() {
  final out = <FocusItem>[];
  final today = todayStr();

  // ---- tasks and feedback actions
  for (final t in store.listOf('tasks')) {
    if (t['done'] == true) continue;
    final due = (t['due'] ?? '').toString();
    if (due.isEmpty) continue;
    if (due.compareTo(today) < 0) {
      out.add(FocusItem('task:${t['id']}', FocusAction.openTask, '${t['id']}', 0, 0, 'task',
          '${t['title']}', 'Overdue task', 90));
    } else if (due == today) {
      out.add(FocusItem('task:${t['id']}', FocusAction.openTask, '${t['id']}', 0, 0, 'task',
          '${t['title']}', 'Due today', 75));
    }
  }
  for (final f in store.listOf('feedback')) {
    if ((f['status'] ?? 'Open') == 'Done') continue;
    final due = (f['due'] ?? '').toString();
    if (due.isNotEmpty && due.compareTo(today) <= 0) {
      out.add(FocusItem('fb:${f['id']}', FocusAction.openFeedback, '${f['id']}', 0, 0, 'feedback',
          '${f['action'] ?? f['said'] ?? ''}', 'Feedback action to review', 85));
    }
  }

  // ---- spaced review
  final dueN = ReviewEngine.dueCount();
  if (dueN > 0) {
    out.add(FocusItem('review', FocusAction.startReview, '', 0, 0, 'review', 'Review what you wrote', '$dueN', 65));
  }

  // ---- gaps in cases
  for (final c in store.cases.values) {
    if (c.shared) continue;
    final age = daysSince(c.s('date'));
    final draft = c.s('status') == 'Draft';
    if (draft && age >= 2) {
      out.add(FocusItem('draft:${c.id}', FocusAction.openCase, c.id, 0, 0, 'draft',
          c.s('code'), c.title, 70));
      continue;
    }
    final pending = c.lst('inv').where((i) => i['status'] == 'Pending').map((i) => '${i['name']}').toList();
    if (pending.isNotEmpty && age >= 1) {
      out.add(FocusItem('pend:${c.id}', FocusAction.openCase, c.id, 3, 0, 'pending',
          c.s('code'), pending.join(', '), 60));
    }
    if (!draft &&
        age >= 2 &&
        c.s('finalDx').trim().isEmpty &&
        c.s('workingDx').trim().isEmpty &&
        c.s('ddx').trim().isEmpty &&
        !_okUnknown(c, 'finalDx')) {
      out.add(FocusItem('dx:${c.id}', FocusAction.openCase, c.id, 4, 0, 'dx', c.s('code'), c.title, 55));
    }
    if (!c.id.startsWith('demo_') && scanCase(c).isNotEmpty) {
      out.add(FocusItem('priv:${c.id}', FocusAction.privacyCheck, c.id, 0, 0, 'privacy', c.s('code'), '${scanCase(c).length}', 50));
    }
    if (!draft && age >= 3 && c.s('hpi').trim().isNotEmpty && c.s('learned').trim().isEmpty) {
      out.add(FocusItem('learn:${c.id}', FocusAction.openCase, c.id, 7, 0, 'learn', c.s('code'), c.title, 40));
    }
    if (c.s('questions').trim().isNotEmpty && age >= 2) {
      out.add(FocusItem('cq:${c.id}', FocusAction.openCase, c.id, 7, 0, 'question', c.s('code'), c.s('questions'), 35));
    }
  }

  // ---- unanswered questions in the inbox
  for (final q in store.inbox) {
    if ((q['status'] ?? 'Open') == 'Answered') continue;
    if (daysSince((q['date'] ?? '').toString()) >= 3) {
      out.add(FocusItem('q:${q['id']}', FocusAction.openQuestion, '${q['id']}', 0, 0, 'question',
          '${q['question'] ?? ''}', 'Open question', 45));
    }
  }

  // ---- procedures that stay at "observed"
  final byName = <String, List<J>>{};
  for (final p in store.procedures) {
    final n = (p['name'] ?? '').toString();
    if (n.isNotEmpty) (byName[n] ??= []).add(p);
  }
  byName.forEach((name, list) {
    final best = list.map((p) => stageOfRole((p['role'] ?? '').toString())).fold<int>(0, (a, b) => a > b ? a : b);
    final last = list.map((p) => (p['date'] ?? '').toString()).fold<String>('', (a, b) => a.compareTo(b) > 0 ? a : b);
    if (best == 1 && list.length >= 2 && daysSince(last) >= 14) {
      out.add(FocusItem('proc:$name', FocusAction.openProcedures, name, 0, 0, 'proc', name, 'Observed only', 38));
    }
  });

  // ---- one pearl a day (afternoon reminder)
  if (DateTime.now().hour >= 14 && !store.listOf('pearls').any((p) => p['date'] == today)) {
    out.add(const FocusItem('pearl', FocusAction.addPearl, '', 0, 0, 'pearl', 'One pearl a day', '', 20));
  }

  // ---- references to refresh (Stage E fills the list)
  for (final e in store.listOf('evidence')) {
    final reviewed = (e['reviewed'] ?? e['saved'] ?? '').toString();
    final year = int.tryParse((e['year'] ?? '').toString());
    final old = year != null && DateTime.now().year - year >= 5;
    if (reviewed.isNotEmpty && daysSince(reviewed) >= 365 || old) {
      out.add(FocusItem('ev:${e['id']}', FocusAction.openEvidence, '${e['id']}', 0, 0, 'evidence',
          '${e['title'] ?? ''}', old ? 'Old reference' : 'Not reviewed for a year', 30));
    }
  }

  // ---- replay suggestion: an older case you have not replayed lately
  final cand = replayCandidates();
  if (cand.isNotEmpty && daysSince(cand.first.s('date')) >= 14) {
    final c = cand.first;
    out.add(FocusItem('replay:${c.id}', FocusAction.replayCase, c.id, 0, 0, 'replay', c.s('code'), c.title, 28));
  }

  out.sort((a, b) => b.weight.compareTo(a.weight));
  return out;
}

/// Own cases that can be replayed (a recorded diagnosis plus a story),
/// those never replayed first, then the longest ago.
List<CaseRec> replayCandidates() {
  final last = <String, String>{};
  for (final r in store.listOf('replays')) {
    final id = (r['caseId'] ?? '').toString();
    final d = (r['date'] ?? '').toString();
    if (d.compareTo(last[id] ?? '') > 0) last[id] = d;
  }
  final list = store.cases.values.where((c) {
    if (c.s('status') == 'Draft') return false;
    final dx = c.s('finalDx').trim().isNotEmpty || c.s('workingDx').trim().isNotEmpty;
    return dx && (c.s('cc').trim().isNotEmpty || c.s('hpi').trim().isNotEmpty);
  }).toList();
  list.sort((a, b) {
    final la = last[a.id] ?? '';
    final lb = last[b.id] ?? '';
    final cmp = la.compareTo(lb);
    return cmp != 0 ? cmp : a.s('date').compareTo(b.s('date'));
  });
  return list;
}

/// Date of the last replay of a case ('' if never).
String lastReplayOf(String caseId) {
  var best = '';
  for (final r in store.listOf('replays')) {
    if (r['caseId'] == caseId) {
      final d = (r['date'] ?? '').toString();
      if (d.compareTo(best) > 0) best = d;
    }
  }
  return best;
}
