import 'ai/ai_context.dart';
import 'ai/ai_tools.dart' show statsOfCases, logbookNarrative;
import 'screens_ai_tools.dart' show PeriodNarrativeCard;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ai/ai_api.dart' show Ai;
import 'ai/ai_cases.dart' show rotationStats;
import 'data.dart';
import 'focus.dart' show stageOfRole;
import 'goals_signoff.dart';
import 'i18n.dart';
import 'motion.dart';
import 'pdf_export.dart';
import 'privacy.dart';
import 'screens_ai_cases.dart' show rotationNarrative;
import 'screens_library.dart';
import 'screens_privacy.dart';
import 'screens_reasoning.dart';
import 'screens_review.dart';
import 'screens_search.dart';
import 'search_index.dart';
import 'ui.dart';
import 'widgets.dart';

// ================================================================ editors

const List<String> kAchievementKinds = ['Presentation', 'Publication', 'Course / workshop', 'Award', 'Teaching', 'Audit / research', 'Other'];

Future<void> editAchievement(BuildContext context, [J? e]) => _editExtra(
      context,
      'achievements',
      e,
      title: e == null ? 'New achievement' : 'Achievement',
      specs: const [
        FieldSpec('title', 'Title'),
        FieldSpec('kind', 'Type', type: FT.choice, options: kAchievementKinds),
        FieldSpec('date', 'Date', type: FT.date),
        FieldSpec('where', 'Where / with whom'),
        FieldSpec('note', 'Notes', type: FT.multi),
      ],
      initial: {'id': newId('ac'), 'date': todayStr(), 'kind': 'Other'},
    );

Future<void> editReflection(BuildContext context, [J? e]) => _editExtra(
      context,
      'reflections',
      e,
      title: e == null ? 'New reflection' : 'Reflection',
      specs: const [
        FieldSpec('title', 'What this is about'),
        FieldSpec('date', 'Date', type: FT.date),
        FieldSpec('happened', 'What happened', type: FT.multi),
        FieldSpec('felt', 'How I felt', type: FT.multi),
        FieldSpec('learned', 'What I learned', type: FT.multi),
        FieldSpec('next', 'What I will do next time', type: FT.multi),
        FieldSpec('caseCode', 'Related case code (optional)'),
      ],
      initial: {'id': newId('rf'), 'date': todayStr()},
    );

const List<String> kQiStatus = ['Idea', 'Running', 'Finished'];

Future<void> editQi(BuildContext context, [J? e]) => _editExtra(
      context,
      'qi',
      e,
      title: e == null ? 'New quality project' : 'Quality project',
      specs: const [
        FieldSpec('title', 'Project title'),
        FieldSpec('problem', 'The problem I noticed', type: FT.multi),
        FieldSpec('change', 'The change I tried', type: FT.multi),
        FieldSpec('measure', 'How I measured it', type: FT.multi),
        FieldSpec('result', 'Result', type: FT.multi),
        FieldSpec('status', 'Status', type: FT.choice, options: kQiStatus),
        FieldSpec('date', 'Started', type: FT.date),
      ],
      initial: {'id': newId('qi'), 'date': todayStr(), 'status': 'Idea'},
    );

const List<String> kEvidenceLevels = ['Guideline', 'Systematic review', 'Trial', 'Observational', 'Expert opinion / textbook', 'Not sure'];

Future<void> editEvidence(BuildContext context, [J? e]) => _editExtra(
      context,
      'evidence',
      e,
      title: e == null ? 'New reference' : 'Reference',
      specs: const [
        FieldSpec('title', 'Title'),
        FieldSpec('source', 'Source / journal'),
        FieldSpec('year', 'Year', type: FT.number),
        FieldSpec('level', 'Type of evidence', type: FT.choice, options: kEvidenceLevels),
        FieldSpec('link', 'Link (optional)'),
        FieldSpec('topic', 'Topic'),
        FieldSpec('note', 'What it says, in my words', type: FT.multi),
        FieldSpec('reviewed', 'Last checked', type: FT.date),
      ],
      initial: {'id': newId('ev'), 'saved': todayStr(), 'reviewed': todayStr(), 'level': 'Not sure'},
    );

Future<void> _editExtra(BuildContext context, String list, J? e,
    {required String title, required List<FieldSpec> specs, required Map<String, dynamic> initial}) async {
  final res = await showFormSheet(
    context,
    title: title,
    specs: specs,
    initial: e ?? Map<String, dynamic>.from(initial),
    canDelete: e != null,
  );
  if (res == null) return;
  if (res['__delete'] == true) {
    await store.removeExtra(list, e!['id'].toString());
  } else {
    await store.upsertExtra(list, res);
  }
}

// ================================================================ generic list screen

