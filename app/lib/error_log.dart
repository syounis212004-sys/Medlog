import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'ai/ai_context.dart';
import 'data.dart';
import 'i18n.dart';
import 'widgets.dart';

/// A small local error log. It records unexpected errors (message and the top of the stack, never case data),
/// keeps the last 100 on this phone and never sends anything. The user can copy it to report a problem.
class ErrorLog {
  static final List<Map<String, String>> entries = [];
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static bool _installed = false;
  static File? _file;

  static Future<void> install() async {
    if (_installed) return;
    _installed = true;
    try {
      _file = File('${store.root.path}/errors.json');
      if (await _file!.exists()) {
        final l = jsonDecode(await _file!.readAsString());
        if (l is List) entries.addAll([for (final e in l) Map<String, String>.from((e as Map).map((k, v) => MapEntry(k.toString(), v.toString())))]);
      }
    } catch (_) {}
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      record(d.exceptionAsString(), d.stack, where: d.library ?? 'flutter');
      if (prev != null) prev(d); else FlutterError.presentError(d);
    };
    final prevPlat = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (e, st) {
      record(e.toString(), st, where: 'platform');
      return prevPlat?.call(e, st) ?? false;
    };
  }

  /// Cuts anything that looks like personal text: only the first line of the message is kept, long digit runs are masked.
  static String _clean(String s, int max) {
    final first = s.split('\n').first;
    final masked = first.replaceAll(RegExp(r'\d{6,}'), '######');
    return masked.length > max ? '${masked.substring(0, max)}…' : masked;
  }

  static void record(String message, StackTrace? stack, {String where = 'app'}) {
    final top = (stack?.toString() ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(6).map((l) => _clean(l, 160)).join('\n');
    entries.insert(0, {
      'time': DateTime.now().toIso8601String(),
      'where': where,
      'message': _clean(message, 300),
      'stack': top,
      'version': kAppVersion,
    });
    if (entries.length > 100) entries.removeRange(100, entries.length);
    changes.value++;
    unawaited(_save());
  }

  static Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode(entries));
    } catch (_) {}
  }

  static Future<void> clear() async {
    entries.clear();
    changes.value++;
    await _save();
  }

  static String report() => [
        'MedLog $kAppVersion error log (${entries.length})',
        for (final e in entries) '\n${e['time']} [${e['where']}] ${e['message']}\n${e['stack']}',
      ].join('\n');
}

class ErrorLogScreen extends StatelessWidget {
  const ErrorLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AiContextScope(
      ctx: const AiScreenContext(kind: 'errors', title: 'Error log'),
      child: Scaffold(
        appBar: AppBar(title: Text('Error log')),
        body: ValueListenableBuilder<int>(
          valueListenable: ErrorLog.changes,
          builder: (context, _, __) {
            final list = ErrorLog.entries;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              Text('Unexpected errors are kept here on this phone only. Nothing is sent anywhere. Copy the log if you want to report a problem.', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton.icon(
                  key: const ValueKey('errlog_copy'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: list.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: ErrorLog.report()));
                          if (context.mounted) snack(context, tr('Copied.'));
                        },
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: Text('Copy log'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: list.isEmpty ? null : ErrorLog.clear,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text('Clear'),
                ),
              ]),
              const SizedBox(height: 8),
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No errors recorded.'))),
              for (final e in list)
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        m.Text('${e['time']}  ·  ${e['where']}', style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        m.Text(e['message'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        if ((e['stack'] ?? '').isNotEmpty) m.Text(e['stack']!, style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

/// In the release app a screen that fails to build shows this card in its place instead of the grey box: what
/// happened, that it was recorded, and that the rest of the app still works.
class FriendlyError extends StatelessWidget {
  const FriendlyError({super.key});

  String _t(String s) {
    try {
      return tr(s);
    } catch (_) {
      return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rtl = _t('Something went wrong in this part.') != 'Something went wrong in this part.';
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        color: const Color(0xFFF7FBF9),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.healing_outlined, size: 44, color: Color(0xFF00695C)),
          const SizedBox(height: 12),
          m.Text(_t('Something went wrong in this part.'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF16201B), decoration: TextDecoration.none)),
          const SizedBox(height: 8),
          m.Text(_t('It was recorded in the error log (Settings). Go back and open it again; your data is safe.'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF455A54), decoration: TextDecoration.none)),
        ]),
      ),
    );
  }
}

/// Replaces the grey error box of release builds (debug builds keep the detailed one).
void installFriendlyErrors() {
  if (!kReleaseMode) return;
  ErrorWidget.builder = (details) => const FriendlyError();
}
