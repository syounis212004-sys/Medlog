import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'data.dart';
import 'dose_calc.dart';
import 'dose_context.dart';
import 'dosing.dart';
import 'formulary.dart';
import 'i18n.dart';
import 'ui.dart';
import 'widgets.dart';

bool _hasArabic(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

/// English medical text keeps its own direction; a string that also has Arabic words follows the app direction.
Widget _en(String s, {TextStyle? style, int? maxLines}) {
  final t = m.Text(s, style: style, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
  return _hasArabic(s) ? t : Directionality(textDirection: TextDirection.ltr, child: t);
}

bool _isFav(String key) => (store.settings['doseFav'] is List) && (store.settings['doseFav'] as List).contains(key);

Future<void> _toggleFav(String key) async {
  final l = [if (store.settings['doseFav'] is List) ...(store.settings['doseFav'] as List).map((e) => '$e')];
  l.contains(key) ? l.remove(key) : l.add(key);
  store.settings['doseFav'] = l;
  await store.saveSettings();
}

/// Doses, durations and the notes around them, from the user's own files (kept on this phone).
class DosingScreen extends StatefulWidget {
  /// The patient of the case the screen was opened from (weight, creatinine): used by the calculators.
  final DoseContext? patient;
  const DosingScreen({super.key, this.patient});
  @override
  State<DosingScreen> createState() => _DosingScreenState();
}

class _DosingScreenState extends State<DosingScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _q = TextEditingController();
  String _pop = ''; // '' | adult | pediatric
  bool _starred = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    dosing.addListener(_changed);
    if (!dosing.loaded) dosing.load();
  }

  @override
  void dispose() {
    dosing.removeListener(_changed);
    _tabs.dispose();
    _q.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
      if (r == null) return;
      final added = await dosing.importFiles([for (final f in r.files) if (f.path != null) f.path!]);
      if (mounted) snack(context, trp('{n} dosing files added. They stay on this phone.', {'n': added.length}));
    } on FormatException catch (e) {
      if (mounted) snack(context, e.message);
    } catch (e) {
      if (mounted) snack(context, 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manage() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Text('Your dosing files', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (dosing.packs.isEmpty) Text('Nothing imported yet.'),
            for (final p in dosing.packs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: _en(p.title),
                subtitle: _en('${p.drugs} ${tr('drugs')} • ${p.durations} ${tr('durations')}${p.source.isEmpty ? '' : '\n${p.source}'}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: tr('Remove'),
                  onPressed: () async {
                    await dosing.remove(p.id);
                    setS(() {});
                  },
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => _formatHelp(ctx), icon: const Icon(Icons.info_outline), label: Text('File format')),
          ]),
        ),
      ),
    );
  }

  void _formatHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dosing file format'),
        content: SingleChildScrollView(
          child: Text('A JSON file with schemaVersion 1, meta (id, title, source), drugs (name, aka, class, routes, regimens with indication, population, route, dose, frequency, duration, max, notes, page; renal, hepatic, pregnancy, cautions, contraindications, interactions, monitoring, adverse, pearls) and durations (condition, regimen, duration, notes, page). Several files or a ZIP can be imported. The files stay on this phone.'),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = dosing.loaded && dosing.packs.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text('Doses & durations'),
        actions: [
          IconButton(icon: const Icon(Icons.file_open_outlined), tooltip: tr('Import a dosing file'), onPressed: _busy ? null : _import),
          IconButton(icon: const Icon(Icons.folder_open), tooltip: tr('Your dosing files'), onPressed: _manage),
        ],
        bottom: TabBar(controller: _tabs, tabs: [Tab(text: tr('Drugs')), Tab(text: tr('Durations'))]),
      ),
      body: !dosing.loaded
          ? const Center(child: CircularProgressIndicator())
          : empty
              ? _emptyState(theme)
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(children: [
                      Icon(Icons.shield_outlined, size: 18, color: theme.colorScheme.tertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('From your own files. Check every dose against your hospital protocol and the current official label before you use it.',
                            style: theme.textTheme.bodySmall),
                      ),
                    ]),
                  ),
                  if (widget.patient != null) _patientBar(theme),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      controller: _q,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: tr('Search a drug, brand name, class or indication'),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_q.clear)),
                      ),
                    ),
                  ),
                  Expanded(child: TabBarView(controller: _tabs, children: [_drugList(), _durationList()])),
                ]),
    );
  }

  Widget _patientBar(ThemeData theme) {
    final p = widget.patient!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withValues(alpha: .4), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.person_outline, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: _en([
              '${tr('Case')} ${p.code}',
              p.weightKg == null ? tr('no weight in the case') : '${DoseCalc.fmt(p.weightKg!)} kg',
              if (p.creatinineMgDl != null) '${tr('creatinine')} ${DoseCalc.fmt(p.creatinineMgDl!)} mg/dL',
            ].join('  •  '), style: theme.textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }

  Widget _emptyState(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.medication_liquid_outlined, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Your own dose reference', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Import the dosing files you prepared from your books or hospital protocols. They stay on this phone and work offline.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _busy ? null : _import, icon: const Icon(Icons.file_open_outlined), label: Text('Import a dosing file')),
            TextButton(onPressed: () => _formatHelp(context), child: Text('File format')),
          ]),
        ),
      );

  Widget _drugList() {
    var list = dosing.searchDrugs(_q.text, population: _pop);
    var flist = dosing.searchFormulary(_q.text, population: _pop);
    if (_starred) {
      list = [for (final d in list) if (_isFav(d.key)) d];
      flist = [for (final d in flist) if (_isFav(d.key)) d];
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Wrap(spacing: 6, children: [
        ChoiceChip(label: Text('All'), selected: _pop.isEmpty, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => _pop = '')),
        ChoiceChip(label: Text('Adult'), selected: _pop == 'adult', visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => _pop = _pop == 'adult' ? '' : 'adult')),
        ChoiceChip(label: Text('Pediatric'), selected: _pop == 'pediatric', visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => _pop = _pop == 'pediatric' ? '' : 'pediatric')),
        FilterChip(avatar: const Icon(Icons.star, size: 16), label: Text('Starred'), selected: _starred, visualDensity: VisualDensity.compact, onSelected: (v) => setState(() => _starred = v)),
      ]),
      const SizedBox(height: 6),
      if (list.isEmpty && flist.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Nothing found.'))),
      for (final d in flist.take(300))
        AppCard(
          child: ListTile(
            leading: Icon(d.hasRegimens ? Icons.calculate_outlined : Icons.menu_book_outlined),
            title: _en(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: _en([if (d.drugClass.isNotEmpty) d.drugClass, d.hasRegimens ? '${d.regimens.length} ${tr('regimens')}' : tr('Label text only')].join('  •  '), maxLines: 2),
            trailing: _isFav(d.key) ? const Icon(Icons.star, color: Colors.amber, size: 20) : const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FDrugScreen(drug: d, patient: widget.patient))).then((_) => setState(() {})),
          ),
        ),
      for (final d in list.take(300))
        AppCard(
          child: ListTile(
            title: _en(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: _en([if (d.drugClass.isNotEmpty) d.drugClass, if (d.routes.isNotEmpty) d.routes.join(' / '), '${d.regimens.length} ${tr('regimens')}'].join('  •  '), maxLines: 2),
            trailing: _isFav(d.key) ? const Icon(Icons.star, color: Colors.amber, size: 20) : const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DrugDetailScreen(drug: d))).then((_) => setState(() {})),
          ),
        ),
      if (list.length > 300) Padding(padding: const EdgeInsets.all(8), child: Text('Showing the first 300. Type more to narrow it down.')),
    ]);
  }

  Widget _durationList() {
    final list = dosing.searchDurations(_q.text);
    if (dosing.durations.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('The imported files have no duration tables.', textAlign: TextAlign.center)));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      if (list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Nothing found.'))),
      for (final d in list.take(300))
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _en(d.condition, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (d.regimen.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: _en(d.regimen)),
              if (d.duration.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _en(d.duration, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                ),
              if (d.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: _en(d.notes, style: Theme.of(context).textTheme.bodySmall)),
              if (d.page.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: _en('${tr('Source page')}: ${d.page}', style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
        ),
    ]);
  }
}

