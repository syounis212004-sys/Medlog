import 'dart:math' show max;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as mm show Text;

import 'core_topics.dart';
import 'data.dart';
import 'goals_signoff.dart' show isSigned, editProcedureSignOff;
import 'i18n.dart';
import 'lib_plan.dart';
import 'lib_user.dart';
import 'library.dart';
import 'review.dart';
import 'screens_review.dart' show ReviewSessionScreen;
import 'motion.dart';
import 'screens_cases.dart';
import 'screens_library.dart' show openArticle;
import 'ai/ai_api.dart' show AiBuilder;
import 'ai/ai_context.dart';
import 'ai/ai_study.dart' show explainRebalance;
import 'screens_ai_study.dart';
import 'screens_quiz.dart' show QuizScreen;
import 'screens_skills.dart';
import 'ui.dart';
import 'widgets.dart';

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  void _open(BuildContext context, String title, Widget body) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiContextScope(
          ctx: const AiScreenContext(kind: 'learn', title: 'Learn'),
          child: Scaffold(appBar: AppBar(title: Text(title)), body: body),
        ),
      ),
    );
  }

  Widget _big(BuildContext context, IconData icon, String title, String sub, VoidCallback onTap, {Key? key}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      key: key,
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.start, children: [
            CircleAvatar(radius: 20, backgroundColor: cs.primaryContainer, child: Icon(icon, color: cs.onPrimaryContainer)),
            const SizedBox(height: 10),
            mm.Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            mm.Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }

  Widget _more(BuildContext context, IconData icon, String title, String sub, VoidCallback onTap, {Key? key}) => ListTile(
        key: key,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(icon),
        title: mm.Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: mm.Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'learn', title: 'Learn'),
      child: Scaffold(
        appBar: AppBar(title: const Text('Learn')),
        body: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final st = ReviewEngine.stats();
            final due = st['due'] ?? 0;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Container(
                        width: 64,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                        child: Center(child: mm.Text('$due', key: const ValueKey('learnDue'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: theme.colorScheme.onPrimaryContainer))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(due == 0 ? 'Nothing due today' : 'Cards due today', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          FilledButton(
                            key: const ValueKey('learnStart'),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewSessionScreen())),
                            child: Text('Start today\u2019s review'),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _big(context, Icons.quiz_outlined, tr('Test myself'), tr('Questions from the articles'), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuizScreen())), key: const ValueKey('learnQuiz'))),
                    const SizedBox(width: 10),
                    Expanded(child: _big(context, Icons.school_outlined, tr('Study'), tr('Exam planner and cases to review'), () => _open(context, tr('Study'), const _ReviewTab()), key: const ValueKey('learnStudy'))),
                  ]),
                ),
                Fold(
                  id: 'learn_more',
                  title: tr('More'),
                  icon: Icons.more_horiz,
                  children: [
                    _more(context, Icons.style_outlined, tr('Flashcards'), tr('Review and add cards'), () => _open(context, tr('Flashcards'), const FlashcardsTab()), key: const ValueKey('learnCards')),
                    _more(context, Icons.help_outline, tr('Questions'), tr('Your own question list'), () => _open(context, tr('Questions'), const _QuestionsTab()), key: const ValueKey('learnQuestions')),
                _more(context, Icons.auto_awesome, tr('AI study'), tr('Question bank, coach and viva practice'), () => _open(context, tr('AI study'), const AiHubTab()), key: const ValueKey('tabAi')),
                _more(context, Icons.healing_outlined, tr('Procedures'), tr('Your log and skills passport'), () => _open(context, tr('Procedures'), const SkillsTab())),
                _more(context, Icons.image_search_outlined, tr('Imaging'), tr('Image review practice'), () => _open(context, tr('Imaging'), const ImagingTab())),
                _more(context, Icons.edit_note, tr('Notebook'), tr('Your personal notes'), () => _open(context, tr('Notebook'), const _NotebookTab())),
                    _more(context, Icons.record_voice_over_outlined, tr('Feedback'), tr('Feedback you received'), () => _open(context, tr('Feedback'), const FeedbackTab())),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Opens the Procedures log (and the skills passport) as its own screen: Home, the Portfolio and the focus
/// list can call this instead of switching to the Learn tab.
void openProceduresScreen(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text('Procedures')), body: const SkillsTab())));
}

