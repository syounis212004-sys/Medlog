import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:flutter/services.dart';

import 'ai/ai_api.dart';
import 'ai/ai_prefs.dart';
import 'ai/ai_widgets.dart' show showAiCaseConsent;
import 'data.dart';
import 'i18n.dart';
import 'ref_data.dart';
import 'screens_ai_quality.dart';
import 'screens_ai_quiz.dart' show AiQuizScreen;
import 'settings_widgets.dart';
import 'widgets.dart';

/// Settings > AI assistant (stand-alone route kept for existing links). The same sections live inside
/// "Library & AI settings" (see [AiSettingsBody]); everything is stored on this phone only (keys in the Android Keystore).
class AiSettingsScreen extends StatelessWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AI assistant')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: const [AiSettingsBody(standalone: true)],
      ),
    );
  }
}

const Map<String, List<String>> _kGroupInfo = {
  'ask': ['Ask my references', 'Answers questions using the library you installed.'],
  'explain': ['Explain / translate', 'Explains or translates a passage in simple words.'],
  'quiz': ['Question bank', 'Drafts practice questions from a topic.'],
  'case': ['Case assistant', 'Suggests ideas for a case from a de-identified summary.'],
  'reports': ['Reports & summaries', 'Drafts summaries of your own logbook.'],
  'help': ['App help', 'Answers "how do I do this in MedLog".'],
};

/// Screens where the floating Ask-AI button can be switched on or off: [id, label].
const List<List<String>> kAiScreens = [
  ['home', 'Home'],
  ['library', 'Library'],
  ['article', 'Articles'],
  ['search', 'Search'],
  ['quiz', 'Quizzes'],
  ['case', 'Cases'],
  ['calc', 'Calculators'],
  ['portfolio', 'Portfolio'],
];

/// The three AI folds (assistant + connection, answers, privacy). Used by [AiSettingsScreen] and by LibrarySettingsScreen.
class AiSettingsBody extends StatefulWidget {
  final bool standalone;

  /// Changes when a suggestion asks to open a section: folds are rebuilt and read their saved state.
  final int foldGen;
  const AiSettingsBody({super.key, this.standalone = false, this.foldGen = 0});

  @override
  State<AiSettingsBody> createState() => _AiSettingsBodyState();
}

class _AiSettingsBodyState extends State<AiSettingsBody> {
  final TextEditingController _key = TextEditingController();
  final TextEditingController _base = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _region = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String _msg = '';
  bool _msgOk = false;

  @override
  void initState() {
    super.initState();
    AiStore.changes.addListener(_r);
    store.addListener(_r);
    AiStore.ensureLoaded().then((_) {
      if (!mounted) return;
      _base.text = AiStore.openaiBase;
      _model.text = AiStore.modelOf(AiStore.provider);
      setState(() {});
    });
    _base.text = AiStore.openaiBase;
    _model.text = AiStore.modelOf(AiStore.provider);
    _region.text = AiPrefs.region;
    if (Ai.enabled) Ai.isOnline();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AiStore.changes.removeListener(_r);
    store.removeListener(_r);
    _key.dispose();
    _base.dispose();
    _model.dispose();
    _region.dispose();
    super.dispose();
  }

  AiProviderId get _p => AiStore.provider;

