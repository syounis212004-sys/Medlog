import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart' show BuildContext;

import '../data.dart';
import '../goals_signoff.dart' show targetsOf, progressFor;
import '../i18n.dart';
import 'ai_api.dart';
import 'ai_case_payload.dart';
import 'ai_cases.dart';
import 'ai_doc_api.dart';
import 'ai_library.dart';
import 'ai_prefs.dart';
import 'ai_prompts.dart';
import 'ai_quiz.dart' show aiBank, aiSaveQ, kAiBank;

/// Logic of the AI helpers that live in the other screens (case senior view, guideline link, patient explanation,
/// teaching quiz, bulk tags, score finder, result interpretation, drug check, morning brief, portfolio drafts,
/// procedure deep-dive). Everything here either runs LOCALLY (numbers, validation) or builds an [AiRequest] that a
/// screen sends with [Ai.run]. The model never computes numbers; AI only suggests; sources are required.

// ================================================================ prompts (persona, language, sources)

String _h(String s) => md5.convert(utf8.encode(s)).toString().substring(0, 20);

class AiToolPrompts {
  /// Source mode used for the prompt: tools have no library passages, so 'library' becomes "web unavailable, passages not given".
  static String effectiveMode() {
    final m = AiPrefs.sourceMode;
    return m == 'library' ? 'libmodel' : m;
  }

  /// Domains the provider search may use (web = the allow-list, custom = the user own list when set).
  static List<String> allowedDomains() => AiSources.allowedFor(AiPrefs.sourceMode == 'custom' ? 'custom' : 'web');

  static bool get webMode => AiPrefs.sourceMode == 'web' || AiPrefs.sourceMode == 'custom';

  /// Live search spec for tools that need sources (null in library/model mode).
  static AiSearchSpec? search() => webMode ? AiSearchSpec(mode: AiPrefs.sourceMode, domains: AiSources.allowedFor(AiPrefs.sourceMode)) : null;

  /// Full system prompt of a tool. [json]: ask for the document schema. [cites]: sources are required (source rule of the
  /// mode); without it the answer is a teaching text without sources (brief, patient words, case rehearsal).
  static String base(String task, {bool json = true, bool cites = true, String? extra}) {
    final t = extra == null || extra.isEmpty ? task : '$task $extra';
    if (cites) {
      return AiPrompts.base(
        task: t,
        schema: json ? null : '',
        mode: effectiveMode(),
        domains: AiSources.allowedFor(AiPrefs.sourceMode),
      );
    }
    return [
      AiPrompts.persona,
      'TASK: $t',
      AiPrompts.languageRule(),
      AiPrompts.lengthRule(),
      AiPrompts.safety,
      AiPrompts.fence,
      if (json) kAiDocSchemaPrompt,
    ].join('\n\n');
  }
}

/// Parsed answer of a request: always through the shared parser.
AiDoc docOf(AiResult r) => parseAiOutput(r.text, json: r.json);

bool docHasCites(AiDoc d) => d.citations.isNotEmpty || d.sections.any((s) => s.cites.isNotEmpty);

/// Web modes require sources: an answer with none is shown with a warning.
bool needsSourceWarning(AiDoc d) => (AiPrefs.sourceMode == 'web' || AiPrefs.sourceMode == 'custom') && !docHasCites(d);

// ================================================================ cases

Map<String, String> subsetFields(AiCasePayload p, List<String> labels) => {
      for (final l in labels)
        if ((p.fields[l] ?? '').isNotEmpty) l: p.fields[l]!,
    };

/// (b) What would the senior ask / examine / order next?
AiRequest seniorRequest(AiCasePayload p) => AiRequest(
      feature: 'case_senior',
      system: AiToolPrompts.base(
        'Act as the senior doctor on the ward round who is about to question the intern about this de-identified case. '
        'Use ONLY the facts given in the case; list what is missing instead of guessing. Sections (kind): "key_points" = the questions the senior is likely to ask '
        '(with the short answer the intern should be ready with when the case gives it), "presentation" = what the senior would examine next, '
        '"investigations" = what the senior might ask you to order or chase next and why (no doses), "red_flags", "note" = one tip for presenting this case. '
        'Phrase as "for your consideration".',
        cites: false,
      ),
      prompt: 'Prepare me for the senior: what will they ask, what will they examine, what will they order next?',
      level: AiLevel.caseData,
      expectJson: true,
      maxTokens: 1600,
      previewFields: p.fields,
      cacheKey: p.cacheKey('case_senior', AiPrefs.answerLang),
    );

const List<String> kGuidelineLabels = ['Age group', 'Sex', 'Setting', 'Specialty', 'Working diagnosis', 'Final diagnosis'];

