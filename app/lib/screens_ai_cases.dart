import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as mm show Text;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'ai/ai_api.dart';
import 'ai/ai_case_payload.dart';
import 'ai/ai_cases.dart';
import 'ai/ai_context.dart';
import 'ai/ai_doc_api.dart';
import 'ai/ai_study_hooks.dart';
import 'ai/ai_tools.dart';
import 'ai/voice_input.dart';
import 'data.dart';
import 'i18n.dart';
import 'library.dart';
import 'screens_ai_settings.dart';
import 'screens_ai_tools.dart';
import 'screens_library.dart' show openArticle;
import 'ui.dart';
import 'widgets.dart';

/// AI case assistant. Every AI tab has a local alternative and never shows an error when AI is off or offline.
/// AI only suggests: nothing reaches the record before the user taps Apply (with Undo and provenance in rec.d['aiSuggested']).
class AiCaseScreen extends StatefulWidget {
  final CaseRec rec;

  /// Called after the record was changed by an Apply / Undo / tag / card action (the editor refreshes its fields).
  final VoidCallback? onChanged;
  final int initialTab;

  /// A note to start the "Fields" tab with (the quick note of the case).
  final String initialNote;
  const AiCaseScreen({super.key, required this.rec, this.onChanged, this.initialTab = 0, this.initialNote = ''});

  @override
  State<AiCaseScreen> createState() => _AiCaseScreenState();
}

class _LibLink {
  final String packId, title;
  final int index;
  const _LibLink(this.packId, this.index, this.title);
}

class _AiCaseScreenState extends State<AiCaseScreen> {
  CaseRec get rec => widget.rec;
  late AiCasePayload _p;

  // discuss
  CaseDiscussion? _disc;
  bool _discBusy = false;
  String _discNote = '';
  final Map<String, Future<List<_LibLink>>> _links = {};

  // socratic
  final List<SocraticTurn> _turns = [];
  bool _socBusy = false, _socDone = false;
  final TextEditingController _ans = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  // fields from a note
  final TextEditingController _note = TextEditingController();
  SuggestionSet? _sug;
  bool _sugBusy = false;
  AiUndo? _undo;
  String _undoLabel = '';
  ScrubResult? _noteClean;

  // check / tags
  bool _tagBusy = false;
  List<String> _aiTags = [];
  String _aiSpec = '';

  // handover
  List<String> _cont = [];
  bool _contBusy = false;

  // learning
  List<String> _questions = [];
  bool _qBusy = false;
  late List<CardDraft> _drafts;
  late List<bool> _draftOn;

  @override
  void initState() {
    super.initState();
    if (widget.initialNote.trim().isNotEmpty) _note.text = widget.initialNote;
    _refresh();
    _loadCached();
  }

  @override
  void dispose() {
    _ans.dispose();
    _note.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _refresh() {
    _p = buildCasePayload(rec);
    _drafts = cardsFromCase(rec);
    _draftOn = List<bool>.filled(_drafts.length, true);
  }

  /// Answers stored earlier can be re-read offline without sending anything.
  void _loadCached() {
    if (_p.blocked || _p.isEmpty) return;
    try {
      final d = AiCache.get(_p.cacheKey('case_ddx'));
      if (d != null && d['json'] is Map) {
        _disc = CaseDiscussion.fromJson(Map<String, dynamic>.from(d['json'] as Map));
        _discNote = 'Saved answer from earlier';
      }
      final h = AiCache.get(_p.cacheKey('case_handover'));
      if (h != null && h['json'] is Map) _cont = _strList((h['json'] as Map)['contingencies']);
      final r = AiCache.get(_p.cacheKey('case_reflect'));
      if (r != null && r['json'] is Map) _questions = _strList((r['json'] as Map)['questions']).take(3).toList();
    } catch (_) {}
  }

  static List<String> _strList(Object? v) =>
      v is List ? [for (final e in v) if (e.toString().trim().isNotEmpty) e.toString().trim()] : <String>[];

  /// Refreshes the screen and the editor first, then writes the file (the UI never waits for the disk).
  Future<void> _saved() async {
    widget.onChanged?.call();
    _refresh();
    if (mounted) setState(() {});
    await store.saveCase(rec);
  }

  // ------------------------------------------------------------ AI call helper

  Future<AiResult?> _call(AiRequest r) async {
    final res = await Ai.run(r, context: context);
    if (!mounted) return null;
    if (res.cancelled) return null;
    if (res.offline) {
      snack(context, tr('AI is not available right now. The local tools still work.'));
      return null;
    }
    if (!res.ok) {
      snack(context, (res.error ?? '').isEmpty ? tr('The AI request failed.') : res.error!);
      return null;
    }
    return res;
  }

  // ------------------------------------------------------------ small widgets

  Widget _card(Widget child, {Color? color}) => AppCard(color: color, child: Padding(padding: const EdgeInsets.all(12), child: child));

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      );

