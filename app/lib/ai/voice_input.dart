import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../i18n.dart';
import '../widgets.dart' show snack;

/// Voice dictation (optional convenience, works on-device or through the phone's recogniser; nothing here uses
/// MedLog's AI provider). Use [VoiceInputButton] next to any TextField:
///
///     VoiceInputButton(controller: _answer)
///
/// The text recognised so far is written into [controller] while the user speaks (partial results). If the
/// recogniser is missing, offline without a language pack, or the microphone permission is denied, the button
/// shows a short message and the keyboard keeps working: nothing else depends on it.
///
/// Tests replace [VoiceInput.engine] with a fake [VoiceEngine].
abstract class VoiceEngine {
  /// True when recognition can start (recogniser exists and the permission was granted).
  Future<bool> init({void Function(String error)? onError, void Function(String status)? onStatus});
  Future<List<String>> locales();
  Future<void> start({required String localeId, required void Function(String text, bool isFinal) onText});
  Future<void> stop();
  bool get listening;
}

class SttEngine implements VoiceEngine {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;

  @override
  Future<bool> init({void Function(String error)? onError, void Function(String status)? onStatus}) async {
    try {
      _ready = await _stt.initialize(
        onError: (SpeechRecognitionError e) => onError?.call(e.errorMsg),
        onStatus: (s) => onStatus?.call(s),
      );
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<List<String>> locales() async {
    try {
      return [for (final l in await _stt.locales()) l.localeId];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> start({required String localeId, required void Function(String text, bool isFinal) onText}) async {
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) => onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        localeId: localeId,
        pauseFor: const Duration(seconds: 6),
        listenFor: const Duration(minutes: 2),
      ),
    );
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  @override
  bool get listening => _stt.isListening;
}

class VoiceInput {
  /// Replaceable in tests.
  static VoiceEngine engine = SttEngine();

  /// 'ar-JO' for the Arabic app, 'en-US' otherwise, matched against what the device offers
  /// (Android lists 'ar_JO', iOS 'ar-JO'; any Arabic / English variant is accepted when the exact one is missing).
  static String pickLocale(List<String> available, {bool? arabic}) {
    final ar = arabic ?? isAr;
    final want = ar ? 'ar-JO' : 'en-US';
    final lang = ar ? 'ar' : 'en';
    String n(String s) => s.replaceAll('_', '-').toLowerCase();
    for (final l in available) {
      if (n(l) == want.toLowerCase()) return l;
    }
    for (final l in available) {
      if (n(l).startsWith('$lang-') || n(l) == lang) return l;
    }
    return want.replaceAll('-', '_');
  }

  /// Message for an error code of the recogniser (permission, no network, nothing heard...).
  static String messageFor(String error) {
    final e = error.toLowerCase();
    if (e.contains('permission')) return tr('Microphone permission was denied. You can allow it in the phone settings, or type instead.');
    if (e.contains('no_match') || e.contains('speech_timeout')) return tr('Nothing was heard. Try again, or type instead.');
    if (e.contains('network')) return tr('Voice input needs a language pack or internet on this phone. You can type instead.');
    return tr('Voice input is not available right now. You can type instead.');
  }
}

class VoiceInputButton extends StatefulWidget {
  final TextEditingController controller;

  /// Called after the text changed because of dictation (so the screen can enable its Send button).
  final VoidCallback? onChanged;

  /// Force the dictation language (default: follows the app language).
  final bool? arabic;
  final double size;
  const VoiceInputButton({super.key, required this.controller, this.onChanged, this.arabic, this.size = 24});

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  bool _on = false;
  bool _busy = false;
  String _base = '';

  @override
  void dispose() {
    if (_on) VoiceInput.engine.stop();
    super.dispose();
  }

  void _fail(String error) {
    if (!mounted) return;
    setState(() {
      _on = false;
      _busy = false;
    });
    snack(context, VoiceInput.messageFor(error));
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final eng = VoiceInput.engine;
    if (_on) {
      await eng.stop();
      if (mounted) setState(() => _on = false);
      return;
    }
    setState(() => _busy = true);
    String? err;
    bool ok = false;
    try {
      ok = await eng.init(onError: (e) => err = e, onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted && _on) setState(() => _on = false);
      });
    } catch (e) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      _fail(err ?? 'unavailable');
      return;
    }
    final loc = VoiceInput.pickLocale(await eng.locales(), arabic: widget.arabic);
    _base = widget.controller.text;
    try {
      await eng.start(
        localeId: loc,
        onText: (text, isFinal) {
          if (!mounted) return;
          final sep = _base.isEmpty || _base.endsWith(' ') || _base.endsWith('\n') ? '' : ' ';
          final t = '$_base$sep$text';
          widget.controller.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
          widget.onChanged?.call();
          if (isFinal) {
            _base = t;
            setState(() => _on = false);
          }
        },
      );
    } catch (_) {
      _fail('unavailable');
      return;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _on = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('voiceInput'),
      tooltip: _on ? tr('Stop dictation') : tr('Dictate with your voice'),
      iconSize: widget.size,
      color: _on ? cs.error : null,
      icon: Icon(_on ? Icons.mic : Icons.mic_none),
      onPressed: _busy ? null : _toggle,
    );
  }
}