class _NotebookList extends StatelessWidget {
  final String title;
  final String list;
  final IconData icon;
  final String empty;
  final Future<void> Function(BuildContext, [J?]) edit;
  final String Function(J) titleOf;
  final String Function(J) subtitleOf;
  final List<Widget> Function(BuildContext)? actions;
  const _NotebookList({
    required this.title,
    required this.list,
    required this.icon,
    required this.empty,
    required this.edit,
    required this.titleOf,
    required this.subtitleOf,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final items = [...store.listOf(list)]
          ..sort((a, b) => '${b['date'] ?? b['saved'] ?? ''}'.compareTo('${a['date'] ?? a['saved'] ?? ''}'));
        return Scaffold(
          appBar: AppBar(title: Text(title), actions: actions?.call(context)),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => edit(context),
            icon: const Icon(Icons.add),
            label: Text('Add'),
          ),
          body: items.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(empty, textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    for (var i = 0; i < items.length; i++)
                      FadeSlideIn(
                        index: i,
                        child: AppCard(
                          child: ListTile(
                            onTap: () => edit(context, items[i]),
                            leading: Icon(icon),
                            title: Text(titleOf(items[i]), maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(subtitleOf(items[i]), maxLines: 2, overflow: TextOverflow.ellipsis),
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

String _join(Iterable<String?> parts) => parts.where((e) => e != null && e.trim().isNotEmpty).join(' • ');

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});
  @override
  Widget build(BuildContext context) => _NotebookList(
        title: tr('Achievements'),
        list: 'achievements',
        icon: Icons.emoji_events_outlined,
        empty: tr('Keep your presentations, courses, publications and awards here, ready for your CV.'),
        edit: editAchievement,
        titleOf: (e) => '${e['title'] ?? ''}',
        subtitleOf: (e) => _join([tr('${e['kind'] ?? ''}'), prettyDate('${e['date'] ?? ''}'), '${e['where'] ?? ''}']),
      );
}

class ReflectionsScreen extends StatelessWidget {
  const ReflectionsScreen({super.key});
  @override
  Widget build(BuildContext context) => _NotebookList(
        title: tr('Reflection notebook'),
        list: 'reflections',
        icon: Icons.self_improvement,
        empty: tr('Your own words, kept private on this phone.'),
        edit: editReflection,
        titleOf: (e) => '${e['title'] ?? ''}'.isEmpty ? '${e['happened'] ?? ''}' : '${e['title']}',
        subtitleOf: (e) => _join([prettyDate('${e['date'] ?? ''}'), '${e['learned'] ?? ''}']),
      );
}

class QiScreen extends StatelessWidget {
  const QiScreen({super.key});
  @override
  Widget build(BuildContext context) => _NotebookList(
        title: tr('Quality improvement'),
        list: 'qi',
        icon: Icons.trending_up,
        empty: tr('Write down a small problem you noticed, what you tried and what happened.'),
        edit: editQi,
        titleOf: (e) => '${e['title'] ?? ''}',
        subtitleOf: (e) => _join([tr('${e['status'] ?? ''}'), '${e['result'] ?? ''}']),
      );
}

Future<void> openUrl(BuildContext context, String url) async {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https') {
    snack(context, tr('Only secure (https) links are opened.'));
    return;
  }
  try {
    final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) snack(context, tr('Could not open the link.'));
  } catch (_) {
    if (context.mounted) snack(context, tr('Could not open the link.'));
  }
}

class EvidenceScreen extends StatelessWidget {
  const EvidenceScreen({super.key});
  @override
  Widget build(BuildContext context) => _NotebookList(
        title: tr('References and evidence'),
        list: 'evidence',
        icon: Icons.menu_book_outlined,
        empty: tr('Save the sources behind what you learn: title, year, type of evidence and what it says.'),
        edit: editEvidence,
        titleOf: (e) => '${e['title'] ?? ''}',
        subtitleOf: (e) => _join([
          '${e['source'] ?? ''}',
          '${e['year'] ?? ''}',
          tr('${e['level'] ?? ''}'),
        ]),
        actions: (ctx) => [
          IconButton(
            tooltip: tr('Search PubMed'),
            icon: const Icon(Icons.travel_explore),
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const PubMedScreen())),
          ),
        ],
      );
}

// ================================================================ PubMed (optional, only the search words leave the phone)

class PubMedHit {
  final String pmid;
  final String title;
  final String authors;
  final String source;
  final String year;
  const PubMedHit(this.pmid, this.title, this.authors, this.source, this.year);
  String get link => 'https://pubmed.ncbi.nlm.nih.gov/$pmid/';
}

Future<Map<String, dynamic>> _getJson(Uri u) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await c.getUrl(u);
    req.headers.set('User-Agent', 'MedLog/$kAppVersion');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final body = await res.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    c.close(force: true);
  }
}

