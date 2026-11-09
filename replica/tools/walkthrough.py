#!/usr/bin/env python3
"""Turn a phone screen recording into a set of unique screens for recon.

usage: python3 walkthrough.py VIDEO APPNAME [--fps 2] [--min-diff 6]

Writes replica/screens/<APPNAME>/NNN_t<seconds>.png (one per distinct screen),
plus replica/screens/<APPNAME>/INDEX.md and contact-sheet-N.png.
Needs ffmpeg and Pillow. Reference material only: never shipped in the app.
"""
import warnings; warnings.filterwarnings("ignore")
import argparse, glob, os, subprocess, sys, tempfile
from PIL import Image

def dhash(im, n=16):
    g = im.convert("L").resize((n + 1, n))
    px = list(g.getdata())
    bits = 0
    for r in range(n):
        for c in range(n):
            bits = (bits << 1) | (px[r * (n + 1) + c] > px[r * (n + 1) + c + 1])
    return bits

def dist(a, b):
    return bin(a ^ b).count("1")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video"); ap.add_argument("app")
    ap.add_argument("--fps", type=float, default=2)
    ap.add_argument("--min-diff", type=int, default=6, help="hash bits (of 256) that must differ to count as a new screen")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "screens"))
    a = ap.parse_args()
    out = os.path.abspath(os.path.join(a.out, a.app)); os.makedirs(out, exist_ok=True)
    tmp = tempfile.mkdtemp()
    subprocess.run(["ffmpeg", "-loglevel", "error", "-i", a.video, "-vf", f"fps={a.fps}", "-q:v", "2",
                    os.path.join(tmp, "f%05d.jpg")], check=True)
    frames = sorted(glob.glob(os.path.join(tmp, "f*.jpg")))
    if not frames: sys.exit("no frames extracted")
    kept, last = [], None
    for i, f in enumerate(frames):
        im = Image.open(f); h = dhash(im)
        if last is None or dist(h, last) >= a.min_diff:
            t = i / a.fps
            name = f"{len(kept)+1:03d}_t{t:06.1f}.png"
            im.convert("RGB").save(os.path.join(out, name)); kept.append((name, t)); last = h
    with open(os.path.join(out, "INDEX.md"), "w") as fh:
        fh.write(f"# {a.app}: {len(kept)} distinct screens from {len(frames)} sampled frames\n\n")
        fh.write("Fill in the name, purpose and how you reached each screen.\n\n| file | time (s) | screen name | notes |\n| --- | --- | --- | --- |\n")
        for n, t in kept: fh.write(f"| {n} | {t:.1f} | | |\n")
    # contact sheets, 8 per sheet, so many screens can be reviewed at once
    for s in range(0, len(kept), 8):
        ims = [Image.open(os.path.join(out, n)).convert("RGB") for n, _ in kept[s:s+8]]
        th = 420; ims = [i.resize((int(i.width * th / i.height), th)) for i in ims]
        W = sum(i.width for i in ims) + 10 * (len(ims) + 1)
        sheet = Image.new("RGB", (W, th + 20), "white"); x = 10
        for i in ims: sheet.paste(i, (x, 10)); x += i.width + 10
        sheet.save(os.path.join(out, f"contact-sheet-{s//8+1}.png"))
    print(f"{len(kept)} screens -> {out}")

if __name__ == "__main__":
    main()
