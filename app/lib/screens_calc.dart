import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as mm show Text;

import 'ai/ai_context.dart';
import 'score_engine.dart';
import 'calculators.dart';
import 'case_scores.dart';
import 'screens_search.dart' show pickCase;
import 'data.dart';
import 'i18n.dart';
import 'motion.dart';
import 'screens_ai_tools.dart';
import 'widgets.dart';

part 'screens_calc_scores.dart';

class _CalcEntry {
  final String id;
  final String title;
  final IconData icon;
  final Widget body;
  const _CalcEntry(this.id, this.title, this.icon, this.body);
}

const List<_CalcEntry> _kCalcs = [
  _CalcEntry('cl_bmi', 'BMI', Icons.monitor_weight_outlined, _BmiCalc()),
  _CalcEntry('cl_map', 'Mean arterial pressure (MAP)', Icons.favorite_outline, _MapCalc()),
  _CalcEntry('cl_gcs', 'Glasgow Coma Scale (GCS)', Icons.psychology_outlined, _GcsCalc()),
  _CalcEntry('cl_curb', 'CURB-65 (pneumonia severity)', Icons.air, _Checklist(
    items: [
      ['Confusion (new)', 1],
      ['Urea > 7 mmol/L (BUN > 19 mg/dL)', 1],
      ['Respiratory rate ≥ 30/min', 1],
      ['Systolic BP < 90 or diastolic ≤ 60 mmHg', 1],
      ['Age ≥ 65', 1],
    ],
    kind: _CheckKind.curb,
    source: 'Lim WS et al., Thorax 2003',
  )),
  _CalcEntry('cl_wdvt', 'Wells score for DVT', Icons.accessibility_new,
      _Checklist(items: kWellsDvt, kind: _CheckKind.wellsDvt, source: 'Wells PS et al., Lancet 1997 / NEJM 2003')),
  _CalcEntry('cl_wpe', 'Wells score for pulmonary embolism', Icons.bubble_chart_outlined,
      _Checklist(items: kWellsPe, kind: _CheckKind.wellsPe, source: 'Wells PS et al., Thromb Haemost 2000')),
  _CalcEntry('cl_cha', 'CHA2DS2-VASc (stroke risk in AF)', Icons.bolt_outlined,
      _Checklist(items: kChadsVasc, kind: _CheckKind.chads, source: 'Lip GYH et al., Chest 2010')),
  _CalcEntry('cl_ag', 'Anion gap', Icons.science_outlined, _AnionCalc()),
  _CalcEntry('cl_ca', 'Corrected calcium', Icons.science_outlined, _CaCalc()),
  _CalcEntry('cl_qtc', 'QTc (Bazett)', Icons.show_chart, _QtcCalc()),
  _CalcEntry('cl_egfr', 'eGFR (CKD-EPI 2021)', Icons.water_drop_outlined, _EgfrCalc()),
  _CalcEntry('cl_cg', 'Creatinine clearance (Cockcroft-Gault)', Icons.water_drop_outlined, _CgCalc()),
  _CalcEntry('cl_fluid', 'Maintenance fluids in children (4-2-1)', Icons.child_care, _FluidCalc()),
  _CalcEntry('cl_edd', 'Due date and gestational age', Icons.pregnant_woman, _EddCalc()),
];

/// Name of the calculator that is open: the result block reads it for "Interpret my result".
class _CalcName extends InheritedWidget {
  final String name;
  final CaseRec? attachTo; // the case the calculators were opened from
  const _CalcName({required this.name, this.attachTo, required super.child});
  static String of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<_CalcName>()?.name ?? '';
  static CaseRec? caseOf(BuildContext c) => c.dependOnInheritedWidgetOfExactType<_CalcName>()?.attachTo;
  @override
  bool updateShouldNotify(_CalcName old) => old.name != name || old.attachTo != attachTo;
}

