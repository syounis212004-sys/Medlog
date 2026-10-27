import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as mm show Text;

import 'ai/ai_api.dart';
import 'ai/ai_context.dart';
import 'ai/ai_doc_api.dart';
import 'ai/ai_quiz.dart';
import 'ai/ai_study.dart';
import 'ai/voice_input.dart';
import 'core_topics.dart';
import 'data.dart';
import 'i18n.dart';
import 'lib_user.dart';
import 'library.dart';
import 'screens_ai_quiz.dart';
import 'screens_library.dart' show openArticle;
import 'screens_quiz.dart' show QuizScreen;
import 'screens_review.dart' show ReviewSessionScreen;
import 'ui.dart';
import 'widgets.dart';

/// The AI study layer's screens: AI bank entry (Learn + Home), the AI hub tab, today's plan (study coach), viva / OSCE
/// examiner, Socratic teaching, guideline check and comparison, pre-shift quiz, case of the day, written-answer grading.
/// Every feature works (or has a local fallback) without AI and without internet; AI only suggests.

// ================================================================ shared bits

/// Opens the AI question bank (practice, generate, history).
void openAiBank(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => const AiQuizScreen()));
}

/// Entry points for the home screen / + menu / floating button (each opens its own screen).
void openPreShiftQuiz(BuildContext context) => Navigator.push(context, MaterialPageRoute(builder: (_) => const PreShiftScreen()));
void openCaseOfTheDay(BuildContext context) => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaseOfDayScreen()));
void openVivaExaminer(BuildContext context) => Navigator.push(context, MaterialPageRoute(builder: (_) => const VivaScreen()));
void openTeachMe(BuildContext context, [String topic = '']) => Navigator.push(context, MaterialPageRoute(builder: (_) => TeachScreen(topic: topic)));
void openCompareGuidelines(BuildContext context) => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompareScreen()));

/// Opens the AI hub (bank + coach + viva + teaching + checks) as its own screen.
void openAiHub(BuildContext context) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => const AiHubScreen()));
}

String failureText(String f) => switch (f) {
      'off' => tr('AI is off. Turn it on in Settings to use this. The local tools below still work.'),
      'offline' => tr('You are offline. Saved items and local tools still work.'),
      'cancelled' => tr('Cancelled: nothing was sent.'),
      'invalid' => tr('The AI answer could not be used (it did not follow the format or had no valid sources). Nothing was saved. Try again.'),
      'nolibrary' => tr('No library passages found for this topic. Download a course in the Library, or switch the AI source to the web in Settings.'),
      'nopassage' => tr('This article has no text to check.'),
      'notopic' => tr('Choose a topic first.'),
      _ => tr('The AI could not answer now. Try again later.'),
    };

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => AppCard(child: Padding(padding: const EdgeInsets.all(14), child: child));
}

class _AiNote extends StatelessWidget {
  final String text;
  const _AiNote(this.text);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
    ]);
  }
}

/// "Source: …" line (and the quote) of a statement made by the AI.
class _SourceLine extends StatelessWidget {
  final StudySource s;
  const _SourceLine(this.s);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (s.isEmpty) return Text('Source: not stated (unverified)', style: theme.textTheme.bodySmall);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      mm.Text('${tr('Source')}: ${s.label}', style: theme.textTheme.bodySmall),
      if (s.quote.isNotEmpty) mm.Text('“${s.quote}”', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
      if (s.url.isNotEmpty) mm.Text(s.url, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary), textDirection: TextDirection.ltr),
    ]);
  }
}

/// Text field with a dictation button.
class _AnswerField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int minLines;
  final VoidCallback? onChanged;
  const _AnswerField({required this.controller, required this.label, this.minLines = 3, this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        minLines: minLines,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(labelText: tr(label), border: const OutlineInputBorder(), alignLabelWithHint: true, suffixIcon: VoiceInputButton(controller: controller, onChanged: onChanged)),
      );
}

Widget _aiBadge(BuildContext context, [String label = 'AI suggestion: check before use']) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.auto_awesome, size: 13, color: cs.onTertiaryContainer),
      const SizedBox(width: 4),
      Flexible(child: Text(label, style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer, fontWeight: FontWeight.w600))),
    ]),
  );
}

/// Body wrapper: registers the AI context and keeps lists readable.
class _Page extends StatelessWidget {
  final String title;
  final String kind;
  final List<Widget> children;
  const _Page({required this.title, required this.children, this.kind = 'learn'});
  @override
  Widget build(BuildContext context) => AiContextScope(
        ctx: AiScreenContext(kind: kind, title: title),
        child: Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView(padding: const EdgeInsets.all(16), children: children),
        ),
      );
}

// ================================================================ AI bank entry card

/// First-class entry to the AI question bank: counts, "Practice now" and "Generate more". Shown at the top of the Study
/// tab, in the AI tab and available to the home screen / + menu.
class AiBankEntryCard extends StatefulWidget {
  final bool compact;
  const AiBankEntryCard({super.key, this.compact = false});
  @override
  State<AiBankEntryCard> createState() => _AiBankEntryCardState();
}

class _AiBankEntryCardState extends State<AiBankEntryCard> {
  bool _busy = false;
  String? _msg;