/// NCBI E-utilities: esearch for ids, esummary for details.
Future<List<PubMedHit>> searchPubMed(String query, {int max = 10}) async {
  final s = await _getJson(Uri.https('eutils.ncbi.nlm.nih.gov', '/entrez/eutils/esearch.fcgi', {
    'db': 'pubmed',
    'term': query,
    'retmode': 'json',
    'retmax': '$max',
    'sort': 'relevance',
    'tool': 'MedLog',
  }));
  final ids = ((s['esearchresult']?['idlist'] as List?) ?? const []).map((e) => '$e').toList();
  if (ids.isEmpty) return const [];
  final d = await _getJson(Uri.https('eutils.ncbi.nlm.nih.gov', '/entrez/eutils/esummary.fcgi', {
    'db': 'pubmed',
    'id': ids.join(','),
    'retmode': 'json',
    'tool': 'MedLog',
  }));
  final result = (d['result'] as Map?) ?? const {};
  final out = <PubMedHit>[];
  for (final id in ids) {
    final r = result[id];
    if (r is! Map) continue;
    final authors = ((r['authors'] as List?) ?? const []).map((a) => '${(a as Map)['name']}').take(3).join(', ');
    final pub = '${r['pubdate'] ?? ''}';
    out.add(PubMedHit(id, '${r['title'] ?? ''}'.replaceAll(RegExp(r'\.$'), ''), authors, '${r['source'] ?? ''}',
        RegExp(r'\d{4}').firstMatch(pub)?.group(0) ?? ''));
  }
  return out;
}

class PubMedScreen extends StatefulWidget {
  const PubMedScreen({super.key});
  @override
  State<PubMedScreen> createState() => _PubMedScreenState();
}

class _PubMedScreenState extends State<PubMedScreen> {
  final _q = TextEditingController();
  List<PubMedHit>? _hits;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    // the search words are the only thing that leaves the phone: never let an identifier go with them
    if (scanText(q).isNotEmpty) {
      setState(() => _error = tr('The search looks like it contains an identifier (number, name, date). Use only medical words.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final h = await searchPubMed(q);
      if (mounted) setState(() => _hits = h);
    } catch (_) {
      if (mounted) setState(() => _error = tr('No internet connection, or PubMed did not answer. Everything else works offline.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(PubMedHit h) async {
    final exists = store.listOf('evidence').any((e) => e['pmid'] == h.pmid);
    if (exists) {
      snack(context, tr('Already in your references.'));
      return;
    }
    await store.upsertExtra('evidence', {
      'id': newId('ev'),
      'pmid': h.pmid,
      'title': h.title,
      'source': h.source,
      'year': h.year,
      'link': h.link,
      'topic': _q.text.trim(),
      'level': 'Not sure',
      'note': '',
      'saved': todayStr(),
      'reviewed': todayStr(),
    });
    if (mounted) snack(context, tr('Saved to your references.'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Search PubMed')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _go(),
            decoration: InputDecoration(
              labelText: tr('Medical words'),
              hintText: 'sepsis guideline',
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _busy ? null : _go),
            ),
          ),
          const SizedBox(height: 8),
          Text('Only the words you type are sent to PubMed (NCBI). Never type patient details.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (_hits != null && _hits!.isEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text('Nothing found.')),
          for (final h in _hits ?? const <PubMedHit>[])
            AppCard(
              child: ListTile(
                title: Text(h.title, maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Text(_join([h.authors, h.source, h.year]), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => openUrl(context, h.link),
                trailing: IconButton(tooltip: tr('Save'), icon: const Icon(Icons.bookmark_add_outlined), onPressed: () => _save(h)),
              ),
            ),
        ],
      ),
    );
  }
}

// ================================================================ trusted sites

const List<List<String>> kTrustedSites = [
  ['PubMed', 'https://pubmed.ncbi.nlm.nih.gov/', 'Research articles (US National Library of Medicine)'],
  ['MedlinePlus', 'https://medlineplus.gov/', 'Patient-friendly health information (US NLM)'],
  ['WHO', 'https://www.who.int/publications/guidelines', 'World Health Organization guidelines'],
  ['CDC', 'https://www.cdc.gov/', 'Infectious disease and public-health guidance'],
  ['NICE', 'https://www.nice.org.uk/guidance', 'UK clinical guidelines'],
  ['Cochrane Library', 'https://www.cochranelibrary.com/', 'Systematic reviews'],
  ['DailyMed', 'https://dailymed.nlm.nih.gov/', 'Official drug labels'],
];

class TrustedSitesScreen extends StatelessWidget {
  const TrustedSitesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Trusted sites')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Opens in your browser. Nothing from your cases is sent.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final s in kTrustedSites)
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: Text(s[0]),
                subtitle: Text(s[2]),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => openUrl(context, s[1]),
              ),
            ),
        ],
      ),
    );
  }
}

