import 'ai_render.dart' as r;

export 'ai_doc_widgets.dart' show AiDocView, showAiCiteSheet;

/// Contract of the AI answer formatting engine. Everything that shows an AI answer (chat, deep-dive, library
/// answers, summaries) goes through [parseAiOutput] + AiDocView, never through raw text.
class AiCite {
  final String label; // e.g. 'NICE NG51 (2024)'
  final String org;
  final String year;
  final String url;
  const AiCite({this.label = '', this.org = '', this.year = '', this.url = ''});

  bool get isEmpty => label.isEmpty && org.isEmpty && year.isEmpty && url.isEmpty;

  /// Text shown on a chip / in the reference list.
  String get short {
    if (org.isNotEmpty && year.isNotEmpty && !label.contains(year)) return '$org $year';
    if (label.isNotEmpty) return label;
    if (org.isNotEmpty) return org;
    return url;
  }

  Map<String, dynamic> toJson() => {'label': label, 'org': org, 'year': year, 'url': url};
}

/// One display block of a section (derived from the markdown or from the JSON fields).
/// type: p paragraph | b bullet (level 0..3) | n numbered step | h sub-heading | t table (rows) | m mnemonic | c code
class AiBlock {
  final String type;
  final String text; // inline markdown (**bold**, [1]) is interpreted by the renderer
  final int level;
  final List<List<String>> rows;
  const AiBlock(this.type, this.text, {this.level = 0, this.rows = const []});
}

/// kind: overview | presentation | differential | investigations | management | red_flags | dont_miss | key_points |
/// mnemonic | table | steps | guidelines | complications | prognosis | disposition | references | note | other
class AiDocSection {
  final String kind;
  final String title;
  final String text;
  final List<String> bullets;
  final List<List<String>> table; // first row = header
  final List<AiCite> cites;
  final List<String> steps;
  /// Ordered content. Empty for sections built by hand: then it is derived from text/bullets/steps/table.
  final List<AiBlock> blocks;
  const AiDocSection({this.kind = 'other', this.title = '', this.text = '', this.bullets = const [], this.table = const [], this.cites = const [], this.steps = const [], this.blocks = const []});

  List<AiBlock> get allBlocks {
    if (blocks.isNotEmpty) return blocks;
    final out = <AiBlock>[];
    for (final p in text.split(RegExp(r'\n+'))) {
      if (p.trim().isNotEmpty) out.add(AiBlock('p', p.trim()));
    }
    for (final b in bullets) {
      if (b.trim().isNotEmpty) out.add(AiBlock('b', b.trim()));
    }
    for (final s in steps) {
      if (s.trim().isNotEmpty) out.add(AiBlock('n', s.trim()));
    }
    if (table.isNotEmpty) out.add(AiBlock('t', '', rows: table));
    return out;
  }
}

class AiDoc {
  final List<AiDocSection> sections;
  final List<AiCite> citations;
  final String raw; // the untouched model text (shown by 'Raw text')
  final bool structured; // true when it came from the JSON schema, false when rebuilt from messy markdown
  final String title;
  final List<String> uncertainties;
  final String disclaimer;
  const AiDoc({this.sections = const [], this.citations = const [], this.raw = '', this.structured = false, this.title = '', this.uncertainties = const [], this.disclaimer = ''});
}

/// Section kinds accepted by the schema.
const List<String> kAiDocKinds = [
  'overview', 'presentation', 'differential', 'investigations', 'management', 'red_flags', 'dont_miss', 'key_points',
  'mnemonic', 'table', 'steps', 'guidelines', 'complications', 'prognosis', 'disposition', 'references', 'note', 'other',
];

