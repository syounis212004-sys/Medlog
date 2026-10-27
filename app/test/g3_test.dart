import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/ai/ai_api.dart';
import 'package:medlog/ai/ai_chat.dart';
import 'package:medlog/ai/ai_context.dart';
import 'package:medlog/ai/ai_doc_api.dart';
import 'package:medlog/ai/ai_engine.dart';
import 'package:medlog/ai/ai_fab.dart';
import 'package:medlog/ai/ai_library.dart';
import 'package:medlog/ai/ai_prefs.dart';
import 'package:medlog/ai/ai_prompts.dart';
import 'package:medlog/ai/ai_providers.dart';
import 'package:medlog/ai/ai_sources.dart';
import 'package:medlog/ai/ai_store.dart';
import 'package:medlog/data.dart';
import 'package:medlog/i18n.dart' show setLangSetting, appLocale;
import 'package:medlog/library.dart';
import 'package:medlog/main.dart';
import 'package:medlog/screens_ai_chat.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _PP extends PathProviderPlatform {
  final String dir;
  _PP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

final GlobalKey shotKey = GlobalKey();

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
  }
  await l.load();
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final b = shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('test_output/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> settle(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpReal(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> initStore(String lang, {double scale = 1.0}) async {
  final dir = Directory.systemTemp.createTempSync('g3s').path;
  PathProviderPlatform.instance = _PP(dir);
  Directory('$dir/medlog/cases').createSync(recursive: true);
  Directory('$dir/medlog/images').createSync(recursive: true);
  File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({'lang': lang, 'author': 'Dr. M', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String(), 'libOnline': false, if (scale != 1.0) 'textScale': scale}));
  await store.init();
}

AiHttpResponse ok(Map<String, dynamic> j) => AiHttpResponse(200, jsonEncode(j));

const kDoc = '{"title":"Hip fracture","sections":['
    '{"kind":"overview","title":"Overview","text":"Hip fracture is a common emergency in older adults [1].","bullets":[],"steps":[],"table":[],"cites":[]},'
    '{"kind":"differential","title":"Differential","text":"","bullets":["Femoral neck fracture: most common","Pubic ramus fracture"],"steps":[],"table":[],"cites":[]},'
    '{"kind":"management","title":"Management","text":"","bullets":["Analgesia and early surgery within 36 hours [1]"],"steps":[],"table":[],"cites":[]}],'
    '"citations":[{"label":"NICE CG124 (2023)","org":"NICE","year":"2023","url":"https://www.nice.org.uk/guidance/cg124"},'
    '{"label":"Fake guide (2024)","org":"Fake","year":"2024","url":"https://cdc.gov.evil.com/x"}],"uncertainties":[],"disclaimer":""}';

