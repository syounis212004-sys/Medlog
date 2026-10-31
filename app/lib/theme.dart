import 'package:flutter/material.dart';

import 'data.dart' show store;
import 'motion.dart';

/// A selectable look for the whole app. Everything else (cards, chips, nav bar,
/// gradients) is derived from the seed color.
class AppPalette {
  final String id;
  final String nameEn;
  final String nameAr;
  final Color seed;
  final Color accent; // second gradient color
  const AppPalette(this.id, this.nameEn, this.nameAr, this.seed, this.accent);
}

const List<AppPalette> kPalettes = [
  AppPalette('clinic', 'Clinic Teal', 'أخضر العيادة', Color(0xFF00796B), Color(0xFF26C6DA)),
  AppPalette('ocean', 'Ocean Blue', 'أزرق المحيط', Color(0xFF1565C0), Color(0xFF29B6F6)),
  AppPalette('royal', 'Royal Purple', 'بنفسجي ملكي', Color(0xFF5E35B1), Color(0xFFBA68C8)),
  AppPalette('sunset', 'Sunset', 'غروب', Color(0xFFE65100), Color(0xFFFFB300)),
  AppPalette('rose', 'Rose', 'وردي', Color(0xFFC2185B), Color(0xFFFF8A80)),
  AppPalette('forest', 'Forest', 'غابة', Color(0xFF2E7D32), Color(0xFF9CCC65)),
  AppPalette('graphite', 'Graphite', 'رمادي فحمي', Color(0xFF37474F), Color(0xFF90A4AE)),
];

/// Selectable fonts. Arabic text uses [arFont], Latin text uses [enFont]; each
/// language's font is the main one and the other is the per-letter fallback, so
/// a typed English word inside Arabic text (or the reverse) never turns into boxes.
class FontChoice {
  final String id;
  final String label;
  final String? family; // null = the phone's default font
  const FontChoice(this.id, this.label, this.family);
}

const List<FontChoice> kArFonts = [
  FontChoice('cairo', 'Cairo', 'Cairo'),
  FontChoice('tajawal', 'Tajawal', 'Tajawal'),
];

const List<FontChoice> kEnFonts = [
  FontChoice('tinos', 'Times', 'Tinos'),
  FontChoice('default', 'Default', null),
];

FontChoice arFontById(String id) =>
    kArFonts.firstWhere((f) => f.id == id, orElse: () => kArFonts.first);
FontChoice enFontById(String id) =>
    kEnFonts.firstWhere((f) => f.id == id, orElse: () => kEnFonts.first);

AppPalette paletteById(String id) {
  for (final p in kPalettes) {
    if (p.id == id) return p;
  }
  return kPalettes.first;
}

final Map<String, ThemeData> _themeCache = {};

/// Themes are cached: the store notifies on every save and rebuilding a full
/// ThemeData each time would be wasted work.
ThemeData buildTheme(
  AppPalette p,
  Brightness b, {
  bool amoled = false,
  bool arabic = false,
  String arFont = 'cairo',
  String enFont = 'tinos',
}) {
  return _themeCache.putIfAbsent(
    '${p.id}|${b.name}|$amoled|$arabic|$arFont|$enFont',
    () => _polish(_buildTheme(p, b, amoled, arabic, arFontById(arFont), enFontById(enFont))),
  );
}

