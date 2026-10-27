import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'data.dart';
import 'focus.dart' show stageOfRole;
import 'i18n.dart';
import 'motion.dart';
import 'screens_learn.dart' show kProcedureNames;
import 'screens_notebooks.dart' show kAchievementKinds;
import 'ui.dart';
import 'widgets.dart';

// ================================================================ supervisor sign-off
//
// A sign-off is recorded BY THE USER on a procedure or a case: who supervised,
// their role, the level of supervision and the date, plus a "signed" state the user
// sets once the supervisor has signed (on paper or verbally). No signature image and
// no patient information is stored. Keys are stored flat on the entry:
//   supName, supRole, supLevel, supDate, supSigned ('1' when signed), supInit

const List<String> kSupLevels = [
  'Observed', 'Assisted', 'Performed under supervision', 'Performed independently',
];
const List<String> kSupRoles = ['Consultant', 'Specialist', 'Senior resident', 'Other'];
const List<String> kSignKeys = ['supName', 'supRole', 'supLevel', 'supDate', 'supSigned', 'supInit'];

bool isSigned(J d) => (d['supSigned'] ?? '').toString().isNotEmpty;

bool hasSignOff(J d) => kSignKeys.any((k) => (d[k] ?? '').toString().trim().isNotEmpty);

String _sdate(J d) {
  final s = (d['supDate'] ?? '').toString();
  return s.isNotEmpty ? s : (d['date'] ?? '').toString();
}

/// "Signed by supervisor on 12 Oct 2026" (+ name, initials) or "Not signed yet".
String signedText(J d) {
  if (!isSigned(d)) return tr('Not signed yet');
  final who = (d['supName'] ?? '').toString().trim();
  final ini = (d['supInit'] ?? '').toString().trim();
  final base = trp('Signed by supervisor on {date}', {'date': prettyDate(_sdate(d))});
  return [base, if (who.isNotEmpty) who, if (ini.isNotEmpty) '($ini)'].join(' • ');
}

/// Short text for a table cell in an exported logbook. Unsigned entries get a blank line
/// so they can be signed by hand on the printed page.
String signCell(J d) {
  if (!isSigned(d)) {
    final who = (d['supName'] ?? '').toString().trim();
    return who.isEmpty ? '________' : '$who\n________';
  }
  final who = (d['supName'] ?? '').toString().trim();
  final ini = (d['supInit'] ?? '').toString().trim();
  return [if (who.isNotEmpty) who, '${_sdate(d)}${ini.isEmpty ? '' : '  $ini'}'].join('\n');
}

Future<bool> editSignOff(BuildContext context, J entry,
    {required String title, required Future<void> Function() save}) async {
  final res = await showModalBottomSheet<J>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _SignOffSheet(initial: entry, title: title),
  );
  if (res == null) return false;
  for (final k in kSignKeys) {
    if (res['__clear'] == true) {
      entry.remove(k);
    } else {
      entry[k] = res[k] ?? '';
    }
  }
  await save();
  return true;
}

Future<bool> editCaseSignOff(BuildContext context, CaseRec rec) =>
    editSignOff(context, rec.d, title: '${tr('Supervisor sign-off')} • ${rec.s('code')}', save: () => store.saveCase(rec));

Future<bool> editProcedureSignOff(BuildContext context, J p) => editSignOff(context, p,
    title: '${tr('Supervisor sign-off')} • ${tr((p['name'] ?? '').toString())}',
    save: () => store.upsert(store.procedures, 'procedures.json', p));

class _SignOffSheet extends StatefulWidget {
  final J initial;
  final String title;
  const _SignOffSheet({required this.initial, required this.title});

  @override
  State<_SignOffSheet> createState() => _SignOffSheetState();
}

