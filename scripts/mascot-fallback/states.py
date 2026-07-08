#!/usr/bin/env python3
"""Hetzi v3 — all animation states from shared templates."""

W = H = 32

def blank():
    return [["." for _ in range(W)] for _ in range(H)]

def px(g, x, y, ch):
    if 0 <= int(x) < W and 0 <= int(y) < H:
        g[int(y)][int(x)] = ch

def ellipse(g, cx, cy, rx, ry, ch):
    for y in range(H):
        for x in range(W):
            if rx > 0 and ry > 0 and ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                g[y][x] = ch

def rect(g, x0, y0, x1, y1, ch):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            px(g, x, y, ch)

def outline(g):
    out = [row[:] for row in g]
    for y in range(H):
        for x in range(W):
            if g[y][x] != ".":
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and out is not None and g[ny][nx] not in ".k":
                    out[y][x] = "k"
                    break
    return out

def shift(g, dx, dy):
    out = blank()
    for y in range(H):
        for x in range(W):
            if g[y][x] != ".":
                px(out, x + dx, y + dy, g[y][x])
    return out

def merge(base_grid, deco):
    for (x, y, ch) in deco:
        px(base_grid, x, y, ch)
    return base_grid

# ---------------------------------------------------------------- sitting
def sitting(blink=False, ears_up=False, tail_dx=0, paws="down"):
    g = blank()
    ear_dy = -1 if ears_up else 0
    # Tail
    ellipse(g, 7, 20, 3.2, 5.5, "r")
    ellipse(g, 5.5 + tail_dx, 13, 2.8, 5.0, "r")
    ellipse(g, 6.5 + tail_dx, 7, 2.6, 3.2, "r")
    ellipse(g, 6.5 + tail_dx, 6, 1.8, 1.8, "c")
    ellipse(g, 8, 21, 1.8, 4.0, "d")
    # Body
    ellipse(g, 14, 22, 5.5, 6.0, "r")
    ellipse(g, 17, 18, 6.0, 8.0, "r")
    ellipse(g, 13.5, 23, 3.4, 4.0, "d")
    ellipse(g, 19, 19, 3.4, 6.0, "c")
    # Head + snout
    ellipse(g, 20, 10, 6.4, 5.6, "r")
    ellipse(g, 26, 12.5, 3.4, 2.6, "r")
    ellipse(g, 26.5, 13.4, 2.6, 1.8, "c")
    # Ears
    ellipse(g, 16.5, 5.0 + ear_dy, 2.0, 2.2, "r")
    ellipse(g, 21.5, 4.4 + ear_dy, 2.2, 2.4, "r")
    px(g, 21, 4 + ear_dy, "d"); px(g, 22, 4 + ear_dy, "d")
    px(g, 21, 5 + ear_dy, "d"); px(g, 22, 5 + ear_dy, "d")
    # Legs/paws
    if paws == "up":
        rect(g, 18, 21, 19, 23, "r"); rect(g, 21, 21, 22, 23, "r")
        rect(g, 18, 21, 19, 21, "d"); rect(g, 21, 21, 22, 21, "d")
        # keep base under body
        rect(g, 18, 26, 22, 27, "r")
    else:
        rect(g, 18, 24, 19, 27, "r"); rect(g, 21, 24, 22, 27, "r")
        rect(g, 18, 27, 19, 27, "d"); rect(g, 21, 27, 22, 27, "d")
    # Face
    if blink:
        px(g, 23, 10, "k"); px(g, 24, 10, "k")
    else:
        px(g, 23, 9, "k"); px(g, 24, 9, "k")
        px(g, 23, 10, "k"); px(g, 24, 10, "k")
        px(g, 23, 9, "w")
    px(g, 29, 12, "k"); px(g, 28, 12, "k")
    px(g, 27, 15, "k")
    return g

