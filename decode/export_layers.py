# Lens — layer overlay for the Dygma Defy
# Copyright (C) 2026 Gary Berger
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: GPL-3.0-or-later

import re
import json, os, sys, glob
S = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, S)
cm = {int(k): v for k, v in json.load(open(S + "/codemap.json")).items()}

def label(c):
    if c == 0:      return ""
    if c == 65535:  return "▽"
    if 17450 <= c <= 17459: return f"⇧L{c-17449}"
    if 17408 <= c <= 17417: return f"→L{c-17407}"
    if 17492 <= c <= 17501: return f"⇩L{c-17491}"
    if c == 17152: return "L+"
    if 49161 <= c <= 49170: return f"1×L{c-49160}"
    if 53852 <= c <= 53979: return f"M{c-53851}"
    if 53980 <= c <= 54107: return f"SK{c-53979}"
    if c == 54108: return "Batt"
    if c == 54109: return "BT"
    if c == 54111: return "Enrgy"
    if c == 54112: return "RF"
    return cm.get(c, f"?{c}")

SHORT = {"Left Shift":"⇧","Right Shift":"⇧","Left Control":"⌃","Right Control":"⌃",
 "Left Cmd":"⌘","Right Cmd":"⌘","Left Opt":"⌥","Right Opt":"⌥",
 "Left Command":"⌘","Right Command":"⌘","Left Option":"⌥","Right Option":"⌥",
 "Left Gui":"⌘","Right Gui":"⌘","Left Alt":"⌥","Right Alt":"⌥","AltGr":"⌥gr",
 "Backspace":"⌫","ENTER":"⏎","TAB":"⇥","SPACE":"␣","ESC":"esc","Delete":"⌦","Caps Lock":"caps",
 "Control / ENTER":"⌃/⏎","Control / Backspace":"⌃/⌫","Alt / ENTER":"⌥/⏎",
 "Play / pause":"▶︎","Next track":"⏭","Prev. track":"⏮","Volume up":"🔊","Volume down":"🔉","Mute":"🔇",
 "Bright +":"☀︎+","Bright -":"☀︎-","Shut Down":"⏻","Sleep":"zzz","Control + →":"⌃→","Control + ←":"⌃←",
 "Page Up":"pgup","Page Down":"pgdn","Up Arrow":"↑","Down Arrow":"↓","Left Arrow":"←","Right Arrow":"→",
 "Num Lock":"num","Print Screen":"prt","Scroll Lock":"scrl","Shuffle":"🔀","Stop":"⏹"}

import glob
BK = sorted(glob.glob(os.path.expanduser(
    "~/Dygma/Backups/Defy/*/*.json")), key=os.path.getmtime, reverse=True)
if not BK: raise SystemExit("no Dygma backup found under ~/Dygma/Backups")

def read(path):
    """Return the keymap, or None if the file is not a clean 16-bit read."""
    try:
        bk = json.load(open(path))
        km = [e for e in bk["backup"] if e["command"] == "keymap.custom"][0]["data"]
        c = [int(x) for x in km.split()]
    except Exception:
        return None
    if len(c) % 80 or len(c) < 80:            # must be whole layers of 80 keys
        return None
    bad = [(i, v) for i, v in enumerate(c) if not 0 <= v <= 65535]
    if bad:
        print(f"  skipping {os.path.basename(path)}: {len(bad)} impossible value(s), "
              f"first at index {bad[0][0]} = {bad[0][1]}")
        return None
    return c

codes, src = None, None
for cand in BK:
    codes = read(cand)
    if codes: src = cand; break
if not codes: raise SystemExit("no clean backup found")
print("source backup:", os.path.basename(src), f"({len(codes)//80} layers)")
LEFT  = [[0,1,2,3,4,5,6],[16,17,18,19,20,21,22],[32,33,34,35,36,37,38],[48,49,50,51,52,53],[64,65,66,67,68,69,70,71]]
RIGHT = [[9,10,11,12,13,14,15],[25,26,27,28,29,30,31],[41,42,43,44,45,46,47],[57,58,59,60,61,62,63],[72,73,74,75,76,77,78,79]]

DUAL = [49169, 49425, 49681, 49937, 50705] + [51218 + 256*n for n in range(10)]

def hid(c):
    """The USB usage this position sends when tapped. 0 when it sends none."""
    if 4 <= c <= 231:            return c            # plain keys and modifiers
    if 256 <= c < 8192:          return c & 0xFF     # shifted / modified keys
    for b in DUAL:                                   # tap half of a dual-use key
        if b <= c < b + 256:     return c - b
    return 0


