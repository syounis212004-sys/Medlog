#!/usr/bin/env python3
"""MedLog skill enforcement for Claude Code hooks (python3 standard library only).

Commands (wired in .claude/settings.json):
  prompt          UserPromptSubmit   classify the task, read the USER's waivers, add a short reminder
  gate            PreToolUse         deny edits / risky Bash / commit-like actions when requirements are not met
  record          PostToolUse        record skills, real file reads, git-diff views, verification runs, Bash file changes
  subagent-start  SubagentStart      tell a sub-agent it must invoke its own skills (nothing is inherited)
  stop            Stop/SubagentStop  block ONCE if finished work was never verified or reviewed
  report          print a summary of the session logs

Design notes (see README.md):
  * Evidence beats invocation. A Skill call proves "invoked", not "applied". Review/verification also need
    fresh evidence: git diff / Read of the changed files, and a passing check run AFTER the last edit.
  * "Fresh" = tied to a fingerprint of the files changed this session; any later change makes the old
    review/verification stale. Old skill state never covers new changes.
  * Edits made through Bash/Python are seen two ways: static path scan before, and a before/after
    snapshot of changed files after (git is the source of truth).
  * Never a loop: Stop blocks once (stop_hook_active), a rule that denies 3 times in a row without a new
    skill call lets the action through with a logged warning, and an internal crash never blocks.
  * Only the human can waive: `ENFORCE-WAIVE: <rule|*> <reason>` / `ENABLE-UNDERSTAND: <reason>` in a prompt.
"""
import fcntl, fnmatch, hashlib, json, os, re, shlex, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.environ.get("CLAUDE_PROJECT_DIR") or os.path.join(HERE, "..", ".."))
ED = os.path.join(ROOT, ".claude", "enforce")
STATE_DIR = os.environ.get("MEDLOG_ENFORCE_STATE") or os.path.join(ED, "state")
LOG_DIR = os.path.join(STATE_DIR, "log")
EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
COMMIT_MCP = ("mcp__github__create_pull_request", "mcp__github__merge_pull_request", "mcp__github__push_files",
              "mcp__github__create_or_update_file")
RULE_IDS = ("ui", "motion", "debug", "tdd", "review", "verify", "audit", "medical-logic", "config", "understand", "*")


# ------------------------------------------------------------------ basics
def now():
    return int(time.time())


def out_json(event, **kw):
    sys.stdout.write(json.dumps({"hookSpecificOutput": dict(hookEventName=event, **kw)}, ensure_ascii=False))


def deny(msg):
    sys.stderr.write("BLOCKED by MedLog skill enforcement: " + msg + "\n")
    sys.exit(2)


