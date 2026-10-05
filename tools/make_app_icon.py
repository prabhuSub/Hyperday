"""Hyperday app icon — "Now Line": your day as blocks, with a red line at now.

    pip install cairosvg && python3 tools/make_app_icon.py [O|A|B|C]   (O = original Now Line, the chosen one)

Writes AppIcon (light / dark / tinted, 1024px) and the small HyperdayMark used on the Lock Screen card.
"""
import sys
from pathlib import Path

import cairosvg

RED, INK = "#E31937", "#111214"


def glyph(v: str, fg="#fff", red=RED, dim=0.5) -> str:
    if v == "G":   # v27: Now Line for iOS 26/27 (Liquid Glass) — thicker round bars, centred with more margin
        return (f'<rect x="19" y="27" width="46" height="13" rx="6.5" fill="{fg}"/>'
                f'<rect x="31" y="43.5" width="51" height="13" rx="6.5" fill="{fg}" opacity=".6"/>'
                f'<rect x="19" y="60" width="34" height="13" rx="6.5" fill="{fg}" opacity=".35"/>'
                f'<rect x="55.5" y="20" width="5" height="62" rx="2.5" fill="{red}"/>'
                f'<circle cx="58" cy="20" r="6" fill="{red}"/>')
    if v == "O":   # the original Now Line: three stacked blocks, red now-line with a pin (chosen)
        return (f'<rect x="18" y="26" width="46" height="11" rx="5.5" fill="{fg}"/>'
                f'<rect x="30" y="44.5" width="52" height="11" rx="5.5" fill="{fg}" opacity=".55"/>'
                f'<rect x="18" y="63" width="34" height="11" rx="5.5" fill="{fg}" opacity=".3"/>'
                f'<rect x="55" y="18" width="4" height="64" rx="2" fill="{red}"/>'
                f'<circle cx="57" cy="18" r="5" fill="{red}"/>')
    if v == "A":   # two blocks, vertical now-line with a pin
        return (f'<rect x="16" y="29" width="46" height="15" rx="7.5" fill="{fg}"/>'
                f'<rect x="38" y="56" width="46" height="15" rx="7.5" fill="{fg}" opacity="{dim}"/>'
                f'<rect x="51" y="21" width="7" height="60" rx="3.5" fill="{red}"/>'
                f'<circle cx="54.5" cy="20" r="8.5" fill="{red}"/>')
    if v == "B":   # same blocks, full-height line, no pin
        return (f'<rect x="16" y="29" width="46" height="15" rx="7.5" fill="{fg}"/>'
                f'<rect x="38" y="56" width="46" height="15" rx="7.5" fill="{fg}" opacity="{dim}"/>'
                f'<rect x="51" y="14" width="8" height="72" rx="4" fill="{red}"/>')
    # C: a day column of blocks with the calendar-style horizontal now-line
    return (f'<rect x="28" y="16" width="44" height="26" rx="8" fill="{fg}" opacity="{dim}"/>'
            f'<rect x="28" y="58" width="44" height="26" rx="8" fill="{fg}"/>'
            f'<rect x="22" y="46.5" width="62" height="7" rx="3.5" fill="{red}"/>'
            f'<circle cx="22" cy="50" r="8" fill="{red}"/>')


def svg(v: str, variant: str, size: int) -> str:
    if variant == "light":
        # Full-bleed square, soft top-light gradient, no baked corners/shadows (iOS adds the glass).
        bg = ('<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
              '<stop offset="0" stop-color="#2a2e38"/><stop offset="1" stop-color="#0c0d10"/></linearGradient></defs>'
              '<rect width="100" height="100" fill="url(#g)"/>') if v == "G" else f'<rect width="100" height="100" fill="{INK}"/>'
        g = glyph(v)
    elif variant == "dark":      # iOS draws its own dark background behind a transparent icon
        bg, g = "", glyph(v)
    else:                        # tinted: grayscale, iOS applies the tint
        bg, g = "", glyph(v, fg="#fff", red="#fff", dim=0.45)
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 100 100">{bg}{g}</svg>'


def check_mark_svg(size: int) -> str:
    # The Lock Screen / Island mark stays the red check (Prabhu's call), separate from the app icon.
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 24 24">'
            f'<rect width="24" height="24" rx="5.5" fill="{RED}"/>'
            f'<path d="M6.2 12.6l3.9 3.9 7.7-8.4" fill="none" stroke="#fff" stroke-width="2.6" '
            f'stroke-linecap="round" stroke-linejoin="round"/></svg>')


def mark_svg(v: str, size: int) -> str:
    # Rounded-square mark for the Lock Screen card (drawn at ~20pt).
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 100 100">'
            f'<rect width="100" height="100" rx="24" fill="{INK}"/>{glyph(v)}</svg>')


if __name__ == "__main__":
    v = (sys.argv[1] if len(sys.argv) > 1 else "G").upper()   # G = v27 (iOS 26/27 rules)
    root = Path(__file__).resolve().parent.parent
    icon = root / "App/Assets.xcassets/AppIcon.appiconset"
    for variant in ("light", "dark", "tinted"):
        cairosvg.svg2png(bytestring=svg(v, variant, 1024).encode(), write_to=str(icon / f"AppIcon-{variant}.png"))
    for cat in ("App", "Widget"):
        cairosvg.svg2png(bytestring=check_mark_svg(96).encode(),
                         write_to=str(root / f"{cat}/Assets.xcassets/HyperdayMark.imageset/HyperdayMark.png"))
    # Layers for Apple's Icon Composer (drag in for full Liquid Glass depth): background, blocks, now-line.
    layers = root / "tools/icon-layers"
    layers.mkdir(exist_ok=True)
    head = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 100 100">'
    (layers / "1-background.svg").write_text(head + svg(v, "light", 1024).split(">", 1)[1].split("<rect x=")[0] + "</svg>")
    full = glyph(v)
    blocks = "".join(p + "/>" for p in full.split("/>") if 'height="13"' in p)
    line = "".join(p + "/>" for p in full.split("/>") if ("#E31937" in p or 'fill="' + RED + '"' in p) and p.strip())
    (layers / "2-blocks.svg").write_text(head + blocks + "</svg>")
    (layers / "3-now-line.svg").write_text(head + line + "</svg>")
    print("app icon", v)