# ── Real Defy geometry, ported from Bazecor src/lens/renderer/geometry-defy.ts ──
X = [105,171,236,301,366,431,497,718,783,848,913,978,1043,1107]
COL_X = [X[0],X[1],X[2],X[3],X[4],X[5],X[6],None,None,X[7],X[8],X[9],X[10],X[11],X[12],X[13]]
COL_STAGGER = [0,0,1,2,1,1,3,None,None,3,1,1,2,1,0,0]
ROW_Y = [[111,88,71,121],[176,153,137,186],[241,217,203,252],[306,282,268,306]]
XX = 255
LED_MAP = [
 [0,1,2,3,4,5,6,XX,XX,41,40,39,38,37,36,35],
 [7,8,9,10,11,12,13,XX,XX,48,47,46,45,44,43,42],
 [14,15,16,17,18,19,20,XX,XX,55,54,53,52,51,50,49],
 [21,22,23,24,25,26,XX,XX,XX,XX,61,60,59,58,57,56],
]
KEY_W = KEY_H = 57
THUMBS = [
 (0,302,350,82,57,"defy-t1"),(1,390,350,57,57,"defy-t2"),(2,449,351,57,57,"defy-t3"),
 (3,497,373,57,57,"defy-t4"),(4,477,434,57,116,"defy-t8"),(5,441,421,57,57,"defy-t7"),
 (6,387,411,57,57,"defy-t6"),(7,305,411,65,57,"defy-t5"),(8,889,411,57,57,"defy-tR5"),
 (9,823,410,57,57,"defy-tR6"),(10,754,420,57,57,"defy-tR7"),(11,686,434,57,116,"defy-tR8"),
 (12,698,372,57,57,"defy-tR4"),(13,748,350,57,57,"defy-tR3"),(14,817,349,57,57,"defy-tR2"),
 (15,886,349,65,57,"defy-tR1"),
]

# Rotation of each thumb cap, and the point it turns about.
# Ported from Bazecor src/lens/renderer/defy-thumb-paths.ts
ROT = {"defy-t2":3,"defy-t3":10,"defy-t4":37,"defy-t6":5,"defy-t7":15,"defy-t8":54,
       "defy-tR2":-5,"defy-tR3":-25,"defy-tR4":-54,"defy-tR6":-8,"defy-tR7":-46,
       "defy-tR8":-60}
CENTER = {"defy-t1":[41.1,26.9],"defy-t2":[31.1,27.9],"defy-t3":[36.5,35.3],
          "defy-t4":[37.5,41.0],"defy-t5":[38.0,26.0],"defy-t6":[30.1,28.5],
          "defy-t7":[38.3,36.5],"defy-t8":[54.0,54.5],"defy-tR1":[41.3,25.9],
          "defy-tR2":[31.3,27.9],"defy-tR3":[36.5,35.3],"defy-tR4":[37.5,41.0],
          "defy-tR5":[38.0,26.0],"defy-tR6":[29.9,28.5],"defy-tR7":[37.5,36.5],
          "defy-tR8":[54.0,54.5]}

THUMB_LED = [27,28,29,30,31,32,33,34,69,68,67,66,65,64,63,62]

def build_geom():
    """[matrix index, x, y, w, h, led index, rotation deg, centre x, centre y]"""
    keys = []
    for row in range(4):
        for col in range(16):
            if LED_MAP[row][col] == XX or COL_X[col] is None: continue
            keys.append([row*16+col, COL_X[col], ROW_Y[row][COL_STAGGER[col]],
                         KEY_W, KEY_H, LED_MAP[row][col], 0, KEY_W/2, KEY_H/2])
    for col, x, y, w, h, kt in THUMBS:
        cx, cy = CENTER.get(kt, [w/2, h/2])
        keys.append([64+col, x, y, w, h, THUMB_LED[col], ROT.get(kt, 0), cx, cy])
    return keys

# ── Real thumb-cap silhouettes, from Bazecor defy-thumb-paths.ts ──────────────
import sys, math, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from svgpath import flatten

TP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "defy-thumb-paths.ts")
if not os.path.exists(TP):
    urllib.request.urlretrieve(
        "https://raw.githubusercontent.com/Dygmalab/Bazecor/development/"
        "src/lens/renderer/defy-thumb-paths.ts", TP)
TPSRC = open(TP).read()

def cap_path(keytype):
    m = re.search(r'"' + keytype + r'":\s*\{\s*base:\s*\n?\s*"([^"]+)"', TPSRC)
    return flatten(m.group(1)) if m else None

GEOM = build_geom()

PATHS = {}
for col, x, y, w, h, kt in THUMBS:
    segs = cap_path(kt)
    if segs: PATHS[64 + col] = [[c[0]] + [round(v, 2) for v in c[1:]] for c in segs]