  Widget _bullets(List<String> l) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in l)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const mm.Text('• '),
                Expanded(child: DirText(s)),
              ]),
            ),
        ],
      );

  Widget _disclaimer() {
    final cs = Theme.of(context).colorScheme;
    return _card(
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, color: cs.onTertiaryContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              'AI suggestions are for your consideration only. They can be wrong or incomplete. You are responsible for every clinical decision: check the library, the guidelines and your senior.',
              style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
        ),
      ]),
      color: cs.tertiaryContainer,
    );
  }

  Widget _busy() => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));

  /// AI tab frame: blocked case / AI off / offline cards, with the local alternative below.
  Widget _gate({required Widget Function() ai, Widget? local}) {
    final cs = Theme.of(context).colorScheme;
    return AiBuilder(builder: (context, enabled, online) {
      final kids = <Widget>[];
      if (_p.blocked) {
        kids.add(_card(
          Row(children: [
            const Icon(Icons.block),
            const SizedBox(width: 10),
            Expanded(child: Text('This case is marked "Never send this case to AI". Turn it off in the case Info tab to use these tools.')),
          ]),
        ));
      } else if (!enabled) {
        kids.add(_card(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.auto_awesome_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text('AI is off. MedLog works fully without it. You can turn on the optional assistant in Settings.')),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiSettingsScreen())),
              icon: const Icon(Icons.settings_outlined),
              label: Text('Open AI settings'),
            ),
          ]),
        ));
      } else {
        if (!online) {
          kids.add(_card(
            Row(children: [
              Icon(Icons.cloud_off, color: cs.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(child: Text('You are offline. Saved answers can still be read; new AI requests need internet.')),
            ]),
            color: cs.secondaryContainer,
          ));
        }
        kids.add(ai());
      }
      if (local != null) kids.add(local);
      return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: kids);
    });
  }

  /// "What leaves the phone": the de-identified fields and what the local cleaning removed.
  Widget _sendPreview({Map<String, String>? extra, Map<String, String>? only}) {
    final f = {...(only ?? _p.fields), ...?extra};
    return Fold(
      id: 'aicase_preview',
      title: tr('What will be sent'),
      icon: Icons.visibility_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Only these de-identified fields. You see them again and can untick any before sending.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        for (final e in f.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              DirText(e.value),
            ]),
          ),
        if (_p.removed.isNotEmpty) ...[
          Text('Removed before sending', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Text(_p.removed.map(tr).join(', ')),
        ],
        const SizedBox(height: 4),
        Text('Never sent: code, names, initials, dates, hospital or doctor names, images.', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _emptyCase() => _card(Text('This case has no content to discuss yet. Add the history and examination first.'));

  // ------------------------------------------------------------ libraries chips (resolved locally)

  Future<List<_LibLink>> _resolve(String name) {
    return _links.putIfAbsent(name, () async {
      try {
        // only articles about this very diagnosis (the whole name), the user's own books first
        final hits = await library.searchEx(name, limit: 6, strict: true);
        final good = hits.where((h) => h.titleMatch).toList();
        final use = (good.isNotEmpty ? good : hits).take(3);
        return [for (final h in use) _LibLink(h.packId, h.index, h.title)];
      } catch (_) {
        return <_LibLink>[];
      }
    });
  }

  Widget _readChips(String name) {
    return FutureBuilder<List<_LibLink>>(
      future: _resolve(name),
      builder: (context, snap) {
        final l = snap.data ?? const <_LibLink>[];
        if (l.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final k in l)
              ActionChip(
                avatar: const Icon(Icons.menu_book_outlined, size: 16),
                label: mm.Text('${tr('Read about it')}: ${k.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                onPressed: () => openArticle(context, k.packId, k.index),
              ),
          ]),
        );
      },
    );
  }

  // ================================================================ (a) discuss

  Future<void> _discuss() async {
    if (_p.isEmpty) return;
    setState(() => _discBusy = true);
    final r = await _call(discussRequest(_p));
    if (!mounted) return;
    setState(() {
      _discBusy = false;
      if (r != null) {
        final j = r.json;
        if (j == null) {
          snack(context, tr('The answer could not be read. Try again.'));
        } else {
          _disc = CaseDiscussion.fromJson(j);
          _discNote = r.fromCache ? 'Saved answer from earlier' : '';
        }
      }
    });
  }

  List<String> _ownDx() {
    final raw = [rec.s('finalDx'), rec.s('workingDx'), rec.s('ddx')].join('\n');
    final out = <String>[];
    for (final s in raw.split(RegExp(r'[\n;,]|\d\)'))) {
      final t = s.trim();
      if (t.length >= 3 && t.length <= 60 && !out.contains(t)) out.add(t);
    }
    return out.take(5).toList();
  }

  Widget _discussTab() {
    final d = _disc;
    return _gate(
      ai: () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _disclaimer(),
        const SizedBox(height: 8),
        if (_p.isEmpty) _emptyCase() else _sendPreview(),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AiButton(label: tr('Discuss my case'), feature: 'case_ddx', filled: true, onPressed: _discBusy || _p.isEmpty ? null : _discuss),
        ),
        if (_discBusy) _busy(),
        if (d != null && !_discBusy) ...[
          if (_discNote.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_discNote, style: Theme.of(context).textTheme.bodySmall)),
          _h(tr('For your consideration')),
          if (d.summary.isNotEmpty) DirText(d.summary),
          for (final x in d.dx) _dxCard(x),
          if (d.redFlags.isNotEmpty) ...[_h(tr('Red flags to exclude')), _bullets(d.redFlags)],
          if (d.dontMiss.isNotEmpty) ...[_h(tr('Do not miss')), _bullets(d.dontMiss)],
          if (d.history.isNotEmpty) ...[_h(tr('Focused history to consider')), _bullets(d.history)],
          if (d.exam.isNotEmpty) ...[_h(tr('Focused examination to consider')), _bullets(d.exam)],
          if (d.investigations.isNotEmpty) ...[_h(tr('Investigations to consider')), _bullets(d.investigations)],
          if (d.wouldChange.isNotEmpty) ...[_h(tr('What would change management')), _bullets(d.wouldChange)],
          if (d.missing.isNotEmpty) ...[_h(tr('Missing in your record')), _bullets(d.missing)],
          if (d.teaching.isNotEmpty) ...[_h(tr('Learning points')), _bullets(d.teaching)],
          const SizedBox(height: 8),
          Text('AI-generated, not medically reviewed', style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
      local: _ownDxSection(),
    );
  }

  Widget _dxCard(DxItem x) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DirText(x.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (x.likelihood.isNotEmpty)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(x.likelihood.toLowerCase().contains('more') ? 'more likely' : (x.likelihood.toLowerCase().contains('less') ? 'less likely' : 'possible')),
              ),
          ]),
          if (x.why.isNotEmpty) ...[const SizedBox(height: 6), DirText(x.why)],
          if (x.forList.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('For (from your case)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
            _bullets(x.forList),
          ],
          if (x.against.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Against / missing', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.error)),
            _bullets(x.against),
          ],
          if (x.features.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Typical features to look for', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.tertiary)),
            _bullets(x.features),
          ],
          if (x.tellsApart.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('What tells it apart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.secondary)),
            DirText(x.tellsApart),
          ],
          if (x.confirm.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('To confirm or exclude', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.secondary)),
            _bullets(x.confirm),
          ],
          _readChips(x.name),
        ]),
      ),
    );
  }

  /// Local alternative: library articles for the diagnoses the user wrote.
  Widget _ownDxSection() {
    final l = _ownDx();
    if (l.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your diagnoses: read about them', style: const TextStyle(fontWeight: FontWeight.w800)),
        for (final n in l)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [DirText(n), _readChips(n)]),
          ),
      ])),
    );
  }

  // ================================================================ (b) Socratic

  Future<void> _socStep() async {
    if (_p.isEmpty) return;
    setState(() => _socBusy = true);
    final answers = _turns.where((t) => t.role == 'me').length;
    final r = await _call(socraticRequest(_p, _turns, answers));
    if (!mounted) return;
    setState(() {
      _socBusy = false;
      if (r?.json != null) {
        final j = r!.json!;
        final fb = (j['feedback'] ?? '').toString().trim();
        final q = (j['question'] ?? '').toString().trim();
        final done = j['done'] == true || answers >= kSocraticMaxTurns;
        final txt = [fb, q].where((e) => e.isNotEmpty).join('\n\n');
        if (txt.isNotEmpty) _turns.add(SocraticTurn('ai', txt));
        if (done || q.isEmpty) _socDone = true;
      } else if (r != null) {
        snack(context, tr('The answer could not be read. Try again.'));
      }
    });
    _scrollChat();
  }

  void _scrollChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
    });
  }

  Future<void> _socSend() async {
    final t = _ans.text.trim();
    if (t.isEmpty || _socBusy) return;
    // what the learner typed leaves the phone too: same local cleaning as the case text
    final clean = cleanFreeText(t, knownIdentifiers(rec), <String>[]);
    _ans.clear();
    setState(() => _turns.add(SocraticTurn('me', clean)));
    _scrollChat();
    await _socStep();
  }

  Widget _bubble(SocraticTurn t) {
    final cs = Theme.of(context).colorScheme;
    final me = t.role == 'me';
    return Align(
      alignment: me ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        decoration: BoxDecoration(
          color: me ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(me ? 'You' : 'Tutor (AI)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          DirText(t.text),
        ]),
      ),
    );
  }

  Widget _socraticTab() {
    final answers = _turns.where((t) => t.role == 'me').length;
    return _gate(
      ai: () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _disclaimer(),
        const SizedBox(height: 8),
        if (_turns.isEmpty) ...[
          mm.Text(trp('The tutor asks you one question at a time about this case (your differential, what you would order...). You answer, then you get feedback and the next question. Up to {n} questions.',
              {'n': kSocraticMaxTurns})),
          const SizedBox(height: 8),
          if (_p.isEmpty) _emptyCase() else _sendPreview(),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AiButton(label: tr('Start Socratic mode'), feature: 'case_socratic', filled: true, onPressed: _socBusy || _p.isEmpty ? null : _socStep),
          ),
        ] else ...[
          Text(trp('Answer {a} of {b}', {'a': answers.clamp(0, kSocraticMaxTurns), 'b': kSocraticMaxTurns}), style: Theme.of(context).textTheme.bodySmall),
          for (final t in _turns) _bubble(t),
        ],
        if (_socBusy) _busy(),
        if (_turns.isNotEmpty && !_socBusy && !_socDone) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _ans,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Your answer'), suffixIcon: VoiceInputButton(controller: _ans)),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: _socSend, icon: const Icon(Icons.send), label: Text('Send answer')),
            TextButton(onPressed: () => setState(() => _socDone = true), child: Text('Finish')),
          ]),
        ],
        if (_socDone && _turns.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _turns.clear();
                  _socDone = false;
                }),
                icon: const Icon(Icons.restart_alt),
                label: Text('Start again'),
              ),
            ]),
          ),
      ]),
      local: _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Questions to ask yourself', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        _bullets(localReflectionPrompts(rec)),
      ])),
    );
  }

  // ================================================================ (c) suggest fields from a note

  void _checkNote() {
    setState(() => _noteClean = cleanNote(_note.text, forCase: rec));
  }

  Future<void> _suggest() async {
    final c = cleanNote(_note.text, forCase: rec);
    if (c.text.trim().length < 15) {
      snack(context, tr('Write or paste a longer note first.'));
      return;
    }
    setState(() {
      _noteClean = c;
      _sugBusy = true;
    });
    final r = await _call(suggestFieldsRequest(c.text));
    if (!mounted) return;
    setState(() {
      _sugBusy = false;
      if (r?.json != null) {
        _sug = parseSuggestions(r!.json!, rec);
        _undo = null;
        if (_sug!.items.isEmpty) snack(context, tr('Nothing new to suggest from this note.'));
      } else if (r != null) {
        snack(context, tr('The answer could not be read. Try again.'));
      }
    });
  }

  Future<void> _applyChosen() async {
    final s = _sug;
    if (s == null) return;
    final chosen = s.items.where((e) => e.apply).toList();
    if (chosen.isEmpty) return;
    final u = applySuggestions(rec, chosen);
    _undo = u;
    _undoLabel = trp('{n} fields applied', {'n': chosen.length});
    _sug = SuggestionSet([for (final e in s.items) if (!e.apply) e], s.procedures);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: mm.Text(_undoLabel),
        action: SnackBarAction(label: tr('Undo'), onPressed: _undoLast),
      ));
    await _saved();
  }

  Future<void> _undoLast() async {
    final u = _undo;
    if (u == null) return;
    undoSuggestions(rec, u);
    _undo = null;
    if (mounted) snack(context, tr('Undone.'));
    await _saved();
  }

  Widget _undoBanner() {
    if (_undo == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return _card(
      Row(children: [
        const Icon(Icons.check_circle_outline),
        const SizedBox(width: 10),
        Expanded(child: mm.Text(_undoLabel)),
        TextButton(onPressed: _undoLast, child: Text('Undo')),
      ]),
      color: cs.secondaryContainer,
    );
  }

  Widget _fieldsTab() {
    final s = _sug;
    final aiMarked = rec.d['aiSuggested'] is List ? (rec.d['aiSuggested'] as List).map((e) => kSuggestable[e] != null ? tr(kSuggestable[e]!) : '$e').toList() : <String>[];
    return _gate(
      ai: () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _disclaimer(),
        const SizedBox(height: 8),
        Text('Paste a free-text note or dictate it with the microphone button. The note is cleaned and shown to you before anything is sent. Nothing is saved until you tap Apply.'),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          minLines: 4,
          maxLines: 10,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) {
            if (_noteClean != null) setState(() => _noteClean = null);
          },
          decoration: InputDecoration(
            labelText: tr('Clinical note'),
            alignLabelWithHint: true,
            suffixIcon: VoiceInputButton(controller: _note, onChanged: () => setState(() => _noteClean = null)),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(onPressed: _checkNote, icon: const Icon(Icons.cleaning_services_outlined), label: Text('Show what will be sent')),
          AiButton(label: tr('Suggest fields'), feature: 'case_fields', filled: true, onPressed: _sugBusy ? null : _suggest),
        ]),
        if (_noteClean != null) ...[
          const SizedBox(height: 8),
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Cleaned note (this is what leaves the phone)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            DirText(_noteClean!.text.isEmpty ? '-' : _noteClean!.text),
            if (_noteClean!.removed.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Removed before sending', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              mm.Text(_noteClean!.removed.map(tr).join(', ')),
            ],
          ])),
        ],
        if (_sugBusy) _busy(),
        _undoBanner(),
        if (s != null && s.items.isNotEmpty) ...[
          _h(tr('Suggested values')),
          Text('Tick what you want to apply. Fields that already have text are not ticked: ticking replaces them.', style: Theme.of(context).textTheme.bodySmall),
          for (final it in s.items)
            AppCard(
              child: CheckboxListTile(
                value: it.apply,
                onChanged: (v) => setState(() => it.apply = v == true),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(it.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (it.current.trim().isNotEmpty) ...[
                    Text('Now', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    DirText(it.current),
                    const SizedBox(height: 4),
                  ],
                  Text('Suggested', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  DirText(it.suggested),
                  if (it.overwrites) Text('Replaces what you wrote', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error)),
                ]),
              ),
            ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: s.items.any((e) => e.apply) ? _applyChosen : null,
            icon: const Icon(Icons.done_all),
            label: Text(trp('Apply selected ({n})', {'n': s.items.where((e) => e.apply).length})),
          ),
        ],
        if (s != null && s.procedures.isNotEmpty) ...[
          _h(tr('Procedures mentioned (log them separately)')),
          _bullets(s.procedures),
        ],
        if (aiMarked.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('${tr('Fields filled from AI suggestions')}: ${aiMarked.join(', ')}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
      local: _card(Text('Without AI: use "Quick fill from specialty template" in the case menu, or type directly in the case tabs.')),
    );
  }

  // ================================================================ (d) missing / inconsistent + tags

  Future<void> _suggestTags() async {
    setState(() => _tagBusy = true);
    final r = await _call(tagsRequest(_p));
    if (!mounted) return;
    setState(() {
      _tagBusy = false;
      final j = r?.json;
      if (j != null) {
        _aiTags = _strList(j['tags']).map((e) => e.replaceAll('#', '').trim().replaceAll(RegExp(r'\s+'), '_').toLowerCase()).where((e) => e.isNotEmpty && !rec.tags.contains(e)).take(5).toList();
        final sp = (j['specialty'] ?? '').toString().trim();
        _aiSpec = kSpecialtyNames.contains(sp) && sp != rec.s('specialty') ? sp : '';
      } else if (r != null) {
        snack(context, tr('The answer could not be read. Try again.'));
      }
    });
  }

  Future<void> _addTag(String t, {bool ai = false}) async {
    if (ai) {
      final u = applySuggestions(rec, [FieldSuggestion('tags', 'Tags', rec.tags.join(', '), t, apply: true)]);
      _undo = u;
      _undoLabel = trp('Tag added: {t}', {'t': t});
    } else {
      final l = rec.tags;
      if (!l.contains(t)) l.add(t);
      rec.tags = l;
    }
    _aiTags.remove(t);
    await _saved();
  }

  Future<void> _setSpec(String s) async {
    _undo = applySuggestions(rec, [FieldSuggestion('specialty', 'Specialty', rec.s('specialty'), s, apply: true)]);
    _undoLabel = trp('Specialty set: {t}', {'t': tr(s)});
    _aiSpec = '';
    await _saved();
  }

  Widget _checkTab() {
    final issues = checkCase(rec);
    final cs = Theme.of(context).colorScheme;
    final localTags = suggestTagsLocal(rec);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
      _card(Row(children: [
        Icon(issues.isEmpty ? Icons.verified_outlined : Icons.fact_check_outlined, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(issues.isEmpty ? 'No missing or inconsistent fields found.' : trp('{n} things to check', {'n': issues.length}),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]), color: issues.isEmpty ? cs.primaryContainer.withAlpha(120) : cs.tertiaryContainer),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Text('These checks run on your phone, with no internet and no AI.', style: Theme.of(context).textTheme.bodySmall),
      ),
      for (final i in issues)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(i.warn ? Icons.warning_amber_rounded : Icons.edit_note, color: i.warn ? cs.error : cs.primary),
          title: mm.Text(i.display),
        ),
      _undoBanner(),
      _h(tr('Suggested tags')),
      if (localTags.isEmpty && _aiTags.isEmpty && _aiSpec.isEmpty)
        Text('No tag suggestions from your own tags yet.', style: Theme.of(context).textTheme.bodySmall),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final t in localTags) ActionChip(avatar: const Icon(Icons.add, size: 16), label: mm.Text(tagLabel(t)), onPressed: () => _addTag(t)),
        for (final t in _aiTags) ActionChip(avatar: const Icon(Icons.auto_awesome, size: 16), label: mm.Text(tagLabel(t)), onPressed: () => _addTag(t, ai: true)),
        if (_aiSpec.isNotEmpty)
          ActionChip(avatar: const Icon(Icons.auto_awesome, size: 16), label: mm.Text('${tr('Specialty')}: ${tr(_aiSpec)}'), onPressed: () => _setSpec(_aiSpec)),
      ]),
      const SizedBox(height: 8),
      if (!_p.blocked)
        AiButton(label: tr('Suggest specialty and tags'), feature: 'case_tags', onPressed: _tagBusy || _p.isEmpty ? null : _suggestTags),
      if (_tagBusy) _busy(),
    ]);
  }

  // ================================================================ (e) handover

  Future<void> _draftContingency() async {
    setState(() => _contBusy = true);
    final r = await _call(handoverRequest(_p));
    if (!mounted) return;
    setState(() {
      _contBusy = false;
      final j = r?.json;
      if (j != null) {
        _cont = _strList(j['contingencies']).take(5).toList();
      } else if (r != null) {
        snack(context, tr('The answer could not be read. Try again.'));
      }
    });
  }

  String _handover() => handoverText(rec, contingencies: [for (final c in _cont) '$c [AI draft]']);

  Widget _handoverTab() {
    final text = _handover();
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
      Text('Built on your phone from the case fields. It uses the case code, never a name.', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      _card(SelectableText(text, textDirection: textDirectionFor(text), style: const TextStyle(height: 1.4))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (mounted) snack(context, tr('Copied'));
          },
          icon: const Icon(Icons.copy),
          label: Text('Copy'),
        ),
        OutlinedButton.icon(onPressed: () => Share.share(text), icon: const Icon(Icons.ios_share), label: Text('Share')),
      ]),
      AiBuilder(builder: (context, enabled, online) {
        if (!enabled || _p.blocked) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AiButton(label: tr('Draft contingency plan'), feature: 'case_handover', onPressed: _contBusy || _p.isEmpty ? null : _draftContingency),
            if (_contBusy) _busy(),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Only the de-identified fields are sent, and you preview them first. The AI lines are marked [AI draft]: check them.', style: Theme.of(context).textTheme.bodySmall),
            ),
          ]),
        );
      }),
    ]);
  }

  // ================================================================ (f) learning

  Future<void> _askReflect() async {
    setState(() => _qBusy = true);
    final r = await _call(reflectRequest(_p));
    if (!mounted) return;
    setState(() {
      _qBusy = false;
      final j = r?.json;
      if (j != null) {
        final q = _strList(j['questions']).take(3).toList();
        if (q.isNotEmpty) _questions = q;
      } else if (r != null) {
        snack(context, tr('The answer could not be read. Try again.'));
      }
    });
  }

  Future<void> _makeCards() async {
    final chosen = [for (var i = 0; i < _drafts.length; i++) if (_draftOn[i]) _drafts[i]];
    if (chosen.isEmpty) return;
    final n = await saveCaseCards(rec, chosen);
    if (!mounted) return;
    snack(context, n == 0 ? tr('These cards already exist.') : trp('{n} review cards made.', {'n': n}));
  }

  Widget _learnTab() {
    final qs = _questions.isNotEmpty ? _questions : localReflectionPrompts(rec);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
      _h(tr('Reflect on this case')),
      _card(_bullets(qs)),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(_questions.isNotEmpty ? 'AI-generated questions: prompts only, the answers are yours to write.' : 'Questions made from your case. Answer them in "What I learned".',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      AiBuilder(builder: (context, enabled, online) {
        if (!enabled || _p.blocked) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AiButton(label: tr('Ask AI for 3 questions'), feature: 'case_reflect', onPressed: _qBusy || _p.isEmpty ? null : _askReflect),
            if (_qBusy) _busy(),
          ]),
        );
      }),
      _h(tr('Make review cards from this case')),
      if (_drafts.isEmpty)
        Text('Add a diagnosis, red flags or "What I learned" to make cards.', style: Theme.of(context).textTheme.bodySmall)
      else ...[
        Text('Cards are phrased from your own entries and join the spaced review. No names or code are in the question.', style: Theme.of(context).textTheme.bodySmall),
        for (var i = 0; i < _drafts.length; i++)
          AppCard(
            child: CheckboxListTile(
              value: _draftOn[i],
              onChanged: (v) => setState(() => _draftOn[i] = v == true),
              controlAffinity: ListTileControlAffinity.leading,
              title: DirText(_drafts[i].front, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: DirText(_drafts[i].back),
            ),
          ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: _draftOn.any((e) => e) ? _makeCards : null,
          icon: const Icon(Icons.style_outlined),
          label: Text('Make review cards'),
        ),
      ],
    ]);
  }


  // ================================================================ (g) senior / guidelines / patient / teach

  /// A tool tab: the case is de-identified, the user previews what leaves the phone, the answer is a labelled document.
  Widget _toolTab({
    required String intro,
    required String label,
    required String feature,
    required AiRequest Function() build,
    required Map<String, String> sends,
    IconData icon = Icons.auto_awesome,
    bool needsCites = true,
    bool narrative = false,
    String? draftNote,
    Widget Function(AiResult res)? footer,
    Widget? local,
    Key? panelKey,
  }) {
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
      if (_p.blocked)
        _card(Row(children: [
          const Icon(Icons.block),
          const SizedBox(width: 10),
          Expanded(child: Text('This case is marked "Never send this case to AI". Turn it off in the case Info tab to use these tools.')),
        ]))
      else ...[
        _disclaimer(),
        const SizedBox(height: 8),
        Text(intro),
        const SizedBox(height: 8),
        if (_p.isEmpty) _emptyCase() else _sendPreview(only: sends),
        const SizedBox(height: 8),
        AiRunPanel(
          key: panelKey,
          label: label,
          icon: icon,
          feature: feature,
          enabled: !_p.isEmpty,
          needsCites: needsCites,
          narrative: narrative,
          draftNote: draftNote,
          build: _p.isEmpty ? () => null : build,
          footer: footer,
        ),
      ],
      if (local != null) ...[const SizedBox(height: 8), local],
    ]);
  }

  Widget _seniorTab() => _toolTab(
        intro: tr('What would the senior ask, examine and order next on this case? Use it to rehearse before the ward round.'),
        label: tr('Prepare me for the senior'),
        feature: 'case_senior',
        icon: Icons.record_voice_over_outlined,
        needsCites: false,
        sends: _p.fields,
        build: () => seniorRequest(_p),
        local: _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Questions to ask yourself', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          _bullets(localReflectionPrompts(rec)),
        ])),
      );

  Widget _guidelineTab() {
    final sends = subsetFields(_p, kGuidelineLabels);
    if (!sends.containsKey('Working diagnosis') && !sends.containsKey('Final diagnosis') && (_p.fields['Chief complaint'] ?? '').isNotEmpty) {
      sends['Chief complaint'] = _p.fields['Chief complaint']!;
    }
    return _toolTab(
      intro: tr('Link this case to the guidelines that cover its working diagnosis: organisation, year and the main recommendation. Only the diagnosis, age group, sex and setting are sent. This gives general recommendations, never orders for this patient.'),
      label: tr('Link this case to guidelines'),
      feature: 'case_guideline',
      icon: Icons.rule_folder_outlined,
      sends: sends,
      build: () => guidelineRequest(_p),
      local: _ownDxSection(),
    );
  }

  Widget _patientTab() => _toolTab(
        intro: tr('A plain-language explanation you could give to the patient or family. It is a draft: check it with your senior and say it in your own words.'),
        label: tr('Explain this to a patient'),
        feature: 'case_patient',
        icon: Icons.record_voice_over_outlined,
        needsCites: false,
        draftNote: tr('DRAFT for you to check. Do not hand it to a patient as it is.'),
        sends: subsetFields(_p, ['Age group', 'Sex', 'Setting', 'Chief complaint', 'Working diagnosis', 'Final diagnosis', 'Investigations', 'Plan and management', 'Disposition', 'Follow-up']),
        build: () => patientExplainRequest(_p),
      );

  Widget _teachTab() => _toolTab(
        intro: tr('Teaching points and a 3-question mini quiz built from this case. You can save the cited questions to your AI bank and make review cards.'),
        label: tr('Teaching points and mini quiz'),
        feature: 'case_teach',
        icon: Icons.school_outlined,
        sends: subsetFields(_p, [
          'Age group', 'Sex', 'Setting', 'Specialty', 'Chief complaint', 'History of present illness', 'Vitals', 'Investigations',
          'Working diagnosis', 'Final diagnosis', 'Problem list',
        ]),
        build: () => teachRequest(_p),
        footer: (res) => _TeachFooter(res: res, topic: rec.title == '(no diagnosis yet)' ? rec.s('cc') : rec.title),
      );

  // ================================================================ build

  @override
  Widget build(BuildContext context) {
    Tab t(IconData i, String l) => Tab(height: 48, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 18), const SizedBox(width: 6), Text(l)]));
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'case', title: 'Case assistant'),
      child: DefaultTabController(
      length: 10,
      initialIndex: widget.initialTab.clamp(0, 9),
      child: Scaffold(
        appBar: AppBar(
          title: mm.Text('${tr('AI assistant')} • ${rec.s('code')}', maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              t(Icons.forum_outlined, tr('Discuss')),
              t(Icons.quiz_outlined, tr('Socratic')),
              t(Icons.auto_fix_high_outlined, tr('Fields')),
              t(Icons.fact_check_outlined, tr('Check')),
              t(Icons.swap_horiz, tr('Handover')),
              t(Icons.school_outlined, tr('Learn')),
              t(Icons.record_voice_over_outlined, tr('Senior')),
              t(Icons.rule_folder_outlined, tr('Guidelines')),
              t(Icons.family_restroom_outlined, tr('Patient')),
              t(Icons.quiz_outlined, tr('Teach')),
            ],
          ),
        ),
        body: TabBarView(
          children: [_discussTab(), _socraticTab(), _fieldsTab(), _checkTab(), _handoverTab(), _learnTab(), _seniorTab(), _guidelineTab(), _patientTab(), _teachTab()],
        ),
      ),
      ),
    );
  }
}