class _SignOffSheetState extends State<_SignOffSheet> {
  late final TextEditingController _name, _role, _init;
  String _level = '';
  String _date = '';
  bool _signed = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _name = TextEditingController(text: (d['supName'] ?? '').toString());
    _role = TextEditingController(text: (d['supRole'] ?? '').toString());
    _init = TextEditingController(text: (d['supInit'] ?? '').toString());
    _level = (d['supLevel'] ?? '').toString();
    if (_level.isEmpty && kSupLevels.contains((d['role'] ?? '').toString())) _level = (d['role']).toString();
    _date = (d['supDate'] ?? '').toString();
    _signed = isSigned(d);
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _init.dispose();
    super.dispose();
  }

  J _result({bool clear = false}) => clear
      ? {'__clear': true}
      : {
          'supName': _name.text.trim(),
          'supRole': _role.text.trim(),
          'supLevel': _level,
          'supDate': _signed && _date.isEmpty ? todayStr() : _date,
          'supSigned': _signed ? '1' : '',
          'supInit': _init.text.trim(),
        };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            m.Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('You record this yourself. No signature image and no patient details are stored.',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Supervisor name')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _role,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: tr('Supervisor role')),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, children: [
                for (final r in kSupRoles)
                  ActionChip(
                    label: Text(r),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _role.text = tr(r)),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Text('Level of supervision', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final l in kSupLevels)
                ChoiceChip(
                  label: Text(l),
                  selected: _level == l,
                  onSelected: (_) => setState(() => _level = _level == l ? '' : l),
                ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: m.Text('${tr('Date')}: ${_date.isEmpty ? '—' : prettyDate(_date)}', style: theme.textTheme.bodyLarge),
              ),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: parseDate(_date) ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => _date = fmtDate(d));
                },
                child: const Text('Pick date'),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Signed by my supervisor'),
              subtitle: const Text('Turn on once your supervisor has signed or confirmed this entry.'),
              value: _signed,
              onChanged: (v) => setState(() {
                _signed = v;
                if (v && _date.isEmpty) _date = todayStr();
              }),
            ),
            if (_signed)
              TextField(
                controller: _init,
                maxLength: 6,
                decoration: InputDecoration(labelText: tr('Typed initials (optional)')),
              ),
            const SizedBox(height: 8),
            Row(children: [
              if (hasSignOff(widget.initial))
                TextButton(
                  onPressed: () => Navigator.pop(context, _result(clear: true)),
                  child: const Text('Clear'),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context, _result()), child: const Text('Save')),
            ]),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- sign-off list (tab + screen)

bool _isDemo(J d) => d['demo'] == true || (d['id'] ?? '').toString().startsWith('demo_');

class SignCounts {
  final int signed, total;
  const SignCounts(this.signed, this.total);
}

/// Signed / total over procedures and (optionally) cases. [rotationId] limits to one rotation.
SignCounts signCounts({String? rotationId, bool cases = true, bool procs = true}) {
  var s = 0, t = 0;
  if (procs) {
    for (final p in store.procedures) {
      if (_isDemo(p)) continue;
      if (rotationId != null && p['rotationId'] != rotationId) continue;
      t++;
      if (isSigned(p)) s++;
    }
  }
  if (cases) {
    for (final c in store.cases.values) {
      if (_isDemo(c.d)) continue;
      if (rotationId != null && c.s('rotationId') != rotationId) continue;
      t++;
      if (isSigned(c.d)) s++;
    }
  }
  return SignCounts(s, t);
}

class SignOffTab extends StatefulWidget {
  const SignOffTab({super.key});

  @override
  State<SignOffTab> createState() => _SignOffTabState();
}

