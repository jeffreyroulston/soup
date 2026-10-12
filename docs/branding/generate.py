"""Generate Soup "fill line" brand masters from Manrope ExtraBold outlines."""
import json
import sys
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

out = Path(sys.argv[1])
font = TTFont(sys.argv[2])
upm = font['head'].unitsPerEm
gs = font.getGlyphSet()
cmap = font.getBestCmap()
TRACK = -0.04 * upm


def r(v):
    s = f'{v:.4f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


class Pen(BasePen):
    """Records em-normalised, y-down outlines as SVG `d` and Dart Path calls."""

    def __init__(self, glyphset, dx):
        super().__init__(glyphset)
        self.dx = dx
        self.svg = []
        self.dart = []

    def p(self, pt):
        return ((pt[0] + self.dx) / upm, -pt[1] / upm)

    def _moveTo(self, pt):
        x, y = self.p(pt)
        self.svg.append(f'M{r(x)} {r(y)}')
        self.dart.append(f'..moveTo({r(x)}, {r(y)})')

    def _lineTo(self, pt):
        x, y = self.p(pt)
        self.svg.append(f'L{r(x)} {r(y)}')
        self.dart.append(f'..lineTo({r(x)}, {r(y)})')

    def _qCurveToOne(self, p1, p2):
        (x1, y1), (x2, y2) = self.p(p1), self.p(p2)
        self.svg.append(f'Q{r(x1)} {r(y1)} {r(x2)} {r(y2)}')
        self.dart.append(f'..quadraticBezierTo({r(x1)}, {r(y1)}, {r(x2)}, {r(y2)})')

    def _curveToOne(self, p1, p2, p3):
        (x1, y1), (x2, y2), (x3, y3) = self.p(p1), self.p(p2), self.p(p3)
        self.svg.append(f'C{r(x1)} {r(y1)} {r(x2)} {r(y2)} {r(x3)} {r(y3)}')
        self.dart.append(f'..cubicTo({r(x1)}, {r(y1)}, {r(x2)}, {r(y2)}, {r(x3)}, {r(y3)})')

    def _closePath(self):
        self.svg.append('Z')
        self.dart.append('..close()')


glyphs = {}
x = 0.0
minx = miny = 1e9
maxx = maxy = -1e9
for ch in 'soup':
    name = cmap[ord(ch)]
    g = gs[name]
    pen = Pen(gs, x)
    g.draw(pen)
    b = BoundsPen(gs)
    g.draw(b)
    bx0, by0, bx1, by1 = b.bounds
    minx, maxx = min(minx, bx0 + x), max(maxx, bx1 + x)
    miny, maxy = min(miny, by0), max(maxy, by1)
    glyphs[ch] = dict(svg=''.join(pen.svg), dart=pen.dart, bounds=(bx0 + x, by0, bx1 + x, by1))
    x += g.width + TRACK

# Fill line: just below the o's optical centre, matching the icon (52 of a 50-centred ring).
ob = glyphs['o']['bounds']
o_mid = (ob[1] + ob[3]) / 2
o_h = ob[3] - ob[1]
level = -(o_mid - 0.03 * o_h) / upm  # y-down, em units

box = dict(
    left=minx / upm, top=-maxy / upm, width=(maxx - minx) / upm, height=(maxy - miny) / upm,
    level=level,
)
(out / 'wordmark.json').write_text(json.dumps(dict(box=box, glyphs={k: v['svg'] for k, v in glyphs.items()}), indent=1))

dart_lines = []
for ch in 'soup':
    dart_lines.append(f'  static final {"o" if ch == "o" else ch}Glyph = Path()')
    dart_lines += ['    ' + c for c in glyphs[ch]['dart']]
    dart_lines[-1] += ';'
    dart_lines.append('')
(out / 'wordmark_paths.dart.txt').write_text('\n'.join(dart_lines))