  Future<void> _practice() async {
    final weak = allWeakTopicNames().isNotEmpty;
    final pick = AiPick(mode: weak ? 'weak' : 'all', count: 10);
    var (qs, _) = await selectFromBank(pick);
    if (qs.isEmpty && weak) (qs, _) = await selectFromBank(const AiPick(mode: 'all', count: 10));
    if (!mounted) return;
    if (qs.isEmpty) {
      setState(() => _msg = tr('No saved questions yet. Generate some when AI is on and you are online.'));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AiSessionScreen(pick: pick, questions: qs)));
    if (mounted) setState(() {});
  }

  Future<void> _generate() async {
    if (!Ai.enabled) {
      setState(() => _msg = tr('AI is off. Turn it on in Settings to generate questions.'));
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final weak = allWeakTopicNames().isNotEmpty;
    final r = await generateMore(weak ? 'weak' : 'core', count: 10);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = r.disabled
          ? tr('AI is off. Turn it on in Settings to generate questions.')
          : r.offline
              ? tr('You are offline: practising from your saved questions.')
              : r.capped
                  ? tr('Daily limit of AI requests reached. Try again tomorrow.')
                  : r.error != null && r.generated == 0
                      ? '${tr('Could not generate questions now. Your saved questions still work.')} (${r.error})'
                      : trp('{a} new questions saved.', {'a': r.accepted});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final bank = aiBank();
        final seen = bank.fold<int>(0, (n, q) => n + q.seen);
        final right = bank.fold<int>(0, (n, q) => n + q.correct);
        final weak = allWeakTopicNames().length;
        return AiBuilder(builder: (context, enabled, online) {
          final canGen = enabled && online;
          return AppCard(
            key: const ValueKey('aiBankCard'),
            color: cs.tertiaryContainer.withValues(alpha: 0.45),
            child: InkWell(
              onTap: () => openAiBank(context),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.auto_awesome, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text('AI question bank', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    Chip(key: const ValueKey('aiBankCount'), visualDensity: VisualDensity.compact, label: Text(trp('{n} saved questions', {'n': bank.length}))),
                    Chip(key: const ValueKey('aiBankWeak'), visualDensity: VisualDensity.compact, label: Text(trp('{n} weak topics', {'n': weak}))),
                    if (seen > 0) Chip(visualDensity: VisualDensity.compact, label: Text(trp('{p}% correct so far', {'p': (right * 100 / seen).round()}))),
                  ]),
                  if (!widget.compact)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        enabled
                            ? (online ? 'Questions come from your library and cited answers. Saved questions work offline.' : 'You are offline: practise from your saved questions.')
                            : 'AI is off: you can still practise your saved questions. Turn AI on in Settings to generate more.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    FilledButton.icon(key: const ValueKey('aiBankPractice'), onPressed: bank.isEmpty ? null : _practice, icon: const Icon(Icons.play_arrow), label: Text('Practice now')),
                    OutlinedButton.icon(
                      key: const ValueKey('aiBankGenerate'),
                      onPressed: _busy ? null : (canGen ? _generate : () => setState(() => _msg = enabled ? tr('You are offline: practising from your saved questions.') : tr('AI is off. Turn it on in Settings to generate questions.'))),
                      icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
                      label: Text('Generate more'),
                    ),
                  ]),
                  if (bank.isEmpty && _msg == null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('No saved questions yet. Generate some when AI is on and you are online.', style: theme.textTheme.bodySmall)),
                  if (_msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: mm.Text(_msg!, style: TextStyle(color: cs.primary))),
                ]),
              ),
            ),
          );
        });
      },
    );
  }
}

// ================================================================ AI hub (Learn > AI tab, also a screen)

class AiHubScreen extends StatelessWidget {
  const AiHubScreen({super.key});
  @override
  Widget build(BuildContext context) => AiContextScope(
        ctx: const AiScreenContext(kind: 'learn', title: 'AI study'),
        child: Scaffold(appBar: AppBar(title: Text('AI study')), body: const AiHubTab()),
      );
}

class AiHubTab extends StatelessWidget {
  const AiHubTab({super.key});

