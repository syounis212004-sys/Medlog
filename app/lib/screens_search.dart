import 'ai/ai_context.dart';
import 'screens_ai_tools.dart' show SearchAskAiCard;
import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import 'data.dart';
import 'i18n.dart';
import 'motion.dart';
import 'screens_ai_library.dart';
import 'screens_cases.dart';
import 'screens_extras.dart';
import 'screens_learn.dart';
import 'screens_library.dart';
import 'library.dart';
import 'search_index.dart';
import 'ui.dart';
import 'widgets.dart';

IconData docIcon(DocType t) {
  switch (t) {
    case DocType.caseRec:
      return Icons.folder_copy_outlined;
    case DocType.note:
      return Icons.sticky_note_2_outlined;
    case DocType.question:
      return Icons.help_outline;
    case DocType.procedure:
      return Icons.healing_outlined;
    case DocType.pearl:
      return Icons.lightbulb_outline;
    case DocType.task:
      return Icons.task_alt;
    case DocType.feedback:
      return Icons.record_voice_over_outlined;
    case DocType.evidence:
      return Icons.menu_book_outlined;
  }
}

String docTypeLabel(DocType t) {
  switch (t) {
    case DocType.caseRec:
      return 'Cases';
    case DocType.note:
      return 'Notes';
    case DocType.question:
      return 'Questions';
    case DocType.procedure:
      return 'Procedures';
    case DocType.pearl:
      return 'Pearls';
    case DocType.task:
      return 'Learning tasks';
    case DocType.feedback:
      return 'Supervisor feedback';
    case DocType.evidence:
      return 'References';
  }
}

/// Opens whatever a search hit points to. Screens added in later stages register
/// themselves in [docOpeners].
final Map<DocType, void Function(BuildContext, String)> docOpeners = {};

void openDoc(BuildContext context, Doc d) {
  switch (d.type) {
    case DocType.caseRec:
      final c = store.cases[d.id];
      if (c != null) openCase(context, c);
      return;
    case DocType.note:
      editNote(context, store.notes.cast<J?>().firstWhere((n) => n!['id'] == d.id, orElse: () => null));
      return;
    case DocType.question:
      editQuestion(context, store.inbox.cast<J?>().firstWhere((n) => n!['id'] == d.id, orElse: () => null));
      return;
    case DocType.procedure:
      editProcedure(context, store.procedures.cast<J?>().firstWhere((n) => n!['id'] == d.id, orElse: () => null));
      return;
    case DocType.pearl:
      editPearl(context, store.listOf('pearls').cast<J?>().firstWhere((n) => n!['id'] == d.id, orElse: () => null));
      return;
    case DocType.task:
      editTask(context, store.listOf('tasks').cast<J?>().firstWhere((n) => n!['id'] == d.id, orElse: () => null));
      return;
    case DocType.feedback:
    case DocType.evidence:
      final f = docOpeners[d.type];
      if (f != null) f(context, d.id);
      return;
  }
}

class HitTile extends StatelessWidget {
  final Doc doc;
  final VoidCallback? onTap;
  final Widget? trailing;
  const HitTile(this.doc, {super.key, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListTile(
        leading: doc.type == DocType.caseRec && store.cases[doc.id] != null
            ? SpecialtyAvatar(store.cases[doc.id]!.s('specialty'), size: 38)
            : Icon(docIcon(doc.type)),
        title: Text(doc.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([doc.subtitle.split(' • ').map(tr).join(' • '), if (doc.date.isNotEmpty) prettyDate(doc.date)].where((e) => e.isNotEmpty).join(' • ')),
        trailing: trailing,
        onTap: onTap ?? () => openDoc(context, doc),
      ),
    );
  }
}

// ================================================================ global search

/// Cases and notes first: "that case I logged" is the usual intent.
const List<DocType> _kGroupOrder = [
  DocType.caseRec, DocType.note, DocType.question, DocType.pearl, DocType.procedure,
  DocType.evidence, DocType.feedback, DocType.task,
];

class SearchScreen extends StatefulWidget {
  final String initial;
  const SearchScreen({super.key, this.initial = ''});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  String _q = '';
  int _libN = 0;
  // 0 = All, 1 = Logbook (my own records), 2 = Library
  int _scope = 0;