  Future<void> _setProvider(AiProviderId p) async {
    AiStore.provider = p;
    _key.clear();
    _msg = '';
    _model.text = AiStore.modelOf(p);
    await AiStore.save();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _key.text = d!.text!.trim());
  }

  Future<void> _saveBase() async {
    if (_p != AiProviderId.openai) return;
    AiStore.openaiBase = _base.text.trim().isEmpty ? AiProviders.openaiDefaultBase : _base.text.trim();
    await AiStore.save();
  }

  Future<void> _saveKey() async {
    await _saveBase();
    final k = _key.text.trim();
    if (k.isEmpty) {
      setState(() {
        _msg = tr('Paste a key first.');
        _msgOk = false;
      });
      return;
    }
    await AiStore.setKey(_p, k);
    _key.clear();
    setState(() {
      _msg = tr('Key saved on this phone.');
      _msgOk = true;
    });
  }

  Future<void> _test() async {
    await _saveBase();
    final typed = _key.text.trim();
    final key = typed.isNotEmpty ? typed : AiStore.keyOf(_p);
    if (key.isEmpty) {
      setState(() {
        _msg = tr('Paste a key first.');
        _msgOk = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    final r = await Ai.testKey(_p, key, _model.text.trim(), openaiBase: AiStore.openaiBase)
        .timeout(const Duration(seconds: 45), onTimeout: () => AiResult(error: tr('The AI took too long to answer. Check your connection, then try again.'), timedOut: true));
    if (!mounted) return;
    if (r.ok) {
      if (typed.isNotEmpty) {
        await AiStore.setKey(_p, typed);
        _key.clear();
      }
      if (AiStore.modelOf(_p).isEmpty && r.text.isNotEmpty) {
        AiStore.models[_p.name] = r.text;
        _model.text = r.text;
        await AiStore.save();
      }
    }
    setState(() {
      _busy = false;
      _msgOk = r.ok;
      _msg = r.ok
          ? tr('It works. Model in use: {m}').replaceAll('{m}', r.text)
          : r.offline
              ? tr('No internet right now. The app works fully without it; try again when you are online.')
              : (r.error ?? tr('The AI request failed.'));
    });
  }

  Future<void> _diag() async {
    await _saveBase();
    final typed = _key.text.trim();
    final key = typed.isNotEmpty ? typed : AiStore.keyOf(_p);
    setState(() {
      _busy = true;
      _msg = '';
    });
    final steps = await Ai.diagnose(_p, key, _model.text.trim(), openaiBase: AiStore.openaiBase);
    if (!mounted) return;
    setState(() => _busy = false);
    final report = StringBuffer('MedLog AI diagnostics\nprovider: ${_p.name}\nmodel: ${_model.text.trim()}\n');
    for (final st in steps) {
      report.writeln('${st.ok ? 'OK ' : 'FAIL'} ${st.name}: ${st.ms} ms, ${st.detail}');
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Connection check'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            for (final st in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(st.ok ? Icons.check_circle : Icons.error, size: 20, color: st.ok ? Colors.green : Theme.of(c).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: m.Text('${st.name}\n${st.ms} ms  ${st.detail}', style: const TextStyle(fontSize: 13))),
                ]),
              ),
            if (key.isEmpty) Text('Paste a key to check it too.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: report.toString())), child: Text('Copy report')),
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Close')),
        ],
      ),
    );
  }

  Future<void> _pickModel() async {
    await _saveBase();
    final key = _key.text.trim().isNotEmpty ? _key.text.trim() : AiStore.keyOf(_p);
    if (key.isEmpty) {
      setState(() {
        _msg = tr('Paste a key first.');
        _msgOk = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _msg = '';
    });
    final r = await Ai.fetchModels(_p, key, openaiBase: AiStore.openaiBase);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.error != null || r.models.isEmpty) {
      setState(() {
        _msgOk = false;
        _msg = r.error ?? tr('No models found.');
      });
      return;
    }
    final auto = AiProviders.pickDefault(_p, r.models);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (ctx, sc) => ListView(controller: sc, children: [
            ListTile(title: Text('Choose a model', style: const TextStyle(fontWeight: FontWeight.w700))),
            ListTile(
              leading: const Icon(Icons.bolt),
              title: Text('Cheap and fast (automatic)'),
              subtitle: m.Text(auto),
              onTap: () => Navigator.pop(ctx, auto),
            ),
            for (final mo in r.models)
              ListTile(
                dense: true,
                title: m.Text(mo.id),
                subtitle: mo.label != mo.id ? m.Text(mo.label) : null,
                trailing: mo.id == AiStore.modelOf(_p) ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, mo.id),
              ),
          ]),
        ),
      ),
    );
    if (chosen != null) {
      AiStore.models[_p.name] = chosen;
      _model.text = chosen;
      await AiStore.save();
    }
  }

  Future<void> _toggleCase(bool v) async {
    if (!v) {
      AiStore.allowCase = false;
      await AiStore.save();
      return;
    }
    if (!AiStore.caseConsented) {
      await showAiCaseConsent(context);
    } else {
      AiStore.allowCase = true;
      await AiStore.save();
    }
  }

  Key _fk(String id) => ValueKey('${id}_${widget.foldGen}');

  @override
  Widget build(BuildContext context) {
    final open = widget.standalone;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Fold(key: _fk('ls_ai'), id: 'ls_ai', title: tr('AI assistant'), subtitle: _aiSubtitle(), icon: Icons.auto_awesome_outlined, initiallyOpen: open, children: _assistant(context)),
      Fold(key: _fk('ls_ai_answers'), id: 'ls_ai_answers', title: tr('AI answers'), icon: Icons.question_answer_outlined, initiallyOpen: open, children: _answers(context)),
      Fold(key: _fk('ls_privacy'), id: 'ls_privacy', title: tr('Privacy'), icon: Icons.shield_outlined, initiallyOpen: open, children: _privacy(context)),
    ]);
  }

  String _aiSubtitle() => AiStore.master ? (AiStore.hasKey() ? tr('On') : tr('On, but no key yet')) : tr('Off');

  // ------------------------------------------------------------------ AI assistant

  List<Widget> _assistant(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasKey = AiStore.hasKey();
    return [
      OptSwitch(
        title: 'Use the AI assistant',
        help: AiStore.master ? (hasKey ? 'On' : 'On, but no key yet') : 'Off',
        info: 'The master switch. When it is off, no AI button appears anywhere and nothing is ever sent. The app works fully without AI and without internet.',
        value: AiStore.master,
        onChanged: (v) async {
          AiStore.master = v;
          await AiStore.save();
        },
      ),
      OptLink(
        icon: Icons.quiz_outlined,
        title: 'AI question bank',
        help: 'Practice questions drafted from your library topics.',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiQuizScreen())),
      ),
      OptHead(
        title: 'Provider',
        help: 'Who answers your questions. You use your own key.',
        info: 'Choose the company whose AI answers. You create a key on their website and paste it here. The key stays on this phone and is sent only to that company. Gemini has a free tier, which is a good place to start.',
      ),
      for (final p in AiProviderId.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          onTap: () => _setProvider(p),
          leading: Icon(_p == p ? Icons.radio_button_checked : Icons.radio_button_off, color: _p == p ? cs.primary : null),
          title: m.Text(AiProviders.label(p)),
          subtitle: p == AiProviderId.gemini ? Text('Free tier available: good to start with') : null,
          trailing: AiStore.hasKey(p) ? const Icon(Icons.key, size: 18) : null,
        ),
      const SizedBox(height: 8),
      if (_p == AiProviderId.openai) ...[
        TextField(
          controller: _base,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: tr('Server address'), hintText: 'https://api.openai.com/v1', border: const OutlineInputBorder()),
          onSubmitted: (_) => _saveBase(),
        ),
        const SizedBox(height: 4),
        Text('Works with OpenAI, OpenRouter, Groq or a local server (http only on your own network).', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
      ],
      TextField(
        controller: _key,
        obscureText: !_show,
        enableSuggestions: false,
        autocorrect: false,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: tr('API key'),
          helperText: hasKey ? tr('A key is stored on this phone. Paste a new one to replace it.') : null,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          suffixIcon: Wrap(children: [
            IconButton(tooltip: tr('Show / hide'), icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)),
            IconButton(tooltip: tr('Paste'), icon: const Icon(Icons.content_paste), onPressed: _paste),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      m.Text(tr('{k}: get a key. Free keys have daily limits.').replaceAll('{k}', AiProviders.keyHelp(_p)), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(onPressed: _busy ? null : _saveKey, child: Text('Save key')),
        OutlinedButton.icon(
          onPressed: _busy ? null : _test,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check),
          label: Text('Test connection'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _diag,
          icon: const Icon(Icons.troubleshoot),
          label: Text('Connection check'),
        ),
        if (hasKey)
          OutlinedButton.icon(
            key: const ValueKey('ai_quality_btn'),
            onPressed: _busy ? null : () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AiQualityScreen())),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text('AI quality check'),
          ),
        if (hasKey)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    if (await confirmDialog(context, tr('Remove the key from this phone?'), action: 'Remove')) {
                      await AiStore.setKey(_p, '');
                      setState(() => _msg = '');
                    }
                  },
            child: Text('Remove key'),
          ),
      ]),
      if (_msg.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(_msgOk ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: _msgOk ? Colors.green : cs.error),
            const SizedBox(width: 6),
            Expanded(child: m.Text(_msg, style: TextStyle(color: _msgOk ? null : cs.error))),
          ]),
        ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Model'),
            subtitle: m.Text(AiStore.modelOf(_p).isEmpty ? tr('Automatic (cheap and fast)') : AiStore.modelOf(_p)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _pickModel,
          ),
        ),
        const OptInfoButton(title: 'Model', info: 'The exact AI model used. Automatic picks a cheap and fast one that is good enough for study questions. Pick another from the list if your key gives access to a stronger model.'),
      ]),
      TextField(
        controller: _model,
        textDirection: TextDirection.ltr,
        autocorrect: false,
        decoration: InputDecoration(labelText: tr('Model name (advanced)'), isDense: true, border: const OutlineInputBorder()),
        onSubmitted: (v) async {
          AiStore.models[_p.name] = v.trim();
          await AiStore.save();
        },
      ),
      OptGroupTitle(tr('What AI may be used for')),
      for (final g in kAiGroups)
        OptSwitch(
          title: _kGroupInfo[g]![0],
          help: _kGroupInfo[g]![1],
          info: 'Switch this on to let the app use AI for this purpose. When it is off, the matching AI button is hidden and nothing is sent for it.',
          value: AiStore.features[g] != false,
          onChanged: (v) async {
            AiStore.features[g] = v;
            await AiStore.save();
          },
        ),
      OptGroupTitle(tr('Usage')),
      Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: m.Text(tr('Requests today: {n}').replaceAll('{n}', '${AiStore.requestsToday}'))),
      if (AiStore.quotaHitToday)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('The free quota was reached today. It usually resets the next day, or use another key.', style: TextStyle(color: cs.error, fontSize: 13)),
        ),
      OptLink(
        icon: Icons.history,
        title: 'Activity log',
        help: 'What was sent, when and to whom',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiActivityLogScreen())),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.delete_sweep_outlined),
        title: Text('Clear AI cache'),
        subtitle: m.Text(tr('{n} saved answers').replaceAll('{n}', '${AiCache.count}')),
        onTap: () async {
          await AiCache.clear();
          if (mounted) {
            setState(() {});
            snack(context, tr('AI cache cleared.'));
          }
        },
      ),
    ];
  }

  // ------------------------------------------------------------------ AI answers

  List<Widget> _answers(BuildContext context) {
    final mode = AiPrefs.sourceMode;
    return [
      OptChoice<String>(
        title: 'Answer language',
        help: 'English is the default.',
        info: 'English: answers in English. Mixed: the explanation is in Arabic and medical terms, drug names and doses stay in English. Arabic: answers in Arabic. Medical terms are always safer to keep in English.',
        value: AiPrefs.answerLang,
        items: const [
          OptItem('en', 'English'),
          OptItem('mixed', 'Mixed', 'Arabic explanation, English medical terms'),
          OptItem('ar', 'Arabic'),
        ],
        onChanged: (v) => AiPrefs.answerLang = v,
      ),
      OptChoice<String>(
        title: 'Answer length',
        help: 'How much detail you get.',
        info: 'Brief: a few lines, for a quick check. Standard: the key points in a structured answer. Comprehensive: a full overview with differentials, management and references. Longer answers use more of your daily quota.',
        segmented: true,
        value: AiPrefs.answerLength,
        items: const [OptItem('brief', 'Brief'), OptItem('standard', 'Standard'), OptItem('full', 'Comprehensive')],
        onChanged: (v) => AiPrefs.answerLength = v,
      ),
      OptChoice<String>(
        title: 'Where answers come from',
        help: 'The kind of source the AI should rely on.',
        info: 'Trusted web: the AI is told to use the websites in the list below (guideline bodies, journals). My library: only the courses installed on this phone. Model knowledge: the AI answers from memory, with no sources. Custom: only the sites you add yourself.',
        value: mode,
        items: const [
          OptItem('web', 'Trusted web', 'Guideline and journal sites from the list below'),
          OptItem('library', 'My library', 'Only the courses installed on this phone'),
          OptItem('model', 'Model knowledge', 'No web, no sources'),
          OptItem('custom', 'Custom', 'Only the sites you add'),
        ],
        onChanged: (v) => AiPrefs.sourceMode = v,
      ),
      if (mode == 'web' || mode == 'custom') _DomainEditor(custom: mode == 'custom'),
      Fold(key: _fk('ls_ai_adv'), id: 'ls_ai_adv', title: tr('Advanced'), subtitle: tr('Web search, region, citations, limits, floating button'), icon: Icons.tune, initiallyOpen: widget.standalone, children: [
      OptSwitch(
        title: "Use the provider's live web search when available",
        help: 'Gemini, Claude and OpenAI can look things up online.',
        info: "When the provider has its own web-search tool, the AI can read current pages instead of relying on memory. The app still checks that every cited link belongs to your allowed list and hides the ones that do not. It needs internet and may use more of your quota.",
        value: AiPrefs.providerSearch,
        onChanged: (v) => AiPrefs.providerSearch = v,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OptHead(
            title: 'Region for guidelines',
            help: 'For example: Jordan, Middle East, UK.',
            info: 'Guidelines differ between countries (drug names, doses, local protocols). A region hint lets the AI choose the guidelines that fit where you work. Leave it empty for international guidelines. Only this short text is sent, never your location.',
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('ai_region'),
            controller: _region,
            decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: tr('Region (optional)')),
            onChanged: (v) => AiPrefs.region = v.trim(),
          ),
        ]),
      ),
      OptSwitch(
        title: 'Show citations',
        help: 'List the sources under each answer.',
        info: 'Shows the references the AI used under every answer, as links you can open. Links that are not on your allowed list are marked as unverified. Turn it off for a cleaner screen.',
        value: AiPrefs.showCitations,
        onChanged: (v) => AiPrefs.showCitations = v,
      ),
      OptChoice<String>(
        title: 'How answers look',
        help: 'Cards or plain text.',
        info: 'Cards: the answer is split into labelled sections (overview, management, red flags, references) that are easy to scan. Plain text: one continuous text, closer to a chat.',
        segmented: true,
        value: AiPrefs.renderStyle,
        items: const [OptItem('cards', 'Cards'), OptItem('text', 'Plain text')],
        onChanged: (v) => AiPrefs.renderStyle = v,
      ),
      OptSlider(
        title: 'Daily request limit',
        help: 'A guard on top of your provider quota.',
        info: 'The most AI requests the app will send in one day. It protects a free key from running out and avoids surprise costs on a paid key. Answers already saved on the phone do not count.',
        value: AiPrefs.dailyCap.toDouble(),
        min: 10,
        max: 200,
        divisions: 19,
        format: (v) => '${v.round()}',
        onChanged: (v) => AiPrefs.dailyCap = v.round(),
      ),
      OptGroupTitle(tr('Floating button')),
      OptSwitch(
        title: 'Floating Ask AI button',
        help: 'A small draggable button on the main screens.',
        info: 'A small button you can drag. It offers quick AI actions that fit the screen you are on. It only appears when the AI assistant is on and has a key.',
        value: AiPrefs.fabEnabled,
        onChanged: (v) => AiPrefs.fabEnabled = v,
      ),
      OptChoice<String>(
        title: 'Button side',
        help: 'Where the button rests.',
        info: 'Start is the left edge in English and the right edge in Arabic. End is the opposite side. You can still drag the button anywhere and it remembers its height.',
        segmented: true,
        value: AiPrefs.fabSide,
        items: const [OptItem('start', 'Start'), OptItem('end', 'End')],
        onChanged: (v) => AiPrefs.fabSide = v,
      ),
      OptHead(
        title: 'Show the button on',
        help: 'Choose the screens.',
        info: 'Switch off the screens where the floating button gets in the way. It stays available on the others.',
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          for (final s in kAiScreens)
            FilterChip(
              key: Key('ai_scr_${s[0]}'),
              label: Text(s[1]),
              selected: AiPrefs.screenOn(s[0]),
              onSelected: AiPrefs.fabEnabled ? (v) => AiPrefs.setScreenOn(s[0], v) : null,
            ),
        ]),
      ),
      ]),
    ];
  }

  // ------------------------------------------------------------------ privacy

  List<Widget> _privacy(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How your data is handled', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('The app works fully without AI and without internet. AI is optional and only makes suggestions: nothing is saved without your confirmation.'),
          const SizedBox(height: 6),
          Text('You use your own key. It is stored only on this phone (Android Keystore) and is never part of backups or exports. It is sent only to the provider you choose.'),
          const SizedBox(height: 6),
          Text('Never sent: names, ids, phone numbers, addresses, hospital or doctor names, images, exact dates or whole notes. Case summaries are shown to you first.'),
          const SizedBox(height: 6),
          Text('AI answers can be wrong. Always check them against a reliable source.'),
        ]),
      ),
      OptGroupTitle(tr('What may leave this phone')),
      Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('Always: your question text (with identifiers removed).', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
      OptSwitch(
        title: 'Passages of my installed library',
        help: 'Public licensed text that helps the answer.',
        info: 'Lets the app add short passages from the courses installed on this phone to your question, so the answer is based on them. These are public, licensed texts, not your own notes.',
        value: AiStore.allowLibrary,
        onChanged: (v) async {
          AiStore.allowLibrary = v;
          await AiStore.save();
        },
      ),
      OptSwitch(
        title: 'De-identified case summaries',
        help: 'Shown to you and approved before sending. Cases marked "never send" are excluded.',
        info: 'Lets the case assistant send a short summary of a case (age band, sex, findings, labs in words). Names, ids, phones, addresses, hospital or doctor names, images and exact dates are removed first. You see and approve every summary before it leaves the phone.',
        value: AiStore.allowCase,
        onChanged: _toggleCase,
      ),
      OptChoice<String>(
        title: 'Preview before sending',
        help: 'See exactly what leaves the phone.',
        info: 'Before every send: you review the text each time. Once per session: you review the first request after opening the app, then the next ones in the same session go straight through.',
        value: AiStore.previewMode,
        items: const [OptItem('always', 'Before every send'), OptItem('session', 'Once per session')],
        onChanged: (v) async {
          AiStore.previewMode = v;
          await AiStore.save();
        },
      ),
      OptHead(
        title: 'What is never sent',
        help: 'Names, ids, images, exact dates, whole notes.',
        info: 'These are removed or never included, whatever you choose: patient names and ids, phone numbers, emails, addresses, hospital and doctor names, images, exact dates and whole free-text notes. A case marked "never send to AI" is blocked completely. The cleaning is automatic and careful, but not perfect, so read the preview.',
      ),
    ];
  }
}