/// Mini quiz + save actions under the teaching points. Questions are saved only when they carry a citation.
class _TeachFooter extends StatefulWidget {
  final AiResult res;
  final String topic;
  const _TeachFooter({required this.res, required this.topic});
  @override
  State<_TeachFooter> createState() => _TeachFooterState();
}

class _TeachFooterState extends State<_TeachFooter> {
  final Set<int> _shown = {};
  String _msg = '';

  Future<void> _saveQuestions(AiDoc doc, List<MiniQuizQ> quiz) async {
    final a = await AiStudyHooks.makeQuestions(doc);
    final b = await saveMiniQuiz(quiz);
    if (!mounted) return;
    setState(() => _msg = (a + b) == 0 ? tr('No new cited questions to save.') : trp('{n} questions saved to your AI bank.', {'n': a + b}));
  }

  Future<void> _saveCards(AiDoc doc) async {
    final n = await AiStudyHooks.makeCards(doc, source: widget.topic);
    if (!mounted) return;
    setState(() => _msg = n == 0 ? tr('These cards already exist.') : trp('{n} review cards made.', {'n': n}));
  }

  @override
  Widget build(BuildContext context) {
    final doc = docOf(widget.res);
    final quiz = parseMiniQuiz(widget.res.json);
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (quiz.isNotEmpty) ...[
        Text('Mini quiz', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        for (var i = 0; i < quiz.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DirText('${i + 1}. ${quiz[i].q}', style: const TextStyle(fontWeight: FontWeight.w700)),
              for (var k = 0; k < quiz[i].options.length; k++) DirText('${String.fromCharCode(65 + k)}. ${quiz[i].options[k]}'),
              if (_shown.contains(i)) ...[
                const SizedBox(height: 2),
                DirText('${tr('Answer')}: ${quiz[i].answerText}${quiz[i].why.isEmpty ? '' : '\n${quiz[i].why}'}', style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                if (quiz[i].cite == null) Text('No source cited: not saved to the bank.', style: theme.textTheme.bodySmall),
              ] else
                TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: () => setState(() => _shown.add(i)), child: Text('Show answer')),
            ]),
          ),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        FilledButton.icon(onPressed: () => _saveQuestions(doc, quiz), icon: const Icon(Icons.psychology_alt_outlined), label: Text('Save cited questions to AI bank')),
        OutlinedButton.icon(onPressed: () => _saveCards(doc), icon: const Icon(Icons.style_outlined), label: Text('Make review cards')),
      ]),
      if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: mm.Text(_msg)),
    ]);
  }
}

