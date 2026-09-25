#!/usr/bin/env python3
"""AudioPaper icon: SVG masters → one Icon Composer document per accent palette, plus previews.

Follows the family's layered technique (icon-lab, GlassPowerTools): each semantic layer is one
white SVG mask; colour lives in per-appearance `fill-specializations`, so light and dark are native
Icon Composer specializations and Clear/Tinted are derived by the system.

  python3 docs/icon/build_icons.py                 # every palette → docs/icon/palettes/, board.png
  python3 docs/icon/build_icons.py --ship red      # also copy that palette to App/AppIcon.icon

Colour roles (GlassPowerTools convention), as vector linear gradients (top → bottom):
  primary   (lens glass, shutter)  the accent, lit → deep, in both appearances
  secondary (body)                 silver in light, white → pale grey in dark
  barrel    (lens ring)            a deeper neutral in both, so it reads against the body
  glyph     (music note)           solid white in both, always on the primary
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SOURCES = HERE / "Sources"
OUT = HERE / "palettes"
ICTOOL = Path("/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool")

PALETTES = {
    "red": (0.90588, 0.03529, 0.03922),   # GlassPowerTools' screen red
    "cobalt": (0.0, 71 / 255, 171 / 255),  # family's approved alternate
    "emerald": (0.0, 0.62, 0.38),
    "violet": (0.45, 0.20, 0.90),
    "amber": (1.0, 0.58, 0.0),
}
WHITE = (1.0, 1.0, 1.0)
# Neutral gradients, top → bottom, as (light appearance, dark appearance). Vector fills, so the system's
# Liquid Glass stays live on top; no shading is baked into the artwork.
SECONDARY = (((0.80, 0.80, 0.82), (0.52, 0.52, 0.54)), ((1.0, 1.0, 1.0), (0.80, 0.80, 0.83)))
# The lens barrel sits on the body; a deeper neutral keeps it legible against it.
BARREL = (((0.62, 0.62, 0.65), (0.32, 0.32, 0.35)), ((0.84, 0.85, 0.87), (0.58, 0.59, 0.62)))

# Groups, top to bottom (index 0 renders in front). Icon Composer allows at most four groups;
# a group may hold several layers, each one SVG mask with its own colour role.
GROUPS = [
    ("Note", 0.10, [("Note", "glyph")]),
    ("Lens", 0.22, [("Lens", "barrel")]),
    ("Accent", 0.12, [("Glass", "primary"), ("Shutter", "primary")]),
    ("Body", 0.22, [("Body", "secondary")]),
]
# Icon Composer maps an SVG's viewBox onto the icon grid, not the full canvas; geometry drawn at
# full-canvas size renders at ~82% and sits low (see GlassPowerTools 3b39e7b). Scale about the centre.
GRID_SCALE = 1.22
APPEARANCES = ["Default", "Dark", "ClearLight", "ClearDark", "TintedDark"]


def srgb(rgb):
    return "srgb:" + ",".join(f"{v:.5f}" for v in (*rgb, 1))


def shade(rgb, factor):
    """Lighten (factor > 1, toward white) or darken (factor < 1) a colour."""
    if factor >= 1:
        return tuple(c + (1 - c) * (factor - 1) for c in rgb)
    return tuple(c * factor for c in rgb)


def fill(value):
    if isinstance(value[0], tuple):
        return {"linear-gradient": [srgb(value[0]), srgb(value[1])]}
    return {"solid": srgb(value)}


def fills(role, accent):
    """Per-appearance fill: a colour (solid) or a (top, bottom) pair (linear gradient)."""
    light, dark = {
        # The accent keeps its hue in both appearances, shading from a lit top to a deep base.
        "primary": ((shade(accent, 1.28), shade(accent, 0.66)),) * 2,
        "secondary": SECONDARY,
        "barrel": BARREL,
        "glyph": (WHITE, WHITE),
    }[role]
    return [{"value": fill(light)}, {"appearance": "dark", "value": fill(dark)}]


def scaled_svg(source: Path) -> str:
    text = source.read_text()
    open_end = text.index(">", text.index("<svg")) + 1
    close = text.rindex("</svg>")
    return (
        text[:open_end]
        + f'\n  <g transform="translate(512 512) scale({GRID_SCALE}) translate(-512 -512)">'
        + text[open_end:close]
        + "  </g>\n"
        + text[close:]
    )


def build(name, accent):
    icon = OUT / f"AppIcon-{name}.icon"
    shutil.rmtree(icon, ignore_errors=True)
    (icon / "Assets").mkdir(parents=True)
    groups = []
    for group, shadow, layers in GROUPS:
        entries = []
        for layer, role in layers:
            (icon / "Assets" / f"{layer}.svg").write_text(scaled_svg(SOURCES / f"{layer}.svg"))
            entries.append({"name": layer, "image-name": f"{layer}.svg", "glass": True,
                            "fill-specializations": fills(role, accent)})
        groups.append({
            "name": group,
            "layers": entries,
            "shadow": {"kind": "neutral", "opacity": shadow},
            "specular": True,
            "translucency": {"enabled": False, "value": 0.05},
        })
    manifest = {
        "fill-specializations": [
            {"value": {"linear-gradient": [srgb((0.985,) * 3), srgb((0.945,) * 3)]}},
            {"appearance": "dark", "value": {"linear-gradient": [srgb((0.11, 0.115, 0.125)), srgb((0.035, 0.038, 0.045))]}},
        ],
        "groups": groups,
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    (icon / "icon.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return icon


def export(icon, name, size=512):
    paths = {}
    for mode in APPEARANCES:
        out = OUT / "previews" / f"{name}-{mode}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        args = [str(ICTOOL), str(icon), "--export-image", "--output-file", str(out), "--platform", "macOS",
                "--rendition", mode, "--width", str(size), "--height", str(size), "--scale", "1",
                "--design-generation", "27"]
        if mode == "TintedDark":
            args += ["--tint-color", "0.58", "--tint-strength", "0.75"]
        subprocess.run(args, check=True, capture_output=True)
        paths[mode] = out
    small = OUT / "previews" / f"{name}-dock64.png"
    subprocess.run([str(ICTOOL), str(icon), "--export-image", "--output-file", str(small), "--platform", "macOS",
                    "--rendition", "Default", "--width", "64", "--height", "64", "--scale", "1",
                    "--design-generation", "27"], check=True, capture_output=True)
    paths["dock64"] = small
    return paths


def board(rows):
    from PIL import Image, ImageDraw
    cell, pad = 256, 16
    cols = APPEARANCES + ["dock64"]
    width = pad + len(cols) * (cell + pad) + 90
    height = pad + len(rows) * (cell + pad)
    sheet = Image.new("RGBA", (width, height), (128, 128, 128, 255))
    draw = ImageDraw.Draw(sheet)
    for r, (name, paths) in enumerate(rows):
        y = pad + r * (cell + pad)
        draw.text((pad, y + cell // 2), name, fill="white")
        for c, mode in enumerate(cols):
            img = Image.open(paths[mode]).convert("RGBA")
            if mode != "dock64":
                img = img.resize((cell, cell), Image.LANCZOS)
            x = 90 + pad + c * (cell + pad)
            sheet.paste(img, (x + (cell - img.width) // 2, y + (cell - img.height) // 2), img)
            if r == 0:
                draw.text((x, 2), mode, fill="white")
    sheet.save(OUT / "board.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, accent in PALETTES.items():
        icon = build(name, accent)
        rows.append((name, export(icon, name)))
    board(rows)
    if "--ship" in sys.argv:
        choice = sys.argv[sys.argv.index("--ship") + 1]
        target = ROOT / "App" / "AppIcon.icon"
        shutil.rmtree(target, ignore_errors=True)
        shutil.copytree(OUT / f"AppIcon-{choice}.icon", target)
        print(f"Shipped {choice} → {target.relative_to(ROOT)}")
    print(f"Board: {(OUT / 'board.png').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