/// Text to append to a system prompt to make the model answer in the JSON document schema (see AiDocSection kinds).
const String kAiDocSchemaPrompt = '''OUTPUT FORMAT: reply with ONE JSON object only (no code fence, no text before or after, no markdown inside the strings except [n] citation marks):
{"title":"","sections":[{"kind":"overview","title":"","text":"","bullets":[],"steps":[],"table":[],"cites":[]}],"citations":[{"label":"","org":"","year":"","url":""}],"uncertainties":[],"disclaimer":""}
Rules:
- kind is one of: overview, presentation, differential, investigations, management, red_flags, dont_miss, key_points, mnemonic, table, steps, guidelines, complications, prognosis, disposition, note.
- First section is "overview": the direct answer in 1-3 sentences. Then only the sections that matter; no filler.
- Use "bullets" for lists, "steps" for ordered actions (management: put Unstable and Stable as two sections titled "Unstable" and "Stable"), "table" for comparisons (first row is the header; every row has the same number of cells; doses go in a table: drug, dose, route, frequency, notes).
- red_flags = findings that need urgent action; dont_miss = dangerous diagnoses not to overlook; key_points = high-yield take-homes; mnemonic = one memory aid and what each letter means.
- guidelines table columns: organisation, year, recommendation. Never invent a guideline, number, dose or link: if unsure put it in "uncertainties" (what you could not verify).
- Cite with [1], [2] in the text and list each source once in "citations" (label, org, year, url when known). Cite every dose and guideline statement.
- "disclaimer" may be empty. Keep every string plain text, one idea per bullet.''';

/// Extra hint for answers in Arabic with English medical terms.
const String kAiDocSchemaPromptMixed = 'LANGUAGE: write the explanations in Arabic but keep every medical term, drug name, dose, unit, score name, guideline name and abbreviation in English exactly as in the literature (e.g. "Give aspirin 300 mg stat"). Keep the JSON keys and the "kind" values in English.';

Map<String, dynamic> _cite() => {
      'type': 'object',
      'properties': {
        'label': {'type': 'string'},
        'org': {'type': 'string'},
        'year': {'type': 'string'},
        'url': {'type': 'string'},
      },
      'required': ['label', 'org', 'year', 'url'],
    };

/// JSON schema (common subset of Gemini responseSchema / OpenAI json_schema / Claude tool input_schema:
/// no pattern, min/max, $ref or recursion). OpenAI strict mode also wants additionalProperties:false: use [aiDocJsonSchemaStrict].
final Map<String, dynamic> aiDocJsonSchema = {
  'type': 'object',
  'properties': {
    'title': {'type': 'string'},
    'sections': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'kind': {'type': 'string', 'enum': [for (final k in kAiDocKinds) if (k != 'references' && k != 'other') k]},
          'title': {'type': 'string'},
          'text': {'type': 'string'},
          'bullets': {'type': 'array', 'items': {'type': 'string'}},
          'steps': {'type': 'array', 'items': {'type': 'string'}},
          'table': {
            'type': 'array',
            'items': {'type': 'array', 'items': {'type': 'string'}},
          },
          'cites': {'type': 'array', 'items': _cite()},
        },
        'required': ['kind', 'title', 'text', 'bullets', 'steps', 'table', 'cites'],
      },
    },
    'citations': {'type': 'array', 'items': _cite()},
    'uncertainties': {'type': 'array', 'items': {'type': 'string'}},
    'disclaimer': {'type': 'string'},
  },
  'required': ['title', 'sections', 'citations', 'uncertainties', 'disclaimer'],
};

/// Deep copy of [aiDocJsonSchema] with additionalProperties:false on every object (OpenAI strict mode).
Map<String, dynamic> aiDocJsonSchemaStrict() {
  dynamic walk(dynamic n) {
    if (n is Map) {
      final m = <String, dynamic>{for (final e in n.entries) '${e.key}': walk(e.value)};
      if (m['type'] == 'object') m['additionalProperties'] = false;
      return m;
    }
    if (n is List) return [for (final e in n) walk(e)];
    return n;
  }

  return walk(aiDocJsonSchema) as Map<String, dynamic>;
}

/// Tolerant parser: JSON (optionally fenced), JSON with trailing text, truncated/dirty JSON, or messy markdown
/// (**, #, -, 1., tables). Never throws, never loses text; [raw] keeps the original.
AiDoc parseAiOutput(String text, {Map<String, dynamic>? json}) {
  try {
    return r.parseAiOutputImpl(text, json: json);
  } catch (_) {
    return AiDoc(sections: [AiDocSection(kind: 'note', text: text, blocks: [AiBlock('p', text)])], raw: text);
  }
}

/// Plain text without any markdown marks (for copy / share / notes). Sections as 'TITLE' + lines.
String aiDocToPlain(AiDoc d) => r.docToText(d, markdown: false);

/// Markdown (headings, bullets, numbered steps, pipe tables, references) for notes, My files and sharing.
String aiDocToMarkdown(AiDoc d) => r.docToText(d, markdown: true);