// ================================================================ analytics

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cases = store.casesSorted().where((c) => !c.id.startsWith('demo_')).toList();
    final now = DateTime.now();
    final months = <String, int>{};
    for (var i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      months['${d.year}-${two(d.month)}'] = 0;
    }
    final spec = <String, int>{};
    final roles = <String, int>{};
    final settings = <String, int>{};
    for (final c in cases) {
      final d = c.s('date');
      if (d.length >= 7 && months.containsKey(d.substring(0, 7))) months[d.substring(0, 7)] = months[d.substring(0, 7)]! + 1;
      void inc(Map<String, int> m, String k) {
        if (k.isNotEmpty) m[k] = (m[k] ?? 0) + 1;
      }

      inc(spec, c.s('specialty'));
      inc(roles, c.s('role'));
      inc(settings, c.s('setting'));
    }
    final maxMonth = months.values.fold<int>(1, (a, b) => b > a ? b : a);
    final specSorted = spec.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = cases.length;
    final withLearning = cases.where((c) => c.s('learned').trim().isNotEmpty).length;
    final withFinal = cases.where((c) => c.s('finalDx').trim().isNotEmpty).length;
    final procs = store.procedures.where((p) => p['demo'] != true).length;

    Widget bars(Map<String, int> m, {int top = 8, String Function(String)? label}) {
      final es = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final mx = es.isEmpty ? 1 : es.first.value;
      return Column(children: [
        for (final e in es.take(top))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 120, child: Text(label == null ? tr(e.key) : label(e.key), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
              Expanded(child: AnimatedBar(e.value / mx, height: 8)),
              SizedBox(width: 32, child: Text('${e.value}', textAlign: TextAlign.end, style: theme.textTheme.labelMedium)),
            ]),
          ),
      ]);
    }

    Widget card(String title, IconData icon, Widget child) => AppCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 10),
              child,
            ]),
          ),
        );

    return AiContextScope(
      ctx: const AiScreenContext(kind: 'portfolio', title: 'Analytics'),
      child: Scaffold(
      appBar: AppBar(title: Text('Analytics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            Chip(label: Text(countLabel(total, 'case'))),
            Chip(label: Text(countLabel(procs, 'procedure'))),
            Chip(label: Text(trp('{a} of {b} with a learning point', {'a': withLearning, 'b': total}))),
            Chip(label: Text(trp('{a} of {b} with a final diagnosis', {'a': withFinal, 'b': total}))),
          ]),
          PeriodNarrativeCard(stats: statsOfCases(cases, store.procedures.where((p) => p['demo'] != true).toList(), title: 'All logged work'), kind: 'analytics'),
          const SizedBox(height: 8),
          card(tr('Cases per month'), Icons.bar_chart, Column(children: [
            for (final e in months.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 120, child: Text(monthLabel(e.key), style: theme.textTheme.bodySmall)),
                  Expanded(child: AnimatedBar(e.value / maxMonth, height: 8)),
                  SizedBox(width: 32, child: Text('${e.value}', textAlign: TextAlign.end, style: theme.textTheme.labelMedium)),
                ]),
              ),
          ])),
          card(tr('Specialty diversity'), Icons.pie_chart_outline, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            bars(spec),
            const SizedBox(height: 6),
            Text(
              spec.isEmpty
                  ? tr('Add cases to see the balance across specialties.')
                  : specSorted.first.value * 2 > total && spec.length > 1
                      ? trp('More than half of your cases are {name}.', {'name': tr(specSorted.first.key)})
                      : tr('Your cases are spread across specialties.'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ])),
          card(tr('My role in cases'), Icons.badge_outlined, bars(roles)),
          card(tr('Where I saw them'), Icons.local_hospital_outlined, bars(settings)),
          const CalibrationCard(),
          const SizedBox(height: 24),
        ],
      ),
      ),
    );
  }
}

String monthLabel(String ym) {
  final p = ym.split('-');
  if (p.length != 2) return ym;
  return '${monthName((int.tryParse(p[1]) ?? 1) - 1)} ${p[0]}';
}

// ================================================================ PDF export + update check

/// Asks for PDF options. Returns null when cancelled, otherwise whether large print is on.
Future<bool?> askPdfOptions(BuildContext context) {
  var large = false;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        icon: const Icon(Icons.picture_as_pdf_outlined),
        title: Text('Export as PDF'),
        content: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Large print'),
          subtitle: Text('Bigger bold text, easier to read'),
          value: large,
          onChanged: (v) => setS(() => large = v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, large), child: Text('Export')),
        ],
      ),
    ),
  );
}