def wordmark_svg(ink, accent, pad=0.0, extra=''):
    vb = f"{r(box['left'] - pad)} {r(box['top'] - pad)} {r(box['width'] + 2 * pad)} {r(box['height'] + 2 * pad)}"
    top, lv = box['top'] - 1, level
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" role="img" aria-label="soup">'
        f'<defs><clipPath id="a"><rect x="-1" y="{r(top)}" width="9" height="{r(lv - top)}"/></clipPath>'
        f'<clipPath id="b"><rect x="-1" y="{r(lv)}" width="9" height="3"/></clipPath></defs>'
        f'<path fill="{ink}" d="{glyphs["s"]["svg"]}{glyphs["u"]["svg"]}{glyphs["p"]["svg"]}"/>'
        f'<path fill="{ink}" clip-path="url(#a)" d="{glyphs["o"]["svg"]}"/>'
        f'<path fill="{accent}" clip-path="url(#b)" d="{glyphs["o"]["svg"]}"/>{extra}</svg>\n'
    )


(out / 'soup-wordmark.svg').write_text(wordmark_svg('#F5F5F7', '#FC7814'))
(out / 'soup-wordmark-light.svg').write_text(wordmark_svg('#1D1D1F', '#E86A0C'))

# The mark on a 100 grid: ring r30/stroke 9, liquid r22.5 filling below y=52.
MARK = (
    '<circle cx="50" cy="50" r="30" fill="none" stroke="{ink}" stroke-width="9"/>'
    '<path d="M27.5 52A22.5 22.5 0 0 0 72.5 52Z" fill="{accent}"/>'
)
BG = (
    '<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
    '<stop offset="0" stop-color="#1C1C1E"/><stop offset="1" stop-color="#050506"/></linearGradient></defs>'
)
mark = MARK.format(ink='#F5F5F7', accent='#FC7814')

(out / 'soup-mark.svg').write_text(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="15.5 15.5 69 69">{mark}</svg>\n')
(out / 'soup-mark-light.svg').write_text(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="15.5 15.5 69 69">'
    f'{MARK.format(ink="#1D1D1F", accent="#E86A0C")}</svg>\n')
# Full-bleed square for platforms that apply their own mask (iOS, Android legacy, PWA).
(out / 'soup-icon.svg').write_text(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">{BG}'
    f'<rect width="100" height="100" fill="url(#bg)"/>{mark}</svg>\n')
# Pre-rounded tile for browser tabs and in-app use.
(out / 'soup-icon-rounded.svg').write_text(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">{BG}'
    f'<rect width="100" height="100" rx="22.5" fill="url(#bg)"/>{mark}</svg>\n')
# Android adaptive foreground: transparent, ring at 78% of the inset art box.
(out / 'android-foreground.svg').write_text(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="5.75 5.75 88.5 88.5">{mark}</svg>\n')

# Android TV banner, 320x180dp: mark + wordmark on the icon gradient.
s = 64 / 1.0  # wordmark font size in banner units
wm_w = box['width'] * s
mark_size = 64
gap = 14
total = mark_size + gap + wm_w
x0 = (320 - total) / 2
wm = wordmark_svg('#F5F5F7', '#FC7814')
inner = wm[wm.index('<defs>'):wm.rindex('</svg>')]
banner = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 180">'
    '<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
    '<stop offset="0" stop-color="#1C1C1E"/><stop offset="1" stop-color="#050506"/></linearGradient></defs>'
    '<rect width="320" height="180" fill="url(#bg)"/>'
    f'<svg x="{r(x0)}" y="{r(90 - mark_size / 2)}" width="{mark_size}" height="{mark_size}" viewBox="15.5 15.5 69 69">{mark}</svg>'
    f'<g transform="translate({r(x0 + mark_size + gap - box["left"] * s)} {r(90 - box["top"] / 2 * s)}) scale({r(s)})">{inner}</g>'
    '</svg>\n'
)
(out / 'android-tv-banner.svg').write_text(banner)
print(json.dumps(box))
