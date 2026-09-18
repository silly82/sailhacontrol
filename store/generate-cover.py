#!/usr/bin/env python3
# Generates store/cover-1080x540.png in the same visual style as the app
# icon (icons/source/generate-icon.py): navy-to-HA-blue diagonal gradient,
# white house motif. Needs python3-cairo (pycairo). Run from the repo root:
#   python3 store/generate-cover.py
import os
import cairo

W, H = 1080, 540
OUT_PATH = os.path.join(os.path.dirname(__file__), "cover-1080x540.png")

surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
ctx = cairo.Context(surface)

# Same diagonal gradient direction/colors as the app icon: navy bottom-left
# to HA-blue top-right.
grad = cairo.LinearGradient(0, H, W, 0)
grad.add_color_stop_rgb(0, 0x1B / 255, 0x3A / 255, 0x57 / 255)
grad.add_color_stop_rgb(1, 0x41 / 255, 0xBD / 255, 0xF5 / 255)
ctx.set_source(grad)
ctx.paint()

# -- House motif (same path as the app icon, scaled/translated into a
# left-aligned square badge) --
house = [
    (43, 19.5), (67, 40.5), (60.5, 40.5), (60.5, 65.5), (48.5, 65.5),
    (48.5, 50), (37.5, 50), (37.5, 65.5), (25.5, 65.5), (25.5, 40.5), (19, 40.5),
]
badge_size = 340
scale = badge_size / 86.0
badge_x, badge_y = 90, (H - badge_size) / 2

ctx.save()
ctx.translate(badge_x, badge_y)
ctx.scale(scale, scale)
ctx.set_source_rgba(1, 1, 1, 0.92)
for i, (x, y) in enumerate(house):
    if i == 0:
        ctx.move_to(x, y)
    else:
        ctx.line_to(x, y)
ctx.close_path()
ctx.fill()
ctx.restore()

# -- Title + subtitle, right of the house badge --
text_x = badge_x + badge_size + 55

ctx.set_source_rgb(1, 1, 1)
ctx.select_font_face("Noto Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
ctx.set_font_size(92)
title = "HA Control"
extents = ctx.text_extents(title)
title_baseline_y = H / 2 - 10
ctx.move_to(text_x, title_baseline_y)
ctx.show_text(title)

ctx.set_source_rgba(1, 1, 1, 0.85)
ctx.select_font_face("Noto Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
ctx.set_font_size(34)
subtitle = "Home Assistant für SailfishOS"
ctx.move_to(text_x, title_baseline_y + 55)
ctx.show_text(subtitle)

surface.write_to_png(OUT_PATH)
print(OUT_PATH)