class _SignOffTabState extends State<SignOffTab> {
  String _filter = 'unsigned'; // all | unsigned | signed
  bool _procs = true;
  bool _cases = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final rows = <_SignRow>[];
        if (_procs) {
          for (final p in store.procedures) {
            if (_isDemo(p)) continue;
            rows.add(_SignRow(p, null));
          }
        }
        if (_cases) {
          for (final c in store.cases.values) {
            if (_isDemo(c.d)) continue;
            rows.add(_SignRow(c.d, c));
          }
        }
        final all = signCounts(cases: _cases, procs: _procs);
        final shown = rows.where((r) {
          if (_filter == 'unsigned') return !isSigned(r.d);
          if (_filter == 'signed') return isSigned(r.d);
          return true;
        }).toList()
          ..sort((a, b) => (b.d['date'] ?? '').toString().compareTo((a.d['date'] ?? '').toString()));
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final f in const ['unsigned', 'signed', 'all'])
                ChoiceChip(
                  label: Text(f == 'unsigned' ? 'Not signed yet' : f == 'signed' ? 'Signed' : 'All'),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              FilterChip(
                label: Text('Procedures'),
                selected: _procs,
                onSelected: (v) => setState(() => _procs = v),
              ),
              FilterChip(
                label: Text('Cases'),
                selected: _cases,
                onSelected: (v) => setState(() => _cases = v),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: m.Text(trp('{a} of {b} signed by a supervisor', {'a': all.signed, 'b': all.total}),
                  style: theme.textTheme.labelLarge?.copyWith(color: cs.primary)),
            ),
            if (shown.isEmpty)
              EmptyState(
                kind: EmptyKind.learn,
                title: _filter == 'unsigned' ? 'Nothing waiting for a signature' : 'Nothing here yet',
                message: 'Open a procedure or a case here to record your supervisor and the level of supervision.',
              ),
            for (var i = 0; i < shown.length && i < 200; i++)
              AppCard(
                child: ListTile(
                  onTap: () => shown[i].edit(context),
                  leading: Icon(isSigned(shown[i].d) ? Icons.verified_outlined : Icons.pending_outlined,
                      color: isSigned(shown[i].d) ? Colors.green : cs.outline),
                  title: m.Text(shown[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: m.Text([
                    prettyDate((shown[i].d['date'] ?? '').toString()),
                    tr(shown[i].isCase ? 'Case' : 'Procedure'),
                    if ((shown[i].d['supLevel'] ?? '').toString().isNotEmpty) tr(shown[i].d['supLevel'].toString()),
                    signedText(shown[i].d),
                  ].where((e) => e.isNotEmpty).join(' • ')),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                ),
              ),
            const SizedBox(height: 8),
            Text('A personal record kept by you. It does not replace your program\'s official sign-off.',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
          ],
        );
      },
    );
  }
}

class _SignRow {
  final J d;
  final CaseRec? c;
  _SignRow(this.d, this.c);
  bool get isCase => c != null;
  String get title => isCase ? '${c!.s('code')}  ${c!.title}' : tr((d['name'] ?? '').toString());
  Future<void> edit(BuildContext context) =>
      isCase ? editCaseSignOff(context, c!) : editProcedureSignOff(context, d);
}

class SignOffScreen extends StatelessWidget {
  const SignOffScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Supervisor sign-off')),
        body: const SignOffTab(),
      );
}

// ================================================================ structured rotation targets
//
// Stored on the rotation as a list under `targets`. Each target is
//   {id, kind, name?, target?, tPerf?, tAssist?}
// kind: Cases | Procedure | Achievements | Notes | Reflections | Signed entries.
// Progress is computed live from what the user has logged.

const List<String> kTargetKinds = ['Cases', 'Procedure', 'Achievements', 'Notes', 'Reflections', 'Signed entries'];

/// Examples only. The user edits them to match their own program.
const List<Map<String, dynamic>> kTargetTemplates = [
  {
    'title': 'Cases and presentations',
    'targets': [
      {'kind': 'Cases', 'target': 20},
      {'kind': 'Achievements', 'name': 'Presentation', 'target': 3},
      {'kind': 'Reflections', 'target': 2},
    ],
  },
  {
    'title': 'Procedures',
    'targets': [
      {'kind': 'Procedure', 'name': 'IV cannulation', 'tPerf': 5, 'tAssist': 5},
      {'kind': 'Procedure', 'name': 'ABG', 'tPerf': 5, 'tAssist': 0},
      {'kind': 'Signed entries', 'target': 5},
    ],
  },
];