  void _go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  Widget _tile(BuildContext context, IconData icon, String title, String sub, Widget screen, {Key? key}) {
    return AppCard(
      child: ListTile(
        key: key,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _go(context, screen),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => ListView(
        key: const ValueKey('aiHub'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          const AiBankEntryCard(),
          AiBuilder(builder: (context, enabled, online) {
            if (enabled && online) return const SizedBox.shrink();
            return _Card(child: _AiNote(enabled ? 'You are offline. Saved questions, saved sessions and the self-viva work without internet.' : 'AI is off. Everything here has a local version that works without AI: your plan, the self-viva, saved questions. Turn AI on in Settings for examiner, teaching and checks.'));
          }),
          const SizedBox(height: 4),
          const TodayPlanCard(),
          const SectionHeader('Practise with an examiner'),
          _tile(context, Icons.record_voice_over_outlined, 'Viva / OSCE examiner', 'Cases built from guidelines, scored against a hidden checklist. Offline: saved sessions and self-viva.', const VivaScreen(), key: const ValueKey('tileViva')),
          _tile(context, Icons.psychology_alt_outlined, 'Teach me a topic', 'The AI asks first, then explains step by step with checks.', const TeachScreen(), key: const ValueKey('tileTeach')),
          _tile(context, Icons.bolt_outlined, 'Pre-shift quiz', '5 quick questions about your current rotation.', const PreShiftScreen(), key: const ValueKey('tilePreShift')),
          _tile(context, Icons.today_outlined, 'Case of the day', 'A fictional learning case from your library, discussed step by step.', const CaseOfDayScreen(), key: const ValueKey('tileCod')),
          _tile(context, Icons.rate_review_outlined, 'Written answers', 'Type an answer to a saved question and get graded against its source.', const WrittenPickerScreen(), key: const ValueKey('tileWritten')),
          const SectionHeader('Check and compare'),
          _tile(context, Icons.fact_check_outlined, 'Guideline check', 'Is my reference still current? What changed?', const GuidelineCheckScreen(), key: const ValueKey('tileGCheck')),
          _tile(context, Icons.compare_arrows, 'Compare guidelines', 'ESC vs AHA (or any two) for a topic, as a table.', const CompareScreen(), key: const ValueKey('tileCompare')),
          const SectionHeader('My weak spots'),
          const _WeakMemory(),
          const SizedBox(height: 8),
          Text('AI only suggests. It never changes your records, and every statement shows its source.', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _WeakMemory extends StatelessWidget {
  const _WeakMemory();
  @override
  Widget build(BuildContext context) {
    final names = allWeakTopicNames();
    if (names.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('No weak spots yet. Self-tests, viva sessions and written answers add to this list.'));
    return Wrap(spacing: 6, runSpacing: 4, children: [for (final n in names.take(12)) Chip(visualDensity: VisualDensity.compact, label: mm.Text(n))]);
  }
}

// ================================================================ today's plan (study coach)

class TodayPlanCard extends StatefulWidget {
  const TodayPlanCard({super.key});
  @override
  State<TodayPlanCard> createState() => _TodayPlanCardState();
}

class _TodayPlanCardState extends State<TodayPlanCard> {
  CoachPlan? _plan;
  CoachNote? _note;
  bool _busy = false;
  String? _msg;
  int _rev = -1;

  @override
  void initState() {
    super.initState();
    _load();
    store.addListener(_onStore);
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (store.rev != _rev) _load();
  }

  Future<void> _load() async {
    _rev = store.rev;
    var p = await buildCoachPlan();
    final n = savedCoachNote();
    if (n != null && n.order.isNotEmpty) p = reorderCoach(p, n.order);
    if (!mounted) return;
    setState(() {
      _plan = p;
      _note = n;
    });
  }

  Future<void> _ask() async {
    final p = _plan;
    if (p == null) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    final n = await coachAiNote(p, force: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (n == null) {
        _msg = tr('The AI could not help now. Your local plan above is complete.');
      } else {
        _note = n;
        if (n.order.isNotEmpty) _plan = reorderCoach(p, n.order);
      }
    });
  }

  Future<void> _open(CoachStep s) async {
    if (s.kind == 'cards') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewSessionScreen()));
      if (mounted) _load();
      return;
    }
    if (s.packId.isEmpty) return;
    final i = await library.indexOfTitle(s.packId, s.articleTitle);
    if (i != null && mounted) openArticle(context, s.packId, i);
  }

  void _quiz(CoachStep s) {
    final q = stripSource(s.articleTitle).replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(packId: s.packId, query: q, autoStart: true, count: 5)));
  }

  IconData _icon(String k) => switch (k) {
        'cards' => Icons.style_outlined,
        'weak' => Icons.flag_outlined,
        'plan' => Icons.event_note_outlined,
        'rotation' => Icons.local_hospital_outlined,
        _ => Icons.star_outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = _plan;
    return AppCard(
      key: const ValueKey('todayPlan'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.today_outlined, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(child: Text('Today’s plan', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            if (p != null && !p.isEmpty) Chip(visualDensity: VisualDensity.compact, label: Text(trp('{n} min', {'n': p.minutes}))),
          ]),
          if (p == null) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (p.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('Nothing urgent today. Open a Core 250 topic, take a self-test, or log a case.'))
          else ...[
            for (var i = 0; i < p.steps.length; i++)
              ListTile(
                key: ValueKey('coachStep$i'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(radius: 14, backgroundColor: cs.primaryContainer, child: Icon(_icon(p.steps[i].kind), size: 16, color: cs.onPrimaryContainer)),
                title: mm.Text(tr(p.steps[i].title.split(': ').first) + (p.steps[i].title.contains(': ') ? ': ${p.steps[i].title.split(': ').skip(1).join(': ')}' : ''), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: mm.Text('${trp('{n} min', {'n': p.steps[i].minutes})} · ${_detail(p.steps[i].detail)}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: p.steps[i].kind == 'cards' || p.steps[i].packId.isEmpty
                    ? null
                    : IconButton(tooltip: tr('Test myself'), icon: const Icon(Icons.quiz_outlined, size: 20), onPressed: () => _quiz(p.steps[i])),
                onTap: () => _open(p.steps[i]),
              ),
          ],
          if (_note != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cs.tertiaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _aiBadge(context),
                const SizedBox(height: 4),
                mm.Text(_note!.motivation),
                if (_note!.why.isNotEmpty) mm.Text(_note!.why, style: theme.textTheme.bodySmall),
              ]),
            ),
          ],
          const SizedBox(height: 6),
          AiBuilder(builder: (context, enabled, online) {
            if (!enabled) return Text('Built from your own data on this phone. Turn AI on in Settings for a short motivating note and a focused order.', style: theme.textTheme.bodySmall);
            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('coachAi'),
                onPressed: !online || _busy || p == null || p.isEmpty ? null : _ask,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 18),
                label: Text(online ? 'Focus my 25 minutes with AI' : 'Offline: the local plan above still works'),
              ),
            );
          }),
          if (_msg != null) mm.Text(_msg!, style: theme.textTheme.bodySmall),
          Text('Only counts leave the phone for the AI note: no topics, no case data.', style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }

  String _detail(String d) {
    final m = RegExp(r'^(\d+) cards? due$').firstMatch(d);
    if (m != null) return trp(m.group(1) == '1' ? '{n} card due' : '{n} cards due', {'n': m.group(1)!});
    if (d.startsWith('For your rotation: ')) return '${tr('For your rotation')}: ${d.substring(19)}';
    return tr(d);
  }
}

// ================================================================ viva / OSCE

class VivaScreen extends StatefulWidget {
  const VivaScreen({super.key});
  @override
  State<VivaScreen> createState() => _VivaScreenState();
}

enum _VPhase { setup, loading, running, result, self }

class _VivaScreenState extends State<VivaScreen> {
  _VPhase _phase = _VPhase.setup;
  String _mode = 'viva';
  String _level = 'medium';
  String? _spec;
  List<String> _specs = const [];
  final _topic = TextEditingController();
  final _answer = TextEditingController();
  VivaStation? _st;
  final List<VivaTurn> _turns = [];
  int _i = 0;
  bool _scoring = false;
  VivaTurn? _last;
  String? _msg;
  VivaResult? _result;
  // self-viva
  List<SelfVivaItem> _self = const [];
  final List<int> _got = [];
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _initSpecs();
  }

