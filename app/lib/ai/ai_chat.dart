import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show BuildContext;

import '../data.dart';
import '../i18n.dart';
import '../lib_user.dart' show saveNote;
import '../library.dart';
import 'ai_api.dart';
import 'ai_context.dart';
import 'ai_case_payload.dart';
import 'ai_doc_api.dart';
import 'ai_engine.dart';
import 'ai_library.dart';
import 'ai_prompts.dart';

/// Logic of the Ask-AI chat: persistence, context chips, quick actions, building the request for a source mode,
/// and the local "from your library" links. The screen is in screens_ai_chat.dart.

// ================================================================ messages and threads

class AiChatMsg {
  final String role; // 'user' | 'assistant'
  final String text; // assistant: the raw model text (parsed again when shown)
  final String mode; // source mode asked: web | library | model | custom
  final bool searched; // the provider's live search ran
  final String note; // searchNote of the result
  final List<AiSource> sources;
  final List<String> queries;
  final List<String> chips; // context labels used for this question
  final bool failed; // error / offline message (not sent back as history)
  final String error;
  final bool offline;
  final bool localOnly; // answered from library passages without a model call
  final bool timedOut; // the request hit the time cap (not stored)
  const AiChatMsg(
    this.role,
    this.text, {
    this.mode = '',
    this.searched = false,
    this.note = '',
    this.sources = const [],
    this.queries = const [],
    this.chips = const [],
    this.failed = false,
    this.error = '',
    this.offline = false,
    this.localOnly = false,
    this.timedOut = false,
  });

  Map<String, dynamic> toJson() => {
        'r': role,
        't': text,
        if (mode.isNotEmpty) 'm': mode,
        if (searched) 's': true,
        if (note.isNotEmpty) 'n': note,
        if (sources.isNotEmpty) 'src': [for (final s in sources) s.toJson()],
        if (queries.isNotEmpty) 'q': queries,
        if (chips.isNotEmpty) 'c': chips,
        if (failed) 'f': true,
        if (error.isNotEmpty) 'e': error,
        if (offline) 'o': true,
        if (localOnly) 'l': true,
      };

  factory AiChatMsg.fromJson(Map j) => AiChatMsg(
        '${j['r'] ?? 'user'}',
        '${j['t'] ?? ''}',
        mode: '${j['m'] ?? ''}',
        searched: j['s'] == true,
        note: '${j['n'] ?? ''}',
        sources: [for (final e in (j['src'] is List ? j['src'] as List : const [])) if (e is Map) AiSource.fromJson(e)],
        queries: [for (final e in (j['q'] is List ? j['q'] as List : const [])) '$e'],
        chips: [for (final e in (j['c'] is List ? j['c'] as List : const [])) '$e'],
        failed: j['f'] == true,
        error: '${j['e'] ?? ''}',
        offline: j['o'] == true,
        localOnly: j['l'] == true,
      );
}

class AiChatThread {
  String id;
  String title;
  String date;
  final List<AiChatMsg> msgs;
  AiChatThread(this.id, this.title, this.date, this.msgs);

  factory AiChatThread.create() => AiChatThread(newId('ch'), '', nowIso(), []);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'date': date, 'msgs': [for (final m in msgs) m.toJson()]};

  factory AiChatThread.fromJson(Map j) => AiChatThread('${j['id']}', '${j['title'] ?? ''}', '${j['date'] ?? ''}',
      [for (final e in (j['msgs'] is List ? j['msgs'] as List : const [])) if (e is Map) AiChatMsg.fromJson(e)]);
}

/// Chats kept on this phone (store list 'aichats', the newest 50).
class AiChats {
  static const int keep = 50;
  static const String list = 'aichats';