List<J> targetsOf(J rot) {
  final v = rot['targets'];
  if (v is List<J>) return v;
  final out = <J>[];
  if (v is List) {
    for (final e in v) {
      out.add(Map<String, dynamic>.from(e as Map));
    }
  }
  rot['targets'] = out;
  return out;
}

int _int(Object? v) => int.tryParse((v ?? '').toString().trim()) ?? 0;

class GoalProgress {
  final J goal;
  final int done;
  final int target;
  final String detail;
  const GoalProgress(this.goal, this.done, this.target, this.detail);
  double get frac => target <= 0 ? 0.0 : (done / target).clamp(0.0, 1.0);
  bool get met => target > 0 && done >= target;
  String get kind => (goal['kind'] ?? '').toString();
  String get label {
    final n = (goal['name'] ?? '').toString().trim();
    switch (kind) {
      case 'Procedure':
        return n.isEmpty ? tr('Procedure') : tr(n);
      case 'Achievements':
        return n.isEmpty ? tr('Achievements') : tr(n);
      default:
        return tr(kind);
    }
  }
}

bool _inRotation(J rot, String date) {
  if (date.isEmpty) return false;
  final s = (rot['start'] ?? '').toString();
  final e = (rot['end'] ?? '').toString();
  if (s.isNotEmpty && date.compareTo(s) < 0) return false;
  if (e.isNotEmpty && date.compareTo(e) > 0) return false;
  return true;
}

GoalProgress progressFor(J rot, J g) {
  final id = rot['id'].toString();
  final kind = (g['kind'] ?? '').toString();
  final name = (g['name'] ?? '').toString().trim();
  switch (kind) {
    case 'Cases':
      return GoalProgress(g, store.casesOfRotation(id).length, _int(g['target']), '');
    case 'Procedure':
      var perf = 0, assist = 0;
      for (final p in store.procedures) {
        if (p['rotationId'] != id || (p['name'] ?? '').toString() != name) continue;
        final st = stageOfRole((p['role'] ?? '').toString());
        if (st >= 3) perf++;
        if (st == 2) assist++;
      }
      final tp = _int(g['tPerf']), ta = _int(g['tAssist']);
      final done = (perf < tp ? perf : tp) + (assist < ta ? assist : ta);
      final detail = [
        if (tp > 0) trp('Performed {a} / {b}', {'a': perf, 'b': tp}),
        if (ta > 0) trp('Assisted {a} / {b}', {'a': assist, 'b': ta}),
      ].join(' • ');
      return GoalProgress(g, done, tp + ta, detail);
    case 'Achievements':
      final n = store.listOf('achievements').where((a) =>
          _inRotation(rot, (a['date'] ?? '').toString()) && (name.isEmpty || a['kind'] == name)).length;
      return GoalProgress(g, n, _int(g['target']), '');
    case 'Notes':
      return GoalProgress(g, store.notes.where((n) => _inRotation(rot, (n['date'] ?? '').toString())).length, _int(g['target']), '');
    case 'Reflections':
      return GoalProgress(
          g, store.listOf('reflections').where((n) => _inRotation(rot, (n['date'] ?? '').toString())).length, _int(g['target']), '');
    case 'Signed entries':
      final c = signCounts(rotationId: id);
      return GoalProgress(g, c.signed, _int(g['target']), c.total == 0 ? '' : trp('{a} of {b} signed by a supervisor', {'a': c.signed, 'b': c.total}));
  }
  return GoalProgress(g, 0, _int(g['target']), '');
}

enum Pace { none, done, onTrack, behind }

int? daysLeftOf(J rot, [DateTime? now]) {
  final e = parseDate((rot['end'] ?? '').toString());
  if (e == null) return null;
  final n = now ?? DateTime.now();
  return DateTime(e.year, e.month, e.day).difference(DateTime(n.year, n.month, n.day)).inDays;
}