/// Add / remove / reset the websites the AI may cite. The app checks every cited link against this list.
class _DomainEditor extends StatefulWidget {
  final bool custom;
  const _DomainEditor({required this.custom});
  @override
  State<_DomainEditor> createState() => _DomainEditorState();
}

class _DomainEditorState extends State<_DomainEditor> {
  final TextEditingController _c = TextEditingController();
  String _err = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Adds the reviewed list of free guideline and public-health sites (assets/data/sources.json) to the allowed websites.
  Future<void> _addMap() async {
    final src = await RefData.sources();
    var n = 0;
    for (final d in (src['domains'] as List? ?? const [])) {
      if (d is Map && d['free'] == true && AiPrefs.addDomain(d['domain'].toString(), custom: widget.custom)) n++;
    }
    if (!mounted) return;
    setState(() => _err = '');
    snack(context, n == 0 ? tr('The map is already in your list.') : trp('{n} sites added.', {'n': n}));
  }

  void _add() {
    final raw = _c.text;
    if (raw.trim().isEmpty) return;
    final ok = AiPrefs.addDomain(raw, custom: widget.custom);
    setState(() {
      _err = ok ? '' : tr('Enter a website such as nice.org.uk (not already in the list).');
      if (ok) _c.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = widget.custom ? AiPrefs.customDomains : AiPrefs.domains;
    final canReset = widget.custom ? list.isNotEmpty : !AiPrefs.domainsAreDefault;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OptHead(
          title: widget.custom ? 'My own sites' : 'Allowed websites',
          help: 'The app verifies cited links against this list and hides the others.',
          info: widget.custom
              ? 'Only the sites you add here are used in Custom mode. The app checks every link the AI cites against this list and marks links from other sites as unverified. If the list is empty, the default trusted list is used.'
              : 'Websites the AI may rely on and cite: guideline bodies, health agencies and journals. The app checks every link the AI cites against this list and marks links from other sites as unverified. Add or remove sites, or restore the default list.',
        ),
        const SizedBox(height: 6),
        if (list.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('No sites yet: the default trusted list is used.', style: theme.textTheme.bodySmall)),
        Wrap(spacing: 6, runSpacing: 0, children: [
          for (final d in list)
            Directionality(
              textDirection: TextDirection.ltr,
              child: InputChip(
                key: Key('dom_$d'),
                label: m.Text(d, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onDeleted: (!widget.custom && list.length <= 1) ? null : () => setState(() => AiPrefs.removeDomain(d, custom: widget.custom)),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('dom_input'),
              controller: _c,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: 'example.org', errorText: _err.isEmpty ? null : _err, errorMaxLines: 2),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(key: const Key('dom_add'), tooltip: tr('Add'), onPressed: _add, icon: const Icon(Icons.add)),
        ]),
        if (!widget.custom)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('dom_map'),
              onPressed: _addMap,
              icon: const Icon(Icons.library_add_outlined, size: 18),
              label: Text('Add the trusted-source map'),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('dom_reset'),
            onPressed: canReset
                ? () => setState(() {
                      AiPrefs.resetDomains();
                      _err = '';
                    })
                : null,
            icon: const Icon(Icons.restore, size: 18),
            label: Text('Reset to the default list'),
          ),
        ),
      ]),
    );
  }
}