  @override
  void initState() {
    super.initState();
    _q = widget.initial;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _set(String v) {
    _c.text = v;
    _c.selection = TextSelection.collapsed(offset: v.length);
    setState(() => _q = v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hits = _q.trim().isEmpty ? <Hit>[] : searchIndex.search(_q);
    final groups = <DocType, List<Hit>>{};
    for (final h in hits) {
      (groups[h.doc.type] ??= []).add(h);
    }
    final recents = store.recentsFor('search');
    final topics = searchIndex.suggestedTopics();
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'search', title: 'Search'),
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _c,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _q = v),
          onSubmitted: (v) => store.noteUse('search', v),
          decoration: InputDecoration(
            hintText: tr('Search everything: cases, notes, questions…'),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        actions: [
          if (_q.isNotEmpty)
            IconButton(tooltip: tr('Clear'), icon: const Icon(Icons.close), onPressed: () => _set('')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          if (_q.trim().isEmpty) ...[
            if (recents.isNotEmpty) ...[
              const SectionHeader('Recent searches'),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final r in recents) ActionChip(label: Text(r), onPressed: () => _set(r)),
              ]),
            ],
            if (topics.isNotEmpty) ...[
              const SectionHeader('Your topics'),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final t in topics)
                  ActionChip(
                    avatar: const Icon(Icons.tag, size: 16),
                    label: Text(t),
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => TopicScreen(topic: t))),
                  ),
              ]),
            ],
            const SizedBox(height: 16),
            Text(
              'Works offline. It understands Arabic and English spellings and common abbreviations (MI, DKA, CAP...).',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ] else ...[
            SearchAskAiCard(query: _q),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(0, 48)),
                      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6))),
                  segments: [
                    ButtonSegment(value: 0, label: Text('All')),
                    ButtonSegment(value: 1, label: Text('Logbook')),
                    ButtonSegment(value: 2, label: Text('Library')),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (v) => setState(() => _scope = v.first),
                ),
              ),
            ),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (library.ready && library.textPacks.isNotEmpty)
                ActionChip(
                  avatar: const Icon(Icons.question_answer_outlined, size: 16),
                  label: Text('Ask about this'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AskReferencesScreen(initialQuestion: _q.trim()))),
                ),
              NlSearchChip(text: _q, onQuery: _set),
            ]),
            if (_scope != 1) AiTrySuggestions(query: _q, resultCount: _libN, onPick: _set),
            // my own records first (cases, notes ...), the library after them
            if (_scope != 2 && hits.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ActionChip(
                    avatar: const Icon(Icons.hub_outlined, size: 16),
                    label: Text('Open topic page'),
                    onPressed: () {
                      store.noteUse('search', _q);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => TopicScreen(topic: _q)));
                    },
                  ),
                ),
              ),
              for (final t in _kGroupOrder)
                if (groups[t] != null) ...[
                  SectionHeader('${tr(docTypeLabel(t))} (${groups[t]!.length})'),
                  for (var i = 0; i < groups[t]!.length && i < 12; i++)
                    FadeSlideIn(index: i, child: HitTile(groups[t]![i].doc)),
                ],
            ],
            if (_scope != 1)
              _LibrarySection(query: _q, onCount: (n) {
                if (n != _libN) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() => _libN = n) : null);
              }),
            if ((_scope == 0 && hits.isEmpty && _libN == 0) ||
                (_scope == 1 && hits.isEmpty) ||
                (_scope == 2 && _libN == 0))
              const EmptyState(kind: EmptyKind.search, title: 'Nothing found', message: 'Try another word or an abbreviation.'),
          ],
        ],
      ),
      ),
    );
  }
}

/// Articles of the downloaded library that match the search (abbreviations and typos understood).
class _LibrarySection extends StatefulWidget {
  final String query;
  final ValueChanged<int> onCount;
  const _LibrarySection({required this.query, required this.onCount});
  @override
  State<_LibrarySection> createState() => _LibrarySectionState();
}