/// Clinical calculators that work without internet. Each one shows its formula so it can be checked.
/// Search, starred favourites (kept on this phone) and the ones used last come first.
class CalculatorsScreen extends StatefulWidget {
  /// When opened from a case, results are added to that case without asking which one.
  final CaseRec? attachTo;

  /// Opens with this text already in the search box (from the global search).
  final String initialQuery;
  const CalculatorsScreen({super.key, this.attachTo, this.initialQuery = ''});

  @override
  State<CalculatorsScreen> createState() => _CalculatorsScreenState();
}

class _CalculatorsScreenState extends State<CalculatorsScreen> {
  String _q = '';
  List<_CalcEntry> _scoreEntries = const [];

  List<_CalcEntry> get _calcs => [..._kCalcs, ..._scoreEntries];

  @override
  void initState() {
    super.initState();
    _q = widget.initialQuery;
    _qc.text = widget.initialQuery;
    ScoreRepo.load().then((defs) {
      if (!mounted) return;
      setState(() => _scoreEntries = [for (final d in defs) _CalcEntry('sc_${d.id}', d.title, Icons.fact_check_outlined, ScoreCalc(def: d))]);
    }).catchError((Object _) {});
  }
  final TextEditingController _qc = TextEditingController();

  @override
  void dispose() {
    _qc.dispose();
    super.dispose();
  }

  /// Opens the "Which score fits?" screen; when it returns a calculator id, that calculator is shown open.
  Future<void> _whichScore() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const WhichScoreScreen()));
    if (id == null || !mounted) return;
    final e = _calcs.where((c) => c.id == id);
    if (e.isEmpty) return;
    final m = store.settings['folds'];
    final map = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
    map[id] = true;
    store.settings['folds'] = map;
    store.saveSettings();
    _noteUsed(id);
    setState(() {
      _q = e.first.title;
      _qc.text = e.first.title;
    });
  }

  List<String> _ids(String key) {
    final v = store.settings[key];
    return v is List ? v.map((e) => e.toString()).toList() : <String>[];
  }

  void _toggleFav(String id) {
    final f = _ids('calcFav');
    if (!f.remove(id)) f.add(id);
    store.settings['calcFav'] = f;
    store.saveSettings();
    setState(() {});
  }

  void _noteUsed(String id) {
    final r = _ids('calcRecent')..remove(id);
    r.insert(0, id);
    store.settings['calcRecent'] = r.take(5).toList();
    store.saveSettings();
  }

  Widget _fold(_CalcEntry e, bool fav) => Fold(
        key: ValueKey(e.id),
        id: e.id,
        title: e.title,
        icon: e.icon,
        onToggle: (open) {
          if (open) _noteUsed(e.id);
        },
        trailing: IconButton(
          tooltip: tr(fav ? 'Remove from favorites' : 'Add to favorites'),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber.shade700 : null),
          onPressed: () => _toggleFav(e.id),
        ),
        children: [_CalcName(name: e.title, attachTo: widget.attachTo, child: e.body)],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favs = _ids('calcFav');
    final recent = _ids('calcRecent');
    final q = _q.trim().toLowerCase();
    final byId = {for (final e in _calcs) e.id: e};
    final children = <Widget>[];
    if (q.isNotEmpty) {
      final hits = _calcs.where((e) => e.title.toLowerCase().contains(q) || e.id.toLowerCase().contains(q) || tr(e.title).toLowerCase().contains(q)).toList();
      if (hits.isEmpty) {
        children.add(const EmptyState(kind: EmptyKind.search, title: 'Nothing found'));
      }
      for (final e in hits) {
        children.add(_fold(e, favs.contains(e.id)));
      }
    } else {
      final fv = [for (final id in favs) if (byId[id] != null) byId[id]!];
      final rc = [for (final id in recent) if (byId[id] != null && !favs.contains(id)) byId[id]!];
      final shown = {...fv.map((e) => e.id), ...rc.map((e) => e.id)};
      final rest = _calcs.where((e) => !shown.contains(e.id)).toList();
      if (fv.isNotEmpty) {
        children.add(const SectionHeader('Favorites'));
        for (final e in fv) {
          children.add(_fold(e, true));
        }
      }
      if (rc.isNotEmpty) {
        children.add(const SectionHeader('Recent'));
        for (final e in rc) {
          children.add(_fold(e, false));
        }
      }
      if (fv.isNotEmpty || rc.isNotEmpty) children.add(const SectionHeader('All calculators'));
      for (final e in rest) {
        children.add(_fold(e, false));
      }
    }
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'calc', title: 'Calculators'),
      child: Scaffold(
      appBar: AppBar(title: Text('Calculators')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AiEntry(key: const ValueKey('calc_which_score'), label: tr('Which score fits this case?'), icon: Icons.calculate_outlined, feature: 'ask_score', compact: true, onPressed: _whichScore),
            OutlinedButton.icon(
              key: const ValueKey('calc_drug_check'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const DrugCheckScreen())),
              icon: const Icon(Icons.medication_outlined, size: 18),
              label: Text('Drug check'),
            ),
          ]),
          AiStateBuilder(
            builder: (context, enabled, online) => enabled
                ? const SizedBox.shrink()
                : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: () => openAiSettings(context),
                      icon: const Icon(Icons.power_settings_new, size: 18),
                      label: Text('AI is off. Turn on AI'),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _qc,
            key: const ValueKey('calc_search'),
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Search calculators'),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          Text('Standard published formulas, for learning. Always confirm with your hospital protocol.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------- building blocks

double? _n(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

Widget _field(TextEditingController c, String label, VoidCallback onChanged, {String? hint}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: tr(label), hintText: hint),
        onChanged: (_) => onChanged(),
      ),
    );