  static List<AiChatThread> all() {
    final out = <AiChatThread>[];
    for (final e in store.listOf(list)) {
      try {
        out.add(AiChatThread.fromJson(e));
      } catch (_) {}
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  static AiChatThread? byId(String id) {
    for (final e in store.listOf(list)) {
      if (e['id'] == id) return AiChatThread.fromJson(e);
    }
    return null;
  }

  static Future<void> save(AiChatThread t) async {
    if (t.msgs.isEmpty) return;
    t.date = nowIso();
    if (t.title.isEmpty) {
      final first = t.msgs.firstWhere((m) => m.role == 'user', orElse: () => t.msgs.first).text.trim();
      t.title = first.length > 60 ? '${first.substring(0, 57)}...' : first;
    }
    await store.upsertExtra(list, Map<String, dynamic>.from(jsonDecode(jsonEncode(t.toJson())) as Map));
    final l = store.listOf(list);
    if (l.length > keep) {
      l.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
      while (l.length > keep) {
        l.removeAt(0);
      }
      await store.saveExtra(list);
    }
  }

  static Future<void> delete(String id) => store.removeExtra(list, id);
}

// ================================================================ context chips and quick actions

class AiChip {
  final String kind; // article | case | quiz | calc | search
  final String label;
  final String title;
  final Map<String, String> data;
  const AiChip(this.kind, this.label, this.title, [this.data = const {}]);
}

/// The chips offered for a screen context. The user can remove each one.
List<AiChip> chipsFor(AiScreenContext? c) {
  if (c == null) return const [];
  final t = c.title.trim();
  switch (c.kind) {
    case 'article':
      return [AiChip('article', trp('This article: {t}', {'t': t}), t, c.data)];
    case 'case':
      return [AiChip('case', tr('This case'), t, c.data)];
    case 'quiz':
      return [AiChip('quiz', tr('Quiz question'), t, c.data)];
    case 'calc':
      return [AiChip('calc', trp('Calculator: {t}', {'t': t}), t, c.data)];
    case 'library':
    case 'search':
      return t.isEmpty ? const [] : [AiChip('search', trp('Library search: {t}', {'t': t}), t, c.data)];
    default:
      return const [];
  }
}

class AiQuick {
  final String id;
  final String label;
  const AiQuick(this.id, this.label);
}

/// Quick actions per screen kind. The last one (Ask anything) is always there.
List<AiQuick> quickActionsFor(String kind) {
  final out = <AiQuick>[];
  switch (kind) {
    case 'article':
      out.addAll([
        AiQuick('deepdive', tr('Deep-dive')),
        AiQuick('simple', tr('Explain simply')),
        AiQuick('compare', tr('Compare with...')),
        AiQuick('guidelines', tr('Check against current guidelines')),
        AiQuick('questions', tr('Make questions')),
      ]);
    case 'case':
      out.addAll([AiQuick('discuss', tr('Discuss (preview)')), AiQuick('ddx', tr('Differential')), AiQuick('senior', tr('What would the senior ask?'))]);
    case 'quiz':
      out.add(AiQuick('explain_q', tr('Explain')));
    case 'calc':
      out.addAll([AiQuick('which_score', tr('Which score?')), AiQuick('interpret', tr('Interpret'))]);
    case 'library':
    case 'search':
      out.add(AiQuick('deepdive', tr('Deep-dive on this query')));
    case 'home':
      out.add(AiQuick('brief', tr("Today's brief")));
  }
  out.add(AiQuick('anything', tr('Ask anything')));
  return out;
}

// ================================================================ running a question

class AiChatOutcome {
  final AiChatMsg msg;
  const AiChatOutcome(this.msg);
}

class AiChatRunner {
  /// Banner text key for an answer: '' = none. web/custom without search, model, library and fallbacks all say where the answer came from.
  static String bannerFor(AiChatMsg m) {
    if (m.role != 'assistant' || m.failed) return '';
    if (m.localOnly) return 'library_only';
    switch (m.mode) {
      case 'library':
        return 'library';
      case 'model':
        return 'model';
      case 'web':
      case 'custom':
        if (m.searched) return 'web';
        switch (m.note) {
          case 'nosearch':
            return 'nosearch';
          case 'searchquota':
            return 'searchquota';
          case 'searchfail':
            return 'searchfail';
          case 'off':
            return 'searchoff';
        }
        return 'nosearch_used';
    }
    return '';
  }

  /// The system prompt of an action. [topic] is the context title (or the question).
  static String systemFor(String action, String topic, String mode, {String contextNote = '', String? length}) {
    switch (action) {
      case 'deepdive':
        return AiPrompts.deepDive(topic, mode: mode);
      case 'simple':
        return AiPrompts.explain(mode: mode);
      case 'guidelines':
        return AiPrompts.guidelineCheck(topic, mode: mode);
      default:
        return AiPrompts.ask(mode: mode, contextNote: contextNote, length: length);
    }
  }

  /// Sends one question and returns the assistant message. Never throws.
  static Future<AiChatMsg> answer(
    BuildContext? context,
    AiChatThread t,
    String question, {
    required String mode,
    List<AiChip> chips = const [],
    String action = '',
  }) async {
    final labels = [for (final c in chips) c.label];
    final q = question.trim();
    AiChatMsg fail(String err, {bool offline = false, bool timedOut = false}) => AiChatMsg('assistant', '', mode: mode, failed: true, error: err, offline: offline, timedOut: timedOut, chips: labels);

    // ---- context
    final article = chips.where((c) => c.kind == 'article').toList();
    final caseChip = chips.where((c) => c.kind == 'case').toList();
    final calc = chips.where((c) => c.kind == 'calc').toList();
    final quiz = chips.where((c) => c.kind == 'quiz').toList();
    final search = chips.where((c) => c.kind == 'search').toList();
    final topic = [if (article.isNotEmpty) article.first.title, if (calc.isNotEmpty) calc.first.title, if (search.isNotEmpty) search.first.title].where((e) => e.isNotEmpty).firstOrNull ??
        (action == 'deepdive' ? q : '');
    final notes = <String>[];
    if (article.isNotEmpty) notes.add('The trainee is reading the article "${article.first.title}".');
    if (calc.isNotEmpty) notes.add('The trainee is using the calculator "${calc.first.title}".');
    if (search.isNotEmpty) notes.add('The trainee searched the library for "${search.first.title}".');
    if (quiz.isNotEmpty) notes.add('The trainee is working on a practice question.');
    if (caseChip.isNotEmpty) notes.add('The trainee is working on one of their own cases (de-identified summary given as data).');

    // ---- case data (preview happens inside Ai.run)
    Map<String, String>? preview;
    if (caseChip.isNotEmpty) {
      final id = caseChip.first.data['caseId'] ?? caseChip.first.data['id'] ?? '';
      final rec = store.cases[id];
      if (rec != null) {
        if (isCaseAiBlocked(rec)) return fail(tr('This case is marked "never send to AI".'));
        final p = buildCasePayload(rec);
        if (!p.isEmpty) preview = p.fields;
      }
    }
    if (calc.isNotEmpty) {
      final inp = calc.first.data['inputs'] ?? calc.first.data['result'] ?? '';
      if (inp.isNotEmpty) preview = {...?preview, 'Calculator inputs': inp};
    }
    final quizStem = quiz.isEmpty ? '' : (quiz.first.data['stem'] ?? '');
    final quizOpts = quiz.isEmpty ? '' : (quiz.first.data['options'] ?? '');

    // ---- source mode
    var useMode = mode;
    var blockedNote = '';
    List<Passage> passages = const [];
    if (mode == 'web' || mode == 'custom') {
      blockedNote = AiEngine.searchBlockedNote();
      if (blockedNote.isNotEmpty) useMode = 'libmodel'; // no live search here: library passages + model, with a banner
    }
    if (useMode == 'library' || useMode == 'libmodel') {
      try {
        final r = await AiLibrary.retrieve(q.isEmpty ? topic : q,
            packId: article.isNotEmpty ? article.first.data['packId'] : null,
            index: article.isNotEmpty ? int.tryParse(article.first.data['index'] ?? '') : null);
        passages = r.passages;
      } catch (_) {}
      if (useMode == 'library' && passages.isEmpty) {
        // library only and nothing found: say so locally, no model call
        return AiChatMsg('assistant', tr('Not found in your library. Switch the source to Web or Model to ask beyond your references.'), mode: mode, localOnly: true, chips: labels);
      }
    }

    final deep = action == 'deepdive';
    final sysMode = (useMode == 'libmodel' || useMode == 'library' || useMode == 'model') ? useMode : mode;
    // a clinical question gets the whole answer; short only when asked for
    final plain = action.isEmpty || action == 'anything';
    final length = plain ? (AiPrompts.wantsBrief(q) ? 'brief' : 'full') : null;
    final system = systemFor(action, topic.isEmpty ? q : topic, sysMode, contextNote: notes.join(' '), length: length);
    final sb = StringBuffer();
    if (quizStem.isNotEmpty) sb.writeln('Practice question: $quizStem\n${quizOpts.isEmpty ? '' : 'Options: $quizOpts\n'}');
    sb.writeln('Question: $q');
    if (passages.isNotEmpty) sb.writeln('\nPassages:\n${AiPrompt.wrapData(AiLibrary.passagesBlock(passages), label: 'LIBRARY')}');
    final lvl = preview != null
        ? AiLevel.caseData
        : (passages.isNotEmpty || quizStem.isNotEmpty ? AiLevel.library : AiLevel.none);
    final history = <AiTurn>[
      for (final m in t.msgs.where((m) => !m.failed && m.text.trim().isNotEmpty).toList().reversed.take(6).toList().reversed)
        AiTurn(m.role, m.role == 'assistant' ? _plain(m.text) : m.text),
    ];
    final domains = AiSources.allowedFor(mode);
    final wantSearch = (mode == 'web' || mode == 'custom') && blockedNote.isEmpty;
    final feature = 'ask_chat';
    final req = AiRequest(
      feature: feature,
      system: system,
      prompt: sb.toString().trim(),
      level: lvl,
      expectJson: true,
      maxTokens: AiPrompts.maxTokens(deepDive: deep, length: length),
      temperature: 0.2,
      previewFields: preview,
      history: history,
      search: wantSearch ? AiSearchSpec(mode: mode, domains: domains, maxUses: deep ? 6 : 4) : null,
      schema: wantSearch ? null : aiDocJsonSchema,
    );
    final res = await Ai.run(req, context: context);
    if (res.offline) return fail(tr('No connection or AI is off.'), offline: true);
    if (res.cancelled) return fail(tr('Cancelled: nothing was sent.'));
    if (!res.ok) return fail(res.error ?? tr('The AI request failed.'), timedOut: res.timedOut);
    return AiChatMsg(
      'assistant',
      res.text,
      mode: mode,
      searched: res.searched,
      note: res.searched ? '' : (res.searchNote.isNotEmpty ? res.searchNote : blockedNote),
      sources: res.sources,
      queries: res.queries,
      chips: labels,
    );
  }

  /// Plain text of a stored answer (history for the model, copy, notes).
  static String _plain(String raw) {
    try {
      final t = aiDocToPlain(parseAiOutput(raw));
      return t.length > 1800 ? t.substring(0, 1800) : t;
    } catch (_) {
      return raw.length > 1800 ? raw.substring(0, 1800) : raw;
    }
  }

  // ------------------------------------------------------------ local library links

  static final RegExp _lead = RegExp(r'^[\s\-•*\d.)]+');

  /// Terms to look up in the user's library for an answer: question topic words, then the differential and the title.
  static List<String> linkTerms(AiDoc doc, String question) {
    final out = <String>[];
    void add(String s) {
      var t = s.replaceAll(RegExp(r'\[\d+\]'), '').replaceAll(RegExp(r'[*_`#]'), '').replaceFirst(_lead, '').trim();
      final cut = RegExp(r'[:(–—\-,;]').firstMatch(t);
      if (cut != null && cut.start >= 3) t = t.substring(0, cut.start).trim();
      if (t.length < 3 || t.length > 40 || t.split(' ').length > 5) return;
      if (!out.any((e) => e.toLowerCase() == t.toLowerCase())) out.add(t);
    }

    if (doc.title.trim().isNotEmpty) add(doc.title);
    for (final s in doc.sections) {
      if (s.kind == 'differential') {
        for (final b in [...s.bullets, ...s.steps].take(6)) {
          add(b);
        }
        if (s.table.length > 1) {
          for (final row in s.table.skip(1).take(6)) {
            if (row.isNotEmpty) add(row.first);
          }
        }
      }
    }
    final q = topicKeywords(question).take(4).join(' ');
    if (q.isNotEmpty) out.insert(0, q);
    return out.take(8).toList();
  }

  /// Articles of the user's own library for an answer ("From your library"). Local only, no AI.
  static Future<List<LibHit>> libraryLinks(AiDoc doc, String question, {int limit = 6}) async {
    if (!library.ready || library.textPacks.isEmpty) return const [];
    final seen = <String>{};
    final out = <LibHit>[];
    for (final term in linkTerms(doc, question)) {
      try {
        for (final h in await library.searchEx(term, concise: true, limit: 2)) {
          if (seen.add('${h.packId}|${h.index}')) out.add(h);
        }
      } catch (_) {}
      if (out.length >= limit) break;
    }
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  // ------------------------------------------------------------ saving

  /// Saves an answer as a note attached to the chat topic (library notes list).
  static Future<void> saveAsNote(String title, String markdown) async {
    await saveNote('ai_chat', title.isEmpty ? 'AI answer' : title, markdown);
  }

  /// Saves an answer as an article of "My files" in the library; returns true when added.
  static Future<bool> saveAsFile(String title, String markdown) async {
    try {
      final dir = await Directory.systemTemp.createTemp('aifile');
      var name = title.replaceAll(RegExp(r'[^A-Za-z0-9؀-ۿ \-_]'), '').trim();
      if (name.isEmpty) name = 'AI answer';
      if (name.length > 60) name = name.substring(0, 60).trim();
      final f = File('${dir.path}/$name.md');
      await f.writeAsString('# $name\n\n$markdown');
      final n = await library.importTextFiles([f.path]);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      return n > 0;
    } catch (_) {
      return false;
    }
  }
}