class _LibrarySectionState extends State<_LibrarySection> {
  List<LibHit> _hits = const [];
  String? _fix;
  Timer? _t;
  String _for = '';
  String? _source;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_LibrarySection old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _schedule();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _schedule() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 280), () async {
      final q = widget.query.trim();
      if (q.isEmpty || !library.ready || library.textPacks.isEmpty) {
        if (mounted) setState(() => _hits = const []);
        widget.onCount(0);
        return;
      }
      var h = await library.searchEx(q, limit: 30, source: _source, body: store.settings['libBody'] != false);
      String? fix;
      if (h.length < 3) {
        fix = await library.didYouMean(q);
        if (fix != null) {
          final more = await library.searchEx(fix, limit: 30, source: _source);
          if (more.length > h.length) h = more;
        }
      }
      if (!mounted) return;
      // the books the user imported come first: they are what the user is looking for in their own library
      h = [...h.where((x) => library.pack(x.packId)?.kind == 'book'), ...h.where((x) => library.pack(x.packId)?.kind != 'book')];
      setState(() {
        _hits = h;
        _fix = fix;
        _for = q;
      });
      widget.onCount(h.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hits.isEmpty && _source == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader('${tr('Library')} (${_hits.length})'),
      SourceFilterChips(
        sources: library.availableSources(),
        selected: _source,
        onChanged: (v) {
          setState(() => _source = v);
          _schedule();
        },
      ),
      if (_fix != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${tr('Showing results for')}: $_fix', style: Theme.of(context).textTheme.bodySmall)),
      for (final h in _hits.take(6))
        AppCard(
          child: ListTile(
            leading: const Icon(Icons.local_library_outlined),
            title: Text(stripSource(h.title), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: hitSubtitle(h.packId, h.title, h.lead),
            onTap: () => openHit(context, h),
          ),
        ),
      if (_hits.length > 6)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryScreen(initialQuery: _for))),
            icon: const Icon(Icons.arrow_forward),
            label: Text('See all in the library'),
          ),
        ),
    ]);
  }
}

// ================================================================ topic page

/// Everything about one topic (a diagnosis, a tag, a word): cases, notes, questions...
class TopicScreen extends StatelessWidget {
  final String topic;
  const TopicScreen({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hits = searchIndex.search(topic, limit: 200);
    final groups = <DocType, List<Hit>>{};
    for (final h in hits) {
      (groups[h.doc.type] ??= []).add(h);
    }
    final order = [
      DocType.caseRec, DocType.note, DocType.question, DocType.pearl, DocType.procedure,
      DocType.evidence, DocType.feedback, DocType.task,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(topic)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final t in order)
                    if (groups[t] != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(docIcon(t), size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text('${groups[t]!.length}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(width: 4),
                        Text(docTypeLabel(t), style: theme.textTheme.bodySmall),
                      ]),
                ],
              ),
            ),
          ),
          if (hits.isEmpty)
            const EmptyState(kind: EmptyKind.search, title: 'Nothing about this topic yet'),
          for (final t in order)
            if (groups[t] != null) ...[
              SectionHeader(docTypeLabel(t)),
              for (var i = 0; i < groups[t]!.length; i++) FadeSlideIn(index: i, child: HitTile(groups[t]![i].doc)),
            ],
        ],
      ),
    );
  }
}

// ================================================================ similar cases + related knowledge

class SimilarCasesScreen extends StatelessWidget {
  final CaseRec rec;
  const SimilarCasesScreen({super.key, required this.rec});

  @override
  Widget build(BuildContext context) {
    final similar = searchIndex.similarCases(rec);
    final related = searchIndex.relatedKnowledge(rec);
    return Scaffold(
      appBar: AppBar(title: Text('${tr('Similar & related')} • ${rec.s('code')}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          const SectionHeader('Similar cases'),
          if (similar.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No similar cases yet.')),
          for (var i = 0; i < similar.length; i++)
            FadeSlideIn(
              index: i,
              child: HitTile(
                similar[i].doc,
                trailing: IconButton(
                  tooltip: tr('Compare'),
                  icon: const Icon(Icons.compare_arrows),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CompareScreen(a: rec, b: store.cases[similar[i].doc.id]!)),
                  ),
                ),
              ),
            ),
          const SectionHeader('Related notes, questions and pearls'),
          if (related.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Nothing related yet.')),
          for (var i = 0; i < related.length; i++) FadeSlideIn(index: i, child: HitTile(related[i].doc)),
        ],
      ),
    );
  }
}