class _Result extends StatelessWidget {
  final String value;
  final String meaning;
  final String formula;
  final List<String> items; // what was chosen, kept with the result when it is added to a case
  const _Result(this.value, this.meaning, this.formula, {this.items = const []});

  Future<void> _attach(BuildContext context) async {
    var rec = _CalcName.caseOf(context);
    rec ??= await pickCase(context);
    if (rec == null || !context.mounted) return;
    final name = _CalcName.of(context);
    await attachScore(rec, newScore(name: name, value: value, meaning: meaning, formula: formula, items: items));
    if (context.mounted) snack(context, '${tr('Added to case')} ${rec.s('code')}');
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (value.isNotEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.primaryContainer.withAlpha(110), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Directionality(textDirection: TextDirection.ltr, child: mm.Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
            if (meaning.isNotEmpty) Text(meaning, style: theme.textTheme.bodyMedium),
          ]),
        ),
      const SizedBox(height: 6),
      Directionality(textDirection: TextDirection.ltr, child: Align(alignment: AlignmentDirectional.centerStart, child: mm.Text(formula, style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)))),
      if (value.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('attach_score'),
            onPressed: () => _attach(context),
            icon: const Icon(Icons.playlist_add_check),
            label: Text(_CalcName.caseOf(context) == null ? 'Add to a case' : 'Add to this case'),
          ),
        ),
      // the number is computed above by the app; the AI only explains it with guideline thresholds
      if (value.isNotEmpty) InterpretResult(calc: _CalcName.of(context), result: CalcResult(value, meaning)),
    ]);
  }
}

class _Chips extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onPick;
  const _Chips(this.labels, this.selected, this.onPick);
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 4, children: [
        for (var i = 0; i < labels.length; i++) ChoiceChip(label: mm.Text(labels[i]), selected: selected == i, onSelected: (_) => onPick(i)),
      ]);
}

// ---------------------------------------------------------------- calculators

class _BmiCalc extends StatefulWidget {
  const _BmiCalc();
  @override
  State<_BmiCalc> createState() => _BmiCalcState();
}

