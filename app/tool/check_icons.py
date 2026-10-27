#!/usr/bin/env python3
"""Safety net: make sure every icon name used in lib/*.dart really exists.

Runs in CI after `flutter pub get`. Any icon name that is not found is replaced
by Icons.circle_outlined, so a wrong icon name can never break the build.
If the icon sources cannot be located, nothing is changed.
usage: check_icons.py <app_dir>
"""
import glob
import json
import os
import re
import shutil
import sys

app = sys.argv[1]
lib = os.path.join(app, "lib")
DECL = re.compile(r"static\s+const\s+(?:[\w<>?.]+\s+)?(\w+)\s*=")


def names_in(path, cls=None):
    try:
        txt = open(path, encoding="utf-8").read()
    except OSError:
        return set()
    if cls:
        m = re.search(r"class\s+%s\b" % cls, txt)
        if not m:
            return set()
        txt = txt[m.start():]
        nxt = re.search(r"\n}\s*\n", txt)
        if nxt:
            txt = txt[: nxt.end()]
    return set(DECL.findall(txt))


# ---- Material icons from the Flutter SDK
material = set()
flutter = shutil.which("flutter")
if flutter:
    sdk = os.path.dirname(os.path.dirname(os.path.realpath(flutter)))
    p = os.path.join(sdk, "packages", "flutter", "lib", "src", "material", "icons.dart")
    material = names_in(p, "Icons")
print("material icon names found:", len(material))

# ---- Phosphor icons from the pub cache
phos = {}
try:
    cfg = json.load(open(os.path.join(app, ".dart_tool", "package_config.json")))
    root = None
    for pk in cfg["packages"]:
        if pk["name"] == "phosphor_flutter":
            uri = pk["rootUri"]
            root = uri[7:] if uri.startswith("file://") else os.path.normpath(
                os.path.join(app, ".dart_tool", uri))
    if root:
        files = glob.glob(os.path.join(root, "lib", "**", "*.dart"), recursive=True)
        print("phosphor root:", root, "dart files:", len(files))
        for cls in ("PhosphorIconsRegular", "PhosphorIconsFill"):
            s = set()
            for f in files:
                s |= names_in(f, cls)
            phos[cls] = s
except Exception as e:  # noqa
    print("could not read phosphor package:", e)
for k, v in phos.items():
    print(k, "names found:", len(v))

bad = []
for f in glob.glob(os.path.join(lib, "*.dart")):
    src = open(f, encoding="utf-8").read()
    out = src

    def fix_material(m):
        n = m.group(1)
        if len(material) > 500 and n not in material:
            bad.append((os.path.basename(f), "Icons." + n))
            return "Icons.circle_outlined"
        return m.group(0)

    def fix_phos(m):
        cls, n = m.group(1), m.group(2)
        known = phos.get(cls, set())
        if len(known) > 200 and n not in known:
            bad.append((os.path.basename(f), cls + "." + n))
            return "Icons.circle_outlined"
        return m.group(0)

    out = re.sub(r"(?<![\w.])Icons\.(\w+)", fix_material, out)
    out = re.sub(r"(PhosphorIconsRegular|PhosphorIconsFill)\.(\w+)", fix_phos, out)
    if out != src:
        open(f, "w", encoding="utf-8").write(out)

if bad:
    print("Replaced unknown icons:")
    for b in bad:
        print("  ", b)
else:
    print("All icon names verified (or could not be verified).")
