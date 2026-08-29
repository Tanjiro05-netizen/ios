#!/usr/bin/env python3
"""Compose the accepted Lenin-A covers without overwriting existing assets."""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
SOURCE_DIR = ROOT / "source-artwork"
FINAL_DIR = ROOT / "final"
MANIFEST_PATH = ROOT / "manifest.json"

CANVAS = (1200, 1800)
SAFE_X = 108
SAFE_TOP = 162
TITLE_TOP = 278
TITLE_BOTTOM = 790

TITLE_FONT_PATH = Path("/System/Library/Fonts/NewYork.ttf")
AUTHOR_FONT_PATH = Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf")

WARM_IVORY = (239, 226, 197, 255)
ORANGE_RED = (190, 61, 31, 255)
CHARCOAL = (13, 14, 13, 255)


@dataclass(frozen=True)
class CoverSpec:
    number: int
    slug: str
    exact_title: str
    title_lines: tuple[str, ...]
    max_title_size: int
    source_filename: str
    final_filename: str
    prompt: str
    cleanup_regions: tuple[tuple[int, int, int, int, float], ...] = ()


SPECS = (
    CoverSpec(
        1,
        "materialism-and-empirio-criticism",
        "Materialism and Empirio-Criticism",
        ("Materialism and", "Empirio-Criticism"),
        92,
        "01-materialism-and-empirio-criticism-artwork.png",
        "01-materialism-and-empirio-criticism-v2.png",
        """Use case: stylized-concept
Asset type: artwork-only source for a 2:3 portrait book cover
Primary request: Create an original archival political-poster illustration for V. I. Lenin's philosophical work Materialism and Empirio-Criticism. Represent the conflict between material reality and idealist abstraction through a solid industrial still life—machined metal sphere, glass prism, optical lens, drafting compass, and intersecting measurement lines—anchored on a heavy tabletop, with a distorted ghostlike reflection dissolving behind it.
Scene/backdrop: deep charcoal field with restrained warm-ivory paper texture; historically plausible late-19th/early-20th-century scientific instruments.
Style/medium: restrained linocut and photomontage, coarse newsprint grain, sharp poster contrast, handmade ink edges; original composition, not a copy of any existing cover.
Composition/framing: 2:3 portrait; motif concentrated in the middle and lower half; keep the upper 42% predominantly dark and uncluttered for later typography; keep all objects at least 9% inside every edge.
Lighting/mood: urgent, analytical, severe rather than triumphalist.
Color palette: charcoal, warm ivory, orange-red accent, restrained black.
Constraints: artwork only. Absolutely no words, letters, numbers, captions, title, author name, quotations, slogans, logos, signatures, publisher marks, or watermark. No contemporary objects. No photorealistic cover mockup, spine, frame, or book object.""",
    ),
    CoverSpec(
        2,
        "one-step-forward-two-steps-back",
        "One Step Forward, Two Steps Back: The Crisis in Our Party",
        ("One Step Forward,", "Two Steps Back:", "The Crisis in Our", "Party"),
        78,
        "02-one-step-forward-two-steps-back-artwork.png",
        "02-one-step-forward-two-steps-back-v2.png",
        """Use case: stylized-concept
Asset type: artwork-only source for a 2:3 portrait book cover
Primary request: Create an original archival political-poster illustration for V. I. Lenin's work One Step Forward, Two Steps Back — The Crisis in Our Party. Express organizational advance, reversal, and internal crisis through a monumental constructivist staircase and railway-switch geometry: one forceful stair rising forward, two smaller stair flights breaking backward, converging rails, a single orange-red switch lever, and scattered blank meeting papers.
Scene/backdrop: deep charcoal field with warm-ivory paper texture; industrial, historically plausible early-20th-century materials.
Style/medium: restrained linocut and photomontage, coarse newsprint grain, sharp poster contrast, handmade ink edges; original composition, not a copy of any existing cover.
Composition/framing: 2:3 portrait; structure concentrated in the middle and lower half; keep the upper 42% predominantly dark and uncluttered for later typography; preserve at least 9% safe margin on every edge.
Lighting/mood: urgent, analytical, tense rather than heroic or triumphalist.
Color palette: charcoal, warm ivory, orange-red accent, restrained black.
Constraints: artwork only. Blank papers only. Absolutely no words, letters, numbers, captions, title, author name, quotations, slogans, flags with symbols, logos, signatures, publisher marks, or watermark. No contemporary objects. No photorealistic cover mockup, spine, frame, or book object.""",
    ),
    CoverSpec(
        3,
        "two-tactics-democratic-revolution",
        "TWO TACTICS OF SOCIAL-DEMOCRACY IN THE DEMOCRATIC REVOLUTION",
        ("TWO TACTICS OF", "SOCIAL-DEMOCRACY", "IN THE DEMOCRATIC", "REVOLUTION"),
        64,
        "03-two-tactics-democratic-revolution-artwork.png",
        "03-two-tactics-democratic-revolution-v2.png",
        """Use case: historical-scene
Asset type: artwork-only source for a 2:3 portrait book cover
Primary request: Create an original archival political-poster illustration for V. I. Lenin's Two Tactics of Social Democracy. Show a historically grounded 1905 urban workers' movement through two sharply diverging but related routes emerging from one crowd: two processional paths divided by angular street geometry, one passing factory gates and one approaching a civic square, seen from a slightly elevated viewpoint.
Scene/backdrop: early-20th-century Russian industrial city rendered without identifiable signs; cobbles, factory silhouettes, plain banners with no marks.
Subject: small anonymous worker figures and two directional routes, not a heroic leader portrait.
Style/medium: restrained linocut and photomontage, coarse newsprint grain, high-contrast archival poster; original composition, not a copy of an existing cover.
Composition/framing: 2:3 portrait; crowd and route geometry centered in the middle and lower half; keep the upper 42% predominantly charcoal and uncluttered for later typography; all faces, symbols, and objects at least 9% inside every edge.
Lighting/mood: strategic, urgent, collective, analytical; avoid triumphalist propaganda pastiche.
Color palette: charcoal, warm ivory, orange-red, restrained black.
Constraints: artwork only. Absolutely no words, letters, numbers, captions, title, author name, quotations, slogans, logos, signatures, publisher marks, or watermark. Banners must be completely blank. No modern clothing, vehicles, or buildings. No photorealistic cover mockup, spine, frame, or book object.""",
    ),
    CoverSpec(
        4,
        "what-is-to-be-done",
        "WHAT IS TO BE DONE?",
        ("WHAT IS TO BE", "DONE?"),
        104,
        "04-what-is-to-be-done-artwork.png",
        "04-what-is-to-be-done-v2.png",
        """Use case: historical-scene
Asset type: artwork-only source for a 2:3 portrait book cover
Primary request: Create an original archival political-poster illustration for V. I. Lenin's What Is to Be Done? Depict a clandestine turn-of-the-century printing workspace: a hand-operated press, movable type blocks turned away so they are unreadable, ink roller, warm desk lamp, and two workers' hands arranging perfectly blank sheets for distribution.
Scene/backdrop: modest 1902-era print room at night, deep shadows, rough wood and metal, no modern equipment.
Style/medium: restrained linocut and photomontage, coarse newsprint grain, strong poster contrast, handmade ink edges; original composition, not a copy of an existing cover.
Composition/framing: 2:3 portrait; press and hands concentrated in middle and lower half; leave the upper 42% as predominantly dark, uncluttered negative space for later typography; preserve a 9% safe margin.
Lighting/mood: conspiratorial, disciplined, urgent, analytical; not romanticized or triumphalist.
Color palette: charcoal, warm ivory, orange-red lamplight, restrained black.
Constraints: artwork only. Sheets must be fully blank and type must be unreadable abstract texture. Absolutely no words, letters, numbers, captions, title, author name, quotations, slogans, logos, signatures, publisher marks, or watermark. No contemporary objects. No photorealistic cover mockup, spine, frame, or book object.""",
    ),
    CoverSpec(
        5,
        "imperialism-highest-stage",
        "Imperialism: The Highest Stage of Capitalism",
        ("Imperialism:", "The Highest Stage", "of Capitalism"),
        86,
        "05-imperialism-highest-stage-artwork.png",
        "05-imperialism-highest-stage-v2.png",
        """Use case: stylized-concept
Asset type: artwork-only source for a 2:3 portrait book cover
Primary request: Create an original archival political-poster illustration for V. I. Lenin's Imperialism: The Highest Stage of Capitalism. Visualize global monopoly and extraction as a weathered globe gripped by steel bands and shipping cables, connected to factory chimneys, a battleship silhouette, rail freight, and a bank-vault mechanism—one integrated system rather than a collage of unrelated icons.
Scene/backdrop: deep charcoal field and warm-ivory newsprint texture, historically plausible early-20th-century industrial forms.
Style/medium: restrained linocut and photomontage, coarse newsprint grain, hard poster contrast, handmade ink edges; original composition, not a copy of any existing cover.
Composition/framing: 2:3 portrait; system concentrated in middle and lower half; keep upper 42% predominantly dark and uncluttered for later typography; all imagery at least 9% inside the edges.
Lighting/mood: ominous, analytical, systemic; avoid sensational or triumphalist propaganda.
Color palette: charcoal, warm ivory, orange-red routes, restrained black.
Constraints: artwork only. No national flags, emblems, currency symbols, labels, maps with place names, or contemporary objects. Absolutely no words, letters, numbers, captions, title, author name, quotations, slogans, logos, signatures, publisher marks, or watermark. No photorealistic cover mockup, spine, frame, or book object.""",
    ),
    CoverSpec(
        6,
        "karl-marx-biographical-sketch",
        "Karl Marx: A Brief Biographical Sketch with an Exposition of Marxism",
        ("Karl Marx:", "A Brief Biographical", "Sketch with an", "Exposition of Marxism"),
        72,
        "06-karl-marx-biographical-sketch-artwork.png",
        "06-karl-marx-biographical-sketch-v3.png",
        """Use case: historical-scene
Asset type: artwork-only source for a 2:3 portrait book cover
Primary request: Create an original archival political-poster illustration for V. I. Lenin's Karl Marx: A Brief Biographical Sketch with an Exposition of Marxism. Create a dignified, historically recognizable but clearly hand-rendered linocut portrait of Karl Marx in three-quarter profile, with his characteristic full beard, integrated with blank manuscript pages, a reading desk, and a restrained industrial panorama of mills and rail lines.
Scene/backdrop: dark archival field with warm-ivory paper texture; 19th-century study and industrial elements.
Style/medium: restrained linocut and photomontage, coarse newsprint grain, high-contrast poster, visibly handmade ink edges; original interpretation, not a photorealistic copy of a known photograph and not a copy of an existing cover.
Composition/framing: 2:3 portrait; Marx portrait and supporting imagery concentrated in middle and lower half; keep the upper 42% predominantly dark and uncluttered for later typography; maintain at least 9% safe margin.
Lighting/mood: intellectually forceful, analytical, historical; humane rather than monumental or triumphalist.
Color palette: charcoal, warm ivory, orange-red accent, restrained black.
Constraints: artwork only. Manuscript pages must be blank. Absolutely no words, letters, numbers, captions, title, author name, quotations, slogans, logos, signatures, publisher marks, or watermark. No contemporary objects. No photorealistic cover mockup, spine, frame, or book object.""",
    ),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tracked_text(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, font: ImageFont.FreeTypeFont, fill: tuple[int, int, int, int], tracking: int) -> None:
    x, y = xy
    for character in text:
        draw.text((x, y), character, font=font, fill=fill, anchor="ls")
        x += int(round(font.getlength(character))) + tracking


def title_font_and_height(lines: tuple[str, ...], max_size: int) -> tuple[ImageFont.FreeTypeFont, int]:
    max_width = CANVAS[0] - (SAFE_X * 2)
    max_height = TITLE_BOTTOM - TITLE_TOP
    size = max_size
    while size >= 42:
        font = ImageFont.truetype(str(TITLE_FONT_PATH), size)
        line_height = int(round(size * 1.12))
        widest = max(font.getlength(line) for line in lines)
        total_height = line_height * len(lines)
        if widest <= max_width and total_height <= max_height:
            return font, line_height
        size -= 1
    raise ValueError(f"Title cannot fit: {lines!r}")


def apply_cleanup(image: Image.Image, regions: tuple[tuple[int, int, int, int, float], ...]) -> Image.Image:
    cleaned = image.copy()
    for left, top, right, bottom, radius in regions:
        blurred = cleaned.filter(ImageFilter.GaussianBlur(radius=radius))
        mask = Image.new("L", CANVAS, 0)
        ImageDraw.Draw(mask).rounded_rectangle((left, top, right, bottom), radius=18, fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(radius=max(10, int(radius * 5))))
        cleaned = Image.composite(blurred, cleaned, mask)
    return cleaned


def title_line(draw: ImageDraw.ImageDraw, xy: tuple[int, int], line: str, font: ImageFont.FreeTypeFont) -> None:
    """Draw a New York title line and reinforce its otherwise hairline hyphen glyph."""
    x, y = xy
    draw.text((x, y), line, font=font, fill=WARM_IVORY, anchor="lt")
    for index, character in enumerate(line):
        if character != "-":
            continue
        hyphen_x = x + int(round(font.getlength(line[:index]))) + 2
        hyphen_y = y + int(round(font.size * 0.58))
        hyphen_width = max(18, int(round(font.size * 0.24)))
        hyphen_height = max(3, int(round(font.size * 0.045)))
        draw.rounded_rectangle(
            (hyphen_x, hyphen_y, hyphen_x + hyphen_width, hyphen_y + hyphen_height),
            radius=max(1, hyphen_height // 2),
            fill=WARM_IVORY,
        )


def top_scrim(image: Image.Image) -> Image.Image:
    overlay = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    pixels = overlay.load()
    for y in range(0, 980):
        if y <= 720:
            alpha = 74
        else:
            alpha = int(round(74 * (1 - ((y - 720) / 260))))
        for x in range(CANVAS[0]):
            pixels[x, y] = (0, 0, 0, max(0, alpha))
    return Image.alpha_composite(image.convert("RGBA"), overlay)


def compose(spec: CoverSpec) -> dict[str, object]:
    source = SOURCE_DIR / spec.source_filename
    output = FINAL_DIR / spec.final_filename
    if not source.is_file():
        raise FileNotFoundError(source)
    if output.exists():
        raise FileExistsError(f"Refusing to overwrite {output}")

    artwork = Image.open(source).convert("RGB")
    artwork = ImageOps.fit(artwork, CANVAS, method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))
    artwork = apply_cleanup(artwork, spec.cleanup_regions)
    cover = top_scrim(artwork)
    draw = ImageDraw.Draw(cover)

    author_font = ImageFont.truetype(str(AUTHOR_FONT_PATH), 34)
    author_ascent, _ = author_font.getmetrics()
    tracked_text(draw, (SAFE_X, SAFE_TOP + author_ascent), "V. I. LENIN", author_font, WARM_IVORY, tracking=7)
    draw.rounded_rectangle((SAFE_X, 232, CANVAS[0] - SAFE_X, 235), radius=1, fill=ORANGE_RED)

    title_font, line_height = title_font_and_height(spec.title_lines, spec.max_title_size)
    y = TITLE_TOP
    for line in spec.title_lines:
        title_line(draw, (SAFE_X, y), line, title_font)
        y += line_height

    cover.convert("RGB").save(output, "PNG", optimize=True)
    return {
        "source": str(source.relative_to(ROOT)),
        "source_sha256": sha256(source),
        "final": str(output.relative_to(ROOT)),
        "final_sha256": sha256(output),
        "title_font_size": title_font.size,
        "title_line_height": line_height,
    }


def compose_all(selected_number: int | None = None) -> None:
    FINAL_DIR.mkdir(parents=True, exist_ok=True)
    for spec in SPECS:
        if selected_number is not None and spec.number != selected_number:
            continue
        result = compose(spec)
        print(f"COMPOSED {spec.number}: {result['final']}")


def write_manifest() -> None:
    if MANIFEST_PATH.exists():
        raise FileExistsError(f"Refusing to overwrite {MANIFEST_PATH}")

    covers = []
    for spec in SPECS:
        source = SOURCE_DIR / spec.source_filename
        final = FINAL_DIR / spec.final_filename
        if not source.is_file() or not final.is_file():
            raise FileNotFoundError(f"Missing accepted source/final pair for {spec.slug}")
        with Image.open(final) as image:
            if image.size != CANVAS or image.format != "PNG":
                raise ValueError(f"Invalid final format for {final}: {image.format} {image.size}")
        covers.append(
            {
                "number": spec.number,
                "slug": spec.slug,
                "exact_title": spec.exact_title,
                "author_line": "V. I. LENIN",
                "accepted": True,
                "generation_mode": "built-in image_gen; one distinct call for this title; artwork only",
                "prompt": spec.prompt,
                "source_artwork": str(source.relative_to(ROOT)),
                "source_sha256": sha256(source),
                "final_cover": str(final.relative_to(ROOT)),
                "final_sha256": sha256(final),
                "final_format": "PNG",
                "final_dimensions": {"width": CANVAS[0], "height": CANVAS[1]},
                "title_lines": list(spec.title_lines),
            }
        )

    manifest = {
        "batch": "lenin-a",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "brief": "../COVER_BRIEF.md",
        "status": "accepted_after_visual_qa",
        "revision_note": "Accepted v2 finals replace non-overwritten initial previews. V2 keeps tracked author punctuation on a common baseline, visibly reinforces required hyphens, uses the canonical colon in One Step Forward, Two Steps Back: The Crisis in Our Party, and removes hard-edged cleanup seams.",
        "typography": {
            "title_font": str(TITLE_FONT_PATH),
            "author_font": str(AUTHOR_FONT_PATH),
            "author_tracking_px": 7,
            "author_font_size_px": 34,
            "author_line": "V. I. LENIN",
            "title_color_rgba": list(WARM_IVORY),
            "rule_color_rgba": list(ORANGE_RED),
            "horizontal_safe_margin_px": SAFE_X,
        },
        "publishing": {
            "uploaded": False,
            "supabase_touched": False,
            "catalog_records_changed": False,
        },
        "covers": covers,
    }
    with MANIFEST_PATH.open("x", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"WROTE {MANIFEST_PATH.relative_to(ROOT)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-manifest", action="store_true", help="write the accepted manifest after visual QA")
    parser.add_argument("--number", type=int, choices=range(1, 7), help="compose only one numbered cover")
    args = parser.parse_args()
    if args.write_manifest:
        write_manifest()
    else:
        compose_all(args.number)


if __name__ == "__main__":
    main()
