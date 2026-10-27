import 'ai_api.dart';
import 'ai_engine.dart';

/// Test seam for the other AI features. Call once at the start of a test:
///
///     installFakeAi(answers: {'metformin': 'Fake answer'}, online: true);
///
/// * AI is switched on with a fake key; everything stays in memory (no files, no secure storage).
/// * [Ai.run] still scrubs, previews, caches and logs; only the network is replaced: the final request
///   (what would have left the phone) is passed to the responder. The answer is the value of the first key of
///   [answers] that occurs in the prompt; otherwise [fallback].
/// * [FakeAi.sent] lists every request that "left the phone" (check privacy rules in tests).
/// * online=false makes every call return AiResult(offline: true).
void installFakeAi({Map<String, String> answers = const {}, bool online = true, String fallback = 'Fake AI answer', bool enabled = true}) {
  AiStore.memoryOnly = true;
  AiStore.resetForTests();
  AiStore.loaded = true;
  AiStore.master = enabled;
  AiStore.provider = AiProviderId.gemini;
  AiStore.models['gemini'] = 'fake-model';
  AiStore.setKey(AiProviderId.gemini, enabled ? 'fake-key' : '');
  AiEngine.debugOnline = online;
  AiEngine.online.value = online;
  AiEngine.fakeSent.clear();
  AiEngine.resetRate();
  AiEngine.fake = (r) {
    for (final e in answers.entries) {
      if (r.prompt.contains(e.key) || r.feature == e.key) return e.value;
    }
    return fallback;
  };
}

/// Back to the real provider (tests that need AiTransport instead).
void uninstallFakeAi() {
  AiEngine.fake = null;
  AiEngine.debugOnline = null;
  AiEngine.fakeSent.clear();
  AiStore.resetForTests();
  AiStore.memoryOnly = false;
}

class FakeAi {
  static List<AiRequest> get sent => AiEngine.fakeSent;
  static set online(bool v) {
    AiEngine.debugOnline = v;
    AiEngine.online.value = v;
  }
}
