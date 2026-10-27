import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'data.dart';
import 'i18n.dart';
import 'motion.dart';
import 'screens_search.dart';
import 'ui.dart';
import 'widgets.dart';

// ================================================================ presentation formats

class _Sec {
  final String title;
  final String text;
  final double share; // part of the total time
  const _Sec(this.title, this.text, this.share);
  bool get missing => text.trim().isEmpty;
}

String _j(List<String> l, [String sep = '\n']) => l.where((e) => e.trim().isNotEmpty).join(sep);

String _vitals(CaseRec c) => [
      ['BP', 'v_bp'], ['HR', 'v_hr'], ['Temp', 'v_temp'], ['RR', 'v_rr'], ['SpO2', 'v_spo2'], ['RBS', 'v_rbs'],
    ].where((e) => c.s(e[1]).trim().isNotEmpty).map((e) => '${e[0]} ${c.s(e[1])}').join(', ');

String _dx(CaseRec c) => c.s('finalDx').trim().isNotEmpty ? c.s('finalDx') : c.s('workingDx');

String _plan(CaseRec c) => c.lst('mgmt').map((m) => '${m['text'] ?? ''}${(m['dose'] ?? '').toString().isEmpty ? '' : ' (${m['dose']})'}').join('; ');

String _who(CaseRec c) => [c.s('ageGroup'), c.s('sex'), c.s('setting')].where((e) => e.isNotEmpty).map(tr).join(' • ');

String _results(CaseRec c) =>
    c.lst('inv').where((i) => (i['result'] ?? '').toString().isNotEmpty).map((i) => '${i['name']}: ${i['result']}').join('; ');

List<_Sec> _sections(String fmt, CaseRec c) {
  switch (fmt) {
    case 'snapps':
      return [
        _Sec('Summarize', _j([_who(c), c.s('cc'), c.s('hpi'), _vitals(c), c.s('examSystemic')]), 0.2),
        _Sec('Narrow the differential', c.s('ddx'), 0.15),
        _Sec('Analyze the differential', c.s('reasoning'), 0.2),
        _Sec('Probe: what I am unsure about', c.s('questions'), 0.15),
        _Sec('Plan', _plan(c), 0.15),
        _Sec('Select a learning point', c.s('learned'), 0.15),
      ];
    case 'long':
      return [
        _Sec('Presenting complaint', c.s('cc'), 0.08),
        _Sec('History of presenting illness', c.s('hpi'), 0.2),
        _Sec('Past history, drugs, allergies', _j([c.s('pmh'), c.s('psh'), c.s('drugs'), c.s('allergies')]), 0.12),
        _Sec('Family and social history', _j([c.s('family'), c.s('social'), c.s('ros')]), 0.1),
        _Sec('Examination', _j([_vitals(c), c.s('examGeneral'), c.s('examSystemic'), c.s('examFocused')]), 0.2),
        _Sec('Investigations', _results(c), 0.1),
        _Sec('Problem list and differential', _j([c.s('problems'), c.s('ddx'), _dx(c)]), 0.1),
        _Sec('Management plan', _plan(c), 0.1),
      ];
    case 'sbar':
      return [
        _Sec('Situation', _j([_who(c), c.s('cc')]), 0.2),
        _Sec('Background', _j([c.s('pmh'), c.s('drugs'), c.s('allergies'), c.s('hpi')]), 0.25),
        _Sec('Assessment', _j([_vitals(c), c.s('examFocused'), _results(c), _dx(c)]), 0.3),
        _Sec('Recommendation', _j([_plan(c), c.s('followUp')]), 0.25),
      ];
    default: // one minute
      return [
        _Sec('Who and what', _j([_who(c), c.s('cc')]), 0.15),
        _Sec('Key history', c.s('hpi').length > 320 ? '${c.s('hpi').substring(0, 320)}…' : c.s('hpi'), 0.25),
        _Sec('Findings', _j([_vitals(c), c.s('examGeneral'), c.s('examSystemic'), _results(c)]), 0.25),
        _Sec('Impression and plan', _j([_dx(c), _plan(c)]), 0.35),
      ];
  }
}

const Map<String, String> _formatNames = {
  'min1': 'One minute',
  'snapps': 'SNAPPS',
  'long': 'Long case',
  'sbar': 'SBAR',
};

class PresentationTrainerScreen extends StatefulWidget {
  final CaseRec? rec;
  const PresentationTrainerScreen({super.key, this.rec});

  @override
  State<PresentationTrainerScreen> createState() => _PresentationTrainerScreenState();
}

