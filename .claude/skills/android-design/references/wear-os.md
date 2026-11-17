# Wear OS

Material 3 Expressive for Wear OS app screens, from the Wear OS design guide and androidx sources (Wear compose-material3 1.6.2 stable, checked September 2026). The phone guidance on emphasis, hero moments, and restraint still applies; this file covers what changes on a round, glanceable, battery-bound screen. Tiles, watch faces, and complications are outside this skill: use the `wear-widgets` skill for tiles and Wear widgets. For scaffolding (`AppScaffold`, `ScreenScaffold`), navigation, and migration, use the `wear-compose-m3` skill.

## Levels of expression

Google grades Wear apps and asks for **excellent or transformative**, and says "don't let your app or tile be unremarkable":

| | Excellent (required) | Transformative (recommended) |
| --- | --- | --- |
| Components | Multiple expressive components | Plus customization |
| Color | Dynamic palette themes | Plus unexpected color combinations |
| Typography | Roboto Flex | Roboto Flex with morphing (animated weight or width) |
| Shape | Some shape library and containment | Expressive containment |
| Motion | Tokens plus springs and shape morphing | Same |
| Hero moments | Product-specific expressive moments | Plus dramatic hierarchy |
| Adaptive | Percentage margins, added value past 225dp | Plus large-screen-specific designs |

## Principles

- **One or two critical tasks**, finished in seconds. No dense data, grids, or spreadsheets.
- **Glanceable:** test while moving; tiles get about 7 seconds of attention.
- **Shallow and vertical:** at most two levels deep; scroll in one direction only.
- **Embrace round:** edge-hugging buttons and bezel-hugging elements (progress rings, scroll indicators, curved time text) use the curve instead of fighting it.

## Theme

```kotlin
@Composable
fun WearAppTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    MaterialTheme(
        colorScheme = dynamicColorScheme(context) ?: BrandWearColorScheme,
        motionScheme = MotionScheme.expressive(), // Wear defaults to standard
        content = content,
    )
}
```

(`androidx.wear.compose.material3.MaterialTheme`, `MotionScheme`, and `dynamicColorScheme`.)

- `dynamicColorScheme(context)` returns null when the watch face provides no theme; always fall back.
- Wear springs (damping / stiffness): expressive spatial fast 0.7 / 800, default 0.75 / 350, slow 0.8 / 200; standard spatial 1.0 with 1400 / 500 / 260; effects never bounce.
- Wear corner scale: 4, 8, 18, 26, 36dp. There is no `MaterialShapes` on Wear.

## Color