class DrugDetailScreen extends StatefulWidget {
  final DrugEntry drug;
  const DrugDetailScreen({super.key, required this.drug});
  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  DrugEntry get d => widget.drug;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String packTitle() {
      for (final p in dosing.packs) {
        if (p.id == d.pack) return p.title;
      }
      return d.pack;
    }

    return Scaffold(
      appBar: AppBar(
        title: _en(d.name),
        actions: [
          IconButton(
            icon: Icon(_isFav(d.key) ? Icons.star : Icons.star_border, color: _isFav(d.key) ? Colors.amber : null),
            onPressed: () async {
              await _toggleFav(d.key);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (d.aka.isNotEmpty) _en(d.aka.join(', '), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (d.drugClass.isNotEmpty) Chip(label: _en(d.drugClass), visualDensity: VisualDensity.compact),
          for (final r in d.routes) Chip(label: _en(r), visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer.withValues(alpha: .4), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.shield_outlined, size: 18, color: theme.colorScheme.tertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('From your file. Check this dose against your hospital protocol and the current official label before you use it.',
                  style: theme.textTheme.bodySmall),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        if (d.regimens.isEmpty) Text('No regimens in the file.'),
        for (final r in d.regimens) _regimen(r, theme),
        if (d.renal.isNotEmpty && d.renal == d.hepatic) _block('Renal and hepatic', d.renal) else ...[_block('Renal', d.renal), _block('Hepatic', d.hepatic)],
        _block('Pregnancy and breastfeeding', d.pregnancy),
        _list('Contraindications', d.contraindications),
        _list('Cautions', d.cautions),
        _list('Interactions', d.interactions),
        _list('Monitoring', d.monitoring),
        _list('Adverse effects', d.adverse),
        _list('Pearls', d.pearls),
        const SizedBox(height: 12),
        _en('${tr('Source')}: ${packTitle()}${d.page.isEmpty ? '' : ' • ${tr('page')} ${d.page}'}', style: theme.textTheme.bodySmall),
      ]),
    );
  }

  Widget _row(String label, String v, {bool strong = false}) {
    if (v.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 92, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        Expanded(child: _en(v, style: strong ? const TextStyle(fontWeight: FontWeight.w800, fontSize: 15) : null)),
      ]),
    );
  }

  Widget _regimen(DoseRegimen r, ThemeData theme) => AppCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _en(r.indication.isEmpty ? '—' : r.indication, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (r.population.isNotEmpty) Chip(label: _en(r.population), visualDensity: VisualDensity.compact),
            ]),
            _row('Route', r.route),
            _row('Dose', r.dose, strong: true),
            _row('Frequency', r.frequency, strong: true),
            _row('Duration', r.duration, strong: true),
            _row('Maximum', r.max),
            _row('Notes', r.notes),
            if (r.verify)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Unclear in the source: check the original.', style: TextStyle(color: theme.colorScheme.error, fontSize: 12))),
                ]),
              ),
            if (r.page.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: _en('${tr('Source page')}: ${r.page}', style: theme.textTheme.bodySmall)),
          ]),
        ),
      );

  Widget _block(String title, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return AppCard(child: ExpansionTile(title: Text(title), childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12), expandedCrossAxisAlignment: CrossAxisAlignment.start, children: [_en(text)]));
  }

  Widget _list(String title, List<String> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: ExpansionTile(
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final i in items) Padding(padding: const EdgeInsets.only(bottom: 4), child: _en('• $i'))],
      ),
    );
  }
}


