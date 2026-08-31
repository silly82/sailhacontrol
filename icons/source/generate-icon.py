#!/usr/bin/env python3
# Regenerates icons/<size>x<size>/harbour-hacontrol.png from scratch.
# Needs python3-cairo (pycairo). Run from the repo root:
#   python3 icons/source/generate-icon.py
import os
import cairo

SIZES = [86, 108, 128, 172]
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "icons")

def draw(size, path):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surface)
    s = size / 86.0
    ctx.scale(s, s)

    # -- Sailfish organic silhouette (exact path from the official
    # icon-launcher-template.svg, 86x86 space) --
    ctx.move_to(84.277, 0.3)
    ctx.line_to(43, 0.3)
    # C 19.417,0.3 0.3,19.418 0.3,43
    ctx.curve_to(19.417, 0.3, 0.3, 19.418, 0.3, 43)
    ctx.line_to(0.3, 84.277)
    # c0,0.786 0.637,1.423 1.423,1.423 -> relative from (0.3,84.277)
    ctx.curve_to(0.3, 85.063, 0.937, 85.7, 1.723, 85.7)
    ctx.line_to(43, 85.7)
    # c23.583,0 42.7,-19.118 42.7,-42.7 -> relative from (43,85.7)
    ctx.curve_to(66.583, 85.7, 85.7, 66.582, 85.7, 43)
    ctx.line_to(85.7, 1.723)
    # c0,-0.786 -0.637,-1.423 -1.423,-1.423 -> relative from (85.7,1.723)
    ctx.curve_to(85.7, 0.937, 85.063, 0.3, 84.277, 0.3)
    ctx.close_path()

    grad = cairo.LinearGradient(0.7169, 85.2831, 85.2831, 0.7169)
    grad.add_color_stop_rgb(0, 0x1B / 255, 0x3A / 255, 0x57 / 255)
    grad.add_color_stop_rgb(1, 0x41 / 255, 0xBD / 255, 0xF5 / 255)
    ctx.set_source(grad)
    ctx.fill()

    # -- House motif, white --
    ctx.set_source_rgb(1, 1, 1)
    for i, (x, y) in enumerate(path):
        if i == 0:
            ctx.move_to(x, y)
        else:
            ctx.line_to(x, y)
    ctx.close_path()
    ctx.fill()

    out_path = os.path.join(OUT_DIR, f"{size}x{size}", "harbour-hacontrol.png")
    surface.write_to_png(out_path)
    print(out_path)

house = [
    (43, 19.5),
    (67, 40.5),
    (60.5, 40.5),
    (60.5, 65.5),
    (48.5, 65.5),
    (48.5, 50),
    (37.5, 50),
    (37.5, 65.5),
    (25.5, 65.5),
    (25.5, 40.5),
    (19, 40.5),
]

for size in SIZES:
    draw(size, house)

print("done")