  @override
  void dispose() {
    _topic.dispose();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _initSpecs() async {
    final ts = await loadCoreTopics();
    final sp = specialtiesOf(ts);
    final rot = store.currentRotation();
    final rs = rot == null ? null : specialtyForRotation('${rot['name'] ?? ''}');
    if (!mounted) return;
    setState(() {
      _specs = sp;
      _spec = rs != null && sp.contains(rs) ? rs : (sp.isEmpty ? null : sp.first);
    });
  }

  Future<void> _start() async {
    if (_spec == null && _topic.text.trim().isEmpty) {
      setState(() => _msg = tr('Choose a specialty or type a topic.'));
      return;
    }
    setState(() {
      _phase = _VPhase.loading;
      _msg = null;
    });
    final g = await generateViva(mode: _mode, specialty: _spec ?? _topic.text.trim(), difficulty: _level, topic: _topic.text.trim());
    if (!mounted) return;
    if (g.station == null) {
      setState(() {
        _phase = _VPhase.setup;
        _msg = failureText(g.failure);
      });
      return;
    }
    setState(() {
      _st = g.station;
      _turns.clear();
      _i = 0;
      _last = null;
      _answer.clear();
      _phase = _VPhase.running;
    });
  }

  Future<void> _submit() async {
    final st = _st;
    if (st == null || _scoring) return;
    setState(() => _scoring = true);
    final t = await scoreViva(st, _i, _answer.text.trim());
    if (!mounted) return;
    setState(() {
      _scoring = false;
      _last = t;
      _turns.add(t);
    });
  }

  Future<void> _next() async {
    final st = _st!;
    if (_i + 1 >= st.items.length) {
      final r = await finishViva(st, _turns);
      if (!mounted) return;
      setState(() {
        _result = r;
        _phase = _VPhase.result;
      });
    } else {
      setState(() {
        _i++;
        _last = null;
        _answer.clear();
      });
    }
  }

  Future<void> _startSelf() async {
    setState(() => _phase = _VPhase.loading);
    final items = await selfVivaItems();
    if (!mounted) return;
    if (items.isEmpty) {
      setState(() {
        _phase = _VPhase.setup;
        _msg = tr('Nothing to practise yet: take a self-test or download a course first.');
      });
      return;
    }
    setState(() {
      _self = items;
      _got.clear();
      _revealed = false;
      _phase = _VPhase.self;
    });
  }

  Future<void> _selfGrade(int g) async {
    _got.add(g);
    if (_got.length >= _self.length) {
      final st = VivaStation('self', 'selfviva', 'Self-viva', 'medium', '', const [], 'library');
      final r = await finishSelfViva(_self, _got);
      if (!mounted) return;
      setState(() {
        _st = st;
        _result = r;
        _phase = _VPhase.result;
      });
    } else {
      setState(() => _revealed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _VPhase.loading:
        return _Page(title: 'Viva / OSCE examiner', children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))]);
      case _VPhase.running:
        return _running(context);
      case _VPhase.result:
        return _resultView(context);
      case _VPhase.self:
        return _selfView(context);
      case _VPhase.setup:
        return _setup(context);
    }
  }

  Widget _setup(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = vivaSessions();
    return _Page(title: 'Viva / OSCE examiner', children: [
      AiBuilder(builder: (context, enabled, online) => _Card(child: _AiNote(enabled ? (online ? 'A senior examiner (AI) presents a fictional case from your library or from guidelines, asks one question at a time and scores you against a hidden checklist. Typed or dictated answers.' : 'You are offline: you can review saved sessions or use the self-viva below.') : 'AI is off. You can review saved sessions and use the self-viva (your own weak topics, no AI).'))),
      const SectionHeader('Mode'),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final e in kVivaModes.entries) ChoiceChip(key: ValueKey('vivaMode_${e.key}'), label: Text(e.value), selected: _mode == e.key, onSelected: (_) => setState(() => _mode = e.key)),
      ]),
      const SectionHeader('Specialty'),
      if (_specs.isNotEmpty)
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _spec,
          items: [for (final s in _specs) DropdownMenuItem(value: s, child: mm.Text(s, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _spec = v),
        ),
      const SizedBox(height: 8),
      TextField(controller: _topic, decoration: InputDecoration(labelText: tr('Topic (optional), e.g. pneumonia'), border: const OutlineInputBorder())),
      const SectionHeader('Difficulty'),
      Wrap(spacing: 8, children: [for (final l in kVivaLevels) ChoiceChip(label: Text(l[0].toUpperCase() + l.substring(1)), selected: _level == l, onSelected: (_) => setState(() => _level = l))]),
      const SizedBox(height: 14),
      AiBuilder(builder: (context, enabled, online) => FilledButton.icon(key: const ValueKey('vivaStart'), onPressed: enabled && online ? _start : null, icon: const Icon(Icons.auto_awesome), label: Text('Start with the AI examiner'))),
      const SizedBox(height: 8),
      OutlinedButton.icon(key: const ValueKey('selfVivaStart'), onPressed: _startSelf, icon: const Icon(Icons.person_search_outlined), label: Text('Self-viva on my weak topics (no AI)')),
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: mm.Text(_msg!, style: TextStyle(color: theme.colorScheme.primary))),
      const SectionHeader('Saved sessions'),
      if (sessions.isEmpty) Text('No sessions yet.'),
      for (final s in sessions.take(20))
        AppCard(
          child: ListTile(
            key: ValueKey('vivaSaved_${s['id']}'),
            leading: Icon(s['type'] == 'self' ? Icons.person_search_outlined : Icons.record_voice_over_outlined),
            title: mm.Text('${s['total']} / ${s['max']} · ${tr(kVivaModes['${s['mode']}'] ?? 'Self-viva')}'),
            subtitle: mm.Text('${'${s['date']}'.split('T').first} · ${s['spec']}'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VivaReportScreen(session: s))),
          ),
        ),
    ]);
  }

  Widget _running(BuildContext context) {
    final theme = Theme.of(context);
    final st = _st!;
    final item = st.items[_i];
    final last = _last;
    return _Page(title: trp('Question {i} of {n}', {'i': _i + 1, 'n': st.items.length}), kind: 'quiz', children: [
      LinearProgressIndicator(value: (_i + (last != null ? 1 : 0)) / st.items.length),
      const SizedBox(height: 12),
      _aiBadge(context, 'Fictional case · AI examiner'),
      const SizedBox(height: 8),
      _Card(child: mm.Text(st.vignette)),
      const SizedBox(height: 8),
      mm.Text(item.question, style: theme.textTheme.titleMedium),
      const SizedBox(height: 10),
      if (last == null) ...[
        _AnswerField(controller: _answer, label: 'Your answer', minLines: 4, onChanged: () => setState(() {})),
        const SizedBox(height: 10),
        FilledButton.icon(key: const ValueKey('vivaSubmit'), onPressed: _scoring || _answer.text.trim().isEmpty ? null : _submit, icon: _scoring ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), label: Text('Submit answer')),
        Text('The marking checklist stays hidden until the end.', style: theme.textTheme.bodySmall),
      ] else ...[
        _Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            mm.Text('${last.score} / ${last.max}', key: const ValueKey('vivaScore'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (last.estimated) Text('Scored by a local keyword check (the AI was not available): treat it as a rough estimate.', style: theme.textTheme.bodySmall),
            if (last.feedback.isNotEmpty) ...[const SizedBox(height: 6), mm.Text(last.feedback)],
            if (last.senior.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('What a senior would expect', style: theme.textTheme.labelLarge),
              mm.Text(last.senior),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        FilledButton(key: const ValueKey('vivaNext'), onPressed: _next, child: Text(_i + 1 >= st.items.length ? 'Finish and see the checklist' : 'Next question')),
      ],
    ]);
  }

  Widget _resultView(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result!;
    final st = _st;
    return _Page(title: 'Result', kind: 'quiz', children: [
      mm.Text('${r.total} / ${r.max}', key: const ValueKey('vivaTotal'), style: theme.textTheme.displaySmall),
      mm.Text('${(r.fraction * 100).round()}%', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      if (r.weak.isNotEmpty) ...[
        Text('Weak areas (saved to your weak spots, with review cards)', style: theme.textTheme.labelLarge),
        Wrap(spacing: 6, runSpacing: 4, children: [for (final w in r.weak) Chip(visualDensity: VisualDensity.compact, label: mm.Text(w))]),
      ] else
        Text('No weak area this time. Well done.'),
      if (st != null && st.items.isNotEmpty && _turns.isNotEmpty) ...[
        const SectionHeader('Checklist and what a senior would expect'),
        VivaReport(items: st.items, turns: _turns),
      ],
      const SizedBox(height: 12),
      FilledButton(onPressed: () => setState(() => _phase = _VPhase.setup), child: Text('Done')),
    ]);
  }

  Widget _selfView(BuildContext context) {
    final theme = Theme.of(context);
    final i = _got.length;
    final it = _self[i];
    return _Page(title: trp('Question {i} of {n}', {'i': i + 1, 'n': _self.length}), kind: 'quiz', children: [
      LinearProgressIndicator(value: i / _self.length),
      const SizedBox(height: 12),
      Text('Self-viva: no AI, from your own weak topics', style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      mm.Text('${tr('Talk through')}: ${it.title}', style: theme.textTheme.titleLarge),
      Text('Say it aloud: definition, key features, investigations, management, pitfalls.'),
      const SizedBox(height: 12),
      if (!_revealed) FilledButton(key: const ValueKey('selfReveal'), onPressed: () => setState(() => _revealed = true), child: Text('Show key points')) else ...[
        _Card(child: mm.Text(it.keyPoints.isEmpty ? tr('Open the article to check yourself.') : it.keyPoints)),
        TextButton.icon(onPressed: () => openArticle(context, it.packId, it.index), icon: const Icon(Icons.article_outlined), label: Text('Open the article')),
        const SizedBox(height: 8),
        Text('How did you do?', style: theme.textTheme.labelLarge),
        Wrap(spacing: 8, runSpacing: 4, children: [
          FilledButton(key: const ValueKey('selfGood'), onPressed: () => _selfGrade(2), child: Text('I knew it')),
          FilledButton.tonal(key: const ValueKey('selfPart'), onPressed: () => _selfGrade(1), child: Text('Partly')),
          OutlinedButton(key: const ValueKey('selfMiss'), onPressed: () => _selfGrade(0), child: Text('I missed it')),
        ]),
      ],
    ]);
  }
}

/// Questions, checklist hits and "what a senior would expect" (shown at the end of a session and for saved sessions).
class VivaReport extends StatelessWidget {
  final List<VivaItem> items;
  final List<VivaTurn> turns;
  const VivaReport({super.key, required this.items, required this.turns});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < items.length && i < turns.length; i++)
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              mm.Text('${i + 1}. ${items[i].question}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              mm.Text('${turns[i].score} / ${turns[i].max}', style: theme.textTheme.labelLarge),
              if (turns[i].answer.isNotEmpty) mm.Text('${tr('Your answer')}: ${turns[i].answer}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              for (var k = 0; k < items[i].points.length; k++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(k < turns[i].hits.length && turns[i].hits[k] ? Icons.check_circle : Icons.cancel_outlined, size: 18, color: k < turns[i].hits.length && turns[i].hits[k] ? Colors.green : cs.error),
                    const SizedBox(width: 6),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      mm.Text(items[i].points[k].text),
                      if (!items[i].points[k].source.isEmpty) mm.Text(items[i].points[k].source.label, style: theme.textTheme.bodySmall),
                    ])),
                  ]),
                ),
              if (turns[i].senior.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('What a senior would expect', style: theme.textTheme.labelLarge),
                mm.Text(turns[i].senior),
              ],
            ]),
          ),
        ),
    ]);
  }
}