class _BmiCalcState extends State<_BmiCalc> {
  final w = TextEditingController(), h = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final kg = _n(w), cm = _n(h);
    final ok = kg != null && cm != null && kg > 0 && cm > 0;
    final v = ok ? bmi(kg, cm) : 0.0;
    return Column(children: [
      _field(w, 'Weight (kg)', () => setState(() {})),
      _field(h, 'Height (cm)', () => setState(() {})),
      _Result(ok ? v.toStringAsFixed(1) : '', ok ? tr(bmiClass(v)) : '', 'BMI = weight (kg) / height (m)²   •   WHO: <18.5, 18.5–24.9, 25–29.9, ≥30'),
    ]);
  }
}

class _MapCalc extends StatefulWidget {
  const _MapCalc();
  @override
  State<_MapCalc> createState() => _MapCalcState();
}

class _MapCalcState extends State<_MapCalc> {
  final s = TextEditingController(), d = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final a = _n(s), b = _n(d);
    final ok = a != null && b != null;
    return Column(children: [
      _field(s, 'Systolic (mmHg)', () => setState(() {})),
      _field(d, 'Diastolic (mmHg)', () => setState(() {})),
      _Result(ok ? '${map(a, b).toStringAsFixed(0)} mmHg' : '', ok ? (map(a, b) < 65 ? tr('Below 65 mmHg: perfusion may be inadequate') : '') : '', 'MAP = (SBP + 2 × DBP) / 3'),
    ]);
  }
}

class _AnionCalc extends StatefulWidget {
  const _AnionCalc();
  @override
  State<_AnionCalc> createState() => _AnionCalcState();
}

class _AnionCalcState extends State<_AnionCalc> {
  final na = TextEditingController(), cl = TextEditingController(), hc = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final a = _n(na), b = _n(cl), c = _n(hc);
    final ok = a != null && b != null && c != null;
    return Column(children: [
      _field(na, 'Sodium (mEq/L)', () => setState(() {})),
      _field(cl, 'Chloride (mEq/L)', () => setState(() {})),
      _field(hc, 'Bicarbonate (mEq/L)', () => setState(() {})),
      _Result(ok ? anionGap(a, b, c).toStringAsFixed(0) : '', ok ? tr('Normal is about 8–12 mEq/L (depends on the lab)') : '', 'Anion gap = Na − (Cl + HCO₃)'),
    ]);
  }
}

class _CaCalc extends StatefulWidget {
  const _CaCalc();
  @override
  State<_CaCalc> createState() => _CaCalcState();
}

class _CaCalcState extends State<_CaCalc> {
  final ca = TextEditingController(), al = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final a = _n(ca), b = _n(al);
    final ok = a != null && b != null;
    return Column(children: [
      _field(ca, 'Total calcium (mg/dL)', () => setState(() {})),
      _field(al, 'Albumin (g/dL)', () => setState(() {})),
      _Result(ok ? '${correctedCalcium(a, b).toStringAsFixed(1)} mg/dL' : '', '', 'Corrected Ca = Ca + 0.8 × (4.0 − albumin)'),
    ]);
  }
}

class _QtcCalc extends StatefulWidget {
  const _QtcCalc();
  @override
  State<_QtcCalc> createState() => _QtcCalcState();
}

class _QtcCalcState extends State<_QtcCalc> {
  final qt = TextEditingController(), hr = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final a = _n(qt), b = _n(hr);
    final ok = a != null && b != null && b > 0;
    return Column(children: [
      _field(qt, 'QT interval (ms)', () => setState(() {})),
      _field(hr, 'Heart rate (bpm)', () => setState(() {})),
      _Result(ok ? '${qtcBazett(a, b).toStringAsFixed(0)} ms' : '', ok ? tr('Often called prolonged above 450 ms (men) / 460 ms (women). Follow your guideline.') : '', 'QTc = QT / √RR   (RR in seconds = 60 / heart rate)'),
    ]);
  }
}

class _EgfrCalc extends StatefulWidget {
  const _EgfrCalc();
  @override
  State<_EgfrCalc> createState() => _EgfrCalcState();
}

