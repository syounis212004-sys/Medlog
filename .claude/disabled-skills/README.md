# Disabled skills

`understand-anything/understand` and `understand-anything/understand-diff` are stored here as **definitions only**. They are outside `.claude/skills/`, so Claude Code does not discover or run them, and `.claude/enforce` never requires them.

The enforcement hook also **denies** any `Skill` call named `understand*` until the project owner writes `ENABLE-UNDERSTAND: <reason>` in a prompt.

To enable them later (only when the owner says so): copy the two folders into `.claude/skills/`, remove the `understand*` guard in `.claude/enforce/rules.json` (`disabled_skills`), and decide first whether any hook should require them. Do not run them to build a graph without that order.
