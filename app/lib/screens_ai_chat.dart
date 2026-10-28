import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:flutter/services.dart';

import 'ai/ai_api.dart';
import 'ai/ai_chat.dart';
import 'ai/ai_context.dart';
import 'ai/ai_doc_api.dart';
import 'ai/ai_prefs.dart';
import 'ai/ai_prompts.dart';
import 'ai/ai_study_hooks.dart';
import 'data.dart';
import 'i18n.dart';
import 'library.dart';
import 'screens_ai_settings.dart';
import 'screens_article.dart';
import 'screens_library.dart';
import 'screens_notebooks.dart' show openUrl;
import 'widgets.dart';

/// The Ask-AI chat: multi-turn, context chips, source-mode selector, quick actions, formatted answers, sources checked by the app.

/// Opens the Ask-AI sheet (90 % height). With AI off or no key it explains and links to the AI settings (never a dead end).
/// [action]: a quick-action id to run at once (see quickActionsFor). [question]: text to send at once.
Future<void> openAskAi(BuildContext context, {AiScreenContext? ctx, String? action, String? question, String? mode}) async {
  await Ai.init();
  if (!context.mounted) return;
  if (!Ai.enabled) {
    await _showAiOff(context);
    return;
  }
  final c = ctx ?? AiContext.current.value;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) {
      final h = MediaQuery.of(context).size.height;
      return SizedBox(height: h * 0.9, child: AskAiChat(ctx: c, startAction: action, startQuestion: question, startMode: mode));
    },
  );
}

Future<void> _showAiOff(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(child: Text('Ask AI is off', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 12),
          Text('AI is optional. Turn it on and add your own key (Google Gemini has a free option) to ask any medical question, get deep-dives and see your library articles under each answer.'),
          const SizedBox(height: 8),
          Text('MedLog keeps working fully without it: your cases, library and quizzes never need AI.', style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.settings_outlined),
            label: Text('Open Library & AI settings'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
            },
          ),
        ]),
      );
    },
  );
}

// ================================================================ chat

class AskAiChat extends StatefulWidget {
  final AiScreenContext? ctx;
  final String? startAction;
  final String? startQuestion;
  final String? threadId;
  final String? startMode;
  const AskAiChat({super.key, this.ctx, this.startAction, this.startQuestion, this.threadId, this.startMode});
  @override
  State<AskAiChat> createState() => _AskAiChatState();
}

class _AskAiChatState extends State<AskAiChat> {
  late AiChatThread _t = (widget.threadId == null ? null : AiChats.byId(widget.threadId!)) ?? AiChatThread.create();
  late List<AiChip> _chips = chipsFor(widget.ctx);
  late String _mode = widget.startMode ?? AiPrefs.sourceMode;
  final TextEditingController _in = TextEditingController();
  final ScrollController _sc = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _busy = false;
  int _runId = 0; // a newer id means the user cancelled or started another request: late answers are ignored
  int _secs = 0;
  Timer? _tick;
  bool _lastTimedOut = false;
  String _lastQ = '';
  String _lastAction = '';
  final Map<int, List<LibHit>> _links = {};

  String get _kind => widget.ctx?.kind ?? 'other';

  @override
  void initState() {
    super.initState();
    if (!AiPrompts.modes.contains(_mode)) _mode = 'web';
    final a = widget.startAction;
    final q = widget.startQuestion;
    if (a != null && a.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _quick(a));
    } else if (q != null && q.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(q));
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _in.dispose();
    _sc.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _topic {
    for (final c in _chips) {
      if (c.title.isNotEmpty) return c.title;
    }
    return '';
  }

  void _quick(String id) {
    if (id == 'anything') {
      _focus.requestFocus();
      return;
    }
    final q = AiPrompts.quickQuestion(id, _topic);
    if (q.isEmpty) {
      _focus.requestFocus();
      return;
    }
    if (id == 'compare') {
      _in.text = q;
      _in.selection = TextSelection.collapsed(offset: q.length);
      _focus.requestFocus();
      _lastAction = id;
      return;
    }
    _send(q, action: id);
  }