class _EgfrCalcState extends State<_EgfrCalc> {
  final cr = TextEditingController(), age = TextEditingController();
  bool female = false;
  @override
  Widget build(BuildContext context) {
    final c = _n(cr), a = _n(age);
    final ok = c != null && a != null && c > 0 && a > 0;
    final v = ok ? egfrCkdEpi2021(c, a.round(), female) : 0.0;
    String stage() {
      if (v >= 90) return 'G1 (≥ 90)';
      if (v >= 60) return 'G2 (60–89)';
      if (v >= 45) return 'G3a (45–59)';
      if (v >= 30) return 'G3b (30–44)';
      if (v >= 15) return 'G4 (15–29)';
      return 'G5 (< 15)';
    }

    return Column(children: [
      _field(cr, 'Serum creatinine (mg/dL)', () => setState(() {})),
      _field(age, 'Age (years)', () => setState(() {})),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text('Female'), value: female, onChanged: (v) => setState(() => female = v)),
      _Result(ok ? '${v.toStringAsFixed(0)} mL/min/1.73 m²' : '', ok ? 'CKD ${stage()}' : '', 'CKD-EPI 2021: 142 × min(Scr/κ,1)^α × max(Scr/κ,1)^−1.200 × 0.9938^age × 1.012 (female).  κ = 0.7 F / 0.9 M;  α = −0.241 F / −0.302 M.  (Inker LA et al., NEJM 2021)'),
    ]);
  }
}

class _CgCalc extends StatefulWidget {
  const _CgCalc();
  @override
  State<_CgCalc> createState() => _CgCalcState();
}

class _CgCalcState extends State<_CgCalc> {
  final age = TextEditingController(), kg = TextEditingController(), cr = TextEditingController();
  bool female = false;
  @override
  Widget build(BuildContext context) {
    final a = _n(age), w = _n(kg), c = _n(cr);
    final ok = a != null && w != null && c != null && c > 0;
    return Column(children: [
      _field(age, 'Age (years)', () => setState(() {})),
      _field(kg, 'Weight (kg)', () => setState(() {})),
      _field(cr, 'Serum creatinine (mg/dL)', () => setState(() {})),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text('Female'), value: female, onChanged: (v) => setState(() => female = v)),
      _Result(ok ? '${cockcroftGault(a.round(), w, c, female).toStringAsFixed(0)} mL/min' : '', '', 'CrCl = (140 − age) × weight / (72 × Scr), × 0.85 if female'),
    ]);
  }
}

class _FluidCalc extends StatefulWidget {
  const _FluidCalc();
  @override
  State<_FluidCalc> createState() => _FluidCalcState();
}

class _FluidCalcState extends State<_FluidCalc> {
  final kg = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final w = _n(kg);
    final ok = w != null && w > 0;
    return Column(children: [
      _field(kg, 'Weight (kg)', () => setState(() {})),
      _Result(ok ? '${maintenanceFluid421(w).toStringAsFixed(0)} mL/hour' : '', ok ? '${(maintenanceFluid421(w) * 24).toStringAsFixed(0)} mL / 24h' : '', '4 mL/kg/h for the first 10 kg, + 2 mL/kg/h for the next 10 kg, + 1 mL/kg/h for each kg above 20'),
    ]);
  }
}

class _EddCalc extends StatefulWidget {
  const _EddCalc();
  @override
  State<_EddCalc> createState() => _EddCalcState();
}

class _EddCalcState extends State<_EddCalc> {
  DateTime? lmp;
  @override
  Widget build(BuildContext context) {
    final l = lmp;
    final ga = l == null ? null : gestationalAge(l, DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text(l == null ? tr('Pick the first day of the last period') : fmtDate(l)),
        onPressed: () async {
          final d = await showDatePicker(context: context, initialDate: l ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 320)), lastDate: DateTime.now());
          if (d != null) setState(() => lmp = d);
        },
      ),
      const SizedBox(height: 10),
      _Result(l == null ? '' : 'EDD ${fmtDate(eddFromLmp(l))}', ga == null ? '' : '${ga.$1}w + ${ga.$2}d', "Naegele's rule: EDD = LMP + 280 days (regular 28-day cycle)"),
    ]);
  }
}

