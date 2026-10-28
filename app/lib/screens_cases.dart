import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'data.dart';
import 'i18n.dart';
import 'motion.dart';
import 'quick_add.dart';
import 'pdf_export.dart' show kClinStatuses, clinStatusOf, clinStatusColor, clinStatusOnColor;
import 'privacy.dart';
import 'screens_privacy.dart';
import 'ai/ai_context.dart';
import 'screens_ai_cases.dart';
import 'ai/ai_tools.dart' show untaggedCases;
import 'screens_ai_tools.dart';
import 'screens_ai_library.dart' show NlSearchChip;
import 'screens_trainer.dart';
import 'lib_user.dart';
import 'screens_library.dart';
import 'screens_notebooks.dart';
import 'case_scores.dart';
import 'dose_context.dart';
import 'screens_calc.dart';
import 'screens_choices.dart';
import 'choices_engine.dart' show ChoicesSync;
import 'screens_dosing.dart';
import 'screens_images.dart';
import 'screens_review.dart';
import 'screens_search.dart';
import 'screens_case_extras.dart';
import 'templates.dart';
import 'templates_user.dart';
import 'ui.dart';
import 'widgets.dart';

void openNewCase(BuildContext context, {String? date}) {
  final c = store.newCase();
  if (date != null) c.set('date', date);
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: c)),
  );
}

void openCase(BuildContext context, CaseRec c) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CaseEditorScreen(rec: c)),
  );
}

// ================================================================ cases list

/// Small coloured pill for the status at presentation (Stable / Improving / Unstable / Critical).
class ClinStatusChip extends StatelessWidget {
  final String status;
  const ClinStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: clinStatusColor(status), borderRadius: BorderRadius.circular(10)),
      child: Text(status,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: clinStatusOnColor(status), fontWeight: FontWeight.w700)),
    );
  }
}

