"""LockWarden 图标方案（仅出预览，不写入应用资源）。

统一风格：粗描边、扁平、深灰 + 琥珀黄，浅色底，便于小尺寸识别。

A「字母锁」：挂锁轮廓，锁体内是 LW 字样 + 钥匙孔
B「盾字」：盾形描边，内部大 W，顶部一个小钥匙孔
C「徽章」：琥珀色圆角方牌，深色 LW 字母，顶上一个小锁梁

输出：docs/lw-a.png / lw-b.png / lw-c.png / lw-options.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
DOCS = r'D:\workspace\docs'

INK = (38, 40, 44)
AMBER = (245, 178, 62)
CREAM_TOP = (255, 253, 250)
CREAM_BOTTOM = (243, 236, 226)
FONT_BOLD = r'C:\Windows\Fonts\arialbd.ttf'
FONT_ALT = r'C:\Windows\Fonts\seguisb.ttf'


def gradient(size, top, bottom):
    img = Image.new('RGB', (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x * 0.25 + y * 0.75) / (size - 1)
            px[x, y] = (int(top[0] + (bottom[0] - top[0]) * t),
                        int(top[1] + (bottom[1] - top[1]) * t),
                        int(top[2] + (bottom[2] - top[2]) * t))
    return img


def font(size):
    for path in (FONT_BOLD, FONT_ALT):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def draw_arc_stroke(d, box, start, end, width, color):
    d.arc(box, start=start, end=end, fill=color, width=width)


def shield_polygon(size, top, bottom, half, r, cx=0.5):
    import math
    cxx = size * cx
    tp, hp, rp, bp = size * top, size * half, size * r, size * bottom
    pts = []
    for deg in range(180, 271, 4):
        a = math.radians(deg)
        pts.append((cxx - hp + rp + rp * math.cos(a), tp + rp + rp * math.sin(a)))
    for deg in range(270, 361, 4):
        a = math.radians(deg)
        pts.append((cxx + hp - rp + rp * math.cos(a), tp + rp + rp * math.sin(a)))
    steps = 120
    right = []
    for i in range(1, steps + 1):
        u = i / steps
        f = 1.0 if u <= 0.30 else max(0.0, (1 - ((u - 0.30) / 0.70) ** 2.1)) ** 0.80
        right.append((cxx + hp * f, (tp + rp) + (bp - (tp + rp)) * u))
    pts.extend(right)
    pts.append((cxx, bp))
    for x, y in reversed(right):
        pts.append((2 * cxx - x, y))
    return pts


def shackle(d, size, r, top, stroke, body_top, color=INK):
    cx = size / 2
    d.arc([cx - r, top, cx + r, top + 2 * r], start=180, end=360, fill=color, width=stroke)
    d.rectangle([cx - r, top + r * 0.85, cx - r + stroke, body_top + stroke * 0.4], fill=color)
    d.rectangle([cx + r - stroke, top + r * 0.85, cx + r, body_top + stroke * 0.4], fill=color)


def lw(d, size, cy, fsize, color):
    f = font(fsize)
    d.text((size / 2, size * cy), 'LW', font=f, fill=color, anchor='mm')


def keyhole(d, size, cy, r, color):
    cx = size / 2
    cyp = size * cy
    rp = size * r
    d.ellipse([cx - rp, cyp - rp, cx + rp, cyp + rp], fill=color)
    d.polygon([(cx - rp * 0.52, cyp + rp * 0.45), (cx + rp * 0.52, cyp + rp * 0.45),
               (cx + rp * 0.30, cyp + rp * 2.4), (cx - rp * 0.30, cyp + rp * 2.4)],
              fill=color)


def design_a(size):
    """方形锁体 + LW + 钥匙孔"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    st = int(size * 0.058)
    shackle(d, size, size * 0.130, size * 0.170, st, size * 0.410)
    d.rounded_rectangle([size * 0.235, size * 0.390, size * 0.765, size * 0.870],
                        radius=size * 0.085, fill=(255, 255, 255, 255),
                        outline=INK, width=st)
    lw(d, size, 0.560, int(size * 0.210), INK)
    keyhole(d, size, 0.775, 0.027, AMBER + (255,))
    return img


