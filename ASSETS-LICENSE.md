# Asset licensing

Hetzly's code is MIT-licensed (see LICENSE). Two asset categories are NOT:

## Mascot sprites (Hetzi)

The mascot sprite data in `Hetzly/Mascot/MascotFrameData+*.swift` and the app
icons generated from it are derived from **"2D Pixel Art Red Panda Sprites"
by Elthen (Ahmet Avci)** — https://elthen.itch.io/2d-pixel-art-red-panda-sprites —
used under Elthen's license (https://www.patreon.com/elthen), which permits
use in commercial and non-commercial projects but does **not** permit
redistributing the assets themselves.

**Before publishing this repository publicly**, do ONE of the following:

1. Obtain permission from Elthen to include the converted sprite data, or
2. Swap back the original CC0-equivalent hand-drawn mascot:
   run `python3 scripts/mascot-fallback/states.py` and regenerate via the
   instructions in `scripts/mascot-fallback/README.md`, then run
   `swift scripts/generate_icons.swift`.

A local working copy and personal device builds are within the license terms
as-is.

## Everything else

All other art (design system, generated share cards) is original to this
project and covered by the MIT license.
