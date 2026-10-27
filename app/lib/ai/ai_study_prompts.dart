import 'ai_api.dart';
import 'ai_prefs.dart';
import 'ai_prompts.dart';

/// Prompts of the study features (viva, teach-me, guideline check, coach...). Thin layer over the AI core's
/// [AiPrompts.base] (persona, language, region, safety, data fence, source rule per AiPrefs.sourceMode): this file only
/// adds the study task text, forces a source mode for features that need it (guideline check = web) and builds the
/// provider search spec (web = live search restricted to the allow-list; cite organisation + year + URL).
class StudyPrompts {
  static String effectiveMode([String? forceMode]) => forceMode ?? AiPrefs.sourceMode;

  /// System prompt of a study task. [task] says what to do and in which JSON shape to answer
  /// (the AiDoc schema is NOT appended: study tasks define their own JSON).
  static String system(String task, {String? forceMode}) {
    final mode = effectiveMode(forceMode);
    if (mode == 'given') {
      // the facts are all in the request (a fenced reference, counts, a checklist): no outside sources, no web
      return [
        AiPrompts.persona,
        'TASK: $task All patients are fictional.',
        AiPrompts.languageRule(),
        'SOURCES: use ONLY the material given in this request; never add outside facts, guidelines, numbers or links. If the material is not enough, say so.',
        AiPrompts.safety,
        AiPrompts.fence,
      ].join('\n\n');
    }
    return AiPrompts.base(
      task: '$task All patients are fictional. Never state a fact without a source unless the source rule says the model may answer from memory; mark it unverified then.',
      schema: '',
      mode: mode,
      domains: AiSources.allowedFor(mode),
    );
  }

  static AiSearchSpec? search({String? forceMode}) {
    final mode = effectiveMode(forceMode);
    if (mode != 'web' && mode != 'custom') return null;
    return AiSearchSpec(mode: mode, domains: AiSources.allowedFor(mode));
  }
}