class VivaReportScreen extends StatelessWidget {
  final Map<String, dynamic> session;
  const VivaReportScreen({super.key, required this.session});
  @override
  Widget build(BuildContext context) {
    final st = stationOf(session);
    return _Page(title: 'Saved session', kind: 'quiz', children: [
      mm.Text('${session['total']} / ${session['max']}', style: Theme.of(context).textTheme.headlineMedium),
      mm.Text('${'${session['date']}'.split('T').first} · ${st.specialty}'),
      if (st.vignette.isNotEmpty) ...[const SizedBox(height: 8), _Card(child: mm.Text(st.vignette))],
      const SizedBox(height: 8),
      VivaReport(items: st.items, turns: turnsOf(session)),
    ]);
  }
}

// ================================================================ Socratic teaching

class TeachScreen extends StatefulWidget {
  final String topic;
  const TeachScreen({super.key, this.topic = ''});
  @override
  State<TeachScreen> createState() => _TeachScreenState();
}

class _TeachScreenState extends State<TeachScreen> {
  late final TextEditingController _topic = TextEditingController(text: widget.topic);
  List<String> _qs = const [];
  List<TextEditingController> _ans = const [];
  TeachLesson? _lesson;
  int _step = 0;
  bool _revealed = false;
  bool _busy = false;
  String? _msg;
  final _check = TextEditingController();
  int _known = 0;
  bool _done = false;
  int _cards = -1;

