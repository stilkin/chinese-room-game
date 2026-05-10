"""Regenerate the temporary launcher icon (皮影 stacked, centred).

Renders each character to a transparent scratch canvas, crops to its actual
ink bbox (PIL's `textbbox` returns the em-square for CJK fonts which
doesn't match the visible-pixel bounds), then pastes centred onto the
final canvas. Pixel-precise vertical and horizontal centering with
generous padding.

Run from the repo root:

    python3 apps/mobile/scripts/gen_icon.py

Output: apps/mobile/assets/icon/icon.png. After regenerating, run
`flutter pub run flutter_launcher_icons` from `apps/mobile/` to refresh
the platform mipmaps.
"""
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
BG = (0x1A, 0x16, 0x12)               # PiYingTheme.bg
FG = (0xEA, 0xD8, 0xB5, 0xFF)         # PiYingTheme.onSurface
FONT_SIZE = 320                        # ~31% of canvas — comfortable padding


def main() -> None:
    here = Path(__file__).resolve()
    icon_path = here.parent.parent / 'assets' / 'icon' / 'icon.png'

    font_candidates = [
        ('/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc', 2),  # JP
        ('/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc', 0),
        ('/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc', 0),
    ]
    font = None
    for path, idx in font_candidates:
        if not os.path.exists(path):
            continue
        try:
            font = ImageFont.truetype(path, FONT_SIZE, index=idx)
            print(f'Using {path} index={idx}')
            break
        except Exception as e:
            print(f'Skip {path}: {e}')
    if font is None:
        raise SystemExit(
            'No CJK-capable font found. Install Noto Serif CJK or Noto Sans CJK.'
        )

    img = Image.new('RGBA', (SIZE, SIZE), BG + (0xFF,))

    top = _render_glyph(font, '皮')
    bot = _render_glyph(font, '影')
    print(f'  皮 ink: {top.size}')
    print(f'  影 ink: {bot.size}')

    img.paste(top, _centre_offset(top, cx=SIZE / 2, cy=SIZE * 0.30), top)
    img.paste(bot, _centre_offset(bot, cx=SIZE / 2, cy=SIZE * 0.70), bot)

    icon_path.parent.mkdir(parents=True, exist_ok=True)
    img.convert('RGB').save(icon_path)
    print(f'Wrote {icon_path}')


def _render_glyph(font: ImageFont.FreeTypeFont, text: str) -> Image.Image:
    """Render `text` to a transparent canvas, cropped to its ink bbox."""
    pad = 200
    side = FONT_SIZE * 2 + pad * 2
    tmp = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    ImageDraw.Draw(tmp).text((pad, pad), text, font=font, fill=FG)
    return tmp.crop(tmp.getbbox())


def _centre_offset(img: Image.Image, *, cx: float, cy: float) -> tuple[int, int]:
    return (int(cx - img.width / 2), int(cy - img.height / 2))


if __name__ == '__main__':
    main()