/// Done when reached; otherwise compares the share of the target reached with the share of
/// the rotation that has passed (10 points of slack). Without dates there is no hint.
Pace paceOf(J rot, GoalProgress gp, [DateTime? now]) {
  if (gp.met) return Pace.done;
  final s = parseDate((rot['start'] ?? '').toString());
  final e = parseDate((rot['end'] ?? '').toString());
  if (s == null || e == null || gp.target <= 0) return Pace.none;
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final start = DateTime(s.year, s.month, s.day), end = DateTime(e.year, e.month, e.day);
  if (today.isAfter(end)) return Pace.behind;
  final total = end.difference(start).inDays;
  if (total <= 0) return Pace.onTrack;
  final elapsed = (today.difference(start).inDays / total).clamp(0.0, 1.0);
  return gp.frac + 0.1 >= elapsed ? Pace.onTrack : Pace.behind;
}

Future<void> _saveRot(J rot) => store.upsert(store.rotations, 'rotations.json', rot);

Future<void> applyTargetTemplate(J rot, int index) async {
  final l = targetsOf(rot);
  final t = kTargetTemplates[index]['targets'] as List;
  for (final e in t) {
    l.add({...Map<String, dynamic>.from(e as Map), 'id': newId('tg')});
  }
  await _saveRot(rot);
}

Future<void> editTarget(BuildContext context, J rot, [J? g]) async {
  final res = await showModalBottomSheet<J>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _TargetSheet(initial: g),
  );
  if (res == null) return;
  final l = targetsOf(rot);
  if (res['__delete'] == true) {
    l.removeWhere((e) => e['id'] == g!['id']);
  } else {
    final i = l.indexWhere((e) => e['id'] == res['id']);
    if (i >= 0) {
      l[i] = res;
    } else {
      l.add(res);
    }
  }
  await _saveRot(rot);
}

class _TargetSheet extends StatefulWidget {
  final J? initial;
  const _TargetSheet({this.initial});

  @override
  State<_TargetSheet> createState() => _TargetSheetState();
}

class _TargetSheetState extends State<_TargetSheet> {
  String _kind = 'Cases';
  late final TextEditingController _name, _target, _perf, _assist;

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    _kind = (g?['kind'] ?? 'Cases').toString();
    _name = TextEditingController(text: (g?['name'] ?? '').toString());
    _target = TextEditingController(text: g == null ? '10' : (g['target'] ?? '').toString());
    _perf = TextEditingController(text: g == null ? '5' : (g['tPerf'] ?? '').toString());
    _assist = TextEditingController(text: g == null ? '5' : (g['tAssist'] ?? '').toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _perf.dispose();
    _assist.dispose();
    super.dispose();
  }

  J _result() {
    final proc = _kind == 'Procedure';
    return {
      'id': widget.initial?['id'] ?? newId('tg'),
      'kind': _kind,
      if (proc || _kind == 'Achievements') 'name': _name.text.trim(),
      if (proc) 'tPerf': _int(_perf.text),
      if (proc) 'tAssist': _int(_assist.text),
      if (!proc) 'target': _int(_target.text),
    };
  }