  @override
  void dispose() {
    _topic.dispose();
    _check.dispose();
    for (final c in _ans) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _ask() async {
    if (_topic.text.trim().isEmpty) {
      setState(() => _msg = tr('Choose a topic first.'));
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final (qs, f) = await teachQuestions(_topic.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (qs.isEmpty) {
        _msg = failureText(f);
      } else {
        _qs = qs;
        _ans = [for (final _ in qs) TextEditingController()];
      }
    });
  }

  Future<void> _teach() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final (l, f) = await teachLesson(_topic.text, [for (var i = 0; i < _qs.length; i++) (_qs[i], _ans[i].text.trim())]);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (l == null) {
        _msg = failureText(f);
      } else {
        _lesson = l;
        _step = 0;
        _revealed = false;
        _known = 0;
      }
    });
  }

  Future<void> _nextStep(bool knew) async {
    final l = _lesson!;
    if (knew) _known++;
    if (_step + 1 >= l.steps.length) {
      await saveTeachSession(l, known: _known);
      if (mounted) setState(() => _done = true);
    } else {
      setState(() {
        _step++;
        _revealed = false;
        _check.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = _lesson;
    if (l != null && _done) {
      return _Page(title: 'Teach me', children: [
        _aiBadge(context),
        const SizedBox(height: 8),
        mm.Text(l.topic, style: theme.textTheme.titleLarge),
        mm.Text(trp('{a} of {b} checks answered correctly', {'a': _known, 'b': l.steps.length})),
        if (l.summary.isNotEmpty) ...[const SizedBox(height: 8), _Card(child: mm.Text(l.summary))],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('teachCards'),
          onPressed: _cards >= 0
              ? null
              : () async {
                  final n = await teachCards(l);
                  if (mounted) setState(() => _cards = n);
                },
          icon: const Icon(Icons.style_outlined),
          label: Text(_cards >= 0 ? trp('{n} review cards added', {'n': _cards}) : tr('Make review cards from the checks')),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text('Done')),
      ]);
    }
    if (l != null) {
      final s = l.steps[_step];
      return _Page(title: trp('Step {i} of {n}', {'i': _step + 1, 'n': l.steps.length}), children: [
        LinearProgressIndicator(value: (_step + (_revealed ? 1 : 0)) / l.steps.length),
        const SizedBox(height: 12),
        _aiBadge(context),
        const SizedBox(height: 8),
        if (s.title.isNotEmpty) mm.Text(s.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        mm.Text(s.text),
        const SizedBox(height: 4),
        _SourceLine(s.source),
        const SectionHeader('Check yourself'),
        mm.Text(s.check, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _AnswerField(controller: _check, label: 'Your answer', minLines: 2),
        const SizedBox(height: 8),
        if (!_revealed) FilledButton(key: const ValueKey('teachReveal'), onPressed: () => setState(() => _revealed = true), child: Text('Show the expected answer')) else ...[
          _Card(child: mm.Text(s.answer)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            FilledButton(key: const ValueKey('teachKnew'), onPressed: () => _nextStep(true), child: Text('I had it')),
            OutlinedButton(key: const ValueKey('teachMissed'), onPressed: () => _nextStep(false), child: Text(_step + 1 >= l.steps.length ? 'I missed it, finish' : 'I missed it, next')),
          ]),
        ],
      ]);
    }
    final weak = allWeakTopicNames();
    return _Page(title: 'Teach me', children: [
      AiBuilder(builder: (context, enabled, online) => _Card(child: _AiNote(enabled ? (online ? 'You choose a topic. The AI first asks what you already know, then explains step by step and checks you. Every step shows its source.' : 'You are offline. Open the topic in the Library instead.') : 'AI is off. Search the topic in the Library, or turn AI on in Settings.'))),
      const SizedBox(height: 8),
      TextField(key: const ValueKey('teachTopic'), controller: _topic, decoration: InputDecoration(labelText: tr('Topic, e.g. atrial fibrillation'), border: const OutlineInputBorder())),
      if (weak.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('From my weak spots', style: theme.textTheme.labelLarge),
        Wrap(spacing: 6, runSpacing: 4, children: [for (final w in weak.take(6)) ActionChip(visualDensity: VisualDensity.compact, label: mm.Text(w), onPressed: () => setState(() => _topic.text = w))]),
      ],
      const SizedBox(height: 10),
      if (_qs.isEmpty)
        AiBuilder(builder: (context, enabled, online) => FilledButton.icon(key: const ValueKey('teachStart'), onPressed: enabled && online && !_busy ? _ask : null, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.psychology_alt_outlined), label: Text('Ask me first')))
      else ...[
        const SectionHeader('First, what do you already know?'),
        for (var i = 0; i < _qs.length; i++) ...[
          mm.Text('${i + 1}. ${_qs[i]}'),
          const SizedBox(height: 4),
          _AnswerField(controller: _ans[i], label: 'Your answer', minLines: 2),
          const SizedBox(height: 10),
        ],
        FilledButton.icon(key: const ValueKey('teachGo'), onPressed: _busy ? null : _teach, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.school_outlined), label: Text('Teach me')),
      ],
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: mm.Text(_msg!, style: TextStyle(color: theme.colorScheme.primary))),
    ]);
  }
}

// ================================================================ pre-shift quiz

class PreShiftScreen extends StatefulWidget {
  const PreShiftScreen({super.key});
  @override
  State<PreShiftScreen> createState() => _PreShiftScreenState();
}

class _PreShiftScreenState extends State<PreShiftScreen> {
  PreShift? _set;

  @override
  void initState() {
    super.initState();
    preShiftSet().then((s) {
      if (mounted) setState(() => _set = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _set;
    if (s == null) return _Page(title: 'Pre-shift quiz', kind: 'quiz', children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))]);
    final theme = Theme.of(context);
    return _Page(title: 'Pre-shift quiz', kind: 'quiz', children: [
      _Card(child: _AiNote(s.rotation.isEmpty ? 'No current rotation is set: the questions come from all your saved questions.' : trp('Quick questions for your rotation: {r}.', {'r': s.rotation}))),
      const SizedBox(height: 12),
      if (s.questions.isNotEmpty) ...[
        mm.Text(trp('{n} questions ready', {'n': s.questions.length}), key: const ValueKey('preShiftReady'), style: theme.textTheme.titleMedium),
        if (s.generated) Text('Some questions were just generated from your library.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const ValueKey('preShiftStart'),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AiSessionScreen(pick: AiPick(mode: s.packId == null ? 'all' : 'course', packId: s.packId, count: s.questions.length), questions: s.questions))),
          icon: const Icon(Icons.play_arrow),
          label: Text('Start'),
        ),
      ] else ...[
        Text('No saved AI questions for this rotation yet.', key: const ValueKey('preShiftNone')),
        const SizedBox(height: 6),
        Text('Turn AI on and go online once to build some. Meanwhile the standard quiz works offline.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const ValueKey('preShiftRuleQuiz'),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QuizScreen(packId: s.packId, autoStart: true, count: 5))),
          icon: const Icon(Icons.quiz_outlined),
          label: Text('Use the standard quiz (5 questions)'),
        ),
      ],
    ]);
  }
}

// ================================================================ case of the day

class CaseOfDayScreen extends StatefulWidget {
  const CaseOfDayScreen({super.key});
  @override
  State<CaseOfDayScreen> createState() => _CaseOfDayScreenState();
}

class _CaseOfDayScreenState extends State<CaseOfDayScreen> {
  CaseDay? _case;
  bool _busy = true;
  String? _msg;
  int _i = 0;
  bool _revealed = false;
  final _a = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    final saved = force ? null : savedCaseOfDay();
    if (saved != null) {
      setState(() {
        _case = saved;
        _busy = false;
      });
      return;
    }
    if (!Ai.enabled) {
      setState(() {
        _busy = false;
        _msg = failureText('off');
      });
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final (c, f) = await caseOfTheDay(force: force);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _case = c;
      _i = 0;
      _revealed = false;
      _msg = c == null ? failureText(f) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _case;
    final past = pastCasesOfDay().where((p) => p.date != todayStr()).toList();
    return _Page(title: 'Case of the day', children: [
      if (_busy) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
      else if (c == null) ...[
        if (_msg != null) _Card(child: _AiNote(_msg!)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final h = await topicOfTheDay();
            if (h != null && context.mounted) openArticle(context, h.packId, h.index);
          },
          icon: const Icon(Icons.article_outlined),
          label: Text('Read the topic of the day instead'),
        ),
      ] else ...[
        _aiBadge(context, '${tr('Fictional case')} · ${c.date}'),
        const SizedBox(height: 8),
        mm.Text(c.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        _Card(child: mm.Text(c.vignette)),
        const SizedBox(height: 10),
        if (_i < c.steps.length) ...[
          Text(trp('Step {i} of {n}', {'i': _i + 1, 'n': c.steps.length}), style: theme.textTheme.labelLarge),
          mm.Text(c.steps[_i].ask, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _AnswerField(controller: _a, label: 'Your answer', minLines: 2),
          const SizedBox(height: 8),
          if (!_revealed) FilledButton(key: const ValueKey('codReveal'), onPressed: () => setState(() => _revealed = true), child: Text('Show the answer and the teaching point')) else ...[
            _Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (c.steps[_i].answer.isNotEmpty) mm.Text(c.steps[_i].answer, style: const TextStyle(fontWeight: FontWeight.w700)),
                mm.Text(c.steps[_i].teach),
                const SizedBox(height: 4),
                _SourceLine(c.steps[_i].source),
              ]),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('codNext'),
              onPressed: () => setState(() {
                _i++;
                _revealed = false;
                _a.clear();
              }),
              child: Text(_i + 1 >= c.steps.length ? 'Finish' : 'Next step'),
            ),
          ],
        ] else ...[
          Text('Case finished. Come back tomorrow for a new one.', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () => setState(() => _i = 0), icon: const Icon(Icons.replay), label: Text('Go through it again')),
            AiButton(label: 'Another case', feature: 'case_ofday', onPressed: () => _load(force: true)),
          ]),
        ],
      ],
      if (past.isNotEmpty) ...[
        const SectionHeader('Earlier cases'),
        for (final p in past.take(10))
          AppCard(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: mm.Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: mm.Text(p.date),
              onTap: () => setState(() {
                _case = p;
                _i = 0;
                _revealed = false;
              }),
            ),
          ),
      ],
    ]);
  }
}

