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

import re, glob, os, json
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "db")
tables = {}   # varname -> list[(code,label)]

def subs(t):
    for k,v in SUBS.items(): t=t.replace(k,v)
    return t
SUBS={"${guiLabel}":"Cmd","${guiVerbose}":"Command","${AltLabel}":"Opt","${AltVerbose}":"Option"}
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "0": "\0"}

def unescape(s):
    """Turn the source text of a TS string into the characters it stands for."""
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            n = s[i+1]
            if n == "u" and re.match(r"[0-9a-fA-F]{4}", s[i+2:i+6]):
                out.append(chr(int(s[i+2:i+6], 16))); i += 6; continue
            out.append(ESCAPES.get(n, n)); i += 2; continue
        out.append(s[i]); i += 1
    return "".join(out)

def quoted(block, field):
    r"""Read one quoted field. Stops at the quote that opened it, not at any quote.

    A label can itself be a quote character, as in primary: "'" or primary: "`".
    Group 1 holds the opening quote, so (?!\1) lets every other quote through."""
    m = re.search(r'\b' + field + r'\s*:\s*([`"\'])((?:\\.|(?!\1).)*?)\1', block, re.S)
    return unescape(m.group(2)) if m else None

def label_from(block):
    for field in ("verbose", "primary"):
        t = quoted(block, field)
        if t: return subs(t)
    return "?"

entry_re = re.compile(r'\{\s*code:\s*(\d+)\s*,(.*?)\n    \}', re.S)
for path in glob.glob(D + "/*.ts") + glob.glob(D + "/*.tsx"):
    src = open(path).read()
    # split into `const XTable = {...}` chunks by brace matching
    for m in re.finditer(r'const\s+(\w+)\s*(?::\s*[A-Za-z0-9_<>\[\], ]+)?\s*=\s*\{\s*\n\s*groupName', src):
        name = m.group(1); i = src.index('{', m.start())
        depth = 0
        for j in range(i, len(src)):
            if src[j] == '{': depth += 1
            elif src[j] == '}':
                depth -= 1
                if depth == 0: break
        chunk = src[i:j+1]
        gn = re.search(r'groupName:\s*"([^"]*)"', chunk)
        ents = [(int(c), label_from(b)) for c, b in
                re.findall(r'code:\s*(\d+)\s*,\s*\n\s*labels:\s*\{(.*?)\},', chunk, re.S)]
        if ents:
            tables[name] = (gn.group(1) if gn else name, ents)

# resolve withModifiers(TableVar, "Group", top, BASE)
derived = []
for path in glob.glob(D + "/*.ts") + glob.glob(D + "/*.tsx"):
    src = open(path).read()
    for tv, grp, base in re.findall(r'withModifiers\(\s*(\w+)\s*,\s*"([^"]*)"\s*,.*?,\s*(\d+)\s*\)', src, re.S):
        derived.append((tv, grp, int(base)))

code_map = {}
for name, (gn, ents) in tables.items():
    for c, lab in ents:
        code_map.setdefault(c, f"{lab}")
for tv, grp, base in derived:
    if tv not in tables: continue
    for c, lab in tables[tv][1]:
        code_map.setdefault(c + base, f"{grp} {lab}".strip())

json.dump(code_map, open(os.path.join(os.path.dirname(D), "codemap.json"), "w"))
print("tables:", len(tables), "derived rules:", len(derived), "codes:", len(code_map))
unknown = [0,335,336,2101,17152,17452,19682,20865,20866,22709,22710,22711,22713,22733,
           23663,23664,23785,23786,49162,49209,49211,49721,53852,53980,54108,54109,65535]
for u in unknown:
    print(f"  {u:6d} -> {code_map.get(u, '*** UNRESOLVED ***')}")
