import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'ai/ai_context.dart';
import 'data.dart';
import 'i18n.dart';
import 'motion.dart' show EmptyState, EmptyKind;
import 'ref_data.dart';
import 'rotation_plan.dart';
import 'screens_library.dart' show LibraryScreen;
import 'screens_notebooks.dart' show openUrl;
import 'ui.dart';
import 'widgets.dart';

Widget _ltrText(String s, {TextStyle? style, int? maxLines}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.centerLeft, child: m.Text(s, style: style, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis)),
    );

const String _kDraftNote = 'Drafted from public clinical guidance. No drug doses are given. Always check your hospital protocol and a senior.';

// ============================================================ bedside cards

class BedsideCardsScreen extends StatefulWidget {
  const BedsideCardsScreen({super.key});
  @override
  State<BedsideCardsScreen> createState() => _BedsideCardsScreenState();
}

class _BedsideCardsScreenState extends State<BedsideCardsScreen> {
  String _q = '';
  late final Future<List<Map<String, dynamic>>> _f = RefData.cards();

  @override
  Widget build(BuildContext context) {
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'cards', title: 'Presentation cards'),
      child: Scaffold(
        appBar: AppBar(title: Text('Presentation cards')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (context, snap) {
            final all = snap.data ?? const <Map<String, dynamic>>[];
            final q = _q.trim().toLowerCase();
            final cards = [
              for (final c in all)
                if (q.isEmpty || c['presentation'].toString().toLowerCase().contains(q) || RefData.strings(c['specialties']).any((s) => s.toLowerCase().contains(q))) c
            ]..sort((a, b) => a['presentation'].toString().compareTo(b['presentation'].toString()));
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              TextField(
                key: const ValueKey('cards_search'),
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Search a presentation'), contentPadding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 8),
              Text(_kDraftNote, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              if (snap.connectionState != ConnectionState.done) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (snap.connectionState == ConnectionState.done && cards.isEmpty) const EmptyState(kind: EmptyKind.search, title: 'Nothing found'),
              for (final c in cards)
                AppCard(
                  child: ListTile(
                    key: ValueKey('card_${c['presentation']}'),
                    title: m.Text(c['presentation'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: _ltrText(RefData.strings(c['specialties']).join(' · '), maxLines: 1),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CardDetailScreen(card: c))),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

class CardDetailScreen extends StatelessWidget {
  final Map<String, dynamic> card;
  const CardDetailScreen({super.key, required this.card});

  Widget _list(String title, String key, IconData icon, {Color? tint, bool open = false}) {
    final items = RefData.strings(card[key]);
    if (items.isEmpty) return const SizedBox.shrink();
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Fold(
        id: 'card_${card['presentation']}_$key',
        title: tr(title),
        icon: icon,
        initiallyOpen: open,
        children: [
          for (final s in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.circle, size: 7, color: tint ?? cs.primary),
                const SizedBox(width: 8),
                Expanded(child: _ltrText(s)),
              ]),
            ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final refs = RefData.strings(card['references']);
    return AiContextScope(
      ctx: AiScreenContext(kind: 'card', title: card['presentation'].toString()),
      child: Scaffold(
        appBar: AppBar(title: m.Text(card['presentation'].toString())),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          _ltrText(RefData.strings(card['specialties']).join(' · '), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline)),
          const SizedBox(height: 4),
          _list('Red flags', 'redFlags', Icons.flag_outlined, tint: cs.error, open: true),
          _list("Can't miss", 'cantMiss', Icons.visibility_outlined, tint: cs.error, open: true),
          _list('Must ask', 'mustAsk', Icons.record_voice_over_outlined, open: true),
          _list('Must examine', 'mustExamine', Icons.accessibility_new),
          _list('Most likely', 'differentialTopThree', Icons.lightbulb_outline),
          _list('First investigations', 'firstInvestigations', Icons.science_outlined),
          _list('First actions', 'firstActions', Icons.bolt_outlined),
          _list('Related calculators', 'relatedCalculators', Icons.calculate_outlined),
          Fold(
            id: 'card_${card['presentation']}_refs',
            title: tr('References'),
            icon: Icons.menu_book_outlined,
            children: [
              for (final r in refs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: _ltrText(r.split(': http').first),
                  trailing: r.contains('http') ? const Icon(Icons.open_in_new, size: 18) : null,
                  onTap: r.contains('http') ? () => openUrl(context, 'http${r.split(': http').last}') : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => LibraryScreen(initialQuery: card['presentation'].toString()))),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: Text('Search the library for this'),
          ),
          const SizedBox(height: 8),
          Text(_kDraftNote, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

// ============================================================ rotation hub

class RotationHubScreen extends StatefulWidget {
  const RotationHubScreen({super.key});
  @override
  State<RotationHubScreen> createState() => _RotationHubScreenState();
}

class _RotationHubScreenState extends State<RotationHubScreen> {
  late String _spec = _defaultSpec();
  late final Future<Map<String, dynamic>> _cur = RefData.curriculum();
  late final Future<List<Map<String, dynamic>>> _cards = RefData.cards();

  static const List<String> _names = [
    'Internal Medicine', 'General Surgery', 'Pediatrics', 'OB/GYN', 'Emergency', 'ICU', 'Orthopedics', 'Family Medicine',
    'Neurology', 'Psychiatry', 'ENT', 'Ophthalmology', 'Dermatology', 'Urology', 'Anesthesia', 'Cardiology',
  ];

  String _defaultSpec() {
    final saved = store.settings['rotHubSpec'];
    if (saved is String && _names.contains(saved)) return saved;
    final n = <String, int>{};
    for (final c in store.cases.values) {
      n[c.s('specialty')] = (n[c.s('specialty')] ?? 0) + 1;
    }
    var best = _names.first;
    var bn = 0;
    n.forEach((k, v) {
      if (_names.contains(k) && v > bn) {
        best = k;
        bn = v;
      }
    });
    return best;
  }

  Set<String> _done() {
    final m = store.settings['rotDone'];
    if (m is Map && m[_spec] is List) return {for (final e in m[_spec] as List) e.toString()};
    return <String>{};
  }

  void _toggle(String topic) {
    final m = store.settings['rotDone'];
    final map = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
    final s = _done();
    if (!s.remove(topic)) s.add(topic);
    map[_spec] = s.toList();
    store.settings['rotDone'] = map;
    store.saveSettings();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AiContextScope(
      ctx: AiScreenContext(kind: 'rotation', title: 'Rotation hub: $_spec'),
      child: Scaffold(
        appBar: AppBar(title: Text('Rotation hub')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _cur,
          builder: (context, snap) {
            final specs = snap.data?['specialties'];
            final data = specs is Map && specs[_spec] is Map ? Map<String, dynamic>.from(specs[_spec] as Map) : <String, dynamic>{};
            final topics = [for (final t in (data['coreTopics'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
            final done = _done();
            final studied = topics.where((t) => done.contains(t['topic'])).length;
            final myCases = store.cases.values.where((c) => c.s('specialty') == _spec).length;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              Wrap(spacing: 6, runSpacing: 2, children: [
                for (final n in _names)
                  ChoiceChip(
                    key: ValueKey('rot_$n'),
                    label: Text(n),
                    selected: n == _spec,
                    onSelected: (_) {
                      store.settings['rotHubSpec'] = n;
                      store.saveSettings();
                      setState(() => _spec = n);
                    },
                  ),
              ]),
              const SizedBox(height: 10),
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('Cases you logged here', style: theme.textTheme.bodyMedium)),
                      m.Text('$myCases', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: Text('Core topics studied', style: theme.textTheme.bodyMedium)),
                      Directionality(textDirection: TextDirection.ltr, child: m.Text('$studied / ${topics.length}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                    ]),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: topics.isEmpty ? 0 : studied / topics.length, minHeight: 8, borderRadius: BorderRadius.circular(8)),
                  ]),
                ),
              ),
              if (snap.connectionState != ConnectionState.done) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              _planCard(theme, topics),
              Fold(
                id: 'rot_topics',
                title: tr('Core topics'),
                icon: Icons.checklist_rtl,
                initiallyOpen: true,
                subtitle: '$studied / ${topics.length}',
                children: [
                  for (final t in topics)
                    CheckboxListTile(
                      key: ValueKey('rot_topic_${t['topic']}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: done.contains(t['topic']),
                      onChanged: (_) => _toggle(t['topic'].toString()),
                      title: _ltrText(t['topic'].toString()),
                      subtitle: t['priority'] == 'must' ? Text('Must know', style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)) : null,
                      secondary: IconButton(
                        tooltip: tr('Search the library for this'),
                        icon: const Icon(Icons.menu_book_outlined, size: 20),
                        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => LibraryScreen(initialQuery: t['topic'].toString().split(':').first.split('(').first.trim()))),
                      ),
                    ),
                ],
              ),
              _plain('rot_pres', 'Common presentations', Icons.sick_outlined, RefData.strings(data['commonPresentations'])),
              _plain('rot_red', 'Red flags', Icons.flag_outlined, RefData.strings(data['redFlags']), tint: cs.error),
              _procedures(data),
              _targets(data),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _cards,
                builder: (context, cs2) {
                  final list = [for (final c in cs2.data ?? const <Map<String, dynamic>>[]) if (RefData.cardMatches(c, _spec)) c];
                  if (list.isEmpty) return const SizedBox.shrink();
                  return Fold(
                    id: 'rot_cards',
                    title: tr('Presentation cards'),
                    icon: Icons.view_agenda_outlined,
                    subtitle: '${list.length}',
                    children: [
                      for (final c in list)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: m.Text(c['presentation'].toString()),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CardDetailScreen(card: c))),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Text('Topic lists come from public curricula and were drafted with an AI assistant. Check them against your own program.', style: theme.textTheme.bodySmall),
            ]);
          },
        ),
      ),
    );
  }

  /// The weekly plan of the person's rotation in this specialty: this week's topics and a way into the whole plan.
  Widget _planCard(ThemeData theme, List<Map<String, dynamic>> topics) {
    final mine = [for (final r in store.rotations) if ('${r['name']}' == _spec && '${r['start']}'.isNotEmpty) r]..sort((a, b) => '${b['start']}'.compareTo('${a['start']}'));
    if (topics.isEmpty) return const SizedBox.shrink();
    if (mine.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: AppCard(child: Padding(padding: const EdgeInsets.all(14), child: Text('Add a rotation of this specialty with its dates to get a weekly study plan.', style: theme.textTheme.bodySmall))),
      );
    }
    final r = store.currentRotation() != null && '${store.currentRotation()!['name']}' == _spec ? store.currentRotation()! : mine.first;
    final start = DateTime.tryParse('${r['start']}') ?? DateTime.now();
    final end = DateTime.tryParse('${r['end']}');
    final weeks = RotationPlan.weeksOf(start, end);
    final week = RotationPlan.currentWeek(start, weeks, DateTime.now());
    final plan = RotationPlan.build(topics, weeks, moved: RotationPlanStore.moved('${r['id']}'));
    final thisWeek = [for (final t in plan) if (t.week == week) t.topic];
    final done = _done();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => RotationPlanScreen(rotation: r))).then((_) => mounted ? setState(() {}) : null),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.event_note_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Weekly study plan', style: theme.textTheme.titleSmall)),
                Text(trp('Week {a} of {b}', {'a': week, 'b': weeks}), style: theme.textTheme.labelMedium),
                const Icon(Icons.chevron_right),
              ]),
              const SizedBox(height: 6),
              if (thisWeek.isEmpty)
                Text('Review and catch up', style: theme.textTheme.bodySmall)
              else
                for (final t in thisWeek.take(4))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(done.contains(t) ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: done.contains(t) ? theme.colorScheme.primary : theme.colorScheme.outline),
                      const SizedBox(width: 6),
                      Expanded(child: _ltrText(t)),
                    ]),
                  ),
              if (thisWeek.length > 4) Text(trp('+ {n} more this week', {'n': thisWeek.length - 4}), style: theme.textTheme.bodySmall),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _plain(String id, String title, IconData icon, List<String> items, {Color? tint}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Fold(
      id: id,
      title: tr(title),
      icon: icon,
      children: [
        for (final s in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.circle, size: 7, color: tint ?? Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: _ltrText(s)),
            ]),
          ),
      ],
    );
  }