print(f"thumb silhouettes: {len(PATHS)} of {len(THUMBS)}")

def placed_extent(entry):
    """Where a key lands. Caps are only translated: the silhouette carries the
    angle already. `rot` applies to the legend, not the shape."""
    idx, x, y, w, h, led, rot, cx, cy = entry
    segs = PATHS.get(idx)
    pts = ([(px, py) for c in segs for px, py in zip(c[1::2], c[2::2])]
           if segs else [(0, 0), (w, 0), (w, h), (0, h)])
    return [(x + px, y + py) for px, py in pts]

ALL = [pt for e in GEOM for pt in placed_extent(e)]
BOUNDS = [min(p[0] for p in ALL), min(p[1] for p in ALL),
          max(p[0] for p in ALL), max(p[1] for p in ALL)]
print("bounds from real shapes:", [round(v, 1) for v in BOUNDS])


# Layer names as you set them in Bazecor.
LAYER_NAMES = [f"L{i+1}" for i in range(10)]
try:
    _bc = json.load(open(os.path.expanduser(
        "~/Library/Application Support/Bazecor/config.json")))
    _neuron = os.path.basename(os.path.dirname(src))
    for n in _bc.get("neurons", []):
        if n.get("id") == _neuron:
            LAYER_NAMES = [l.get("name") or f"L{i+1}" for i, l in enumerate(n["layers"])]
            break
except Exception as e:
    print("  layer names unavailable:", e)
print("layer names:", LAYER_NAMES)

def read_entry(path, cmd):
    for e in json.load(open(path))["backup"]:
        if e["command"] == cmd: return str(e["data"]).split()
    return []

pal_raw = [int(x) for x in read_entry(src, "palette")]
PALETTE = []
for i in range(0, len(pal_raw) - 3, 4):
    r, g, b, w = pal_raw[i:i+4]          # Defy LEDs are RGBW; fold white into rgb
    PALETTE.append([min(255, r + int(w*0.8)),
                    min(255, g + int(w*0.8)),
                    min(255, b + int(w*0.8))])

cmap_raw = [int(x) for x in read_entry(src, "colormap.map")]
LEDS = 178
COLORMAP = [cmap_raw[i*LEDS:(i+1)*LEDS] for i in range(len(cmap_raw)//LEDS)]
print(f"palette: {len(PALETTE)} colours   colormap: {len(COLORMAP)} layers x {LEDS} leds")

out = {"left": LEFT, "right": RIGHT, "geom": GEOM, "bounds": BOUNDS,
       "palette": PALETTE, "colormap": COLORMAP, "paths": PATHS, "layerNames": LAYER_NAMES, "layers": []}
def shift_label(c):
    """The legend this key shows while Shift is held, or None when it does not change.

    Bazecor stores a shifted key as the plain code plus 2048, so the symbol is
    already in the code map: 2048+52 is '"', 2048+53 is '~'. Codes that only
    give back "Shift + X" add nothing, so they keep the plain legend.
    Only plain keys qualify; a macro or a layer key is not a character."""
    if not 4 <= c <= 231: return None
    s = cm.get(2048 + c)
    if not s or s.startswith("Shift + "): return None
    return SHORT.get(s, s)

for L in range(10):
    lay = codes[L*80:(L+1)*80]
    labels = [SHORT.get(label(c), label(c)) for c in lay]
    out["layers"].append({
        "labels": labels,
        "shift":  [shift_label(c) or labels[i] for i, c in enumerate(lay)],
        "hid":    [hid(c) for c in lay],
    })

# Code 65535 is "transparent": the key does whatever the base layer does.
# Resolve it so the overlay shows the real function instead of a blank.
BASE = 0
inherited = 0
for L, entry in enumerate(out["layers"]):
    if L == BASE: continue
    lay = codes[L*80:(L+1)*80]
    for pos, c in enumerate(lay):
        if c == 65535:
            entry["labels"][pos] = out["layers"][BASE]["labels"][pos]
            entry["shift"][pos]  = out["layers"][BASE]["shift"][pos]
            entry["hid"][pos]    = out["layers"][BASE]["hid"][pos]
            inherited += 1
print(f"transparent keys resolved to the base layer: {inherited}")
# Beside the app, wherever the checkout is, not a path baked into the script.
dest = os.path.join(os.path.dirname(S), "layers.json")
json.dump(out, open(dest, "w"), ensure_ascii=False)
print("geom keys:", len(GEOM), "bounds:", BOUNDS)
print("wrote", dest, "-", sum(1 for l in out["layers"] if any(l["labels"])), "layers with content")