// ============================================================ source-bound drug reference + calculator

String _approvalKey(FDrug d, FRegimen r) => '${d.pack}|${r.id}';

bool _approvedLocally(FDrug d, FRegimen r) {
  final m = store.settings['formApprove'];
  return m is Map && m[_approvalKey(d, r)] != null;
}

Future<void> _setApproval(FDrug d, FRegimen r, bool on) async {
  final m = <String, dynamic>{if (store.settings['formApprove'] is Map) ...Map<String, dynamic>.from(store.settings['formApprove'] as Map)};
  if (on) {
    m[_approvalKey(d, r)] = DateTime.now().toIso8601String().substring(0, 10);
  } else {
    m.remove(_approvalKey(d, r));
  }
  store.settings['formApprove'] = m;
  await store.saveSettings();
}

class FDrugScreen extends StatefulWidget {
  final FDrug drug;
  final DoseContext? patient;
  const FDrugScreen({super.key, required this.drug, this.patient});
  @override
  State<FDrugScreen> createState() => _FDrugScreenState();
}

class _FDrugScreenState extends State<FDrugScreen> {
  FDrug get d => widget.drug;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final srcs = [for (final id in d.sourceIds) if (dosing.fsources[id] != null) dosing.fsources[id]!];
    return Scaffold(
      appBar: AppBar(
        title: _en(d.name),
        actions: [
          IconButton(
            icon: Icon(_isFav(d.key) ? Icons.star : Icons.star_border, color: _isFav(d.key) ? Colors.amber : null),
            onPressed: () async {
              await _toggleFav(d.key);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (d.aka.isNotEmpty) _en(d.aka.join(', '), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (d.drugClass.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(children: [Chip(label: _en(d.drugClass), visualDensity: VisualDensity.compact)])),
        const SizedBox(height: 6),
        _banner(theme),
        const SizedBox(height: 8),
        if (d.hasRegimens) _CalcCard(drug: d, patient: widget.patient) else AppCard(child: Padding(padding: const EdgeInsets.all(12), child: Text('No structured dose in the file for this drug: read the label dosing text below.'))),
        _renalMentions(theme, open: false),
        _texts('Indications', d.indications, open: true),
        _texts('Contraindications', d.contraindications, open: true),
        _texts('Warnings and precautions', d.cautions),
        if (d.interactions.isNotEmpty)
          AppCard(
            child: ExpansionTile(
              title: Text('Interactions'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in d.interactions)
                  _LabelText('${i.with_.isEmpty ? '' : '${i.with_}: '}${i.effect}${i.severity.isEmpty ? '' : ' (${i.severity})'}'),
              ],
            ),
          ),
        _texts('Pregnancy', d.pregnancy),
        _texts('Breastfeeding', d.lactation),
        _texts('Adverse reactions', d.adverse),
        _texts('Label dosing text', d.dosingText),
        if (d.forms.isNotEmpty)
          AppCard(
            child: ExpansionTile(
              title: Text('Products in the file'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final f in d.forms) _en('• ${f.form}: ${f.label}${f.route.isEmpty ? '' : ' (${f.route})'}')],
            ),
          ),
        if (srcs.isNotEmpty)
          AppCard(
            child: ExpansionTile(
              title: Text('Sources'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in srcs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _en(s.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      _en('${s.publisher}${s.accessed.isEmpty ? '' : ' • ${tr('accessed')} ${s.accessed}'}', style: theme.textTheme.bodySmall),
                      if (s.url.isNotEmpty) SelectableText(s.url, style: theme.textTheme.bodySmall),
                      if (s.license.isNotEmpty) _en(s.license, style: theme.textTheme.bodySmall),
                    ]),
                  ),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _banner(ThemeData theme) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer.withValues(alpha: .4), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.shield_outlined, size: 18, color: theme.colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Taken from official drug labels. Not clinically approved: calculate only regimens you have checked against the source and your hospital protocol.',
                style: theme.textTheme.bodySmall),
          ),
        ]),
      );

