import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../i18n.dart';
import 'ai_api.dart' show AiSearchSpec, AiTurn;
import 'ai_sources.dart';
import 'ai_store.dart';

// ------------------------------------------------------------------ transport seam

class AiHttpRequest {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;
  /// Per-request cap (live web search answers take longer than a plain one).
  final Duration? timeout;
  const AiHttpRequest(this.method, this.url, this.headers, [this.body, this.timeout]);
}

class AiHttpResponse {
  final int status;
  final String body;
  final Map<String, String> headers;
  const AiHttpResponse(this.status, this.body, [this.headers = const {}]);
}

/// All AI network traffic goes through [AiTransport.send]: tests replace it with a fake.
class AiTransport {
  static Future<AiHttpResponse> Function(AiHttpRequest r) send = _real;

  /// Multiplier for the retry delays (tests use 0).
  static double backoffScale = 1.0;

  /// Tests: force the answer of the reachability check.
  static Future<bool> Function()? reachability;

  static const Duration timeout = Duration(seconds: 30);

  static Future<AiHttpResponse> _real(AiHttpRequest r) async {
    final cap = r.timeout ?? timeout;
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final q = await c.openUrl(r.method, r.url);
        r.headers.forEach(q.headers.set);
        if (r.body != null) q.add(utf8.encode(r.body!));
        final resp = await q.close();
        final text = await resp.transform(utf8.decoder).join();
        final h = <String, String>{};
        resp.headers.forEach((k, v) => h[k.toLowerCase()] = v.join(','));
        return AiHttpResponse(resp.statusCode, text, h);
      })()
          .timeout(cap);
    } finally {
      c.close(force: true);
    }
  }
}

// ------------------------------------------------------------------ errors

enum AiErrKind { auth, quota, rate, network, timeout, server, blocked, badRequest, notFound, empty, config, other }

class AiFail implements Exception {
  final AiErrKind kind;
  final int status;
  final String detail; // technical, key-free, for the audit log only
  const AiFail(this.kind, {this.status = 0, this.detail = ''});

  /// Friendly message in the user's UI language.
  String get message {
    switch (kind) {
      case AiErrKind.auth:
        return tr('The key was not accepted. Check that it is copied completely and belongs to this provider.');
      case AiErrKind.quota:
        return tr('The free quota for today is used up. Try again later, or use another key or provider.');
      case AiErrKind.rate:
        return tr('Too many requests at once. Wait a minute and try again.');
      case AiErrKind.network:
        return tr('No connection to the AI service.');
      case AiErrKind.timeout:
        return tr('The AI service took too long to answer. Try again.');
      case AiErrKind.server:
        return tr('The AI service is busy right now. Try again in a moment.');
      case AiErrKind.blocked:
        return tr('The AI service declined to answer this request.');
      case AiErrKind.badRequest:
        return tr('The AI service did not accept the request. Try another model in the AI settings.');
      case AiErrKind.notFound:
        return tr('Model not found. Pick another model in the AI settings.');
      case AiErrKind.empty:
        return tr('The AI service returned an empty answer.');
      case AiErrKind.config:
        return tr('The AI address is not valid. Use an https address.');
      case AiErrKind.other:
        return tr('The AI request failed.');
    }
  }
}

class AiCompletion {
  final String text;
  final int inTokens;
  final int outTokens;
  final List<AiSource> sources;
  final List<String> queries;
  final bool searched;
  final String searchError; // Claude: error_code of a web_search_tool_result_error
  final bool paused; // Claude stop_reason pause_turn: resend [rawContent] as an assistant turn to continue
  final List<Map<String, dynamic>> rawContent;
  const AiCompletion(this.text,
      {this.inTokens = 0,
      this.outTokens = 0,
      this.sources = const [],
      this.queries = const [],
      this.searched = false,
      this.searchError = '',
      this.paused = false,
      this.rawContent = const []});
}

class AiModel {
  final String id;
  final String label;
  const AiModel(this.id, [String? label]) : label = label ?? id;
}

// ------------------------------------------------------------------ providers

class AiProviders {
  static const String geminiBase = 'https://generativelanguage.googleapis.com';
  static const String anthropicBase = 'https://api.anthropic.com';
  static const String openaiDefaultBase = 'https://api.openai.com/v1';