def log(name, rec):
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        rec["ts"] = now()
        with open(os.path.join(LOG_DIR, name), "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass


def load_rules(strict=False):
    try:
        with open(os.path.join(ED, "rules.json"), encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        if strict:
            deny("rules.json is unreadable (%s). Fix it (needs the user's ENFORCE-WAIVE: config)." % e)
        return None


class State:
    """Per-session JSON state, exclusive-locked (sub-agent hooks may run at the same time)."""

    def __init__(self, sid):
        os.makedirs(STATE_DIR, exist_ok=True)
        self.path = os.path.join(STATE_DIR, re.sub(r"[^A-Za-z0-9_.-]", "_", sid or "nosession") + ".json")
        self.fh = open(self.path, "a+", encoding="utf-8")
        fcntl.flock(self.fh, fcntl.LOCK_EX)
        self.fh.seek(0)
        raw = self.fh.read()
        try:
            self.d = json.loads(raw) if raw.strip() else {}
        except Exception:
            self.d = {}
        for k, v in (("actors", {}), ("waivers", {}), ("task", {"id": 0, "types": [], "weak_debug": False}),
                     ("baseline", None), ("file_ts", {}), ("session_files", {})):
            self.d.setdefault(k, v)

    def actor(self, key):
        return self.d["actors"].setdefault(key, {"skills": {}, "reads": {}, "diffs": [], "tests": [], "verifies": [],
                                                 "explore": [], "test_edit_ts": [], "denies": {}, "edits": {}})

    def save(self):
        self.fh.seek(0)
        self.fh.truncate()
        self.fh.write(json.dumps(self.d, ensure_ascii=False))
        self.fh.flush()
        fcntl.flock(self.fh, fcntl.LOCK_UN)
        self.fh.close()


def actor_key(p):
    return p.get("agent_id") or "main"


def norm(s):
    return (s or "").strip().lower()


def skill_name(s):
    s = norm(s)
    return s.split(":")[-1]


# ------------------------------------------------------------------ paths and classes
def roots(rules):
    rs = [(ROOT, True)]
    for r in (rules or {}).get("extra_roots", []):
        ap = os.path.abspath(os.path.join(ROOT, r))
        if os.path.isdir(ap) and ap != ROOT:
            rs.append((ap, False))
    return rs


def vpath(rules, path):
    """Virtual path used by the rules, or None when outside every watched root."""
    if not path:
        return None
    ap = os.path.abspath(path if os.path.isabs(path) else os.path.join(ROOT, path))
    best = None
    for r, is_main in roots(rules):
        rel = os.path.relpath(ap, r)
        if not rel.startswith(".."):
            rel = rel.replace(os.sep, "/")
            if is_main and rel.startswith("app/"):
                rel = rel[4:]
            if best is None or len(r) > len(best[1]):
                best = (rel, r)
    return best[0] if best else None


def gm(globs, v):
    return any(fnmatch.fnmatch(v, g) for g in globs)


def classify(rules, v):
    """Set of classes for a virtual path."""
    c = set()
    if gm(rules.get("protected", []), v):
        c.add("protected")
    if gm(rules.get("exempt", []), v) and v not in rules.get("package_files", []):
        c.add("exempt")
    for k, gl in rules.get("classes", {}).items():
        if gm(gl, v):
            c.add(k)
    if v in rules.get("package_files", []):
        c.add("package")
    if gm(rules.get("audit_paths", []), v):
        c.add("audit")
    return c


# ------------------------------------------------------------------ git: what really changed
def git(root, *args, timeout=15):
    try:
        r = subprocess.run(["git", "-C", root] + list(args), capture_output=True, timeout=timeout)
        return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else ""
    except Exception:
        return ""


_hcache = {}


def fhash(path):
    try:
        st = os.stat(path)
    except OSError:
        return "gone"
    key = (path, st.st_size, st.st_mtime_ns)
    if key not in _hcache:
        h = hashlib.sha1()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        _hcache[key] = h.hexdigest()[:16]
    return _hcache[key]


def changed_map(rules):
    """{virtual path: content hash} of every file that differs from HEAD (tracked or untracked) in the watched roots."""
    m = {}
    for r, _ in roots(rules):
        raw = git(r, "status", "--porcelain=v1", "-z", "-uall")
        if not raw:
            continue
        items = raw.split("\0")
        i = 0
        while i < len(items):
            e = items[i]
            i += 1
            if len(e) < 4:
                continue
            code, path = e[:2], e[3:]
            if code[0] in "RC":
                i += 1  # skip the source name of a rename/copy
            ap = os.path.join(r, path)
            v = vpath(rules, ap)
            if v:
                m[v] = fhash(ap)
    return m


def session_changed(st, rules, cur=None):
    """Files changed THIS session: new or different from the session-start baseline. Exempt files are ignored."""
    cur = cur if cur is not None else changed_map(rules)
    base = st.d.get("baseline") or {}
    out = {}
    for v, h in cur.items():
        if "exempt" in classify(rules, v):
            continue
        if base.get(v) != h:
            out[v] = h
    return out


def fingerprint(files):
    return hashlib.sha1(json.dumps(sorted(files.items())).encode()).hexdigest()[:16]


def line_stats(rules, files):
    """Rough size of the change: added+removed lines (numstat) plus a weight for the package zip."""
    total, n = 0, 0
    cfg = rules.get("large_change", {})
    for r, _ in roots(rules):
        for ln in git(r, "diff", "--numstat", "HEAD").splitlines():
            a = ln.split("\t")
            if len(a) == 3 and a[0].isdigit() and a[1].isdigit():
                v = vpath(rules, os.path.join(r, a[2]))
                if v in files:
                    total += int(a[0]) + int(a[1])
    for v in files:
        if v in rules.get("package_files", []):
            total += cfg.get("package_weight", 300)
        else:
            for r, _ in roots(rules):
                ap = os.path.join(r, v if r != ROOT else v)
                for cand in (ap, os.path.join(r, "app", v)):
                    if os.path.isfile(cand) and not git(r, "ls-files", "--error-unmatch", os.path.relpath(cand, r)):
                        try:
                            with open(cand, "rb") as f:
                                total += min(f.read().count(b"\n"), 2000)
                        except OSError:
                            pass
                        break
        n += 1
    return total, n


def is_large(rules, files):
    cfg = rules.get("large_change", {})
    lines, n = line_stats(rules, files)
    return (lines >= cfg.get("lines", 150) or n >= cfg.get("files", 6)), lines, n


# ------------------------------------------------------------------ requirements
def has_skill(A, want, task_id=None):
    e = A["skills"].get(skill_name(want))
    if not e:
        return False
    return task_id is None or e.get("task") == task_id


def waived(st, rule):
    w = st.d["waivers"]
    return rule in w or "*" in w


def texts_of(tool, ti):
    if tool == "Write":
        return [ti.get("content", "")]
    if tool == "Edit":
        return [ti.get("new_string", "")]
    if tool == "MultiEdit":
        return [e.get("new_string", "") for e in ti.get("edits", [])]
    if tool == "NotebookEdit":
        return [ti.get("new_source", "")]
    return []


def need_for(st, rules, v, texts):
    """{skill: (rule id, why)} required before editing virtual path v."""
    c = classify(rules, v)
    need = {}
    if "exempt" in c or "protected" in c:
        return need
    task = st.d["task"]
    is_lib = v.startswith("lib/")
    if "ui" in c:
        for s in rules.get("ui_skills", []):
            need[s] = ("ui", "Flutter UI: design skills first (principles only, never Compose code)")
    mo = rules.get("motion", {})
    if is_lib and mo.get("pattern") and re.search(mo["pattern"], "\n".join(texts)):
        need[mo["skill"]] = ("motion", "motion/animation code must follow the MedLog motion rules")
    if "debug" in task["types"] and ("code" in c or "test" in c) and is_lib:
        need["systematic-debugging"] = ("debug", "this prompt reports a real bug: systematic-debugging before editing")
    if "tdd" in task["types"] and ("code" in c or "test" in c):
        need["test-driven-development"] = ("tdd", "this task asks for tests: test-driven-development")
    if "audit" in task["types"] and "audit" in c:
        need["ponytail-audit"] = ("audit", "audit reports need ponytail-audit")
    return need


def evidence_problems(st, A, rules, v, c):
    """Extra evidence (beyond the Skill call) that the skill was really applied before editing."""
    task, probs = st.d["task"], []
    tid = task["id"]
    if "debug" in task["types"] and v.startswith("lib/") and ("code" in c) and not waived(st, "debug"):
        investigated = any(e["task"] == tid for e in A["reads"].values()) or any(e["task"] == tid for e in A["tests"]) \
            or any(e["task"] == tid for e in A["explore"])
        if not investigated:
            probs.append(("debug", "systematic-debugging needs investigation first: Read the failing code or logs, or "
                                   "run the failing check, before the first fix edit (root cause before fix)"))
    if "tdd" in task["types"] and v.startswith("lib/") and "test" not in c and not waived(st, "tdd"):
        had_test = any(t >= task.get("start", 0) for t in A["test_edit_ts"]) or any(e["task"] == tid for e in A["tests"])
        if not had_test:
            probs.append(("tdd", "test-driven-development: write the failing test first (edit a file under test/) and "
                                 "run it before changing production code"))
    return probs


def breaker(st, A, rules, rule):
    """3 denials in a row for one rule with no new skill call: let it through (logged) instead of looping."""
    n = A["denies"].get(rule, 0) + 1
    A["denies"][rule] = n
    if n >= rules.get("breaker", 3):
        log("breaker.jsonl", {"rule": rule, "actor": "?", "denies": n})
        return True
    return False


# ------------------------------------------------------------------ Bash analysis
PATHY = re.compile(r"[\w.@+/-]+\.(?:dart|json|yaml|yml|zip|csv|md|py|sh|txt|arb|gradle|xml|png)\b|\b(?:lib|test|assets|tool|app|\.claude)/[\w./-]*")
WRITEY = re.compile(r"open\([^)]*['\"][wax]b?\+?['\"]|write_text|write_bytes|json\.dump|\.write\(|os\.(rename|replace|remove)|shutil\.(copy|move|rmtree)|"
                    r"writeFile|appendFile|fs\.(rename|unlink)|File\([^)]*\)\.write|>>?\s*['\"]")


def bash_targets(cmd):
    """Best-effort static list of paths a shell/python/node command writes. Over-approximation is limited to writes."""
    t = set()
    for m in re.finditer(r"(?<![0-9&<>])>>?\s*(['\"]?)([^\s'\"|;&<>]+)\1", cmd):
        if not m.group(2).startswith("&") and m.group(2) not in ("/dev/null",):
            t.add(m.group(2))
    try:
        toks = shlex.split(cmd, posix=True)
    except ValueError:
        toks = cmd.split()
    for i, w in enumerate(toks):
        base = os.path.basename(w)
        rest = [x for x in toks[i + 1:] if not x.startswith("-") and x not in ("&&", ";", "|", "||")]
        stop = next((k for k, x in enumerate(toks[i + 1:]) if x in ("&&", ";", "|", "||")), None)
        seg = [x for x in toks[i + 1:(i + 1 + stop) if stop is not None else None] if not x.startswith("-")]
        if base == "tee":
            t.update(seg)
        elif base in ("rm", "touch", "mkdir", "truncate", "patch"):
            t.update(seg)
        elif base in ("cp", "mv", "install", "rsync", "ln") and seg:
            t.add(seg[-1])
            if base == "mv":
                t.update(seg[:-1])
        elif base in ("sed", "perl") and any(x.startswith("-") and "i" in x[1:] and not x.startswith("--") for x in toks[i + 1:i + 4]):
            t.update(x for x in seg[1:] if "/" in x or "." in x)
        elif base == "git" and i + 1 < len(toks) and toks[i + 1] in ("apply", "checkout", "restore", "rm", "mv"):
            t.update(x for x in seg[1:] if "/" in x or "." in x)
        elif base in ("unzip", "zip") and seg:
            t.add(seg[0] if base == "zip" else (seg[0]))
        elif base.startswith(("python", "node", "ruby", "perl")) and WRITEY.search(cmd):
            t.update(m.group(0) for m in PATHY.finditer(cmd))
    return {x for x in t if x}


def call_key(p, cmd):
    return p.get("tool_use_id") or hashlib.sha1(cmd.encode()).hexdigest()[:12]


def diff_cover(cmd, rules):
    """None = not a diff view; 'all' = whole tree; else the explicit set of paths shown. Excludes/--stat do not count."""
    if not re.search(rules.get("diffview_commands", "git\\s+(diff|show)"), cmd) or re.search(r"git\s+status", cmd) and not re.search(r"git\s+(diff|show)", cmd):
        return None
    if re.search(r"--(stat|numstat|shortstat|name-only|name-status|summary|check)|:\(exclude\)|':!|\":!|--exclude", cmd):
        return None
    m = re.search(r"git\s+(?:-C\s+\S+\s+)?(?:diff|show)\b(.*)", cmd)
    args = shlex.split(m.group(1).split("|")[0].split("&&")[0], posix=True) if m else []
    paths = []
    after = False
    for a in args:
        if a == "--":
            after = True
            continue
        if after or (not a.startswith("-") and "/" in a or re.search(r"\.\w+$", a)):
            paths.append(a)
    return set(paths) if paths else "all"


def out_text(resp):
    if isinstance(resp, dict):
        return "\n".join(str(resp.get(k, "")) for k in ("stdout", "stderr", "output", "content") if resp.get(k))
    return str(resp or "")


FAIL = re.compile(r"Some tests failed|\[E\]|\bFAILED\b|Traceback \(most recent|error •|^Error:|AssertionError|exited with code [1-9]|\d+ issues? found", re.M)


def command_ok(resp):
    if isinstance(resp, dict) and (resp.get("interrupted") or resp.get("is_error")):
        return False
    return not FAIL.search(out_text(resp))


# ------------------------------------------------------------------ hook: prompt
def classify_prompt(rules, prompt):
    t = rules.get("tasks", {})
    types = []
    p = prompt or ""
    strong = bool(re.search(t.get("debug_strong", "$^"), p, re.I))
    weak = len(re.findall(t.get("debug_weak", "$^"), p, re.I))
    if strong or weak >= 2:
        types.append("debug")
    if re.search(t.get("tdd", "$^"), p, re.I):
        types.append("tdd")
    if re.search(t.get("design", "$^"), p, re.I) and not re.search(t.get("logic_words", "$^"), p, re.I):
        types.append("design")
    if re.search(t.get("audit", "$^"), p, re.I):
        types.append("audit")
    return types, (weak == 1 and not strong)


def cmd_prompt(p):
    rules = load_rules()
    if not rules:
        return
    st = State(p.get("session_id"))
    try:
        prompt = p.get("prompt", "")
        for m in re.finditer(r"^\s*ENFORCE-WAIVE:\s*(\S+)\s+(\S.*)$", prompt, re.M):
            rid = m.group(1).strip().lower()
            if rid in RULE_IDS:
                st.d["waivers"][rid] = m.group(2).strip()[:200]
                log("waivers.jsonl", {"rule": rid, "reason": m.group(2).strip()[:200]})
        if re.search(r"^\s*ENABLE-UNDERSTAND:\s*\S+", prompt, re.M):
            st.d["waivers"]["understand"] = "enabled by the user"
            log("waivers.jsonl", {"rule": "understand"})
        types, weak = classify_prompt(rules, prompt)
        old = st.d["task"]
        st.d["task"] = {"id": old["id"] + 1, "types": types, "weak_debug": weak, "start": now()}
        if st.d["baseline"] is None:
            st.d["baseline"] = changed_map(rules)
        notes = []
        if "debug" in types:
            notes.append("Bug report detected: invoke systematic-debugging and investigate (read code/logs, reproduce) before editing lib/.")
        elif weak:
            notes.append("If this is a real bug (not a small wording or content change), use systematic-debugging first. Not enforced for plain 'fix' wording.")
        if "tdd" in types:
            notes.append("Tests requested: invoke test-driven-development; write and run the failing test before production code. The hook checks the order, not the quality.")
        if "design" in types:
            notes.append("Design task: ui-ux-pro-max + android-design (principles only) before Flutter UI edits; medlog-motion-guidance for animation. Medical data/logic files are locked during design-only tasks.")
        if "audit" in types:
            notes.append("Audit task: use ponytail-audit for the audit report.")
        notes.append("Before finishing code changes: verification-before-completion (fresh passing check after the last edit). Large changes: ponytail-review before commit. Understand-Anything/understand-diff are disabled.")
        out_json("UserPromptSubmit", additionalContext="MedLog enforcement: " + " ".join(notes))
    finally:
        st.save()


# ------------------------------------------------------------------ hook: gate
def missing_for(st, A, need):
    tid = st.d["task"]["id"]
    out = []
    for s, (rule, why) in need.items():
        if waived(st, rule):
            continue
        task_scoped = rule in ("debug", "tdd")
        if not has_skill(A, s, tid if task_scoped else None):
            out.append((s, rule, why))
    return out


def howto(miss):
    return "Invoke with the Skill tool: " + ", ".join(sorted({s for s, _, _ in miss})) + ". Then retry. (Only the user can waive: ENFORCE-WAIVE: <rule> <reason>.)"


def check_paths(st, A, rules, paths, texts, tool):
    """Returns ('deny', msg) | ('warn', msg) | None for a set of virtual paths about to be written."""
    miss, probs, locked, protected = [], [], [], []
    task = st.d["task"]
    for v in sorted(paths):
        c = classify(rules, v)
        if "protected" in c and not waived(st, "config"):
            protected.append(v)
        if "medical" in c and "design" in task["types"] and "debug" not in task["types"] and "tdd" not in task["types"] \
                and not waived(st, "medical-logic") and not waived(st, "*"):
            locked.append(v)
        miss += missing_for(st, A, need_for(st, rules, v, texts))
        probs += [x for x in evidence_problems(st, A, rules, v, c) if not waived(st, x[0])]
    if protected:
        return "deny", "enforcement/config files are protected (%s). Only the user can unlock: ENFORCE-WAIVE: config <reason>." % ", ".join(protected)
    if locked:
        return "deny", ("this is a design-only task and %s is medical data/logic. Design work must not change medical content "
                        "or logic. If the user really wants that, they write ENFORCE-WAIVE: medical-logic <reason>." % ", ".join(locked))
    for rule in ("ui", "motion", "debug", "tdd", "audit"):
        mm = [m for m in miss if m[1] == rule]
        pp = [x for x in probs if x[0] == rule]
        if mm or pp:
            if breaker(st, A, rules, rule):
                return "warn", "rule '%s' kept blocking; allowed once (logged). Invoke: %s" % (rule, ", ".join(sorted({m[0] for m in mm})) or rule)
            if mm:
                return "deny", "%s %s" % (mm[0][2], howto(mm))
            return "deny", pp[0][1]
    return None


def commit_gate(st, A, rules, what):
    """Before commit/push/PR: edited files still need their skills, and a LARGE change needs a fresh, evidenced ponytail-review."""
    files = session_changed(st, rules)
    if not files:
        return None
    fp = fingerprint(files)
    msgs = []
    for v in sorted(files):
        if v in A["edits"] or st.d["session_files"].get(v):
            m = missing_for(st, A, need_for(st, rules, v, []))
            msgs += [x for x in m if x[1] in ("ui",)]
    large, lines, n = is_large(rules, files)
    if large and not waived(st, "review"):
        rv = A["skills"].get("ponytail-review")
        fresh = bool(rv) and rv.get("fp") == fp
        if not fresh:
            msgs.append(("ponytail-review", "review", "large change (%d files, ~%d lines) needs ponytail-review of THIS diff (earlier reviews do not cover new edits)" % (n, lines)))
        else:
            unseen = unviewed(st, A, rules, files)
            if unseen:
                msgs.append(("ponytail-review", "review", "ponytail-review was invoked but the diff was not actually read: run `git diff` (no --stat, no excludes) or Read: " + ", ".join(unseen[:6])))
    if not msgs:
        return None
    if breaker(st, A, rules, "review"):
        return "warn", "review rule kept blocking; allowed once (logged)"
    first = msgs[0]
    return "deny", "%s before %s. %s" % (first[2], what, howto(msgs) if first[0] != "ponytail-review" or "invoked but" not in first[2] else "")


def unviewed(st, A, rules, files):
    """Changed files whose latest edit was not covered by a git diff view or a Read made after that edit."""
    seen = []
    for v in files:
        if "package" in classify(rules, v):
            continue
        ts = st.d["file_ts"].get(v, 0)
        ok = any(d["ts"] >= ts and (d["cover"] == "all" or any(v.endswith(x.lstrip("./")) or x.endswith(v) for x in d["cover"])) for d in A["diffs"])
        ok = ok or (A["reads"].get(v, {}).get("ts", 0) >= ts and v in A["reads"])
        if not ok:
            seen.append(v)
    return seen


def cmd_gate(p):
    rules = load_rules(strict=False)
    tool, ti = p.get("tool_name", ""), p.get("tool_input") or {}
    if rules is None:
        if tool in EDIT_TOOLS:
            deny("rules.json is unreadable. Fix it (needs the user's ENFORCE-WAIVE: config).")
        return
    st = State(p.get("session_id"))
    try:
        A = st.actor(actor_key(p))
        if st.d["baseline"] is None:
            st.d["baseline"] = changed_map(rules)
        verdict = None
        if tool == "Skill":
            name = skill_name(ti.get("skill") or ti.get("name"))
            if name in rules.get("disabled_skills", []) and not st.d["waivers"].get("understand"):
                verdict = ("deny", "'%s' is disabled in this project. Understand-Anything / understand-diff run only after the owner writes ENABLE-UNDERSTAND: <reason>." % name)
        elif tool in EDIT_TOOLS:
            tp = ti.get("file_path") or ti.get("notebook_path")
            v = vpath(rules, tp)
            if v:
                verdict = check_paths(st, A, rules, {v}, texts_of(tool, ti), tool)
        elif tool == "Bash":
            cmd = ti.get("command", "")
            targets = {vpath(rules, x) for x in bash_targets(cmd)} - {None}
            if targets:
                verdict = check_paths(st, A, rules, targets, [cmd], tool)
            if not verdict and re.search(r"(^|[;&|]\s*)(git\s+(-C\s+\S+\s+)?(commit|push)\b|gh\s+(pr\s+(create|merge)|release))", cmd):
                verdict = commit_gate(st, A, rules, "commit/push")
            if not verdict and re.search(rules.get("bash_mutation_hint", "$^"), cmd):
                A.setdefault("pending", {})[call_key(p, cmd)] = changed_map(rules)
        elif tool in COMMIT_MCP:
            verdict = commit_gate(st, A, rules, tool.replace("mcp__github__", "GitHub "))
        if verdict:
            kind, msg = verdict
            log("decisions.jsonl", {"tool": tool, "actor": actor_key(p), "verdict": kind, "msg": msg[:300]})
            if kind == "deny":
                st.save()
                st = None
                deny(msg)
            out_json("PreToolUse", permissionDecision="allow", permissionDecisionReason="MedLog enforcement warning: " + msg)
    finally:
        if st is not None:
            st.save()


# ------------------------------------------------------------------ hook: record
def cmd_record(p):
    rules = load_rules()
    if not rules:
        return
    tool, ti = p.get("tool_name", ""), p.get("tool_input") or {}
    st = State(p.get("session_id"))
    msg = None
    try:
        key = actor_key(p)
        A = st.actor(key)
        tid = st.d["task"]["id"]
        if st.d["baseline"] is None:
            st.d["baseline"] = {}
        if tool == "Skill":
            name = skill_name(ti.get("skill") or ti.get("name"))
            files = session_changed(st, rules)
            A["skills"][name] = {"ts": now(), "task": tid, "fp": fingerprint(files)}
            A["denies"] = {}
            log("skills.jsonl", {"actor": key, "skill": name, "fp": A["skills"][name]["fp"], "changed": len(files)})
        elif tool in EDIT_TOOLS:
            v = vpath(rules, ti.get("file_path") or ti.get("notebook_path"))
            if v:
                note_edit(st, A, rules, v)
        elif tool == "Read":
            v = vpath(rules, ti.get("file_path"))
            if v:
                A["reads"][v] = {"ts": now(), "task": tid}
        elif tool in ("Grep", "Glob"):
            # exploration only: never counted as "file reviewed" (a path or exclusion inside grep proves nothing)
            A["explore"].append({"ts": now(), "task": tid})
            A["explore"] = A["explore"][-20:]
        elif tool == "Bash":
            cmd = ti.get("command", "")
            resp = p.get("tool_response")
            ok = command_ok(resp)
            cover = diff_cover(cmd, rules)
            if cover is not None:
                A["diffs"].append({"ts": now(), "cover": "all" if cover == "all" else sorted(cover), "task": tid})
                A["diffs"] = A["diffs"][-30:]
            if re.search(r"(flutter|dart)\s+test", cmd):
                A["tests"].append({"ts": now(), "task": tid, "ok": ok, "cmd": cmd[:120]})
            if re.search(rules.get("verify_commands", "$^"), cmd):
                A["verifies"].append({"ts": now(), "ok": ok, "cmd": cmd[:120]})
                A["verifies"] = A["verifies"][-20:]
            snap = A.get("pending", {}).pop(call_key(p, cmd), None)
            if snap is not None:
                after = changed_map(rules)
                delta = [v for v in set(after) | set(snap) if after.get(v) != snap.get(v)]
                for v in delta:
                    note_edit(st, A, rules, v, via="bash")
                msg = bash_debt(st, A, rules, delta)
    finally:
        st.save()
    if msg:
        sys.stderr.write(msg + "\n")
        sys.exit(2)


def note_edit(st, A, rules, v, via="tool"):
    c = classify(rules, v)
    ts = now()
    st.d["file_ts"][v] = ts
    st.d["session_files"][v] = True
    A["edits"][v] = ts
    if "test" in c:
        A["test_edit_ts"].append(ts)


def bash_debt(st, A, rules, delta):
    """A Bash/Python command changed files: tell the agent right away what is missing (the commit/stop gates enforce it)."""
    miss = []
    for v in delta:
        c = classify(rules, v)
        if "protected" in c and not waived(st, "config"):
            return "MedLog enforcement: a Bash command changed protected enforcement files (%s). Revert them; only the user can unlock (ENFORCE-WAIVE: config)." % v
        miss += missing_for(st, A, need_for(st, rules, v, []))
    if miss:
        s = sorted({m[0] for m in miss})
        return "MedLog enforcement: the Bash/Python command changed files that need skills you have not invoked: %s. Invoke them now and re-check those edits (commit and stop are blocked until you do)." % ", ".join(s)
    return None


# ------------------------------------------------------------------ hook: subagents and stop
def cmd_subagent_start(p):
    rules = load_rules()
    if not rules:
        return
    ctx = ("You are a sub-agent. You do NOT inherit the main agent's skills: invoke the Skill tool yourself before editing. "
           "Flutter UI files need ui-ux-pro-max + android-design (principles only); animation code needs medlog-motion-guidance; "
           "real bug fixes need systematic-debugging and investigation first; tests-first tasks need test-driven-development; "
           "before you finish code changes run verification-before-completion with a fresh passing check. "
           "Do not change medical data/logic in design tasks. Do not call understand-anything or understand-diff (disabled).")
    out_json("SubagentStart", additionalContext=ctx)


def cmd_stop(p):
    rules = load_rules()
    if not rules:
        return
    st = State(p.get("session_id"))
    msg = None
    try:
        A = st.actor(actor_key(p))
        files = session_changed(st, rules)
        if not files:
            return
        if p.get("stop_hook_active"):
            log("decisions.jsonl", {"tool": "Stop", "verdict": "allowed-second-stop", "actor": actor_key(p)})
            return
        fp = fingerprint(files)
        probs = []
        code = [v for v in files if {"code", "test", "package"} & classify(rules, v)]
        mine = actor_key(p) == "main" or any(v in A["edits"] for v in files)
        if code and mine and not waived(st, "verify"):
            vs = A["skills"].get("verification-before-completion")
            last = max([st.d["file_ts"].get(v, 0) for v in code] or [0])
            good = [x for x in A["verifies"] if x["ts"] >= last and x["ok"]] + [x for x in A["tests"] if x["ts"] >= last and x["ok"]]
            if not vs or vs.get("fp") != fp:
                probs.append("invoke verification-before-completion AFTER your last edit (an earlier call does not cover these changes)")
            if not good:
                probs.append("run a real check after the last edit and see it pass (flutter analyze / flutter test for the touched area, or a JSON/diff check for data files); the skill call alone is not evidence")
        large, lines, n = is_large(rules, files)
        if large and mine and not waived(st, "review"):
            rv = A["skills"].get("ponytail-review")
            if not rv or rv.get("fp") != fp:
                probs.append("large change (%d files, ~%d lines): ponytail-review of this diff before finishing" % (n, lines))
            elif unviewed(st, A, rules, files):
                probs.append("ponytail-review was invoked but the diff was not read: run `git diff` or Read the changed files")
        if probs:
            msg = "uncommitted work is not verified yet: " + "; ".join(probs) + ". (Stop is blocked once; the user can waive with ENFORCE-WAIVE: verify|review <reason>.)"
            log("decisions.jsonl", {"tool": "Stop", "verdict": "block", "actor": actor_key(p), "msg": msg[:300]})
    finally:
        st.save()
    if msg:
        deny(msg)


def cmd_report(_p=None):
    for name in ("skills.jsonl", "decisions.jsonl", "waivers.jsonl", "breaker.jsonl"):
        path = os.path.join(LOG_DIR, name)
        n = sum(1 for _ in open(path, encoding="utf-8")) if os.path.exists(path) else 0
        print("%-16s %d entries" % (name, n))
    print("A skills.jsonl entry proves a skill was INVOKED, not that its guidance was applied well.")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "report":
        return cmd_report()
    try:
        p = json.load(sys.stdin)
    except Exception:
        return
    fn = {"prompt": cmd_prompt, "gate": cmd_gate, "record": cmd_record, "subagent-start": cmd_subagent_start, "stop": cmd_stop}.get(cmd)
    if not fn:
        return
    try:
        fn(p)
    except SystemExit:
        raise
    except Exception as e:  # an internal crash must never brick a session
        log("errors.jsonl", {"cmd": cmd, "error": repr(e)[:300]})


if __name__ == "__main__":
    main()