  /// Sentences of the label about the kidneys, found for the reader.
  Widget _renalMentions(ThemeData theme, {required bool open}) {
    final r = renalSentences(d);
    if (r.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: ExpansionTile(
        initiallyExpanded: open,
        title: Text('Kidney (renal) mentions in the label'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final x in r) Padding(padding: const EdgeInsets.only(bottom: 6), child: _en(x))],
      ),
    );
  }

  Widget _texts(String title, List<FText> items, {bool open = false}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: ExpansionTile(
        initiallyExpanded: open,
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final t in items) _LabelText(t.text)],
      ),
    );
  }
}

/// A paragraph of label text, cleaned for reading and shortened until the user asks for all of it.
class _LabelText extends StatefulWidget {
  final String text;
  const _LabelText(this.text);
  @override
  State<_LabelText> createState() => _LabelTextState();
}

class _LabelTextState extends State<_LabelText> {
  bool _all = false;
  static const _max = 900;

  @override
  Widget build(BuildContext context) {
    final t = cleanLabelText(widget.text);
    final long = t.length > _max;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _en(long && !_all ? '${t.substring(0, _max)}…' : t),
        if (long)
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Show less' : 'Show all'),
          ),
      ]),
    );
  }
}

class _CalcCard extends StatefulWidget {
  final FDrug drug;
  final DoseContext? patient;
  const _CalcCard({required this.drug, this.patient});
  @override
  State<_CalcCard> createState() => _CalcCardState();
}