  Widget _num(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: tr(label)),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proc = _kind == 'Procedure';
    final suggestions = proc ? kProcedureNames : (_kind == 'Achievements' ? kAchievementKinds : const <String>[]);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            m.Text(tr(widget.initial == null ? 'New target' : 'Edit target'),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final k in kTargetKinds)
                ChoiceChip(label: Text(k), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
            ]),
            const SizedBox(height: 10),
            if (proc || _kind == 'Achievements') ...[
              TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: tr(proc ? 'Procedure' : 'Type (empty = any)')),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Wrap(spacing: 6, children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(s),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _name.text = s),
                    ),
                ]),
              ),
            ],
            if (proc) ...[
              Row(children: [
                Expanded(child: _num(_perf, 'Performed at least')),
                const SizedBox(width: 10),
                Expanded(child: _num(_assist, 'Assisted at least')),
              ]),
              const SizedBox(height: 4),
              Text('Performed = under supervision or independently. Assisted = role "Assisted".',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ] else
              _num(_target, 'Target number'),
            const SizedBox(height: 12),
            Row(children: [
              if (widget.initial != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, {'__delete': true}),
                  child: const Text('Delete'),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context, _result()), child: const Text('Save')),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Targets block of the rotation screen: progress bars, on track / behind hint, editing.
class RotationTargets extends StatelessWidget {
  final J rot;
  const RotationTargets({super.key, required this.rot});

  Future<void> _templates(BuildContext context) async {
    final i = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Example targets — edit to match your program',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('These are only examples, not official requirements. You can change every number after adding them.',
                style: Theme.of(ctx).textTheme.bodySmall),
          ),
          for (var k = 0; k < kTargetTemplates.length; k++)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(kTargetTemplates[k]['title'] as String),
              subtitle: m.Text([
                for (final t in kTargetTemplates[k]['targets'] as List) _templateLine(t as Map),
              ].join(' • ')),
              onTap: () => Navigator.pop(ctx, k),
            ),
        ])),
      ),
    );
    if (i != null) await applyTargetTemplate(rot, i);
  }

  static String _templateLine(Map t) {
    final kind = t['kind'].toString();
    final name = (t['name'] ?? '').toString();
    final label = name.isEmpty ? tr(kind) : tr(name);
    if (kind == 'Procedure') {
      final p = _int(t['tPerf']), a = _int(t['tAssist']);
      if (a == 0) return trp('{name} ≥ {p} performed', {'name': label, 'p': p});
      return trp('{name} ≥ {p} performed / ≥ {a} assisted', {'name': label, 'p': p, 'a': a});
    }
    return '$label ≥ ${t['target']}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final goals = [for (final g in targetsOf(rot)) progressFor(rot, g)];
    final left = daysLeftOf(rot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Targets',
          trailing: TextButton.icon(
            onPressed: () => editTarget(context, rot),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ),
        if (goals.isEmpty) ...[
          Text('Set numbers to aim for in this rotation. Progress is counted from what you log.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () => _templates(context),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Use example targets'),
            ),
          ),
        ] else ...[
          if (left != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: m.Text(
                  left < 0 ? tr('This rotation has ended') : left == 0 ? tr('Last day of this rotation') : trp('{n} days left', {'n': left}),
                  style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            ),
          for (final gp in goals) _TargetCard(rot: rot, gp: gp),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _templates(context),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Use example targets'),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text('Targets are your own. They are not official requirements.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
      ],
    );
  }
}

class _TargetCard extends StatelessWidget {
  final J rot;
  final GoalProgress gp;
  const _TargetCard({required this.rot, required this.gp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pace = paceOf(rot, gp);
    final (String, Color)? chip = switch (pace) {
      Pace.done => (tr('Done'), Colors.green),
      Pace.onTrack => (tr('On track'), Colors.teal),
      Pace.behind => (tr('Behind'), Colors.orange.shade800),
      Pace.none => null,
    };
    return AppCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => editTarget(context, rot, gp.goal),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: m.Text(gp.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (chip != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: chip.$2.withAlpha(36),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: chip.$2.withAlpha(120)),
                  ),
                  child: m.Text(chip.$1, style: theme.textTheme.labelSmall?.copyWith(color: chip.$2, fontWeight: FontWeight.w800)),
                ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              m.Text('${gp.done} / ${gp.target}', style: theme.textTheme.labelLarge),
              const SizedBox(width: 10),
              Expanded(child: AnimatedBar(gp.frac, height: 8, color: gp.met ? Colors.green : cs.primary)),
            ]),
            if (gp.detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: m.Text(gp.detail, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
          ]),
        ),
      ),
    );
  }
}