/// (b) Link this case to guidelines: only the diagnosis (and age group, sex, setting) is sent; no patient-specific orders.
AiRequest guidelineRequest(AiCasePayload p) {
  final f = subsetFields(p, kGuidelineLabels);
  if (!f.containsKey('Working diagnosis') && !f.containsKey('Final diagnosis') && (p.fields['Chief complaint'] ?? '').isNotEmpty) {
    f['Chief complaint'] = p.fields['Chief complaint']!;
  }
  return AiRequest(
    feature: 'case_guideline',
    system: AiToolPrompts.base(
      'List the current guidelines that cover the working diagnosis of the case (or the complaint when there is no diagnosis). '
      'Return ONE section of kind "guidelines" with a "table" whose first row is the header: Organisation | Year | Guideline | Key recommendation (one line). '
      'Also give "cites" for every row (org, year, url). Describe general recommendations only: do NOT give patient-specific orders, doses or a plan for this patient. '
      'Prefer the guidelines of the region the learner works in when a region is given${AiPrefs.region.isEmpty ? '' : ' (${AiPrefs.region})'}. '
      'If no source is found write "no verified source found".',
    ),
    prompt: 'Which guidelines apply to this diagnosis, and what do they recommend in general?',
    level: AiLevel.caseData,
    expectJson: true,
    maxTokens: 1500,
    previewFields: f,
    search: AiToolPrompts.search(),
      cacheKey: _h('case_guideline|${f.entries.map((e) => '${e.key}=${e.value}').join('|')}|${AiPrefs.sourceMode}|${AiPrefs.answerLang}'),
  );
}

/// (b) Explain this to a patient (plain language): a DRAFT for the intern to check and say in their own words.
AiRequest patientExplainRequest(AiCasePayload p) => AiRequest(
      feature: 'case_patient',
      system: AiToolPrompts.base(
        'Write a plain-language explanation that an intern could give to the patient or family: what the likely problem is, what happens next, '
        'what to watch for and when to ask for help. Reading level: age 12. Short sentences, no jargon (explain any medical word). Warm, calm tone. '
        'Use only the facts in the case. Do not promise outcomes, do not give doses, do not name a diagnosis as certain when the case says working diagnosis. '
        'Sections: "overview" (what is going on), "steps" (what happens next, as bullets), "red_flags" (when to ask for help), "note" (a reminder that the intern checks with the senior first).',
        cites: false,
      ),
      prompt: 'Draft a plain-language explanation of this case for the patient.',
      level: AiLevel.caseData,
      expectJson: true,
      maxTokens: 900,
      previewFields: subsetFields(p, [
        'Age group', 'Sex', 'Setting', 'Chief complaint', 'Working diagnosis', 'Final diagnosis', 'Investigations', 'Plan and management', 'Disposition', 'Follow-up',
      ]),
      cacheKey: p.cacheKey('case_patient', AiPrefs.answerLang),
    );

/// (b) Teaching points + a 3-question mini quiz from the case. Teaching points carry citations; the quiz is saved only from cited facts.
AiRequest teachRequest(AiCasePayload p) => AiRequest(
      feature: 'case_teach',
      system: AiToolPrompts.base(
        'Make teaching material for the intern from this de-identified case. Return the document schema with: a section of kind "key_points" '
        'titled "Teaching points" (4 to 6 bullets, each a general fact about the condition, with the guideline cited in "cites"), and add the extra top-level '
        'field "quiz": exactly 3 questions [{"q":"question","options":["A","B","C","D"],"answer":0,"why":"one-line reason","cite":{"org":"","year":"","url":""}}]. '
        'Questions test general knowledge triggered by the case (never the identity of the patient). ',
        extra: 'The "quiz" array goes next to "sections" in the same JSON object.',
      ),
      prompt: 'Give me teaching points and a 3-question mini quiz from this case.',
      level: AiLevel.caseData,
      expectJson: true,
      maxTokens: 1800,
      previewFields: subsetFields(p, [
        'Age group', 'Sex', 'Setting', 'Specialty', 'Chief complaint', 'History of present illness', 'Vitals', 'Investigations',
        'Working diagnosis', 'Final diagnosis', 'Problem list',
      ]),
      search: AiToolPrompts.search(),
      cacheKey: p.cacheKey('case_teach', '${AiPrefs.sourceMode}|${AiPrefs.answerLang}'),
    );

class MiniQuizQ {
  final String q;
  final List<String> options;
  final int answer;
  final String why;
  final AiCite? cite;
  const MiniQuizQ(this.q, this.options, this.answer, this.why, this.cite);
  String get answerText => answer >= 0 && answer < options.length ? options[answer] : '';
}

List<MiniQuizQ> parseMiniQuiz(Map<String, dynamic>? j) {
  final raw = j?['quiz'];
  if (raw is! List) return const [];
  final out = <MiniQuizQ>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final q = (e['q'] ?? e['question'] ?? '').toString().trim();
    final opts = e['options'] is List ? [for (final o in e['options'] as List) o.toString().trim()] : <String>[];
    final av = e['answer'];
    final a = av is num ? av.toInt() : (int.tryParse('$av') ?? -1);
    if (q.isEmpty || opts.length < 2 || a < 0 || a >= opts.length) continue;
    AiCite? c;
    final cj = e['cite'];
    if (cj is Map) {
      final org = (cj['org'] ?? '').toString().trim(), year = (cj['year'] ?? '').toString().trim(), url = (cj['url'] ?? '').toString().trim();
      if (org.isNotEmpty && url.isNotEmpty) c = AiCite(label: [org, year].where((s) => s.isNotEmpty).join(' '), org: org, year: year, url: url);
    }
    out.add(MiniQuizQ(q, opts, a, (e['why'] ?? e['explanation'] ?? '').toString().trim(), c));
    if (out.length == 3) break;
  }
  return out;
}

