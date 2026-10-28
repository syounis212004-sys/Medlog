import 'dart:async' show scheduleMicrotask;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'access.dart';
import 'ai/ai_context.dart';
import 'ai/ai_fab.dart';
import 'app_lock.dart';
import 'data.dart';
import 'error_log.dart';
import 'i18n.dart';
import 'motion.dart';
import 'quick_add.dart';
import 'reminders.dart';
import 'screens_access.dart';
import 'screens_ai_chat.dart';
import 'screens_ai_quiz.dart';
import 'screens_cases.dart';
import 'screens_extras.dart';
import 'screens_home.dart';
import 'library.dart';
import 'screens_learn.dart';
import 'screens_tools.dart';
import 'screens_library.dart';
import 'screens_notebooks.dart';
import 'screens_review.dart';
import 'screens_search.dart';
import 'screens_skills.dart';
import 'search_index.dart';
import 'shortcuts.dart';
import 'theme.dart';
import 'widgets.dart';

/// One Navigator key per language. Flutter keeps a Navigator alive across
/// rebuilds (it has a global key), so without this every open screen and every
/// `const` widget would keep showing the old language after a switch.
final Map<String, GlobalKey<NavigatorState>> _navKeys = {};
GlobalKey<NavigatorState> navKeyFor(String id) => _navKeys.putIfAbsent(
    id, () => GlobalKey<NavigatorState>(debugLabel: 'nav-$id'));

/// One route observer per Navigator (a Navigator takes its own observer instance); it feeds the AI screen context
/// and tells the floating Ask-AI button whether a full page (not a dialog or sheet) is on top.
final Map<String, AiRouteObserver> _aiObservers = {};
AiRouteObserver aiObserverFor(String id) => _aiObservers.putIfAbsent(id, () {
      AiRouteObserver.reset();
      return AiRouteObserver();
    });

/// Key id used by the running app (language once the store is loaded).
String get currentNavId => store.ready ? '$langCode${medEnglish ? '' : '-ma'}' : 'boot';

/// Set by the running Shell so launcher shortcuts can switch tabs.
void Function(int tab)? shellGoTab;

/// "Ask AI" and "AI question bank" in the "+" menu (also called by the app State so widget tests that skip main() have them).
void registerAiMenuEntries() {
  addMenuExtras = [
    AddMenuExtra(Icons.auto_awesome, 'Ask AI', (c) => openAskAi(c)),
    AddMenuExtra(Icons.quiz_outlined, 'AI question bank', (c) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const AiQuizScreen()))),
  ];
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installFriendlyErrors();
  addProcedure = (c) => editProcedure(c);
  addNote = (c) => editNote(c);
  addQuestion = (c) => editQuestion(c);
  registerNotebookHooks();
  registerAiMenuEntries();
  openFeedbackHook = (c) => Navigator.push(
      c,
      MaterialPageRoute(
          builder: (_) => Scaffold(appBar: AppBar(title: Text('Feedback')), body: const FeedbackTab())));
  docOpeners[DocType.feedback] = (c, id) {
    final f = store.listOf('feedback').cast<J?>().firstWhere((e) => e!['id'] == id, orElse: () => null);
    editFeedback(c, f);
  };
  runApp(const MedLogApp());
  store.addListener(_installErrorLogOnce);
}

void _installErrorLogOnce() {
  if (!store.ready) return;
  store.removeListener(_installErrorLogOnce);
  ErrorLog.install();
}

class MedLogApp extends StatefulWidget {
  const MedLogApp({super.key});

  @override
  State<MedLogApp> createState() => _MedLogAppState();
}