# ---------------------------------------------------------------- standing / running
def standing(phase=0, stretch=False, lean=0):
    """Horizontal pose facing right. phase 0/1 alternates legs."""
    g = blank()
    # Tail streaming behind (left), slightly raised.
    ellipse(g, 5, 14 - lean, 3.0, 2.4, "r")
    ellipse(g, 8, 15 - lean, 3.2, 2.6, "r")
    ellipse(g, 4.5, 13 - lean, 1.6, 1.6, "c")
    # Long body.
    ellipse(g, 15, 17, 8.0, 4.6, "r")
    ellipse(g, 14, 19, 6.0, 2.6, "d")
    ellipse(g, 18, 19.5, 4.4, 2.2, "c")
    # Head at front.
    ellipse(g, 24, 12 + lean, 5.4, 4.8, "r")
    ellipse(g, 29, 14 + lean, 2.8, 2.2, "r")
    ellipse(g, 29.2, 14.8 + lean, 2.2, 1.5, "c")
    # Ears.
    ellipse(g, 21, 7.6 + lean, 1.8, 2.0, "r")
    ellipse(g, 25, 7.2 + lean, 2.0, 2.2, "r")
    px(g, 25, 7 + lean, "d"); px(g, 24, 7 + lean, "d")
    # Eye + nose.
    px(g, 26, 11 + lean, "k"); px(g, 27, 11 + lean, "k")
    px(g, 26, 12 + lean, "k"); px(g, 27, 12 + lean, "k")
    px(g, 26, 11 + lean, "w")
    px(g, 31, 14 + lean, "k")
    # Legs: two pairs, alternating.
    if stretch:
        # gallop: front legs forward, hind legs back
        if phase == 0:
            rect(g, 22, 20, 23, 25, "r"); rect(g, 25, 19, 26, 24, "r")
            rect(g, 8, 19, 9, 24, "r"); rect(g, 5, 18, 6, 23, "r")
        else:
            rect(g, 21, 20, 22, 26, "r"); rect(g, 24, 20, 25, 26, "r")
            rect(g, 9, 20, 10, 26, "r"); rect(g, 12, 20, 13, 26, "r")
    else:
        # Trot: one leg of each pair swings, its partner stays planted —
        # positions keep a >=1px gap so legs never merge into one blob.
        a = phase * 2  # 0 or 2
        rect(g, 20 + a, 21, 21 + a, 26, "r")
        rect(g, 25, 21, 26, 26, "r")
        rect(g, 8 + a, 21, 9 + a, 26, "r")
        rect(g, 13, 21, 14, 26, "r")
    return g

# ---------------------------------------------------------------- sleep
def sleeping(frame):
    g = blank()
    rise = 1 if frame == 1 else 0
    # Curled body ball.
    ellipse(g, 16, 21 - rise * 0.5, 8.5, 6.0 + rise * 0.4, "r")
    ellipse(g, 15, 23, 6.0, 3.4, "d")
    # Tail wrapped around the front.
    ellipse(g, 10, 24, 4.6, 2.6, "r")
    ellipse(g, 7.5, 23.5, 1.6, 1.6, "c")
    # Head tucked on top-right, ear visible.
    ellipse(g, 21, 16, 4.6, 3.6, "r")
    ellipse(g, 24.5, 17.5, 2.2, 1.6, "c")
    ellipse(g, 18.5, 12.8, 1.8, 1.9, "r")
    px(g, 18, 12, "d"); px(g, 19, 12, "d")
    # Closed eye.
    px(g, 23, 15, "k"); px(g, 24, 15, "k")
    g = outline(g)
    # z z Z rising — 4x4 Z glyphs with a real anti-diagonal, drawn AFTER
    # outline so they stay crisp.
    zs = [(24, 10), (27, 5), (28, 0)]
    deco = []
    for i in range(min(frame + 1, 3)):
        x, y = zs[i]
        deco += [(x, y, "c"), (x + 1, y, "c"), (x + 2, y, "c"), (x + 3, y, "c"),
                 (x + 2, y + 1, "c"),
                 (x + 1, y + 2, "c"),
                 (x, y + 3, "c"), (x + 1, y + 3, "c"), (x + 2, y + 3, "c"), (x + 3, y + 3, "c")]
    return merge(g, deco)

