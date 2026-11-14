"""Builds the NUS Computing Tour images for iOS and Android from the artwork NUS supplied.

Run from the repository root: python3 design/nus/make_assets.py   (needs Pillow)
The artwork is only resized, trimmed and placed; it is never redrawn (see SOURCES.md).
"""
import os
from PIL import Image, ImageDraw

SRC = "design/nus/source"
IOS = "NUSOpenHouse/Assets.xcassets"
AND = "android/app/src/nus/res"
BLUE = (0x00, 0x3D, 0x7C, 255)


def trimmed(im):
    return im.crop(im.getchannel("A").getbbox())


def cut_out(im):
    """White page around a drawing made transparent; the white inside the outline stays."""
    im = im.convert("RGBA")
    marker = (255, 0, 255, 255)
    for corner in [(0, 0), (im.width - 1, 0), (0, im.height - 1), (im.width - 1, im.height - 1)]:
        ImageDraw.floodfill(im, corner, marker, thresh=60)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y] == marker:
                px[x, y] = (255, 255, 255, 0)
    return trimmed(im)


def fit_height(im, h):
    return im.resize((round(im.width * h / im.height), h), Image.LANCZOS)


def imageset(name, im, height_pt):
    for scale, suffix in [(1, ""), (2, "@2x"), (3, "@3x")]:
        fit_height(im, height_pt * scale).save(f"{IOS}/{name}.imageset/{name}{suffix}.png", optimize=True)


def icon(mascot, size):
    """SoCCat, whole and unaltered, on NUS blue."""
    big = Image.new("RGBA", (1024, 1024), BLUE)
    cat = fit_height(mascot, 760)
    big.alpha_composite(cat, ((1024 - cat.width) // 2, (1024 - cat.height) // 2))
    return big.convert("RGB").resize((size, size), Image.LANCZOS)


logo = trimmed(Image.open(f"{SRC}/nus-computing-logo.png").convert("RGBA"))
mascot = trimmed(Image.open(f"{SRC}/soccat-mascot.png").convert("RGBA"))
waving = cut_out(Image.open(f"{SRC}/soccat-waving-page5.png"))

imageset("NUSLogo", logo, 44)
imageset("SoCat", mascot, 300)
imageset("SoCatWave", waving, 200)
icon(mascot, 1024).save(f"{IOS}/AppIcon.appiconset/AppIcon-1024.png", optimize=True)

fit_height(logo, 132).save(f"{AND}/drawable-nodpi/nus_logo.png", optimize=True)
fit_height(mascot, 900).save(f"{AND}/drawable-nodpi/socat.png", optimize=True)
fit_height(waving, 600).save(f"{AND}/drawable-nodpi/socat_wave.png", optimize=True)
for density, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    icon(mascot, size).save(f"{AND}/mipmap-{density}/ic_launcher.png", optimize=True)
