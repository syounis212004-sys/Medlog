#!/usr/bin/env python3
"""Tests for the MedLog skill enforcement hooks. Light: simulated hook payloads in a throw-away git repo.
Run:  python3 .claude/enforce/test_enforce.py
Never touches the app code; state goes to a temp dir."""
import json, os, shutil, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ENFORCE = os.path.join(HERE, "enforce.py")
RULES = os.path.join(HERE, "rules.json")


def sh(cwd, *a):
    subprocess.run(a, cwd=cwd, check=True, capture_output=True)


def wr(path, text, mode="w"):
    with open(path, mode, encoding="utf-8") as f:
        f.write(text)


def rd(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class Base(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix="medlog-enf-")
        self.state = tempfile.mkdtemp(prefix="medlog-enf-state-")
        os.makedirs(os.path.join(self.d, ".claude", "enforce"))
        rules = json.loads(rd(RULES))
        rules["extra_roots"] = []
        wr(os.path.join(self.d, ".claude", "enforce", "rules.json"), json.dumps(rules))
        for f, c in (("lib/screens_home.dart", "// ui\n"), ("lib/store.dart", "// logic\n"), ("test/store_test.dart", "// t\n"),
                     ("assets/data/cards.json", "{}\n"), ("README.md", "x\n")):
            p = os.path.join(self.d, f)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            wr(p, c)
        sh(self.d, "git", "init", "-q")
        sh(self.d, "git", "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A")
        sh(self.d, "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init")
        self.n = 0
        self.sid = "s1"
        self.prompt("hello")

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)
        shutil.rmtree(self.state, ignore_errors=True)

    def run_hook(self, cmd, payload):
        payload.setdefault("session_id", self.sid)
        env = dict(os.environ, CLAUDE_PROJECT_DIR=self.d, MEDLOG_ENFORCE_STATE=self.state)
        r = subprocess.run([sys.executable, ENFORCE, cmd], input=json.dumps(payload).encode(), env=env, capture_output=True, timeout=30)
        return r.returncode, r.stdout.decode(), r.stderr.decode()

    def prompt(self, text):
        return self.run_hook("prompt", {"prompt": text, "hook_event_name": "UserPromptSubmit"})

    def fresh(self):
        """New session: independent state (so the 3-denials circuit breaker of an earlier call does not interfere)."""
        self.sid = "s%d" % (self.n + 100)
        self.n += 1
        self.prompt("hello")

    def tid(self):
        self.n += 1
        return "tu%d" % self.n

    def edit(self, path, agent=None, new="x\n", tool="Edit"):
        ti = {"file_path": os.path.join(self.d, path), "new_string": new, "old_string": "a"} if tool == "Edit" else {"file_path": os.path.join(self.d, path), "content": new}
        pl = {"tool_name": tool, "tool_input": ti}
        if agent:
            pl["agent_id"] = agent
        return self.run_hook("gate", pl)

    def did_edit(self, path, text="changed\n", agent=None):
        wr(os.path.join(self.d, path), text, "a")
        pl = {"tool_name": "Edit", "tool_input": {"file_path": os.path.join(self.d, path)}}
        if agent:
            pl["agent_id"] = agent
        return self.run_hook("record", pl)

    def skill(self, name, agent=None):
        pl = {"tool_name": "Skill", "tool_input": {"skill": name}}
        if agent:
            pl["agent_id"] = agent
        return self.run_hook("record", pl)

    def bash(self, cmd, response=None, agent=None, uid=None):
        pl = {"tool_name": "Bash", "tool_input": {"command": cmd}, "tool_use_id": uid or self.tid()}
        if agent:
            pl["agent_id"] = agent
        g = self.run_hook("gate", pl)
        if response is not None:
            pl["tool_response"] = {"stdout": response, "stderr": ""}
            return g, self.run_hook("record", pl)
        return g

    def read(self, path):
        return self.run_hook("record", {"tool_name": "Read", "tool_input": {"file_path": os.path.join(self.d, path)}})


class TestTaskClassification(Base):
    def test_plain_fix_word_is_not_a_bug_task(self):
        self.prompt("fix the wording of the title")
        self.assertEqual(self.edit("lib/store.dart")[0], 0)

    def test_real_bug_requires_debugging_skill_and_investigation(self):
        self.prompt("RenderFlex overflowed on the case screen, fix the crash")
        code, _, err = self.edit("lib/store.dart")
        self.assertEqual(code, 2)
        self.assertIn("systematic-debugging", err)
        self.skill("systematic-debugging")
        code, _, err = self.edit("lib/store.dart")
        self.assertEqual(code, 2)  # invoked, but no investigation evidence
        self.assertIn("investigation", err)
        self.read("lib/store.dart")
        self.assertEqual(self.edit("lib/store.dart")[0], 0)

    def test_old_debug_skill_does_not_carry_to_next_task(self):
        self.prompt("crash when saving")
        self.skill("systematic-debugging")
        self.read("lib/store.dart")
        self.assertEqual(self.edit("lib/store.dart")[0], 0)
        self.prompt("another crash in export")
        self.assertEqual(self.edit("lib/store.dart")[0], 2)  # skill must be invoked again for the new task