/// Export sheet: range (this rotation / date range / all), format (PDF / CSV), large print and
/// supervisor sign-off lines. Returns null when cancelled. [withRange] is false when the
/// entries were already chosen by the caller (e.g. selected cases).
Future<ExportOptions?> askExportOptions(BuildContext context, {bool withRange = true, String? rotationId}) {
  final cur = rotationId != null ? store.rotationById(rotationId) : store.currentRotation();
  final o = ExportOptions(
    range: rotationId != null ? 'rotation' : 'all',
    rotationId: cur == null ? null : cur['id'].toString(),
  );
  final rots = [...store.rotations]..sort((a, b) => (b['start'] ?? '').toString().compareTo((a['start'] ?? '').toString()));
  return showDialog<ExportOptions>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final theme = Theme.of(ctx);
        Widget label(String t) => Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(t, style: theme.textTheme.labelLarge),
            );
        Future<void> pick(bool from) async {
          final d = await showDatePicker(
            context: ctx,
            initialDate: (from ? o.from : o.to) ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (d != null) setS(() => from ? o.from = d : o.to = d);
        }

        return AlertDialog(
          icon: const Icon(Icons.ios_share_outlined),
          title: const Text('Export logbook'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (withRange) ...[
                  label(tr('Range')),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    ChoiceChip(label: const Text('All'), selected: o.range == 'all', onSelected: (_) => setS(() => o.range = 'all')),
                    if (rots.isNotEmpty)
                      ChoiceChip(
                          label: const Text('This rotation'),
                          selected: o.range == 'rotation',
                          onSelected: (_) => setS(() => o.range = 'rotation')),
                    ChoiceChip(
                        label: const Text('Date range'), selected: o.range == 'dates', onSelected: (_) => setS(() => o.range = 'dates')),
                  ]),
                  if (o.range == 'rotation' && rots.length > 1)
                    DropdownButton<String>(
                      isExpanded: true,
                      value: rots.any((r) => r['id'] == o.rotationId) ? o.rotationId : null,
                      items: [
                        for (final r in rots)
                          DropdownMenuItem(value: r['id'].toString(), child: Text(store.rotationLabel(r), overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setS(() => o.rotationId = v),
                    ),
                  if (o.range == 'rotation' && rots.length == 1)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(store.rotationLabel(rots.first))),
                  if (o.range == 'dates')
                    Wrap(spacing: 8, children: [
                      OutlinedButton(
                          onPressed: () => pick(true),
                          child: Text('${tr('From')}: ${o.from == null ? '—' : fmtDate(o.from!)}')),
                      OutlinedButton(
                          onPressed: () => pick(false), child: Text('${tr('To')}: ${o.to == null ? '—' : fmtDate(o.to!)}')),
                    ]),
                ],
                label(tr('Format')),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'pdf', icon: Icon(Icons.picture_as_pdf_outlined), label: Text('PDF')),
                      ButtonSegment(value: 'csv', icon: Icon(Icons.table_chart_outlined), label: Text('CSV')),
                    ],
                    selected: {o.format},
                    onSelectionChanged: (v) => setS(() => o.format = v.first),
                  ),
                ),
                if (o.format == 'pdf')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Large print'),
                    subtitle: const Text('Bigger bold text, easier to read'),
                    value: o.large,
                    onChanged: (v) => setS(() => o.large = v),
                  ),
                if (o.format == 'pdf' && Ai.enabled)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Add an AI summary paragraph'),
                    subtitle: const Text('Written from the counts only, marked AI-generated in the PDF. Needs internet.'),
                    value: o.aiSummary,
                    onChanged: (v) => setS(() => o.aiSummary = v),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include supervisor sign-off lines'),
                  subtitle: Text(o.format == 'pdf'
                      ? tr('A sign-off column and lines to sign by hand on the printed page')
                      : tr('Supervisor, role, level and signed columns')),
                  value: o.signOff,
                  onChanged: (v) => setS(() => o.signOff = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, o), child: const Text('Export')),
          ],
        );
      },
    ),
  );
}

Future<void> exportCasePdf(BuildContext context, CaseRec c) => exportCasesPdf(context, [c]);

Future<void> exportCasesPdf(BuildContext context, List<CaseRec> cases) async {
  if (cases.isEmpty) return;
  if (!await privacyGate(context, cases)) return;
  if (!context.mounted) return;
  final o = await askExportOptions(context, withRange: false);
  if (o == null) return;
  try {
    if (o.format == 'csv') {
      final files = await store.exportCsv(onlyCases: cases, onlyProcs: const [], signOff: o.signOff);
      await Share.shareXFiles([XFile(files.first.path)], text: 'MedLog');
      return;
    }
    final one = cases.length == 1;
    final f = await writeCasesPdf(cases,
        title: one ? null : tr('Cases'),
        fileName: one ? 'MedLog_${cases.first.s('code')}' : 'MedLog_cases',
        large: o.large,
        signOff: o.signOff);
    await Share.shareXFiles([XFile(f.path)], text: 'MedLog');
  } catch (e) {
    if (context.mounted) snack(context, '${tr('Export failed')}: $e');
  }
}