  Future<void> _send(String text, {String action = ''}) async {
    final q = text.trim();
    if (q.isEmpty || _busy) return;
    HapticFeedback.selectionClick();
    final act = action.isNotEmpty ? action : _lastAction;
    _lastAction = '';
    final id = ++_runId;
    _secs = 0;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _busy) setState(() => _secs++);
    });
    setState(() {
      _busy = true;
      _lastQ = q;
      _t.msgs.add(AiChatMsg('user', q, mode: _mode, chips: [for (final c in _chips) c.label]));
      _in.clear();
    });
    _toBottom();
    final msg = await AiChatRunner.answer(context, _t, q, mode: _mode, chips: _chips, action: act);
    if (!mounted || id != _runId) return; // cancelled meanwhile
    _tick?.cancel();
    setState(() {
      _t.msgs.add(msg);
      _lastTimedOut = msg.failed && msg.timedOut;
      _busy = false;
    });
    await AiChats.save(_t);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sc.hasClients) _sc.animateTo(_sc.position.maxScrollExtent + 400, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  void _cancel() {
    _runId++; // the request may still finish in the background; its answer is dropped
    _tick?.cancel();
    setState(() {
      _busy = false;
      _lastTimedOut = true;
      _t.msgs.add(AiChatMsg('assistant', '', mode: _mode, failed: true, error: tr('Cancelled.'), timedOut: true));
    });
  }

  void _retry() {
    if (_lastQ.isEmpty || _busy) return;
    // a slow connection with live web search: ask again without it (the answer then says it may be outdated)
    if (_lastTimedOut && (_mode == 'web' || _mode == 'custom')) {
      _mode = 'model';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Trying again without web search.')));
    }
    _lastTimedOut = false;
    // drop the failed answer and the question, then ask again
    if (_t.msgs.isNotEmpty && _t.msgs.last.failed) _t.msgs.removeLast();
    if (_t.msgs.isNotEmpty && _t.msgs.last.role == 'user') _t.msgs.removeLast();
    _send(_lastQ);
  }

  void _newChat() {
    setState(() {
      _t = AiChatThread.create();
      _links.clear();
      _chips = chipsFor(widget.ctx);
    });
  }

  Future<void> _history() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _HistorySheet(),
    );
    if (id == null || !mounted) return;
    final th = AiChats.byId(id);
    if (th != null) {
      setState(() {
        _t = th;
        _links.clear();
      });
      _toBottom();
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Column(children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 4, 0),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(gradient: kAiGradient, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('Ask AI', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(tooltip: tr('Earlier chats'), icon: const Icon(Icons.history), onPressed: _history),
            IconButton(tooltip: tr('New chat'), icon: const Icon(Icons.add_comment_outlined), onPressed: _busy ? null : _newChat),
          ]),
        ),
        if (_chips.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(spacing: 6, runSpacing: 0, children: [
                for (final c in _chips)
                  InputChip(
                    key: ValueKey('chip_${c.kind}'),
                    avatar: Icon(_chipIcon(c.kind), size: 16),
                    label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 230), child: m.Text(c.label, overflow: TextOverflow.ellipsis)),
                    onDeleted: _busy ? null : () => setState(() => _chips = [..._chips]..remove(c)),
                    visualDensity: VisualDensity.compact,
                  ),
              ]),
            ),
          ),
        const Divider(height: 8),
        Expanded(child: _messages(cs)),
        if (_t.msgs.isNotEmpty && kb == 0) _quickRow(),
        _inputRow(cs),
      ]),
    );
  }

  IconData _chipIcon(String k) {
    switch (k) {
      case 'article':
        return Icons.menu_book_outlined;
      case 'case':
        return Icons.folder_copy_outlined;
      case 'quiz':
        return Icons.quiz_outlined;
      case 'calc':
        return Icons.calculate_outlined;
      default:
        return Icons.search;
    }
  }

  Widget _messages(ColorScheme cs) {
    if (_t.msgs.isEmpty && !_busy) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ask anything medical. Answers are teaching notes that suggest, not orders. I add articles from your own library under each answer.',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in quickActionsFor(_kind))
              ActionChip(
                key: ValueKey('quick_${a.id}'),
                avatar: const Icon(Icons.bolt, size: 16),
                label: m.Text(a.label),
                onPressed: () => _quick(a.id),
              ),
          ]),
        ]),
      );
    }
    return ListView.builder(
      controller: _sc,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: _t.msgs.length + (_busy ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _t.msgs.length) return _thinking(cs);
        final msg = _t.msgs[i];
        if (msg.role == 'user') return _userBubble(msg, cs);
        return _AssistantCard(
          key: ValueKey('a$i${msg.text.hashCode}'),
          msg: msg,
          question: _questionBefore(i),
          topic: _topic,
          links: _links[i],
          onNeedLinks: (doc) => _loadLinks(i, doc),
          onRetry: i == _t.msgs.length - 1 ? _retry : null,
          onFollow: i == _t.msgs.length - 1 && !_busy ? (q) => _send(q) : null,
        );
      },
    );
  }

  String _questionBefore(int i) {
    for (var j = i - 1; j >= 0; j--) {
      if (_t.msgs[j].role == 'user') return _t.msgs[j].text;
    }
    return '';
  }

  Future<void> _loadLinks(int i, AiDoc doc) async {
    if (_links.containsKey(i)) return;
    _links[i] = const [];
    final l = await AiChatRunner.libraryLinks(doc, _questionBefore(i));
    if (!mounted) return;
    setState(() => _links[i] = l);
  }

  Widget _thinking(ColorScheme cs) {
    final slow = _secs >= 25;
    final base = _secs < 6 ? tr('Contacting the AI...') : (_mode == 'web' || _mode == 'custom' ? tr('Searching and writing the answer...') : tr('Writing the answer...'));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(child: m.Text('$base  ${_secs}s', style: TextStyle(color: cs.onSurfaceVariant))),
          TextButton(onPressed: _cancel, child: Text('Cancel')),
        ]),
        if (slow)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _mode == 'web' || _mode == 'custom'
                  ? 'Taking longer than usual. Live web search is slow on a weak connection. You can cancel and try again without it.'
                  : 'Taking longer than usual. Check your connection, or cancel and try again.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
      ]),
    );
  }

  Widget _userBubble(AiChatMsg msg, ColorScheme cs) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          margin: const EdgeInsetsDirectional.only(start: 40, top: 6, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: SelectableText(msg.text, style: TextStyle(color: cs.onPrimaryContainer)),
        ),
      );

  Widget _quickRow() {
    final qs = quickActionsFor(_kind);
    if (qs.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          for (final a in qs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                label: m.Text(a.label),
                onPressed: _busy ? null : () => _quick(a.id),
              ),
            ),
        ],
      ),
    );
  }

  static const Map<String, String> _modeNames = {'web': 'Web', 'library': 'My library', 'model': 'Model', 'custom': 'Custom'};
  static const Map<String, String> _modeHelp = {
    'web': 'Accredited sites and the latest guidelines',
    'library': 'Only the articles you installed',
    'model': 'Model memory: may be outdated',
    'custom': 'Only your own list of sites',
  };
  static const Map<String, IconData> _modeIcon = {'web': Icons.public, 'library': Icons.local_library_outlined, 'model': Icons.psychology_alt_outlined, 'custom': Icons.tune};

  /// Source selector: one compact button (saves a row on small screens); the menu explains each source.
  Widget _modeButton(ColorScheme cs) {
    return PopupMenuButton<String>(
      key: const ValueKey('mode_btn'),
      tooltip: tr('Source'),
      enabled: !_busy,
      initialValue: _mode,
      onSelected: (v) => setState(() => _mode = v),
      itemBuilder: (_) => [
        for (final k in AiPrompts.modes)
          PopupMenuItem<String>(
            key: ValueKey('mode_$k'),
            value: k,
            child: Row(children: [
              Icon(_modeIcon[k], size: 20, color: _mode == k ? cs.primary : null),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_modeNames[k]!, style: TextStyle(fontWeight: _mode == k ? FontWeight.w800 : FontWeight.w600)),
                  Text(_modeHelp[k]!, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_modeIcon[_mode], size: 18, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(_modeNames[_mode]!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSecondaryContainer)),
          Icon(Icons.arrow_drop_down, size: 18, color: cs.onSecondaryContainer),
        ]),
      ),
    );
  }

  Widget _inputRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Padding(padding: const EdgeInsetsDirectional.only(end: 6, bottom: 2), child: _modeButton(cs)),
        Expanded(
          child: TextField(
            key: const ValueKey('chat_input'),
            controller: _in,
            focusNode: _focus,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (v) => _send(v),
            decoration: InputDecoration(
              hintText: tr('Ask a question...'),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filled(
          key: const ValueKey('chat_send'),
          tooltip: tr('Send'),
          onPressed: _busy ? null : () => _send(_in.text),
          icon: const Icon(Icons.send_rounded),
        ),
      ]),
    );
  }
}