class TestTdd(Base):
    def test_tests_task_needs_skill_then_test_first(self):
        self.prompt("اكتب اختبار لمنطق الحفظ ثم عدّل الكود (TDD)")
        self.assertEqual(self.edit("lib/store.dart")[0], 2)
        self.skill("test-driven-development")
        code, _, err = self.edit("lib/store.dart")
        self.assertEqual(code, 2)
        self.assertIn("failing test first", err)
        self.assertEqual(self.edit("test/store_test.dart")[0], 0)
        self.did_edit("test/store_test.dart")
        self.assertEqual(self.edit("lib/store.dart")[0], 0)


class TestUi(Base):
    def test_ui_files_need_design_skills_and_subagents_do_not_inherit(self):
        code, _, err = self.edit("lib/screens_home.dart")
        self.assertEqual(code, 2)
        self.assertIn("ui-ux-pro-max", err)
        self.skill("ui-ux-pro-max")
        self.assertEqual(self.edit("lib/screens_home.dart")[0], 2)  # android-design still missing
        self.skill("android-design")
        self.assertEqual(self.edit("lib/screens_home.dart")[0], 0)
        self.assertEqual(self.edit("lib/screens_home.dart", agent="sub1")[0], 2)  # sub-agent has its own state
        self.skill("ui-ux-pro-max", agent="sub1")
        self.skill("android-design", agent="sub1")
        self.assertEqual(self.edit("lib/screens_home.dart", agent="sub1")[0], 0)

    def test_motion_code_needs_motion_skill(self):
        self.skill("ui-ux-pro-max")
        self.skill("android-design")
        code, _, err = self.edit("lib/screens_home.dart", new="AnimatedContainer(duration: d)")
        self.assertEqual(code, 2)
        self.assertIn("medlog-motion-guidance", err)
        self.skill("medlog-motion-guidance")
        self.assertEqual(self.edit("lib/screens_home.dart", new="AnimatedContainer(duration: d)")[0], 0)

    def test_non_ui_and_docs_are_not_blocked(self):
        self.assertEqual(self.edit("README.md")[0], 0)
        self.assertEqual(self.edit("lib/store.dart")[0], 0)

    def test_design_task_cannot_touch_medical_data(self):
        self.prompt("تصميم واجهة جديدة للبطاقات")
        code, _, err = self.edit("assets/data/cards.json")
        self.assertEqual(code, 2)
        self.assertIn("medical", err)
        self.prompt("تصميم واجهة جديدة للبطاقات\nENFORCE-WAIVE: medical-logic المستخدم طلب ذلك")
        self.assertEqual(self.edit("assets/data/cards.json")[0], 0)

    def test_claude_cannot_waive_itself(self):
        self.prompt("تصميم واجهة")
        # a waiver text in a tool call is not a user prompt: no effect
        self.run_hook("record", {"tool_name": "Bash", "tool_input": {"command": "echo ENFORCE-WAIVE: * x"}})
        self.assertEqual(self.edit("assets/data/cards.json")[0], 2)


class TestProtectedAndDisabled(Base):
    def test_enforcement_files_protected(self):
        self.assertEqual(self.edit(".claude/enforce/rules.json")[0], 2)
        self.prompt("ENFORCE-WAIVE: config تعديل مقصود")
        self.assertEqual(self.edit(".claude/enforce/rules.json")[0], 0)

    def test_understand_skills_are_blocked_never_required(self):
        for name in ("understand", "understand-diff", "understand-anything:understand"):
            code, _, err = self.run_hook("gate", {"tool_name": "Skill", "tool_input": {"skill": name}})
            self.assertEqual(code, 2, name)
        self.prompt("ENABLE-UNDERSTAND: المالك طلب")
        self.assertEqual(self.run_hook("gate", {"tool_name": "Skill", "tool_input": {"skill": "understand"}})[0], 0)

    def test_rules_never_require_understand(self):
        rules = json.loads(rd(RULES))
        flat = json.dumps({k: v for k, v in rules.items() if k != "disabled_skills"})
        self.assertNotIn("understand", flat.lower())


class TestBashAndPython(Base):
    def test_bash_redirect_and_python_writes_are_gated(self):
        self.assertEqual(self.bash("echo x > lib/screens_home.dart")[0], 2)
        self.fresh()
        py = "python3 -c \"open('lib/screens_home.dart','w').write('x')\""
        self.assertEqual(self.bash(py)[0], 2)
        self.fresh()
        self.assertEqual(self.bash("sed -i 's/a/b/' lib/screens_home.dart")[0], 2)
        self.fresh()
        self.assertEqual(self.bash("python3 -c \"print(1)\"")[0], 0)  # no write, allowed

    def test_dynamic_python_write_is_caught_after_the_fact_with_git(self):
        cmd = "python3 -c \"import os;open(os.path.join('li'+'b','screens_home.dart'),'a').write('x')\""
        uid = self.tid()
        g = self.run_hook("gate", {"tool_name": "Bash", "tool_input": {"command": cmd}, "tool_use_id": uid})
        self.assertEqual(g[0], 0)  # path was not visible statically
        wr(os.path.join(self.d, "lib/screens_home.dart"), "x\n", "a")  # what the command did
        code, _, err = self.run_hook("record", {"tool_name": "Bash", "tool_input": {"command": cmd}, "tool_use_id": uid, "tool_response": {"stdout": "", "stderr": ""}})
        self.assertEqual(code, 2)
        self.assertIn("ui-ux-pro-max", err)