/// Opens the assistant (from the case editor / detail menu).
Future<void> openAiCase(BuildContext context, CaseRec rec, {VoidCallback? onChanged, int tab = 0, String note = ''}) =>
    Navigator.push<void>(context, MaterialPageRoute(builder: (_) => AiCaseScreen(rec: rec, onChanged: onChanged, initialTab: tab, initialNote: note)));

// ================================================================ week / rotation summary (numbers only)

/// Plain local summary of the last 7 days (always works offline) + an optional AI narrative written from the same numbers.
/// Only aggregated counts leave the phone (no case content, no dates, no names), and only when the user taps the button.
class WeekSummaryCard extends StatefulWidget {
  const WeekSummaryCard({super.key});

  @override
  State<WeekSummaryCard> createState() => _WeekSummaryCardState();
}

final Map<String, String> _narrativeMemo = {};

class _WeekSummaryCardState extends State<WeekSummaryCard> {
  bool _busy = false;

  Future<void> _write(AiStats s) async {
    setState(() => _busy = true);
    final r = await Ai.run(summaryRequest(s), context: context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok && r.text.trim().isNotEmpty) {
        _narrativeMemo[s.digest] = r.text.trim();
      } else if (!r.cancelled) {
        snack(context, tr('AI is not available right now. The local tools still work.'));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = weekStats();
    if (s.isEmpty && s.goals.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final memo = _narrativeMemo[s.digest];
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.insights_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text('Week summary', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 6),
          DirText(s.plainText()),
          // only touches the connectivity monitor when AI is on (nothing to show otherwise)
          AnimatedBuilder(animation: AiStore.changes, builder: (context, _) => !Ai.enabled ? const SizedBox.shrink() : AiBuilder(builder: (context, enabled, online) {
            if (!enabled) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (memo == null)
                  AiButton(label: tr('Write a short summary'), feature: 'summary_week', onPressed: _busy ? null : () => _write(s)),
                if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                if (memo != null) AiOutputCard(text: memo, feature: 'summary_week'),
                if (memo == null && !_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Only the numbers above are sent, never case content.', style: theme.textTheme.bodySmall),
                  ),
              ]),
            );
          })),
        ]),
      ),
    );
  }
}

/// AI paragraph for a rotation report. Returns null when AI is off/offline/cancelled: the report then has only the plain numbers.
Future<String?> rotationNarrative(AiStats s, {BuildContext? context}) async {
  if (!Ai.enabled) return null;
  final r = await Ai.run(summaryRequest(s, kind: 'rotation'), context: context);
  if (!r.ok || r.text.trim().isEmpty) return null;
  return r.text.trim();
}