/// Saves the mini quiz questions that have a citation to the AI bank. Returns the number of NEW questions.
Future<int> saveMiniQuiz(List<MiniQuizQ> qs) async {
  final have = {for (final q in aiBank(includeFlagged: true)) q.id};
  var n = 0;
  for (final x in qs) {
    final c = x.cite;
    if (c == null) continue; // bank rule for web material: citation present
    final id = _h('mini|${x.q}|${x.answerText}');
    if (have.contains(id)) continue;
    final label = c.label.isEmpty ? c.org : c.label;
    await aiSaveQ({
      'id': id,
      'stem': x.q,
      'options': x.options,
      'answer': x.answer,
      'expl': x.why,
      'quote': x.why,
      'p': '',
      'i': -1,
      'title': label,
      'section': 'Case mini quiz',
      'topic': 'Case mini quiz',
      'group': 'AI (web answer)',
      'diff': 'medium',
      'style': 'vignette',
      'src': 'web',
      'cite': label,
      'url': c.url,
      'seen': 0,
      'correct': 0,
      'flagged': false,
      'createdAt': nowIso(),
    });
    have.add(id);
    n++;
  }
  return n;
}

// ---------------------------------------------------------------- bulk tag suggestions

/// Cases the bulk tagger may use: not demo, no tags, not flagged "never send to AI", with something to classify.
List<CaseRec> untaggedCases() {
  final out = <CaseRec>[];
  for (final c in store.casesSorted()) {
    if (c.d['demo'] == true || c.id.startsWith('demo_')) continue;
    if (c.tags.isNotEmpty || isCaseAiBlocked(c)) continue;
    if (c.s('cc').trim().isEmpty && c.s('workingDx').trim().isEmpty && c.s('finalDx').trim().isEmpty) continue;
    out.add(c);
  }
  return out;
}

const int kBulkTagBatch = 8;

/// Short de-identified line of a case (label -> value) for the bulk request. Never code, id, dates.
String bulkLine(CaseRec c) {
  final f = buildCasePayload(c).fields;
  return [
    for (final k in const ['Age group', 'Sex', 'Specialty', 'Chief complaint', 'Working diagnosis', 'Final diagnosis'])
      if ((f[k] ?? '').isNotEmpty) '$k: ${f[k]!.length > 160 ? '${f[k]!.substring(0, 160)}...' : f[k]}',
  ].join('; ');
}

Map<String, String> bulkPreview(List<CaseRec> batch) => {
      for (var i = 0; i < batch.length; i++)
        if (bulkLine(batch[i]).isNotEmpty) 'Case ${i + 1}': bulkLine(batch[i]),
    };

AiRequest bulkTagsRequest(List<CaseRec> batch) {
  final used = <String, int>{};
  for (final x in store.cases.values) {
    for (final t in x.tags) {
      used[t] = (used[t] ?? 0) + 1;
    }
  }
  final vocab = (used.keys.toList()..sort((a, b) => used[b]!.compareTo(used[a]!))).take(15).map((t) => cleanFreeText(t, const [], <String>[])).where((t) => t.isNotEmpty);
  final pv = bulkPreview(batch);
  return AiRequest(
    feature: 'case_tags_bulk',
    system: AiToolPrompts.base(
      'Suggest short lowercase tags (1 to 4 per case, underscores instead of spaces, e.g. chest_pain, dka) that classify each de-identified case summary. '
      'Use only the text of each summary. ${vocab.isEmpty ? '' : 'Prefer these existing tags when they fit: ${vocab.join(', ')}. '}'
      'Return ONLY JSON: {"cases":[{"n":1,"tags":["tag"]}]} where n is the number after "Case".',
      json: false,
      cites: false,
    ),
    prompt: 'Suggest tags for each case.',
    level: AiLevel.caseData,
    expectJson: true,
    maxTokens: 700,
    previewFields: pv,
    cacheKey: _h('case_tags_bulk|${pv.entries.map((e) => '${e.key}${e.value}').join('|')}'),
  );
}

/// n -> tags for the batch positions that exist. The model cannot add tags to a case outside the batch.
Map<int, List<String>> parseBulkTags(Map<String, dynamic>? j, int batchSize) {
  final out = <int, List<String>>{};
  final raw = j?['cases'];
  if (raw is! List) return out;
  for (final e in raw) {
    if (e is! Map) continue;
    final nv = e['n'];
    final n = nv is num ? nv.toInt() : (int.tryParse('$nv') ?? -1);
    if (n < 1 || n > batchSize || e['tags'] is! List) continue;
    final tags = <String>[];
    for (final t in e['tags'] as List) {
      final c = t.toString().trim().replaceAll('#', '').replaceAll(RegExp(r'\s+'), '_').toLowerCase();
      if (c.isEmpty || c.length > 30 || tags.contains(c) || !RegExp(r'^[\p{L}\p{N}_\-]+$', unicode: true).hasMatch(c)) continue;
      tags.add(c);
      if (tags.length == 4) break;
    }
    if (tags.isNotEmpty) out[n] = tags;
  }
  return out;
}

// ================================================================ calculators