// ================================================================ guideline check

/// Opens "Is my reference still current?" for a library article (the article screen / the AI button can call this).
void openGuidelineCheck(BuildContext context, String packId, int index) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => GuidelineCheckScreen(packId: packId, index: index)));
}

class GuidelineCheckScreen extends StatefulWidget {
  final String? packId;
  final int? index;
  const GuidelineCheckScreen({super.key, this.packId, this.index});
  @override
  State<GuidelineCheckScreen> createState() => _GuidelineCheckScreenState();
}

class _GuidelineCheckScreenState extends State<GuidelineCheckScreen> {
  String? _pack;
  int? _index;
  String _title = '';
  final _q = TextEditingController();
  List<LibHit> _hits = const [];
  GCheck? _result;
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    if (widget.packId != null && widget.index != null) _pick(widget.packId!, widget.index!);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _pick(String packId, int index) async {
    final titles = await library.titlesOf(packId);
    if (!mounted) return;
    final t = index >= 0 && index < titles.length ? stripSource(titles[index]) : '';
    final prev = guidelineChecks(packId: packId, title: t);
    setState(() {
      _pack = packId;
      _index = index;
      _title = t;
      _result = prev.isEmpty ? null : prev.first;
      _msg = null;
    });
  }

  Future<void> _search() async {
    if (_q.text.trim().isEmpty || !library.ready) return;
    final h = await library.searchEx(_q.text.trim(), limit: 8, concise: true);
    if (mounted) setState(() => _hits = h);
  }

  Future<void> _run() async {
    if (_pack == null || _index == null) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    final (c, f) = await guidelineCheck(_pack!, _index!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (c != null) {
        _result = c;
      } else {
        _msg = failureText(f);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;
    final recent = [for (final e in recentArticles().take(6)) e];
    return _Page(title: 'Guideline check', children: [
      AiBuilder(builder: (context, enabled, online) => _Card(child: _AiNote(enabled ? (online ? 'The AI looks up current guidelines on the allowed sites (Settings > AI > sources) and compares them with the article. Items without a source are marked "No source found": nothing is claimed without one.' : 'You are offline. Saved checks stay visible. A new check needs internet.') : 'AI is off. Saved checks stay visible. Turn AI on in Settings to check an article.'))),
      const SectionHeader('Article'),
      if (_pack == null) ...[
        TextField(
          key: const ValueKey('gcQuery'),
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(labelText: tr('Search the library'), border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search)),
        ),
        for (final h in _hits)
          ListTile(contentPadding: EdgeInsets.zero, title: mm.Text(stripSource(h.title)), subtitle: mm.Text(library.pack(h.packId)?.title ?? ''), onTap: () => _pick(h.packId, h.index)),
        if (_hits.isEmpty && recent.isNotEmpty) ...[
          Text('Recently read', style: theme.textTheme.labelLarge),
          for (final e in recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: mm.Text(stripSource('${e['t']}')),
              onTap: () async {
                final i = await library.indexOfTitle('${e['p']}', '${e['t']}');
                if (i != null) _pick('${e['p']}', i);
              },
            ),
        ],
      ] else ...[
        _Card(child: Row(children: [
          const Icon(Icons.article_outlined),
          const SizedBox(width: 10),
          Expanded(child: mm.Text(_title, style: theme.textTheme.titleMedium)),
          TextButton(onPressed: () => setState(() {
                _pack = null;
                _result = null;
              }), child: Text('Change')),
        ])),
        const SizedBox(height: 8),
        AiBuilder(builder: (context, enabled, online) => FilledButton.icon(key: const ValueKey('gcRun'), onPressed: enabled && online && !_busy ? _run : null, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.fact_check_outlined), label: Text(r == null ? 'Check now' : 'Check again'))),
      ],
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: mm.Text(_msg!, style: TextStyle(color: theme.colorScheme.primary))),
      if (r != null) ...[
        const SectionHeader('Result'),
        Text('${tr('Checked on')} ${r.date}', key: const ValueKey('gcDate'), style: theme.textTheme.bodySmall),
        if (!r.searched) Text('The live web search did not run for this check: treat the result as unverified.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        const SizedBox(height: 6),
        if (r.rows.isNotEmpty) AiDocView(doc: r.toDoc()),
        const SizedBox(height: 6),
        mm.Text(r.noChange ? tr('No change found in the allowed sources. This does not prove that the article is up to date.') : (r.changed == 1 ? tr('1 item may be out of date: check the guideline itself before changing anything.') : trp('{n} items may be out of date: check the guideline itself before changing anything.', {'n': r.changed})), key: const ValueKey('gcVerdict'), style: theme.textTheme.titleSmall),
        if (r.summary.isNotEmpty) mm.Text(r.summary, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text('AI suggestion: check before use. Your article was not changed.', style: theme.textTheme.bodySmall),
      ],
    ]);
  }
}

// ================================================================ compare guidelines

const List<String> kCompareOrgs = ['ESC', 'AHA/ACC', 'NICE', 'WHO', 'CDC', 'IDSA', 'KDIGO', 'ADA', 'GOLD', 'GINA', 'SIGN', 'ACOG', 'RCOG', 'AAP', 'SCCM', 'ESMO', 'NCCN'];

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});
  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final _topic = TextEditingController();
  String _a = 'ESC';
  String _b = 'AHA/ACC';
  bool _busy = false;
  String? _msg;
  GCompare? _res;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_topic.text.trim().isEmpty) {
      setState(() => _msg = tr('Choose a topic first.'));
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final (c, f) = await compareGuidelines(_topic.text, _a, _b);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _res = c;
      _msg = c == null ? failureText(f) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _res;
    return _Page(title: 'Compare guidelines', children: [
      AiBuilder(builder: (context, enabled, online) => _Card(child: _AiNote(enabled ? (online ? 'The AI finds the current guideline of each organisation on the allowed sites and lists where they differ. Differences are only listed when both sources were found.' : 'You are offline: comparison needs internet.') : 'AI is off. Turn AI on in Settings to compare guidelines.'))),
      const SizedBox(height: 8),
      TextField(key: const ValueKey('cmpTopic'), controller: _topic, decoration: InputDecoration(labelText: tr('Topic, e.g. blood pressure targets'), border: const OutlineInputBorder())),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(isExpanded: true, initialValue: _a, items: [for (final o in kCompareOrgs) DropdownMenuItem(value: o, child: mm.Text(o))], onChanged: (v) => setState(() => _a = v ?? _a))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: mm.Text('vs')),
        Expanded(child: DropdownButtonFormField<String>(isExpanded: true, initialValue: _b, items: [for (final o in kCompareOrgs) DropdownMenuItem(value: o, child: mm.Text(o))], onChanged: (v) => setState(() => _b = v ?? _b))),
      ]),
      const SizedBox(height: 10),
      AiBuilder(builder: (context, enabled, online) => FilledButton.icon(key: const ValueKey('cmpRun'), onPressed: enabled && online && !_busy ? _run : null, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.compare_arrows), label: Text('Compare'))),
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: mm.Text(_msg!, style: TextStyle(color: theme.colorScheme.primary))),
      if (r != null) ...[
        const SectionHeader('Result'),
        if (r.rows.isNotEmpty) AiDocView(doc: r.toDoc()),
        if (r.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: mm.Text(r.summary, key: const ValueKey('cmpSummary'))),
        const SizedBox(height: 4),
        Text('AI suggestion: check the guidelines themselves before acting.', style: theme.textTheme.bodySmall),
      ],
    ]);
  }
}

