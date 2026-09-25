# AudioPaper icon

**Shipped: the display design in red.** A display with a music note on its screen — a sibling of
GlassPowerTools' icon (same bezel and screen geometry, with a note where its shell prompt is and a stand
where its database is). Built with the family's layered Icon Composer technique (see `~/Software/icon-lab`
and GlassPowerTools' `App/GlassPowerTools.icon` history).

## Designs

| Design | Masters | Layers (top → bottom; Icon Composer allows four groups) |
|---|---|---|
| `display` (shipped) | `Sources/display/` | Note · Bezel (screen aperture knocked out, a true frame) · Screen · Stand |
| `camera` (earlier) | `Sources/camera/` | Note · Lens (barrel ring) · Accent (glass + shutter) · Body (flash window knocked out) |

Each SVG is one white mask for one layer. The display's note is the solid "musical-note" from
[Heroicons](https://heroicons.com) (MIT; see `THIRD-PARTY-NOTICES.md` at the repo root).

## Colour

Colour lives in `fill-specializations` as vector linear gradients (top → bottom), never in the SVGs,
so the system's Liquid Glass, lighting and appearances stay live:

| Role | Display | Camera | Light | Dark |
|---|---|---|---|---|
| Primary | screen | lens glass, shutter | accent, lit → deep | same |
| Secondary | bezel, stand | body | silver | white → pale grey |
| Barrel | — | lens ring | deeper grey | light grey |
| Glyph | note | note | white | white |

Palettes: red (shipped; GlassPowerTools' screen red), cobalt (family alternate), emerald, violet, amber.

## Scale

Icon Composer maps an SVG viewBox onto the icon grid rather than the full canvas, so every layer is
wrapped in a 1.22 scale about the centre (GlassPowerTools' fix). The display, narrower than the camera,
gets a further 1.12 (`DESIGN_SCALE`) so it fills the icon comparably.

## Build

```sh
python3 docs/icon/build_icons.py                      # every design × palette → palettes/<design>/, boards
python3 docs/icon/build_icons.py --ship display red   # also install that one as App/AppIcon.icon
```

Outputs `palettes/board-display.png`, `board-camera.png` and `board-compare.png` (both designs, red and
cobalt), each rendered through Apple's `ictool` in Default, Dark, ClearLight, ClearDark and TintedDark,
plus 64 px. Requires Xcode-beta's Icon Composer and Pillow. PNG previews are git-ignored.

## Menu bar icon

`App/Assets.xcassets/MenuBarIcon*.imageset` are template SVGs of the same display: the screen as one
solid with the Heroicons note (or, while paused, pause bars) knocked out, and the stand below. The note's
path is baked into the screen path at menu bar scale (a single even-odd path is the most dependable
template rendering). The viewBox is cropped to the drawing, 18.4 × 16 pt, so it sits centred and matches
neighbouring menu bar icons.