/// Readability pass applied to every theme: captions a little larger and darker,
/// chips with a 48 dp touch target.
ThemeData _polish(ThemeData t) {
  final cs = t.colorScheme;
  final cap = Color.lerp(cs.onSurfaceVariant, cs.onSurface, 0.35)!;
  TextStyle? fix(TextStyle? s, double min) => s == null
      ? s
      : s.copyWith(
          color: cap,
          fontSize: (s.fontSize ?? min) < min ? min : s.fontSize);
  final tt = t.textTheme;
  return t.copyWith(
    textTheme: tt.copyWith(
      bodySmall: fix(tt.bodySmall, 13),
      labelSmall: fix(tt.labelSmall, 12.5),
    ),
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}

ThemeData _buildTheme(
    AppPalette p, Brightness b, bool amoled, bool arabic, FontChoice ar, FontChoice en) {
  // main font follows the UI language, the other one covers the other script
  final String? family = arabic ? ar.family : en.family;
  final List<String> fallback = [
    if (arabic && en.family != null) en.family!,
    if (!arabic && ar.family != null) ar.family!,
  ];
  var cs = ColorScheme.fromSeed(seedColor: p.seed, brightness: b);
  if (b == Brightness.dark && amoled) {
    cs = cs.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0B0B0B),
      surfaceContainer: const Color(0xFF111111),
      surfaceContainerHigh: const Color(0xFF181818),
      surfaceContainerHighest: const Color(0xFF202020),
    );
  }
  final radius = BorderRadius.circular(16);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    fontFamily: family,
    fontFamilyFallback: fallback,
    scaffoldBackgroundColor: cs.surface,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SharedAxisBuilder(),
        TargetPlatform.iOS: SharedAxisBuilder(),
        TargetPlatform.linux: SharedAxisBuilder(),
        TargetPlatform.macOS: SharedAxisBuilder(),
        TargetPlatform.windows: SharedAxisBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: cs.outlineVariant),
      ),
    ),
    // An opened ExpansionTile draws a straight line along its top and bottom edge: inside a rounded card it stuck out
    // past the corners like a notch. No lines at all; the card's own border is enough.
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant.withAlpha(120), space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // room for the floating label above the text, so it never straddles the box edge
      contentPadding: const EdgeInsets.fromLTRB(16, 24, 16, 14),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      floatingLabelStyle: const TextStyle(fontSize: 13, height: 1.1),
      fillColor: cs.surfaceContainerHighest.withAlpha(b == Brightness.dark ? 90 : 120),
      // Underline style (not outline): the floating label then sits INSIDE the
      // filled box instead of straddling its top edge.
      border: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: cs.outlineVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      minVerticalPadding: 6,
    ),
  );
  // Times-style letters look smaller than Roboto at the same size: enlarge slightly
  if (!arabic && en.family == 'Tinos') {
    TextStyle? big(TextStyle? t) =>
        (t == null || t.fontSize == null) ? t : t.copyWith(fontSize: t.fontSize! * 1.1);
    final t = base.textTheme;
    return base.copyWith(
      textTheme: t.copyWith(
        displayLarge: big(t.displayLarge),
        displayMedium: big(t.displayMedium),
        displaySmall: big(t.displaySmall),
        headlineLarge: big(t.headlineLarge),
        headlineMedium: big(t.headlineMedium),
        headlineSmall: big(t.headlineSmall),
        titleLarge: big(t.titleLarge),
        titleMedium: big(t.titleMedium),
        titleSmall: big(t.titleSmall),
        bodyLarge: big(t.bodyLarge),
        bodyMedium: big(t.bodyMedium),
        bodySmall: big(t.bodySmall),
        labelLarge: big(t.labelLarge),
        labelMedium: big(t.labelMedium),
        labelSmall: big(t.labelSmall),
      ),
    );
  }
  if (arabic) {
    // Arabic letters (Cairo) carry a lot of space above and below: with an even,
    // slightly taller line the text sits in the middle of fields, chips and buttons
    // instead of pressing against the lower edge.
    TextStyle? centred(TextStyle? t) =>
        t == null ? t : t.copyWith(height: t.height ?? 1.45, leadingDistribution: TextLeadingDistribution.even);
    final t = base.textTheme;
    return base.copyWith(
      textTheme: t.copyWith(
        headlineLarge: centred(t.headlineLarge),
        headlineMedium: centred(t.headlineMedium),
        headlineSmall: centred(t.headlineSmall),
        titleLarge: centred(t.titleLarge),
        titleMedium: centred(t.titleMedium),
        titleSmall: centred(t.titleSmall),
        bodyLarge: centred(t.bodyLarge),
        bodyMedium: centred(t.bodyMedium),
        bodySmall: centred(t.bodySmall),
        labelLarge: centred(t.labelLarge),
        labelMedium: centred(t.labelMedium),
        labelSmall: centred(t.labelSmall),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        contentPadding: const EdgeInsets.fromLTRB(16, 26, 16, 16),
        floatingLabelStyle: const TextStyle(fontSize: 13, height: 1.3, leadingDistribution: TextLeadingDistribution.even),
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, height: 1.4, leadingDistribution: TextLeadingDistribution.even),
      ),
    );
  }
  return base;
}

/// Gradient used by the header, logo and add button. It is built from the
/// palette's own saturated colors (not the light dark-mode scheme colors) so
/// white text on top always has good contrast.
LinearGradient paletteGradient(BuildContext context, {bool soft = false}) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (soft) {
    final b = Color.lerp(cs.primary, cs.tertiary, 0.75)!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [cs.primary.withAlpha(dark ? 70 : 38), b.withAlpha(dark ? 40 : 18)],
    );
  }
  final p = paletteById(store.paletteId);
  final a = Color.lerp(p.seed, Colors.black, dark ? 0.30 : 0.0)!;
  final b = Color.lerp(Color.lerp(p.seed, p.accent, 0.55)!, Colors.black, dark ? 0.30 : 0.0)!;
  return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]);
}