/// Pick any other case to compare with.
Future<CaseRec?> pickCase(BuildContext context, {String? exclude}) {
  return showModalBottomSheet<CaseRec>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final list = store.casesSorted().where((c) => c.id != exclude).toList();
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (ctx, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(12),
          children: [
            Text('Choose a case', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final c in list)
              CaseTile(c, key: ValueKey(c.id), selecting: true, selected: false, onToggle: () => Navigator.pop(ctx, c)),
          ],
        ),
      );
    },
  );
}

// ================================================================ compare two cases

class CompareScreen extends StatelessWidget {
  final CaseRec a;
  final CaseRec b;
  const CompareScreen({super.key, required this.a, required this.b});

  String _vitals(CaseRec c) => [
        ['BP', 'v_bp'], ['HR', 'v_hr'], ['Temp', 'v_temp'], ['RR', 'v_rr'], ['SpO2', 'v_spo2'], ['RBS', 'v_rbs'],
      ].where((e) => c.s(e[1]).trim().isNotEmpty).map((e) => '${e[0]} ${c.s(e[1])}').join('\n');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rows = <List<String>>[
      ['Specialty', tr(a.s('specialty')), tr(b.s('specialty'))],
      ['Age group', tr(a.s('ageGroup')), tr(b.s('ageGroup'))],
      ['Chief complaint + duration', a.s('cc'), b.s('cc')],
      ['History of presenting illness', a.s('hpi'), b.s('hpi')],
      ['Vital signs', _vitals(a), _vitals(b)],
      ['General examination', a.s('examGeneral'), b.s('examGeneral')],
      ['Systemic examination (CVS / Resp / Abd / CNS / MSK)', a.s('examSystemic'), b.s('examSystemic')],
      ['Differential diagnosis (most likely first)', a.s('ddx'), b.s('ddx')],
      ['Working / provisional diagnosis', a.s('workingDx'), b.s('workingDx')],
      ['Final diagnosis', a.s('finalDx'), b.s('finalDx')],
      ['Red flags', a.s('redFlags'), b.s('redFlags')],
      ['What I learned', a.s('learned'), b.s('learned')],
      ['Mistakes / near-misses (mine or others) — for learning', a.s('mistakes'), b.s('mistakes')],
    ].where((r) => r[1].trim().isNotEmpty || r[2].trim().isNotEmpty).toList();
    final shared = tokens('${a.s('workingDx')} ${a.s('finalDx')} ${a.s('cc')}')
        .toSet()
        .intersection(tokens('${b.s('workingDx')} ${b.s('finalDx')} ${b.s('cc')}').toSet());
    return Scaffold(
      appBar: AppBar(title: Text('Compare')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Row(children: [
            Expanded(child: _head(context, a)),
            const SizedBox(width: 8),
            Expanded(child: _head(context, b)),
          ]),
          if (shared.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, children: [
                Text('In common', style: theme.textTheme.labelMedium),
                for (final w in shared.take(8)) Chip(label: Text(w), visualDensity: VisualDensity.compact),
              ]),
            ),
          for (final r in rows) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text(r[0], style: theme.textTheme.labelLarge?.copyWith(color: cs.primary)),
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _cell(context, r[1])),
                  const SizedBox(width: 8),
                  Expanded(child: _cell(context, r[2])),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _head(BuildContext context, CaseRec c) => AppCard(
        child: ListTile(
          dense: true,
          leading: SpecialtyAvatar(c.s('specialty'), size: 34),
          title: Text(c.s('code')),
          subtitle: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => openCase(context, c),
        ),
      );

  Widget _cell(BuildContext context, String t) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Text(t.trim().isEmpty ? '—' : t, style: Theme.of(context).textTheme.bodyMedium),
      );
}