class CaseTile extends StatelessWidget {
  final CaseRec c;
  final bool selected;
  final bool selecting;
  final VoidCallback? onToggle;
  final EdgeInsetsGeometry margin;
  const CaseTile(this.c,
      {super.key,
      this.selected = false,
      this.selecting = false,
      this.onToggle,
      this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 4)});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = c.s('specialty');
    final age = c.s('ageGroup');
    final initials =
        store.useInitials && c.s('initials').isNotEmpty ? c.s('initials') : '';
    final head = [
      c.s('code'),
      if (initials.isNotEmpty) initials,
      if (age.isNotEmpty) tr(age)
    ].join(' • ');
    final sub =
        [tr(spec), tr(c.s('setting'))].where((e) => e.isNotEmpty).join(' • ');
    final tags = c.tags;
    final by = c.shared && c.s('author').isNotEmpty
        ? trp('by {name}', {'name': c.s('author')})
        : '';
    return AppCard(
      margin: margin,
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: selecting ? onToggle : () => openCase(context, c),
        onLongPress: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SpecialtyAvatar(spec, selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(head, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 2),
                    Text(c.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge),
                    if (sub.isNotEmpty || by.isNotEmpty)
                      Text([sub, by].where((e) => e.isNotEmpty).join(' • '),
                          style: theme.textTheme.bodySmall),
                    if (tags.isNotEmpty)
                      Text(tags.map(tagLabel).join('  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.primary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c.shared)
                        const Icon(Icons.people_alt_outlined, size: 16),
                      if (c.starred)
                        const Icon(Icons.star, size: 18, color: Colors.amber),
                      if (c.review) const Icon(Icons.bookmark, size: 18),
                    ],
                  ),
                  const SizedBox(height: 4),
                  StatusDot(c.s('status')),
                  if (clinStatusOf(c).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ClinStatusChip(clinStatusOf(c)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  String _q = '';
  String _status = '';
  String _rotation = '';
  bool _starred = false;
  bool _review = false;
  bool _others = false;
  bool _urgent = false;
  final Set<String> _sel = {};
  bool _busy = false;
  Timer? _debounce;
  final TextEditingController _qc = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _qc.dispose();
    super.dispose();
  }

  List<CaseRec> _filtered() {
    return store.casesSorted().where((c) {
      if (_status.isNotEmpty && c.s('status') != _status) return false;
      if (_rotation.isNotEmpty && c.s('rotationId') != _rotation) return false;
      if (_starred && !c.starred) return false;
      if (_review && !c.review) return false;
      if (_others && !c.shared) return false;
      if (_urgent && !const ['Unstable', 'Critical'].contains(clinStatusOf(c))) return false;
      return matchesQuery(c, _q);
    }).toList();
  }

  int get _filterCount => [_status.isNotEmpty, _rotation.isNotEmpty, _starred, _review, _others, _urgent].where((e) => e).length;

  void _clearFilters() => setState(() {
        _status = '';
        _rotation = '';
        _starred = _review = _others = _urgent = false;
      });

  Widget _filterButton() {
    final n = _filterCount;
    return IconButton(
      key: const Key('cases_filter'),
      tooltip: tr('Filter'),
      onPressed: _openFilters,
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        child: Icon(n > 0 ? Icons.filter_alt : Icons.filter_alt_outlined),
      ),
    );
  }

  /// One compact line with what is filtered now (nothing at all when no filter is on).
  Widget _activeFilters() {
    if (_filterCount == 0) return const SizedBox.shrink();
    String rot() {
      for (final r in store.rotations) {
        if (r['id'].toString() == _rotation) return store.rotationLabel(r);
      }
      return '';
    }

    InputChip chip(String label, VoidCallback off) => InputChip(
          label: Text(label),
          visualDensity: VisualDensity.compact,
          onDeleted: () => setState(off),
          onPressed: _openFilters,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _row([
        if (_starred) chip(tr('Starred'), () => _starred = false),
        if (_review) chip(tr('To review'), () => _review = false),
        if (_urgent) chip(tr('Unstable / Critical'), () => _urgent = false),
        if (_others) chip(tr('From others'), () => _others = false),
        if (_status.isNotEmpty) chip(trUi(_status), () => _status = ''),
        if (_rotation.isNotEmpty && rot().isNotEmpty) chip(rot(), () => _rotation = ''),
        TextButton(onPressed: _clearFilters, child: Text('Clear all')),
      ]),
    );
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        void upd(VoidCallback f) {
          setState(f);
          set(() {});
        }

        Widget group(String title, List<Widget> chips) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: chips),
              ]),
            );
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                group(tr('Show only'), [
                  FilterChip(label: Text('Starred'), selected: _starred, onSelected: (v) => upd(() => _starred = v)),
                  FilterChip(label: Text('To review'), selected: _review, onSelected: (v) => upd(() => _review = v)),
                  FilterChip(label: Text('Unstable / Critical'), selected: _urgent, onSelected: (v) => upd(() => _urgent = v)),
                  FilterChip(label: Text('From others'), selected: _others, onSelected: (v) => upd(() => _others = v)),
                ]),
                group(tr('Status'), [
                  for (final st in const ['Draft', 'Active', 'Discharged', 'Referred', 'Completed'])
                    ChoiceChip(label: Text(trUi(st)), selected: _status == st, onSelected: (v) => upd(() => _status = v ? st : '')),
                ]),
                if (store.rotations.isNotEmpty)
                  group(tr('Rotation'), [
                    for (final r in store.rotations)
                      ChoiceChip(
                        label: Text(store.rotationLabel(r)),
                        selected: _rotation == r['id'].toString(),
                        onSelected: (v) => upd(() => _rotation = v ? r['id'].toString() : ''),
                      ),
                  ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(children: [
                    TextButton(onPressed: _filterCount == 0 ? null : () { _clearFilters(); set(() {}); }, child: Text('Clear all')),
                    const Spacer(),
                    FilledButton(onPressed: () => Navigator.pop(ctx), child: Text('Done')),
                  ]),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _row(List<Widget> items) {
    // intrinsic height: chips grow with the text size instead of being clipped
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final w in items)
            Padding(
                padding: const EdgeInsetsDirectional.only(end: 8), child: w),
        ],
      ),
    );
  }

  /// The only other search entry: library, notes and questions, from the same words.
  Widget _everywhereTile() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: AppCard(
          child: ListTile(
            leading: const Icon(Icons.manage_search),
            title: Text('Search everything'),
            subtitle: Text(_q.trim(), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SearchScreen(initial: _q.trim()))),
          ),
        ),
      );

  void _toggle(String id) {
    setState(() {
      if (!_sel.remove(id)) _sel.add(id);
    });
  }

  Future<void> _sharePack() async {
    final chosen =
        _sel.map((id) => store.cases[id]).whereType<CaseRec>().toList();
    if (chosen.isEmpty) return;
    if (!await privacyGate(context, chosen)) return;
    if (!mounted) return;
    final opt = await askPackOptions(context, chosen.length);
    if (opt == null) return;
    setState(() => _busy = true);
    try {
      final f = await store.exportPack(chosen, opt.password,
          images: opt.images, learning: opt.learning);
      await Share.shareXFiles([XFile(f.path)], text: 'MedLog cases');
      if (mounted) setState(() => _sel.clear());
    } catch (e) {
      if (mounted) snack(context, '${tr('Could not share')}: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _exportPdf() async {
    final chosen = _sel.map((id) => store.cases[id]).whereType<CaseRec>().toList();
    if (chosen.isEmpty) return;
    chosen.sort((a, b) => b.s('date').compareTo(a.s('date')));
    await exportCasesPdf(context, chosen);
  }

  /// AI tools of the case list. Every entry opens a screen that explains when AI is off or offline.
  void _aiMenu() {
    void go(Widget w) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => w));
    }

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              key: const ValueKey('cases_ai_tags'),
              leading: const Icon(Icons.sell_outlined),
              title: Text('Suggest tags for my untagged cases'),
              subtitle: Text(trp('{n} cases have no tags.', {'n': untaggedCases().length})),
              onTap: () => go(const BulkTagsScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: Text('Which score fits this case?'),
              onTap: () => go(const WhichScoreScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.medication_outlined),
              title: Text('Drug check'),
              onTap: () => go(const DrugCheckScreen()),
            ),
            AiStateBuilder(
              builder: (context, enabled, online) => enabled
                  ? const SizedBox.shrink()
                  : ListTile(
                      leading: const Icon(Icons.power_settings_new),
                      title: Text('Turn on AI'),
                      subtitle: Text('AI is off. MedLog works fully without it.'),
                      onTap: () {
                        Navigator.pop(ctx);
                        openAiSettings(context);
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  void _help() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search codes', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Write several words: all of them must match.\n'
                'Use _ for a space, and a minus to exclude.'),
            const SizedBox(height: 12),
            Directionality(
              textDirection: TextDirection.ltr,
              child: m.Text(
                'dx:pneumonia          diagnosis / DDx\n'
                'dx:heart_failure\n'
                '#rare   or   tag:rare\n'
                'spec:MED   spec:peds\n'
                'status:active   role:independent\n'
                'date:2026-10   (month)   date:2026-10-21\n'
                'cc:chest_pain   code:MED-00\n'
                'age:child   setting:er\n'
                'by:ahmad   (cases shared by someone)\n'
                'has:image  has:pending  has:allergy\n'
                'has:question  has:plan  has:progress\n'
                'is:starred  is:review  is:shared  is:draft\n'
                'learn:word\n\n'
                'Examples:\n'
                'spec:MED dx:pneumonia has:image\n'
                'is:review -status:draft\n'
                '#rare date:2026-10',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final list = _filtered();
        final perDay = <String, int>{};
        for (final c in list) {
          perDay[c.s('date')] = (perDay[c.s('date')] ?? 0) + 1;
        }
        // flat list of items: String = day header, CaseRec = case
        final items = <Object>[];
        String lastDate = '';
        for (final c in list) {
          final d = c.s('date');
          if (d != lastDate) {
            lastDate = d;
            items.add(d);
          }
          items.add(c);
        }
        final selecting = _sel.isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            title: Text(selecting
                ? trp('{n} selected', {'n': _sel.length})
                : '${tr('Cases')} (${list.length})'),
            leading: selecting
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _sel.clear()),
                  )
                : null,
            actions: [
              if (selecting) ...[
                IconButton(
                  tooltip: 'Select all shown',
                  icon: const Icon(Icons.select_all),
                  onPressed: () => setState(() {
                    for (final c in list) {
                      _sel.add(c.id);
                    }
                  }),
                ),
                IconButton(
                  tooltip: tr('Export as PDF'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: _busy ? null : _exportPdf,
                ),
                IconButton(
                  tooltip: 'Share with colleagues',
                  icon: const Icon(Icons.ios_share),
                  onPressed: _busy ? null : _sharePack,
                ),
              ] else ...[
                AiChipButton(key: const ValueKey('cases_ai_chip'), tooltip: 'AI tools', onTap: _aiMenu),
                IconButton(
                  tooltip: 'Search help',
                  icon: const Icon(Icons.help_outline),
                  onPressed: _help,
                ),
              ],
            ],
          ),
          body: Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: TextField(
                  controller: _qc,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr('Search… try  spec:MED dx:pneumonia #rare'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    suffixIcon: _filterButton(),
                  ),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 180), () {
                      if (mounted) setState(() => _q = v);
                    });
                  },
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12),
                  child: NlSearchChip(
                    text: _q,
                    forCases: true,
                    onQuery: (q) {
                      _qc.text = q;
                      setState(() => _q = q);
                    },
                  ),
                ),
              ),
              _activeFilters(),
              Expanded(
                child: items.isEmpty
                    ? (store.cases.isEmpty
                        ? EmptyState(
                            kind: EmptyKind.cases,
                            title: 'No cases yet',
                            message: 'Tap + to log your first case.',
                            action: FilledButton.icon(
                              onPressed: () => showQuickAdd(context),
                              icon: const Icon(Icons.add),
                              label: Text('New case'),
                            ),
                          )
                        : ListView(children: [
                            const EmptyState(
                              kind: EmptyKind.search,
                              title: 'No cases found',
                              message: 'Try fewer filters or a different search.',
                            ),
                            if (_q.trim().isNotEmpty) _everywhereTile(),
                          ]))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: items.length + (_q.trim().isEmpty ? 0 : 1),
                        itemBuilder: (context, i) {
                          final hasTile = _q.trim().isNotEmpty;
                          if (hasTile && i == 0) return _everywhereTile();
                          final it = items[hasTile ? i - 1 : i];
                          if (it is String) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                '${prettyDate(it)} • ${countLabel(perDay[it] ?? 0, 'case')}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            );
                          }
                          final c = it as CaseRec;
                          return FadeSlideIn(
                            key: ValueKey(c.id),
                            index: i > 8 ? 0 : i,
                            child: CaseTile(
                              c,
                              selecting: selecting,
                              selected: _sel.contains(c.id),
                              onToggle: () => _toggle(c.id),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ================================================================ case editor

class CaseEditorScreen extends StatefulWidget {
  final CaseRec rec;
  final int initialTab;
  const CaseEditorScreen({super.key, required this.rec, this.initialTab = 0});

  @override
  State<CaseEditorScreen> createState() => _CaseEditorScreenState();
}

enum _SaveState { saved, saving, failed }

class _CaseEditorScreenState extends State<CaseEditorScreen>
    with WidgetsBindingObserver {
  final Map<String, TextEditingController> _ctl = {};
  Timer? _timer;
  bool _dirty = false;
  bool _warnedImages = false;
  _SaveState _save = _SaveState.saved;
  bool _failedShown = false;
  String _saveError = '';
  // undo: snapshots of the record taken before each burst of typing
  final List<String> _undo = [];
  String _baseline = '';
  bool _burst = false;
  // refreshes only the app bar (save status, Undo) while typing, not the whole form
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  CaseRec get rec => widget.rec;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _baseline = jsonEncode(rec.d);
    // remember where I was, so Home can offer "continue where you left off"
    store.settings['lastCase'] = rec.id;
    store.settings['lastCaseAt'] = nowIso();
    store.settings['lastTab'] = widget.initialTab;
    store.saveSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) _flush();
  }

  // The nine pages of a case live in five tabs; the pages of a tab are chosen with the chips on top of it.
  // Page numbers: 0 Info, 1 History, 2 Exam, 3 Investigations, 4 Assessment, 5 Management, 6 Progress, 7 Learning, 8 Timeline.
  static const List<List<int>> _groups = [
    [0],
    [1, 2, 3],
    [4, 5],
    [6, 8],
    [7],
  ];
  late final List<int> _sub = [for (var g = 0; g < _groups.length; g++) _groups[g].contains(widget.initialTab) ? _groups[g].indexOf(widget.initialTab) : 0];

  static int _groupOf(int page) => _groups.indexWhere((g) => g.contains(page));

  void _rememberTab(int g) {
    store.settings['lastTab'] = _groups[g][_sub[g]];
    store.saveSettings();
  }

  /// Goes to a page: its tab opens and the page is chosen in it.
  void _goPage(BuildContext ctx, int page) {
    final g = _groupOf(page);
    if (g < 0) return;
    setState(() => _sub[g] = _groups[g].indexOf(page));
    DefaultTabController.of(ctx).animateTo(g);
    store.settings['lastTab'] = page;
    store.saveSettings();
  }

  Widget _pageOf(int page) => switch (page) {
        0 => _info(),
        1 => _history(),
        2 => _exam(),
        3 => _inv(),
        4 => _assess(),
        5 => _mgmt(),
        6 => _progress(),
        7 => _learn(),
        _ => _timeline(),
      };

  static const List<(IconData, String)> _pageChip = [
    (Icons.assignment_ind_outlined, 'Info'),
    (Icons.forum_outlined, 'History'),
    (Icons.monitor_heart_outlined, 'Exam'),
    (Icons.biotech_outlined, 'Investigations'),
    (Icons.psychology_outlined, 'Assessment'),
    (Icons.healing_outlined, 'Management'),
    (Icons.trending_up_outlined, 'Progress'),
    (Icons.school_outlined, 'Learning'),
    (Icons.timeline_outlined, 'Timeline'),
  ];

  /// One tab: its page, with the chips that switch between its pages when it has several.
  Widget _group(int g, List<bool> filled) {
    final pages = _groups[g];
    if (pages.length == 1) return _pageOf(pages[0]);
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          for (var i = 0; i < pages.length; i++)
            Expanded(child: Padding(padding: EdgeInsetsDirectional.only(end: i == pages.length - 1 ? 0 : 6), child: ChoiceChip(
              visualDensity: VisualDensity.compact,
              labelPadding: const EdgeInsets.symmetric(horizontal: 2),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              key: ValueKey('page_${pages[i]}'),
              avatar: Stack(clipBehavior: Clip.none, children: [
                Icon(_pageChip[pages[i]].$1, size: 18),
                if (filled[pages[i]])
                  PositionedDirectional(
                    top: -2,
                    end: -4,
                    child: Container(width: 7, height: 7, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: cs.surface, width: 1))),
                  ),
              ]),
              label: FittedBox(fit: BoxFit.scaleDown, child: Text(trUi(_pageChip[pages[i]].$2))),
              selected: _sub[g] == i,
              showCheckmark: false,
              onSelected: (_) {
                setState(() => _sub[g] = i);
                _rememberTab(g);
              },
            ))),
        ]),
      ),
      Expanded(child: KeyedSubtree(key: ValueKey('grp_${g}_${_sub[g]}'), child: _pageOf(pages[_sub[g]]))),
    ]);
  }

  /// Always at hand under every page: the library, the calculators, the doses and the search, for this case.
  Widget _toolsBar() {
    final topic = [rec.s('finalDx'), rec.s('workingDx'), rec.s('cc')].firstWhere((e) => e.trim().isNotEmpty, orElse: () => '');
    Widget tool(IconData icon, String label, VoidCallback onTap, {String? key}) => Expanded(
          child: InkWell(
            key: key == null ? null : ValueKey(key),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 22),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        );
    Future<void> open(Widget Function() page) async {
      await _flush();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => page()));
      if (mounted) setState(() {});
    }

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Row(children: [
          tool(Icons.menu_book_outlined, trUi('Library'), () => open(() => LibraryScreen(initialQuery: topic)), key: 'tool_library'),
          tool(Icons.calculate_outlined, trUi('Calculators'), () => open(() => CalculatorsScreen(attachTo: rec)), key: 'tool_calcs'),
          tool(Icons.medication_outlined, trUi('Doses'), () => open(() => DosingScreen(patient: DoseContext.fromCase(rec))), key: 'tool_doses'),
          tool(Icons.search_outlined, trUi('Search'), () => open(() => SearchScreen(initial: topic)), key: 'tool_search'),
        ]),
      ),
    );
  }

  void _doUndo() {
    if (_undo.isEmpty) return;
    final snap = _undo.removeLast();
    final m = jsonDecode(snap) as Map;
    rec.d
      ..clear()
      ..addAll(Map<String, dynamic>.from(m));
    _ctl.forEach((k, c) => c.text = rec.s(k));
    _baseline = jsonEncode(rec.d);
    _burst = false;
    _dirty = true;
    _touched = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), _flush);
    _save = _SaveState.saving;
    _tick.value++;
    setState(() {});
  }

  /// A value derived from the quick choices (diagnosis fields, red flags): store it and show it in its field.
  void _writeDerived(String key, String value) {
    rec.set(key, value);
    _tc(key).text = value;
  }

  TextEditingController _tc(String key) =>
      _ctl.putIfAbsent(key, () => TextEditingController(text: rec.s(key)));

  bool _touched = false;

  void _changed({bool rebuild = true}) {
    if (!_burst) {
      // first change after a pause: keep the state from before it, for Undo
      _burst = true;
      _undo.add(_baseline);
      if (_undo.length > 30) _undo.removeAt(0);
    }
    _dirty = true;
    _touched = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), _flush);
    _save = _SaveState.saving;
    _tick.value++;
    if (rebuild && mounted) setState(() {});
  }

  Future<void> _flush() async {
    _timer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    try {
      await store.saveCase(rec, notify: false);
      _baseline = jsonEncode(rec.d);
      _burst = false;
      _save = _SaveState.saved;
      _tick.value++;
      if (mounted && _failedShown) setState(() => _failedShown = false);
    } catch (e) {
      _dirty = true; // keep it so a retry (or leaving the screen) tries again
      _saveError = '$e';
      _save = _SaveState.failed;
      _tick.value++;
      if (mounted) setState(() => _failedShown = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick.dispose();
    _timer?.cancel();
    final touched = _touched;
    Future<void> done;
    if (_dirty) {
      _dirty = false;
      done = store.saveCase(rec, notify: false);
    } else {
      done = Future<void>.value();
    }
    if (touched) {
      done.then((_) => store.refresh());
    }
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ builders

  /// "Unknown / Not assessed / Pending" markers: an empty field is not the same
  /// as "I did not ask" or "waiting for the result".
  Widget _uncRow(String key) {
    final cur = rec.s('st_$key');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        children: [
          for (final o in const ['Unknown', 'Not assessed', 'Pending'])
            FilterChip(
              label: Text(o),
              selected: cur == o,
              onSelected: (v) {
                rec.set('st_$key', v ? o : '');
                _changed();
              },
            ),
        ],
      ),
    );
  }

  Widget _tf(String key, String label,
      {int lines = 1, String hint = '', TextInputType? kt, bool unc = false}) {
    final field = _tfField(key, label, lines: lines, hint: hint, kt: kt);
    if (!unc) return field;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [field, _uncRow(key)]),
    );
  }

  Widget _tfField(String key, String label,
      {int lines = 1, String hint = '', TextInputType? kt}) {
    final field = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _tc(key),
        // empty: at most 2 lines; it grows with what is typed
        minLines: lines >= 4 ? 2 : 1,
        maxLines: lines == 1 ? 1 : null,
        keyboardType: lines > 1 ? TextInputType.multiline : kt,
        textCapitalization: TextCapitalization.sentences,
        // English text keeps its own direction inside the Arabic app (": ()" stay in place)
        textDirection: isAr ? textDirectionFor(_tc(key).text) : null,
        decoration: InputDecoration(
          labelText: tr(label),
          hintText: hint.isEmpty ? null : tr(hint),
          alignLabelWithHint: true,
        ),
        onChanged: (v) {
          final wasEmpty = rec.s(key).isEmpty;
          final wasAuto = _isAuto(key);
          rec.set(key, v);
          _changed(
              rebuild: wasEmpty != v.isEmpty ||
                  key == 'allergies' ||
                  wasAuto != _isAuto(key));
        },
      ),
    );
    if (!_isAuto(key)) return field;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        field,
        Transform.translate(offset: const Offset(0, -8), child: _autoHint()),
      ]),
    );
  }

  Widget _choice(String key, String label, List<String> options,
      {void Function(String)? onPick,
      String Function(String)? labelOf,
      bool keepOrder = false,
      Widget? trailing}) {
    final cur = rec.s(key);
    // long lists: the options used last come first
    var ordered = options;
    if (options.length > 8 && !keepOrder) {
      final r = store.recentsFor(key).where(options.contains).toList();
      ordered = [...r, ...options.where((e) => !r.contains(e))];
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final o in ordered)
                ChoiceChip(
                  label: Text(labelOf == null ? o : labelOf(o)),
                  selected: cur == o,
                  onSelected: (_) {
                    final v = cur == o ? '' : o;
                    if (v.isNotEmpty && kSpecialtyNames.length > 8 && key == 'specialty') {
                      store.noteUse(key, v);
                    } else if (v.isNotEmpty && options.length > 8) {
                      store.noteUse(key, v);
                    }
                    rec.set(key, v);
                    if (onPick != null) onPick(v);
                    _changed();
                  },
                ),
              if (trailing != null) trailing,
            ],
          ),
        ],
      ),
    );
  }

  /// A row of phrases to tap, scrolling sideways (a wall of chips used to fill the screen).
  Widget _chipRow(List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [for (final c in chips) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: c)]),
        ),
      );

  Widget _quick(String key, List<String> items) {
    return _chipRow([
      for (final t in items)
        ActionChip(
          label: Text(t),
          visualDensity: VisualDensity.compact,
          onPressed: () {
            final c = _tc(key);
            final cur = c.text.trim();
            c.text = cur.isEmpty ? t : '$cur; $t';
            rec.set(key, c.text);
            _changed();
          },
        ),
    ]);
  }

  Widget _banner(String text, {IconData icon = Icons.shield_outlined}) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
                child:
                    Text(text, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }

  bool _specMore = false;

  /// Five specialties first (current rotation, the one chosen, recent), the rest behind "More".
  Widget _specialtyPicker() {
    final rot = store.currentRotation();
    final rotName = rot == null ? '' : (rot['name'] ?? '').toString();
    final cur = rec.s('specialty');
    final recents = store.recentsFor('specialty').where(kSpecialtyNames.contains);
    final ordered = <String>{
      if (kSpecialtyNames.contains(rotName)) rotName,
      if (kSpecialtyNames.contains(cur)) cur,
      ...recents,
      ...kSpecialtyNames,
    }.toList();
    final shown = _specMore ? ordered : ordered.take(5).toList();
    return _choice(
      'specialty',
      'Specialty',
      shown,
      keepOrder: true,
      onPick: (v) {
        if (v.isNotEmpty) {
          final p = prefixFor(v);
          if (!rec.s('code').startsWith('$p-')) {
            rec.set('code', store.nextCode(p));
          }
        }
      },
      trailing: ActionChip(
        key: const ValueKey('spec_more'),
        avatar: Icon(_specMore ? Icons.expand_less : Icons.expand_more, size: 18),
        label: Text(_specMore ? 'Less' : 'More'),
        onPressed: () => setState(() => _specMore = !_specMore),
      ),
    );
  }

  /// Guides the flow: one tap to the next section.
  Widget _next(int from) {
    const names = [
      'Info',
      'History',
      'Exam',
      'Investigations',
      'Assessment',
      'Management',
      'Progress',
      'Learning',
      'Timeline'
    ];
    if (from >= names.length - 1) return const SizedBox(height: 24);
    return Builder(builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.tonalIcon(
            onPressed: () => _goPage(ctx, from + 1),
            icon: const Icon(Icons.arrow_forward),
            iconAlignment: IconAlignment.end,
            label: Text('${trUi('Next')}: ${trUi(names[from + 1])}'),
          ),
        ),
      );
    });
  }

  /// Optional fields live in a collapsible block so the screen stays short.
  Widget _more(String title, List<Widget> children, {bool open = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: open,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          collapsedShape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          collapsedBackgroundColor:
              Theme.of(context).colorScheme.surfaceContainerLow,
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          children: children,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ tabs

  Widget _info() {
    final tags = rec.tags;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (scanCase(rec).isNotEmpty)
          AppCard(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(trp('{n} possible identifiers found',
                  {'n': scanCase(rec).length})),
              subtitle: Text('Tap to review before sharing'),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => PrivacyCheckScreen(rec: rec))),
            ),
          ),
        if (rec.shared)
          _banner(
              '${rec.s('author').isEmpty ? tr('Shared with you.') : trp('Shared with you by {name}.', {
                      'name': rec.s('author')
                    })} '
              '${tr('You can add your own notes. A newer version from the sender replaces this copy.')}',
              icon: Icons.people_alt_outlined),
        // code + date first: the two things every entry needs
        Builder(builder: (context) {
          final big = MediaQuery.textScalerOf(context).scale(1.0) > 1.15;
          final codeCol = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rec.s('code'),
                  maxLines: 1, style: Theme.of(context).textTheme.headlineSmall),
              Text('Case code (automatic)',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          );
          final dateBtn = OutlinedButton.icon(
            key: const ValueKey('info_date'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(rec.s('date').isEmpty ? '—' : prettyDate(rec.s('date'))),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: parseDate(rec.s('date')) ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null) {
                rec.set('date', fmtDate(d));
                _changed();
              }
            },
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: big
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [codeCol, const SizedBox(height: 8), dateBtn])
                : Row(children: [Expanded(child: codeCol), dateBtn]),
          );
        }),
        const SizedBox(height: 8),
        _choice('setting', 'Setting',
            const ['ER', 'Clinic', 'Ward', 'ICU', 'OR']),
        if (store.useInitials)
          _tf('initials', 'Patient initials (stays on this phone)',
              hint: 'M.K.'),
        _choice('ageGroup', 'Age group', const ['Child', 'Adult']),
        _choice('sex', 'Sex (only if clinically relevant)', const ['M', 'F']),
        _specialtyPicker(),
        if (store.rotations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rotation', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final r in store.rotations)
                      ChoiceChip(
                        label: Text(store.rotationLabel(r)),
                        selected: rec.s('rotationId') == r['id'],
                        onSelected: (sel) {
                          rec.set('rotationId', sel ? r['id'].toString() : '');
                          _changed();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        _choice('status', 'Status',
            const ['Draft', 'Active', 'Discharged', 'Referred', 'Completed'],
            labelOf: trUi),
        _choice('cstatus', 'Status at presentation (optional)', kClinStatuses),
        _choice('role', 'My role',
            const ['Observed', 'Assisted', 'Supervised', 'Independent']),
        _more(
          'More details',
          [
            _choice('encounter', 'Encounter',
                const ['New admission', 'Follow-up', 'Consultation']),
          ],
          open: rec.s('encounter').isNotEmpty,
        ),
        _banner(store.useInitials
            ? tr(
                'Initials only (e.g. M.K.). No names, ID numbers or exact ages. '
                'Cover any name on photos before taking them.')
            : tr('No names, initials, ID numbers or exact ages are stored. '
                'Use the case code to recognise a patient. Cover any name on photos.')),
        const SectionHeader('Tags'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in tags)
              InputChip(
                label: Text(tagLabel(t)),
                onDeleted: () {
                  final l = rec.tags;
                  l.remove(t);
                  rec.tags = l;
                  _changed();
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Tag'),
              onPressed: () async {
                final t = await askText(context, 'New tag', hint: 'e.g. rare');
                if (t != null && t.trim().isNotEmpty) {
                  final l = rec.tags;
                  final clean =
                      t.trim().replaceAll('#', '').replaceAll(' ', '_');
                  if (!l.contains(clean)) l.add(clean);
                  rec.tags = l;
                  _changed();
                }
              },
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final t in const [
              'interesting',
              'rare',
              'exam_case',
              'to_present'
            ])
              if (!tags.contains(t))
                ActionChip(
                  label: Text(tagLabel(t)),
                  onPressed: () {
                    final l = rec.tags;
                    l.add(t);
                    rec.tags = l;
                    _changed();
                  },
                ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Starred'),
          value: rec.starred,
          onChanged: (v) {
            rec.set('starred', v);
            _changed();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('To review later'),
          value: rec.review,
          onChanged: (v) {
            rec.set('review', v);
            _changed();
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Never send this case to AI'),
          subtitle: const Text('The AI assistant skips this case completely.'),
          value: rec.d['aiNever'] == true,
          onChanged: (v) {
            if (v) {
              rec.set('aiNever', true);
            } else {
              rec.d.remove('aiNever');
            }
            _changed();
          },
        ),
        PatientSection(
          rec: rec,
          onChanged: _changed,
          pick: () => pickCase(context, exclude: rec.id),
          open: (c) => openCase(context, c),
        ),
        _next(0),
      ],
    );
  }

  Widget _history() {
    final al = rec.s('allergies').trim().toLowerCase();
    final hasAllergy =
        al.isNotEmpty && !const ['nkda', 'none', 'no', 'nka'].contains(al);
    final extra = specialtyFieldsFor(rec.s('specialty'));
    final mine = [for (final t in templatesFor(rec.s('specialty'))) if (t.mine) t];
    final fromChoices = ChoicesSync.historyText(rec);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _fillNormalButton(history: true),
        _tf('cc', 'Chief complaint + duration', lines: 2),
        ChoicesSection(rec: rec, section: 'History', onChanged: _changed, write: _writeDerived),
        _tf('allergies', 'Allergies', hint: 'NKDA or list', unc: true),
        if (hasAllergy)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${tr('ALLERGY')}: ${rec.s('allergies')}',
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        // everything written in words lives in one folded block: the questions above already cover it
        _more(
          'Written history',
          [
            _tf('hpi', 'History of presenting illness', lines: 6),
            if (fromChoices.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('hpi_from_choices'),
                  onPressed: () {
                    final c = _tc('hpi');
                    if (!c.text.contains(fromChoices)) c.text = c.text.trim().isEmpty ? fromChoices : '${c.text.trim()}\n$fromChoices';
                    rec.set('hpi', c.text);
                    _changed();
                  },
                  icon: const Icon(Icons.subdirectory_arrow_left, size: 18),
                  label: Text('Add my answers to the text'),
                ),
              ),
            _tf('pmh', 'Past medical history', lines: 2, unc: true),
            _tf('drugs', 'Drug history (name, dose)', lines: 2, unc: true),
            _tf('psh', 'Past surgical history', lines: 2),
            _tf('family', 'Family history', lines: 2, unc: true),
            _tf('social', 'Social history (smoking, occupation...)', lines: 2),
            _tf('ros', 'Review of systems', lines: 3),
            _quick('ros', const [
              'ROS negative except as above',
              'Fever',
              'Weight loss',
              'Cough',
              'SOB',
              'Chest pain',
              'Palpitations',
              'Nausea/vomiting',
              'Diarrhea',
              'Constipation',
              'Dysuria',
              'Headache',
            ]),
            if (extra != null) ...[
              SectionHeader('${tr(rec.s('specialty'))} • ${tr('specific')}'),
              for (final f in extra) _tf(f[0], f[1], lines: 2),
            ],
            if (mine.isNotEmpty) ...[
              Text('My templates', style: Theme.of(context).textTheme.labelLarge),
              Wrap(spacing: 6, children: [
                for (final t in mine)
                  GestureDetector(
                    onLongPress: () => _deleteMyTemplate(t),
                    child: ActionChip(avatar: const Icon(Icons.person_outline, size: 16), label: Text(t.label), onPressed: () => _applyTemplate(t)),
                  ),
              ]),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('save_my_template'),
                onPressed: _saveMyTemplate,
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text('Save this history as my template'),
              ),
            ),
          ],
          open: ['hpi', 'pmh', 'drugs', 'psh', 'family', 'social', 'ros'].any((k) => rec.s(k).isNotEmpty),
        ),
        _next(1),
      ],
    );
  }

  // ------------------------------------------------------------ fill normal

  /// Clinical wording: stays English on purpose (never translated).
  static const Map<String, String> _kNormalHistory = {
    'pmh': 'No significant past medical history',
    'drugs': 'No regular medications',
    'allergies': 'NKDA',
    'family': 'Non-contributory',
    'ros': 'ROS negative except as above',
  };
  static const Map<String, String> _kNormalExam = {
    'examGeneral':
        'Conscious, alert, oriented. Not pale, not jaundiced. No cyanosis, no clubbing, no edema, no lymphadenopathy. Well hydrated.',
    'examSystemic':
        'S1 S2 normal, no murmurs. Chest clear bilaterally. Abdomen soft and lax, no tenderness, bowel sounds present. GCS 15/15. Neck supple. Power 5/5 all limbs. Reflexes normal.',
  };

  List<String> get _autoKeys {
    final v = rec.d['autoNormal'];
    return v is List ? v.map((e) => e.toString()).toList() : <String>[];
  }

  /// True while the field still holds exactly the text that was filled automatically.
  bool _isAuto(String key) {
    if (!_autoKeys.contains(key)) return false;
    if (key.startsWith('sys:')) {
      final e = _sysMap()[key.substring(4)];
      return e is Map &&
          e['s'] == 'Normal' &&
          (e['n'] ?? '').toString().isEmpty;
    }
    final t = _kNormalHistory[key] ?? _kNormalExam[key];
    return t != null && rec.s(key) == t;
  }

  Widget _autoHint() => Text('Filled automatically - confirm you examined this',
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Colors.orange.shade800));

  Widget _fillNormalButton({required bool history}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () => _fillNormal(history: history, exam: !history),
            icon: const Icon(Icons.done_all),
            label: Text('Fill the rest as normal'),
          ),
        ),
        const SizedBox(height: 4),
        Text('Fills only empty fields. Vital signs and results are never filled.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  bool _emptyField(String k) =>
      rec.s(k).trim().isEmpty && rec.s('st_$k').isEmpty;

  /// Fills ONLY empty fields with normal findings (optionally a specialty template first).
  Future<void> _fillNormal(
      {bool history = false, bool exam = false, CaseTemplate? tpl}) async {
    final text = <String, String>{};
    if (tpl != null) {
      if (tpl.hpi.isNotEmpty && _emptyField('hpi')) text['hpi'] = tpl.hpi;
      if (tpl.exam.isNotEmpty && _emptyField('examSystemic')) {
        text['examSystemic'] = tpl.exam;
      }
    }
    final auto = <String>[];
    if (history) {
      _kNormalHistory.forEach((k, v) {
        if (_emptyField(k)) {
          text[k] = v;
          auto.add(k);
        }
      });
    }
    final sysNames = <String>[];
    if (exam) {
      _kNormalExam.forEach((k, v) {
        if (_emptyField(k) && !text.containsKey(k)) {
          text[k] = v;
          auto.add(k);
        }
      });
      final m = _sysMap();
      for (final n in _kSystems) {
        final e = m[n];
        if (!(e is Map && (e['s'] ?? '').toString().isNotEmpty)) {
          sysNames.add(n);
        }
      }
    }
    final n = text.length + sysNames.length;
    if (n == 0) {
      snack(context, tr('Nothing to fill: the fields already have content.'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Fill as normal?'),
        content: Text(trp(
            '{n} empty fields will be filled with normal findings. Review them before you rely on them.',
            {'n': n})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Fill')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // one undo step that restores exactly the previous record
    _undo.add(jsonEncode(rec.d));
    if (_undo.length > 30) _undo.removeAt(0);
    _burst = true;
    text.forEach((k, v) {
      _tc(k).text = v;
      rec.set(k, v);
    });
    if (sysNames.isNotEmpty) {
      final all = _sysMap();
      for (final s in sysNames) {
        final cur = Map<String, dynamic>.from(
            (all[s] is Map) ? all[s] as Map : <String, dynamic>{});
        cur['s'] = 'Normal';
        all[s] = cur;
        auto.add('sys:$s');
      }
      rec.d['sys'] = all;
    }
    rec.d['autoNormal'] = {..._autoKeys, ...auto}.toList();
    _changed();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content:
            Text(trp('{n} fields filled. Review them.', {'n': n})),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: tr('Undo'), onPressed: _doUndo),
      ));
  }

  Future<void> _fillFromTemplate() async {
    final tpls = templatesFor(rec.s('specialty'));
    if (tpls.isEmpty) {
      snack(context, tr('No template for this specialty.'));
      return;
    }
    var pick = tpls.first;
    if (tpls.length > 1) {
      final t = await showDialog<CaseTemplate>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Quick fill from specialty template'),
          children: [
            for (final t in tpls)
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, t),
                  child: Text(t.label)),
          ],
        ),
      );
      if (t == null || !mounted) return;
      pick = t;
    }
    await _fillNormal(history: true, exam: true, tpl: pick);
  }

  Future<void> _saveMyTemplate() async {
    final spec = rec.s('specialty');
    final exam = rec.s('examGeneral');
    final hpi = _tc('hpi').text.trim();
    if (hpi.isEmpty && exam.trim().isEmpty) {
      snack(context, tr('Write something in the history first.'));
      return;
    }
    final ctl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Name this template'),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(labelText: tr('Template name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text('Save')),
        ],
      ),
    );
    if (label == null || label.isEmpty || !mounted) return;
    // Keep the headings and drop what was typed after them, so the template is reusable.
    String skeleton(String t) => t.split('\n').map((l) {
          final i = l.indexOf(':');
          return i > 0 && i < 60 ? '${l.substring(0, i + 1)} ' : l;
        }).join('\n');
    await saveUserTemplate(spec, label, hpi: skeleton(hpi), exam: skeleton(exam));
    if (!mounted) return;
    setState(() {});
    snack(context, tr('Template saved. Long-press it to delete.'));
  }

  Future<void> _deleteMyTemplate(CaseTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete this template?'),
        content: m.Text(t.label),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await removeUserTemplate(rec.s('specialty'), t.label);
    if (mounted) setState(() {});
  }

  void _applyTemplate(CaseTemplate t) {
    void put(String key, String text) {
      if (text.isEmpty) return;
      final c = _tc(key);
      c.text = c.text.trim().isEmpty ? text : '${c.text.trim()}\n$text';
      rec.set(key, c.text);
    }

    put('hpi', t.hpi);
    put('examSystemic', t.exam);
    _changed();
    snack(context, trp('Template added: {name}', {'name': tr(t.label)}));
  }

  static const List<String> _kSystems = [
    'General',
    'CVS',
    'Respiratory',
    'Abdomen',
    'CNS',
    'MSK',
    'ENT',
    'Skin',
  ];
  static const List<String> _kSysStates = [
    'Normal',
    'Abnormal',
    'Not examined',
    'Unknown'
  ];

  Map<String, dynamic> _sysMap() {
    final v = rec.d['sys'];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  void _setSys(String name, String? state, {String? note}) {
    final m = _sysMap();
    final cur = Map<String, dynamic>.from(
        (m[name] is Map) ? m[name] as Map : <String, dynamic>{});
    if (state != null) cur['s'] = state;
    if (note != null) cur['n'] = note;
    if ((cur['s'] ?? '').toString().isEmpty &&
        (cur['n'] ?? '').toString().isEmpty) {
      m.remove(name);
    } else {
      m[name] = cur;
    }
    rec.d['sys'] = m;
    _changed();
  }

  /// Examination by system: normal / abnormal / not examined / unknown.
  Widget _systems() {
    final m = _sysMap();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text('Examination by system',
                    style: theme.textTheme.titleMedium)),
            TextButton(
              onPressed: () {
                final all = _sysMap();
                for (final n in _kSystems) {
                  final cur = Map<String, dynamic>.from(
                      (all[n] is Map) ? all[n] as Map : <String, dynamic>{});
                  if ((cur['s'] ?? '').toString().isEmpty) {
                    cur['s'] = 'Normal';
                    all[n] = cur;
                  }
                }
                rec.d['sys'] = all;
                _changed();
              },
              child: Text('Mark empty as normal'),
            ),
          ]),
          if (_kSystems.any((n) => _isAuto('sys:$n')))
            Padding(padding: const EdgeInsets.only(bottom: 6), child: _autoHint()),
          for (final n in _kSystems)
            Fold(
              id: 'sys_$n',
              title: tr(n),
              subtitle:
                  (m[n] is Map ? (m[n] as Map)['s'] : '').toString().isEmpty
                      ? null
                      : tr((m[n] as Map)['s'].toString()),
              initiallyOpen:
                  (m[n] is Map ? (m[n] as Map)['s'] : '') == 'Abnormal',
              children: [
                Wrap(spacing: 6, children: [
                  for (final st in _kSysStates)
                    ChoiceChip(
                      label: Text(st),
                      selected: (m[n] is Map ? (m[n] as Map)['s'] : '') == st,
                      onSelected: (v) => _setSys(n, v ? st : ''),
                    ),
                ]),
                if ((m[n] is Map ? (m[n] as Map)['s'] : '') == 'Abnormal')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextFormField(
                      initialValue: (m[n] as Map)['n']?.toString() ?? '',
                      decoration: InputDecoration(
                          labelText: tr('What is abnormal?'), isDense: true),
                      onChanged: (t) => _setSys(n, null, note: t),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _exam() {
    final adult = rec.s('ageGroup') == 'Adult';
    const vitals = [
      ['v_bp', 'BP', '120/80'],
      ['v_hr', 'HR', 'bpm'],
      ['v_temp', 'Temp', '°C'],
      ['v_rr', 'RR', '/min'],
      ['v_spo2', 'SpO2', '%'],
      ['v_rbs', 'RBS', 'mg/dL'],
      ['v_wt', 'Weight', 'kg'],
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _fillNormalButton(history: false),
        ChoicesSection(rec: rec, section: 'Examination', onChanged: _changed, write: _writeDerived, onGoHistory: (c) => _goPage(c, 1)),
        Text('Vital signs', style: Theme.of(context).textTheme.titleMedium),
        if (!adult)
          Text(
              'Abnormal-value highlighting works for Adult only (set age group in Info).',
              style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (ctx, c) {
          final cols = c.maxWidth >= 340 ? 4 : 3;
          final w = (c.maxWidth - 8 * (cols - 1)) / cols;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in vitals)
                SizedBox(
                  width: w,
                  child: TextField(
                    controller: _tc(v[0]),
                    keyboardType: v[0] == 'v_bp' ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: tr(v[1]),
                      hintText: v[2],
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(10, 22, 10, 8),
                      enabledBorder: vitalAbnormal(v[0], rec.s(v[0]), adult)
                          ? UnderlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.red, width: 2))
                          : null,
                    ),
                    onChanged: (t) {
                      rec.set(v[0], t);
                      _changed();
                    },
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: 16),
        _systems(),
        Fold(
            id: 'ex_general',
            title: tr('General examination'),
            icon: Icons.accessibility_new,
            initiallyOpen: rec.s('examGeneral').isNotEmpty,
            children: [
              _tf('examGeneral', 'General examination', lines: 3),
              _obs('obsGeneral', 'examGeneral'),
              _quick('examGeneral', const [
                'Conscious, alert, oriented',
                'Not pale',
                'Not jaundiced',
                'No cyanosis',
                'No clubbing',
                'No edema',
                'No lymphadenopathy',
                'Well hydrated',
              ]),
            ]),
        Fold(
            id: 'ex_systemic',
            title: tr('Systemic examination (CVS / Resp / Abd / CNS / MSK)'),
            icon: Icons.monitor_heart_outlined,
            initiallyOpen: rec.s('examSystemic').isNotEmpty,
            children: [
              _tf('examSystemic',
                  'Systemic examination (CVS / Resp / Abd / CNS / MSK)',
                  lines: 6),
              _obs('obsSystemic', 'examSystemic'),
              _quick('examSystemic', const [
                'S1 S2 normal, no murmurs',
                'Chest clear bilaterally',
                'Soft & lax abdomen',
                'No tenderness',
                'Bowel sounds present',
                'GCS 15/15',
                'Neck supple',
                'Power 5/5 all limbs',
                'Reflexes normal',
              ]),
            ]),
        Fold(
            id: 'ex_focused',
            title: tr('Focused examination / positive findings'),
            icon: Icons.center_focus_strong_outlined,
            initiallyOpen: rec.s('examFocused').isNotEmpty,
            children: [
              _tf('examFocused', 'Focused examination / positive findings',
                  lines: 3),
              _obs('obsFocused', 'examFocused'),
            ]),
        _next(2),
      ],
    );
  }

  /// Who actually examined? Keeps the log honest.
  Widget _obs(String key, String textKey) {
    final missing = rec.s(textKey).trim().isNotEmpty && rec.s(key).isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _choice(key, 'Source of these findings',
              const ['Examined by me', 'Reported by team', 'Not examined']),
          if (missing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Tip: mark whether you examined this yourself.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.orange)),
            ),
        ],
      ),
    );
  }

  Future<void> _editInv([J? inv]) async {
    final res = await showFormSheet(
      context,
      title: inv == null ? 'New investigation' : 'Investigation',
      specs: const [
        FieldSpec('name', 'Test / study', hint: 'CBC, CXR, ECG...'),
        FieldSpec('indication', 'Indication'),
        FieldSpec('requestedBy', 'Requested by',
            type: FT.choice, options: ['Me', 'Team', 'Supervisor']),
        FieldSpec('status', 'Status',
            type: FT.choice, options: ['Pending', 'Resulted', 'Reviewed']),
        FieldSpec('result', 'Result', type: FT.multi),
        FieldSpec('interpretation', 'My interpretation', type: FT.multi),
      ],
      initial: inv ??
          <String, dynamic>{
            'id': newId('i'),
            'status': 'Pending',
            'requestedBy': 'Me',
            'date': todayStr(),
          },
      canDelete: inv != null,
    );
    if (res == null) return;
    final list = rec.lst('inv');
    if (res['__delete'] == true) {
      list.removeWhere((e) => e['id'] == inv!['id']);
    } else {
      final i = list.indexWhere((e) => e['id'] == res['id']);
      if (i >= 0) {
        list[i] = res;
      } else {
        list.add(res);
      }
    }
    _changed();
  }

  void _quickInv(String name) {
    rec.lst('inv').add(<String, dynamic>{
      'id': newId('i'),
      'name': name,
      'status': 'Pending',
      'requestedBy': 'Me',
      'date': todayStr(),
    });
    _changed();
  }

  static const List<String> _imgTypes = [
    'X-ray',
    'CT',
    'MRI',
    'Ultrasound',
    'ECG',
    'Lab report',
    'Skin / wound',
    'Pathology',
    'Other',
  ];

  Future<void> _addImage() async {
    if (!_warnedImages) {
      final ok = await confirmDialog(
        context,
        'Before adding an image: make sure no patient name, ID number or hospital '
        'file number is visible. Cover it before taking the photo.',
        action: 'Continue',
      );
      if (!ok) return;
      _warnedImages = true;
    }
    if (!mounted) return;
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (src == null || !mounted) return;
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What is this image?',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                  'Sets the quality: ECG and lab reports keep small print readable.',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _imgTypes)
                    ActionChip(
                        label: Text(t), onPressed: () => Navigator.pop(ctx, t)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (type == null) return;
    int quality = 75;
    double width = 1800;
    if (type == 'ECG' || type == 'Lab report') {
      quality = 92;
      width = 2600;
    } else if (const ['X-ray', 'CT', 'MRI', 'Ultrasound', 'Pathology']
        .contains(type)) {
      quality = 85;
      width = 2200;
    }
    final x = await ImagePicker()
        .pickImage(source: src, imageQuality: quality, maxWidth: width);
    if (x == null) return;
    final name = await store.importImage(x.path, rec.s('code'));
    if (!mounted) return;
    final meta = await showFormSheet(
      context,
      title: 'Image details',
      specs: const [
        FieldSpec('type', 'Type', type: FT.choice, options: _imgTypes),
        FieldSpec('view', 'View', hint: 'AP, lateral, axial...'),
        FieldSpec('caption', 'Caption'),
        FieldSpec('interpretation', 'My interpretation', type: FT.multi),
      ],
      initial: <String, dynamic>{
        'file': name,
        'date': todayStr(),
        'type': type
      },
    );
    rec.lst('images').add(meta ??
        <String, dynamic>{'file': name, 'date': todayStr(), 'type': type});
    _changed();
  }

  Future<void> _viewImage(J img) async {
    final act = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ImageViewer(img: img)),
    );
    if (act == 'edit') {
      if (!mounted) return;
      final res = await showFormSheet(
        context,
        title: 'Image details',
        specs: const [
          FieldSpec('type', 'Type', type: FT.choice, options: [
            'X-ray',
            'CT',
            'MRI',
            'Ultrasound',
            'ECG',
            'Lab report',
            'Skin / wound',
            'Pathology',
            'Other'
          ]),
          FieldSpec('view', 'View'),
          FieldSpec('caption', 'Caption'),
          FieldSpec('interpretation', 'My interpretation', type: FT.multi),
        ],
        initial: img,
      );
      if (res != null) {
        final l = rec.lst('images');
        final i = l.indexWhere((e) => e['file'] == img['file']);
        if (i >= 0) l[i] = res;
        _changed();
      }
    } else if (act == 'annotate') {
      if (!mounted) return;
      final res = await Navigator.push<List<J>>(
        context,
        MaterialPageRoute(
          builder: (_) => ImageAnnotateScreen(
              path: store.imagePath(img['file'].toString()),
              initial: annotationsOf(img)),
        ),
      );
      if (res != null) {
        img['ann'] = res;
        _changed();
      }
    } else if (act == 'cover') {
      if (!mounted) return;
      final bytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
            builder: (_) => ImageCoverScreen(
                path: store.imagePath(img['file'].toString()))),
      );
      if (bytes != null) {
        final old = img['file'].toString();
        final name =
            '${old.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')}_c${DateTime.now().millisecondsSinceEpoch % 100000}.png';
        await File(store.imagePath(name)).writeAsBytes(bytes, flush: true);
        img['file'] = name;
        await store.deleteImageFile(old);
        _changed();
        if (mounted) snack(context, tr('Private details covered permanently'));
      }
    } else if (act == 'compare') {
      if (!mounted) return;
      final images = rec.lst('images');
      if (images.length < 2) {
        snack(context, tr('Add at least two images to compare'));
        return;
      }
      final two = await pickTwoImages(context, images);
      if (two != null && mounted) {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ImageCompareScreen(a: two[0], b: two[1])));
      }
    } else if (act == 'delete') {
      if (!mounted) return;
      final ok = await confirmDialog(context, 'Delete this image?');
      if (ok) {
        rec.lst('images').removeWhere((e) => e['file'] == img['file']);
        await store.deleteImageFile(img['file'].toString());
        _changed();
      }
    }
  }

  Widget _inv() {
    final list = rec.lst('inv');
    final images = rec.lst('images');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LabSection(rec: rec, onChanged: _changed),
        ChoicesSection(rec: rec, section: 'Investigations', onChanged: _changed, write: _writeDerived, onGoHistory: (c) => _goPage(c, 1)),
        const SizedBox(height: 8),
        Text('Quick add (as requested / pending)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        _chipRow([
          for (final n in const ['CBC', 'KFT', 'LFT', 'Electrolytes', 'ABG', 'CRP', 'Troponin', 'Coagulation', 'Urinalysis', 'ECG', 'CXR', 'Ultrasound', 'CT', 'MRI'])
            ActionChip(label: Text(n), visualDensity: VisualDensity.compact, onPressed: () => _quickInv(n)),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _editInv(),
          icon: const Icon(Icons.add),
          label: const Text('Add custom investigation'),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No investigations yet.'),
          ),
        for (final i in list)
          AppCard(
            child: ListTile(
              onTap: () => _editInv(i),
              title: Text((i['name'] ?? '').toString()),
              subtitle: Text(
                [
                  '${tr((i['status'] ?? '').toString())} • ${tr('by')} ${tr((i['requestedBy'] ?? '').toString())}',
                  if ((i['result'] ?? '').toString().isNotEmpty)
                    '${i['result']}',
                ].join('\n'),
              ),
              isThreeLine: (i['result'] ?? '').toString().isNotEmpty,
              trailing: Icon(
                i['status'] == 'Pending'
                    ? Icons.hourglass_empty
                    : Icons.check_circle_outline,
              ),
            ),
          ),
        SectionHeader(
          '${tr('Images')} (${images.length})',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (images.length >= 2)
                IconButton(
                  tooltip: tr('Compare images'),
                  icon: const Icon(Icons.compare),
                  onPressed: () async {
                    final two = await pickTwoImages(context, images);
                    if (two != null && mounted) {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ImageCompareScreen(a: two[0], b: two[1])));
                    }
                  },
                ),
              TextButton.icon(
                onPressed: _addImage,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        if (images.isNotEmpty)
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final img in images)
                InkWell(
                  onTap: () => _viewImage(img),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(store.imagePath(img['file'].toString())),
                          fit: BoxFit.cover,
                          cacheWidth: 400,
                          errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image_outlined)),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.all(3),
                            child: Text(
                              [
                                (img['type'] ?? '').toString(),
                                (img['view'] ?? '').toString()
                              ].where((e) => e.isNotEmpty).join(' '),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        _next(3),
      ],
    );
  }

  /// Optional diagnostic time-out: four questions that make me look again.
  Future<void> _challenge() async {
    final res = await showFormSheet(
      context,
      title: 'Challenge my diagnosis',
      specs: const [
        FieldSpec('chAlt', 'What else could this be?', type: FT.multi),
        FieldSpec('chContra', 'Which findings do not fit?', type: FT.multi),
        FieldSpec('chAnchor', 'Am I anchoring on the first impression?',
            type: FT.multi),
        FieldSpec('chMissing', 'What is still missing?', type: FT.multi),
      ],
      initial: {
        for (final k in ['chAlt', 'chContra', 'chAnchor', 'chMissing'])
          k: rec.s(k)
      },
    );
    if (res == null || res['__delete'] == true) return;
    for (final k in ['chAlt', 'chContra', 'chAnchor', 'chMissing']) {
      rec.set(k, (res[k] ?? '').toString());
      _ctl[k]?.text = rec.s(k);
    }
    _changed();
  }

  Widget _assess() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ProblemSection(rec: rec, onChanged: _changed),
        ChoicesSection(rec: rec, section: 'Assessment', onChanged: _changed, write: _writeDerived, onGoHistory: (c) => _goPage(c, 1)),
        ScoresSection(rec: rec, onChanged: _changed),
        _tf('problems', 'Problem list (free text)', lines: 3),
        _tf('ddx', 'Differential diagnosis (most likely first)', lines: 4),
        _tf('workingDx', 'Working / provisional diagnosis', lines: 2),
        _tf('finalDx', 'Final diagnosis', lines: 2, unc: true),
        _tf('redFlags', 'Red flags', lines: 2),
        _tf('reasoning', 'Clinical reasoning: what supports / argues against?',
            lines: 5),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _challenge,
            icon: const Icon(Icons.psychology_alt_outlined),
            label: Text('Challenge my diagnosis'),
          ),
        ),
        SectionHeader(
          'Diagnostic evolution',
          trailing: TextButton.icon(
            onPressed: () => _editEvo(),
            icon: const Icon(Icons.add),
            label: const Text('Step'),
          ),
        ),
        if (rec.lst('evo').isEmpty)
          Text(
              'Track how your thinking changed: first impression, new findings, final diagnosis.',
              style: Theme.of(context).textTheme.bodySmall),
        for (final e in rec.lst('evo'))
          AppCard(
            child: ListTile(
              onTap: () => _editEvo(e),
              leading: const Icon(Icons.timeline),
              title: Text(tr('${e['step'] ?? ''}')),
              subtitle: Text([
                prettyDate((e['date'] ?? '').toString()),
                (e['text'] ?? '').toString(),
                if ((e['evidence'] ?? '').toString().isNotEmpty)
                  '${tr('Because')}: ${e['evidence']}',
              ].where((x) => x.isNotEmpty).join('\n')),
            ),
          ),
        _next(4),
      ],
    );
  }

  Future<void> _editEvo([J? e]) async {
    final res = await showFormSheet(
      context,
      title: e == null ? 'New step' : 'Step',
      specs: const [
        FieldSpec('step', 'Step', type: FT.choice, options: [
          'Initial DDx',
          'New finding',
          'Updated DDx',
          'Final diagnosis'
        ]),
        FieldSpec('date', 'Date', type: FT.date),
        FieldSpec('text', 'Diagnosis / thinking at this point', type: FT.multi),
        FieldSpec('evidence', 'What made me think so (finding / result)',
            type: FT.multi),
      ],
      initial: e ??
          <String, dynamic>{
            'id': newId('e'),
            'date': todayStr(),
            'step': 'Initial DDx'
          },
      canDelete: e != null,
    );
    if (res == null) return;
    final list = rec.lst('evo');
    if (res['__delete'] == true) {
      list.removeWhere((x) => x['id'] == e!['id']);
    } else {
      final i = list.indexWhere((x) => x['id'] == res['id']);
      if (i >= 0) {
        list[i] = res;
      } else {
        list.add(res);
      }
      list.sort((a, b) =>
          (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
    }
    _changed();
  }

  Future<void> _editMgmt([J? m]) async {
    final res = await showFormSheet(
      context,
      title: m == null ? 'New plan item' : 'Plan item',
      specs: const [
        FieldSpec('text', 'Plan item (drug / intervention)', type: FT.multi),
        FieldSpec('dose', 'Dose / route / frequency (as written in the chart)',
            hint: 'e.g. 500 mg PO q8h'),
        FieldSpec('state', 'Status',
            type: FT.choice,
            options: ['Suggested', 'Ordered', 'Given', 'Stopped']),
        FieldSpec('category', 'Category', type: FT.choice, options: [
          'Initial / ER',
          'Medications & fluids',
          'Procedure / surgery',
          'Consult / referral',
          'Monitoring',
          'Safety-netting'
        ]),
        FieldSpec('by', 'Who decided', type: FT.choice, options: [
          'Suggested by me',
          'Team decision',
          'Supervisor changed'
        ]),
      ],
      initial: m ??
          <String, dynamic>{
            'id': newId('m'),
            'by': 'Team decision',
            'state': 'Ordered'
          },
      canDelete: m != null,
    );
    if (res == null) return;
    final list = rec.lst('mgmt');
    if (res['__delete'] == true) {
      list.removeWhere((e) => e['id'] == m!['id']);
    } else {
      final i = list.indexWhere((e) => e['id'] == res['id']);
      if (i >= 0) {
        list[i] = res;
      } else {
        list.add(res);
      }
    }
    _changed();
  }

  Color _byColor(String by) {
    switch (by) {
      case 'Suggested by me':
        return Colors.green;
      case 'Supervisor changed':
        return Colors.amber;
      default:
        return Colors.blue;
    }
  }

  Widget _mgmt() {
    final list = rec.lst('mgmt');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ChoicesSection(rec: rec, section: 'Management', onChanged: _changed, write: _writeDerived, onGoHistory: (c) => _goPage(c, 1)),
        _banner(
            'Mark honestly who made each decision: what you suggested, what the '
            'team decided, and what the supervisor changed.',
            icon: Icons.fact_check_outlined),
        FilledButton.icon(
          onPressed: () => _editMgmt(),
          icon: const Icon(Icons.add),
          label: const Text('Add plan item'),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _menu('doses'),
            icon: const Icon(Icons.medication_liquid_outlined),
            label: Text('Drug doses for this patient'),
          ),
        ),
        const SizedBox(height: 8),
        for (final m in list)
          AppCard(
            child: ListTile(
              onTap: () => _editMgmt(m),
              leading: Icon(Icons.circle,
                  color: _byColor((m['by'] ?? '').toString())),
              title: Text((m['text'] ?? '').toString()),
              subtitle: Text([
                '${tr((m['category'] ?? '').toString())} • ${tr((m['by'] ?? '').toString())}',
                if ((m['dose'] ?? '').toString().isNotEmpty) '${m['dose']}',
                if ((m['state'] ?? '').toString().isNotEmpty)
                  tr('${m['state']}'),
              ].join('\n')),
              isThreeLine: (m['dose'] ?? '').toString().isNotEmpty,
            ),
          ),
        const SectionHeader('Disposition'),
        _choice('disposition', 'Disposition', const [
          'Admitted',
          'Discharged',
          'Transferred',
          'Referred',
          'Deceased'
        ]),
        _tf('followUp', 'Follow-up recommendations', lines: 2),
        _tf('outcome', 'Outcome', lines: 2),
        _next(5),
      ],
    );
  }

  Future<void> _editProgress([J? p]) async {
    final base = parseDate(rec.s('date')) ?? DateTime.now();
    final diff = DateTime.now().difference(base).inDays;
    final res = await showFormSheet(
      context,
      title: p == null ? 'New progress note' : 'Progress note',
      specs: const [
        FieldSpec('day', 'Day',
            hint: 'Day 1 / POD 2',
            options: ['Day 0', 'Day 1', 'Day 2', 'Day 3']),
        FieldSpec('date', 'Date', type: FT.date),
        FieldSpec('s', 'S - Subjective', type: FT.multi),
        FieldSpec('o', 'O - Objective (exam, vitals, results)', type: FT.multi),
        FieldSpec('a', 'A - Assessment', type: FT.multi),
        FieldSpec('p', 'P - Plan', type: FT.multi),
      ],
      initial: p ??
          <String, dynamic>{
            'id': newId('p'),
            'day': 'Day ${diff < 0 ? 0 : diff}',
            'date': todayStr(),
          },
      canDelete: p != null,
    );
    if (res == null) return;
    final list = rec.lst('progress');
    if (res['__delete'] == true) {
      list.removeWhere((e) => e['id'] == p!['id']);
    } else {
      final i = list.indexWhere((e) => e['id'] == res['id']);
      if (i >= 0) {
        list[i] = res;
      } else {
        list.add(res);
      }
      list.sort((a, b) =>
          (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
    }
    _changed();
  }

  Future<void> _editEncounter([J? e]) async {
    final res = await showFormSheet(
      context,
      title: e == null ? 'New encounter' : 'Encounter',
      specs: const [
        FieldSpec('type', 'Type', type: FT.choice, options: [
          'Admission',
          'Follow-up',
          'Consultation',
          'Procedure',
          'Discharge',
          'Other'
        ]),
        FieldSpec('date', 'Date', type: FT.date),
        FieldSpec('note', 'What happened', type: FT.multi),
      ],
      initial: e ??
          <String, dynamic>{
            'id': newId('en'),
            'date': todayStr(),
            'type': 'Follow-up'
          },
      canDelete: e != null,
    );
    if (res == null) return;
    final list = rec.lst('encounters');
    if (res['__delete'] == true) {
      list.removeWhere((x) => x['id'] == e!['id']);
    } else {
      final i = list.indexWhere((x) => x['id'] == res['id']);
      if (i >= 0) {
        list[i] = res;
      } else {
        list.add(res);
      }
    }
    _changed();
  }

  /// One time line for the whole case: visits, results, notes, images and diagnosis changes.
  Widget _timeline() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ev = <({
      String date,
      IconData icon,
      String title,
      String sub,
      VoidCallback? tap
    })>[];
    ev.add((
      date: rec.s('date'),
      icon: Icons.flag_outlined,
      title: tr('Case opened'),
      sub: rec.s('cc'),
      tap: null
    ));
    for (final e in rec.lst('encounters')) {
      ev.add((
        date: (e['date'] ?? '').toString(),
        icon: Icons.event_note_outlined,
        title: tr((e['type'] ?? '').toString()),
        sub: (e['note'] ?? '').toString(),
        tap: () => _editEncounter(e)
      ));
    }
    for (final p in rec.lst('progress')) {
      ev.add((
        date: (p['date'] ?? '').toString(),
        icon: Icons.timeline,
        title: '${tr('Progress note')} • ${tr('${p['day'] ?? ''}')}',
        sub: (p['a'] ?? p['s'] ?? '').toString(),
        tap: null
      ));
    }
    for (final i in rec.lst('inv')) {
      ev.add((
        date: (i['date'] ?? '').toString(),
        icon: Icons.biotech_outlined,
        title: (i['name'] ?? '').toString(),
        sub: '${tr('${i['status'] ?? ''}')} ${(i['result'] ?? '').toString()}'
            .trim(),
        tap: null
      ));
    }
    for (final d in rec.lst('evo')) {
      ev.add((
        date: (d['date'] ?? '').toString(),
        icon: Icons.psychology_outlined,
        title: tr('${d['step'] ?? ''}'),
        sub: (d['text'] ?? '').toString(),
        tap: null
      ));
    }
    for (final im in rec.lst('images')) {
      ev.add((
        date: (im['date'] ?? '').toString(),
        icon: Icons.image_outlined,
        title: tr('${im['type'] ?? 'Image'}'),
        sub: (im['caption'] ?? '').toString(),
        tap: null
      ));
    }
    ev.sort((a, b) => a.date.compareTo(b.date));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _editEncounter,
          icon: const Icon(Icons.add),
          label: Text('Add encounter'),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < ev.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 34,
                  child: Column(children: [
                    CircleAvatar(
                        radius: 14,
                        backgroundColor: cs.primaryContainer,
                        child: Icon(ev[i].icon,
                            size: 16, color: cs.onPrimaryContainer)),
                    if (i < ev.length - 1)
                      Expanded(
                          child: Container(width: 2, color: cs.outlineVariant)),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: ev[i].tap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ev[i].date.isEmpty ? '' : prettyDate(ev[i].date),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: cs.outline)),
                          Text(ev[i].title,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          if (ev[i].sub.isNotEmpty)
                            Text(ev[i].sub,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        _next(8),
      ],
    );
  }

  Widget _progress() {
    final list = rec.lst('progress');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () => _editProgress(),
          icon: const Icon(Icons.add),
          label: const Text('Add progress note (SOAP)'),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No progress notes yet.'),
          ),
        for (final p in list)
          AppCard(
            child: ListTile(
              onTap: () => _editProgress(p),
              title: Text(
                  '${tr('${p['day'] ?? ''}')} • ${prettyDate((p['date'] ?? '').toString())}'),
              subtitle: Text(
                [
                  for (final k in const ['s', 'o', 'a', 'p'])
                    if ((p[k] ?? '').toString().isNotEmpty)
                      '${k.toUpperCase()}: ${p[k]}',
                ].join('\n'),
              ),
            ),
          ),
        _next(6),
      ],
    );
  }

  // ---- Learning tab: ideas taken from what is already in the case, never filled in silently ----

  String _firstLine(String s) => s.split(RegExp(r'[\n;]')).map((e) => e.trim()).firstWhere((e) => e.isNotEmpty, orElse: () => '');

  List<String> _initialDxIdeas() {
    final evo = rec.lst('evo');
    final out = <String>[];
    for (final e in evo) {
      if ('${e['step']}' == 'Initial DDx' && '${e['text']}'.trim().isNotEmpty) out.add('${e['text']}'.trim());
    }
    if (out.isEmpty) {
      final dd = _firstLine(rec.s('ddx'));
      if (dd.isNotEmpty) out.add(dd);
      final wk = rec.s('workingDx').trim();
      if (wk.isNotEmpty && !out.contains(wk)) out.add(wk);
    }
    return out;
  }

  List<String> _initialWhyIdeas() {
    for (final e in rec.lst('evo')) {
      if ('${e['step']}' == 'Initial DDx' && '${e['evidence']}'.trim().isNotEmpty) return ['${e['evidence']}'.trim()];
    }
    return const [];
  }

  List<String> _whatChangedIdeas() {
    final parts = <String>[];
    for (final e in rec.lst('evo')) {
      final step = '${e['step']}';
      if (step == 'Initial DDx') continue;
      final text = '${e['text']}'.trim(), ev = '${e['evidence']}'.trim();
      if (text.isEmpty && ev.isEmpty) continue;
      parts.add([if (text.isNotEmpty) text, if (ev.isNotEmpty) '(${tr('Because')}: $ev)'].join(' '));
    }
    return parts.isEmpty ? const [] : [parts.join('\n')];
  }

  Widget _learnSuggest(String key, List<String> ideas) {
    if (rec.s(key).trim().isNotEmpty || ideas.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Use from this case:', style: Theme.of(context).textTheme.bodySmall),
        for (final i in ideas)
          ActionChip(
            avatar: const Icon(Icons.auto_awesome, size: 14),
            label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: Text(i, maxLines: 1, overflow: TextOverflow.ellipsis)),
            onPressed: () {
              rec.set(key, i);
              _tc(key).text = i;
              _changed();
            },
          ),
      ]),
    );
  }

  static Set<String> _words(String s) => s.toLowerCase().split(RegExp(r'[^a-z0-9\u0600-\u06FF]+')).where((w) => w.length > 2).toSet();

  /// Suggests Right / Partly / Wrong by comparing the first and the final diagnosis; the user decides.
  Widget _rightSuggest() {
    if (rec.s('initialRight').isNotEmpty) return const SizedBox.shrink();
    final a = _words(rec.s('initialDx')), b = _words(rec.s('finalDx'));
    if (a.isEmpty || b.isEmpty) return const SizedBox.shrink();
    final overlap = a.intersection(b).length / a.union(b).length;
    final v = overlap >= .75 ? 'Right' : overlap >= .3 ? 'Partly' : 'Wrong';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ActionChip(
          avatar: const Icon(Icons.auto_awesome, size: 14),
          label: Text('${tr('Suggested')}: ${tr(v)} (${tr('first vs final diagnosis')})'),
          onPressed: () {
            rec.set('initialRight', v);
            _changed();
          },
        ),
      ),
    );
  }

  bool _reviewSuggested() => rec.s('questions').trim().isNotEmpty || rec.s('initialRight') == 'Wrong' || rec.s('initialRight') == 'Partly';

  Widget _learn() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _banner('This is the most valuable part: what did this case teach you?',
            icon: Icons.school_outlined),
        _tf('initialDx', 'My first diagnosis (before results)', lines: 2),
        _learnSuggest('initialDx', _initialDxIdeas()),
        _tf('initialWhy', 'Why I thought so', lines: 2),
        _learnSuggest('initialWhy', _initialWhyIdeas()),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How sure was I?',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(spacing: 8, children: [
                for (final e in const [
                  ['30', 'Not sure'],
                  ['60', 'Fairly sure'],
                  ['85', 'Very sure']
                ])
                  ChoiceChip(
                    label: Text(e[1]),
                    selected: rec.s('confInitial') == e[0],
                    onSelected: (_) {
                      rec.set('confInitial',
                          rec.s('confInitial') == e[0] ? '' : e[0]);
                      _changed();
                    },
                  ),
              ]),
            ],
          ),
        ),
        _choice('initialRight', 'Was my first diagnosis right?',
            const ['Right', 'Partly', 'Wrong']),
        _rightSuggest(),
        if (rec.s('chAlt').isNotEmpty ||
            rec.s('chContra').isNotEmpty ||
            rec.s('chAnchor').isNotEmpty ||
            rec.s('chMissing').isNotEmpty)
          AppCard(
            child: ListTile(
              leading: const Icon(Icons.psychology_alt_outlined),
              title: Text('My diagnostic time-out'),
              subtitle: Text([
                if (rec.s('chAlt').isNotEmpty)
                  '${tr('What else could this be?')} ${rec.s('chAlt')}',
                if (rec.s('chContra').isNotEmpty)
                  '${tr('Which findings do not fit?')} ${rec.s('chContra')}',
                if (rec.s('chAnchor').isNotEmpty)
                  '${tr('Am I anchoring on the first impression?')} ${rec.s('chAnchor')}',
                if (rec.s('chMissing').isNotEmpty)
                  '${tr('What is still missing?')} ${rec.s('chMissing')}',
              ].join('\n')),
              onTap: _challenge,
            ),
          ),
        _tf('whatChanged', 'What changed my diagnosis?', lines: 3),
        _learnSuggest('whatChanged', _whatChangedIdeas()),
        _tf('learned', 'What I learned', lines: 5),
        _tf('mistakes',
            'Mistakes / near-misses (mine or others) — for learning',
            lines: 3),
        _tf('questions', 'Questions I could not answer (to review)', lines: 3),
        _tf('refs', 'References (book, guideline, page, link)', lines: 2),
        _tf('teaching', 'Supervisor teaching points', lines: 3),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Add to review list'),
          subtitle: !rec.review && _reviewSuggested() ? Text('Suggested: this case has open questions or a missed first diagnosis.') : null,
          value: rec.review,
          onChanged: (v) {
            rec.set('review', v);
            _changed();
          },
        ),
        _next(7),
      ],
    );
  }

  // ------------------------------------------------------------ actions

  Future<void> _menu(String v) async {
    if (v == 'fillAll') {
      await _fillNormal(history: true, exam: true);
    } else if (v == 'fillTpl') {
      await _fillFromTemplate();
    } else if (v == 'share') {
      await _flush();
      if (!mounted || !await privacyGate(context, [rec])) return;
      await Share.share(caseAsText(rec));
    } else if (v == 'ai') {
      await _flush();
      if (!mounted) return;
      await openAiCase(context, rec, onChanged: () {
        _ctl.forEach((k, c) => c.text = rec.s(k));
        _changed();
      });
    } else if (v == 'calcs') {
      await _flush();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CalculatorsScreen(attachTo: rec)));
      if (mounted) setState(() {});
    } else if (v == 'doses') {
      await _flush();
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => DosingScreen(patient: DoseContext.fromCase(rec))));
    } else if (v == 'privacy') {
      await _flush();
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => PrivacyCheckScreen(rec: rec)));
    } else if (v == 'similar') {
      await _flush();
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => SimilarCasesScreen(rec: rec)));
    } else if (v == 'compare') {
      await _flush();
      if (!mounted) return;
      final other = await pickCase(context, exclude: rec.id);
      if (other == null || !mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => CompareScreen(a: rec, b: other)));
    } else if (v == 'replay') {
      await _flush();
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => OwnReplayScreen(rec: rec)));
    } else if (v == 'library') {
      await _flush();
      final hits = await articlesForCase(rec);
      if (!mounted) return;
      if (hits.isEmpty) {
        snack(context, tr('No matching article in your library yet.'));
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Read about this in the library', style: Theme.of(ctx).textTheme.titleMedium),
              ),
              for (final h in hits)
                ListTile(
                  leading: const Icon(Icons.local_library_outlined),
                  title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(h.lead, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(ctx);
                    openArticle(context, h.packId, h.index);
                  },
                ),
            ],
          ),
        ),
      );
    } else if (v == 'pdf') {
      await _flush();
      if (!mounted) return;
      await exportCasePdf(context, rec);
    } else if (v == 'practice') {
      await _flush();
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PresentationTrainerScreen(rec: rec)));
    } else if (v == 'present') {
      await _flush();
      if (!mounted || !await privacyGate(context, [rec])) return;
      await Share.share(casePresentation(rec));
    } else if (v == 'pack') {
      await _flush();
      if (!mounted || !await privacyGate(context, [rec])) return;
      final opt = await askPackOptions(context, 1);
      if (opt == null) return;
      try {
        final f = await store.exportPack([rec], opt.password,
            images: opt.images, learning: opt.learning);
        await Share.shareXFiles([XFile(f.path)], text: 'MedLog case');
      } catch (e) {
        if (mounted) snack(context, '${tr('Could not share')}: $e');
      }
    } else if (v == 'delete') {
      final ok =
          await confirmDialog(context, 'Delete this case and its images?');
      if (!ok) return;
      _timer?.cancel();
      _dirty = false;
      await store.deleteCase(rec);
      if (mounted) Navigator.pop(context);
    }
  }

  /// Which of the 8 sections already have something in them.
  List<bool> _filled() {
    bool any(List<String> keys) => keys.any((k) => rec.s(k).trim().isNotEmpty);
    return [
      rec.s('specialty').isNotEmpty && rec.s('ageGroup').isNotEmpty,
      any(['cc', 'hpi', 'pmh']),
      any([
        'examGeneral',
        'examSystemic',
        'examFocused',
        'v_bp',
        'v_hr',
        'v_temp'
      ]),
      rec.lst('inv').isNotEmpty || rec.lst('images').isNotEmpty,
      any(['ddx', 'workingDx', 'finalDx', 'problems']),
      rec.lst('mgmt').isNotEmpty || any(['disposition']),
      rec.lst('progress').isNotEmpty,
      any(['learned', 'initialDx', 'whatChanged']),
      rec.lst('encounters').isNotEmpty,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final filled = _filled();
    final done = filled.where((e) => e).length;
    final cs = Theme.of(context).colorScheme;

    Widget tab(IconData icon, String label, List<int> pages) {
      final lit = pages.any((p) => filled[p]);
      return Tab(
        height: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22),
                PositionedDirectional(
                  top: -2,
                  end: -5,
                  child: AnimatedScale(
                    scale: lit ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 12), maxLines: 1)),
          ],
        ),
      );
    }

    return AiContextScope(
      ctx: const AiScreenContext(kind: 'case', title: 'Case'),
      child: DefaultTabController(
      length: 5,
      initialIndex: _groupOf(widget.initialTab.clamp(0, 8)),
      child: PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _flush();
        },
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: ValueListenableBuilder<int>(
              valueListenable: _tick,
              builder: (context, _, __) {
                final saveLabel = switch (_save) {
                  _SaveState.saved => tr('Saved'),
                  _SaveState.saving => tr('Saving…'),
                  _SaveState.failed => tr('Not saved'),
                };
                final saveColor = switch (_save) {
                  _SaveState.saved => Colors.green,
                  _SaveState.saving => cs.onSurfaceVariant,
                  _SaveState.failed => Colors.red,
                };
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // the whole case code stays readable on a narrow screen: it shrinks instead of being cut
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(rec.s('code'),
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w800)),
                    ),
                    Row(
                      children: [
                        Icon(
                          _save == _SaveState.saved
                              ? Icons.check_circle
                              : (_save == _SaveState.saving
                                  ? Icons.sync
                                  : Icons.error),
                          size: 13,
                          color: saveColor,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '$saveLabel • ${trp('{a} of {b} sections filled', {
                                  'a': done,
                                  'b': filled.length
                                })}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            actions: [
              AiChipButton(key: const ValueKey('case_ai_chip'), tooltip: 'AI assistant', onTap: () => _menu('ai')),
              ValueListenableBuilder<int>(
                valueListenable: _tick,
                builder: (context, _, __) => IconButton(
                  tooltip: tr('Undo'),
                  icon: const Icon(Icons.undo),
                  onPressed: _undo.isEmpty ? null : _doUndo,
                ),
              ),
              IconButton(
                tooltip: tr('Starred'),
                icon: Icon(rec.starred ? Icons.star : Icons.star_border),
                onPressed: () {
                  rec.set('starred', !rec.starred);
                  _changed();
                },
              ),
              PopupMenuButton<String>(
                onSelected: _menu,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'fillAll',
                      child: Text('Fill everything normal (empty fields only)')),
                  PopupMenuItem(
                      value: 'fillTpl',
                      child: Text('Quick fill from specialty template')),
                  PopupMenuItem(value: 'calcs', child: Text('Calculators for this case')),
                  PopupMenuItem(value: 'doses', child: Text('Drug doses for this patient')),
                  PopupMenuItem(value: 'privacy', child: Text('Privacy check')),
                  PopupMenuItem(value: 'ai', child: Text('AI assistant')),
                  PopupMenuItem(
                      value: 'similar', child: Text('Similar & related')),
                  PopupMenuItem(
                      value: 'compare',
                      child: Text('Compare with another case')),
                  PopupMenuItem(
                      value: 'replay', child: Text('Replay this case')),
                  PopupMenuItem(
                      value: 'practice', child: Text('Practice presenting')),
                  PopupMenuItem(value: 'library', child: Text('Read about this in the library')),
                  PopupMenuItem(value: 'pdf', child: Text('Export as PDF')),
                  PopupMenuItem(
                      value: 'present', child: Text('Share case presentation')),
                  PopupMenuItem(
                      value: 'share',
                      child: Text('Share as text (no initials)')),
                  PopupMenuItem(
                      value: 'pack',
                      child: Text('Share to colleague (encrypted)')),
                  PopupMenuItem(value: 'delete', child: Text('Delete case')),
                ],
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(62),
              child: Column(
                children: [
                  TabBar(
                    onTap: _rememberTab,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                    tabs: [
                      tab(Icons.assignment_ind_outlined, trUi('Info'), [0]),
                      tab(Icons.medical_services_outlined, trUi('Clinical'), [1, 2, 3]),
                      tab(Icons.fact_check_outlined, trUi('Plan'), [4, 5]),
                      tab(Icons.update_outlined, trUi('Follow-up'), [6, 8]),
                      tab(Icons.school_outlined, trUi('Learning'), [7]),
                    ],
                  ),
                  AnimatedBar(done / filled.length, height: 3),
                ],
              ),
            ),
          ),
          bottomNavigationBar: _toolsBar(),
          body: Column(
            children: [
              if (_failedShown)
                Material(
                  color: cs.errorContainer,
                  child: ListTile(
                    dense: true,
                    leading:
                        Icon(Icons.error_outline, color: cs.onErrorContainer),
                    title: Text('${tr('Could not save')}: $_saveError',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(
                      onPressed: () {
                        _dirty = true;
                        _flush();
                      },
                      child: Text('Retry'),
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [for (var g = 0; g < _groups.length; g++) _group(g, filled)],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ================================================================ image viewer

class ImageViewer extends StatelessWidget {
  final J img;
  const ImageViewer({super.key, required this.img});

  @override
  Widget build(BuildContext context) {
    final title = [
      (img['type'] ?? '').toString(),
      (img['view'] ?? '').toString()
    ].where((e) => e.isNotEmpty).map(tr).join(' • ');
    final caption = (img['caption'] ?? '').toString();
    final interp = (img['interpretation'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isEmpty ? tr('Image') : title),
        actions: [
          IconButton(
            tooltip: tr('Annotate'),
            icon: const Icon(Icons.draw_outlined),
            onPressed: () => Navigator.pop(context, 'annotate'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => Navigator.pop(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                  value: 'cover', child: Text('Cover private details')),
              PopupMenuItem(value: 'compare', child: Text('Compare images')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 6,
              child: AnnotatedImage(
                  path: store.imagePath(img['file'].toString()),
                  ann: annotationsOf(img)),
            ),
          ),
          if (caption.isNotEmpty || interp.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (caption.isNotEmpty) Text(caption),
                  if (interp.isNotEmpty)
                    Text('${tr('My interpretation')}: $interp'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