/// Names of the in-app calculators the score finder can send the learner to (id -> title).
const Map<String, String> kCalcTitles = {
  'cl_bmi': 'BMI',
  'cl_map': 'Mean arterial pressure (MAP)',
  'cl_gcs': 'Glasgow Coma Scale (GCS)',
  'cl_curb': 'CURB-65 (pneumonia severity)',
  'cl_wdvt': 'Wells score for DVT',
  'cl_wpe': 'Wells score for pulmonary embolism',
  'cl_cha': 'CHA2DS2-VASc (stroke risk in AF)',
  'cl_ag': 'Anion gap',
  'cl_ca': 'Corrected calcium',
  'cl_qtc': 'QTc (Bazett)',
  'cl_egfr': 'eGFR (CKD-EPI 2021)',
  'cl_cg': 'Creatinine clearance (Cockcroft-Gault)',
  'cl_fluid': 'Maintenance fluids in children (4-2-1)',
  'cl_edd': 'Due date and gestational age',
};

/// Level none: [description] is typed by the user (scrubbed). With a case ([p] given) the level is caseData with a preview.
AiRequest scoreFinderRequest({String description = '', AiCasePayload? p}) {
  final desc = AiPrivacy.scrub(description.trim()).text;
  final fields = p == null
      ? null
      : subsetFields(p, ['Age group', 'Sex', 'Setting', 'Chief complaint', 'History of present illness', 'Vitals', 'Investigations', 'Working diagnosis', 'Problem list']);
  return AiRequest(
    feature: 'ask_score',
    system: AiToolPrompts.base(
      'Suggest which validated clinical scores or decision rules fit the clinical picture (1 to 4). For each give: the score name, why it fits, what inputs it needs, '
      'and the guideline or paper that recommends it (org, year, url). Mark the ones the app can calculate: ${kCalcTitles.values.join('; ')}. '
      'Return the document schema with ONE section of kind "table" whose first row is the header: Score | Why it fits | Inputs needed | Source, plus "cites". '
      'Never calculate the score yourself and never give a result for the patient.',
    ),
    prompt: p == null ? 'Which score fits this situation?\n${AiPrompt.wrapData(desc, label: 'DESCRIPTION')}' : 'Which score fits this case?',
    level: p == null ? AiLevel.none : AiLevel.caseData,
    expectJson: true,
    maxTokens: 1100,
    previewFields: fields,
    search: AiToolPrompts.search(),
      cacheKey: _h('ask_score|${p == null ? desc : fields!.entries.map((e) => e.value).join('|')}|${AiPrefs.sourceMode}|${AiPrefs.answerLang}'),
  );
}

/// In-app calculators named in a score table (so the screen can offer "Open calculator").
List<String> calcIdsMentioned(String text) {
  final low = text.toLowerCase();
  final out = <String>[];
  for (final e in kCalcTitles.entries) {
    final names = <String>{e.value.toLowerCase(), e.value.toLowerCase().split(' (').first};
    if (e.key == 'cl_curb') names.add('curb-65');
    if (e.key == 'cl_cha') names.addAll({'cha2ds2-vasc', 'cha₂ds₂-vasc'});
    if (e.key == 'cl_wdvt') names.add('wells score for dvt');
    if (e.key == 'cl_wpe') names.addAll({'wells score for pe', 'wells score for pulmonary embolism'});
    if (e.key == 'cl_egfr') names.addAll({'egfr', 'ckd-epi'});
    if (e.key == 'cl_gcs') names.addAll({'glasgow coma', 'gcs'});
    if (names.any((n) => n.length > 2 && low.contains(n))) out.add(e.key);
  }
  return out;
}

/// Interpret a result the APP computed. Only the calculator name, the value and the app meaning are sent.
AiRequest interpretRequest({required String calc, required String value, required String meaning}) {
  final v = AiPrivacy.scrub(value).text, m = AiPrivacy.scrub(meaning).text;
  return AiRequest(
    feature: 'ask_calc_interpret',
    system: AiToolPrompts.base(
      'The learner computed a clinical score in the app. Explain what the result means using the thresholds of a named guideline or the original validation paper: '
      'which category it falls in, what the usual next consideration is in general terms, and the limits of the score. '
      'Do not recompute or change the number. Sections: "overview", "table" (threshold | category | what it usually prompts) with cites, "note" (limits). '
      'No patient-specific orders.',
    ),
    prompt: 'Calculator: $calc\nResult: $v\nApp meaning: $m\nInterpret this result with guideline thresholds.',
    level: AiLevel.none,
    expectJson: true,
    maxTokens: 900,
    search: AiToolPrompts.search(),
      cacheKey: _h('ask_calc_interpret|$calc|$v|$m|${AiPrefs.sourceMode}|${AiPrefs.answerLang}'),
  );
}

// ================================================================ drug check (cited-only)

enum DrugKind { interaction, renal, hepatic, pregnancy, paediatric }

const Map<DrugKind, String> kDrugKindLabel = {
  DrugKind.interaction: 'Interactions',
  DrugKind.renal: 'Kidney dose adjustment',
  DrugKind.hepatic: 'Liver dose adjustment',
  DrugKind.pregnancy: 'Pregnancy and breastfeeding',
  DrugKind.paediatric: 'Children',
};

const Map<DrugKind, String> _kindAsk = {
  DrugKind.interaction: 'clinically significant interactions between the listed drugs',
  DrugKind.renal: 'whether and how the drug needs adjustment in renal impairment',
  DrugKind.hepatic: 'whether and how the drug needs adjustment in hepatic impairment',
  DrugKind.pregnancy: 'safety in pregnancy and breastfeeding',
  DrugKind.paediatric: 'use in children (age limits, dosing sources, cautions)',
};

