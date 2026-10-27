import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medlog/ai/ai_api.dart';
import 'package:medlog/ai/ai_engine.dart';
import 'package:medlog/ai/ai_prefs.dart';
import 'package:medlog/ai/ai_providers.dart';
import 'package:medlog/ai/ai_store.dart';
import 'package:medlog/data.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _PP extends PathProviderPlatform {
  final String dir;
  _PP(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void cfg() {
  AiStore.memoryOnly = true;
  AiStore.resetForTests();
  AiStore.loaded = true;
  AiStore.master = true;
  AiStore.provider = AiProviderId.gemini;
  AiStore.models['gemini'] = 'm1';
  AiStore.setKey(AiProviderId.gemini, 'KEY-1');
  AiEngine.fake = null;
  AiEngine.debugOnline = true;
  AiEngine.online.value = true;
  AiEngine.resetRate();
  AiEngine.deadlineScale = 1.0;
  AiTransport.backoffScale = 0;
  AiPrefs.dailyCap = 60;
  AiPrefs.providerSearch = true;
}

AiHttpResponse ok(String text) => AiHttpResponse(200, jsonEncode({'candidates': [{'content': {'parts': [{'text': text}]}}]}));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    HttpOverrides.global = null;
    final dir = Directory.systemTemp.createTempSync('g6s').path;
    PathProviderPlatform.instance = _PP(dir);
    Directory('$dir/medlog/cases').createSync(recursive: true);
    Directory('$dir/medlog/images').createSync(recursive: true);
    File('$dir/medlog/settings.json').writeAsStringSync(jsonEncode({'lang': 'en', 'deviceId': 'x', 'lastBackup': DateTime.now().toIso8601String()}));
    await store.init();
  });
  tearDown(() {
    AiEngine.deadlineScale = 1.0;
    AiTransport.send = (r) async => throw StateError('no network in tests');
  });

  test('a request that never answers ends at the deadline with timedOut (no endless spinner)', () async {
    cfg();
    AiEngine.deadlineScale = 0.02; // 1 s
    AiTransport.send = (r) => Completer<AiHttpResponse>().future; // never completes
    final sw = Stopwatch()..start();
    final r = await Ai.run(const AiRequest(feature: 'ask_chat', system: 's', prompt: 'hello'));
    expect(r.ok, false);
    expect(r.timedOut, true);
    expect(r.error, isNotNull);
    expect(sw.elapsedMilliseconds < 4000, true, reason: '${sw.elapsedMilliseconds} ms');
  });

  test('timeouts are retried once, not twice', () async {
    cfg();
    var n = 0;
    AiTransport.send = (r) async {
      n++;
      throw TimeoutException('slow');
    };
    final r = await Ai.run(const AiRequest(feature: 'ask_chat', system: 's', prompt: 'hello'));
    expect(r.ok, false);
    expect(r.timedOut, true);
    expect(n, 2);
  });

  test('live search timing out: the question is answered without search, search stays available next time', () async {
    cfg();
    var withTools = 0, without = 0;
    AiTransport.send = (r) async {
      if (r.body != null && r.body!.contains('"tools"')) {
        withTools++;
        throw TimeoutException('search too slow');
      }
      without++;
      return ok('Plain answer');
    };
    final r = await Ai.run(AiRequest(feature: 'ask_chat', system: 's', prompt: 'hello', search: AiSearchSpec(mode: 'web', domains: const ['cdc.gov'])));
    expect(r.ok, true);
    expect(r.text, 'Plain answer');
    expect(r.searched, false);
    expect(r.searchNote, 'searchfail');
    expect(withTools, 2);
    expect(without, 1);
    expect(AiEngine.searchBlockedNote(), '', reason: 'a slow network must not switch search off for the whole day');
  });

  test('the connection check always ends and never returns the key', () async {
    cfg();
    final steps = await Ai.diagnose(AiProviderId.gemini, '', '').timeout(const Duration(seconds: 40));
    expect(steps.length, 3);
    for (final s in steps) {
      expect(s.detail.contains('KEY-1'), false);
    }
  });
}