String logbookSummaryText() {
  final b = StringBuffer();
  final cases = store.casesSorted().where((c) => !c.id.startsWith('demo_')).toList();
  b.writeln('## ${tr('Summary')}');
  b.writeln('${countLabel(cases.length, 'case')}  •  ${countLabel(store.procedures.where((p) => p['demo'] != true).length, 'procedure')}');
  b.writeln('');
  b.writeln('## ${tr('Cases')}');
  for (final c in cases) {
    b.writeln('${c.s('date')}  ${c.s('code')}  ${tr(c.s('specialty'))}  —  ${[c.s('finalDx'), c.s('workingDx')].firstWhere((e) => e.isNotEmpty, orElse: () => c.s('cc'))}');
  }
  b.writeln('');
  b.writeln('## ${tr('Procedures')}');
  for (final p in store.procedures.where((p) => p['demo'] != true)) {
    b.writeln('${p['date'] ?? ''}  ${tr('${p['name'] ?? ''}')}  —  ${tr('${p['role'] ?? ''}')}');
  }
  final ach = store.listOf('achievements');
  if (ach.isNotEmpty) {
    b.writeln('');
    b.writeln('## ${tr('Achievements')}');
    for (final a in ach) {
      b.writeln('${a['date'] ?? ''}  ${a['title'] ?? ''}  (${tr('${a['kind'] ?? ''}')})');
    }
  }
  return b.toString();
}

/// One summary page for a rotation: totals, procedures by level, the user's own targets and
/// (when [signOff]) lines for the supervisor's name, role, signature and date.
void addRotationSummary(PdfDoc d, J rot, List<CaseRec> cases, List<J> procs, {bool signOff = true}) {
  final id = rot['id'].toString();
  final start = (rot['start'] ?? '').toString();
  final end = (rot['end'] ?? '').toString();
  final sup = (rot['supervisor'] ?? '').toString();
  d.band(
    '${tr('Rotation summary')}  -  ${store.rotationLabel(rot)}',
    subtitle: _join([
      start.isEmpty ? null : '$start${end.isEmpty ? '' : '  -  $end'}',
      sup.isEmpty ? null : '${tr('Supervisor')}: $sup',
    ]),
  );
  final duty = store.shifts.where((x) => x['rotationId'] == id).length;
  final sc = cases.where((c) => isSigned(c.d)).length;
  final sp = procs.where(isSigned).length;
  d.section(tr('Totals'), icon: 'chart');
  d.table(
    [tr('Item'), tr('Total'), tr('Signed by supervisor')],
    [
      [tr('Cases'), '${cases.length}', '$sc / ${cases.length}'],
      [tr('Procedures'), '${procs.length}', '$sp / ${procs.length}'],
      [tr('Duty days'), '$duty', ''],
    ],
    weights: [2.4, 1, 1.6],
  );
  if (procs.isNotEmpty) {
    final byName = <String, List<int>>{};
    for (final p in procs) {
      final n = (p['name'] ?? '').toString();
      if (n.isEmpty) continue;
      final row = byName.putIfAbsent(n, () => List<int>.filled(5, 0));
      final st = stageOfRole((p['role'] ?? '').toString());
      row[st.clamp(0, 4)]++;
    }
    final names = byName.keys.toList()..sort();
    d.section(tr('Procedures'), icon: 'cross');
    d.table(
      [tr('Procedure'), tr('Observed'), tr('Assisted'), tr('Supervised'), tr('Independent')],
      [
        for (final n in names) [tr(n), '${byName[n]![1]}', '${byName[n]![2]}', '${byName[n]![3]}', '${byName[n]![4]}'],
      ],
      weights: [3, 1.2, 1.2, 1.3, 1.4],
    );
  }
  final goals = targetsOf(rot);
  if (goals.isNotEmpty) {
    d.section(tr('Targets'), icon: 'flag');
    final rows = <List<String>>[];
    for (final g in goals) {
      final gp = progressFor(rot, g);
      final pace = paceOf(rot, gp);
      rows.add([
        gp.label,
        '${gp.done} / ${gp.target}${gp.detail.isEmpty ? '' : '\n${gp.detail}'}',
        switch (pace) { Pace.done => tr('Done'), Pace.onTrack => tr('On track'), Pace.behind => tr('Behind'), Pace.none => '' },
      ]);
    }
    d.table([tr('Target'), tr('Progress'), tr('Status')], rows, weights: [2.2, 2.4, 1.2]);
    d.para('', tr('Targets are set by the trainee and are not official requirements.'));
  }
  if (signOff) {
    d.space(24);
    d.signLines(tr('Supervisor sign-off'), [tr('Supervisor name'), tr('Role'), tr('Signature'), tr('Date')]);
  }
}