class _MedLogAppState extends State<MedLogApp> with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    registerAiMenuEntries();
    WidgetsBinding.instance.addObserver(this);
    store.init().then((_) {
      store.applySecure();
      library.init(store.root.parent, bundled: const ['medlineplus']).then((_) {
        // local books get their in-text index in the background, so the general search finds words inside them
        for (final p in library.textPacks.where((p) => p.kind == 'book')) {
          library.ensureFts(only: p.id).then((_) {}, onError: (_) {});
        }
      }, onError: (_) {});
      // optional system features: never block or break the start
      try {
        appLock.startup();
      } catch (_) {}
      // administrator-approval gate: fail-soft, ungated unless an admin key is published
      access.startup().catchError((_) {});
      Reminders.sync();
      AppShortcuts.init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      appLock.onPaused();
      if (store.ready) {
        Reminders.onPaused();
        AppShortcuts.refreshItems();
      }
    } else if (state == AppLifecycleState.resumed) {
      final p = _pausedAt;
      if (p != null && DateTime.now().difference(p).inSeconds > 30) {
        store.lock();
      }
      _pausedAt = null;
      appLock.onResumed();
      Reminders.onResumed();
    }
  }

  /// The Android back button must not get past the lock cover.
  @override
  Future<bool> didPopRoute() async => store.ready && appLock.locked;

  @override
  void didChangeLocales(List<Locale>? locales) {
    // "follow the phone" language: rebuild when the phone language changes
    if (store.lang == kLangSystem && mounted) setState(() {});
  }

  ThemeMode get _mode {
    switch (store.themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([store, appLock, access]),
      builder: (context, _) {
        final pal = paletteById(store.paletteId);
        final ar = isAr;
        return MaterialApp(
          title: 'MedLog',
          navigatorKey: navKeyFor(currentNavId),
          navigatorObservers: [aiObserverFor(currentNavId)],
          debugShowCheckedModeBanner: false,
          locale: appLocale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(pal, Brightness.light,
              arabic: ar, arFont: store.fontAr, enFont: store.fontEn),
          darkTheme: buildTheme(pal, Brightness.dark,
              amoled: store.amoled,
              arabic: ar,
              arFont: store.fontAr,
              enFont: store.fontEn),
          themeMode: _mode,
          themeAnimationDuration: const Duration(milliseconds: 450),
          themeAnimationCurve: Curves.easeInOut,
          // The lock screen is drawn above the Navigator, so pushed screens can
          // never cover it. The key rebuilds every screen when the language
          // changes so no string is left in the old language.
          builder: (context, child) {
            // user text size on top of the phone's own font-size setting (capped so layouts survive)
            final mq = MediaQuery.of(context);
            final scaled = mq.textScaler.scale(1.0) * store.textScale;
            return MediaQuery(
                data: mq.copyWith(
                    textScaler: TextScaler.linear(scaled.clamp(0.8, 1.7))),
                child: KeyedSubtree(
                  key: ValueKey(currentNavId),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExcludeFocus(
                          excluding: store.ready && appLock.locked,
                          child: NotificationListener<ScrollNotification>(
                              onNotification: _fabScrollWatch,
                              child: child ?? const SizedBox.shrink())),
                      // the floating Ask-AI button: above the app, BELOW the access gate and the lock screens
                      if (store.ready)
                        Positioned.fill(
                            child: AiFab(
                                navigatorKey: () => navKeyFor(currentNavId),
                                covered: access.blocking || appLock.locked || store.locked)),
                      if (store.ready && access.blocking)
                        const Positioned.fill(child: AccessGate()),
                      if (store.ready && appLock.locked)
                        const Positioned.fill(child: AppLockScreen()),
                      if (store.ready && store.locked)
                        const Positioned.fill(child: PinScreen()),
                    ],
                  ),
                ));
          },
          home: const Root(),
        );
      },
    );
  }
}

bool _splashShown = false;

/// Fades the floating AI button while anything scrolls, so it never covers a list item the user is reading.
/// No timer: the scroll-end notification brings it back.
bool _fabScrollWatch(ScrollNotification n) {
  if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
  final want = n is ScrollEndNotification ? false : (n is ScrollStartNotification || n is ScrollUpdateNotification) ? true : null;
  // never change it while a frame is being built (notifications can arrive during layout)
  if (want != null && AiFab.scrolling.value != want) scheduleMicrotask(() => AiFab.scrolling.value = want);
  return false;
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool _done = _splashShown;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        Widget body;
        if (!store.ready) {
          body = const Scaffold(key: ValueKey('boot'), body: SizedBox.expand());
        } else if (!_done) {
          body = SplashScreen(
            key: const ValueKey('splash'),
            onDone: () {
              _splashShown = true;
              if (mounted) setState(() => _done = true);
            },
          );
        } else {
          body = const Shell(key: ValueKey('shell'));
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOut,
          child: body,
        );
      },
    );
  }
}

