import 'screens_ai_tools.dart' show AiChipButton, openProcedureDeepDive;
import 'package:flutter/material.dart' hide Text;

import 'data.dart';
import 'focus.dart' show stageOfRole;
import 'goals_signoff.dart';
import 'i18n.dart';
import 'motion.dart';
import 'screens_learn.dart';
import 'ui.dart';
import 'widgets.dart';

// ================================================================ imaging log (POCUS, X-ray, ECG readings)

const List<String> kImagingKinds = [
  'POCUS - FAST', 'POCUS - Echo', 'POCUS - Lung', 'POCUS - IVC', 'POCUS - Abdomen', 'POCUS - Vascular',
  'X-ray read', 'CT read', 'MRI read', 'ECG read', 'Other',
];

const List<String> kAgreement = ['Agree', 'Partly', 'Disagree', 'Not reviewed'];

Future<void> editImaging(BuildContext context, [J? e]) async {
  final res = await showFormSheet(
    context,
    title: e == null ? 'Log an imaging reading' : 'Imaging reading',
    specs: const [
      FieldSpec('kind', 'Type of study', options: kImagingKinds),
      FieldSpec('date', 'Date', type: FT.date),
      FieldSpec('views', 'View', hint: 'AP, lateral, axial...'),
      FieldSpec('reading', 'My interpretation', type: FT.multi),
      FieldSpec('agreement', 'Supervisor / formal report', type: FT.choice, options: kAgreement),
      FieldSpec('learning', 'What I learned', type: FT.multi),
      FieldSpec('caseCode', 'Related case code (optional)'),
    ],
    initial: e ?? <String, dynamic>{'id': newId('im'), 'date': todayStr(), 'agreement': 'Not reviewed'},
    canDelete: e != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeExtra('imaging', e!['id'].toString());
  } else {
    await store.upsertExtra('imaging', res);
  }
}

Color agreementColor(String a) {
  switch (a) {
    case 'Agree':
      return Colors.green;
    case 'Partly':
      return Colors.orange;
    case 'Disagree':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

class ImagingTab extends StatelessWidget {
  const ImagingTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final list = [...store.listOf('imaging')]
          ..sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
        final reviewed = list.where((e) => e['agreement'] != 'Not reviewed' && (e['agreement'] ?? '').toString().isNotEmpty).toList();
        final agree = reviewed.where((e) => e['agreement'] == 'Agree').length;
        final byKind = <String, int>{};
        for (final e in list) {
          final k = (e['kind'] ?? '').toString();
          if (k.isNotEmpty) byKind[k] = (byKind[k] ?? 0) + 1;
        }
        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(onPressed: () => editImaging(context), icon: const Icon(Icons.add), label: Text('Log reading')),
              ),
              const SizedBox(height: 6),
              if (list.isNotEmpty)
                Wrap(spacing: 8, runSpacing: 4, children: [
                  Chip(label: Text(trp('{n} logged', {'n': list.length}))),
                  if (reviewed.isNotEmpty) Chip(label: Text(trp('{a} of {b} agreed', {'a': agree, 'b': reviewed.length}))),
                  for (final e in byKind.entries) Chip(label: Text('${tr(e.key)}: ${e.value}')),
                ]),
              if (list.isEmpty)
                const EmptyState(
                  kind: EmptyKind.learn,
                  title: 'No imaging readings yet',
                  message: 'Log POCUS scans, X-ray and ECG readings with the formal result, to see how your reading improves.',
                ),
              for (var i = 0; i < list.length; i++)
                FadeSlideIn(
                  key: ValueKey(list[i]['id']),
                  index: i,
                  child: AppCard(
                    child: ListTile(
                      onTap: () => editImaging(context, list[i]),
                      leading: Icon(Icons.circle, size: 14, color: agreementColor((list[i]['agreement'] ?? '').toString())),
                      title: Text(tr((list[i]['kind'] ?? '').toString())),
                      subtitle: Text([
                        prettyDate((list[i]['date'] ?? '').toString()),
                        (list[i]['views'] ?? '').toString(),
                        tr((list[i]['agreement'] ?? '').toString()),
                        if ((list[i]['caseCode'] ?? '').toString().isNotEmpty) '${list[i]['caseCode']}',
                      ].where((e) => e.isNotEmpty).join(' • ')),
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


// ================================================================ skills passport

const List<String> kStageRoles = [
  'Observed', 'Assisted', 'Performed under supervision', 'Performed independently',
];

String nextStepOf(int best) {
  if (best <= 0) return 'Log your first one';
  if (best >= 4) return 'Independent. Keep a supervisor assessment up to date';
  return 'Next: ${kStageRoles[best]}';
}

/// Passport (progress per skill) or Log (every entry).
class SkillsTab extends StatefulWidget {
  const SkillsTab({super.key});

  @override
  State<SkillsTab> createState() => _SkillsTabState();
}

class _SkillsTabState extends State<SkillsTab> {
  String _view = 'passport'; // passport | log | signoff

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'passport', icon: Icon(Icons.workspace_premium_outlined), label: Text('Passport')),
                ButtonSegment(value: 'log', icon: Icon(Icons.list_alt), label: Text('Log')),
                ButtonSegment(value: 'signoff', icon: Icon(Icons.verified_outlined), label: Text('Sign-off')),
              ],
              selected: {_view},
              onSelectionChanged: (v) => setState(() => _view = v.first),
            ),
          ),
        ),
        Expanded(
            child: _view == 'passport'
                ? const SkillsPassport()
                : _view == 'log'
                    ? const ProceduresLogTab()
                    : const SignOffTab()),
      ],
    );
  }
}