// ================================================================ flashcards

/// First tab of Learn: the daily queue of review cards (your own cases, notes, pearls and the library cards that
/// your missed quiz questions create), plus the settings that feed it.
class FlashcardsTab extends StatefulWidget {
  const FlashcardsTab({super.key});
  @override
  State<FlashcardsTab> createState() => _FlashcardsTabState();
}

class _FlashcardsTabState extends State<FlashcardsTab> {
  Future<void> _start({Set<ReviewKind>? kinds}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewSessionScreen(kinds: kinds)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final st = ReviewEngine.stats();
        final due = st['due'] ?? 0;
        final libCards = store.listOf('libcards').length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            const AiBankEntryCard(compact: true),
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                      child: Center(child: mm.Text('$due', key: const ValueKey('flashDue'), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: theme.colorScheme.onPrimaryContainer))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(due == 0 ? 'Nothing due today' : 'Cards due today', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text(trp('{a} cards in total, {b} learned', {'a': st['items'] ?? 0, 'b': st['learned'] ?? 0}), style: theme.textTheme.bodySmall),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: () => _start(), icon: const Icon(Icons.play_arrow), label: Text('Start today\u2019s review')),
                  if (libCards > 0)
                    TextButton.icon(onPressed: () => _start(kinds: {ReviewKind.library}), icon: const Icon(Icons.local_library_outlined, size: 18), label: Text(trp('Only library cards ({n})', {'n': libCards}))),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Add missed questions to review cards'),
              subtitle: Text('Every wrong answer in a self-test becomes a card, and comes back sooner.'),
              value: quizAutoCards(),
              onChanged: (v) async {
                await setQuizAutoCards(v);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 4),
            Text('Study universe', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: Text('Core 250 (recommended)'),
                  selected: studyUniverse() == kUniverseCore,
                  onSelected: (_) async {
                    await setStudyUniverse(kUniverseCore);
                    if (mounted) setState(() {});
                  }),
              ChoiceChip(
                  label: Text('All installed articles'),
                  selected: studyUniverse() == kUniverseAll,
                  onSelected: (_) async {
                    await setStudyUniverse(kUniverseAll);
                    if (mounted) setState(() {});
                  }),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Used by Test myself and by the exam planner.', style: theme.textTheme.bodySmall),
            ),
            const SizedBox(height: 8),
            const TodayPlanCard(),
          ],
        );
      },
    );
  }
}

// ================================================================ procedures

const List<String> kProcedureNames = [
  'IV cannulation', 'Blood sampling', 'ABG', 'Suturing', 'Wound dressing',
  'Urinary catheterization', 'NG tube', 'Casting / splinting', 'Reduction',
  'Lumbar puncture', 'Chest tube', 'CPR', 'ECG', 'Incision & drainage',
  'Intubation', 'Paracentesis', 'Normal delivery (assisted)', 'Other',
];

const List<String> kProcedureRoles = [
  'Observed', 'Assisted', 'Performed under supervision', 'Performed independently',
];

Future<void> editProcedure(BuildContext context, [J? p, String? presetName]) async {
  final cur = store.currentRotation();
  final res = await showFormSheet(
    context,
    title: p == null ? 'Log procedure' : 'Procedure',
    specs: const [
      FieldSpec('name', 'Procedure', options: kProcedureNames),
      FieldSpec('role', 'My role', type: FT.choice, options: kProcedureRoles),
      FieldSpec('confidence', 'My confidence now (1 = low, 5 = high)',
          type: FT.choice, options: ['1', '2', '3', '4', '5']),
      FieldSpec('assessedBy', 'Assessment',
          type: FT.choice, options: ['Self-assessed', 'Supervisor assessed']),
      FieldSpec('date', 'Date', type: FT.date),
      FieldSpec('caseCode', 'Related case code (optional)', hint: 'MED-0012'),
      FieldSpec('outcome', 'Outcome / complications / what I learned', type: FT.multi),
      FieldSpec('feedback', 'Supervisor feedback', type: FT.multi),
    ],
    initial: p ??
        <String, dynamic>{
          'id': newId('p'),
          'date': todayStr(),
          'rotationId': cur == null ? '' : cur['id'].toString(),
          'role': 'Assisted',
          'assessedBy': 'Self-assessed',
          if (presetName != null) 'name': presetName,
        },
    canDelete: p != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeFrom(store.procedures, 'procedures.json', p!['id'].toString());
  } else {
    await store.upsert(store.procedures, 'procedures.json', res);
  }
}