class _PresentationTrainerScreenState extends State<PresentationTrainerScreen> {
  CaseRec? _rec;
  String _fmt = 'min1';
  int _total = 60;
  int _elapsed = 0;
  bool _running = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _rec = widget.rec;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setFmt(String f) {
    setState(() {
      _fmt = f;
      _total = f == 'min1' ? 60 : (f == 'sbar' ? 60 : (f == 'snapps' ? 180 : 300));
      _elapsed = 0;
      _running = false;
      _timer?.cancel();
    });
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed == _total) HapticFeedback.heavyImpact();
    });
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _elapsed = 0;
      _running = false;
    });
  }

  String _mmss(int s) {
    final a = s.abs();
    return '${s < 0 ? '-' : ''}${(a ~/ 60).toString().padLeft(2, '0')}:${(a % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rec = _rec;
    final secs = rec == null ? <_Sec>[] : _sections(_fmt, rec);
    final left = _total - _elapsed;
    final over = left < 0;
    // which section is "current" by time
    var acc = 0.0, current = -1;
    for (var i = 0; i < secs.length; i++) {
      acc += secs[i].share;
      if (_elapsed / _total <= acc + 0.0001 && current < 0 && _elapsed > 0) current = i;
    }
    final missing = secs.where((s) => s.missing).length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Presentation trainer'),
        actions: [
          IconButton(
            tooltip: tr('Choose a case'),
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: () async {
              final c = await pickCase(context);
              if (c != null) setState(() => _rec = c);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Wrap(spacing: 8, children: [
            for (final e in _formatNames.entries)
              ChoiceChip(label: Text(e.value), selected: _fmt == e.key, onSelected: (_) => _setFmt(e.key)),
          ]),
          if (_fmt != 'min1' && _fmt != 'sbar')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, children: [
                for (final s in const [180, 300, 420])
                  ChoiceChip(
                    label: Text(trp('{n} min', {'n': s ~/ 60})),
                    selected: _total == s,
                    onSelected: (_) => setState(() {
                      _total = s;
                      _elapsed = 0;
                    }),
                  ),
              ]),
            ),
          const SizedBox(height: 12),
          Center(
            child: AnimatedRing(
              (_elapsed / _total).clamp(0.0, 1.0),
              size: 150,
              color: over ? cs.error : cs.primary,
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_mmss(left), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: over ? cs.error : null)),
                  Text(over ? tr('Overtime') : tr('left'), style: theme.textTheme.labelMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.icon(
              onPressed: rec == null ? null : _toggle,
              icon: Icon(_running ? Icons.pause : Icons.play_arrow),
              label: Text(_running ? 'Pause' : 'Start'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt), label: Text('Reset')),
          ]),
          if (rec == null)
            const EmptyState(kind: EmptyKind.cases, title: 'Choose a case to practise with', message: 'The script is built from what you already recorded.')
          else ...[
            const SizedBox(height: 8),
            if (missing > 0)
              AppCard(
                color: cs.tertiaryContainer,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.info_outline),
                  title: Text(trp('{n} parts are missing from the case', {'n': missing})),
                ),
              ),
            for (var i = 0; i < secs.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: i == current ? cs.primary : cs.outlineVariant, width: i == current ? 2.2 : 1),
                  color: i == current ? cs.primaryContainer.withAlpha(90) : cs.surfaceContainerLow,
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(tr(secs[i].title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                      Text(_mmss((secs[i].share * _total).round()), style: theme.textTheme.labelMedium),
                      if (secs[i].missing) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.error_outline, size: 18, color: cs.error),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    m(secs[i].missing ? tr('Missing in this case') : secs[i].text, secs[i].missing ? cs.error : cs.onSurface, 14, FontWeight.w400, align: TextAlign.start),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: secs.map((s) => '${tr(s.title)}: ${s.text}').join('\n\n'))),
              icon: const Icon(Icons.copy),
              label: Text('Copy script'),
            ),
          ],
          const SizedBox(height: 16),
          Text('Practice aid only. Built from your own record, with no names.', style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
        ],
      ),
    );
  }
}

// ================================================================ communication practice

class _Framework {
  final String id;
  final String title;
  final String hint;
  final List<String> steps;
  const _Framework(this.id, this.title, this.hint, this.steps);
}

