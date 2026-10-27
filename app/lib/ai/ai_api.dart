import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data.dart' show CaseRec;
import 'ai_engine.dart';
import 'ai_privacy.dart';
import 'ai_sources.dart';
import 'ai_store.dart';

export 'ai_engine.dart' show AiPrompt, AiModelsResult, AiDiagStep;
export 'ai_providers.dart' show AiTransport, AiHttpRequest, AiHttpResponse, AiModel, AiProviders, AiFail, AiErrKind;
export 'ai_store.dart' show AiProviderId, AiStore, AiAudit, AiCache, kAiGroups;
export 'ai_widgets.dart' show AiButton, AiOutputCard, AiBuilder;
export 'ai_fake.dart' show installFakeAi, uninstallFakeAi, FakeAi;
export 'ai_sources.dart' show AiSource, AiSources, SourceCheck, CheckedCite, CiteStatus, verify;

/// Contract shared by every AI feature in MedLog.
///
/// ===== PUBLIC API SUMMARY (for feature code) =====
///  * `Ai.enabled`            sync: master switch on + key stored. Hide/disable AI UI when false.
///  * `Ai.online`             ValueListenable<bool>; `await Ai.isOnline()`; `Ai.featureOn('ask_refs')` per-feature switch;
///                            `Ai.levelAllowed(AiLevel.caseData)`.
///  * `await Ai.run(AiRequest(...), context: context)`  never throws:
///        offline / AI off / no key / feature off -> AiResult(offline: true)  (fall back to the non-AI path silently)
///        user declined preview                    -> AiResult(cancelled: true)
///        provider error (quota, key, busy...)     -> AiResult(error: 'friendly message in the UI language')
///        success                                  -> AiResult(ok: true, text, json (when expectJson parsed), fromCache)
///    Feature ids (AiRequest.feature) start with: ask_ | explain_ / translate_ | quiz_ | case_ | report_ / summary_ | help_
///    so the matching switch in Settings > AI assistant applies; other ids are always allowed.
///    Ai.run scrubs the prompt at every level, answers from the cache (cacheKey) even offline, appends the safety rules to
///    `system`, logs to the local activity log (never prompt text), counts requests, rate-limits (12/min).
///    caseData: pass `context` and `previewFields` (label -> value). The user sees the (scrubbed) values + the list of what was
///    removed and can untick fields: the values of unticked fields are replaced by "[removed by user]" inside `prompt`; ticked values
///    that are not already inside `prompt` are appended as DATA. No context -> cancelled (nothing is sent).
///    The first caseData request asks the one-time consent dialog; `isCaseAiBlocked(case)` must be checked by the caller BEFORE
///    building a case summary (cases flagged aiNever are never sent).
///  * `AiPrompt.wrapData(untrusted, label: 'LIBRARY')`  fence library/case text as DATA inside `prompt`.
///  * `AiPrivacy.scrub(text)`  -> ScrubResult(text, removed).
///  * Widgets (ai_widgets.dart): `AiButton(label:, icon:, feature:, onPressed:)` (hidden when AI off, disabled + tooltip when offline),
///    `AiOutputCard(text:, feature:, sources: [...])` (label, copy, report problem), `AiBuilder(builder: (ctx, enabled, online) => ...)`.
///  * Settings: `AiSettingsScreen` (lib/screens_ai_settings.dart).
///  * Tests: `installFakeAi(answers: {'keyword in prompt': 'answer'}, online: true)` (ai_fake.dart); `FakeAi.sent` = what left the phone;
///    `AiTransport.send` = replace the HTTP layer; `AiTransport.backoffScale = 0`.
///
/// Rules of the whole AI layer:
///  * The app must work 100% without AI and without internet: callers always have a non-AI fallback,
///    and must show/enable AI buttons only when [Ai.enabled] is true; when [Ai.run] says offline, fall back silently.
///  * AI only SUGGESTS: nothing is written to records without the user confirming.
///  * Level [AiLevel.none]: only the user's question text leaves the phone.
///    [AiLevel.library]: question + passages from the installed library (public licensed text).
///    [AiLevel.caseData]: a de-identified case summary after the user previews it. Never names, ids, images, or free-text dumps.
///  * Keys live in Android Keystore (SecureKv), never in backups/exports/settings.json; AI files live in <documents>/medlog_ai/
///    (outside the backed-up medlog/ folder).
enum AiLevel { none, library, caseData }

class AiResult {
  final bool ok;
  final String text;
  final Map<String, dynamic>? json; // parsed when the request asked for JSON and it parsed
  final String? error;
  final bool offline; // no internet / no key / AI off: use the non-AI fallback
  final bool cancelled; // the user declined the privacy preview
  final bool fromCache;

  /// The request did not finish in time (slow or broken connection).
  final bool timedOut;

  /// Live web search: true when the provider's search tool really ran for this answer.
  final bool searched;