class DrugQuery {
  final DrugKind kind;
  final List<String> drugs;
  final String context; // optional short note typed by the user (no patient data)
  DrugQuery(this.kind, List<String> drugs, {String context = ''})
      : drugs = [for (final d in drugs) _cleanDrug(d)].where((d) => d.isNotEmpty).toList(),
        context = _cleanCtx(context);

  static String _cleanCtx(String s) {
    final t = AiPrivacy.scrub(s.trim()).text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 120 ? t.substring(0, 120) : t;
  }

  static String _cleanDrug(String s) {
    final t = AiPrivacy.scrub(s.trim()).text.replaceAll(RegExp(r'[^\p{L}\p{N}\s\-/+().]', unicode: true), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 40 ? t.substring(0, 40) : t;
  }

  bool get valid => kind == DrugKind.interaction ? drugs.length >= 2 : drugs.isNotEmpty;

  String get question =>
      '${kDrugKindLabel[kind]}: ${drugs.join(kind == DrugKind.interaction ? ' + ' : ', ')}${context.isEmpty ? '' : ' ($context)'}';
}

/// One cited statement.
class DrugFinding {
  final String text;
  final AiCite cite;
  final bool confirmed; // the live search returned this host
  const DrugFinding(this.text, this.cite, {this.confirmed = false});
}

enum DrugStatus { answered, noSource, offline, off, cancelled, error }

class DrugAnswer {
  final DrugStatus status;
  final List<DrugFinding> findings;
  final String reason; // why there is no answer / error text
  final List<Passage> passages; // library mode
  final String libraryText;
  final bool searched; // the provider live search really ran for this answer
  const DrugAnswer(this.status, {this.findings = const [], this.reason = '', this.passages = const [], this.libraryText = '', this.searched = false});

  bool get answered => status == DrugStatus.answered;
  static const DrugAnswer none = DrugAnswer(DrugStatus.noSource);
}

bool hostAllowed(String url, List<String> allowed) => AiSources.hostMatches(AiSources.hostOf(url), allowed);

bool citeValid(AiCite c, List<String> allowed) =>
    c.org.trim().isNotEmpty && RegExp(r'^(19|20)\d{2}$').hasMatch(c.year.trim()) && hostAllowed(c.url, allowed);

AiRequest drugWebRequest(DrugQuery q) => AiRequest(
      feature: 'ask_drug',
      system: AiToolPrompts.base(
        'You answer drug-information questions for a junior doctor ONLY from published guidelines, drug monographs or labels found by search on the allowed domains. '
        'Never answer from memory. Return ONLY JSON: {"findings":[{"statement":"one factual sentence","org":"organisation","year":"2024","url":"https://..."}],"no_source":false}. '
        'Each finding must have its own org, year and url from the allowed domains. A dose may appear only if the cited source states it, with the same numbers. '
        'If you cannot find a source for the question return {"findings":[],"no_source":true}. This is general drug information, not advice for a patient.',
        json: false,
      ),
      prompt: 'Question (${_kindAsk[q.kind]}): ${q.question}',
      level: AiLevel.none,
      expectJson: true,
      maxTokens: 1100,
      temperature: 0.1,
      search: AiToolPrompts.search(),
      cacheKey: _h('ask_drug|${q.kind.name}|${q.drugs.map((d) => d.toLowerCase()).join(',')}|${q.context}|${AiPrefs.sourceMode}|${AiToolPrompts.allowedDomains().join(',')}|${AiPrefs.answerLang}'),
    );

/// Keeps only findings with a complete citation on an allow-listed domain. Everything else is dropped.
DrugAnswer parseDrugWeb(Map<String, dynamic>? j, List<String> allowed, {List<String> seenHosts = const [], bool searched = false}) {
  if (j == null) return const DrugAnswer(DrugStatus.noSource, reason: 'unreadable');
  if (j['no_source'] == true && (j['findings'] is! List || (j['findings'] as List).isEmpty)) return DrugAnswer.none;
  final raw = j['findings'];
  final out = <DrugFinding>[];
  if (raw is List) {
    for (final e in raw) {
      if (e is! Map) continue;
      final st = (e['statement'] ?? '').toString().trim();
      final c = AiCite(
        org: (e['org'] ?? '').toString().trim(),
        year: (e['year'] ?? '').toString().trim(),
        url: (e['url'] ?? '').toString().trim(),
        label: [(e['org'] ?? '').toString().trim(), (e['year'] ?? '').toString().trim()].where((s) => s.isNotEmpty).join(' '),
      );
      if (st.isEmpty || !citeValid(c, allowed)) continue;
      // the live search ran and returned its sources: a host it did not return is not trusted
      final host = AiSources.hostOf(c.url);
      final seen = seenHosts.isNotEmpty && seenHosts.any((h) => host == h || host.endsWith('.$h') || h.endsWith('.$host'));
      if (searched && seenHosts.isNotEmpty && !seen) continue;
      out.add(DrugFinding(st, c, confirmed: searched && seen));
    }
  }
  if (out.isEmpty) return const DrugAnswer(DrugStatus.noSource, reason: 'uncited');
  return DrugAnswer(DrugStatus.answered, findings: out.take(8).toList(), searched: searched);
}

/// Runs the drug check. NEVER takes a case. No source (web allow-list or library pack passages) = no answer.
Future<DrugAnswer> runDrugCheck(DrugQuery q, {BuildContext? context}) async {
  if (!Ai.enabled) return const DrugAnswer(DrugStatus.off);
  if (!q.valid) return const DrugAnswer(DrugStatus.noSource, reason: 'input');
  final mode = AiPrefs.sourceMode;
  if (mode == 'model') return const DrugAnswer(DrugStatus.noSource, reason: 'mode');
  if (mode == 'library') {
    final r = await AiLibrary.retrieve('${q.drugs.join(' ')} ${q.kind == DrugKind.interaction ? 'interaction' : kDrugKindLabel[q.kind]!.toLowerCase()}');
    final ps = r.passages;
    final low = ps.map((p) => '${p.title} ${p.text}'.toLowerCase()).join(' ');
    final allThere = q.drugs.every((d) => low.contains(d.toLowerCase().split(' ').first));
    if (ps.isEmpty || !allThere) return const DrugAnswer(DrugStatus.noSource, reason: 'library');
    final res = await Ai.run(AiLibrary.askRequest(q.question, ps), context: context);
    if (res.offline) return const DrugAnswer(DrugStatus.offline);
    if (res.cancelled) return const DrugAnswer(DrugStatus.cancelled);
    if (!res.ok) return DrugAnswer(DrugStatus.error, reason: res.error ?? '');
    final a = AskAnswer.from(res.text, ps);
    if (a.notFound || a.cited.isEmpty || a.unsupported.isNotEmpty) return const DrugAnswer(DrugStatus.noSource, reason: 'library');
    return DrugAnswer(DrugStatus.answered, passages: ps, libraryText: a.text);
  }
  final res = await Ai.run(drugWebRequest(q), context: context);
  if (res.offline) return const DrugAnswer(DrugStatus.offline);
  if (res.cancelled) return const DrugAnswer(DrugStatus.cancelled);
  if (!res.ok) return DrugAnswer(DrugStatus.error, reason: res.error ?? '');
  final seen = <String>[
    for (final x in res.sources) AiSources.normDomain(x.host.isNotEmpty ? x.host : AiSources.hostOf(x.url)),
  ].where((h) => h.isNotEmpty).toList();
  return parseDrugWeb(res.json, AiToolPrompts.allowedDomains(), seenHosts: seen, searched: res.searched);
}

// ================================================================ morning brief (local numbers first)

class MorningBrief {
  final int casesToday, drafts, reviewDue, aiBankCount;
  final String rotation;
  final int rotDay, rotDays;
  final List<String> goals, weak;
  const MorningBrief(this.casesToday, this.drafts, this.reviewDue, this.aiBankCount, this.rotation, this.rotDay, this.rotDays, this.goals, this.weak);