const List<_Framework> kFrameworks = [
  _Framework('spikes', 'Breaking bad news (SPIKES)', 'A well known six-step approach for difficult conversations.', [
    'Setting: private place, sit down, no interruptions',
    'Perception: ask what the patient already understands',
    'Invitation: ask how much they want to know',
    'Knowledge: give information in small clear pieces, no jargon',
    'Emotions: notice and respond with empathy',
    'Strategy and summary: agree the next steps and check understanding',
  ]),
  _Framework('heard', 'Upset or angry patient (HEARD)', 'Stay calm, listen, and move toward a solution.', [
    'Hear: let them finish without interrupting',
    'Empathize: name the feeling you see',
    'Apologize: for the experience, where appropriate',
    'Respond: say what you can do now',
    'Diagnose or follow up: find the cause and who will follow up',
  ]),
  _Framework('consent', 'Explaining a procedure and asking for agreement', 'For practising a clear explanation. Not a legal consent form.', [
    'Say what the procedure is, in plain words',
    'Say why it is suggested (benefits)',
    'Say the main risks and what to expect',
    'Offer alternatives, including doing nothing',
    'Check understanding and invite questions',
    'Make clear the decision is theirs',
  ]),
  _Framework('teachback', 'Checking understanding (teach-back)', 'Ask the patient to explain it back in their own words.', [
    'Explain one key point in simple words',
    'Ask them to say it back in their own words',
    'Clarify anything that was missed',
    'Ask again until it is clear',
  ]),
];

class CommunicationPracticeScreen extends StatelessWidget {
  const CommunicationPracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final hist = [...store.listOf('scenarios')]..sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
        return Scaffold(
          appBar: AppBar(title: Text('Communication practice')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              for (var i = 0; i < kFrameworks.length; i++)
                FadeSlideIn(
                  index: i,
                  child: AppCard(
                    child: ListTile(
                      leading: const Icon(Icons.forum_outlined),
                      title: Text(kFrameworks[i].title),
                      subtitle: Text(kFrameworks[i].hint),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _PracticeScreen(fw: kFrameworks[i]))),
                    ),
                  ),
                ),
              AppCard(
                child: ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text('Add my own scenario'),
                  onTap: () async {
                    final res = await showFormSheet(
                      context,
                      title: 'My own scenario',
                      specs: const [
                        FieldSpec('title', 'Situation I want to practise', type: FT.multi),
                        FieldSpec('steps', 'Steps or points to remember', type: FT.multi),
                      ],
                      initial: <String, dynamic>{'id': newId('sc'), 'kind': 'own', 'date': todayStr()},
                    );
                    if (res != null && res['__delete'] != true) await store.upsertExtra('scenarios', res);
                  },
                ),
              ),
              const SectionHeader('My practice'),
              if (hist.isEmpty) Text('No practice yet.', style: theme.textTheme.bodySmall),
              for (final h in hist)
                AppCard(
                  child: ListTile(
                    onTap: () async {
                      final res = await showFormSheet(
                        context,
                        title: 'Practice',
                        specs: const [
                          FieldSpec('title', 'Situation', type: FT.multi),
                          FieldSpec('note', 'Note', type: FT.multi),
                        ],
                        initial: h,
                        canDelete: true,
                      );
                      if (res == null) return;
                      if (res['__delete'] == true) {
                        await store.removeExtra('scenarios', h['id'].toString());
                      } else {
                        await store.upsertExtra('scenarios', res);
                      }
                    },
                    leading: const Icon(Icons.record_voice_over_outlined),
                    title: Text((h['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      prettyDate((h['date'] ?? '').toString()),
                      if ((h['rating'] ?? '').toString().isNotEmpty) '${h['rating']}/5',
                    ].join(' • ')),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PracticeScreen extends StatefulWidget {
  final _Framework fw;
  const _PracticeScreen({required this.fw});

  @override
  State<_PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<_PracticeScreen> {
  late final List<bool> _done = List<bool>.filled(widget.fw.steps.length, false);
  int _rating = 0;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = _done.where((e) => e).length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.fw.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.fw.hint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          AnimatedBar(n / widget.fw.steps.length, height: 6),
          for (var i = 0; i < widget.fw.steps.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _done[i],
              onChanged: (v) => setState(() => _done[i] = v == true),
              title: Text(widget.fw.steps[i]),
            ),
          const SectionHeader('How did it go?'),
          Wrap(spacing: 8, children: [
            for (var r = 1; r <= 5; r++) ChoiceChip(label: Text('$r'), selected: _rating == r, onSelected: (_) => setState(() => _rating = r)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _note, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: tr('What I would do differently'))),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await store.upsertExtra('scenarios', {
                'id': newId('sc'),
                'kind': widget.fw.id,
                'title': widget.fw.title,
                'date': todayStr(),
                'rating': _rating == 0 ? '' : '$_rating',
                'note': _note.text.trim(),
                'steps': '$n/${widget.fw.steps.length}',
              });
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.check),
            label: Text('Save practice'),
          ),
        ],
      ),
    );
  }
}
