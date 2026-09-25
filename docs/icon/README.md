# AudioPaper icon

A camera with a music note in the lens, built with the family's layered Icon Composer technique
(see `~/Software/icon-lab` and GlassPowerTools' `App/GlassPowerTools.icon` history).

- `Sources/*.svg` are the masters. Each file is one white mask for one layer, grouped into the four groups Icon Composer allows (Note, Lens, Accent = glass + shutter, Body):
  `Note`, `Lens` (barrel ring, aperture knocked out), `Glass`, `Shutter`, `Body` (flash window knocked out).
- `build_icons.py` turns them into one `.icon` per accent palette under `palettes/`, renders every
  appearance with Apple's `ictool` (Default, Dark, ClearLight, ClearDark, TintedDark, plus 64 px),
  and assembles `palettes/board.png`.
- Colour lives in `fill-specializations`, never in the SVGs:

  | Role | Light | Dark |
  |---|---|---|
  | Glass, shutter (primary) | accent | accent |
  | Body (secondary) | grey 0.62 | white |
  | Lens barrel | grey 0.44 | grey 0.75 |
  | Note (glyph) | white | white |

- Layer geometry is wrapped in a 1.22 scale about the centre, because Icon Composer maps the SVG
  viewBox onto the icon grid rather than the full canvas.

```sh
python3 docs/icon/build_icons.py              # rebuild palettes and board
python3 docs/icon/build_icons.py --ship red   # also install that palette as App/AppIcon.icon
```

Requires Xcode-beta's Icon Composer (`ictool`) and Pillow for the board. PNGs are previews, not masters.

Next step, if the flat look isn't enough: the approach GlassPowerTools shipped with, 3D-rendered
layers with a light and a dark variant per layer via `image-name-specializations`.