class _GcsCalc extends StatefulWidget {
  const _GcsCalc();
  @override
  State<_GcsCalc> createState() => _GcsCalcState();
}

class _GcsCalcState extends State<_GcsCalc> {
  int e = 3, v = 4, mo = 5; // selected index in the lists below (score = 4 - index etc.)
  static const eye = ['4 Spontaneous', '3 To voice', '2 To pain', '1 None'];
  static const verbal = ['5 Oriented', '4 Confused', '3 Words', '2 Sounds', '1 None'];
  static const motor = ['6 Obeys', '5 Localizes', '4 Withdraws', '3 Flexion', '2 Extension', '1 None'];
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = gcs(4 - e, 5 - v, 6 - mo);
    Widget group(String title, List<String> l, int sel, ValueChanged<int> f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: Text(title, style: theme.textTheme.labelLarge)),
          _Chips(l, sel, (i) => setState(() => f(i))),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      group('Eye opening', eye, e, (i) => e = i),
      group('Verbal response', verbal, v, (i) => v = i),
      group('Motor response', motor, mo, (i) => mo = i),
      const SizedBox(height: 10),
      _Result('GCS $total', tr(gcsClass(total)), 'E${4 - e} V${5 - v} M${6 - mo}   •   Teasdale G, Jennett B, Lancet 1974',
          items: ['Eye opening: ${eye[e]}', 'Verbal response: ${verbal[v]}', 'Motor response: ${motor[mo]}']),
    ]);
  }
}

enum _CheckKind { curb, wellsDvt, wellsPe, chads }

class _Checklist extends StatefulWidget {
  final List<List<Object>> items;
  final _CheckKind kind;
  final String source;
  const _Checklist({required this.items, required this.kind, required this.source});
  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  final Set<int> on = {};
  @override
  Widget build(BuildContext context) {
    final score = sumChecked(widget.items, on);
    String shown = score == score.roundToDouble() ? score.toStringAsFixed(0) : score.toStringAsFixed(1);
    String meaning;
    switch (widget.kind) {
      case _CheckKind.curb:
        meaning = tr(curb65Risk(score.round()));
        break;
      case _CheckKind.wellsDvt:
        meaning = score >= 2 ? tr('DVT likely (≥ 2): imaging is advised') : tr('DVT unlikely (< 2): D-dimer can help rule it out');
        break;
      case _CheckKind.wellsPe:
        meaning = score > 4 ? tr('PE likely (> 4): imaging is advised') : tr('PE unlikely (≤ 4): D-dimer can help rule it out');
        break;
      case _CheckKind.chads:
        meaning = score >= 2 ? tr('Higher risk: anticoagulation is usually recommended. Follow your guideline.') : tr('Low to intermediate risk. Follow your guideline.');
        break;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < widget.items.length; i++)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Directionality(textDirection: TextDirection.ltr, child: mm.Text('${widget.items[i][0]}   (${(widget.items[i][1] as num) > 0 ? '+' : ''}${widget.items[i][1]})')),
          value: on.contains(i),
          onChanged: (v) => setState(() => v == true ? on.add(i) : on.remove(i)),
        ),
      const SizedBox(height: 6),
      _Result(shown, meaning, widget.source, items: [
        for (final i in on.toList()..sort()) '${widget.items[i][0]} (${(widget.items[i][1] as num) > 0 ? '+' : ''}${widget.items[i][1]})'
      ]),
    ]);
  }
}


/// Titles of every calculator and score: for the global search.
Future<List<String>> calculatorTitles() async {
  final titles = [for (final c in _kCalcs) c.title];
  try {
    titles.addAll([for (final d in await ScoreRepo.load()) d.title]);
  } catch (_) {}
  return titles;
}