class _CalcCardState extends State<_CalcCard> {
  final _w = TextEditingController(), _a = TextEditingController(), _h = TextEditingController();
  bool _lb = false, _years = false;
  String _regId = '';
  String _formId = '';

  FDrug get d => widget.drug;
  FRegimen get _reg => d.regimens.firstWhere((r) => r.id == _regId, orElse: () => d.regimens.first);

  @override
  void initState() {
    super.initState();
    final p = widget.patient;
    if (p != null && p.weightKg != null) _w.text = DoseCalc.fmt(p.weightKg!);
    // the regimens for this patient's age group come first
    final group = p == null ? '' : (p.isChild ? 'pediatric' : (p.isAdult ? 'adult' : ''));
    final match = group.isEmpty ? <FRegimen>[] : [for (final r in d.regimens) if (r.group.toLowerCase().contains(group)) r];
    _regId = (match.isNotEmpty ? match.first : d.regimens.first).id;
    _formId = _formsFor(_reg).isEmpty ? '' : (_formsFor(_reg).any((f) => f.id == _reg.formId) ? _reg.formId : _formsFor(_reg).first.id);
  }

  @override
  void dispose() {
    _w.dispose();
    _a.dispose();
    _h.dispose();
    super.dispose();
  }

  List<FForm> _formsFor(FRegimen r) {
    final byComponent = [for (final f in d.forms) if (r.component.isEmpty || f.component.isEmpty || f.component == r.component) f];
    return byComponent;
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  bool get _approved => _reg.fileApproved || _approvedLocally(d, _reg);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _reg;
    final forms = _formsFor(r);
    final w = _num(_w), a = _num(_a), h = _num(_h);
    final input = DoseInput(
      weightKg: w == null ? null : (_lb ? w * 0.45359237 : w),
      ageMonths: a == null ? null : (_years ? a * 12 : a),
      heightCm: h,
    );
    FForm? form;
    for (final f in forms) {
      if (f.id == _formId) form = f;
    }
    final res = _approved ? DoseCalc.compute(r, input, form: form) : null;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.calculate_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Dose calculator', style: theme.textTheme.titleMedium),
          ]),
          const SizedBox(height: 8),
          _picker(tr('Regimen'), r.label, () async {
            final v = await _pick<String>(tr('Regimen'), [for (final x in d.regimens) (x.id, x.label)], _regId);
            if (v == null) return;
            setState(() {
              _regId = v;
              final fs = _formsFor(_reg);
              _formId = fs.isEmpty ? '' : (fs.any((f) => f.id == _reg.formId) ? _reg.formId : fs.first.id);
            });
          }),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _numField(_w, tr('Weight'), _lb ? 'lb' : 'kg', () => setState(() => _lb = !_lb))),
            const SizedBox(width: 8),
            Expanded(child: _numField(_a, tr('Age'), _years ? tr('years') : tr('months'), () => setState(() => _years = !_years))),
          ]),
          if (r.basis == 'bsa' || (widget.patient?.creatinineMgDl != null && widget.patient!.isChild))
            Padding(padding: const EdgeInsets.only(top: 8), child: _numField(_h, tr('Height'), 'cm', null)),
          if (widget.patient != null) _kidneyBlock(theme, input),
          if (forms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _picker(tr('Product (for the volume)'), form == null ? '' : '${form.form}: ${form.label}', () async {
                final v = await _pick<String>(tr('Product (for the volume)'), [for (final f in forms) (f.id, '${f.form}: ${f.label}')], _formId);
                if (v != null) setState(() => _formId = v);
              }),
            ),
          const SizedBox(height: 10),
          if (!_approved) _approvalBox(theme) else _result(theme, res!),
        ]),
      ),
    );
  }

  /// A field that shows the whole chosen text (up to 3 lines) and opens a list of the options.
  Widget _picker(String label, String value, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, isDense: true, suffixIcon: const Icon(Icons.arrow_drop_down)),
          child: _en(value.isEmpty ? '—' : value, maxLines: 3),
        ),
      );

  Future<T?> _pick<T>(String title, List<(T, String)> options, T current) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
            for (final o in options)
              ListTile(
                title: _en(o.$2),
                trailing: o.$1 == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, o.$1),
              ),
          ]),
        ),
      ),
    );
  }

  /// The creatinine of the case with the day it was recorded, the kidney function it gives, and the label's kidney
  /// sentences when the function is reduced.
  Widget _kidneyBlock(ThemeData theme, DoseInput input) {
    final p = widget.patient!;
    if (p.creatinineMgDl == null) return const SizedBox.shrink();
    final days = p.creatinineAgeDays;
    final old = days != null && days >= 2;
    final ageYears = input.ageMonths == null ? null : input.ageMonths! / 12;
    final cl = p.clearance(ageYears: ageYears, weight: input.weightKg, heightCm: input.heightCm);
    final low = cl != null && cl.value < 60;
    final mentions = renalSentences(d);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (low ? theme.colorScheme.errorContainer : theme.colorScheme.surfaceContainerHighest).withValues(alpha: .6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _en('${tr('Creatinine')} ${DoseCalc.fmt(p.creatinineMgDl!)} mg/dL${days == null ? '' : ' — ${tr('recorded')} ${days == 0 ? tr('today') : '$days ${tr('days ago')}'}'}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (old) Text('This value may have changed: check the latest result before you rely on it.', style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
          const SizedBox(height: 4),
          if (cl != null)
            _en('${tr('Kidney function')}: ≈ ${DoseCalc.fmt(cl.value.roundToDouble())} mL/min (${cl.method})', style: const TextStyle(fontWeight: FontWeight.w700))
          else
            Text(p.isChild ? 'Enter the age and the height to estimate the kidney function.' : 'Enter the age to estimate the kidney function.', style: theme.textTheme.bodySmall),
          if (low) ...[
            const SizedBox(height: 6),
            Text('Reduced kidney function: this drug may need a different dose. Read what the label says:', style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w700)),
            for (final x in mentions) Padding(padding: const EdgeInsets.only(top: 4), child: _en(x, style: theme.textTheme.bodySmall)),
            if (mentions.isEmpty) Text('The label text in the file does not mention the kidneys: check another source.'),
          ] else if (mentions.isNotEmpty && cl != null)
            Text('The label has kidney-related statements: see "Kidney (renal) mentions in the label".', style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label, String unit, VoidCallback? toggle) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffix: toggle == null
              ? m.Text(unit)
              : InkWell(onTap: toggle, child: Padding(padding: const EdgeInsets.all(2), child: m.Text(unit, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)))),
        ),
      );

  Widget _approvalBox(ThemeData theme) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: theme.colorScheme.errorContainer.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This regimen is not approved for calculation yet.', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Compare its numbers with the source and your hospital protocol, then approve it here. The approval stays on this phone only.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(onPressed: _review, icon: const Icon(Icons.fact_check_outlined), label: Text('Check it against the source')),
        ]),
      );

  Future<void> _review() async {
    final r = _reg;
    var sure = false;
    String range(double? a, double? b, String u) => a == null && b == null ? '—' : (a == b || b == null ? '${DoseCalc.fmt(a ?? b!)} $u' : '${DoseCalc.fmt(a!)}–${DoseCalc.fmt(b)} $u');
    final lines = <String>[
      '${tr('Indication')}: ${r.indication.isEmpty ? '—' : r.indication}',
      '${tr('For')}: ${[r.group, if (r.ageMin != null) '${tr('age from')} ${DoseCalc.fmt(r.ageMin!)} ${tr('months')}', if (r.ageMax != null) '${tr('age under')} ${DoseCalc.fmt(r.ageMax!)} ${tr('months')}', if (r.weightMin != null) '${tr('weight from')} ${DoseCalc.fmt(r.weightMin!)} kg', if (r.weightMax != null) '${tr('weight under')} ${DoseCalc.fmt(r.weightMax!)} kg'].where((e) => e.isNotEmpty).join(', ')}',
      '${tr('Route')}: ${r.route.isEmpty ? '—' : r.route}',
      '${tr('Dose')}: ${range(r.doseMin, r.doseMax, '${r.doseUnit}${r.dosePer.isEmpty ? '' : '/${r.dosePer}'}${r.dosePerUnit.isEmpty ? '' : ' ${tr('per')} ${r.dosePerUnit == 'day' ? tr('day') : tr('dose')}'}')}',
      '${tr('Frequency')}: ${r.freqText.isEmpty ? '—' : r.freqText}',
      if (r.maxSingle != null) '${tr('Maximum single dose')}: ${DoseCalc.fmt(r.maxSingle!)} ${r.maxSingleUnit}',
      if (r.maxDaily != null) '${tr('Maximum per day')}: ${DoseCalc.fmt(r.maxDaily!)} ${r.maxDailyUnit}',
      if (r.maxDailyPerKg != null) '${tr('Maximum per kg per day')}: ${DoseCalc.fmt(r.maxDailyPerKg!)} ${r.maxDailyPerKgUnit}',
      if (r.notes.isNotEmpty) '${tr('Notes')}: ${r.notes}',
    ];
    final src = d.dosingText.isEmpty ? '' : cleanLabelText(d.dosingText.first.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Check against the source'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Numbers in the file', style: const TextStyle(fontWeight: FontWeight.w700)),
                    for (final l in lines) Padding(padding: const EdgeInsets.only(top: 2), child: _en(l)),
                    if (src.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Label dosing text (start)', style: const TextStyle(fontWeight: FontWeight.w700)),
                      _en(src.length > 1500 ? '${src.substring(0, 1500)}…' : src),
                    ],
                  ]),
                ),
              ),
              const Divider(),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: sure,
                onChanged: (v) => setS(() => sure = v == true),
                title: Text('I checked these numbers against the source and my hospital protocol.'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
            FilledButton(onPressed: sure ? () => Navigator.pop(ctx, true) : null, child: Text('Approve')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _setApproval(d, r, true);
      if (mounted) setState(() {});
    }
  }

  String _range(double a, double b, String u) => (a - b).abs() < 1e-9 ? '${DoseCalc.fmt(a)} $u' : '${DoseCalc.fmt(a)}–${DoseCalc.fmt(b)} $u';

  Widget _result(ThemeData theme, DoseResult res) {
    final r = _reg;
    final children = <Widget>[];
    if (res.blockers.isNotEmpty) {
      for (final b in res.blockers) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(b)),
          ]),
        ));
      }
    } else {
      final per = res.perDoseMin == null ? null : _range(res.perDoseMin!, res.perDoseMax!, res.unit);
      children.addAll([
        if (per != null) ...[
          Text('Per dose', style: theme.textTheme.bodySmall),
          _en(per, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
        ],
        if (res.volumeMin != null) ...[
          const SizedBox(height: 4),
          Text('Volume / amount of the product', style: theme.textTheme.bodySmall),
          _en(_range(res.volumeMin!, res.volumeMax!, res.volumeUnit), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ],
        if (res.dailyMin != null) ...[
          const SizedBox(height: 4),
          Text('Per day', style: theme.textTheme.bodySmall),
          _en(_range(res.dailyMin!, res.dailyMax!, res.unit), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
        if (r.freqText.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: _en('${tr('Frequency')}: ${r.freqText}')),
        if (r.durationText.isNotEmpty) _en('${tr('Duration')}: ${r.durationText}'),
        if (r.administration.isNotEmpty) _en('${tr('Administration')}: ${r.administration}'),
        const SizedBox(height: 4),
        _en(res.formula, style: theme.textTheme.bodySmall),
      ]);
      for (final x in res.warnings) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
            const SizedBox(width: 6),
            Expanded(child: Text(x, style: TextStyle(color: theme.colorScheme.error))),
          ]),
        ));
      }
      for (final x in res.notes) {
        children.add(Padding(padding: const EdgeInsets.only(top: 4), child: Text(x, style: theme.textTheme.bodySmall)));
      }
      if (r.notes.isNotEmpty) children.add(Padding(padding: const EdgeInsets.only(top: 6), child: _en(r.notes, style: theme.textTheme.bodySmall)));
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Renal and hepatic adjustment, allergies and interactions are not calculated: check them yourself.', style: theme.textTheme.bodySmall),
      ));
    }
    children.add(Row(children: [
      Expanded(child: _en('${tr('Source')}: ${r.source.split('#').first}', style: theme.textTheme.bodySmall)),
      if (!r.fileApproved)
        TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () async {
            await _setApproval(d, r, false);
            if (mounted) setState(() {});
          },
          child: Text('Remove my approval'),
        ),
    ]));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
