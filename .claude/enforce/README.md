# MedLog skill enforcement (Claude Code hooks)

Hooks in `.claude/settings.json` call `enforce.py`; rules live in `rules.json`. Python 3 standard library only. Built for MedLog (Flutter/Dart, Material 3, Arabic/English RTL/LTR, offline medical logbook), not copied from Halaqati.

## What is enforced

| Situation | Requirement | Evidence checked beyond the Skill call |
|---|---|---|
| Editing Flutter UI files (`lib/screens*.dart`, widgets, theme, motion...) | `ui-ux-pro-max` + `android-design` (principles only, never Compose code) | none (invocation per actor/session) |
| Editing code that animates (`AnimationController`, `AnimatedContainer`, `FadeSlideIn`...) | `medlog-motion-guidance` | none |
| Prompt reports a **real bug** (stack trace, crash, `RenderFlex`, "لا يعمل"..., or two weak words) and `lib/` is edited | `systematic-debugging` for THIS task | at least one investigation (Read of code, a check run) before the first fix edit |
| Prompt asks for tests / TDD and `lib/` or `test/` is edited | `test-driven-development` for THIS task | a test file edited or a `flutter/dart test` run before production code (order only, **not** proof of Red-Green) |
| Commit / push / PR of a **large** change (>=150 changed lines or >=6 files; `medlog.zip` counts as 300 lines) | `ponytail-review` of THIS diff | the diff was really read: `git diff` (no `--stat`, no exclude pathspec) or a Read of each changed file after its last edit |
| Stop with uncommitted code changes made this session | `verification-before-completion` after the last edit | a passing `flutter analyze/test`, `dart ...`, JSON or `git diff --check` run after the last edit |
| Audit task writing an audit report | `ponytail-audit` | none |
| Design-only task touching medical data/logic (`assets/data/*`, choices/exam/dose/score engines) | **denied** | user waiver only |
| Edit of `.claude/enforce/*` or `.claude/settings.json` | **denied** | user waiver only |
| `Skill` call for `understand*` | **denied** (disabled) | user `ENABLE-UNDERSTAND:` only |

Understand-Anything and `understand-diff` are never required. Their definitions are stored in `.claude/disabled-skills/` (not discoverable).

## Gaps from the Halaqati system, and how they are handled
1. **Edits through Bash/Python were missed.** Now: static scan of redirects, `tee`, `sed -i`, `cp/mv/rm`, `git apply/checkout`, and Python/Node snippets that write; plus a before/after snapshot of `git status` for any possibly-mutating Bash command, so a path built at run time is still caught right after the command.
2. **grep or an exclude flag counted as "reviewed".** Now only `Read` and real `git diff/show` views count; `Grep`/`Glob` count only as exploration for debugging, and `--stat`, `--name-only`, `:(exclude)`, `:!path` and `--exclude` never count as reading.
3. **A Skill call was treated as proof.** Now debugging, TDD, review and verification each need extra evidence (see table). The README states plainly what stays unproven.
4. **Changed files come from git.** `git status` is compared with a session-start baseline, so old dirty files do not trigger demands and sub-agent or Bash edits are seen.
5. **Old skill state covering new changes.** Review and verification store a fingerprint of the changed files at invocation; any later change makes them stale. Debug/TDD skills are required again for each new task.
6. **Sub-agents.** State is per actor (`agent_id` or `main`). A sub-agent must invoke skills itself; `SubagentStart` tells it so; `SubagentStop` runs the same finish check.
7. **Loops and heavy hooks.** Stop blocks at most once (`stop_hook_active`). A rule that denies 3 times in a row with no new skill call lets the action through and logs it. Only path-classified edits are checked; reads, greps and normal commands pass instantly. A hook crash is logged and never blocks. A `git commit`/revert is not an edit: files that disappear from `git status` are ignored by the Bash snapshot check. Plain words like "fix" do not trigger debugging.

## Limits (honest)
- A log entry proves a skill was **invoked**, not that its guidance was applied well. TDD order is checked, not a real failing test. Quality is for ponytail-review, CI and humans.
- Bash can be obfuscated. The commit gate and the git snapshot are the backstop.
- Skills used via the user's own `/slash` command are not `Skill` tool calls and are not recorded.
- Hooks apply only in sessions that load this repo's `.claude/settings.json`.
- Source outside the repo: `rules.json` `extra_roots` (default `../Medlog-dev/app`) watches the app checkout used in cloud sessions; `medlog.zip` edits are treated as a package file.

## Waivers (only the user can write them, in a prompt)
`ENFORCE-WAIVE: <ui|motion|debug|tdd|review|verify|audit|medical-logic|config|*> <reason>` and `ENABLE-UNDERSTAND: <reason>`. Hooks read the user's prompt, so Claude cannot create one. Waivers are logged in `state/log/waivers.jsonl` and last for the session.

## Test and report
`python3 .claude/enforce/test_enforce.py` (26 light tests, simulated payloads in a temp git repo; never touches app code).
`python3 .claude/enforce/enforce.py report` summarizes the logs. State and logs are in `.claude/enforce/state/` (git-ignored).
