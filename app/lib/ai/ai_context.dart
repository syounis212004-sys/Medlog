import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// What the user is looking at right now: the floating Ask-AI button uses it to offer the right actions.
/// kind: home | article | case | quiz | calc | library | search | portfolio | learn | other
class AiScreenContext {
  final String kind;
  final String title;
  final Map<String, String> data; // small, non-identifying hints (e.g. packId, article title, calculator name)
  const AiScreenContext({this.kind = 'other', this.title = '', this.data = const {}});

  bool sameAs(AiScreenContext o) => kind == o.kind && title == o.title && mapEquals(data, o.data);
}

/// Tracks the page routes of the app Navigator (dialogs and bottom sheets are ignored) so that the context of the screen
/// the user really sees wins, and popping restores the one below. One observer per Navigator (see main.dart).
class AiRouteObserver extends NavigatorObserver {
  /// Routes in stack order (oldest first). Static: the AI core only ever cares about the app Navigator.
  static final List<Route<dynamic>> routes = [];

  /// Bumps whenever the stack changes (the floating button listens).
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void reset() {
    routes.clear();
    scheduleMicrotask(() => version.value++); // never notify while the tree is building
    AiContext._schedule();
  }

  /// The top route is a full page (not a dialog / bottom sheet / menu). True when nothing is known yet.
  static bool get topIsPage => routes.isEmpty || routes.last is PageRoute;

  void _changed() {
    version.value++;
    AiContext._schedule();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (i >= 0) {
      if (newRoute != null) {
        routes[i] = newRoute;
      } else {
        routes.removeAt(i);
      }
    } else if (newRoute != null) {
      routes.add(newRoute);
    }
    _changed();
  }
}

class _Entry {
  final Object owner;
  AiScreenContext ctx;
  Route<dynamic>? route;
  bool active; // visible tab / not Offstage (TickerMode)
  int seq;
  _Entry(this.owner, this.ctx, this.route, this.active, this.seq);
}

class AiContext {
  /// The context of the screen on top, or null when that screen registered none.
  static final ValueNotifier<AiScreenContext?> current = ValueNotifier<AiScreenContext?>(null);

  static final List<_Entry> _entries = [];
  static int _seq = 0;
  static bool _pending = false;
  static const Object _manual = Object();

  /// Manual override API (kept for code that sets the context itself): behaves like a screen without a route.
  static void set(AiScreenContext c) => _register(_manual, c, null, true);
  static void clear() => unregister(_manual);

  static void _register(Object owner, AiScreenContext c, Route<dynamic>? route, bool active) {
    for (final e in _entries) {
      if (identical(e.owner, owner)) {
        e.ctx = c;
        e.route = route;
        e.active = active;
        _schedule();
        return;
      }
    }
    _entries.add(_Entry(owner, c, route, active, ++_seq));
    _schedule();
  }

  static void unregister(Object owner) {
    _entries.removeWhere((e) => identical(e.owner, owner));
    _schedule();
  }

  static void _schedule() {
    if (_pending) return;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      recompute();
    });
  }

  /// Picks the context of the top page route. Without route information (tests, observer missing) the latest active one wins.
  static void recompute() {
    final live = _entries.where((e) => e.active).toList()..sort((a, b) => a.seq.compareTo(b.seq));
    AiScreenContext? pick;
    final routes = AiRouteObserver.routes;
    if (routes.isNotEmpty) {
      Route<dynamic>? top;
      for (var i = routes.length - 1; i >= 0; i--) {
        if (routes[i] is PageRoute) {
          top = routes[i];
          break;
        }
      }
      for (final e in live.reversed) {
        if (e.route == null) continue; // manual entries are handled below
        if (identical(e.route, top)) {
          pick = e.ctx;
          break;
        }
      }
      if (pick == null) {
        for (final e in live.reversed) {
          if (e.route == null) {
            pick = e.ctx;
            break;
          }
        }
      }
    } else if (live.isNotEmpty) {
      pick = live.last.ctx;
    }
    final cur = current.value;
    if (pick == null && cur == null) return;
    if (pick != null && cur != null && pick.sameAs(cur)) return;
    current.value = pick;
  }

  /// Tests: forget everything.
  static void resetForTests() {
    _entries.clear();
    AiRouteObserver.routes.clear();
    current.value = null;
  }
}

/// Wrap a screen body: registers the context while the screen is the current page route (and, for tab screens, the
/// visible tab). Pushing another page over it hides its context; popping restores it.
class AiContextScope extends StatefulWidget {
  final AiScreenContext ctx;
  final Widget child;
  const AiContextScope({super.key, required this.ctx, required this.child});
  @override
  State<AiContextScope> createState() => _AiContextScopeState();
}

class _AiContextScopeState extends State<AiContextScope> {
  final Object _owner = Object();

  void _sync() => AiContext._register(_owner, widget.ctx, ModalRoute.of(context), TickerMode.valuesOf(context).enabled);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AiContextScope old) {
    super.didUpdateWidget(old);
    if (!old.ctx.sameAs(widget.ctx)) _sync();
  }

  @override
  void dispose() {
    AiContext.unregister(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