  static String label(AiProviderId p) {
    switch (p) {
      case AiProviderId.gemini:
        return 'Google Gemini';
      case AiProviderId.anthropic:
        return 'Anthropic Claude';
      case AiProviderId.openai:
        return 'OpenAI-compatible';
    }
  }

  static String keyHelp(AiProviderId p) {
    switch (p) {
      case AiProviderId.gemini:
        return 'aistudio.google.com/apikey';
      case AiProviderId.anthropic:
        return 'console.anthropic.com';
      case AiProviderId.openai:
        return 'platform.openai.com / openrouter.ai / groq.com';
    }
  }

  /// https is required except for a server on this phone or the local network.
  static Uri? safeBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return null;
    if (u.scheme == 'https') return u;
    if (u.scheme == 'http') {
      final h = u.host;
      final local = h == 'localhost' ||
          h.endsWith('.local') ||
          RegExp(r'^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)').hasMatch(h) ||
          h == '10.0.2.2';
      if (local) return u;
    }
    return null;
  }

  static Uri _join(Uri base, String path, [Map<String, String>? q]) {
    final bp = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
    return base.replace(path: '$bp$path', queryParameters: q == null || q.isEmpty ? null : q);
  }

  static Uri _base(AiProviderId p, String openaiBase) {
    switch (p) {
      case AiProviderId.gemini:
        return Uri.parse(geminiBase);
      case AiProviderId.anthropic:
        return Uri.parse(anthropicBase);
      case AiProviderId.openai:
        final u = safeBase(openaiBase.isEmpty ? openaiDefaultBase : openaiBase);
        if (u == null) throw const AiFail(AiErrKind.config);
        return u;
    }
  }

  static bool _isOpenAiHost(Uri u) => u.host == 'api.openai.com';

  // ---- chat request

  /// True when the provider/address can run a live web search from this app.
  /// Gemini: google_search grounding; Claude: web_search tool; OpenAI-compatible: only api.openai.com (Responses API).
  static bool supportsSearch(AiProviderId p, String openaiBase) {
    switch (p) {
      case AiProviderId.gemini:
      case AiProviderId.anthropic:
        return true;
      case AiProviderId.openai:
        final u = safeBase(openaiBase.isEmpty ? openaiDefaultBase : openaiBase);
        return u != null && _isOpenAiHost(u);
    }
  }

  static List<String> _bareDomains(List<String> d) {
    final out = <String>[];
    for (final x in d) {
      final n = AiSources.normDomain(x);
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
    }
    return out;
  }

  static AiHttpRequest buildChat({
    required AiProviderId p,
    required String key,
    required String model,
    required String system,
    required String prompt,
    required bool json,
    required int maxTokens,
    double? temperature,
    String openaiBase = '',
    List<AiTurn> history = const [],
    AiSearchSpec? search,
    List<Map<String, dynamic>> continuation = const [],
    Map<String, dynamic>? schema,
  }) {
    final r = _buildChatRaw(p: p, key: key, model: model, system: system, prompt: prompt, json: json, maxTokens: maxTokens, temperature: temperature, openaiBase: openaiBase, history: history, search: search, continuation: continuation, schema: schema);
    // a live-search answer needs longer than a plain one, but never unbounded
    return search != null ? AiHttpRequest(r.method, r.url, r.headers, r.body, const Duration(seconds: 45)) : r;
  }

  static AiHttpRequest _buildChatRaw({
    required AiProviderId p,
    required String key,
    required String model,
    required String system,
    required String prompt,
    required bool json,
    required int maxTokens,
    double? temperature,
    String openaiBase = '',
    List<AiTurn> history = const [],
    AiSearchSpec? search,
    List<Map<String, dynamic>> continuation = const [],
    Map<String, dynamic>? schema,
  }) {
    final base = _base(p, openaiBase);
    switch (p) {
      case AiProviderId.gemini:
        final noSys = model.toLowerCase().contains('gemma'); // Gemma models take no systemInstruction
        final turns = <Map<String, dynamic>>[
          for (final t in history) {'role': t.role == 'assistant' ? 'model' : 'user', 'parts': [{'text': t.text}]},
        ];
        final firstUser = turns.isEmpty;
        turns.add({'role': 'user', 'parts': [{'text': noSys && system.isNotEmpty && firstUser ? '$system\n\n$prompt' : prompt}]});
        if (noSys && system.isNotEmpty && !firstUser) {
          turns.first['parts'] = [{'text': '$system\n\n${(turns.first['parts'] as List).first['text']}'}];
        }
        final body = <String, dynamic>{
          if (!noSys && system.isNotEmpty) 'systemInstruction': {'parts': [{'text': system}]},
          'contents': turns,
          // Verified (docs, 2026-10): tools:[{"google_search":{}}]. JSON mime type is NOT sent with the tool (not documented for
          // generateContent; older models answer 400): the prompt carries the schema and the parser is tolerant.
          if (search != null && !noSys) 'tools': [{'google_search': <String, dynamic>{}}],
          'generationConfig': {
            // thinking models spend part of the budget on hidden reasoning: leave headroom
            'maxOutputTokens': maxTokens + 1024,
            if (temperature != null) 'temperature': temperature,
            if (json && !noSys && search == null) 'responseMimeType': 'application/json',
            if (json && !noSys && search == null && schema != null) 'responseSchema': schema,
          },
          'safetySettings': [
            for (final c in ['HARM_CATEGORY_HARASSMENT', 'HARM_CATEGORY_HATE_SPEECH', 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'HARM_CATEGORY_DANGEROUS_CONTENT'])
              {'category': c, 'threshold': 'BLOCK_ONLY_HIGH'}
          ],
        };
        return AiHttpRequest('POST', _join(base, '/v1beta/models/$model:generateContent'),
            {'content-type': 'application/json', 'x-goog-api-key': key}, jsonEncode(body));
      case AiProviderId.anthropic:
        final msgs = <Map<String, dynamic>>[
          for (final t in history) {'role': t.role == 'assistant' ? 'assistant' : 'user', 'content': t.text},
          {'role': 'user', 'content': prompt},
          ...continuation,
        ];
        final sys = json ? '$system\n\nReply with one valid JSON object only: no prose, no code fences.' : system;
        final body = <String, dynamic>{
          'model': model,
          'max_tokens': maxTokens,
          if (sys.isNotEmpty) 'system': sys,
          'messages': msgs,
          if (temperature != null) 'temperature': temperature,
          if (search != null)
            'tools': [
              {
                'type': 'web_search_20250305',
                'name': 'web_search',
                'max_uses': search.maxUses,
                // allowed_domains and blocked_domains are mutually exclusive (400): only allowed_domains is used
                if (_bareDomains(search.domains).isNotEmpty) 'allowed_domains': _bareDomains(search.domains),
              }
            ],
        };
        return AiHttpRequest('POST', _join(base, '/v1/messages'),
            {'content-type': 'application/json', 'x-api-key': key, 'anthropic-version': '2023-06-01'}, jsonEncode(body));
      case AiProviderId.openai:
        final official = _isOpenAiHost(base);
        final m = model.toLowerCase();
        final reasoning = official && (RegExp(r'^o\d').hasMatch(m) || m.startsWith('gpt-5'));
        if (search != null && official) {
          // Responses API: the only place with domain filters (verified in the docs)
          final doms = _bareDomains(search.domains);
          final body = <String, dynamic>{
            'model': model,
            if (system.isNotEmpty) 'instructions': system,
            'input': [
              for (final t in history) {'role': t.role == 'assistant' ? 'assistant' : 'user', 'content': t.text},
              {'role': 'user', 'content': prompt},
            ],
            'max_output_tokens': reasoning ? maxTokens + 2048 : maxTokens,
            if (temperature != null && !reasoning) 'temperature': temperature,
            'tools': [
              {
                'type': 'web_search',
                if (doms.isNotEmpty) 'filters': {'allowed_domains': doms.take(100).toList()},
              }
            ],
          };
          return AiHttpRequest('POST', _join(base, '/responses'),
              {'content-type': 'application/json', 'authorization': 'Bearer $key'}, jsonEncode(body));
        }
        final body = <String, dynamic>{
          'model': model,
          'messages': [
            if (system.isNotEmpty) {'role': 'system', 'content': system},
            for (final t in history) {'role': t.role == 'assistant' ? 'assistant' : 'user', 'content': t.text},
            {'role': 'user', 'content': prompt},
          ],
          if (official) 'max_completion_tokens': reasoning ? maxTokens + 1024 : maxTokens else 'max_tokens': maxTokens,
          if (temperature != null && !reasoning) 'temperature': temperature,
          if (json && schema != null && official)
            'response_format': {
              'type': 'json_schema',
              'json_schema': {'name': 'answer', 'strict': true, 'schema': schema}
            }
          else if (json)
            'response_format': {'type': 'json_object'},
        };
        return AiHttpRequest('POST', _join(base, '/chat/completions'),
            {'content-type': 'application/json', 'authorization': 'Bearer $key'}, jsonEncode(body));
    }
  }

  static String _hostOfAny(String url) {
    final h = AiSources.hostOf(url, requireHttps: false);
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  /// Parses a chat answer. [responses]: the OpenAI answer came from /responses (search) and not /chat/completions.
  static AiCompletion parseChat(AiProviderId p, AiHttpResponse r, {bool responses = false}) {
    final j = _decode(r.body);
    switch (p) {
      case AiProviderId.gemini:
        final fb = j['promptFeedback'];
        if (fb is Map && fb['blockReason'] != null) throw AiFail(AiErrKind.blocked, detail: 'blockReason ${fb['blockReason']}');
        final cands = j['candidates'];
        if (cands is! List || cands.isEmpty) throw const AiFail(AiErrKind.empty, detail: 'no candidates');
        final c = cands.first as Map;
        final parts = (c['content'] is Map ? (c['content'] as Map)['parts'] : null);
        final sb = StringBuffer();
        if (parts is List) {
          for (final x in parts) {
            if (x is Map && x['text'] is String && x['thought'] != true) sb.write(x['text']);
          }
        }
        final text = sb.toString();
        if (text.trim().isEmpty) {
          final fr = c['finishReason']?.toString() ?? '';
          throw AiFail(fr == 'SAFETY' || fr == 'PROHIBITED_CONTENT' || fr == 'RECITATION' ? AiErrKind.blocked : AiErrKind.empty, detail: 'finishReason $fr');
        }
        final u = j['usageMetadata'];
        // grounding: chunk.web.title is the source DOMAIN, chunk.web.uri a redirect address (verified in the docs)
        final sources = <AiSource>[];
        final queries = <String>[];
        final gm = c['groundingMetadata'];
        if (gm is Map) {
          final q = gm['webSearchQueries'];
          if (q is List) queries.addAll([for (final e in q) '$e']);
          final ch = gm['groundingChunks'];
          if (ch is List) {
            final seen = <String>{};
            for (final e in ch) {
              final w = e is Map ? e['web'] : null;
              if (w is! Map) continue;
              final title = '${w['title'] ?? ''}'.trim();
              final uri = '${w['uri'] ?? ''}'.trim();
              var host = AiSources.normDomain(title);
              if (host.isEmpty) host = _hostOfAny(uri);
              if (host.endsWith('vertexaisearch.cloud.google.com')) host = '';
              if (seen.add('$host|$uri')) sources.add(AiSource(title: title, url: uri, host: host));
            }
          }
        }
        return AiCompletion(text,
            inTokens: _int(u is Map ? u['promptTokenCount'] : null),
            outTokens: _int(u is Map ? u['candidatesTokenCount'] : null),
            sources: sources,
            queries: queries,
            searched: sources.isNotEmpty || queries.isNotEmpty);
      case AiProviderId.anthropic:
        final cs = j['content'];
        final sb = StringBuffer();
        final sources = <AiSource>[];
        final queries = <String>[];
        final seen = <String>{};
        var searchErr = '';
        var searched = false;
        if (cs is List) {
          for (final x in cs) {
            if (x is! Map) continue;
            final t = x['type'];
            if (t == 'text' && x['text'] is String) {
              sb.write(x['text']);
              final cit = x['citations'];
              if (cit is List) {
                for (final e in cit) {
                  if (e is Map && e['url'] != null && seen.add('${e['url']}')) {
                    sources.add(AiSource(title: '${e['title'] ?? ''}', url: '${e['url']}', host: _hostOfAny('${e['url']}')));
                  }
                }
              }
            } else if (t == 'server_tool_use') {
              searched = true;
              final inp = x['input'];
              if (inp is Map && inp['query'] != null) queries.add('${inp['query']}');
            } else if (t == 'web_search_tool_result') {
              sb.clear(); // text before a search is only "I will search ..."; the answer follows the last result
              final cont = x['content'];
              if (cont is List) {
                for (final e in cont) {
                  if (e is Map && e['url'] != null && seen.add('${e['url']}')) {
                    sources.add(AiSource(title: '${e['title'] ?? ''}', url: '${e['url']}', host: _hostOfAny('${e['url']}')));
                  }
                }
              } else if (cont is Map && cont['error_code'] != null) {
                searchErr = '${cont['error_code']}';
              }
            }
          }
        }
        final text = sb.toString();
        final stop = '${j['stop_reason'] ?? ''}';
        if (text.trim().isEmpty && stop != 'pause_turn') {
          throw AiFail(stop == 'refusal' ? AiErrKind.blocked : AiErrKind.empty, detail: 'stop $stop');
        }
        final u = j['usage'];
        return AiCompletion(text,
            inTokens: _int(u is Map ? u['input_tokens'] : null),
            outTokens: _int(u is Map ? u['output_tokens'] : null),
            sources: sources,
            queries: queries,
            searched: searched,
            searchError: searchErr,
            paused: stop == 'pause_turn',
            rawContent: cs is List ? [for (final e in cs) if (e is Map) Map<String, dynamic>.from(e)] : const []);
      case AiProviderId.openai:
        if (responses) {
          final out = j['output'];
          final sb = StringBuffer();
          final sources = <AiSource>[];
          final queries = <String>[];
          final seen = <String>{};
          var searched = false;
          if (out is List) {
            for (final it in out) {
              if (it is! Map) continue;
              if (it['type'] == 'web_search_call') {
                searched = true;
                final a = it['action'];
                if (a is Map && a['queries'] is List) queries.addAll([for (final e in a['queries'] as List) '$e']);
                if (a is Map && a['query'] != null) queries.add('${a['query']}');
              } else if (it['type'] == 'message' && it['content'] is List) {
                for (final c in it['content'] as List) {
                  if (c is! Map) continue;
                  if (c['text'] is String) sb.write(c['text']);
                  final an = c['annotations'];
                  if (an is List) {
                    for (final e in an) {
                      if (e is Map && e['type'] == 'url_citation' && e['url'] != null && seen.add('${e['url']}')) {
                        sources.add(AiSource(title: '${e['title'] ?? ''}', url: '${e['url']}', host: _hostOfAny('${e['url']}')));
                      }
                    }
                  }
                }
              }
            }
          }
          final text = sb.toString();
          if (text.trim().isEmpty) throw const AiFail(AiErrKind.empty, detail: 'no output text');
          final u = j['usage'];
          return AiCompletion(text,
              inTokens: _int(u is Map ? u['input_tokens'] : null),
              outTokens: _int(u is Map ? u['output_tokens'] : null),
              sources: sources,
              queries: queries,
              searched: searched);
        }
        final ch = j['choices'];
        String text = '';
        if (ch is List && ch.isNotEmpty && ch.first is Map) {
          final m = (ch.first as Map)['message'];
          if (m is Map && m['content'] is String) text = m['content'] as String;
        }
        if (text.trim().isEmpty) throw const AiFail(AiErrKind.empty, detail: 'no content');
        final u = j['usage'];
        return AiCompletion(text, inTokens: _int(u is Map ? u['prompt_tokens'] : null), outTokens: _int(u is Map ? u['completion_tokens'] : null));
    }
  }

  static int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

  static Map<String, dynamic> _decode(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return <String, dynamic>{};
  }

  // ---- model lists

  static AiHttpRequest buildModels(AiProviderId p, String key, {String openaiBase = '', String? pageToken}) {
    final base = _base(p, openaiBase);
    switch (p) {
      case AiProviderId.gemini:
        return AiHttpRequest('GET', _join(base, '/v1beta/models', {'pageSize': '200', if (pageToken != null) 'pageToken': pageToken}), {'x-goog-api-key': key});
      case AiProviderId.anthropic:
        return AiHttpRequest('GET', _join(base, '/v1/models', {'limit': '100'}), {'x-api-key': key, 'anthropic-version': '2023-06-01'});
      case AiProviderId.openai:
        return AiHttpRequest('GET', _join(base, '/models'), {'authorization': 'Bearer $key'});
    }
  }

  /// Returns the models and (Gemini) the next page token.
  static (List<AiModel>, String?) parseModels(AiProviderId p, AiHttpResponse r, {String openaiBase = ''}) {
    final j = _decode(r.body);
    final out = <AiModel>[];
    switch (p) {
      case AiProviderId.gemini:
        final l = j['models'];
        if (l is List) {
          for (final m in l) {
            if (m is! Map) continue;
            final methods = m['supportedGenerationMethods'];
            if (methods is List && !methods.contains('generateContent')) continue;
            final id = m['name'].toString().replaceFirst('models/', '');
            final low = id.toLowerCase();
            if (!(low.contains('gemini') || low.contains('gemma'))) continue;
            if (['embedding', 'tts', 'image', 'live', 'audio', 'robotics', 'computer-use', 'native-audio', 'aqa'].any(low.contains)) continue;
            out.add(AiModel(id, (m['displayName'] ?? id).toString()));
          }
        }
        return (out, j['nextPageToken']?.toString());
      case AiProviderId.anthropic:
        final l = j['data'];
        if (l is List) {
          for (final m in l) {
            if (m is Map && m['id'] != null) out.add(AiModel(m['id'].toString(), (m['display_name'] ?? m['id']).toString()));
          }
        }
        return (out, null);
      case AiProviderId.openai:
        final l = j['data'];
        final official = _isOpenAiHost(safeBase(openaiBase.isEmpty ? openaiDefaultBase : openaiBase) ?? Uri.parse(openaiDefaultBase));
        if (l is List) {
          for (final m in l) {
            if (m is! Map || m['id'] == null) continue;
            final id = m['id'].toString();
            final low = id.toLowerCase();
            if (official &&
                (['whisper', 'tts', 'embedding', 'dall-e', 'moderation', 'davinci', 'babbage', 'image', 'audio', 'realtime', 'transcribe', 'search', 'codex', 'instruct'].any(low.contains) ||
                    !(low.startsWith('gpt') || RegExp(r'^o\d').hasMatch(low)))) {
              continue;
            }
            out.add(AiModel(id));
          }
        }
        return (out, null);
    }
  }

  static int _natural(String a, String b) {
    final ra = RegExp(r'\d+|\D+').allMatches(a).map((m) => m.group(0)!).toList();
    final rb = RegExp(r'\d+|\D+').allMatches(b).map((m) => m.group(0)!).toList();
    for (var i = 0; i < ra.length && i < rb.length; i++) {
      final x = ra[i], y = rb[i];
      final nx = int.tryParse(x), ny = int.tryParse(y);
      final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
      if (c != 0) return c;
    }
    return ra.length.compareTo(rb.length);
  }

  /// A cheap, fast default chosen by name pattern (never a hard-coded model name); the user can override it.
  static String pickDefault(AiProviderId p, List<AiModel> models) {
    if (models.isEmpty) return '';
    final ids = [for (final m in models) m.id];
    final prefs = p == AiProviderId.gemini
        ? ['flash-lite', 'flash']
        : p == AiProviderId.anthropic
            ? ['haiku', 'sonnet']
            : ['nano', 'mini', 'flash', 'instant', 'small', 'haiku'];
    bool stable(String id) => !RegExp(r'preview|exp|beta|thinking|-\d{3,}$|latest').hasMatch(id);
    for (final pat in prefs) {
      final hit = ids.where((i) => i.toLowerCase().contains(pat)).toList();
      if (hit.isEmpty) continue;
      final st = hit.where(stable).toList();
      final pool = st.isEmpty ? hit : st;
      pool.sort((a, b) => _natural(b, a));
      // 'mini' beats 'nano' for answer quality at similar cost: only prefer nano if no mini exists
      if (p == AiProviderId.openai && pat == 'nano') {
        final mini = ids.where((i) => i.toLowerCase().contains('mini')).toList();
        if (mini.isNotEmpty) continue;
      }
      return pool.first;
    }
    final s = [...ids]..sort((a, b) => _natural(b, a));
    return s.first;
  }

  // ---- errors

  static AiFail classify(int status, String body, String key) {
    var msg = '';
    final j = _decode(body);
    final e = j['error'];
    if (e is Map && e['message'] != null) {
      msg = e['message'].toString();
    } else if (e is String) {
      msg = e;
    }
    if (key.isNotEmpty) msg = msg.replaceAll(key, '***');
    if (msg.length > 200) msg = msg.substring(0, 200);
    final low = '${msg.toLowerCase()} ${body.toLowerCase()}';
    final detail = 'HTTP $status $msg';
    if (status == 401 || status == 403 || low.contains('api_key_invalid') || low.contains('api key not valid') || low.contains('invalid x-api-key') || low.contains('invalid api key')) {
      return AiFail(AiErrKind.auth, status: status, detail: detail);
    }
    if (status == 429) {
      final daily = low.contains('perday') || low.contains('per day') || low.contains('daily') || low.contains('insufficient_quota') || low.contains('billing');
      return AiFail(daily ? AiErrKind.quota : AiErrKind.rate, status: status, detail: detail);
    }
    if (status == 404) return AiFail(AiErrKind.notFound, status: status, detail: detail);
    if (status >= 500) return AiFail(AiErrKind.server, status: status, detail: detail);
    if (status == 400 || status == 422) return AiFail(AiErrKind.badRequest, status: status, detail: detail);
    return AiFail(AiErrKind.other, status: status, detail: detail);
  }

  /// Sends [mk()] through [AiTransport.send] with backoff on 429/5xx/network errors. Throws [AiFail].
  static Future<AiHttpResponse> sendWithRetry(AiHttpRequest Function() mk, String key, {int retries = 2}) async {
    var attempt = 0;
    while (true) {
      AiHttpResponse? r;
      AiFail? fail;
      try {
        r = await AiTransport.send(mk());
      } on TimeoutException {
        fail = const AiFail(AiErrKind.timeout, detail: 'timeout');
      } on SocketException catch (e) {
        fail = AiFail(AiErrKind.network, detail: e.message);
      } on HandshakeException {
        fail = const AiFail(AiErrKind.network, detail: 'tls');
      } on HttpException catch (e) {
        fail = AiFail(AiErrKind.network, detail: e.message);
      }
      if (r != null && r.status >= 200 && r.status < 300) return r;
      if (r != null) fail = classify(r.status, r.body, key);
      final f = fail!;
      final retryable = (f.kind == AiErrKind.rate || f.kind == AiErrKind.server || f.kind == AiErrKind.network || f.kind == AiErrKind.timeout);
      if (!retryable || attempt >= retries) throw f;
      // a dead or very slow connection will not recover within seconds: one retry is enough
      if ((f.kind == AiErrKind.timeout || f.kind == AiErrKind.network) && attempt >= 1) throw f;
      var secs = 1.0 + attempt * 2.0;
      final ra = double.tryParse(r?.headers['retry-after'] ?? '');
      if (ra != null) secs = ra.clamp(0.5, 10.0);
      attempt++;
      final ms = (secs * 1000 * AiTransport.backoffScale).round();
      if (ms > 0) await Future<void>.delayed(Duration(milliseconds: ms));
    }
  }

  /// Parses a JSON object out of model text, tolerating code fences and surrounding prose.
  static Map<String, dynamic>? parseJsonText(String text) {
    var t = text.trim();
    t = t.replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '').replaceAll(RegExp(r'\s*```$'), '').trim();
    dynamic v;
    try {
      v = jsonDecode(t);
    } catch (_) {
      final a = t.indexOf('{'), b = t.lastIndexOf('}');
      if (a >= 0 && b > a) {
        try {
          v = jsonDecode(t.substring(a, b + 1));
        } catch (_) {}
      }
    }
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }
}
