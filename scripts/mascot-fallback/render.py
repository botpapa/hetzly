#!/usr/bin/env python3
"""Render 32x32 palette-character sprite grids to an upscaled PNG contact sheet."""
import sys, zlib, struct

PALETTE = {
    ".": None,
    "k": (0x1B, 0x15, 0x12),
    "r": (0xC1, 0x64, 0x3B),
    "d": (0x8F, 0x45, 0x27),
    "c": (0xF2, 0xE3, 0xC6),
    "p": (0xE8, 0xA2, 0xA0),
    "w": (0xFF, 0xFF, 0xFF),
}
BG = (0x14, 0x14, 0x18)
SCALE = 12
PAD = 8

def write_png(path, w, h, rgb_rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rgb_rows)
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(png)

def render(frames, out):
    n = len(frames)
    W = n * (32 * SCALE + PAD) + PAD
    H = 32 * SCALE + 2 * PAD
    rows = [[*BG] * W for _ in range(H)]
    for fi, frame in enumerate(frames):
        assert len(frame) == 32, f"frame {fi}: {len(frame)} rows"
        ox = PAD + fi * (32 * SCALE + PAD)
        for y, line in enumerate(frame):
            assert len(line) == 32, f"frame {fi} row {y}: {len(line)} cols"
            for x, ch in enumerate(line):
                col = PALETTE[ch]
                if col is None:
                    continue
                for dy in range(SCALE):
                    trow = rows[PAD + y * SCALE + dy]
                    for dx in range(SCALE):
                        px = (ox + x * SCALE + dx) * 3
                        trow[px:px + 3] = col
    write_png(out, W, H, rows)
    print(f"wrote {out} ({n} frames)")

if __name__ == "__main__":
    src = open(sys.argv[1]).read()
    ns = {}
    exec(src, ns)
    render(ns["FRAMES"], sys.argv[2])
