#!/usr/bin/env python3
"""Usage: validate.py <lang>   – checks tr_<lang>.json against source.json (same folder)."""
import json, re, sys, os
here = os.path.dirname(os.path.abspath(__file__))
lang = sys.argv[1]
src = json.load(open(os.path.join(here, "source.json")))
try:
    tr = json.load(open(os.path.join(here, f"tr_{lang}.json")))
except Exception as e:
    print("CANNOT READ:", e); sys.exit(1)
SPEC = re.compile(r"%(?:(\d+)\$)?(lld|ld|d|lf|f|@|%)")
def specs(s):
    out = []
    i = 0
    for m in SPEC.finditer(s):
        if m.group(2) == "%": continue
        i += 1
        out.append((int(m.group(1)) if m.group(1) else i, m.group(2)))
    return sorted(out)
errors = 0
for target in ("Skylog", "SkylogWidgets"):
    got = tr.get(target, {})
    for k in src[target]:
        if k not in got: print(f"MISSING [{target}]: {k[:70]!r}"); errors += 1; continue
        v = got[k]
        if not isinstance(v, str) or not v.strip(): print(f"EMPTY [{target}]: {k[:70]!r}"); errors += 1; continue
        if specs(k) != specs(v): print(f"PLACEHOLDERS differ [{target}]: {k[:60]!r} -> {v[:60]!r}"); errors += 1
        if k.count("%%") != v.count("%%") and "%%" in k: print(f"PERCENT [{target}]: {k[:60]!r}"); errors += 1
        if re.search(r"%(?![\d@l%df])", v.replace("%%", "")): print(f"STRAY % [{target}]: {v[:70]!r}"); errors += 1
        if (k[:1] == " ") != (v[:1] == " ") or (k[-1:] == " ") != (v[-1:] == " "):
            print(f"SPACING [{target}]: {k[:50]!r} -> {v[:50]!r}"); errors += 1
    for k in got:
        if k not in src[target]: print(f"UNKNOWN KEY [{target}]: {k[:70]!r}"); errors += 1
for k in src["InfoPlist"]:
    if not tr.get("InfoPlist", {}).get(k): print("MISSING InfoPlist:", k); errors += 1
print("OK" if errors == 0 else f"{errors} problems")
sys.exit(1 if errors else 0)