/// The gradient of the floating button and the chat badge.
const LinearGradient kAiGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF7C4DFF), Color(0xFFE040FB), Color(0xFFFF8A65)],
);

// ================================================================ one answer

class _AssistantCard extends StatefulWidget {
  final AiChatMsg msg;
  final String question;
  final String topic;
  final List<LibHit>? links;
  final void Function(AiDoc doc) onNeedLinks;
  final VoidCallback? onRetry;
  final void Function(String)? onFollow;
  const _AssistantCard({super.key, required this.msg, required this.question, required this.topic, required this.links, required this.onNeedLinks, this.onRetry, this.onFollow});
  @override
  State<_AssistantCard> createState() => _AssistantCardState();
}

class _AssistantCardState extends State<_AssistantCard> {
  late final AiDoc _doc = widget.msg.failed || widget.msg.localOnly ? const AiDoc() : parseAiOutput(widget.msg.text);
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    if (!widget.msg.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_asked) {
          _asked = true;
          widget.onNeedLinks(_doc);
        }
      });
    }
  }

  AiChatMsg get _m => widget.msg;

  List<String> get _seenHosts => [for (final s in _m.sources) if (s.host.isNotEmpty) s.host];

  SourceCheck get _check => AiSources.verify(AiSources.citesOf(_doc), allow: AiSources.allowedFor(_m.mode == 'library' || _m.mode == 'model' ? 'web' : _m.mode), seenHosts: _seenHosts);

  String _title() {
    if (_doc.title.trim().isNotEmpty) return _doc.title.trim();
    if (widget.topic.isNotEmpty) return widget.topic;
    final q = widget.question.trim();
    return q.length > 50 ? q.substring(0, 50) : q;
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _doc.sections.isEmpty ? _m.text : aiDocToPlain(_doc)));
    snack(context, tr('Copied'));
  }

  Future<void> _saveNote() async {
    await AiChatRunner.saveAsNote(_title(), aiDocToMarkdown(_doc));
    if (mounted) snack(context, tr('Saved as a note'));
  }

  Future<void> _saveFile() async {
    final ok = await AiChatRunner.saveAsFile(_title(), aiDocToMarkdown(_doc));
    if (mounted) snack(context, ok ? tr('Saved in My files (Library)') : tr('Could not save the file'));
  }

  Future<bool> _confirm(String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Add')),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _cards() async {
    final n = AiStudyHooks.cardPairs(_doc, widget.topic).length;
    if (n == 0) {
      snack(context, tr('Nothing to make cards from.'));
      return;
    }
    if (!await _confirm(trp('Add up to {n} flashcards from this answer to your review deck?', {'n': n}))) return;
    final made = await AiStudyHooks.makeCards(_doc, source: widget.topic.isEmpty ? _title() : widget.topic);
    if (mounted) snack(context, trp('{n} flashcards added.', {'n': made}));
  }

  Future<void> _questions() async {
    final n = AiStudyHooks.questionMaps(_doc).length;
    if (n == 0) {
      snack(context, tr('No cited facts to make questions from. Ask with Web as the source to get cited answers.'));
      return;
    }
    if (!await _confirm(trp('Add up to {n} questions made from the cited facts to your AI question bank?', {'n': n}))) return;
    final made = await AiStudyHooks.makeQuestions(_doc);
    if (mounted) snack(context, trp('{n} questions added.', {'n': made}));
  }

  Future<void> _openCite(CheckedCite c) async {
    if (c.status == CiteStatus.notAllowed || c.status == CiteStatus.noLink) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Source not opened'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.status == CiteStatus.noLink ? 'This source has no usable https address.' : 'This address is not on your allowed list, so MedLog does not open it.'),
            if (c.cite.url.isNotEmpty) ...[const SizedBox(height: 8), SelectableText(c.cite.url, style: const TextStyle(fontSize: 12))],
          ]),
          actions: [
            if (c.cite.url.isNotEmpty) TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: c.cite.url)), child: Text('Copy address')),
            TextButton(onPressed: () => Navigator.pop(d), child: Text('Close')),
          ],
        ),
      );
      return;
    }
    final u = Uri.tryParse(c.cite.url);
    if (u == null) return;
    if (hostAllowed(u.host)) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BrowserScreen(title: c.cite.short, url: c.cite.url)));
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Open in your browser?'),
          content: Text(trp('{h} is on your allowed list but is not shown inside MedLog. Open it in your phone browser?', {'h': c.host})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Open')),
          ],
        ),
      );
      if (ok == true && mounted) await openUrl(context, c.cite.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    if (_m.failed) return _failed(cs);
    if (_m.localOnly) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [m.Text(_m.text), _libraryLinks(cs)])),
      );
    }
    final check = _check;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _banner(cs),
          if (AiPrefs.renderStyle == 'text' || _doc.sections.isEmpty)
            SelectableText(_doc.sections.isEmpty ? _m.text : aiDocToPlain(_doc))
          else
            AiDocView(doc: _doc, onCite: (c) {
              final k = check.of(c) ?? AiSources.verify([c], allow: AiSources.allowedFor(_m.mode == 'library' || _m.mode == 'model' ? 'web' : _m.mode), seenHosts: _seenHosts).items.first;
              _openCite(k);
            }),
          if (AiPrefs.showCitations) _sources(check, cs),
          _libraryLinks(cs),
          const SizedBox(height: 6),
          Wrap(spacing: 2, runSpacing: 0, children: [
            if (widget.onFollow != null) ...[
              _act(Icons.unfold_more, 'More detail', () => widget.onFollow!('Go deeper on your last answer: add the missing detail, causes, work-up, management steps, escalation points and pitfalls. Keep it organised under short headings.')),
              _act(Icons.unfold_less, 'Shorter', () => widget.onFollow!('Give a shorter version of your last answer: only the key decision points.')),
            ],
            _act(Icons.copy_rounded, 'Copy', _copy),
            _act(Icons.note_add_outlined, 'Save as note', _saveNote),
            _act(Icons.folder_open_outlined, 'Save as My file', _saveFile),
            _act(Icons.style_outlined, 'Make flashcards', _cards),
            _act(Icons.quiz_outlined, 'Make quiz questions', _questions),
          ]),
          m.Text(tr('AI suggestion: check before use. Not clinical advice.'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Widget _act(IconData i, String label, VoidCallback f) => TextButton.icon(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
        onPressed: f,
        icon: Icon(i, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );

  Widget _failed(ColorScheme cs) {
    return Card(
      color: cs.errorContainer.withAlpha(110),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(_m.offline ? Icons.wifi_off : Icons.error_outline, size: 18, color: cs.error),
            const SizedBox(width: 8),
            Expanded(child: m.Text(_m.error)),
          ]),
          if (_m.offline) ...[
            const SizedBox(height: 6),
            Text('Nothing was sent. Your library still works offline; these articles match your question:', style: TextStyle(color: cs.onSurfaceVariant)),
            _OfflineLinks(question: widget.question, open: _openArticle),
          ],
          if (widget.onRetry != null) Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(onPressed: widget.onRetry, icon: const Icon(Icons.refresh, size: 18), label: Text('Try again'))),
        ]),
      ),
    );
  }

  void _openArticle(LibHit h) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArticleScreen(packId: h.packId, index: h.index)));

  Widget _banner(ColorScheme cs) {
    final k = AiChatRunner.bannerFor(_m);
    if (k.isEmpty) return const SizedBox.shrink();
    final good = k == 'web';
    final text = {
      'web': trp('Searched the web ({n} sources)', {'n': _m.sources.length}),
      'library': tr('Answered from your library passages only.'),
      'model': tr('From model memory: may be outdated. Check the current guideline.'),
      'nosearch': tr('This provider has no live web search here. Answered from your library and the model: may be outdated.'),
      'searchquota': tr('The live search quota is used up. Answered from your library and the model: may be outdated.'),
      'searchfail': tr('Live search was refused for this key (not on its plan, or switched off by an admin). Answered from your library and the model: may be outdated.'),
      'searchoff': tr('Live search is switched off in the AI settings. Answered from your library and the model: may be outdated.'),
      'nosearch_used': tr('The model did not use web search for this answer, so it may be outdated. Check the current guideline.'),
    }[k]!;
    return Container(
      key: ValueKey('banner_$k'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: good ? cs.primaryContainer.withAlpha(150) : cs.tertiaryContainer.withAlpha(170), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(good ? Icons.public : Icons.info_outline, size: 16, color: good ? cs.onPrimaryContainer : cs.onTertiaryContainer),
        const SizedBox(width: 8),
        Expanded(child: m.Text(text, style: TextStyle(fontSize: 12, color: good ? cs.onPrimaryContainer : cs.onTertiaryContainer))),
      ]),
    );
  }

  Widget _sources(SourceCheck check, ColorScheme cs) {
    final chips = <Widget>[];
    for (final c in check.items) {
      final (icon, color, tip) = switch (c.status) {
        CiteStatus.verified => (Icons.verified_outlined, cs.primary, tr('Address on your allowed list')),
        CiteStatus.unconfirmed => (Icons.help_outline, cs.tertiary, tr('Allowed site, but the search did not return it: check the page')),
        CiteStatus.notAllowed => (Icons.block, cs.error, tr('Not on your allowed list: not opened')),
        CiteStatus.noLink => (Icons.link_off, cs.outline, tr('No usable address')),
      };
      chips.add(ActionChip(
        key: ValueKey('cite_${c.status.name}'),
        visualDensity: VisualDensity.compact,
        avatar: Icon(icon, size: 16, color: color),
        label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: m.Text(c.cite.short, overflow: TextOverflow.ellipsis)),
        tooltip: tip,
        onPressed: () => _openCite(c),
      ));
    }
    // searched sites the model did not cite (Gemini returns domains only)
    final allow = AiSources.allowedFor(_m.mode == 'library' || _m.mode == 'model' ? 'web' : _m.mode);
    final shown = {for (final c in check.items) c.host};
    final extra = <String>{};
    for (final s in _m.sources) {
      final h = s.host;
      if (h.isNotEmpty && !shown.contains(h) && extra.add(h)) {
        final ok = AiSources.hostMatches(h, allow);
        chips.add(Chip(
          key: ValueKey(ok ? 'seen_ok' : 'seen_bad'),
          visualDensity: VisualDensity.compact,
          avatar: Icon(ok ? Icons.travel_explore : Icons.block, size: 16, color: ok ? cs.primary : cs.error),
          label: m.Text(h, overflow: TextOverflow.ellipsis),
        ));
      }
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sources', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 0, children: chips),
        if (check.notAllowed > 0 || check.unconfirmed > 0 || check.noLink > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Marked sources could not be verified against your allowed sites: check them before relying on them.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
      ]),
    );
  }

  Widget _libraryLinks(ColorScheme cs) {
    final l = widget.links;
    if (l == null || l.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('From your library', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 0, children: [
          for (final h in l)
            ActionChip(
              key: ValueKey('lib_${h.packId}_${h.index}'),
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.menu_book_outlined, size: 16),
              label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: m.Text(stripSource(h.title), overflow: TextOverflow.ellipsis)),
              onPressed: () => _openArticle(h),
            ),
        ]),
      ]),
    );
  }
}

