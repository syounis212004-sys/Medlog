import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../data.dart';
import '../i18n.dart';
import '../screens_ai_chat.dart';
import '../screens_ai_settings.dart';
import 'ai_api.dart';
import 'ai_context.dart';
import 'ai_prefs.dart';

/// The floating "Ask AI" button: a small gradient sparkle that sits above every screen of the app (placed by main.dart BELOW the
/// access gate and the lock screens), can be dragged (position kept in AiPrefs.fabY / fabSide) and hidden.
class AiFab extends StatefulWidget {
  /// The key of the app Navigator (sheets are opened through it: the button lives above the Navigator).
  final GlobalKey<NavigatorState> Function() navigatorKey;

  /// True while a lock / access cover is shown: the button is not drawn at all then.
  final bool covered;
  const AiFab({super.key, required this.navigatorKey, this.covered = false});

  /// "Hide until restart" (long-press menu).
  static final ValueNotifier<bool> hiddenUntilRestart = ValueNotifier<bool>(false);

  /// Set by the Shell while the home shell is on screen (not during the splash).
  static final ValueNotifier<bool> shellReady = ValueNotifier<bool>(false);

  /// True while the user scrolls anything: the button fades so it never hides a list item.
  static final ValueNotifier<bool> scrolling = ValueNotifier<bool>(false);

  /// Pages where the button is never drawn (administration, access, error log).
  static const Set<String> neverOn = {'admin', 'access', 'errors'};

  /// Size of the button and the room kept for the bottom bar.
  static const double size = 50;

  /// The visibility rules in one pure function (tested).
  static bool visibleFor({
    required bool aiEnabled,
    required bool fabOn,
    required String kind,
    required bool hiddenForSession,
    required bool covered,
    required bool topIsPage,
    bool keyboardOpen = false,
    bool shellReady = true,
  }) {
    if (!aiEnabled || !fabOn || hiddenForSession || covered || !topIsPage || keyboardOpen || !shellReady) return false;
    if (neverOn.contains(kind)) return false;
    return AiPrefs.screenOn(kind);
  }

  /// Vertical range (top of the button) that avoids the app bar, the bottom bar with its "+" button and the system bars.
  static (double, double) yRange(Size screen, EdgeInsets pad, double textScale) {
    final bar = 80 + (textScale.clamp(1.0, 1.7) - 1) * 44;
    final minY = pad.top + 64;
    var maxY = screen.height - pad.bottom - bar - size - 14;
    if (maxY < minY) maxY = minY;
    return (minY, maxY);
  }

  @override
  State<AiFab> createState() => _AiFabState();
}

class _AiFabState extends State<AiFab> {
  Offset? _drag; // while dragging: top-left in screen coordinates

  late final Listenable _all = Listenable.merge([store, AiStore.changes, AiContext.current, AiRouteObserver.version, AiFab.hiddenUntilRestart, AiFab.shellReady, AiFab.scrolling]);

  @override
  void initState() {
    super.initState();
    AiStore.ensureLoaded();
  }

  BuildContext? get _navCtx => widget.navigatorKey().currentContext;

  void _open() {
    final c = _navCtx;
    if (c == null) return;
    HapticFeedback.selectionClick();
    openAskAi(c, ctx: AiContext.current.value);
  }

  void _menu() {
    final c = _navCtx;
    if (c == null) return;
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: c,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: Text('Hide until restart'),
            onTap: () {
              Navigator.pop(ctx);
              AiFab.hiddenUntilRestart.value = true;
            },
          ),
          ListTile(
            leading: const Icon(Icons.toggle_off_outlined),
            title: Text('Hide in settings'),
            subtitle: Text('You can turn the button on again in Library & AI settings.'),
            onTap: () {
              Navigator.pop(ctx);
              AiPrefs.fabEnabled = false;
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text('Library & AI settings'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(c).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _all,
      builder: (context, _) {
        final mq = MediaQuery.of(context);
        final kind = AiContext.current.value?.kind ?? 'other';
        final show = AiFab.visibleFor(
          aiEnabled: Ai.enabled,
          fabOn: AiPrefs.fabEnabled,
          kind: kind,
          hiddenForSession: AiFab.hiddenUntilRestart.value,
          covered: widget.covered,
          topIsPage: AiRouteObserver.topIsPage,
          keyboardOpen: mq.viewInsets.bottom > 0,
          shellReady: AiFab.shellReady.value,
        );
        if (!show) return const SizedBox.shrink();
        return LayoutBuilder(builder: (context, c) {
          final screen = Size(c.maxWidth, c.maxHeight);
          final (minY, maxY) = AiFab.yRange(screen, mq.padding, mq.textScaler.scale(1.0));
          final y = (_drag?.dy ?? (AiPrefs.fabY * screen.height)).clamp(minY, maxY).toDouble();
          final wide = screen.width >= 840; // the navigation rail sits at the start side
          final startPad = (wide ? 96.0 : 10.0);
          final atStart = AiPrefs.fabSide != 'end';
          final btn = AnimatedOpacity(opacity: AiFab.scrolling.value ? 0.22 : 1.0, duration: const Duration(milliseconds: 180), child: _button(context));
          final Widget placed;
          if (_drag != null) {
            placed = Positioned(left: _drag!.dx.clamp(6.0, screen.width - AiFab.size - 6), top: y, child: btn);
          } else if (atStart) {
            placed = PositionedDirectional(start: startPad, top: y, child: btn);
          } else {
            placed = PositionedDirectional(end: 10, top: y, child: btn);
          }
          return Stack(clipBehavior: Clip.none, children: [placed]);
        });
      },
    );
  }

  Widget _button(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('ai_fab'),
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      onLongPress: _menu,
      onPanStart: (d) => setState(() => _drag = d.globalPosition - const Offset(AiFab.size / 2, AiFab.size / 2)),
      onPanUpdate: (d) => setState(() => _drag = d.globalPosition - const Offset(AiFab.size / 2, AiFab.size / 2)),
      onPanEnd: (_) => _endDrag(context),
      onPanCancel: () => setState(() => _drag = null),
      child: Semantics(
        button: true,
        label: tr('Ask AI'),
        child: Container(
          width: AiFab.size,
          height: AiFab.size,
          decoration: BoxDecoration(
            gradient: kAiGradient,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: const Color(0xFF7C4DFF).withAlpha(110), blurRadius: 14, offset: const Offset(0, 5))],
            border: Border.all(color: Colors.white.withAlpha(150), width: 1.5),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  void _endDrag(BuildContext context) {
    final d = _drag;
    if (d == null) return;
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final (minY, maxY) = AiFab.yRange(screen, mq.padding, mq.textScaler.scale(1.0));
    final y = d.dy.clamp(minY, maxY).toDouble();
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final centreLeft = d.dx + AiFab.size / 2 < screen.width / 2;
    final startSide = rtl ? !centreLeft : centreLeft;
    setState(() => _drag = null);
    AiPrefs.fabSide = startSide ? 'start' : 'end';
    AiPrefs.fabY = (y / screen.height).clamp(0.05, 0.95);
  }
}
