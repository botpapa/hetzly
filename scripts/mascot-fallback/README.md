# Fallback mascot (CC0-equivalent, original art)

The shipped mascot uses Elthen's red panda sprites (see ../../ASSETS-LICENSE.md),
which cannot be redistributed. This directory regenerates the original
hand-drawn marten so the repository can be published without Elthen's assets:

1. `python3 - <<'PY'` — run the emitter (see states.py's __main__ or adapt the
   emitter loop from the git history of Hetzly/Mascot/MascotFrameData+Idle.swift).
2. Restore MascotPalette.swift's original colors (git history: commit d488c04).
3. `swift scripts/generate_icons.swift` to regenerate icons.
4. Preview any state: `python3 render.py states.py out.png`.
