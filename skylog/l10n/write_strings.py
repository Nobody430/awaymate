#!/usr/bin/env python3
"""Writes <lang>.lproj/Localizable.strings and InfoPlist.strings for app and widget from tr_<lang>.json."""
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
repo = sys.argv[1]
def esc(s): return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
def write(path, pairs, header):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"/* {header} */\n")
        for k, v in sorted(pairs.items()):
            f.write(f'"{esc(k)}" = "{esc(v)}";\n')
src = json.load(open(os.path.join(here, "source.json")))
for lang in sys.argv[2:]:
    tr = json.load(open(os.path.join(here, f"tr_{lang}.json")))
    write(f"{repo}/Skylog/{lang}.lproj/Localizable.strings", tr["Skylog"], f"Skylog – {lang}. Keys are the German source texts.")
    write(f"{repo}/SkylogWidgets/{lang}.lproj/Localizable.strings", tr["SkylogWidgets"], f"Skylog widgets – {lang}")
    write(f"{repo}/Skylog/{lang}.lproj/InfoPlist.strings", tr["InfoPlist"], f"Permission texts – {lang}")
    print(lang, len(tr["Skylog"]), len(tr["SkylogWidgets"]))
# German: keys are the texts themselves; the folder makes German a supported language
for target in ("Skylog", "SkylogWidgets"):
    write(f"{repo}/{target}/de.lproj/Localizable.strings", {"Skylog": "Skylog"}, "German is the source language – the keys are the texts.")
write(f"{repo}/Skylog/de.lproj/InfoPlist.strings", src["InfoPlist"], "Permission texts – de")