class _OfflineLinks extends StatefulWidget {
  final String question;
  final void Function(LibHit) open;
  const _OfflineLinks({required this.question, required this.open});
  @override
  State<_OfflineLinks> createState() => _OfflineLinksState();
}

class _OfflineLinksState extends State<_OfflineLinks> {
  List<LibHit> _l = const [];
  @override
  void initState() {
    super.initState();
    AiChatRunner.libraryLinks(const AiDoc(), widget.question).then((v) {
      if (mounted) setState(() => _l = v);
    });
  }

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, children: [
        for (final h in _l) ActionChip(visualDensity: VisualDensity.compact, label: m.Text(stripSource(h.title)), onPressed: () => widget.open(h)),
      ]);
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet();
  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  @override
  Widget build(BuildContext context) {
    final l = AiChats.all();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(alignment: AlignmentDirectional.centerStart, child: Text('Earlier chats', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          ),
          if (l.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('No earlier chats yet.')),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final t in l)
                ListTile(
                  title: m.Text(t.title.isEmpty ? '-' : t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: m.Text(prettyDate(t.date.length >= 10 ? t.date.substring(0, 10) : t.date)),
                  onTap: () => Navigator.pop(context, t.id),
                  trailing: IconButton(
                    tooltip: tr('Delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await AiChats.delete(t.id);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