Map<String, dynamic> geminiGrounded(String text) => {
      'candidates': [
        {
          'content': {'parts': [{'text': text}], 'role': 'model'},
          'groundingMetadata': {
            'webSearchQueries': ['hip fracture guideline', 'NICE hip fracture'],
            'searchEntryPoint': {'renderedContent': '<div/>'},
            'groundingChunks': [
              {'web': {'uri': 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/AAA', 'title': 'nice.org.uk'}},
              {'web': {'uri': 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/BBB', 'title': 'random-blog.example'}},
            ],
            'groundingSupports': [
              {'segment': {'startIndex': 0, 'endIndex': 40, 'text': 'Hip fracture'}, 'groundingChunkIndices': [0, 1]}
            ],
          }
        }
      ],
      'usageMetadata': {'promptTokenCount': 10, 'candidatesTokenCount': 20},
    };

void cfg(AiProviderId p, {String openaiBase = ''}) {
  AiStore.memoryOnly = true;
  AiStore.resetForTests();
  AiStore.loaded = true;
  AiStore.master = true;
  AiStore.provider = p;
  AiStore.models[p.name] = 'm1';
  if (openaiBase.isNotEmpty) AiStore.openaiBase = openaiBase;
  AiStore.setKey(p, 'KEY-1');
  AiEngine.fake = null;
  AiEngine.debugOnline = true;
  AiEngine.online.value = true;
  AiEngine.resetRate();
  AiTransport.backoffScale = 0;
}

Map<String, dynamic> bodyOf(AiHttpRequest r) => jsonDecode(r.body!) as Map<String, dynamic>;

void main() {
  setUpAll(() async {
    final rb = '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts';
    await loadFont('MaterialIcons', ['$rb/MaterialIcons-Regular.otf']);
    const fd = 'assets/fonts';
    await loadFont('Cairo', ['$fd/Cairo_400Regular.ttf', '$fd/Cairo_500Medium.ttf', '$fd/Cairo_700Bold.ttf', '$fd/Cairo_800ExtraBold.ttf']);
    await loadFont('Tinos', ['$fd/Tinos_400Regular.ttf', '$fd/Tinos_700Bold.ttf']);
    await loadFont('Tajawal', ['$fd/Tajawal_400Regular.ttf', '$fd/Tajawal_500Medium.ttf', '$fd/Tajawal_700Bold.ttf']);
    await loadFont('Roboto', ['$rb/Roboto-Regular.ttf', '$rb/Roboto-Medium.ttf', '$rb/Roboto-Bold.ttf']);
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  group('logic', () {
    setUpAll(() async {
      await initStore('en');
    });
    setUp(() {
      setLangSetting('en');
      AiPrefs.answerLang = 'en';
      AiPrefs.answerLength = 'standard';
      AiPrefs.sourceMode = 'web';
      AiPrefs.providerSearch = true;
      AiPrefs.dailyCap = 60;
      AiPrefs.region = '';
      AiPrefs.customDomains = [];
      AiPrefs.domains = [];
    });
    tearDown(() {
      uninstallFakeAi();
      AiTransport.send = (r) async => throw StateError('no network in tests');
    });

    // ------------------------------------------------------------ language policy
    test('language policy: English by default, mixed, ar; never a refusal path', () {
      expect(AiPrefs.answerLang, 'en');
      for (final l in ['en', 'mixed', 'ar']) {
        final sys = AiPrompts.ask(lang: l);
        expect(sys.toLowerCase().contains('never refuse'), true, reason: l);
        expect(sys.contains('LANGUAGE:'), true);
        final all = [
          sys,
          AiPrompts.deepDive('Hip fracture', lang: l),
          AiPrompts.explain(lang: l),
          AiPrompts.compare('A', 'B', lang: l),
          AiPrompts.guidelineCheck('sepsis', lang: l),
          AiPrompts.summarise(lang: l),
          AiPrompts.translate(lang: l),
          AiPrompts.viva('asthma', lang: l),
          AiPrompts.coach(lang: l),
          AiPrompts.base(task: 'x', lang: l),
        ];
        for (final s in all) {
          expect(s.contains('LANGUAGE:'), true);
          expect(RegExp(r'cannot answer in Arabic|can.t answer in Arabic', caseSensitive: false).hasMatch(s), false);
        }
      }
      expect(AiPrompts.languageRule('en').contains('English'), true);
      expect(AiPrompts.languageRule('mixed').contains('English terms dominate'), true);
      expect(AiPrompts.languageRule('ar').contains('Arabic'), true);
      // translation default direction: Arabic explanation WITH English terms
      expect(AiPrompts.translate().contains('Arabic explanation WITH the English medical terms'), true);
    });

    test('library ask prompt: language never blocks the answer, all 3 languages', () {
      final ps = [const Passage(1, 'p', 0, 'DKA', 'WikEM', 'Mgmt', 'Give fluids then insulin.')];
      for (final l in ['en', 'mixed', 'ar']) {
        AiPrefs.answerLang = l;
        final r = AiLibrary.askRequest('How is DKA managed?', ps);
        expect(r.system.contains('never refuse because of language'), true);
        expect(r.system.contains('NOT adding facts'), true);
        expect(r.prompt.contains('LANGUAGE:'), true);
        expect(r.prompt.contains(l == 'en' ? 'English' : 'Arabic'), true);
      }
    });

    test('deep-dive prompt: persona, sections, guideline table, doses rule, injection fence, region, length', () {
      AiPrefs.region = 'Jordan / Middle East';
      AiPrefs.answerLength = 'brief';
      final s = AiPrompts.deepDive('Sepsis');
      for (final k in ['intern doctor', 'epidemiology', 'pathophysiology', 'first hour', 'escalate', 'red_flags', 'dont_miss', 'complications', 'prognosis', 'disposition', 'Organisation', 'Year', 'Jordan / Middle East', 'untrusted DATA', 'name with its year', 'LENGTH: full']) {
        expect(s.contains(k), true, reason: k);
      }
      expect(AiPrompts.ask().contains('LENGTH: brief'), true);
      expect(AiPrompts.maxTokens(deepDive: true) > AiPrompts.maxTokens(length: 'full'), true);
      expect(AiPrompts.maxTokens(length: 'brief') < AiPrompts.maxTokens(length: 'standard'), true);
      // source rules per mode
      expect(AiPrompts.ask(mode: 'model').contains('may be outdated'), true);
      expect(AiPrompts.ask(mode: 'library').contains('NOT adding facts'), true);
      expect(AiPrompts.ask(mode: 'web').contains('https URL'), true);
    });

    // ------------------------------------------------------------ allow-list verification
    test('citation host verification: allowed / non-allowed / look-alikes', () {
      AiCite c(String u) => AiCite(label: 'x', url: u);
      final r = AiSources.verify([
        c('https://www.cdc.gov/stroke/'),
        c('https://cdc.gov.evil.com/x'),
        c('https://evilcdc.gov/x'),
        c('https://cdc.gov@evil.com/x'),
        c('https://evil.com/cdc.gov'),
        c('http://www.cdc.gov/x'),
        c('https://pubmed.ncbi.nlm.nih.gov/123/'),
        c('https://CDC.GOV./x'),
        c('not a url'),
        c(''),
        c('https://who.int:8443/x'),
        c('javascript:alert(1)'),
        c('https://random-blog.example/hip'),
      ]);
      final st = [for (final i in r.items) i.status];
      expect(st, [
        CiteStatus.verified,
        CiteStatus.notAllowed,
        CiteStatus.notAllowed,
        CiteStatus.notAllowed,
        CiteStatus.notAllowed,
        CiteStatus.noLink, // http is not https
        CiteStatus.verified,
        CiteStatus.verified,
        CiteStatus.noLink,
        CiteStatus.noLink,
        CiteStatus.verified,
        CiteStatus.noLink,
        CiteStatus.notAllowed,
      ]);
      // seen hosts: allowed host that the search did not return is only unconfirmed
      final r2 = AiSources.verify([c('https://www.nice.org.uk/guidance/ng51'), c('https://www.who.int/x')], seenHosts: ['nice.org.uk']);
      expect(r2.items[0].status, CiteStatus.verified);
      expect(r2.items[1].status, CiteStatus.unconfirmed);
      expect(verify([c('https://cdc.gov/x')]).allVerified, true);
      // custom list: user's own domains
      AiPrefs.customDomains = ['https://www.MyHospital.org/guidelines', 'bad domain'];
      expect(AiSources.allowedFor('custom'), ['myhospital.org']);
      expect(AiSources.allowedFor('web').contains('cdc.gov'), true);
      expect(AiSources.allowedFor('library'), isEmpty);
      expect(AiSources.allowedFor('model'), isEmpty);
      expect(AiSources.verify([c('https://a.myhospital.org/x'), c('https://cdc.gov/x')], allow: AiSources.allowedFor('custom')).items.map((e) => e.status).toList(), [CiteStatus.verified, CiteStatus.notAllowed]);
    });

    // ------------------------------------------------------------ request shapes + grounding metadata
    test('Gemini: google_search tool, no JSON mime with the tool; grounding metadata parsed', () {
      final withTool = AiProviders.buildChat(
          p: AiProviderId.gemini, key: 'k', model: 'gemini-x', system: 's', prompt: 'p', json: true, maxTokens: 500,
          search: const AiSearchSpec(domains: ['cdc.gov']), history: const [AiTurn('user', 'q1'), AiTurn('assistant', 'a1')]);
      final b = bodyOf(withTool);
      expect(b['tools'], [{'google_search': {}}]);
      expect((b['generationConfig'] as Map).containsKey('responseMimeType'), false);
      expect((b['contents'] as List).map((e) => e['role']).toList(), ['user', 'model', 'user']);
      expect(withTool.url.path.endsWith(':generateContent'), true);
      final noTool = bodyOf(AiProviders.buildChat(p: AiProviderId.gemini, key: 'k', model: 'gemini-x', system: 's', prompt: 'p', json: true, maxTokens: 500, schema: aiDocJsonSchema));
      expect(noTool.containsKey('tools'), false);
      expect((noTool['generationConfig'] as Map)['responseMimeType'], 'application/json');
      expect((noTool['generationConfig'] as Map)['responseSchema'], isNotNull);

      final c = AiProviders.parseChat(AiProviderId.gemini, ok(geminiGrounded('Hello')));
      expect(c.searched, true);
      expect(c.queries, ['hip fracture guideline', 'NICE hip fracture']);
      expect(c.sources.map((s) => s.host).toList(), ['nice.org.uk', 'random-blog.example']);
      expect(c.sources.first.url.contains('vertexaisearch'), true); // redirect uri is never used as a host
    });

    test('Claude: web_search tool with allowed_domains and max_uses; citations parsed; pause_turn', () {
      final r = AiProviders.buildChat(
          p: AiProviderId.anthropic, key: 'k', model: 'claude-x', system: 's', prompt: 'p', json: false, maxTokens: 800,
          search: const AiSearchSpec(domains: ['https://www.NICE.org.uk/x', 'cdc.gov'], maxUses: 3));
      final t = (bodyOf(r)['tools'] as List).first as Map;
      expect(t['type'], 'web_search_20250305');
      expect(t['name'], 'web_search');
      expect(t['max_uses'], 3);
      expect(t['allowed_domains'], ['nice.org.uk', 'cdc.gov']);
      expect(t.containsKey('blocked_domains'), false);

      final resp = ok({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': "I'll search for that."},
          {'type': 'server_tool_use', 'id': 's1', 'name': 'web_search', 'input': {'query': 'hip fracture nice'}},
          {
            'type': 'web_search_tool_result',
            'tool_use_id': 's1',
            'content': [
              {'type': 'web_search_result', 'url': 'https://www.nice.org.uk/guidance/cg124', 'title': 'NICE CG124', 'encrypted_content': 'x'}
            ]
          },
          {
            'type': 'text',
            'text': 'Surgery within 36 hours.',
            'citations': [
              {'type': 'web_search_result_location', 'url': 'https://www.nice.org.uk/guidance/cg124', 'title': 'NICE CG124', 'cited_text': '...', 'encrypted_index': 'e'}
            ]
          },
        ],
        'usage': {'input_tokens': 5, 'output_tokens': 9},
      });
      final c = AiProviders.parseChat(AiProviderId.anthropic, resp);
      expect(c.text, 'Surgery within 36 hours.'); // the "I'll search" preface is dropped
      expect(c.searched, true);
      expect(c.queries, ['hip fracture nice']);
      expect(c.sources.length, 1);
      expect(c.sources.first.host, 'nice.org.uk');
      final paused = AiProviders.parseChat(AiProviderId.anthropic, ok({'stop_reason': 'pause_turn', 'content': [{'type': 'text', 'text': 'Working'}]}));
      expect(paused.paused, true);
      final err = AiProviders.parseChat(AiProviderId.anthropic, ok({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'web_search_tool_result', 'tool_use_id': 's1', 'content': {'type': 'web_search_tool_result_error', 'error_code': 'max_uses_exceeded'}},
          {'type': 'text', 'text': 'Answer'},
        ]
      }));
      expect(err.searchError, 'max_uses_exceeded');
    });

    test('OpenAI: Responses API web_search with allowed_domains (official host only); annotations parsed', () {
      final r = AiProviders.buildChat(p: AiProviderId.openai, key: 'k', model: 'gpt-x', system: 's', prompt: 'p', json: false, maxTokens: 500, search: const AiSearchSpec(domains: ['cdc.gov', 'who.int']));
      expect(r.url.path.endsWith('/responses'), true);
      final b = bodyOf(r);
      expect(b['tools'], [
        {'type': 'web_search', 'filters': {'allowed_domains': ['cdc.gov', 'who.int']}}
      ]);
      expect(AiProviders.supportsSearch(AiProviderId.openai, 'https://openrouter.ai/api/v1'), false);
      expect(AiProviders.supportsSearch(AiProviderId.openai, 'https://api.openai.com/v1'), true);
      expect(AiProviders.supportsSearch(AiProviderId.gemini, ''), true);
      // another base never gets the Responses call
      final other = AiProviders.buildChat(p: AiProviderId.openai, key: 'k', model: 'x', system: 's', prompt: 'p', json: false, maxTokens: 500, openaiBase: 'https://openrouter.ai/api/v1', search: const AiSearchSpec());
      expect(other.url.path.endsWith('/chat/completions'), true);
      final c = AiProviders.parseChat(
          AiProviderId.openai,
          ok({
            'output': [
              {'type': 'web_search_call', 'id': 'w1', 'status': 'completed', 'action': {'type': 'search', 'queries': ['sepsis surviving']}},
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'Give antibiotics within 1 hour.',
                    'annotations': [
                      {'type': 'url_citation', 'url': 'https://www.sccm.org/survivingsepsiscampaign', 'title': 'SSC', 'start_index': 0, 'end_index': 5}
                    ]
                  }
                ]
              }
            ],
            'usage': {'input_tokens': 3, 'output_tokens': 4}
          }),
          responses: true);
      expect(c.text, 'Give antibiotics within 1 hour.');
      expect(c.searched, true);
      expect(c.sources.single.host, 'sccm.org');
      expect(c.queries, ['sepsis surviving']);
    });

    // ------------------------------------------------------------ engine: routing and fallbacks
    AiRequest webReq({String mode = 'web'}) => AiRequest(feature: 'ask_chat', system: 'sys', prompt: 'Hip fracture?', expectJson: true, search: AiSearchSpec(mode: mode, domains: AiSources.allowedFor(mode)));

    test('web mode on Gemini sends the tool; result carries sources; second call also; cap respected', () async {
      cfg(AiProviderId.gemini);
      final seen = <AiHttpRequest>[];
      AiTransport.send = (r) async {
        seen.add(r);
        return ok(geminiGrounded(kDoc));
      };
      final r = await Ai.run(webReq());
      expect(r.ok, true);
      expect(r.searched, true);
      expect(r.searchNote, '');
      expect(r.sources.length, 2);
      expect(r.json, isNotNull); // tolerant JSON parse even without the mime type
      expect(bodyOf(seen.single)['tools'], isNotNull);
      // the prompt text carries the question only (level none): no key in the body
      expect(seen.single.body!.contains('KEY-1'), false);

      // daily cap
      AiPrefs.dailyCap = 1;
      final r2 = await Ai.run(webReq());
      expect(r2.ok, false);
      expect(r2.error!.contains('limit'), true);
      expect(seen.length, 1);
    });

    test('Gemini refuses the tool (400): answered without it, banner note, and no tool on the next call', () async {
      cfg(AiProviderId.gemini);
      final seen = <AiHttpRequest>[];
      AiTransport.send = (r) async {
        seen.add(r);
        if (bodyOf(r).containsKey('tools')) return const AiHttpResponse(400, '{"error":{"message":"Tool use with a response mime type is unsupported"}}');
        return ok({'candidates': [{'content': {'parts': [{'text': kDoc}]}}]});
      };
      final r = await Ai.run(webReq());
      expect(r.ok, true);
      expect(r.searched, false);
      expect(r.searchNote, 'searchfail');
      expect(seen.length, 2);
      expect(bodyOf(seen.last).containsKey('tools'), false);
      expect(AiEngine.searchBlockedNote(), 'searchfail');
      final r2 = await Ai.run(webReq());
      expect(r2.ok, true);
      expect(seen.length, 3); // no new failed attempt
      expect(bodyOf(seen.last).containsKey('tools'), false);
      expect(r2.searchNote, 'searchfail');
    });

    test('grounding quota (429 per day) -> searchquota; the retry without the tool works', () async {
      cfg(AiProviderId.gemini);
      var n = 0;
      AiTransport.send = (r) async {
        n++;
        if (bodyOf(r).containsKey('tools')) return const AiHttpResponse(429, '{"error":{"status":"RESOURCE_EXHAUSTED","message":"Quota exceeded for ... per day"}}');
        return ok({'candidates': [{'content': {'parts': [{'text': 'plain'}]}}]});
      };
      final r = await Ai.run(webReq());
      expect(r.ok, true);
      expect(r.searchNote, 'searchquota');
      expect(AiEngine.searchBlockedNote(), 'searchquota');
    });

    test('OpenAI-compatible base without search -> no tool, note nosearch; settings switch off -> note off', () async {
      cfg(AiProviderId.openai, openaiBase: 'https://openrouter.ai/api/v1');
      final seen = <AiHttpRequest>[];
      AiTransport.send = (r) async {
        seen.add(r);
        return ok({'choices': [{'message': {'content': 'hi'}}]});
      };
      final r = await Ai.run(webReq());
      expect(r.ok, true);
      expect(r.searchNote, 'nosearch');
      expect(seen.single.url.path.endsWith('/chat/completions'), true);
      expect(AiEngine.searchBlockedNote(), 'nosearch');
      cfg(AiProviderId.gemini);
      AiPrefs.providerSearch = false;
      AiTransport.send = (r) async {
        seen.add(r);
        return ok({'candidates': [{'content': {'parts': [{'text': 'x'}]}}]});
      };
      final r2 = await Ai.run(webReq());
      expect(r2.searchNote, 'off');
      expect(bodyOf(seen.last).containsKey('tools'), false);
    });

    test('Claude pause_turn loop continues and returns the final text', () async {
      cfg(AiProviderId.anthropic);
      var n = 0;
      final bodies = <Map<String, dynamic>>[];
      AiTransport.send = (r) async {
        bodies.add(bodyOf(r));
        n++;
        if (n == 1) {
          return ok({'stop_reason': 'pause_turn', 'content': [{'type': 'server_tool_use', 'id': 's', 'name': 'web_search', 'input': {'query': 'q'}}]});
        }
        return ok({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': 'Final answer', 'citations': [{'type': 'web_search_result_location', 'url': 'https://www.cdc.gov/a', 'title': 'CDC'}]}
          ]
        });
      };
      final r = await Ai.run(webReq());
      expect(r.ok, true);
      expect(r.text, 'Final answer');
      expect(n, 2);
      final msgs = bodies.last['messages'] as List;
      expect(msgs.last['role'], 'assistant'); // the paused turn is sent back
      expect(r.searched, true);
    });

    test('model / library modes send no tool (no spec); history is sent as turns and scrubbed', () async {
      cfg(AiProviderId.gemini);
      final seen = <AiHttpRequest>[];
      AiTransport.send = (r) async {
        seen.add(r);
        return ok({'candidates': [{'content': {'parts': [{'text': 'ok'}]}}]});
      };
      final r = await Ai.run(AiRequest(feature: 'ask_chat', system: 's', prompt: 'follow up', history: const [AiTurn('user', 'My patient phone 0791234567'), AiTurn('assistant', 'Earlier answer')]));
      expect(r.ok, true);
      final b = bodyOf(seen.single);
      expect(b.containsKey('tools'), false);
      expect((b['contents'] as List).length, 3);
      expect(seen.single.body!.contains('0791234567'), false);
    });

    // ------------------------------------------------------------ chat storage, chips, quick actions
    test('chat persistence: save, reload, last 50 only', () async {
      final t = AiChatThread.create();
      t.msgs.add(const AiChatMsg('user', 'What is DKA?', mode: 'web'));
      t.msgs.add(AiChatMsg('assistant', kDoc, mode: 'web', searched: true, sources: const [AiSource(title: 'nice.org.uk', url: 'u', host: 'nice.org.uk')], queries: const ['q']));
      await AiChats.save(t);
      final back = AiChats.byId(t.id)!;
      expect(back.title, 'What is DKA?');
      expect(back.msgs.length, 2);
      expect(back.msgs.last.searched, true);
      expect(back.msgs.last.sources.single.host, 'nice.org.uk');
      for (var i = 0; i < 55; i++) {
        final x = AiChatThread.create();
        x.msgs.add(AiChatMsg('user', 'Q$i'));
        await AiChats.save(x);
      }
      expect(AiChats.all().length, 50);
      expect(AiChats.all().first.title, 'Q54');
    });

    test('context chips and quick actions per screen kind', () {
      String l(AiScreenContext c) => chipsFor(c).map((e) => e.label).join('|');
      expect(l(const AiScreenContext(kind: 'article', title: 'Greater trochanter')), 'This article: Greater trochanter');
      expect(l(const AiScreenContext(kind: 'case', title: 'x')), 'This case');
      expect(l(const AiScreenContext(kind: 'quiz')), 'Quiz question');
      expect(l(const AiScreenContext(kind: 'calc', title: 'eGFR')), 'Calculator: eGFR');
      expect(l(const AiScreenContext(kind: 'search', title: 'hip pain')), 'Library search: hip pain');
      expect(l(const AiScreenContext(kind: 'home')), '');
      expect(chipsFor(null), isEmpty);
      List<String> q(String k) => quickActionsFor(k).map((e) => e.id).toList();
      expect(q('article'), ['deepdive', 'simple', 'compare', 'guidelines', 'questions', 'anything']);
      expect(q('case'), ['discuss', 'ddx', 'senior', 'anything']);
      expect(q('quiz'), ['explain_q', 'anything']);
      expect(q('calc'), ['which_score', 'interpret', 'anything']);
      expect(q('search'), ['deepdive', 'anything']);
      expect(q('library'), ['deepdive', 'anything']);
      expect(q('home'), ['brief', 'anything']);
      expect(q('other'), ['anything']);
    });

    test('FAB visibility rules', () {
      bool v({bool ai = true, bool fab = true, String kind = 'home', bool hidden = false, bool covered = false, bool page = true, bool kb = false, bool shell = true}) =>
          AiFab.visibleFor(aiEnabled: ai, fabOn: fab, kind: kind, hiddenForSession: hidden, covered: covered, topIsPage: page, keyboardOpen: kb, shellReady: shell);
      expect(v(), true);
      expect(v(ai: false), false); // AI off / no key
      expect(v(fab: false), false); // hidden in settings
      expect(v(hidden: true), false); // hide until restart
      expect(v(covered: true), false); // lock screen / access gate
      expect(v(page: false), false); // dialog or sheet on top
      expect(v(kb: true), false); // keyboard open
      expect(v(shell: false), false); // splash
      AiPrefs.setScreenOn('quiz', false);
      expect(v(kind: 'quiz'), false);
      expect(v(kind: 'article'), false); // reading an article: off by default, the text must not be covered
      AiPrefs.setScreenOn('article', true);
      expect(v(kind: 'article'), true);
      AiPrefs.setScreenOn('article', false);
      AiPrefs.setScreenOn('quiz', true);
      // never over the bottom bar
      final (minY, maxY) = AiFab.yRange(const Size(412, 892), const EdgeInsets.only(top: 24, bottom: 16), 1.0);
      expect(maxY + AiFab.size < 892 - 16 - 80, true);
      expect(minY > 24, true);
      final (_, maxBig) = AiFab.yRange(const Size(360, 640), EdgeInsets.zero, 1.3);
      expect(maxBig + AiFab.size <= 640 - (80 + 0.3 * 44), true);
    });

    // ------------------------------------------------------------ chat runner with the fake AI
    test('chat runner: source modes route correctly; library-only with nothing found makes no call; offline falls back', () async {
      installFakeAi(online: true, answers: {'Hip': kDoc});
      final t = AiChatThread.create();
      // web mode: search spec is attached
      var m = await AiChatRunner.answer(null, t, 'Hip fracture management?', mode: 'web');
      expect(m.failed, false);
      expect(FakeAi.sent.last.search, isNotNull);
      expect(FakeAi.sent.last.search!.domains.contains('nice.org.uk'), true);
      expect(FakeAi.sent.last.system.contains('intern doctor'), true);
      expect(m.searched, true);
      expect(AiChatRunner.bannerFor(m), 'web');
      // model mode
      m = await AiChatRunner.answer(null, t, 'Hip fracture management?', mode: 'model');
      expect(FakeAi.sent.last.search, isNull);
      expect(AiChatRunner.bannerFor(m), 'model');
      // custom: the user's own list
      AiPrefs.customDomains = ['myhospital.org'];
      await AiChatRunner.answer(null, t, 'Hip fracture management?', mode: 'custom');
      expect(FakeAi.sent.last.search!.domains, ['myhospital.org']);
      // library with an empty library: local message, no call
      final before = FakeAi.sent.length;
      m = await AiChatRunner.answer(null, t, 'Hip fracture management?', mode: 'library');
      expect(m.localOnly, true);
      expect(FakeAi.sent.length, before);
      // history is sent back (last turns), failed ones are not
      t.msgs.add(const AiChatMsg('user', 'first question'));
      t.msgs.add(AiChatMsg('assistant', kDoc));
      await AiChatRunner.answer(null, t, 'Hip follow up', mode: 'model');
      expect(FakeAi.sent.last.history.length, 2);
      // offline
      FakeAi.online = false;
      m = await AiChatRunner.answer(null, t, 'Hip fracture management?', mode: 'web');
      expect(m.failed && m.offline, true);
      // provider without search: the web question is answered from library+model and says so
      FakeAi.online = true;
      AiStore.provider = AiProviderId.openai;
      AiStore.openaiBase = 'https://openrouter.ai/api/v1';
      AiStore.models['openai'] = 'x';
      AiStore.setKey(AiProviderId.openai, 'k');
      m = await AiChatRunner.answer(null, t, 'Hip fracture management?', mode: 'web');
      expect(FakeAi.sent.last.search, isNull);
      expect(FakeAi.sent.last.system.contains('General knowledge'), true);
      expect(AiChatRunner.bannerFor(m), 'nosearch');
    });

    test('AI off: nothing is sent, offline result', () async {
      installFakeAi(online: true, enabled: false);
      final m = await AiChatRunner.answer(null, AiChatThread.create(), 'Hip?', mode: 'web');
      expect(m.failed && m.offline, true);
      expect(FakeAi.sent, isEmpty);
    });

    test('links: terms from differential + question; no library -> none', () async {
      final doc = parseAiOutput(kDoc);
      final terms = AiChatRunner.linkTerms(doc, 'How do I manage a hip fracture?');
      expect(terms.any((e) => e.toLowerCase().contains('femoral neck fracture')), true);
      expect(terms.first.toLowerCase().contains('hip'), true);
      expect(await AiChatRunner.libraryLinks(doc, 'hip'), isA<List>());
    });
  });

  // ================================================================ widgets
  for (final lang in ['en', 'ar']) {
    for (final small in [false, true]) {
      final size = small ? const Size(360, 640) : const Size(412, 892);
      final tag = '${lang}_${small ? '360' : '412'}';
      testWidgets('ui $tag: FAB over the app, drag persists, chat sheet with context chip, verified/marked sources, library links', (tester) async {
        await initStoreRun(tester, lang, small ? 1.3 : 1.0);
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        installFakeAi(online: true, answers: {'Hip': kDoc});
        AiEngine.fakeSources = const [AiSource(title: 'nice.org.uk', url: 'https://vertexaisearch.cloud.google.com/x', host: 'nice.org.uk')];
        AiPrefs.answerLang = 'en';
        AiPrefs.fabY = 0.78;
        AiPrefs.fabSide = 'start';
        AiPrefs.sourceMode = 'web';
        AiFab.hiddenUntilRestart.value = false;
        AiContext.resetForTests();
        await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
        await tester.runAsync(() async {
          final base = Directory.systemTemp.createTempSync('g3lib');
          await library.init(base);
          await library.writePack(
            const PackMeta(id: 'orthopedics', title: 'Orthopedics', kind: 'wiki', source: 'WikEM', license: 'CC BY-SA 4.0', date: '2026-10-01'),
            [
              LibArticle('Femoral neck fracture', '', const [LibSection('', 'A femoral neck fracture is a break of the neck of the femur. It is common after a fall in older adults.')]),
              LibArticle('Hip fracture', '', const [LibSection('', 'Hip fracture is a break near the hip joint. Surgery is the usual treatment.')]),
            ],
          );
          await library.init(base);
        });
        await settle(tester, 3800);
        // the button is visible on the home tab, above the content and clear of the bottom bar
        final fab = find.byKey(const ValueKey('ai_fab'));
        expect(fab, findsOneWidget);
        final fr = tester.getRect(fab);
        final nav = tester.getRect(find.byType(AppNavBar));
        expect(fr.bottom <= nav.top, true, reason: 'FAB $fr must stay above the bottom bar $nav');
        expect(fr.top > 56, true);
        await shot(tester, 'G3_${tag}_home_fab');

        // drag: position saved (fraction) and side flips when dropped on the other half
        await tester.drag(fab, Offset(size.width * 0.6, -120));
        await settle(tester, 300);
        expect(AiPrefs.fabSide, lang == 'ar' ? 'start' : 'end'); // start = right side in Arabic
        expect(AiPrefs.fabY < 0.78, true);
        final y1 = AiPrefs.fabY;
        final fr2 = tester.getRect(fab);
        expect(fr2.right > size.width / 2, true);
        expect(store.settings['aiFabY'], y1); // stored with the other look settings
        // a drag far down never gets over the bottom bar
        await tester.drag(fab, const Offset(0, 900));
        await settle(tester, 300);
        expect(tester.getRect(fab).bottom <= nav.top, true);
        await tester.drag(fab, Offset(-size.width * 0.7, -900));
        await settle(tester, 300);
        expect(AiPrefs.fabSide, lang == 'ar' ? 'end' : 'start');
        expect(tester.getRect(fab).top >= 56, true);

        // open the chat with an article context
        AiPrefs.setScreenOn('article', true);
        final nav0 = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav0.push(MaterialPageRoute(builder: (_) => const Scaffold(body: AiContextScope(ctx: AiScreenContext(kind: 'article', title: 'Hip fracture'), child: Text('article page')))));
        await settle(tester, 700);
        expect(AiContext.current.value?.kind, 'article');
        expect(fab, findsOneWidget);
        await tester.tap(fab);
        await settle(tester, 700);
        expect(find.byKey(const ValueKey('chat_input')), findsOneWidget);
        expect(find.byKey(const ValueKey('chip_article')), findsOneWidget);
        expect(find.byKey(const ValueKey('quick_deepdive')), findsOneWidget);
        // FAB is hidden while the sheet is open
        expect(fab, findsNothing);
        await shot(tester, 'G3_${tag}_chat_empty');
        // remove the chip
        await tester.tap(find.descendant(of: find.byKey(const ValueKey('chip_article')), matching: find.byType(Icon)).last);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey('chip_article')), findsNothing);
        // ask
        await tester.enterText(find.byKey(const ValueKey('chat_input')), 'Hip fracture: what should I do first?');
        await tester.tap(find.byKey(const ValueKey('chat_send')));
        await pumpReal(tester, 10);
        await settle(tester, 600);
        expect(FakeAi.sent.last.search, isNotNull);
        expect(find.byKey(const ValueKey('banner_web')), findsOneWidget);
        expect(find.byKey(const ValueKey('cite_verified')), findsWidgets);
        expect(find.byKey(const ValueKey('cite_notAllowed')), findsWidgets);
        // library links resolved locally
        expect(find.byKey(const ValueKey('lib_orthopedics_1')), findsWidgets);
        await shot(tester, 'G3_${tag}_chat_answer');
        // source selector
        await tester.tap(find.byKey(const ValueKey('mode_btn')));
        await settle(tester, 500);
        expect(find.byKey(const ValueKey('mode_library')), findsOneWidget);
        expect(find.byKey(const ValueKey('mode_custom')), findsOneWidget);
        await shot(tester, 'G3_${tag}_chat_modes');
        await tester.tap(find.byKey(const ValueKey('mode_model')));
        await settle(tester, 400);
        // persisted
        expect(AiChats.all().isNotEmpty, true);
        expect(AiChats.all().first.msgs.length, 2);
        // not-allowed source opens a dialog, never a page
        await tester.ensureVisible(find.byKey(const ValueKey('cite_notAllowed')).first);
        await tester.drag(find.byType(ListView).first, const Offset(0, 90));
        await settle(tester, 300);
        await tester.tap(find.byKey(const ValueKey('cite_notAllowed')).first);
        await settle(tester, 500);
        await shot(tester, 'G3_${tag}_chat_blocked_source');
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await settle(tester, 400);
        FakeAi.sent.clear();
        AiContext.resetForTests();
      });
    }
  }

  testWidgets('FAB hidden: AI off, hidden in settings, per-screen off, until restart; long-press menu; + menu entries; AI-off explanation', (tester) async {
    await initStoreRun(tester, 'en', 1.0);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 892);
    addTearDown(tester.view.reset);
    AiPrefs.fabY = 0.5;
    AiPrefs.fabSide = 'start';
    AiPrefs.fabEnabled = true;
    AiFab.hiddenUntilRestart.value = false;
    AiContext.resetForTests();
    installFakeAi(online: true, enabled: false);
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
    await settle(tester, 3800);
    final fab = find.byKey(const ValueKey('ai_fab'));
    expect(fab, findsNothing, reason: 'AI off');
    installFakeAi(online: true);
    AiStore.changes.notifyListeners();
    await settle(tester, 300);
    expect(fab, findsOneWidget);
    // per-screen switch (screen kind comes from the context on top)
    final nav0 = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav0.push(MaterialPageRoute(builder: (_) => const Scaffold(body: AiContextScope(ctx: AiScreenContext(kind: 'calc', title: 'eGFR'), child: Text('calc page')))));
    await settle(tester, 700);
    expect(fab, findsOneWidget);
    await tester.runAsync(() async => AiPrefs.setScreenOn('calc', false));
    await settle(tester, 300);
    expect(fab, findsNothing);
    await tester.runAsync(() async => AiPrefs.setScreenOn('calc', true));
    nav0.pop();
    await settle(tester, 700);
    expect(fab, findsOneWidget);
    // long-press menu: hide until restart
    await tester.longPress(fab);
    await settle(tester, 600);
    expect(find.text('Hide until restart'), findsOneWidget);
    expect(find.text('Hide in settings'), findsOneWidget);
    await shot(tester, 'G3_menu');
    await tester.tap(find.text('Hide until restart'));
    await settle(tester, 500);
    expect(fab, findsNothing);
    AiFab.hiddenUntilRestart.value = false;
    await settle(tester, 300);
    expect(fab, findsOneWidget);
    await tester.longPress(fab);
    await settle(tester, 600);
    await tester.tap(find.text('Hide in settings'));
    await settle(tester, 500);
    expect(AiPrefs.fabEnabled, false);
    expect(fab, findsNothing);
    await tester.runAsync(() async => AiPrefs.fabEnabled = true);
    await settle(tester, 300);
    // + menu has the two entries
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await settle(tester, 700);
    expect(find.descendant(of: find.byType(GridView), matching: find.text('Ask AI')), findsOneWidget);
    expect(find.descendant(of: find.byType(GridView), matching: find.text('AI question bank')), findsOneWidget);
    await shot(tester, 'G3_add_menu');
    await tester.tap(find.descendant(of: find.byType(GridView), matching: find.text('Ask AI')));
    await settle(tester, 800);
    await shot(tester, 'G3_add_ask');
    expect(find.byKey(const ValueKey('chat_input')), findsOneWidget);
    await tester.tapAt(const Offset(200, 20)); // scrim closes the sheet
    await settle(tester, 600);
    // AI off: the entry explains and links to the settings (not a dead end)
    installFakeAi(online: true, enabled: false);
    AiStore.changes.notifyListeners();
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await settle(tester, 700);
    await tester.tap(find.descendant(of: find.byType(GridView), matching: find.text('Ask AI')));
    await settle(tester, 800);
    expect(find.text('Ask AI is off'), findsOneWidget);
    expect(find.text('Open Library & AI settings'), findsOneWidget);
    await shot(tester, 'G3_ai_off');
    await tester.tap(find.text('Open Library & AI settings'));
    await settle(tester, 900);
    expect(find.byType(Scaffold), findsWidgets);
    await shot(tester, 'G3_ai_off_settings');
  });

  testWidgets('context scope: current route wins, pop restores, tabs follow visibility, sheets are ignored', (tester) async {
    await initStoreRun(tester, 'en', 1.0);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 892);
    addTearDown(tester.view.reset);
    installFakeAi(online: true);
    AiContext.resetForTests();
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: const MedLogApp()));
    await settle(tester, 3800);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    String kind() => AiContext.current.value?.kind ?? '-';
    // push article A, then case B on top, then a screen without any scope
    nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: AiContextScope(ctx: AiScreenContext(kind: 'article', title: 'A'), child: Text('page A')))));
    await settle(tester, 700);
    expect(kind(), 'article');
    nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: AiContextScope(ctx: AiScreenContext(kind: 'case', title: 'B'), child: Text('page B')))));
    await settle(tester, 700);
    expect(kind(), 'case');
    // a dialog on top does not change the context
    showDialog<void>(context: nav.context, builder: (_) => const AlertDialog(content: Text('dlg')));
    await settle(tester, 500);
    expect(kind(), 'case');
    expect(find.byKey(const ValueKey('ai_fab')), findsNothing, reason: 'hidden while a dialog is on top');
    nav.pop();
    await settle(tester, 500);
    nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('page C without scope'))));
    await settle(tester, 700);
    expect(kind(), '-', reason: 'a screen without a context must not inherit the one below');
    nav.pop();
    await settle(tester, 700);
    expect(kind(), 'case');
    nav.pop();
    await settle(tester, 700);
    expect(kind(), 'article');
    nav.pop();
    await settle(tester, 700);
    expect(kind(), 'home', reason: 'back on the shell: its own context');
    // two tabs registered, only the visible one counts
    nav.push(MaterialPageRoute(builder: (_) => Scaffold(body: _Tabs())));
    await settle(tester, 700);
    expect(kind(), 'tabA');
    await tester.tap(find.text('go tab 2'));
    await settle(tester, 500);
    expect(kind(), 'tabB');
  });
}

class _Tabs extends StatefulWidget {
  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int i = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
        TextButton(onPressed: () => setState(() => i = 1), child: const Text('go tab 2')),
        Expanded(
          child: Stack(children: [
            for (var k = 0; k < 2; k++)
              Offstage(
                offstage: k != i,
                child: TickerMode(
                  enabled: k == i,
                  child: AiContextScope(ctx: AiScreenContext(kind: k == 0 ? 'tabA' : 'tabB'), child: Text('tab $k')),
                ),
              ),
          ]),
        ),
      ]);
}

Future<void> initStoreRun(WidgetTester t, String lang, double scale) async {
  await t.runAsync(() => initStore(lang, scale: scale));
}