- **Build from black, dark theme only:** "Wear OS uses only the dark theme." The app background is black (the `background` role); color lives in components, never in a tinted page. Container roles are fills, never text or icon colors.
- Dynamic themes come from two watch-face seed colors (primary and tertiary) and meet WCAG AAA. Pair only `X` with `onX`.
- Each accent has base, **dim**, and container roles. Primary: the main action and edge button. PrimaryDim: distinct but not demanding. Secondary: supporting actions in dense UI. Tertiary: standout feedback (tap responses, a goal reached). ErrorDim: emergencies and stop buttons.
- Recommended pairings: Primary with PrimaryDim (main plus complementary); PrimaryDim with Tertiary (highlight plus feedback); Primary with SecondaryContainer (main stands out, rest recedes); Tertiary plus Primary with SecondaryContainer when there's no single main action.
- Fill only the one primary action ([Primary action](#primary-action)); everything else recedes.
- Color carries meaning: red for errors, green for success.

## Typography

- Roboto Flex everywhere. Weight and width are the useful axes: narrow width fits long names and numbers; no wide type in headers; no very light weights at small sizes.
- Roles: `display*` (hero information and metrics), `title*` (wayfinding), `label*` (inside components), `bodyLarge` to `bodyExtraSmall`, `numeralExtraLarge` to `numeralExtraSmall` (tabular by default, can take expressive width), `arcLarge/Medium/Small` (curved text at the top or bottom edge).
- Curved text: `curvedText(text, style = MaterialTheme.typography.arcMedium)` inside a `CurvedScope`.
- Line height about 1.1x. The user font setting moves styles in 6% steps, but a style never scales at 20sp or larger: display, numeral, and `labelLarge` stay fixed, and title, `labelMedium`, `labelSmall`, body, and arc scale below that. Design for the largest and smallest settings, and for Bold text.
- Numerals are for a few digits that need no localization (timer, step count, picker); use tabular spacing wherever digits change or animate.

## Layout

- **Three sections:** top (optional time text, optional title, optionally a compact button on a very long page), middle (content), bottom (actions, ideally an **edge button**, or empty at the end of a journey). Time text never appears on dialogs, confirmations, or pickers, and nothing overlaps it. The scroll indicator appears only on scrolling screens.
- **Round safe area:** the curve clips corners. Outer margins (top, bottom, sides) are **percentages**, never fixed dp, and grow where the curve cuts in (the top and bottom margins differ by what sits there). Spacing between elements is fixed dp.
- **Touch targets:** at least 48 x 48dp, icons centered in the target. Every action is inline with an icon and a label where it fits; do not rely on an icon alone.
- **Small first:** design for the smallest round screen (204 to 216dp), render dense layouts at 192dp, and test 192dp with large fonts. **Breakpoint at 225dp:** add value past it (more content, more buttons, bigger controls, larger text for glanceability). A larger screen must never show less than a smaller one, so a size override that enlarges components must not push content out. Components fill the width; do not stretch them or scale fonts up unless they are graphic.
- **Scrolling screens** (most screens): a `TransformingLazyColumn`; items scale and fade at the top and bottom edges. Group long mixed lists with labels, but not a list of one content type. Elevate an unambiguous primary action to the top of a long page, or close the list with the edge button. Scroll in one direction only.
- **Non-scrolling screens** (media, pickers, steppers, timers, dialogs, progress): top, middle, and bottom sections, the middle stretching to fill the height. Prefer icon buttons over wide pills, and show data graphically (progress ring, large numeral). Use the preset dialog, confirmation, stepper, and picker layouts rather than custom ones. Never let content push the screen to scroll or get cut off.
- **Rotary input:** on non-scrolling screens with limited space (steppers, pickers, players), let the crown control the main value; tapping alone is not enough.

## Primary action

One prominent action per screen. On a scrolling screen it is usually the **edge button** at the end of the list: filled `primary`, with either a short label the user can read at a glance or a single clear icon (the API takes one or the other, never both). On a non-scrolling screen use an edge button when space allows, otherwise one filled icon button among lower-emphasis neighbors. Supporting actions are tonal, outlined, or child buttons; more than one bottom action goes in a button stack or a two-icon button group. If nothing is clearly main, pair `tertiary` and `primary` with `secondaryContainer`.

## Expressive components

| Pattern | API |
| --- | --- |
| Edge-hugging button | `ScreenScaffold(scrollState, edgeButton = { EdgeButton(onClick, buttonSize = EdgeButtonSize.Medium) { ... } })`; sizes ExtraSmall 46, Small 56, Medium 70, Large 96dp |
| Morph on press | `FilledIconButton(onClick, shapes = IconButtonDefaults.animatedShapes()) { ... }` (also `TextButtonDefaults.animatedShapes()`, toggle `animatedShapes()`) |
| Button group | `ButtonGroup { ... }`: one `MutableInteractionSource` per button, `Modifier.animateWidth(interactionSource)`, and the same source passed to the button; the pressed button widens and squeezes its neighbors |
| Morphing list | `TransformingLazyColumn` with `val spec = rememberTransformationSpec()`; per item `Modifier.transformedHeight(this, spec)` and `transformation = SurfaceTransformation(spec)` |

Custom `TransformationSpec` effects (rotating or morphing items at the edges) are hero-moment material, not a default.

## Media and ongoing activities

- **Media:** five-button controls with play/pause at 64dp (80dp past 225dp) inside a progress ring; volume via the rotating side button; prioritize downloaded media.
- **Always-on:** few lit pixels; drop frequently updating progress.
- **Haptics:** strong for key moments (payment confirmed), subtle for precision (scrolling), synced with motion.
- **Gestures (Wear OS 7):** double pinch triggers the screen's one primary action, wrist turn dismisses; every gesture action must also have a visible button.
- **Notifications** only when worth buzzing the wrist.

## Behaviors

- **Navigation:** swipe right closes the screen; no back buttons. Don't mix vertical and horizontal scrolling (media playback excepted). Non-scrolling multi-page layouts can paginate vertically or horizontally.
- **Physical buttons:** map a multifunction button only to a single-press, binary, reversible action (start/stop, play/pause) that also exists on screen. Never a destructive or multi-step action.
- **Launch:** black background with the 48dp circular app icon centered; build the screen from static text and placeholders, not an indeterminate spinner.
- **Ongoing activities:** the Recents entry states type and status (track, workout duration, ETA); the tile shows a glanceable summary.
- **Clipping:** test with Bold text, larger text, and long languages; calls to action fit the smallest screen; compact chips beat cards in dense layouts.
- **Offline:** an indicator at the top when features are unavailable (gray them out or hide them), at the end of a list when nothing more can load.
- **Sign-in:** passkeys through Credential Manager first, at least two methods total; sign-in-only apps ask immediately, others wait until needed and explain the benefit.
- **Dialogs:** alerts are full-screen interruptions, used sparingly, with text left-aligned past three lines. Confirmations only acknowledge a finished action; they never ask a question. Usually skip them: "A visible change in the UI is enough to show that an action succeeded."
- **Swipe to reveal** (delete, archive in lists): a partial left swipe reveals a primary and optional secondary action; a swipe past 75% commits the primary; destructive actions leave an undo chip.
