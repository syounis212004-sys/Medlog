---
name: medlog-motion-guidance
description: MedLog project rules for motion and animation in the Flutter app (Material 3). Load before adding, changing or reviewing any animation, transition, page route or animated widget. Covers Flutter animation APIs, RTL/LTR direction, reduced motion, performance on mid-range Android phones, battery, offline use, long clinical forms, and the rule that motion never changes medical logic or data. Project rules override generic design or motion skills.
---

# MedLog motion guidance

This file is project policy for **Flutter/Dart + Material 3**. It does not replace `ui-ux-pro-max` or `android-design` (what the motion should look like); it says how and whether to animate here, and which limits win.

## Existing building blocks (reuse first)

MedLog already has motion helpers in `lib/motion.dart` (`FadeSlideIn`, `AnimatedBar`, `AnimatedRing`, page transitions) and `PressScale` in `lib/case_ui.dart`. Look there before writing a new animation. Reuse or extend them; do not create a parallel set.

## Rules

1. **Smallest Flutter API that fits.** Prefer implicit animations (`AnimatedContainer`, `AnimatedOpacity`, `AnimatedSwitcher`, `AnimatedSize`, `TweenAnimationBuilder`). Use an explicit `AnimationController` only when you need sequencing or repeat control, and always `dispose()` it.
2. **No new packages.** Never add an animation dependency (Lottie, Rive, `animations`, `flutter_animate`, physics or motion libraries) without explicit approval from the project owner. The web skills' `npm`, CSS, GSAP and Framer lines never apply.
3. **RTL and LTR.** MedLog is Arabic/English. Directional motion (slides, swipes, progress direction, enter/exit offsets, carousels) must follow `Directionality.of(context)` or use `AlignmentDirectional` / `EdgeInsetsDirectional` and a direction-aware sign. "Forward" is leftward in RTL. Never hard-code a left or right offset.
4. **Reduced motion.** Honor `MediaQuery.disableAnimationsOf(context)` (and the system animator scale). When it is on, replace movement with an instant change or a plain fade; the state change must still be visible.
5. **Purposeful and subtle.** Animate only to explain a state change, keep context, or give feedback. If it has no job, remove it. Keep durations short (about 150-300 ms for most UI); no animation may delay an action or block input.
6. **Performance on mid-range Android.**
   - No infinite or repeating animation unless it shows ongoing work, and it must stop when the screen is hidden or the work ends.
   - Keep animation out of long scrolling lists (`ListView`/`SliverList` items, long case forms) unless bounded and needed; never animate every row of a long list.
   - Isolate animated subtrees with `RepaintBoundary`, pass the static `child` to `AnimatedBuilder`/`TweenAnimationBuilder`, and avoid `setState` on large trees every frame.
   - Prefer transform and opacity (`Transform`, `FadeTransition`, `SlideTransition`) over properties that force relayout (size, padding) in hot paths.
   - Do not run work (JSON parsing, store writes, PDF) on the animation path.
7. **Clinical safety and data.** Motion is presentation only. It must not change case data, doses, scores, choices logic, navigation graph, save behavior or what is shown. Never hide or delay a warning (red flag, dose safety, "not assessed") with an animation, and never animate away content a clinician needs to read.
8. **Offline and persistence.** Animation must not depend on network assets and must not break draft saving or restoring state.
9. **Accessibility.** Keep text readable during transitions (no animated text that moves while being read), keep tap targets at least 48 dp, and keep `Semantics` intact.
10. **Tests.** Test with `tester.pump(Duration)` / `pumpAndSettle`, never real `sleep`. Repeating animations need an explicit stop in tests so `pumpAndSettle` can finish.

## Conflicts

If a generic skill disagrees with this file, follow this file. If this file disagrees with accessibility or platform behavior, follow accessibility and the platform.