// ================================================================ shell + navigation

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  void _go(int v) => setState(() => _i = v);

  @override
  void initState() {
    super.initState();
    shellGoTab = (t) {
      if (mounted) _go(t);
    };
    AppShortcuts.shellReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AiFab.shellReady.value = true;
      AppShortcuts.tryRun();
    });
  }

  @override
  void dispose() {
    shellGoTab = null;
    AppShortcuts.shellReady = false;
    Future.microtask(() => AiFab.shellReady.value = false);
    super.dispose();
  }

  /// Long-press on "+": straight to the quick case sheet.
  void _addQuick(BuildContext context) {
    HapticFeedback.mediumImpact();
    showQuickAdd(context);
  }

  void _add(BuildContext context) => showAddMenu(
        context,
        onQuickCase: () => showQuickAdd(context),
        onFullCase: () => openNewCase(context),
      );

  @override
  Widget build(BuildContext context) {
    final tabs = TabStack(
      index: _i,
      children: [
        HomeScreen(onOpenTab: _go),
        const CasesScreen(),
        const LibraryScreen(embedded: true),
        const ToolsScreen(),
      ],
    );
    return LayoutBuilder(builder: (context, c) {
      // tablets and landscape: side navigation rail and a readable content width
      if (c.maxWidth >= 840) {
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _i,
                onDestinationSelected: _go,
                labelType: NavigationRailLabelType.all,
                backgroundColor: cs.surfaceContainer,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: GestureDetector(
                    onLongPress: () => _addQuick(context),
                    child: FloatingActionButton(
                      tooltip: tr('Add'),
                      onPressed: () => _add(context),
                      child: const Icon(Icons.add_rounded, size: 30),
                    ),
                  ),
                ),
                destinations: [
                  for (final it in _kNav)
                    NavigationRailDestination(
                      icon: Icon(it.icon),
                      selectedIcon: Icon(it.selected),
                      label: Text(it.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: tabs),
                ),
              ),
            ],
          ),
        );
      }
      return Scaffold(
        body: tabs,
        bottomNavigationBar: AppNavBar(
            index: _i,
            onTap: _go,
            onAdd: () => _add(context),
            onAddLong: () => _addQuick(context)),
      );
    });
  }
}

/// Keeps every tab alive (filters, scroll positions) and fades the new one in.
class TabStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const TabStack({super.key, required this.index, required this.children});

  @override
  State<TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<TabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 280), value: 1);

  @override
  void didUpdateWidget(TabStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && animOn(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(
              enabled: i == widget.index,
              child: AnimatedBuilder(
                animation: _c,
                child: widget.children[i],
                builder: (context, child) {
                  final v = i == widget.index
                      ? Curves.easeOutCubic.transform(_c.value)
                      : 1.0;
                  return Opacity(
                    opacity: v,
                    child: Transform.translate(
                        offset: Offset((1 - v) * 18 * dir, 0), child: child),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selected;
  final String label;
  const _NavItem(this.icon, this.selected, this.label);
}

const List<_NavItem> _kNav = [
  _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
  _NavItem(Icons.folder_shared_outlined, Icons.folder_shared, 'Cases'),
  _NavItem(Icons.local_library_outlined, Icons.local_library, 'Library'),
  _NavItem(Icons.apps_outlined, Icons.apps_rounded, 'Tools'),
];

/// Bottom bar with a sliding pill, bouncing icons and a raised "add case" button.
class AppNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;
  final VoidCallback? onAddLong;
  const AppNavBar(
      {super.key,
      required this.index,
      required this.onTap,
      required this.onAdd,
      this.onAddLong});

  Widget _item(BuildContext context, int i) {
    final cs = Theme.of(context).colorScheme;
    final sel = i == index;
    final it = _kNav[i];
    final on = animOn(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onTap(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration:
                    on ? const Duration(milliseconds: 320) : Duration.zero,
                curve: Curves.easeOutBack,
                width: sel ? 60 : 36,
                height: 32,
                decoration: BoxDecoration(
                  color: sel ? cs.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: AnimatedScale(
                  scale: sel ? 1.12 : 1.0,
                  duration:
                      on ? const Duration(milliseconds: 320) : Duration.zero,
                  curve: Curves.easeOutBack,
                  child: Icon(
                    sel ? it.selected : it.icon,
                    size: 24,
                    color: sel ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration:
                    on ? const Duration(milliseconds: 250) : Duration.zero,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                  color: sel ? cs.onSurface : cs.onSurfaceVariant,
                  fontFamily:
                      Theme.of(context).textTheme.bodyMedium?.fontFamily,
                ),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(it.label, maxLines: 1)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        side: BorderSide(color: cs.outlineVariant.withAlpha(120)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SizedBox(
          // taller with the text size, so labels never overflow
          height: 80 + (MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.7) - 1) * 44,
          child: Row(
            children: [
              _item(context, 0),
              _item(context, 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _AddButton(onTap: onAdd, onLongPress: onAddLong),
              ),
              _item(context, 2),
              _item(context, 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _AddButton({required this.onTap, this.onLongPress});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: tr('New case'),
      onLongPressHint: tr('Quick case'),
      child: GestureDetector(
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                setState(() => _down = false);
                widget.onLongPress!();
              },
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.86 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: AnimatedRotation(
            turns: _down ? 0.125 : 0,
            duration: const Duration(milliseconds: 180),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: paletteGradient(context),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withAlpha(80),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child:
                  const Icon(Icons.add_rounded, color: Colors.white, size: 32),
            ),
          ),
        ),
      ),
    );
  }
}