class TestReviewAndStop(Base):
    def many_changes(self, n=7):
        for i in range(n):
            self.did_edit("lib/store.dart" if i == 0 else "README.md", "line %d\n" % i)
        for i in range(n):
            p = os.path.join(self.d, "lib", "m%d.dart" % i)
            wr(p, "// m\n" * 3)
            self.run_hook("record", {"tool_name": "Write", "tool_input": {"file_path": p}})

    def test_large_change_needs_fresh_review_with_diff_actually_read(self):
        self.many_changes()
        self.assertEqual(self.bash("git commit -m x")[0], 2)
        self.skill("ponytail-review")
        code, _, err = self.bash("git commit -m x")
        self.assertEqual(code, 2)
        self.assertIn("not actually read", err)
        # a grep (even on a path) and a --stat do not count as reading the diff
        self.run_hook("record", {"tool_name": "Grep", "tool_input": {"pattern": "m", "path": os.path.join(self.d, "lib")}})
        self.bash("git diff --stat", response="1 file changed")
        self.bash("git diff -- . ':!lib/m0.dart'", response="diff")
        self.assertEqual(self.bash("git commit -m x")[0], 2)
        self.bash("git diff", response="diff --git")
        self.bash("git ls-files -o --exclude-standard", response="")
        for i in range(7):
            self.read("lib/m%d.dart" % i)
        self.assertEqual(self.bash("git commit -m x")[0], 0)

    def test_old_review_is_stale_after_new_edit(self):
        self.many_changes()
        self.skill("ponytail-review")
        self.bash("git diff", response="x")
        for i in range(7):
            self.read("lib/m%d.dart" % i)
        self.assertEqual(self.bash("git commit -m x")[0], 0)
        self.did_edit("lib/store.dart", "more\n")
        self.assertEqual(self.bash("git commit -m x")[0], 2)

    def test_small_change_commit_not_blocked(self):
        self.did_edit("lib/store.dart", "x\n")
        self.assertEqual(self.bash("git commit -m small")[0], 0)

    def test_stop_blocks_once_without_verification_then_never_loops(self):
        self.did_edit("lib/store.dart", "x\n")
        self.assertEqual(self.run_hook("stop", {"hook_event_name": "Stop"})[0], 2)
        self.assertEqual(self.run_hook("stop", {"hook_event_name": "Stop", "stop_hook_active": True})[0], 0)

    def test_verification_needs_skill_and_a_passing_check_after_last_edit(self):
        self.did_edit("lib/store.dart", "x\n")
        self.skill("verification-before-completion")
        self.assertEqual(self.run_hook("stop", {})[0], 2)  # skill alone is not evidence
        self.bash("flutter analyze", response="No issues found!")
        self.assertEqual(self.run_hook("stop", {})[0], 0)
        self.did_edit("lib/store.dart", "again\n")  # new change: old verification is stale
        self.assertEqual(self.run_hook("stop", {})[0], 2)

    def test_failed_check_is_not_evidence(self):
        self.did_edit("lib/store.dart", "x\n")
        self.skill("verification-before-completion")
        self.bash("flutter test", response="00:03 +2 -1: Some tests failed.")
        self.assertEqual(self.run_hook("stop", {})[0], 2)

    def test_docs_only_changes_need_nothing(self):
        self.did_edit("README.md", "doc\n")
        self.assertEqual(self.run_hook("stop", {})[0], 0)
        self.assertEqual(self.bash("git commit -m docs")[0], 0)

    def test_circuit_breaker_prevents_endless_denials(self):
        codes = [self.edit("lib/screens_home.dart")[0] for _ in range(4)]
        self.assertEqual(codes[:2], [2, 2])
        self.assertEqual(codes[3], 0)  # allowed (logged) after repeated denials


class TestSubagentStart(Base):
    def test_start_context_mentions_own_skills_and_disabled_understand(self):
        code, out, _ = self.run_hook("subagent-start", {"agent_id": "a1"})
        self.assertEqual(code, 0)
        ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("do NOT inherit", ctx)
        self.assertIn("understand", ctx)


class TestRobustness(Base):
    def test_garbage_input_never_blocks(self):
        env = dict(os.environ, CLAUDE_PROJECT_DIR=self.d, MEDLOG_ENFORCE_STATE=self.state)
        for cmd in ("gate", "record", "prompt", "stop", "subagent-start"):
            r = subprocess.run([sys.executable, ENFORCE, cmd], input=b"not json", env=env, capture_output=True)
            self.assertEqual(r.returncode, 0, cmd)


if __name__ == "__main__":
    unittest.main(verbosity=1)