def design_b(size, ink=INK, text=None):
    if text is None:
        text = ink
    """盾形锁体 + LW"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    st = int(size * 0.062)
    from PIL import ImageChops
    shackle(d, size, size * 0.152, size * 0.128, st, size * 0.352, ink)
    outer = Image.new('L', (size, size), 0)
    ImageDraw.Draw(outer).polygon(
        shield_polygon(size, top=0.330, bottom=0.885, half=0.272, r=0.098), fill=255)
    inner = Image.new('L', (size, size), 0)
    ImageDraw.Draw(inner).polygon(
        shield_polygon(size, top=0.330 + 0.020, bottom=0.885 - 0.028,
                       half=0.272 - 0.019, r=0.090), fill=255)
    ring = ImageChops.subtract(outer, inner)
    img.paste(Image.new('RGBA', (size, size), ink + (255,)), (0, 0), ring)
    img.paste(Image.new('RGBA', (size, size), AMBER + (255,)), (0, 0), inner)
    lw(d, size, 0.560, int(size * 0.195), text)
    keyhole(d, size, 0.720, 0.025, text)
    return img


def design_c(size):
    """圆角牌锁 + LW"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    st = int(size * 0.062)
    shackle(d, size, size * 0.118, size * 0.150, st, size * 0.375)
    d.rounded_rectangle([size * 0.180, size * 0.355, size * 0.820, size * 0.870],
                        radius=size * 0.115, fill=AMBER + (255,))
    lw(d, size, 0.610, int(size * 0.250), INK)
    return img

def rounded(img, size, r=0.225):
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1],
                                        radius=int(size * r), fill=255)
    out.paste(img, (0, 0), m)
    return out


OUT_APP = r'D:\workspace\VaultWardenHarmony\AppScope\resources\base\media'
OUT_ENTRY = r'D:\workspace\VaultWardenHarmony\entry\src\main\resources\base\media'


def apply_to_app(bg, art):
    """把方案 B 写入应用资源（分层图 + 启动图 + 预览）。"""
    comp = bg.copy()
    comp.alpha_composite(art)
    for out in (OUT_APP, OUT_ENTRY):
        os.makedirs(out, exist_ok=True)
        bg.convert('RGB').save(os.path.join(out, 'background.png'))
        art.save(os.path.join(out, 'foreground.png'))
    rounded(comp.resize((288, 288), Image.LANCZOS), 288).resize((144, 144), Image.LANCZOS).save(
        os.path.join(OUT_ENTRY, 'startIcon.png'))
    rounded(comp.resize((512, 512), Image.LANCZOS), 512).save(os.path.join(DOCS, 'app-icon.png'))
    sizes = [144, 96, 72, 48]
    sheet = Image.new('RGBA', (sum(sizes) + 40 * len(sizes), 200), (240, 243, 247, 255))
    x = 20
    for s in sizes:
        sheet.alpha_composite(rounded(comp.resize((s, s), Image.LANCZOS), s), (x, 30))
        x += s + 40
    sheet.save(os.path.join(DOCS, 'icon-sizes.png'))
    print('applied')


def main():
    bg = gradient(SIZE, CREAM_TOP, CREAM_BOTTOM).convert('RGBA')
    designs = {'a': design_a(SIZE), 'b': design_b(SIZE), 'c': design_c(SIZE)}
    previews = {}
    for key, art in designs.items():
        comp = bg.copy()
        comp.alpha_composite(art)
        previews[key] = rounded(comp.resize((512, 512), Image.LANCZOS), 512)
        previews[key].save(os.path.join(DOCS, f'lw-{key}.png'))

    sheet = Image.new('RGBA', (512 * 3 + 80, 512 + 40), (255, 255, 255, 255))
    for i, key in enumerate(['a', 'b', 'c']):
        sheet.alpha_composite(previews[key], (20 + i * (512 + 20), 12))
    sheet.save(os.path.join(DOCS, 'lw-options.png'))
    if '--apply' in sys.argv:
        apply_to_app(bg, designs['b'])
    print('done')


if __name__ == '__main__':
    main()