/// Logbook as a study-sheet document: numbered sections with tables. With [opts] the entries
/// follow the chosen range, each rotation gets a summary page and sign-off columns / lines can be
/// added. Without [opts] it is the plain logbook of everything.
PdfDoc logbookDoc(bool large, {ExportOptions? opts}) {
  final d = PdfDoc(large: large);
  final o = opts ?? ExportOptions(signOff: false);
  final cases = o.cases();
  final procs = o.procedures();
  final sign = o.signOff;
  final sumRots = <J>[];
  if (opts != null) {
    final rots = [...store.rotations]..sort((a, b) => (a['start'] ?? '').toString().compareTo((b['start'] ?? '').toString()));
    for (final r in rots) {
      final id = r['id'].toString();
      if (o.range == 'rotation' && o.rotationId != id) continue;
      final has = cases.any((c) => c.s('rotationId') == id) || procs.any((p) => p['rotationId'] == id);
      if (has || (o.range == 'rotation' && o.rotationId == id)) sumRots.add(r);
    }
  }
  final summaries = sumRots.isNotEmpty;
  if (!summaries) {
    d.band(tr('MedLog logbook'), subtitle: '${countLabel(cases.length, 'case')}  •  ${countLabel(procs.length, 'procedure')}');
  }
  for (final r in sumRots) {
    final id = r['id'].toString();
    addRotationSummary(d, r, cases.where((c) => c.s('rotationId') == id).toList(),
        procs.where((p) => p['rotationId'] == id).toList(), signOff: sign);
    final ai = o.aiNarratives[id];
    if (ai != null && ai.trim().isNotEmpty) {
      d.para('${tr('AI-generated summary')} (${tr('AI-generated')})', '$ai\n${tr('Written by AI from the counts above, not reviewed. Check before use.')}');
    }
  }
  final allAi = o.aiNarratives['_all'];
  if (allAi != null && allAi.trim().isNotEmpty) {
    d.para('${tr('AI-generated summary')} (${tr('AI-generated')})', '$allAi\n${tr('Written by AI from the counts above, not reviewed. Check before use.')}');
  }
  if (cases.isNotEmpty) {
    if (summaries) d.band(tr('MedLog logbook'), subtitle: tr('Cases'));
    d.section(tr('Cases'), icon: 'list');
    d.table(
      [tr('Date'), tr('Code'), tr('Specialty'), tr('Diagnosis'), tr('Status at presentation'), if (sign) tr('Supervisor sign-off')],
      [
        for (final c in cases)
          [c.s('date'), c.s('code'), tr(c.s('specialty')), c.title, tr(clinStatusOf(c)), if (sign) signCell(c.d)]
      ],
      weights: sign ? [1.3, 1.3, 1.4, 2.0, 1.3, 1.9] : [1.5, 1.4, 1.6, 2.4, 1.6],
      rowInk: [
        for (final c in cases) ['Unstable', 'Critical'].contains(clinStatusOf(c)) ? clinStatusColor(clinStatusOf(c)) : null
      ],
    );
  }
  if (procs.isNotEmpty) {
    d.section(tr('Procedures'), icon: 'cross');
    d.table(
      [tr('Date'), tr('Procedure'), tr('My role'), if (sign) tr('Supervisor sign-off')],
      [
        for (final p in procs) ['${p['date'] ?? ''}', tr('${p['name'] ?? ''}'), tr('${p['role'] ?? ''}'), if (sign) signCell(p)]
      ],
      weights: sign ? [1.3, 2.4, 1.6, 2.0] : [1.5, 3, 1.6],
    );
  }
  if (o.range == 'all' || opts == null) {
    final ach = store.listOf('achievements');
    if (ach.isNotEmpty) {
      d.section(tr('Achievements'), icon: 'check');
      d.table(
        [tr('Date'), tr('Title'), tr('Kind')],
        [
          for (final a in ach) ['${a['date'] ?? ''}', '${a['title'] ?? ''}', tr('${a['kind'] ?? ''}')]
        ],
        weights: [1.5, 3, 1.6],
      );
    }
  }
  return d;
}

/// Asks for range / format / extras, runs the privacy gate on the chosen cases and shares the file.
Future<void> exportLogbook(BuildContext context, {String? rotationId}) async {
  final o = await askExportOptions(context, rotationId: rotationId);
  if (o == null || !context.mounted) return;
  final cases = o.cases();
  final procs = o.procedures();
  if (cases.isEmpty && procs.isEmpty) {
    snack(context, 'Nothing to export in this range.');
    return;
  }
  if (!await privacyGate(context, cases)) return;
  if (!context.mounted) return;
  try {
    if (o.format == 'csv') {
      final files = await store.exportCsv(onlyCases: cases, onlyProcs: procs, signOff: o.signOff);
      await Share.shareXFiles([for (final f in files) XFile(f.path)], text: 'MedLog logbook');
      return;
    }
    if (o.aiSummary && Ai.enabled) {
      // optional: failure or offline simply leaves the plain numbers
      final rots = [
        for (final r in store.rotations)
          if (r['demo'] != true &&
              (o.range == 'rotation' ? o.rotationId == r['id'].toString() : (cases.any((c) => c.s('rotationId') == r['id'].toString()) || procs.any((p) => p['rotationId'] == r['id'].toString()))))
            r
      ];
      for (final r in rots.take(4)) {
        if (!context.mounted) return;
        final t = await rotationNarrative(rotationStats(r), context: context);
        if (t != null) o.aiNarratives[r['id'].toString()] = t;
      }
      // one paragraph for the whole export too (all / date range, or a rotation-less logbook)
      if (context.mounted && o.range != 'rotation') {
        final t = await logbookNarrative(statsOfCases(cases, procs, title: o.range == 'dates' ? 'Selected dates' : 'All logged work'), context: context);
        if (t != null) o.aiNarratives['_all'] = t;
      }
      if (o.aiNarratives.isEmpty && context.mounted) snack(context, tr('AI is not available right now. The local tools still work.'));
    }
    final f = await writeDocPdf(logbookDoc(o.large, opts: o), tr('MedLog logbook'), fileName: 'MedLog_logbook');
    await Share.shareXFiles([XFile(f.path)], text: 'MedLog');
  } catch (e) {
    if (context.mounted) snack(context, '${tr('Export failed')}: $e');
  }
}