// ================================================================ written answers

/// Picks a saved question and opens the grading screen.
class WrittenPickerScreen extends StatelessWidget {
  const WrittenPickerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final qs = aiBank().where((q) => q.quote.length >= 25).toList()..sort((a, b) => a.seen.compareTo(b.seen));
    final past = gradings();
    final theme = Theme.of(context);
    return _Page(title: 'Written answers', kind: 'quiz', children: [
      _Card(child: _AiNote('Pick a saved question, write the answer in your own words (type or dictate) and the AI grades it against the cited source: strengths, missing points and wrong statements. Offline you get a keyword check.')),
      const SectionHeader('Saved questions'),
      if (qs.isEmpty) Text('No saved questions yet. Generate some in the AI question bank first.'),
      for (final q in qs.take(15))
        AppCard(
          child: ListTile(
            key: ValueKey('wq_${q.id}'),
            title: mm.Text(q.stem, maxLines: 3, overflow: TextOverflow.ellipsis),
            subtitle: mm.Text(q.shownTitle),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WrittenAnswerScreen(question: q.stem, reference: '${q.quote}\n${q.explanation}\n${q.isShort ? q.answerText : q.correctText}', sourceLabel: q.shownTitle))),
          ),
        ),
      if (past.isNotEmpty) ...[
        const SectionHeader('Graded answers'),
        for (final g in past.take(10))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 16, child: mm.Text('${g['score']}', style: theme.textTheme.labelLarge)),
            title: mm.Text('${g['q']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: mm.Text('${'${g['date']}'.split('T').first} · ${g['src']}'),
          ),
      ],
    ]);
  }
}

/// Written-answer grading: the learner types / dictates an answer, the AI grades it against the cited reference.
class WrittenAnswerScreen extends StatefulWidget {
  final String question;
  final String reference;
  final String sourceLabel;
  const WrittenAnswerScreen({super.key, required this.question, required this.reference, required this.sourceLabel});
  @override
  State<WrittenAnswerScreen> createState() => _WrittenAnswerScreenState();
}

class _WrittenAnswerScreenState extends State<WrittenAnswerScreen> {
  final _a = TextEditingController();
  bool _busy = false;
  Grade? _g;
  String? _msg;

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  Future<void> _grade() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final (g, f) = await gradeWritten(question: widget.question, reference: widget.reference, sourceLabel: widget.sourceLabel, answer: _a.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _g = g;
      _msg = f.isEmpty ? null : failureText(f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = _g;
    return _Page(title: 'Written answer', kind: 'quiz', children: [
      mm.Text(widget.question, style: theme.textTheme.titleMedium),
      const SizedBox(height: 10),
      _AnswerField(controller: _a, label: 'Your answer', minLines: 5, onChanged: () => setState(() {})),
      const SizedBox(height: 10),
      FilledButton.icon(key: const ValueKey('gradeRun'), onPressed: _busy || _a.text.trim().length < 3 ? null : _grade, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.rate_review_outlined), label: Text(Ai.enabled ? 'Grade my answer' : 'Check my answer (local)')),
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: mm.Text(_msg!, style: TextStyle(color: theme.colorScheme.primary))),
      if (g != null) ...[
        const SectionHeader('Result'),
        if (!g.estimated) _aiBadge(context),
        mm.Text('${g.score} / 10', key: const ValueKey('gradeScore'), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        if (g.comment.isNotEmpty) mm.Text(g.comment),
        if (g.strengths.isNotEmpty) ...[const SizedBox(height: 8), Text('Strengths', style: theme.textTheme.labelLarge), for (final s in g.strengths) mm.Text('• $s')],
        if (g.missing.isNotEmpty) ...[const SizedBox(height: 8), Text('Missing points', style: theme.textTheme.labelLarge), for (final s in g.missing) mm.Text('• $s')],
        if (g.wrong.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Wrong statements', style: theme.textTheme.labelLarge),
          for (final w in g.wrong) mm.Text('• “${w.$1}”${w.$2.isEmpty ? '' : ' — ${w.$2}'}'),
        ],
        const SizedBox(height: 8),
        mm.Text('${tr('Source')}: ${widget.sourceLabel}', style: theme.textTheme.bodySmall),
        Text('Saved on this phone. Wrong statements are only those you wrote that contradict the source.', style: theme.textTheme.bodySmall),
      ],
    ]);
  }
}