  bool get isEmpty => casesToday == 0 && drafts == 0 && reviewDue == 0 && rotation.isEmpty && goals.isEmpty && weak.isEmpty;

  /// Lines shown on the phone (translated).
  List<String> lines() => [
        trp('{n} cases today', {'n': casesToday}),
        if (drafts > 0) trp('{n} unfinished drafts', {'n': drafts}),
        trp('{n} flashcards due', {'n': reviewDue}),
        if (rotation.isNotEmpty) '${tr('Rotation')}: $rotation${rotDays > 0 ? ' (${trp('day {a} of {b}', {'a': rotDay, 'b': rotDays})})' : ''}',
        for (final g in goals.take(3)) g,
        if (weak.isNotEmpty) '${tr('Weak topics')}: ${weak.join(', ')}',
      ];

  /// Only these aggregated numbers can leave the phone.
  String aiFacts() {
    final b = StringBuffer()
      ..writeln('Cases logged today: $casesToday')
      ..writeln('Unfinished drafts: $drafts')
      ..writeln('Flashcards due: $reviewDue');
    if (rotation.isNotEmpty) b.writeln('Current rotation: $rotation${rotDays > 0 ? ', day $rotDay of $rotDays' : ''}');
    for (final g in goals.take(4)) {
      b.writeln('Goal: $g');
    }
    if (weak.isNotEmpty) b.writeln('Weak quiz topics: ${weak.join(', ')}');
    return b.toString().trimRight();
  }