class ProceduresLogTab extends StatelessWidget {
  const ProceduresLogTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final list = List<J>.from(store.procedures);
        list.sort((a, b) =>
            (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
        final counts = <String, int>{};
        for (final p in list) {
          final n = (p['name'] ?? '').toString();
          if (n.isEmpty) continue;
          counts[n] = (counts[n] ?? 0) + 1;
        }
        var confSum = 0;
        var confN = 0;
        var sup = 0;
        for (final p in list) {
          final c = int.tryParse((p['confidence'] ?? '').toString());
          if (c != null) {
            confSum += c;
            confN++;
          }
          if (p['assessedBy'] == 'Supervisor assessed') sup++;
        }
        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(onPressed: () => editProcedure(context), icon: const Icon(Icons.add), label: Text('Log procedure')),
              ),
              const SizedBox(height: 6),
              if (list.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(label: Text(trp('{n} logged', {'n': list.length}))),
                    if (confN > 0)
                      Chip(label: Text(trp('Avg confidence {n}/5', {'n': (confSum / confN).toStringAsFixed(1)}))),
                    Chip(label: Text(trp('{n} supervisor assessed', {'n': sup}))),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              if (counts.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final e in counts.entries) Chip(label: Text('${tr(e.key)}: ${e.value}')),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (list.isEmpty)
                const EmptyState(
                  kind: EmptyKind.learn,
                  title: 'No procedures logged yet.',
                  message: 'Log every cannulation, suture or ABG with your role and confidence.',
                ),
              for (var i = 0; i < list.length; i++)
                FadeSlideIn(
                  key: ValueKey(list[i]['id']),
                  index: i,
                  child: AppCard(
                    child: ListTile(
                      onTap: () => editProcedure(context, list[i]),
                      title: Text(tr((list[i]['name'] ?? '').toString())),
                      subtitle: Text(
                        [
                          prettyDate((list[i]['date'] ?? '').toString()),
                          tr((list[i]['role'] ?? '').toString()),
                          if ((list[i]['confidence'] ?? '').toString().isNotEmpty)
                            trp('confidence {n}/5', {'n': list[i]['confidence']}),
                          if ((list[i]['assessedBy'] ?? '') == 'Supervisor assessed')
                            tr('supervisor'),
                          if ((list[i]['caseCode'] ?? '').toString().isNotEmpty)
                            '${list[i]['caseCode']}',
                          if (isSigned(list[i])) tr('signed'),
                        ].where((e) => e.isNotEmpty).join(' • '),
                      ),
                      trailing: IconButton(
                        tooltip: tr('Supervisor sign-off'),
                        icon: Icon(isSigned(list[i]) ? Icons.verified_outlined : Icons.pending_outlined,
                            color: isSigned(list[i]) ? Colors.green : null),
                        onPressed: () => editProcedureSignOff(context, list[i]),
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

// ================================================================ notebook

Future<void> editNote(BuildContext context, [J? n]) async {
  final res = await showFormSheet(
  context,
    title: n == null ? 'New note' : 'Note',
    specs: const [
      FieldSpec('title', 'Title'),
      FieldSpec('body', 'What I learned', type: FT.multi),
      FieldSpec('tags', 'Tags (comma separated)', hint: 'cardiology, antibiotics'),
      FieldSpec('caseCode', 'Related case code (optional)'),
    ],
    initial: n ?? <String, dynamic>{'id': newId('n'), 'date': todayStr()},
    canDelete: n != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeFrom(store.notes, 'notes.json', n!['id'].toString());
  } else {
    await store.upsert(store.notes, 'notes.json', res);
  }
  }


class _NotebookTab extends StatefulWidget {
  const _NotebookTab();

  @override
  State<_NotebookTab> createState() => _NotebookTabState();
}

class _NotebookTabState extends State<_NotebookTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final q = _q.trim().toLowerCase();
        final list = store.notes.where((n) {
          if (q.isEmpty) return true;
          return '${n['title']} ${n['body']} ${n['tags']}'.toLowerCase().contains(q);
        }).toList();
        list.sort((a, b) =>
            (b['updated'] ?? '').toString().compareTo((a['updated'] ?? '').toString()));
        return Scaffold(
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr('Search notes'),
                    isDense: true,
                    suffixIcon: IconButton(tooltip: tr('New note'), icon: const Icon(Icons.edit_note), onPressed: () => editNote(context)),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const EmptyState(
                        kind: EmptyKind.learn,
                        title: 'Your personal notebook',
                        message: 'Pearls, guidelines, doses, things the supervisor taught you.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                        children: [
                          for (var i = 0; i < list.length; i++)
                            FadeSlideIn(
                              key: ValueKey(list[i]['id']),
                              index: i,
                              child: AppCard(
                                child: ListTile(
                                  onTap: () => editNote(context, list[i]),
                                  title: Text((list[i]['title'] ?? '').toString().isEmpty
                                      ? '(untitled)'
                                      : list[i]['title'].toString()),
                                  subtitle: Text(
                                    (list[i]['body'] ?? '').toString(),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ================================================================ review

class _ReviewTab extends StatelessWidget {
  const _ReviewTab();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final all = store.casesSorted();
        final flagged = all.where((c) => c.review).toList();
        final withQuestions =
            all.where((c) => c.s('questions').trim().isNotEmpty).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            const AiBankEntryCard(),
            const ExamPlannerSection(),
            const SectionHeader('Cases flagged for review'),
            if (flagged.isEmpty)
              const EmptyState(
                kind: EmptyKind.generic,
                title: 'Nothing flagged',
                message: 'Use “To review later” inside a case.',
              ),
            for (var i = 0; i < flagged.length; i++) FadeSlideIn(index: i, child: CaseTile(flagged[i])),
            const SectionHeader('Open questions from my cases'),
            if (withQuestions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No open questions.'),
              ),
            for (final c in withQuestions)
              AppCard(
                child: ListTile(
                  onTap: () => openCase(context, c),
                  title: Text('${c.s('code')} • ${c.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(c.s('questions')),
                ),
              ),
          ],
        );
      },
    );
  }
}


// ================================================================ questions inbox

Future<void> editQuestion(BuildContext context, [J? q]) async {
  final res = await showFormSheet(
  context,
    title: q == null ? 'New question' : 'Question',
    specs: const [
      FieldSpec('question', 'Question', type: FT.multi),
      FieldSpec('status', 'Status', type: FT.choice, options: ['Open', 'Answered']),
      FieldSpec('answer', 'Answer', type: FT.multi),
      FieldSpec('reference', 'Reference (book, guideline, link)'),
      FieldSpec('caseCode', 'Related case code (optional)'),
    ],
    initial: q ?? <String, dynamic>{'id': newId('q'), 'date': todayStr(), 'status': 'Open'},
    canDelete: q != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeFrom(store.inbox, 'questions.json', q!['id'].toString());
  } else {
    await store.upsert(store.inbox, 'questions.json', res);
  }
  }



class _QuestionsTab extends StatefulWidget {
  const _QuestionsTab();

  @override
  State<_QuestionsTab> createState() => _QuestionsTabState();
}

class _QuestionsTabState extends State<_QuestionsTab> {
  bool _openOnly = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final list = store.inbox
            .where((q) => !_openOnly || (q['status'] ?? 'Open') != 'Answered')
            .toList()
          ..sort((a, b) =>
              (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Row(
                children: [
                  OutlinedButton.icon(onPressed: () => editQuestion(context), icon: const Icon(Icons.add), label: Text('Add question')),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Open only'),
                    selected: _openOnly,
                    onSelected: (v) => setState(() => _openOnly = v),
                  ),
                ],
              ),
              if (list.isEmpty)
                const EmptyState(
                  kind: EmptyKind.learn,
                  title: 'Question inbox',
                  message: 'Write down every question you could not answer on the ward, '
                      'then answer it later and keep the reference.',
                ),
              for (var i = 0; i < list.length; i++)
                FadeSlideIn(
                  key: ValueKey(list[i]['id']),
                  index: i,
                  child: AppCard(
                    child: ListTile(
                      onTap: () => editQuestion(context, list[i]),
                      leading: Icon(
                        list[i]['status'] == 'Answered'
                            ? Icons.check_circle_outline
                            : Icons.help_outline,
                      ),
                      title: Text((list[i]['question'] ?? '').toString(),
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        prettyDate((list[i]['date'] ?? '').toString()),
                        if ((list[i]['caseCode'] ?? '').toString().isNotEmpty)
                          '${list[i]['caseCode']}',
                        if ((list[i]['answer'] ?? '').toString().isNotEmpty) '${list[i]['answer']}',
                      ].where((e) => e.isNotEmpty).join('\n')),
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



// ================================================================ exam / board planner

/// Collapsible planner: exam date + courses -> a day-by-day list of the user's weak spots and
/// topics not studied yet (titles from the downloaded packs only), with ticks and days left.
class ExamPlannerSection extends StatelessWidget {
  const ExamPlannerSection({super.key});
  @override
  Widget build(BuildContext context) {
    return Fold(
      id: 'exam_planner',
      title: tr('Exam planner'),
      subtitle: tr('Plan your revision day by day'),
      icon: Icons.event_note_outlined,
      children: const [_PlannerBody()],
    );
  }
}

class _PlannerBody extends StatefulWidget {
  const _PlannerBody();
  @override
  State<_PlannerBody> createState() => _PlannerBodyState();
}

class _PlannerBodyState extends State<_PlannerBody> {
  ExamPlan? _plan = examPlan();
  bool _editing = false;
  bool _busy = false;
  late final TextEditingController _name = TextEditingController(text: _plan?.name ?? '');
  String _date = examPlan()?.date ?? '';
  late final Set<String> _packs = {...?_plan?.packs};
  late String _preset = _plan?.preset.isNotEmpty == true ? _plan!.preset : 'internship';
  Map<String, double> _weights = {};
  bool _showWeights = false;
  List<String> _specs = const [];

  @override
  void initState() {
    super.initState();
    _initSpecs();
  }

  Future<void> _initSpecs() async {
    final ts = await loadCoreTopics();
    final sp = specialtiesOf(ts);
    if (!mounted) return;
    setState(() {
      _specs = sp;
      _weights = _plan != null && _plan!.weights.isNotEmpty ? {...presetWeights('equal', sp), ..._plan!.weights} : presetWeights(_preset, sp);
    });
  }

  void _pickPreset(String id) => setState(() {
        _preset = id;
        _weights = presetWeights(id, _specs);
      });

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _build({bool keepDone = false}) async {
    setState(() => _busy = true);
    final core = studyUniverse() == kUniverseCore;
    final items = await buildPlanItems(packs: _packs.toList(), examDate: _date, weights: core ? _weights : null);
    final old = _plan;
    final plan = ExamPlan(
      name: _name.text.trim(),
      date: _date,
      packs: _packs.toList(),
      items: items,
      done: keepDone && old != null ? {...old.done} : <String>{},
      weights: core ? _weights : const {},
      preset: core ? _preset : '',
      start: todayStr(),
      perDay: max(1, (items.length / max(1, examDaysLeft(_date))).ceil()),
      doneOn: keepDone && old != null ? {...old.doneOn} : const {},
      revDone: keepDone && old != null ? {...old.revDone} : const {},
    );
    await saveExamPlan(plan);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _editing = false;
      _busy = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final cur = parseDate(_date) ?? now.add(const Duration(days: 30));
    final d = await showDatePicker(context: context, initialDate: cur.isBefore(now) ? now : cur, firstDate: now, lastDate: now.add(const Duration(days: 730)));
    if (d != null && mounted) setState(() => _date = fmtDate(d));
  }

  Future<void> _openItem(PlanItem it) async {
    final i = await library.indexOfTitle(it.packId, it.title);
    if (i != null && mounted) openArticle(context, it.packId, i);
  }

  void _quizItem(PlanItem it) {
    final q = stripSource(it.title).replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(packId: it.packId, query: q, autoStart: true, count: 5)));
  }

  Future<void> _tick(PlanItem it) async {
    await togglePlanDone(it.key);
    if (mounted) setState(() => _plan = examPlan());
  }

  String _summary(int a, int q) => trp(a == 1 ? '{a} article + {q} questions' : '{a} articles + {q} questions', {'a': a, 'q': q});

  Widget _row(PlanItem it, bool done) {
    final pack = library.pack(it.packId)?.title ?? '';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(value: done, onChanged: (_) => _tick(it)),
      title: mm.Text(stripSource(it.title), maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: done ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
      subtitle: Text(it.weak ? '${tr('Weak spot')} • $pack' : pack, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(tooltip: tr('Test myself'), icon: const Icon(Icons.quiz_outlined, size: 20), onPressed: () => _quizItem(it)),
      onTap: () => _openItem(it),
    );
  }

  Widget _form(ThemeData theme) {
    final packs = [for (final p in library.textPacks) if (p.kind != 'medline' && p.kind != 'user') p];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: _name, decoration: InputDecoration(labelText: tr('Exam name (optional)'), hintText: tr('Board exam, final exam…'))),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _pickDate,
        icon: const Icon(Icons.event),
        label: Text(parseDate(_date) == null ? tr('Choose the exam date') : prettyDate(_date)),
      ),
      const SizedBox(height: 10),
      if (studyUniverse() == kUniverseCore) ...[
        Text('Exam blueprint', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: [
          for (final id in kPlanPresetIds)
            ChoiceChip(label: Text(planPresetName(id)), selected: _preset == id, visualDensity: VisualDensity.compact, onSelected: (_) => _pickPreset(id)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Presets are approximate shares by specialty from public exam outlines (see the notes in the app), not an official blueprint.', style: theme.textTheme.bodySmall),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _showWeights = !_showWeights),
          icon: Icon(_showWeights ? Icons.expand_less : Icons.tune, size: 18),
          label: Text('Weights by specialty'),
        ),
        if (_showWeights)
          for (final sp in _specs)
            Row(children: [
              Expanded(flex: 5, child: mm.Text(sp, style: theme.textTheme.bodySmall)),
              Expanded(
                flex: 6,
                child: Slider(
                  value: (_weights[sp] ?? 0).clamp(0, 20).toDouble(),
                  min: 0,
                  max: 20,
                  divisions: 40,
                  onChanged: (v) => setState(() {
                    _weights = {..._weights, sp: v};
                    _preset = 'custom';
                  }),
                ),
              ),
              SizedBox(width: 28, child: mm.Text((_weights[sp] ?? 0).toStringAsFixed(0), textAlign: TextAlign.end, style: theme.textTheme.labelSmall)),
            ]),
        const SizedBox(height: 6),
      ],
      Text(studyUniverse() == kUniverseCore ? 'Courses to revise (optional)' : 'Courses to revise', style: theme.textTheme.labelLarge),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 0, children: [
        for (final p in packs)
          FilterChip(
            label: mm.Text(p.title),
            selected: _packs.contains(p.id),
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() => v ? _packs.add(p.id) : _packs.remove(p.id)),
          ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        FilledButton.icon(
          onPressed: _busy || parseDate(_date) == null || (_packs.isEmpty && studyUniverse() != kUniverseCore) ? null : () => _build(keepDone: _plan != null && _plan!.date == _date),
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_motion_outlined),
          label: Text('Build my plan'),
        ),
        if (_plan != null && _editing) TextButton(onPressed: () => setState(() => _editing = false), child: Text('Cancel')),
      ]),
    ]);
  }

  Future<void> _tickReview(PlanReview r) async {
    await togglePlanReview(r.id);
    if (mounted) setState(() => _plan = examPlan());
  }

  Future<void> _adapt(ExamPlan plan) async {
    final wr = weekReview(plan);
    final rb = rebalanceWeights(plan, wr);
    final ok = await showDialog<bool>(context: context, builder: (_) => _AdaptDialog(wr: wr, rb: rb));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final np = await adaptWeekPlan(plan, rb);
    await saveExamPlan(np);
    if (mounted) setState(() {
      _plan = np;
      _busy = false;
    });
  }

  Future<void> _catchUp(ExamPlan plan) async {
    final np = catchUpPlan(plan);
    await saveExamPlan(np);
    if (mounted) setState(() => _plan = np);
  }

  Widget _view(ThemeData theme, ExamPlan plan) {
    final cs = theme.colorScheme;
    final left = examDaysLeft(plan.date);
    final total = plan.items.length;
    final done = plan.items.where((i) => plan.done.contains(i.key)).length;
    final days = planSchedule(plan);
    final overdue = planOverdue(plan);
    final reviews = planReviewsDue(plan);
    final progress = planProgress(plan);
    final bigText = left > 0 ? '$left' : (left == 0 ? '0' : '—');
    final label = left > 1 ? tr('days left') : left == 1 ? tr('day left') : left == 0 ? tr('Exam is today') : tr('The exam date has passed');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            mm.Text(bigText, key: const ValueKey('planDaysLeft'), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: cs.onPrimaryContainer)),
            if (left > 0) Text(label, style: theme.textTheme.labelSmall?.copyWith(color: cs.onPrimaryContainer)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (plan.name.isNotEmpty) mm.Text(plan.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            mm.Text(prettyDate(plan.date), style: theme.textTheme.bodyMedium),
            if (left <= 0) Text(label, style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      if (total > 0) ...[
        LinearProgressIndicator(value: done / total, minHeight: 6, borderRadius: BorderRadius.circular(6)),
        const SizedBox(height: 4),
        Text(trp('{done} of {total} done', {'done': done, 'total': total}), style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: 8),
      if (total == 0)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Nothing to plan yet: no weak spots and no new topics in the chosen courses. Take a few self-tests, or pick more courses.', style: theme.textTheme.bodyMedium),
        )
      else if (days.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Everything on the plan is done. Well done!', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.green, fontWeight: FontWeight.w700)),
        )
      else ...[
        if (overdue.isNotEmpty)
          Container(
            key: const ValueKey('planBehind'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cs.errorContainer.withAlpha(90), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(child: Text(trp('You are {n} items behind the plan.', {'n': overdue.length}), style: theme.textTheme.bodyMedium)),
              FilledButton.tonal(onPressed: () => _catchUp(plan), child: Text('Catch up')),
            ]),
          ),
        Text('${tr('Today')}: ${_summary(days.first.articles, days.first.questions)}', key: const ValueKey('planToday'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        for (final it in days.first.items) _row(it, false),
        for (final d in days.skip(1).take(6))
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: Text('${prettyDate(fmtDate(d.date))}: ${_summary(d.articles, d.questions)}', style: theme.textTheme.bodyMedium),
            children: [for (final it in d.items) _row(it, false)],
          ),
        if (days.length > 7) Padding(padding: const EdgeInsets.only(top: 4), child: Text(trp('and {n} more days', {'n': days.length - 7}), style: theme.textTheme.bodySmall)),
      ],
      if (reviews.isNotEmpty) ...[
        Text(trp('Review: {n} studied earlier', {'n': reviews.length}), key: const ValueKey('planReviews'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        for (final r in reviews)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Checkbox(value: false, onChanged: (_) => _tickReview(r)),
            title: mm.Text(stripSource(r.item.title), maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
            subtitle: Text(trp('After {n} days', {'n': r.afterDays})),
            trailing: IconButton(tooltip: tr('Test myself'), icon: const Icon(Icons.quiz_outlined, size: 20), onPressed: () => _quizItem(r.item)),
            onTap: () => _openItem(r.item),
          ),
      ],
      if (progress.length > 1)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          dense: true,
          title: Text('Progress by specialty', style: theme.textTheme.bodyMedium),
          children: [
            for (final e in (progress.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2))))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(flex: 5, child: mm.Text(e.key, style: theme.textTheme.bodySmall)),
                  Expanded(flex: 4, child: LinearProgressIndicator(value: e.value.$1 / e.value.$2, minHeight: 6, borderRadius: BorderRadius.circular(6))),
                  SizedBox(width: 44, child: mm.Text('${e.value.$1}/${e.value.$2}', textAlign: TextAlign.end, textDirection: TextDirection.ltr, style: theme.textTheme.labelSmall)),
                ]),
              ),
          ],
        ),
      if (done > 0)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          dense: true,
          title: Text(trp('Done ({n})', {'n': done}), style: theme.textTheme.bodyMedium),
          children: [for (final it in plan.items.where((i) => plan.done.contains(i.key))) _row(it, true)],
        ),
      const SizedBox(height: 4),
      Wrap(spacing: 8, children: [
        TextButton.icon(onPressed: _busy ? null : () => _build(keepDone: true), icon: const Icon(Icons.refresh, size: 18), label: Text('Rebuild with my latest results')),
        TextButton.icon(key: const ValueKey('planAdapt'), onPressed: _busy ? null : () => _adapt(plan), icon: const Icon(Icons.tune, size: 18), label: Text('Adapt this week')),
        TextButton.icon(onPressed: () => setState(() => _editing = true), icon: const Icon(Icons.edit_outlined, size: 18), label: Text('Change')),
        TextButton.icon(
          onPressed: () async {
            if (await confirmDialog(context, 'Delete this plan?')) {
              await saveExamPlan(null);
              if (mounted) setState(() => _plan = null);
            }
          },
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text('Delete'),
        ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        if (!library.ready || library.textPacks.where((p) => p.kind != 'medline').isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Download a course first (Library → Courses). Then pick your exam date and the planner lists what to revise each day.', style: theme.textTheme.bodyMedium),
          );
        }
        final plan = _plan;
        if (plan == null || _editing) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (plan == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('No exam date yet. Choose it and the courses you are revising: the plan puts your weak spots first.', style: theme.textTheme.bodyMedium),
              ),
            _form(theme),
          ]);
        }
        return _view(theme, plan);
      },
    );
  }
}


/// "Adapt this week": what last week's results say, the proposed weight changes (local, explainable) and an optional AI explanation.
class _AdaptDialog extends StatefulWidget {
  final WeekReview wr;
  final Rebalance rb;
  const _AdaptDialog({required this.wr, required this.rb});
  @override
  State<_AdaptDialog> createState() => _AdaptDialogState();
}

class _AdaptDialogState extends State<_AdaptDialog> {
  String? _text;
  bool _busy = false;
  bool _tried = false;

  Future<void> _explain() async {
    setState(() => _busy = true);
    final t = await explainRebalance(widget.rb, widget.wr);
    if (mounted) {
      setState(() {
        _busy = false;
        _tried = true;
        _text = t;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wr = widget.wr, rb = widget.rb;
    return AlertDialog(
      title: Text('Adapt this week'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          mm.Text(trp('Last 7 days: {d} of {p} planned items done.', {'d': wr.done, 'p': wr.planned}), key: const ValueKey('adaptWeek')),
          mm.Text(wr.accuracy == null ? tr('No answers in the last 7 days.') : trp('Answers: {a}% correct ({n} questions).', {'a': (wr.accuracy! * 100).round(), 'n': wr.answers})),
          const SizedBox(height: 8),
          if (rb.changes.isEmpty)
            Text('No specialty needs more or less time this week. The plan will be re-spread from today over the days left.', key: const ValueKey('adaptNone'))
          else ...[
            Text('Proposed changes', style: theme.textTheme.labelLarge),
            for (final c in rb.changes)
              mm.Text('• ${c.spec}: ${trp('{a} to {b}', {'a': c.before.toStringAsFixed(1), 'b': c.after.toStringAsFixed(1)})} (${c.accuracy == null ? '' : '${(c.accuracy! * 100).round()}%'}${c.after > c.before ? ' · ${tr('more time')}' : ' · ${tr('less time')}'})'),
          ],
          if (rb.behind) Padding(padding: const EdgeInsets.only(top: 6), child: Text('You did less than half of the planned items, so the rest is re-spread over the days left.')),
          const SizedBox(height: 8),
          AiBuilder(builder: (context, enabled, online) {
            if (!enabled) return Text('Turn AI on in Settings for a short explanation of the changes.', style: theme.textTheme.bodySmall);
            if (_text != null) return Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)), child: mm.Text(_text!));
            if (_tried) return Text('No explanation available now. The changes above are complete.', style: theme.textTheme.bodySmall);
            return TextButton.icon(key: const ValueKey('adaptExplain'), onPressed: !online || _busy ? null : _explain, icon: const Icon(Icons.auto_awesome, size: 18), label: Text('Explain with AI'));
          }),
          if (_busy) const LinearProgressIndicator(),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
        FilledButton(key: const ValueKey('adaptApply'), onPressed: () => Navigator.pop(context, true), child: Text('Apply')),
      ],
    );
  }
}
