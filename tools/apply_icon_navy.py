"""把「深夜蓝底 + 琥珀盾形锁 + LW」写入应用图标资源。

背景：#14223E → #080E1C 渐变
图形：tools/make_icon_lockwarden.py 的 design_b（白色描边、深色 LW 与钥匙孔）
"""
import importlib.util
import os
import sys

from PIL import Image, ImageDraw

SIZE = 1024
TOOLS = r'D:\workspace\LockWarden\tools\make_icon_lockwarden.py'
OUT_APP = r'D:\workspace\LockWarden\AppScope\resources\base\media'
OUT_ENTRY = r'D:\workspace\LockWarden\entry\src\main\resources\base\media'
DOCS = r'D:\workspace\docs'

TOP = (20, 34, 62)
BOTTOM = (8, 14, 28)
WHITE = (255, 255, 255)
DARK = (38, 40, 44)


def load_mk():
    spec = importlib.util.spec_from_file_location('mk', TOOLS)
    mk = importlib.util.module_from_spec(spec)
    sys.modules['mk'] = mk
    spec.loader.exec_module(mk)
    return mk


def rounded(img, size, r=0.225):
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1],
                                        radius=int(size * r), fill=255)
    out.paste(img, (0, 0), m)
    return out


def main():
    mk = load_mk()
    bg = mk.gradient(SIZE, TOP, BOTTOM).convert('RGBA')
    fg = mk.design_b(SIZE, ink=WHITE, text=DARK)

    for out in (OUT_APP, OUT_ENTRY):
        os.makedirs(out, exist_ok=True)
        bg.convert('RGB').save(os.path.join(out, 'background.png'))
        fg.save(os.path.join(out, 'foreground.png'))

    comp = bg.copy()
    comp.alpha_composite(fg)

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
    print('applied midnight-navy icon')


if __name__ == '__main__':
    main()