  String get digest => _h('${aiFacts()}|${todayStr()}|$langCode|${AiPrefs.answerLang}');
}

MorningBrief buildMorningBrief() {
  final today = todayStr();
  final real = store.cases.values.where((c) => c.d['demo'] != true && !c.id.startsWith('demo_'));
  final todays = real.where((c) => c.s('date') == today).length;
  final drafts = real.where((c) => c.s('status') == 'Draft').length;
  final st = weekStats();
  final rot = store.currentRotation();
  var name = '', day = 0, days = 0;
  if (rot != null && rot['demo'] != true) {
    name = (rot['name'] ?? '').toString();
    final a = parseDate((rot['start'] ?? '').toString()), z = parseDate((rot['end'] ?? '').toString());
    if (a != null && z != null) {
      days = z.difference(a).inDays + 1;
      day = DateTime.now().difference(a).inDays + 1;
      if (day < 1 || day > days) day = day.clamp(1, days).toInt();
    }
  }
  int bank = 0;
  try {
    bank = store.listOf(kAiBank).length;
  } catch (_) {}
  return MorningBrief(todays, drafts, st.reviewDue, bank, name, day, days, st.goals, st.weakTopics);
}

AiRequest briefRequest(MorningBrief b) => AiRequest(
      feature: 'summary_brief',
      system: AiToolPrompts.base(
        'Write a short morning brief for a medical trainee from the numbers given. Use ONLY those numbers; never invent counts or clinical details. '
        '2 to 3 sentences, then one line starting "Suggestion:" with ONE concrete, small next action (for example reviewing the due flashcards or a weak topic). '
        'Plain text, encouraging, no medical advice.',
        json: false,
        cites: false,
      ),
      prompt: 'Numbers:\n${b.aiFacts()}',
      level: AiLevel.none,
      maxTokens: 260,
      temperature: 0.4,
      cacheKey: b.digest,
    );

AiRequest caseOfDayRequest(String topic) => AiRequest(
      feature: 'quiz_case_of_day',
      system: AiToolPrompts.base(
        'Write ONE short fictional teaching case (no real patient, no names) about the topic for an intern: 3 to 4 sentence vignette, then 2 questions with the answers hidden in the "steps" '
        'bullets as "Q1: ... -> A: ...", then one "key_points" section (3 bullets with the guideline cited) and a "note" that this is fictional and for learning.',
      ),
      prompt: 'Topic: ${AiPrivacy.scrub(topic).text}',
      level: AiLevel.none,
      expectJson: true,
      maxTokens: 1100,
      temperature: 0.6,
      search: AiToolPrompts.search(),
      cacheKey: _h('case_of_day|$topic|${todayStr()}|${AiPrefs.sourceMode}|${AiPrefs.answerLang}'),
    );

/// A topic for the case of the day: first weak topic, else the most common specialty of the user, else a default.
String caseOfDayTopic() {
  try {
    final w = weekStats().weakTopics;
    if (w.isNotEmpty) return w.first;
    final by = <String, int>{};
    for (final c in store.cases.values) {
      final s = c.s('specialty');
      if (s.isNotEmpty && c.d['demo'] != true) by[s] = (by[s] ?? 0) + 1;
    }
    if (by.isNotEmpty) return 'A common presentation in ${(by.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key}';
  } catch (_) {}
  return 'Chest pain in the emergency department';
}

// ================================================================ portfolio

/// Reflection draft from ONE of the user own cases (de-identified, previewed). The user edits it; it is marked DRAFT.
AiRequest reflectionDraftRequest(AiCasePayload p) => AiRequest(
      feature: 'report_reflection',
      system: AiToolPrompts.base(
        'Help the intern start a reflection about this de-identified case, in the first person ("I"), using Gibbs-style steps. Use ONLY facts in the case; do not invent feelings the case does not hint at: '
        'write them as gentle prompts the intern completes. Return ONLY JSON: {"title":"","happened":"","felt":"","learned":"","next":""}. Each field 1 to 3 sentences, plain text. '
        'This is a DRAFT the intern will rewrite in their own words.',
        json: false,
        cites: false,
      ),
      prompt: 'Draft a reflection for me about this case.',
      level: AiLevel.caseData,
      expectJson: true,
      maxTokens: 700,
      previewFields: subsetFields(p, [
        'Age group', 'Sex', 'Setting', 'Specialty', 'My role', 'Chief complaint', 'History of present illness', 'Working diagnosis', 'Final diagnosis', 'Outcome',
      ]),
      cacheKey: p.cacheKey('report_reflection', AiPrefs.answerLang),
    );

const String kDraftMark = 'AI draft: ';

/// Fields of a reflection entry from the model JSON; the title is marked as a draft.
Map<String, dynamic> reflectionEntryFrom(Map<String, dynamic> j) {
  String s(String k) => (j[k] ?? '').toString().trim();
  final t = s('title');
  return {
    'id': newId('rf'),
    'date': todayStr(),
    'title': '$kDraftMark${t.isEmpty ? 'Reflection' : t}',
    'happened': s('happened'),
    'felt': s('felt'),
    'learned': s('learned'),
    'next': s('next'),
    'aiDraft': true,
  };
}

/// One goal with its gap, computed locally.
class GoalGap {
  final String label;
  final int done, target, left, daysLeft;
  const GoalGap(this.label, this.done, this.target, this.left, this.daysLeft);
  double? get perWeek => daysLeft > 0 && left > 0 ? left / (daysLeft / 7) : null;
  String line() =>
      '$label $done / $target${left > 0 ? ' - ${trp('{n} to go', {'n': left})}${daysLeft > 0 ? ', ${trp('{n} days left', {'n': daysLeft})}' : ''}' : ' - ${tr('done')}'}';
  String fact() => '$label: $done of $target done, $left to go${daysLeft > 0 ? ', $daysLeft days left' : ''}';
}

List<GoalGap> goalGaps() {
  final out = <GoalGap>[];
  final rots = store.rotations.where((r) => r['demo'] != true).toList();
  final cur = store.currentRotation();
  for (final r in rots) {
    if (cur != null && r['id'] != cur['id']) continue;
    if (cur == null) break;
    final z = parseDate((r['end'] ?? '').toString());
    final left = z == null ? 0 : z.difference(DateTime.now()).inDays + 1;
    for (final g in targetsOf(r)) {
      final pr = progressFor(r, g);
      if (pr.target <= 0) continue;
      out.add(GoalGap(pr.label, pr.done, pr.target, (pr.target - pr.done).clamp(0, pr.target).toInt(), left < 0 ? 0 : left));
    }
  }
  return out;
}

AiRequest goalGapRequest(List<GoalGap> gaps, AiStats s) => AiRequest(
      feature: 'report_gap',
      system: AiToolPrompts.base(
        'The learner shows goals with local numbers. Using ONLY these numbers, say which goals are on track or behind, and suggest 3 concrete next actions for the coming week '
        '(for example which kind of case or procedure to look for, which weak quiz topic to review). Sections: "overview", "steps" (the next actions). Do not invent numbers. No medical advice.',
        cites: false,
      ),
      prompt: 'Goals:\n${gaps.map((g) => g.fact()).join('\n')}\n\nContext:\n${s.aiFacts()}',
      level: AiLevel.none,
      expectJson: true,
      maxTokens: 700,
      temperature: 0.3,
      cacheKey: _h('report_gap|${gaps.map((g) => g.fact()).join('|')}|${s.digest}|${AiPrefs.answerLang}'),
    );

AiRequest cvRequest(AiStats s) => AiRequest(
      feature: 'report_cv',
      system: AiToolPrompts.base(
        'Write a CV / training-summary paragraph for a trainee from the aggregated numbers of a rotation, plus 3 bullet lines for a CV. Use ONLY the numbers given; never invent '
        'cases, hospitals, supervisors, names or outcomes. Professional, factual, first person. Plain text. The trainee will edit it.',
        json: false,
        cites: false,
      ),
      prompt: 'Aggregated numbers:\n${s.aiFacts()}',
      level: AiLevel.none,
      maxTokens: 450,
      temperature: 0.3,
      cacheKey: _h('report_cv|${s.digest}|${AiPrefs.answerLang}'),
    );

/// Optional narrative for a whole export (logbook, analytics): aggregated counts only.
AiRequest periodNarrativeRequest(AiStats s, {String kind = 'logbook'}) => AiRequest(
      feature: 'report_$kind',
      system: AiToolPrompts.base(
        'Write a short factual summary (3 to 4 sentences) of a trainee logbook from aggregated numbers. Use ONLY the numbers given; never invent counts or clinical details. Plain text, no advice about treatment.',
        json: false,
        cites: false,
      ),
      prompt: 'Aggregated numbers:\n${s.aiFacts()}',
      level: AiLevel.none,
      maxTokens: 320,
      temperature: 0.3,
      cacheKey: _h('report_$kind|${s.digest}|${AiPrefs.answerLang}'),
    );

/// Counts of everything the user logged between [from] and [to] (null = all time), as aggregated facts.
AiStats statsOfCases(List<CaseRec> cases, List<J> procs, {String title = 'Logbook'}) {
  final spec = <String, int>{}, role = <String, int>{}, pr = <String, int>{};
  var performed = 0;
  for (final c in cases) {
    final s = c.s('specialty');
    if (s.isNotEmpty) spec[s] = (spec[s] ?? 0) + 1;
    final r = c.s('role');
    if (r.isNotEmpty) role[r] = (role[r] ?? 0) + 1;
  }
  for (final p in procs) {
    final n = (p['name'] ?? '').toString().trim();
    if (n.isNotEmpty) pr[n] = (pr[n] ?? 0) + 1;
    final r = (p['role'] ?? '').toString();
    if (r.startsWith('Performed') || r.startsWith('Independent')) performed++;
  }
  return AiStats(title, 0, cases.length, spec, role, pr, procs.length, performed, const [], const [], 0);
}

// ================================================================ procedures

AiRequest procedureRequest(String name) {
  final n = AiPrivacy.scrub(name.trim()).text;
  return AiRequest(
    feature: 'ask_procedure',
    system: AiToolPrompts.base(
      'Teach an intern how to approach a bedside procedure: indications and contraindications, equipment, the steps in order, complications and how to recognise them, '
      'consent points to cover (what to explain, risks, alternatives), after-care. Use sections of kind "overview", "steps", "complications", "key_points" (consent points, titled "Consent points"), '
      '"red_flags" (when to stop and call for help), "references". Give doses or volumes only when a cited guideline states them. Remind the learner to be supervised until signed off.',
    ),
    prompt: 'Procedure: $n',
    level: AiLevel.none,
    expectJson: true,
    maxTokens: 1500,
    search: AiToolPrompts.search(),
      cacheKey: _h('ask_procedure|${n.toLowerCase()}|${AiPrefs.sourceMode}|${AiToolPrompts.allowedDomains().length}|${AiPrefs.answerLang}'),
  );
}

/// AI paragraph for a logbook export. null when AI is off / offline / cancelled: the report then has only the plain numbers.
Future<String?> logbookNarrative(AiStats s, {BuildContext? context}) async {
  if (!Ai.enabled || s.isEmpty) return null;
  final r = await Ai.run(periodNarrativeRequest(s), context: context);
  if (!r.ok || r.text.trim().isEmpty) return null;
  return r.text.trim();
}