# ---------------------------------------------------------------- peek
def peeking(blink=False):
    g = blank()
    # Head rising from the bottom edge.
    ellipse(g, 16, 27, 7.0, 6.2, "r")
    ellipse(g, 22, 29, 3.4, 2.6, "r")
    ellipse(g, 22.5, 30, 2.6, 1.8, "c")
    # Ears.
    ellipse(g, 12.5, 21.4, 2.0, 2.2, "r")
    ellipse(g, 18, 20.6, 2.2, 2.4, "r")
    px(g, 18, 20, "d"); px(g, 17, 20, "d")
    # Paws gripping the edge.
    rect(g, 8, 30, 10, 31, "r")
    rect(g, 25, 30, 27, 31, "r")
    px(g, 9, 31, "d"); px(g, 26, 31, "d")
    # Eyes (both visible, facing viewer-ish).
    if blink:
        px(g, 13, 26, "k"); px(g, 14, 26, "k")
        px(g, 19, 26, "k"); px(g, 20, 26, "k")
    else:
        for ex in (13, 19):
            px(g, ex, 25, "k"); px(g, ex + 1, 25, "k")
            px(g, ex, 26, "k"); px(g, ex + 1, 26, "k")
            px(g, ex, 25, "w")
    px(g, 22, 28, "k")
    return outline(g)

# ---------------------------------------------------------------- states
def deco_excl(g):
    # "!" above the head.
    return merge(g, [(28, 2, "w"), (28, 3, "w"), (28, 4, "w"), (28, 6, "w")])

def deco_sparkle(g, alt=False):
    pts = [(4, 4), (28, 6), (10, 2)] if not alt else [(6, 8), (26, 3), (14, 1)]
    deco = []
    for (x, y) in pts:
        deco += [(x, y, "w"), (x - 1, y, "c"), (x + 1, y, "c"), (x, y - 1, "c"), (x, y + 1, "c")]
    return merge(g, deco)

def deco_dirt(g, alt=False):
    pts = [(27, 22), (29, 19), (28, 25)] if not alt else [(26, 20), (30, 22), (27, 26)]
    return merge(g, [(x, y, "d") for (x, y) in pts])

def dig(phase):
    """Work: leaning-down stand pose, front paws digging."""
    g = standing(phase=phase % 2, stretch=False, lean=3)
    return g

STATES = {
    "idle": [
        outline(sitting()),
        outline(sitting(blink=True)),
        outline(sitting(tail_dx=1)),
        outline(sitting()),
    ],
    "walk": [
        outline(standing(phase=0)),
        shift(outline(standing(phase=1)), 0, 1),
        outline(standing(phase=0)),
        shift(outline(standing(phase=1)), 0, 1),
    ],
    "run": [
        outline(standing(phase=0, stretch=True)),
        shift(outline(standing(phase=1, stretch=True)), 0, 1),
        outline(standing(phase=0, stretch=True)),
        shift(outline(standing(phase=1, stretch=True)), 0, 1),
    ],
    "sleep": [sleeping(0), sleeping(1), sleeping(2)],
    "alarm": [
        deco_excl(outline(sitting(ears_up=True))),
        deco_excl(outline(sitting(ears_up=True, blink=True))),
    ],
    "celebrate": [
        outline(sitting()),
        deco_sparkle(shift(outline(sitting(ears_up=True)), 0, -2)),
        deco_sparkle(shift(outline(sitting(ears_up=True)), 0, -3), alt=True),
        outline(sitting()),
    ],
    "work": [
        deco_dirt(outline(dig(0))),
        deco_dirt(outline(dig(1)), alt=True),
        deco_dirt(outline(dig(0)), alt=True),
        deco_dirt(outline(dig(1))),
    ],
    "peek": [peeking(), peeking(blink=True)],
}

FRAMES = []
for name in ["idle", "walk", "run", "sleep", "alarm", "celebrate", "work", "peek"]:
    for f in STATES[name]:
        FRAMES.append(["".join(row) for row in f])

if __name__ == "__main__":
    import json, sys
    if len(sys.argv) > 1 and sys.argv[1] == "swift":
        for name in ["idle", "walk", "run", "sleep", "alarm", "celebrate", "work", "peek"]:
            print(f"== {name} ==")
            for f in STATES[name]:
                print("        [")
                for row in f:
                    print(f'            "{"".join(row)}",')
                print("        ],")