J? goalFor(String name) {
  for (final g in store.listOf('skillgoals')) {
    if (g['name'] == name) return g;
  }
  return null;
}

Future<void> editGoal(BuildContext context, String name) async {
  final cur = goalFor(name);
  final res = await showFormSheet(
    context,
    title: '${tr('Goal')} • ${tr(name)}',
    specs: const [
      FieldSpec('target', 'How many do I want to reach?', type: FT.number, hint: '10'),
      FieldSpec('minStage', 'Counts when my role is at least', type: FT.choice, options: ['Assisted', 'Performed under supervision', 'Performed independently']),
    ],
    initial: cur ?? <String, dynamic>{'id': newId('g'), 'name': name, 'target': '10', 'minStage': 'Performed under supervision'},
    canDelete: cur != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeExtra('skillgoals', cur!['id'].toString());
  } else {
    await store.upsertExtra('skillgoals', res);
  }
}

class SkillsPassport extends StatelessWidget {
  const SkillsPassport({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final byName = <String, List<J>>{};
        for (final p in store.procedures) {
          final n = (p['name'] ?? '').toString();
          if (n.isNotEmpty) (byName[n] ??= []).add(p);
        }
        // skills with a goal but no entries yet
        for (final g in store.listOf('skillgoals')) {
          byName.putIfAbsent((g['name'] ?? '').toString(), () => []);
        }
        final names = byName.keys.where((e) => e.isNotEmpty).toList()
          ..sort((a, b) {
            int best(String n) => byName[n]!.map((p) => stageOfRole((p['role'] ?? '').toString())).fold<int>(0, (x, y) => x > y ? x : y);
            final c = best(a).compareTo(best(b));
            return c != 0 ? c : byName[b]!.length.compareTo(byName[a]!.length);
          });
        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(onPressed: () => editProcedure(context), icon: const Icon(Icons.add), label: Text('Log procedure')),
              ),
              const SizedBox(height: 6),
              if (names.isEmpty)
                const EmptyState(
                  kind: EmptyKind.learn,
                  title: 'Your skills passport',
                  message: 'Each skill shows how far you have moved: observed, assisted, supervised, independent.',
                ),
              for (var i = 0; i < names.length; i++)
                FadeSlideIn(
                  index: i,
                  child: _SkillCard(name: names[i], logs: byName[names[i]]!),
                ),
              if (names.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'A personal record of supervision levels. It is not an official assessment of competence.',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SkillCard extends StatelessWidget {
  final String name;
  final List<J> logs;
  const _SkillCard({required this.name, required this.logs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final counts = List<int>.filled(5, 0);
    var confSum = 0, confN = 0, sup = 0;
    for (final p in logs) {
      counts[stageOfRole((p['role'] ?? '').toString())]++;
      final c = int.tryParse((p['confidence'] ?? '').toString());
      if (c != null) {
        confSum += c;
        confN++;
      }
      if (p['assessedBy'] == 'Supervisor assessed') sup++;
    }
    var best = 0;
    for (var s = 4; s >= 1; s--) {
      if (counts[s] > 0) {
        best = s;
        break;
      }
    }
    final goal = goalFor(name);
    double? goalProgress;
    String goalText = '';
    if (goal != null) {
      final target = int.tryParse((goal['target'] ?? '').toString()) ?? 0;
      final minStage = stageOfRole((goal['minStage'] ?? 'Performed under supervision').toString());
      final done = logs.where((p) => stageOfRole((p['role'] ?? '').toString()) >= minStage).length;
      if (target > 0) {
        goalProgress = (done / target).clamp(0.0, 1.0);
        goalText = '$done / $target';
      }
    }
    const labels = ['Observed', 'Assisted', 'Supervised', 'Independent'];
    return AppCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => editProcedure(context, null, name),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(tr(name), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                AiChipButton(key: ValueKey('skill_ai_$name'), tooltip: 'Procedure deep-dive', onTap: () => openProcedureDeepDive(context, name)),
                IconButton(
                  tooltip: tr('Goal'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(goal == null ? Icons.flag_outlined : Icons.flag, color: goal == null ? null : cs.primary),
                  onPressed: () => editGoal(context, name),
                ),
              ]),
              const SizedBox(height: 4),
              // four steps, filled up to the highest stage reached
              Row(children: [
                for (var s = 1; s <= 4; s++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(children: [
                        AnimatedBar(counts[s] > 0 ? 1 : 0, height: 8, color: s <= best ? cs.primary : cs.outline),
                        const SizedBox(height: 4),
                        Text('${tr(labels[s - 1])}\n${counts[s]}',
                            textAlign: TextAlign.center, style: theme.textTheme.labelSmall),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 2, children: [
                Text(tr(nextStepOf(best)), style: theme.textTheme.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                if (confN > 0) Text(trp('Avg confidence {n}/5', {'n': (confSum / confN).toStringAsFixed(1)}), style: theme.textTheme.bodySmall),
                if (sup > 0) Text(trp('{n} supervisor assessed', {'n': sup}), style: theme.textTheme.bodySmall),
                if (logs.any(isSigned)) Text(trp('{n} signed by supervisor', {'n': logs.where(isSigned).length}), style: theme.textTheme.bodySmall),
              ]),
              if (goalProgress != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Text('${tr('Goal')} $goalText', style: theme.textTheme.labelMedium),
                  const SizedBox(width: 8),
                  Expanded(child: AnimatedBar(goalProgress, height: 8, color: cs.tertiary)),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================ supervisor feedback -> action

const List<String> kFeedbackStatus = ['Open', 'Improving', 'Done'];

Future<void> editFeedback(BuildContext context, [J? f]) async {
  final res = await showFormSheet(
    context,
    title: f == null ? 'New feedback' : 'Feedback',
    specs: const [
      FieldSpec('from', 'From (supervisor)'),
      FieldSpec('said', 'What they said', type: FT.multi),
      FieldSpec('action', 'What I will do about it', type: FT.multi),
      FieldSpec('due', 'Review on', type: FT.date),
      FieldSpec('status', 'Status', type: FT.choice, options: kFeedbackStatus),
      FieldSpec('result', 'What improved', type: FT.multi),
      FieldSpec('caseCode', 'Related case code (optional)'),
    ],
    initial: f ?? <String, dynamic>{'id': newId('fb'), 'date': todayStr(), 'status': 'Open',
      'due': fmtDate(DateTime.now().add(const Duration(days: 14)))},
    canDelete: f != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeExtra('feedback', f!['id'].toString());
  } else {
    await store.upsertExtra('feedback', res);
  }
}

class FeedbackTab extends StatefulWidget {
  const FeedbackTab({super.key});

  @override
  State<FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<FeedbackTab> {
  bool _fb = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, icon: Icon(Icons.record_voice_over_outlined), label: Text('Feedback')),
                ButtonSegment(value: false, icon: Icon(Icons.fact_check_outlined), label: Text('Assessments')),
              ],
              selected: {_fb},
              onSelectionChanged: (v) => setState(() => _fb = v.first),
            ),
          ),
        ),
        Expanded(child: _fb ? const _FeedbackList() : const AssessmentsList()),
      ],
    );
  }
}

class _FeedbackList extends StatelessWidget {
  const _FeedbackList();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final list = [...store.listOf('feedback')]
          ..sort((a, b) {
            int rank(J e) => (e['status'] ?? 'Open') == 'Done' ? 1 : 0;
            final r = rank(a).compareTo(rank(b));
            return r != 0 ? r : (a['due'] ?? '').toString().compareTo((b['due'] ?? '').toString());
          });
        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(onPressed: () => editFeedback(context), icon: const Icon(Icons.add), label: Text('Add feedback')),
              ),
              const SizedBox(height: 6),
              if (list.isEmpty)
                const EmptyState(
                  kind: EmptyKind.learn,
                  title: 'Turn feedback into action',
                  message: 'Write what a supervisor said, what you will do, and when to check whether it improved.',
                ),
              for (var i = 0; i < list.length; i++)
                FadeSlideIn(
                  key: ValueKey(list[i]['id']),
                  index: i,
                  child: Builder(builder: (context) {
                    final f = list[i];
                    final done = (f['status'] ?? 'Open') == 'Done';
                    final due = (f['due'] ?? '').toString();
                    final over = !done && due.isNotEmpty && due.compareTo(todayStr()) < 0;
                    return AppCard(
                      child: ListTile(
                        onTap: () => editFeedback(context, f),
                        leading: Icon(done ? Icons.check_circle : (over ? Icons.alarm : Icons.pending_outlined),
                            color: done ? Colors.green : (over ? cs.error : null)),
                        title: Text((f['action'] ?? '').toString().isEmpty ? (f['said'] ?? '').toString() : (f['action']).toString(),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          if ((f['from'] ?? '').toString().isNotEmpty) f['from'].toString(),
                          tr((f['status'] ?? 'Open').toString()),
                          if (due.isNotEmpty) '${tr('Review on')} ${prettyDate(due)}',
                          if (over) tr('Overdue'),
                        ].join(' • ')),
                      ),
                    );
                  }),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ================================================================ formal assessments (Mini-CEX / DOPS / CBD)

const Map<String, List<String>> kAssessmentDomains = {
  'Mini-CEX': ['History taking', 'Physical examination', 'Communication skills', 'Clinical judgement', 'Professionalism', 'Organisation and efficiency', 'Overall care'],
  'DOPS': ['Indication and consent', 'Preparation', 'Technique', 'Aseptic technique', 'Seeks help appropriately', 'Post-procedure management', 'Communication', 'Overall ability'],
  'CBD': ['Record keeping', 'Clinical assessment', 'Investigations and referrals', 'Treatment', 'Follow-up and planning', 'Professionalism', 'Overall clinical judgement'],
};

const List<String> kLevels = ['Below expectations', 'Meets expectations', 'Above expectations'];

Future<void> editAssessment(BuildContext context, [J? a]) async {
  final res = await Navigator.push<J>(
    context,
    MaterialPageRoute(builder: (_) => AssessmentEditor(initial: a)),
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeExtra('assessments', a!['id'].toString());
  } else {
    await store.upsertExtra('assessments', res);
  }
}

class AssessmentEditor extends StatefulWidget {
  final J? initial;
  const AssessmentEditor({super.key, this.initial});

  @override
  State<AssessmentEditor> createState() => _AssessmentEditorState();
}

class _AssessmentEditorState extends State<AssessmentEditor> {
  late final J _d = widget.initial == null
      ? <String, dynamic>{'id': newId('as'), 'type': 'Mini-CEX', 'date': todayStr(), 'ratings': <String, dynamic>{}}
      : Map<String, dynamic>.from(widget.initial!);
  final Map<String, TextEditingController> _c = {};

  TextEditingController _tc(String k) => _c.putIfAbsent(k, () => TextEditingController(text: (_d[k] ?? '').toString()));

  Map<String, dynamic> get _ratings {
    final r = _d['ratings'];
    if (r is Map) return Map<String, dynamic>.from(r);
    return <String, dynamic>{};
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = (_d['type'] ?? 'Mini-CEX').toString();
    final domains = kAssessmentDomains[type] ?? const [];
    final ratings = _ratings;
    return Scaffold(
      appBar: AppBar(
        title: Text('Assessment'),
        actions: [
          if (widget.initial != null)
            IconButton(
              tooltip: tr('Delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.pop(context, <String, dynamic>{'__delete': true}),
            ),
          TextButton(
            onPressed: () {
              for (final k in ['assessor', 'subject', 'strengths', 'development', 'action']) {
                _d[k] = _tc(k).text.trim();
              }
              _d['ratings'] = ratings;
              Navigator.pop(context, _d);
            },
            child: Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(spacing: 8, children: [
            for (final t in kAssessmentDomains.keys)
              ChoiceChip(label: Text(t), selected: type == t, onSelected: (_) => setState(() => _d['type'] = t)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _tc('assessor'), decoration: InputDecoration(labelText: tr('Assessor'))),
          const SizedBox(height: 10),
          TextField(controller: _tc('subject'), decoration: InputDecoration(labelText: tr('Case code or procedure'))),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Date'),
            subtitle: Text(prettyDate((_d['date'] ?? '').toString())),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: parseDate((_d['date'] ?? '').toString()) ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _d['date'] = fmtDate(d));
            },
          ),
          const SectionHeader('Ratings'),
          for (final dom in domains)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(dom), style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, children: [
                    for (final l in kLevels)
                      ChoiceChip(
                        label: Text(l),
                        selected: ratings[dom] == l,
                        onSelected: (_) => setState(() {
                          final r = _ratings;
                          r[dom] = ratings[dom] == l ? '' : l;
                          _d['ratings'] = r;
                        }),
                      ),
                  ]),
                ],
              ),
            ),
          const SizedBox(height: 4),
          TextField(controller: _tc('strengths'), minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: tr('What went well'))),
          const SizedBox(height: 10),
          TextField(controller: _tc('development'), minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: tr('What to develop'))),
          const SizedBox(height: 10),
          TextField(controller: _tc('action'), minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: tr('My action plan'))),
          const SizedBox(height: 12),
          Text('A personal copy. It is not the official assessment form of your hospital.', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class AssessmentsList extends StatelessWidget {
  const AssessmentsList({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final list = [...store.listOf('assessments')]
          ..sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => editAssessment(context),
            icon: const Icon(Icons.add),
            label: const Text('New assessment'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              if (list.isEmpty)
                const EmptyState(
                  kind: EmptyKind.learn,
                  title: 'Mini-CEX, DOPS and CBD',
                  message: 'Keep your own copy of assessments you receive, with strengths and what to develop.',
                ),
              for (var i = 0; i < list.length; i++)
                FadeSlideIn(
                  key: ValueKey(list[i]['id']),
                  index: i,
                  child: Builder(builder: (context) {
                    final a = list[i];
                    final r = (a['ratings'] is Map) ? (a['ratings'] as Map).values.map((e) => e.toString()).toList() : <String>[];
                    final above = r.where((e) => e == 'Above expectations').length;
                    final below = r.where((e) => e == 'Below expectations').length;
                    return AppCard(
                      child: ListTile(
                        onTap: () => editAssessment(context, a),
                        leading: const Icon(Icons.fact_check_outlined),
                        title: Text('${a['type'] ?? ''} • ${(a['subject'] ?? '').toString()}'.trim()),
                        subtitle: Text([
                          prettyDate((a['date'] ?? '').toString()),
                          if ((a['assessor'] ?? '').toString().isNotEmpty) a['assessor'].toString(),
                          if (r.isNotEmpty) trp('{a} above, {b} below', {'a': above, 'b': below}),
                        ].join(' • ')),
                      ),
                    );
                  }),
                ),
            ],
          ),
        );
      },
    );
  }
}