  /// Why a requested web search did not run: '' | 'off' (switched off in settings) | 'nosearch' (this provider/address has no search)
  /// | 'searchfail' (the search call was refused: answered without it) | 'searchquota' (search quota used up: answered without it).
  final String searchNote;

  /// Sources the provider's search returned (not written by the model) and the queries it ran.
  final List<AiSource> sources;
  final List<String> queries;
  const AiResult({
    this.ok = false,
    this.text = '',
    this.json,
    this.error,
    this.offline = false,
    this.cancelled = false,
    this.fromCache = false,
    this.timedOut = false,
    this.searched = false,
    this.searchNote = '',
    this.sources = const [],
    this.queries = const [],
  });
}

/// One earlier message of a conversation ('user' | 'assistant').
class AiTurn {
  final String role;
  final String text;
  const AiTurn(this.role, this.text);
}

/// Asks the provider's own live web search to be used (when it has one). The engine checks the daily cap, the provider
/// and the AiPrefs.providerSearch switch, and falls back (with [AiResult.searchNote]) when the search cannot run.
class AiSearchSpec {
  /// 'web' | 'custom' (library/model are sent without a spec)
  final String mode;
  final List<String> domains;
  final int maxUses;
  const AiSearchSpec({this.mode = 'web', this.domains = const [], this.maxUses = 4});
}

class AiRequest {
  final String feature; // short id for the audit log, e.g. 'ask_refs', 'case_ddx', 'quiz_gen'
  final String system; // role + rules; feature agents write these
  final String prompt; // user content (already scrubbed by the caller or by Ai.run)
  final AiLevel level;
  final bool expectJson;
  final int maxTokens;
  final double temperature;
  final String? cacheKey; // same key = reuse the stored answer (also usable offline)
  /// For AiLevel.caseData: label -> value pairs shown in the preview before sending (what exactly leaves the phone).
  final Map<String, String>? previewFields;

  /// Conversation so far (older turns first, WITHOUT the current [prompt]); sent as real chat turns.
  final List<AiTurn> history;

  /// Live web search request (see [AiSearchSpec]); null = no search.
  final AiSearchSpec? search;

  /// JSON schema for structured output (used only when no search tool is attached and the provider takes one; a 400 retries without it).
  final Map<String, dynamic>? schema;
  const AiRequest({
    required this.feature,
    required this.system,
    required this.prompt,
    this.level = AiLevel.none,
    this.expectJson = false,
    this.maxTokens = 1024,
    this.temperature = 0.2,
    this.cacheKey,
    this.previewFields,
    this.history = const [],
    this.search,
    this.schema,
  });
}

class ScrubResult {
  final String text;
  final List<String> removed; // human-readable list of what was removed/replaced
  const ScrubResult(this.text, this.removed);
}

class Ai {
  /// The user enabled AI and a provider key is stored on this phone.
  static bool get enabled => AiEngine.enabled;

  /// Connection state for enabling/disabling buttons (updated by connectivity changes and by [isOnline]).
  static ValueListenable<bool> get online {
    AiEngine.startMonitor();
    return AiEngine.online;
  }

  static Future<bool> isOnline() => AiEngine.isOnline();

  static bool featureOn(String feature) => AiEngine.enabled && AiStore.groupOn(feature);

  static bool levelAllowed(AiLevel l) => AiEngine.levelAllowed(l);

  /// Runs a request: offline/no-key -> AiResult(offline: true); level caseData with [context] -> privacy preview first;
  /// scrubs identifiers; caches; writes the local audit log. Never throws.
  static Future<AiResult> run(AiRequest r, {BuildContext? context}) => AiEngine.run(r, context);

  /// Loads the saved AI settings (call once at start; Ai.run also does it by itself).
  static Future<void> init() => AiStore.ensureLoaded();

  /// Notes a problem with an AI answer in the local activity log.
  static Future<void> flagProblem(String feature, {String note = ''}) => AiEngine.flag(feature, note: note);

  /// Lists the models of a provider for the given key (settings screen).
  static Future<AiModelsResult> fetchModels(AiProviderId p, String key, {String openaiBase = ''}) => AiEngine.fetchModels(p, key, openaiBase: openaiBase);

  /// Tiny request to check a key (settings screen). ok -> text holds the model id used.
  static Future<List<AiDiagStep>> diagnose(AiProviderId p, String key, String model, {String openaiBase = ''}) => AiEngine.diagnose(p, key, model, openaiBase: openaiBase);

  static Future<AiResult> testKey(AiProviderId p, String key, String model, {String openaiBase = ''}) => AiEngine.test(p, key, model, openaiBase: openaiBase);
}

class AiPrivacy {
  /// Removes names/ids/phones/emails/addresses/exact dates from free text (heuristic, not a guarantee).
  static ScrubResult scrub(String text) => AiPrivacyImpl.scrub(text);
}

/// True when the user flagged this case "never send to AI" (rec.d['aiNever']). Check before building any case summary.
bool isCaseAiBlocked(CaseRec c) => c.d['aiNever'] == true;
