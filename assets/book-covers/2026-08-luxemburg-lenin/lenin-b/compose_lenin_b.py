#!/usr/bin/env python3
"""Deterministically typeset the Lenin-B cover artwork.

The generated artwork remains untouched in source-artwork/. This script only
resizes it to the required 1200 x 1800 canvas and adds exact typography. It
refuses to overwrite an existing final.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps, PngImagePlugin


ROOT = Path(__file__).resolve().parent
SOURCE_DIR = ROOT / "source-artwork"
FINAL_DIR = ROOT / "final"

CANVAS = (1200, 1800)
SAFE_X = 120
AUTHOR_BASELINE_Y = 207
RULE_Y = 239
TITLE_Y = 282
TITLE_MAX_WIDTH = CANVAS[0] - (SAFE_X * 2)
TITLE_MAX_BOTTOM = 790

TITLE_FONT = Path("/System/Library/Fonts/NewYork.ttf")
SANS_FONT = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")

CHARCOAL = (18, 18, 17, 255)
IVORY = (242, 226, 194, 255)
ORANGE_RED = (198, 54, 24, 255)


@dataclass(frozen=True)
class Cover:
    number: int
    slug: str
    exact_title: str
    title_lines: tuple[str, ...]
    source_name: str
    final_name: str
    edition_line: str | None = None
    edition_lines: tuple[str, ...] = ()


COVERS = (
    Cover(
        7,
        "the-proletarian-revolution-and-the-renegade-kautsky",
        "The Proletarian Revolution and the Renegade Kautsky",
        ("THE PROLETARIAN", "REVOLUTION AND THE", "RENEGADE KAUTSKY"),
        "07-the-proletarian-revolution-and-the-renegade-kautsky-artwork-v1.png",
        "07-the-proletarian-revolution-and-the-renegade-kautsky-cover-v1.png",
    ),
    Cover(
        8,
        "the-state-and-revolution",
        "The State and Revolution",
        ("THE STATE AND", "REVOLUTION"),
        "08-the-state-and-revolution-artwork-v1.png",
        "08-the-state-and-revolution-cover-v1.png",
    ),
    Cover(
        9,
        "left-wing-communism-an-infantile-disorder",
        "Left-Wing Communism: An Infantile Disorder",
        ("LEFT-WING", "COMMUNISM:", "AN INFANTILE DISORDER"),
        "09-left-wing-communism-an-infantile-disorder-artwork-v1.png",
        "09-left-wing-communism-an-infantile-disorder-cover-v2.png",
    ),
    Cover(
        10,
        "the-tax-in-kind",
        "The Tax in Kind",
        ("THE TAX", "IN KIND"),
        "10-the-tax-in-kind-artwork-v1.png",
        "10-the-tax-in-kind-cover-v1.png",
    ),
    Cover(
        11,
        "lenins-last-works",
        "Lenin’s Last Works",
        ("LENIN’S LAST", "WORKS"),
        "11-lenins-last-works-artwork-v1.png",
        "11-lenins-last-works-cover-v1.png",
    ),
    Cover(
        12,
        "the-state-and-revolution-with-an-introduction-by-ralph-miliband",
        "The State and Revolution — With an Introduction by Ralph Miliband",
        ("THE STATE AND", "REVOLUTION"),
        "12-the-state-and-revolution-with-an-introduction-by-ralph-miliband-artwork-v1.png",
        "12-the-state-and-revolution-with-an-introduction-by-ralph-miliband-cover-v1.png",
        edition_line="WITH AN INTRODUCTION BY RALPH MILIBAND",
        edition_lines=("WITH AN INTRODUCTION BY", "RALPH MILIBAND"),
    ),
)


def tracked_width(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, tracking: float) -> float:
    if not text:
        return 0
    return sum(draw.textlength(char, font=font) for char in text) + tracking * (len(text) - 1)


def draw_tracked_text(
    draw: ImageDraw.ImageDraw,
    xy: tuple[float, float],
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int, int],
    tracking: float,
) -> None:
    x, baseline_y = xy
    for char in text:
        # Every glyph shares one baseline. Using a per-glyph top anchor makes
        # punctuation such as the periods in "V. I. LENIN" float at cap height.
        draw.text((x, baseline_y), char, font=font, fill=fill, anchor="ls")
        x += draw.textlength(char, font=font) + tracking


def title_font_for(lines: tuple[str, ...]) -> tuple[ImageFont.FreeTypeFont, int]:
    scratch = Image.new("RGB", (8, 8))
    draw = ImageDraw.Draw(scratch)
    for size in range(144, 73, -2):
        font = ImageFont.truetype(str(TITLE_FONT), size=size)
        spacing = round(size * 0.12)
        widths = [draw.textbbox((0, 0), line, font=font, anchor="lt")[2] for line in lines]
        line_height = draw.textbbox((0, 0), "HGY", font=font, anchor="lt")[3]
        block_height = line_height * len(lines) + spacing * (len(lines) - 1)
        if max(widths) <= TITLE_MAX_WIDTH and TITLE_Y + block_height <= TITLE_MAX_BOTTOM:
            return font, spacing
    raise RuntimeError(f"Title does not fit safe area: {lines!r}")


def draw_title(draw: ImageDraw.ImageDraw, lines: tuple[str, ...]) -> float:
    font, spacing = title_font_for(lines)
    line_height = draw.textbbox((0, 0), "HGY", font=font, anchor="lt")[3]
    y = TITLE_Y
    for line in lines:
        draw.text((SAFE_X, y), line, font=font, fill=IVORY, anchor="lt")
        # New York's ASCII hyphen has an extremely faint hairline at this size.
        # Reinforce the exact hyphen without replacing it with a different dash.
        if "-" in line:
            prefix = line.split("-", 1)[0]
            prefix_width = draw.textlength(prefix, font=font)
            hyphen_advance = draw.textlength("-", font=font)
            bar_width = max(28, round(font.size * 0.28))
            bar_height = max(6, round(font.size * 0.055))
            bar_x = SAFE_X + prefix_width + ((hyphen_advance - bar_width) / 2)
            bar_y = y + round(line_height * 0.52)
            draw.rounded_rectangle(
                (bar_x, bar_y, bar_x + bar_width, bar_y + bar_height),
                radius=max(2, bar_height // 2),
                fill=IVORY,
            )
        y += line_height + spacing
    return y


def add_top_tone(image: Image.Image) -> Image.Image:
    """Subtly unify the typography field while retaining generated grain."""
    overlay = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    pixels = overlay.load()
    fade_end = 850
    for y in range(fade_end):
        alpha = round(54 * (1 - (y / fade_end)))
        for x in range(CANVAS[0]):
            pixels[x, y] = (*CHARCOAL[:3], alpha)
    return Image.alpha_composite(image.convert("RGBA"), overlay)


def render(cover: Cover) -> Path:
    source = SOURCE_DIR / cover.source_name
    destination = FINAL_DIR / cover.final_name
    if not source.is_file():
        raise FileNotFoundError(source)
    if destination.exists():
        raise FileExistsError(f"Refusing to overwrite {destination}")

    with Image.open(source) as raw:
        artwork = ImageOps.fit(raw.convert("RGB"), CANVAS, method=Image.Resampling.LANCZOS)
    image = add_top_tone(artwork)
    draw = ImageDraw.Draw(image)

    author_font = ImageFont.truetype(str(SANS_FONT), size=39)
    author = "V. I. LENIN"
    author_tracking = 8.5
    if tracked_width(draw, author, author_font, author_tracking) > TITLE_MAX_WIDTH:
        raise RuntimeError("Author line exceeds safe area")
    draw_tracked_text(draw, (SAFE_X, AUTHOR_BASELINE_Y), author, author_font, ORANGE_RED, author_tracking)
    draw.rounded_rectangle((SAFE_X, RULE_Y, SAFE_X + 150, RULE_Y + 9), radius=4, fill=IVORY)

    title_end_y = draw_title(draw, cover.title_lines)

    if cover.edition_lines:
        edition_font = ImageFont.truetype(str(SANS_FONT), size=37)
        edition_tracking = 2.2
        edition_y = title_end_y + 58
        for line in cover.edition_lines:
            if tracked_width(draw, line, edition_font, edition_tracking) > TITLE_MAX_WIDTH:
                raise RuntimeError(f"Edition line exceeds safe area: {line}")
            draw_tracked_text(
                draw,
                (SAFE_X, edition_y),
                line,
                edition_font,
                IVORY,
                edition_tracking,
            )
            edition_y += 50
        if edition_y > 850:
            raise RuntimeError("Edition block intrudes into illustration")

    metadata = PngImagePlugin.PngInfo()
    metadata.add_text("Title", cover.exact_title)
    metadata.add_text("Author", "V. I. Lenin")
    metadata.add_text("Artwork source", cover.source_name)
    metadata.add_text("Typography", "New York Regular; Arial Bold")
    if cover.edition_line:
        metadata.add_text("Edition", cover.edition_line)

    FINAL_DIR.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(destination, format="PNG", optimize=True, pnginfo=metadata)
    return destination


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", type=int, choices=range(7, 13))
    args = parser.parse_args()
    selected = [cover for cover in COVERS if args.only is None or cover.number == args.only]
    outputs = [render(cover) for cover in selected]
    for output in outputs:
        print(output)


if __name__ == "__main__":
    main()
