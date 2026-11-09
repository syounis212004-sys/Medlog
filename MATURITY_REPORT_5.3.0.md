# SharqMed 5.3.0 — maturity report (done / not done)

## Done in this update
- **One icon family**: all Material `Icons.*` replaced by Phosphor (`Ph` / `PhFill`, the whole set bundled). Health Icons (CC0) for rotations/organs. Animated icons (`icon_animated`) in confirmation/warning snack bars; pop animation for the selected bottom-bar icon. A test (g34) fails the build if a Material icon or a meaning-bearing `Colors.green/red/amber/orange/blue` is added again.
- **Semantic colours** (`Sem`: success, danger, warning, info, star) replace 78 ad-hoc colour uses; contrast test g35 (WCAG 4.5:1 text, 3:1 icons) over 9 palettes × light/dark.
- **Accessibility/touch**: no `fontSize` below 12 in the UI; 19 icon buttons got tooltips (screen-reader names); bottom-bar items announced as selected buttons; the 2 remaining pop-up menus (AI source, copy) now use the app's bottom sheet.
- **Reliability**: 45 silent `catch (_) {}` in data.dart, library.dart, ai_store, lib_quiz, choices_engine now record to the local error log (never sent anywhere).

## Not done (honest list)
1. **Duplicate entries between screens were NOT removed** (Home vs Learn cards, 3 settings screens / `SettingsScreen` still lives in `screens_portfolio.dart`, 5 plan UIs, 6 Ask-AI entries, 13 quiz entries, 7 search entries). Needs product decisions on which entry stays; do it as its own update.
2. ~170 hex colour literals remain (mostly theme, PDF, AI document widgets, brand palettes).
3. The full logbook PDF (not the case PDF) still uses the old layout.
4. No on-device test and no TalkBack test; only widget tests. Only some `Semantics` added (nav bar), not every card.
5. ~1,680 strings are candidates for missing Arabic translation — not audited.
6. Very large files (screens_cases.dart ≈ 3,700 lines) not split.
7. No Lottie icon pack added: licences of free Lottie icons were not verified.
8. The full test suite (>1 hour) was not run; only the suites listed in the PR.
9. ~100 other silent catches (UI/network helpers) are left as they are.
