#!/usr/bin/env python3
"""Writes the named color tokens (light + dark) into the asset catalog and checks their contrast.
Run: python3 scripts/gen_colors.py   (edit TOKENS to retheme; fails if a text pair drops below WCAG AA)."""
import json, os, sys

CATALOG = os.path.join(os.path.dirname(__file__), "..", "ios", "SmallStep", "Assets.xcassets")

# name: (light, dark)
TOKENS = {
    "Background":    ("F6F1E8", "1D2123"),   # warm sand / deep slate
    "Surface":       ("FCFAF5", "292E30"),   # cards
    "TextPrimary":   ("2E3438", "ECE7DF"),   # gentle charcoal / soft cream
    "TextSecondary": ("5A6368", "B4B9B7"),
    "Sage":          ("4E7060", "9DBBA8"),   # primary actions, selection
    "OnSage":        ("FFFFFF", "17201B"),   # text on Sage
    "SageSoft":      ("E3EBE4", "34403A"),   # selected card tint
    "MutedBlue":     ("4C6A87", "93B0CC"),   # secondary accent
    "BlueSoft":      ("E1E9F0", "2C3A47"),
    "Taupe":         ("6E5E50", "C2B3A3"),   # skipped / unfinished (never red)
    "TaupeSoft":     ("ECE4DA", "3A342E"),
    "Hairline":      ("D9D2C5", "3C4244"),   # decorative borders only
}

def rgb(h): return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
def lum(h):
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = map(f, rgb(h)); return 0.2126 * r + 0.7152 * g + 0.0722 * b
def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True); return (la + 0.05) / (lb + 0.05)

# (foreground, background, minimum ratio): 4.5 for text, 3 for icons / large UI
PAIRS = [("TextPrimary", "Background", 4.5), ("TextPrimary", "Surface", 4.5), ("TextPrimary", "SageSoft", 4.5),
         ("TextSecondary", "Background", 4.5), ("TextSecondary", "Surface", 4.5), ("OnSage", "Sage", 4.5),
         ("Sage", "Background", 3.0), ("Sage", "Surface", 3.0), ("MutedBlue", "Background", 4.5),
         ("MutedBlue", "BlueSoft", 4.5), ("Taupe", "Background", 4.5), ("Taupe", "TaupeSoft", 4.5),
         ("TextPrimary", "TaupeSoft", 4.5), ("TextPrimary", "BlueSoft", 4.5), ("Sage", "SageSoft", 3.0)]

bad = False
for mode in (0, 1):
    for fg, bg, need in PAIRS:
        r = contrast(TOKENS[fg][mode], TOKENS[bg][mode])
        flag = "ok " if r >= need else "LOW"
        if r < need: bad = True
        print(f"{'dark ' if mode else 'light'} {flag} {fg:>13} on {bg:<10} {r:5.2f} (need {need})")

def color(h):
    r, g, b = rgb(h)
    return {"color-space": "srgb", "components": {"alpha": "1.000", "red": f"{r:.3f}", "green": f"{g:.3f}", "blue": f"{b:.3f}"}}

os.makedirs(CATALOG, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(CATALOG, "Contents.json"), "w"), indent=2)
for name, (light, dark) in TOKENS.items():
    d = os.path.join(CATALOG, f"{name}.colorset"); os.makedirs(d, exist_ok=True)
    json.dump({"colors": [
        {"color": color(light), "idiom": "universal"},
        {"appearances": [{"appearance": "luminosity", "value": "dark"}], "color": color(dark), "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)
# the app's accent colour is Sage
acc = os.path.join(CATALOG, "AccentColor.colorset"); os.makedirs(acc, exist_ok=True)
json.dump(json.load(open(os.path.join(CATALOG, "Sage.colorset", "Contents.json"))), open(os.path.join(acc, "Contents.json"), "w"), indent=2)
sys.exit(1 if bad else 0)