  Widget _procedures(Map<String, dynamic> data) {
    final list = [for (final p in (data['procedures'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
    if (list.isEmpty) return const SizedBox.shrink();
    return Fold(
      id: 'rot_proc',
      title: tr('Procedures'),
      icon: Icons.healing_outlined,
      children: [
        for (final p in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: _ltrText(p['name'].toString()),
            trailing: m.Text((p['level'] ?? '').toString(), style: Theme.of(context).textTheme.labelSmall),
          ),
      ],
    );
  }

  Widget _targets(Map<String, dynamic> data) {
    final list = [for (final p in (data['suggestedCaseTargets'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
    if (list.isEmpty) return const SizedBox.shrink();
    return Fold(
      id: 'rot_targets',
      title: tr('Suggested case targets'),
      icon: Icons.flag_circle_outlined,
      subtitle: tr('A suggestion, not your program\'s official numbers'),
      children: [
        for (final p in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: _ltrText(p['item'].toString()),
            trailing: m.Text('${p['count']}', style: Theme.of(context).textTheme.titleSmall),
          ),
      ],
    );
  }
}

// ============================================================ guidelines map

class GuidelinesScreen extends StatefulWidget {
  const GuidelinesScreen({super.key});
  @override
  State<GuidelinesScreen> createState() => _GuidelinesScreenState();
}

class _GuidelinesScreenState extends State<GuidelinesScreen> {
  String _q = '';
  late final Future<Map<String, dynamic>> _f = RefData.sources();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Guidelines')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (context, snap) {
          final g = [for (final e in (snap.data?['guidelines'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
          final q = _q.trim().toLowerCase();
          final hits = [for (final e in g) if (q.isEmpty || '${e['title']} ${e['topic']} ${e['specialty']} ${e['org']}'.toLowerCase().contains(q)) e];
          final by = <String, List<Map<String, dynamic>>>{};
          for (final e in hits) {
            by.putIfAbsent(e['specialty'].toString(), () => []).add(e);
          }
          final keys = by.keys.toList()..sort();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            TextField(
              key: const ValueKey('guide_search'),
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Search guidelines'), contentPadding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 8),
            Text('Links open in your browser. Guideline versions change: check the year and the status before you rely on one.', style: theme.textTheme.bodySmall),
            if (snap.connectionState != ConnectionState.done) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            for (final k in keys)
              Fold(
                id: 'guide_$k',
                title: k,
                icon: Icons.fact_check_outlined,
                subtitle: '${by[k]!.length}',
                initiallyOpen: q.isNotEmpty,
                children: [
                  for (final e in by[k]!)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: _ltrText(e['title'].toString()),
                      subtitle: _ltrText('${e['org']} · ${e['year']}${e['status'] == 'current' ? '' : ' · ${e['status']}'}'),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => openUrl(context, e['url'].toString()),
                    ),
                ],
              ),
          ]);
        },
      ),
    );
  }
}

// ============================================================ privacy policy

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});
  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  late final Future<Map<String, dynamic>> _f = RefData.privacy();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = isAr ? 'ar' : 'en';
    return Scaffold(
      appBar: AppBar(title: Text('Privacy policy')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          final p = Map<String, dynamic>.from(d[lang] as Map);
          final contact = (d['contact'] ?? '').toString();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            m.Text(p['title'].toString(), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            m.Text('${p['effective']}  ·  ${p['developer']}', style: theme.textTheme.bodySmall),
            for (final s in (p['sections'] as List))
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  m.Text((s as Map)['heading'].toString(), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  m.Text(s['text'].toString()),
                ]),
              ),
            if (contact.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 14), child: m.Text('${tr('Contact')}: $contact')),
            const SizedBox(height: 14),
            AppCard(child: Padding(padding: const EdgeInsets.all(12), child: m.Text((d['disclaimer'] as Map)[lang].toString()))),
          ]);
        },
      ),
    );
  }
}
