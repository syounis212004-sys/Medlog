import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as mm show Text;

import 'ai/ai_api.dart';
import 'ai/ai_help.dart';
import 'i18n.dart';
import 'screens_ai_tools.dart' show AiEntry, AiStateBuilder;
import 'ui.dart';
import 'widgets.dart';

/// "How do I...?" help. The offline FAQ search always works; the AI rephrase is an optional extra and receives
/// only the question and the FAQ text (no user data).
class AppHelpScreen extends StatefulWidget {
  final String initialQuery;
  const AppHelpScreen({super.key, this.initialQuery = ''});

  @override
  State<AppHelpScreen> createState() => _AppHelpScreenState();
}

class _Msg {
  final String q;
  final List<FaqEntry> hits;
  String? ai;
  bool busy = false;
  _Msg(this.q, this.hits);
}

class _AppHelpScreenState extends State<AppHelpScreen> {
  final TextEditingController _c = TextEditingController();
  final ScrollController _sc = ScrollController();
  final List<_Msg> _msgs = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask(widget.initialQuery));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _sc.dispose();
    super.dispose();
  }

  void _ask(String q) {
    final t = q.trim();
    if (t.isEmpty) return;
    final hits = searchFaq(t, limit: 3).map((h) => h.entry).toList();
    setState(() => _msgs.add(_Msg(t, hits)));
    _c.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) _sc.animateTo(_sc.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _rephrase(_Msg m) async {
    setState(() => m.busy = true);
    final r = await aiRephrase(m.q, m.hits);
    if (!mounted) return;
    setState(() {
      m.busy = false;
      m.ai = r;
    });
    if (r == null) snack(context, tr('AI is not available right now. The local tools still work.'));
  }

  Widget _entry(FaqEntry e) {
    final theme = Theme.of(context);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.q, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(e.a, style: const TextStyle(height: 1.4)),
        ]),
      ),
    );
  }

  Widget _message(_Msg m) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
          child: DirText(m.q),
        ),
      ),
      if (m.hits.isEmpty)
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('I could not find this in the help. Try other words, or browse all topics below.'),
          ),
        )
      else ...[
        for (var i = 0; i < m.hits.length; i++) _entry(m.hits[i]),
        AiStateBuilder(builder: (context, enabled, online) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (m.ai == null)
                AiEntry(label: tr('Explain simply with AI'), feature: 'help_faq', onPressed: m.busy ? null : () => _rephrase(m)),
              if (m.busy) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
              if (m.ai != null) AiOutputCard(text: m.ai!, feature: 'help_faq'),
              if (m.ai == null && !m.busy && enabled)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Only your question and the help text above are sent. No case data.', style: Theme.of(context).textTheme.bodySmall),
                ),
            ]),
          );
        }),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('App help')),
      body: Column(children: [
        Expanded(
          child: ListView(
            controller: _sc,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.support_agent),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Ask how to do something in MedLog. Answers come from the built-in help and work offline.')),
                  ]),
                ),
              ),
              if (_msgs.isEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final s in kHelpStarters) ActionChip(label: mm.Text(tr(s)), onPressed: () => _ask(tr(s))),
                ]),
              ],
              for (final m in _msgs) _message(m),
              const SizedBox(height: 12),
              Fold(
                id: 'help_all',
                title: tr('All topics'),
                icon: Icons.list_alt,
                children: [
                  for (final e in kFaq)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.q, style: theme.textTheme.bodyMedium),
                      onTap: () => setState(() => _msgs.add(_Msg(tr(e.q), [e]))),
                    ),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _ask,
                  decoration: InputDecoration(hintText: tr('How do I...?'), isDense: true, prefixIcon: const Icon(Icons.search)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: () => _ask(_c.text), tooltip: tr('Search'), icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}

void openAppHelp(BuildContext context, {String query = ''}) =>
    Navigator.push<void>(context, MaterialPageRoute(builder: (_) => AppHelpScreen(initialQuery: query)));