/// What was sent (never the text itself): feature, time, provider, size.
class AiActivityLogScreen extends StatefulWidget {
  const AiActivityLogScreen({super.key});

  @override
  State<AiActivityLogScreen> createState() => _AiActivityLogScreenState();
}

class _AiActivityLogScreenState extends State<AiActivityLogScreen> {
  @override
  void initState() {
    super.initState();
    AiStore.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AiAudit.entries.reversed.toList();
    const lv = ['Question only', 'Question + library text', 'De-identified case summary'];
    return Scaffold(
      appBar: AppBar(
        title: Text('Activity log'),
        actions: [
          IconButton(
            tooltip: tr('Clear'),
            icon: const Icon(Icons.delete_outline),
            onPressed: l.isEmpty
                ? null
                : () async {
                    if (await confirmDialog(context, tr('Clear the AI activity log?'), action: 'Clear')) {
                      await AiAudit.clear();
                      if (mounted) setState(() {});
                    }
                  },
          ),
        ],
      ),
      body: l.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Nothing has been sent yet.')))
          : ListView.separated(
              itemCount: l.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = l[i];
                final flag = e['k'] == 'flag';
                final ok = e['ok'] == true;
                final t = (e['t'] ?? '').toString().replaceFirst('T', ' ');
                final when = t.length >= 16 ? t.substring(0, 16) : t;
                final lvl = (e['lv'] is int && e['lv'] >= 0 && e['lv'] < 3) ? lv[e['lv'] as int] : lv[0];
                return ListTile(
                  dense: true,
                  leading: Icon(flag ? Icons.flag_outlined : (ok ? Icons.north_east : Icons.error_outline), color: ok || flag ? null : Theme.of(context).colorScheme.error),
                  title: m.Text(flag ? '${tr('Problem reported')}: ${e['f']}' : '${e['f']}'),
                  subtitle: m.Text(flag ? when : '$when • ${e['p'] ?? ''} ${e['m'] ?? ''}\n${tr(lvl)} • ${e['b'] ?? 0} ${tr('bytes')}${ok ? '' : ' • ${tr('failed')}'}'),
                  isThreeLine: !flag,
                );
              },
            ),
    );
  }
}