Future<void> exportLogbookPdf(BuildContext context) => exportLogbook(context);

/// -1 older, 0 same, 1 newer
int compareVersions(String a, String b) {
  final x = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final y = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final p = i < x.length ? x[i] : 0;
    final q = i < y.length ? y[i] : 0;
    if (p != q) return p < q ? -1 : 1;
  }
  return 0;
}

/// Latest published version, or null when it cannot be read.
Future<String?> latestVersion() async {
  final j = await _getJson(Uri.https('api.github.com', '/repos/syounis212004-sys/Medlog/releases/latest'));
  final name = '${j['name'] ?? ''} ${j['tag_name'] ?? ''}';
  return RegExp(r'\d+\.\d+\.\d+').firstMatch(name)?.group(0);
}

Future<void> checkForUpdate(BuildContext context) async {
  snack(context, tr('Checking…'));
  String? v;
  try {
    v = await latestVersion();
  } catch (_) {
    v = null;
  }
  if (!context.mounted) return;
  store.settings['updateChecked'] = nowIso();
  store.saveSettings();
  if (v == null) {
    snack(context, tr('Could not check. You may be offline.'));
    return;
  }
  if (compareVersions(kAppVersion, v) >= 0) {
    snack(context, tr('You have the latest version.'));
    return;
  }
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update_alt),
      title: Text('A new version is available'),
      content: Text(trp('Version {v} is out. Your cases stay on the phone when you install it over this one.', {'v': v!})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Open download page')),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await openUrl(context, 'https://github.com/syounis212004-sys/Medlog/releases/latest');
  }
}

// ================================================================ hub

class NotebooksScreen extends StatelessWidget {
  const NotebooksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap, {int? count}) => AppCard(
          child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(sub),
            trailing: count == null ? const Icon(Icons.chevron_right) : Text('$count'),
            onTap: onTap,
          ),
        );
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text('Notebooks and tools')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader('My notebooks'),
            tile(Icons.emoji_events_outlined, tr('Achievements'), tr('Presentations, courses, publications, awards'), () => go(const AchievementsScreen()),
                count: store.listOf('achievements').length),
            tile(Icons.self_improvement, tr('Reflection notebook'), tr('What happened, how I felt, what I learned'), () => go(const ReflectionsScreen()),
                count: store.listOf('reflections').length),
            tile(Icons.trending_up, tr('Quality improvement'), tr('Small problems, changes and results'), () => go(const QiScreen()),
                count: store.listOf('qi').length),
            tile(Icons.menu_book_outlined, tr('References and evidence'), tr('Sources behind what I learn'), () => go(const EvidenceScreen()),
                count: store.listOf('evidence').length),
            tile(Icons.local_library_outlined, tr('Library'), tr('Courses that work without internet, and the online library'), () => go(const LibraryScreen())),
            const SectionHeader('Insights'),
            tile(Icons.insights_outlined, tr('Analytics'), tr('Months, specialties, roles, confidence'), () => go(const AnalyticsScreen())),
            const SectionHeader('Online (optional)'),
            tile(Icons.travel_explore, tr('Search PubMed'), tr('Only your search words are sent'), () => go(const PubMedScreen())),
            tile(Icons.verified_outlined, tr('Trusted sites'), tr('Guidelines and references in your browser'), () => go(const TrustedSitesScreen())),
            tile(Icons.system_update_alt, tr('Check for updates'), '${tr('Version')} $kAppVersion', () => checkForUpdate(context)),
            const SectionHeader('Export'),
            tile(Icons.picture_as_pdf_outlined, tr('Export logbook (PDF or CSV)'), tr('Choose the range, add supervisor sign-off lines'), () => exportLogbook(context)),
          ],
        ),
      ),
    );
  }
}

/// Registers the hooks other screens use to open these notebooks.
void registerNotebookHooks() {
  openEvidenceHook = (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const EvidenceScreen()));
  docOpeners[DocType.evidence] = (c, id) {
    final e = store.listOf('evidence').cast<J?>().firstWhere((x) => x!['id'] == id, orElse: () => null);
    editEvidence(c, e);
  };
}
