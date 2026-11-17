# Theming

Theme setup for Material 3 Expressive in Compose: versions, color schemes, typography, shapes, motion, and spacing. API names were checked against androidx sources (material3 1.5.0-alpha28) in September 2026.

## Versions

- `androidx.compose.material3:material3`: Expressive requires **1.5.0-alpha** or later. Stable 1.4.0 only has `ShortNavigationBar`, `WideNavigationRail`, and `ModalWideNavigationRail` from this skill.
- Toolchain: 1.5.0-alpha29 (and Wear Compose 1.7) require **compileSdk 37 and AGP 9.1+**; AGP 9.4 in turn needs Gradle 9.6. The `android create` template ships AGP 9.0.1, so raise these first or the build fails on dependency metadata checks.
- Check the newest version in [Maven metadata](https://dl.google.com/dl/android/maven2/androidx/compose/material3/material3/maven-metadata.xml) before adding it; alpha APIs still change (for example `Slider`'s `onValueChange` became required on main after alpha28, so pass it by name).
- Still `@ExperimentalMaterial3ExpressiveApi`: `MaterialShapes`, `RoundedPolygon.toShape()` / `toPath()`, `Morph.toPath()`, `LoadingIndicator`, `ContainedLoadingIndicator`, the pull-to-refresh loading indicator. Still `@ExperimentalMaterial3Api`: `AppBarWithSearch`, `carouselParallaxScrollEffect`, sheets, tooltips.
- Shape morphing uses `androidx.graphics:graphics-shapes`, which material3 already exposes.

## Theme

```kotlin
@Composable fun MaterialExpressiveTheme(
    colorScheme: ColorScheme? = null,
    motionScheme: MotionScheme? = null,
    shapes: Shapes? = null,
    typography: Typography? = null,
    content: @Composable () -> Unit,
)
```

A typical app theme takes dynamic color where available and falls back to a fixed scheme:

```kotlin
@Composable
fun AppTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val context = LocalContext.current
    val colorScheme = when {
        Build.VERSION.SDK_INT >= 31 -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> darkColorScheme()
        else -> expressiveLightColorScheme()
    }
    MaterialExpressiveTheme(
        colorScheme = colorScheme,
        motionScheme = MotionScheme.expressive(),
        typography = AppTypography, // Google Sans Flex voices plus an optional brand face
        content = content,
    )
}
```

- At the top level, nulls become `expressiveLightColorScheme()`, `MotionScheme.expressive()`, `Shapes()`, and `Typography()`. Nested, nulls inherit from the outer theme.
- `expressiveLightColorScheme()` is `lightColorScheme()` with more colorful `on*Container` roles. There is no dark counterpart; use `darkColorScheme()` or a generated scheme.
- Plain `MaterialTheme(...)` still works but defaults to `MotionScheme.standard()`.

## Color schemes

Pick one source per app, plus at most one content-based scheme per screen.

### Dynamic (wallpaper)

`dynamicLightColorScheme(context)` / `dynamicDarkColorScheme(context)` on API 31+. Google recommends it. Always provide a fallback scheme for older devices.

### Brand (seed color)

Compose has no seed or variant API. Two options:

1. **Static export:** generate light and dark schemes in Material Theme Builder from the brand color (or several: primary, secondary, tertiary, neutral) and paste the `lightColorScheme(...)` / `darkColorScheme(...)` values into the theme. Turn on "match color" (color fidelity) when the brand color must appear as-is.
2. **Runtime generation** with the third-party [MaterialKolor](https://github.com/jordond/MaterialKolor) library (`com.materialkolor:material-kolor`; check its latest version):

```kotlin
val colorScheme = rememberDynamicColorScheme(
    seedColor = BrandColor,
    isDark = dark,
    specVersion = ColorSpec.SpecVersion.SPEC_2025,
    style = PaletteStyle.TonalSpot, // Material's default; Fidelity when the brand color must appear as-is
    contrastLevel = rememberSystemContrast(), // see Contrast levels below
)
```

Keep the generator's default style. `TonalSpot` is what Material and Theme Builder generate; `Fidelity` keeps primary and secondary tones close to the seed, like Theme Builder's "match color" (observed with MaterialKolor, not a Google rule: its tertiary, like `Content`'s, moves far from the seed's hue). The other styles are scheme variants, not M3 Expressive: `Vibrant` pushes primary chroma to the maximum, and `Expressive` shifts hues away from the seed (in testing, a teal brand gained brown and orange roles) and tints surfaces. Palette variants are color-generation choices, not levels of M3 Expressive. For more color on a screen, use content-based color or give accent roles to more elements that have a job.

A common pattern: brand scheme by default, dynamic color as a user setting.

### Content-based

Color a contained area from an image on screen (a media player from its album art, cards from their photos). Keep the source image visible where its color is used, limit a screen to two scheme sources, and never recolor semantic colors.

With MaterialKolor, extract a seed from the image and theme just that subtree:

```kotlin
val seed = remember(art) { art.themeColor(fallback = BrandColor) } // com.materialkolor.ktx, on an ImageBitmap
val scheme = rememberDynamicColorScheme(seedColor = seed, isDark = isSystemInDarkTheme(), style = PaletteStyle.Content, contrastLevel = rememberSystemContrast())
MaterialExpressiveTheme(colorScheme = scheme) { NowPlaying(...) }
```

A nested theme changes `MaterialTheme.colorScheme` but not `LocalContentColor`, so plain `Icon` and `Text` keep the outer scheme's color (black icons on a dark player). Draw the themed subtree inside a `Surface(color = MaterialTheme.colorScheme.surface)`, which sets the matching content color.

Decode a small thumbnail for extraction, not the full image. MaterialKolor 5.x is built with Kotlin 2.4; if it fails to resolve against your Kotlin or Compose versions, pin the latest version that does (4.x for older Kotlin).

### Roles

| Role | Use |
| --- | --- |
| `primary` / `onPrimary` | The most important action and active states |
| `primaryContainer` / `onPrimaryContainer` | Standout fills (FAB, selected hero element) |
| `secondary`, `secondaryContainer` | Supporting controls, selection, tonal buttons, filter chips |
| `tertiary`, `tertiaryContainer` | Contrasting accents: status, badges, progress, delight; vibrant menus (vibrant toolbars use `primaryContainer`) |
| `error`, `errorContainer` | Errors (static in every scheme) |
| `surface`, `surfaceContainerLowest` to `surfaceContainerHighest` | Body background, then nested containers by emphasis; nav areas use `surfaceContainer` |
| `onSurface`, `onSurfaceVariant` | Default text; lower-emphasis text and icons |
| `outline`, `outlineVariant` | Text field borders; dividers and decorative lines |
| `inverseSurface`, `inverseOnSurface`, `inversePrimary` | Snackbars and reversed elements |
| `primaryFixed`, `primaryFixedDim` (and secondary, tertiary) | Same tone in light and dark themes |

Pairing and no-alpha rules live in [SKILL.md, Color](../SKILL.md#color). Material itself uses opacity only for state layers (built into components), disabled content (38%), and the `scrim` behind modals. `outlineVariant` is for dividers and decorative lines only, never text or icons.

### Extra colors (semantic and categories)

For a Success green, or categories beyond the two category-safe accent containers, Material's answer is a **static color**: one seed that produces four roles (color, on-color, container, on-container) following the same pairing rules. Generate them at runtime so they follow light, dark, and contrast:

```kotlin
@Immutable
data class ExtraColor(val color: Color, val onColor: Color, val container: Color, val onContainer: Color)

@Composable
fun rememberExtraColor(seed: Color, harmonize: Boolean = true): ExtraColor {
    val scheme = MaterialTheme.colorScheme
    val source = if (harmonize) scheme.harmonizeWithPrimary(seed) else seed // com.materialkolor.ktx
    val generated = rememberDynamicColorScheme(
        seedColor = source,
        isDark = scheme.surface.luminance() < 0.5f,
        style = PaletteStyle.TonalSpot,
        contrastLevel = rememberSystemContrast(),
    )
    return ExtraColor(generated.primary, generated.onPrimary, generated.primaryContainer, generated.onPrimaryContainer)
}
```

- Harmonizing shifts the hue slightly toward the scheme's primary while keeping its meaning (a red stays red). Skip it when the color is literal (a brand color, transit line colors) or must stay distinguishable: pass `harmonize = false` for categories, and pick seeds far apart in hue.
- Contrast for colors outside the scheme roles (category seeds, chart series, widget art): HCT tone difference is the contrast rule. "Smaller elements (less than ¼" or 40 dp) require a tone difference of 50 with their background, larger elements require a tone difference of 40." (Google)
- Use one role per category across a screen: `color` with an `onColor` glyph when the category also appears in a chart, or `container` with `onContainer` when it only marks badges. Category rules: [SKILL.md, Color](../SKILL.md#color).

### Contrast levels

Users pick standard, medium, or high contrast in system settings (Android 14+). Dynamic schemes follow it automatically; hand-made and generated schemes don't. For generated schemes, pass the system value to MaterialKolor:

```kotlin
@Composable
fun rememberSystemContrast(): Double {
    val context = LocalContext.current
    return remember(context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            context.getSystemService(UiModeManager::class.java).contrast.toDouble() // 0 standard, 0.5 medium, 1 high
        } else 0.0
    }
}
```

The brand and content-based snippets above already pass it. For a static Theme Builder export, also export the medium and high contrast schemes and pick one from this value.

## Typography

- 15 baseline styles plus 15 emphasized ones (`displayLargeEmphasized` ... `labelSmallEmphasized`, 1.5.0 only). Emphasized raises weight: Display, Headline, Body, and Title Large go Regular to Medium; Title Medium/Small and Labels go Medium to Bold.
- `Typography(fontFamily = ...)` sets one family everywhere. This skill mixes faces by role, so build each style with the `voice` helper ([Building the type scale](#building-the-type-scale)).
- Change letter spacing and line height to fit a new face, not the scale's sizes: "Avoid changing the type size; this can affect how components render and reflow." (Google) For editorial sizes (a total that fills the top of the screen), define a separate style outside the scale, like `numeralStyle` below.

### Google Sans Flex

Open source on [Google Fonts](https://fonts.google.com/specimen/Google+Sans+Flex) (since November 2025) and this skill's default family: plain text always uses it, and so does every Display, Headline, and Title Large unless you choose a brand face (below). Axes: `wght` 1 to 1000, `wdth` 25 to 151, `opsz` 6 to 144, `slnt` -10 to 0, `GRAD` 0 to 100, `ROND` 0 to 100.

Bundle the variable TTF in `res/font/` (downloadable Google Fonts don't carry variation settings).

Voice starting points (tune them to the screen's direction; they are not presets to copy):

| Voice | Axes (approx.) | Use for |
| --- | --- | --- |
| Friendly hero | weight 800 to 900, roundness 100 | The one hero title or number in a warm, playful product |
| Tall numerals | width 25 to 50; weight 300 off, 800 on | Numbers that fill a card (times, totals, calculators), state through weight |
| Premium display | width 75 to 90, weight 400 to 600 | Elegant headers and editorial titles |
| Airy display | weight 100 to 300, large sizes only | Calm headers, inactive states |
| Wide header | width 125 to 151, weight 500 to 700, roundness 0 | Confident section or dialog titles; never in app bars |
| Loud expressive | width 151, weight 900, slant -10 | Celebrations and the user's own voice; rare |
| Text | default axes, weight 400 to 500 | Body and labels; don't vary it |

### Brand faces (Display, Headline, and Title Large only)

Optional: one face from the set below on Display, Headline, and Title Large styles, with everything else on Google Sans Flex. A small app bar title and a side sheet title draw in `titleLarge`, so a brand face set only on Display and Headline leaves those headers in the plain face. The face set, one face per proposal, Doto's display-only limit, and keeping Title Medium and Small on Google Sans Flex are this skill's choices, not Google's. All are OFL and bundled as variable TTFs with the previewer app that `android-design-explore` drives, so an exploration never fetches fonts. A real app bundles the variable TTF of each face it uses in `res/font/`. Material calls this the brand typeface (larger styles, "to focus on expression") against the plain typeface (smaller styles, "to focus on readability"); do not use a brand face on Title Medium, Title Small, Body, or Label.

| Face | File | Axes | Use for | Starting point |
| --- | --- | --- | --- | --- |
| Fraunces | `fraunces` | `opsz` 9-144, `wght` 100-900, `SOFT` 0-100, `WONK` 0-1 | Warm editorial serif: food, reading, journaling, heritage | `wght` 600, `SOFT` 100, `WONK` 1 |
| Bricolage Grotesque | `bricolage_grotesque` | `opsz` 12-96, `wdth` 75-100, `wght` 200-800 | Playful, quirky grotesque: indie, creative tools | `wght` 800, `wdth` 80 to 100 |
| Big Shoulders Display | `big_shoulders_display` | `wght` 100-900 | Tall condensed poster type: sport, fitness, transit, loud energy | `wght` 800 to 900, tight tracking, line height 1.2x |
| Doto | `doto` | `ROND` 0-100, `wght` 100-900 | Dot-matrix: timers, music, retro-tech. Display sizes only (36sp and up) | `wght` 700 to 900, `ROND` 100 for round dots |

Measured line boxes (Pixel_10_Pro_XL emulator, M3 `bodyLarge` base style with the token size and line height): Fraunces, Bricolage Grotesque, and Big Shoulders Display match the token line height at 36/44 and 32/40 (Fraunces 44.7dp at 36/44 from pixel rounding), so no extra vertical room is needed. Doto at 45/52 renders 54dp tall, so leave about 2dp of room around a Doto line. Google Sans Flex, by comparison, renders 52.7dp at 36/44 and 46.7dp at 32/40.

Google Sans Code (`google_sans_code`, `wght` 300-800) is the mono face for numbers and data (timers, tabular values, codes, metadata) at any size, in any proposal.

### Building the type scale

Build every style from a bundled face with `voice`. A plain `FontFamily(Font(R.font.google_sans_flex))` draws every weight at 400, because a variable font needs `FontVariation.weight` set per `Font`. Variation settings apply on API 26+.

```kotlin
/**
 * A voice: one bundled variable face at fixed axes. Sets weight and optical size itself (Compose
 * never sets optical size, and Fraunces and Bricolage Grotesque change width without it; faces with
 * no `opsz` axis ignore it). `axes` holds only the face's other axes, such as width, SOFT, or ROND:
 * Compose rejects a repeated axis.
 */
fun TextStyle.voice(@FontRes font: Int, weight: Int, vararg axes: FontVariation.Setting) = copy(
    fontFamily = FontFamily(
        Font(
            resId = font,
            weight = FontWeight(weight),
            variationSettings = FontVariation.Settings(
                FontVariation.weight(weight),
                FontVariation.opticalSizing(fontSize),
                *axes,
            ),
        ),
    ),
    fontWeight = FontWeight(weight),
)

private val base = Typography()
private val soft = arrayOf(FontVariation.Setting("SOFT", 100f), FontVariation.Setting("WONK", 1f))

val AppTypography = base.copy(
    // Display, Headline, and Title Large: one brand face (Fraunces here) or a Google Sans Flex voice,
    // such as base.displayLarge.voice(R.font.google_sans_flex, 850, FontVariation.Setting("ROND", 100f)).
    // Set all six, plus their *Emphasized styles: components read them internally
    // (a large app bar's title is displaySmall), so a skipped one falls back to the default face.
    displayLarge = base.displayLarge.voice(R.font.fraunces, 600, *soft),
    displayMedium = base.displayMedium.voice(R.font.fraunces, 600, *soft),
    displaySmall = base.displaySmall.voice(R.font.fraunces, 600, *soft),
    headlineLarge = base.headlineLarge.voice(R.font.fraunces, 600, *soft),
    headlineMedium = base.headlineMedium.voice(R.font.fraunces, 600, *soft),
    headlineSmall = base.headlineSmall.voice(R.font.fraunces, 600, *soft),
    // Title Large is read by small app bars and side sheets, so it takes the brand face too.
    titleLarge = base.titleLarge.voice(R.font.fraunces, 600, *soft),
    // Title Medium and Small, Body, and Label: always Google Sans Flex at default axes.
    titleMedium = base.titleMedium.voice(R.font.google_sans_flex, 500),
    bodyLarge = base.bodyLarge.voice(R.font.google_sans_flex, 400),
    bodyMedium = base.bodyMedium.voice(R.font.google_sans_flex, 400),
    labelLarge = base.labelLarge.voice(R.font.google_sans_flex, 500),
    // ...the remaining Title, Body, and Label styles (titleLargeEmphasized takes the brand face), and every *Emphasized style one weight step heavier
)

// Voices outside the type scale: tall numerals with state, and numbers and data.
@Composable
fun numeralStyle(selected: Boolean) = MaterialTheme.typography.displayLarge
    .voice(R.font.google_sans_flex, if (selected) 800 else 300, FontVariation.width(35f))
    .copy(fontFeatureSettings = "tnum")

@Composable
fun dataStyle() = MaterialTheme.typography.bodyMedium
    .voice(R.font.google_sans_code, 500)
    .copy(fontFeatureSettings = "tnum")
```

- Define two or three voices once per app and apply them consistently; don't invent new axis values per screen.
- State through axes: selected items heavy (700 to 900), unselected light (200 to 300); keep sizes equal so nothing reflows. `FontVariation.grade(...)` changes emphasis without changing width.
- Each distinct axis combination is a separate font instance; for animated axes (text that widens as a slider moves), step through a small set of values and keep it to a hero moment.
- Tabular numbers: `style.copy(fontFeatureSettings = "tnum")`.

## Shapes

`Shapes(extraSmall, small, medium, large, extraLarge, largeIncreased, extraLargeIncreased, extraExtraLarge)`, read as `MaterialTheme.shapes.*`:

| Token | Default | Typical use |
| --- | --- | --- |
| extraSmall | 4dp | Chips, snackbars |
| small | 8dp | Text fields, menus |
| medium | 12dp | Cards |
| large | 16dp | FABs, sheets on large screens |
| largeIncreased | 20dp | Expressive containers |
| extraLarge | 28dp | Dialogs, bottom sheets |
| extraLargeIncreased | 32dp | Expressive hero containers |
| extraExtraLarge | 48dp | Large hero surfaces |

Change a token to change every component mapped to it; pass `shape` to change one component.

### Shape library

`MaterialShapes` (experimental) has 35 `RoundedPolygon`s: Circle, Square, Slanted, Arch, Fan, Arrow, SemiCircle, Oval, Pill, Triangle, Diamond, ClamShell, Pentagon, Gem, Sunny, VerySunny, Cookie4Sided, Cookie6Sided, Cookie7Sided, Cookie9Sided, Cookie12Sided, Ghostish, Clover4Leaf, Clover8Leaf, Burst, SoftBurst, Boom, SoftBoom, Flower, Puffy, PuffyDiamond, PixelCircle, PixelTriangle, Bun, Heart.

Clip with `Modifier.clip(MaterialShapes.Sunny.toShape())` or use as a `Surface` shape.

### Shape morphing

Prefer components that morph on their own (buttons, icon buttons, toggles, button groups, list items, loading indicators). For a custom morph between two library shapes:

```kotlin
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
private class MorphShape(private val morph: Morph, private val progress: Float) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val path = morph.toPath(progress = progress) // unit-square coordinates
        path.transform(Matrix().apply { scale(size.width, size.height) })
        return Outline.Generic(path)
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun MorphingBadge(done: Boolean, modifier: Modifier = Modifier) {
    val morph = remember { Morph(MaterialShapes.Circle, MaterialShapes.Cookie9Sided) }
    val progress by animateFloatAsState(if (done) 1f else 0f, MaterialTheme.motionScheme.defaultSpatialSpec())
    Box(modifier.size(64.dp).clip(MorphShape(morph, progress)).background(MaterialTheme.colorScheme.tertiaryContainer))
}
```

## Motion

`MotionScheme` has six specs: `defaultSpatialSpec`, `fastSpatialSpec`, `slowSpatialSpec`, `defaultEffectsSpec`, `fastEffectsSpec`, `slowEffectsSpec`. `MotionScheme.expressive()` and `MotionScheme.standard()` are the presets:

| Spec | Expressive (damping / stiffness) | Standard |
| --- | --- | --- |
| Fast spatial | 0.6 / 800 | 0.9 / 1400 |
| Default spatial | 0.8 / 380 | 0.9 / 700 |
| Slow spatial | 0.8 / 200 | 0.9 / 300 |
| Effects fast / default / slow | 1.0 / 3800, 1600, 800 | same |

- Override one subtree by nesting `MaterialTheme(motionScheme = MotionScheme.standard()) { ... }` (`LocalMotionScheme` was removed).
- Reduced motion, Google's pattern:

```kotlin
object ReducedMotionScheme : MotionScheme {
    override fun <T> defaultSpatialSpec(): FiniteAnimationSpec<T> = snap()
    override fun <T> fastSpatialSpec(): FiniteAnimationSpec<T> = snap()
    override fun <T> slowSpatialSpec(): FiniteAnimationSpec<T> = snap()
    override fun <T> defaultEffectsSpec(): FiniteAnimationSpec<T> = snap()
    override fun <T> fastEffectsSpec(): FiniteAnimationSpec<T> = snap()
    override fun <T> slowEffectsSpec(): FiniteAnimationSpec<T> = snap()
}
```

- A custom brand scheme overrides the same six functions with `spring(dampingRatio, stiffness)`; keep effects specs at `Spring.DampingRatioNoBouncy`.

## Spacing

Compose has no spacing tokens. Define the 8dp scale once in the theme package and use it everywhere:

```kotlin
object Spacing {
    val xs = 4.dp
    val s = 8.dp
    val m = 12.dp
    val l = 16.dp
    val xl = 24.dp
    val xxl = 32.dp
    val xxxl = 48.dp
}
```

Screen margins: 16dp on compact, 24dp on medium and larger. Put padding and gaps on parent layouts (`Arrangement.spacedBy`) instead of margins on children.
