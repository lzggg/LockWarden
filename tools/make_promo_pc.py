"""生成鸿蒙电脑（2in1）应用市场宣传图：1920x1080（16:9），5 张。

风格与手机/平板版一致：浅色底 + 蓝紫渐变、大标题 + 胶囊标签 + 圆角窗口样机。
截图来自电脑模拟器（本机测试数据），不含真实账号信息。

用法：python tools/make_promo_pc.py
输出：docs/store-promo/pc/*.png 与同名 .jpg
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

DOCS = r'D:\workspace\docs'
OUT = os.path.join(DOCS, 'store-promo', 'pc')
FONT_BOLD = r'C:\Windows\Fonts\msyhbd.ttc'
FONT_REGULAR = r'C:\Windows\Fonts\msyh.ttc'

W, H = 1920, 1080
BG = (238, 241, 248)
INK = (24, 28, 40)
SUB = (92, 100, 120)
ACCENT = (47, 107, 255)
ACCENT2 = (123, 92, 255)

SLIDES = [
    {
        'slug': '01-vault',
        'file': 'pc-vault-demo.jpeg',
        'style': 'window',
        'crop': (515, 335, 2420, 1670),
        'title': ['密码保险库', '装进鸿蒙电脑'],
        'subtitle': '条目、文件夹、回收站都在一个窗口里',
        'pills': ['自建服务器', '本机保险库'],
        'covers': [(385, 17, 532, 76)],
    },
    {
        'slug': '02-server',
        'file': 'pc-run.jpeg',
        'style': 'window',
        'crop': (515, 335, 2604, 1670),
        'title': ['连接你的', 'Vaultwarden 服务器'],
        'subtitle': '兼容 Bitwarden 协议，数据只走你自己的服务器',
        'pills': ['强制 HTTPS', '端到端加密'],
    },
    {
        'slug': '03-settings',
        'file': 'pc-settings.jpeg',
        'style': 'window',
        'crop': (400, 90, 2720, 1340),
        'title': ['安全设置', '一眼看清'],
        'subtitle': '自动锁定、禁止截屏、剪贴板自动清除',
        'pills': ['自动锁定', '隐私保护'],
    },
    {
        'slug': '04-generator',
        'file': 'pc-generator-demo.jpeg',
        'style': 'window',
        'crop': (515, 335, 2420, 1670),
        'title': ['强密码', '一键生成'],
        'subtitle': '长度与字符集可调，密码只在本地生成',
        'pills': ['本地生成', '可调长度'],
    },
    {
        'slug': '05-notify',
        'file': 'pc-notification-center.jpeg',
        'style': 'panel',
        'crop': (2425, 25, 3110, 430),
        'title': ['复制用户名', '通知栏一键取密码'],
        'subtitle': '点一下通知，就能取到同一账号的密码',
        'pills': ['通知复制', '不切前台'],
    },
]


def font(path, size):
    return ImageFont.truetype(path, size)


def rounded_mask(size, radius):
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def background():
    img = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(img)
    # 右上角蓝紫光晕
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((1180, -420, 2320, 560), fill=(132, 128, 255, 90))
    gd.ellipse((900, 620, 2100, 1500), fill=(96, 176, 255, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    img = Image.alpha_composite(img.convert('RGBA'), glow).convert('RGB')
    return img


def window_mockup(shot, crop, width, covers=None):
    """把截图裁成圆角窗口，带顶部标题栏和阴影。"""
    content = shot.crop(crop)
    for (x1, y1, x2, y2) in (covers or []):
        ImageDraw.Draw(content).rectangle((x1, y1, x2, y2), fill=(243, 244, 246))
    bar_h = 46
    ratio = width / content.width
    inner_h = int(content.height * ratio)
    content = content.resize((width, inner_h), Image.LANCZOS)

    frame_w, frame_h = width, inner_h + bar_h
    frame = Image.new('RGBA', (frame_w, frame_h), (255, 255, 255, 255))
    frame.paste(content, (0, bar_h))

    d = ImageDraw.Draw(frame)
    d.rectangle((0, 0, frame_w, bar_h), fill=(246, 247, 251))
    d.line((0, bar_h, frame_w, bar_h), fill=(226, 230, 240), width=2)
    # 窗口按钮
    for i, color in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        cx = 26 + i * 26
        d.ellipse((cx - 8, bar_h // 2 - 8, cx + 8, bar_h // 2 + 8), fill=color)
    title_font = font(FONT_BOLD, 20)
    d.text((110, bar_h // 2 - 12), 'LockWarden', font=title_font, fill=(60, 66, 82))

    mask = rounded_mask((frame_w, frame_h), 22)
    frame.putalpha(mask)
    return frame


def panel_card(shot, crop, width):
    """把截图区域做成圆角卡片（不带窗口标题栏），用于通知中心这类局部截图。"""
    content = shot.crop(crop)
    ratio = width / content.width
    content = content.resize((width, int(content.height * ratio)), Image.LANCZOS)
    mask = rounded_mask(content.size, 20)
    content = content.convert('RGBA')
    content.putalpha(mask)
    return content


def draw_pill(d, xy, text, fnt, fill=(255, 255, 255), ink=ACCENT, border=(214, 224, 250)):
    x, y = xy
    tw = d.textlength(text, font=fnt)
    pad_x, h = 22, 44
    d.rounded_rectangle((x, y, x + tw + pad_x * 2, y + h), radius=22, fill=fill, outline=border, width=2)
    d.text((x + pad_x, y + (h - fnt.size) / 2 - 3), text, font=fnt, fill=ink)
    return x + tw + pad_x * 2


def make(slide):
    img = background()
    d = ImageDraw.Draw(img)

    # 左上角小标
    d.rounded_rectangle((96, 84, 96 + 300, 84 + 46), radius=23, fill=(255, 255, 255))
    d.text((118, 96), 'HarmonyOS 电脑版', font=font(FONT_BOLD, 22), fill=ACCENT)

    # 标题
    title_font = font(FONT_BOLD, 66)
    y = 176
    for line in slide['title']:
        d.text((96, y), line, font=title_font, fill=INK)
        y += 88

    # 副标题（自动换行）
    sub_font = font(FONT_REGULAR, 26)
    y += 10
    line = ''
    for ch in slide['subtitle']:
        test = line + ch
        if d.textlength(test, font=sub_font) > 620:
            d.text((96, y), line, font=sub_font, fill=SUB)
            y += 42
            line = ch
        else:
            line = test
    if line:
        d.text((96, y), line, font=sub_font, fill=SUB)
        y += 42

    # 胶囊
    pill_font = font(FONT_BOLD, 22)
    px, py = 96, y + 26
    for text in slide['pills']:
        px = draw_pill(d, (px, py), text, pill_font) + 14

    # 右侧样机
    shot = Image.open(os.path.join(DOCS, slide['file'])).convert('RGB')
    if slide.get('style') == 'panel':
        frame = panel_card(shot, slide['crop'], 600)
    else:
        frame = window_mockup(shot, slide['crop'], 1080, slide.get('covers'))
    fx, fy = W - frame.width - 88, (H - frame.height) // 2 - 10

    # 阴影
    shadow = Image.new('RGBA', (frame.width + 120, frame.height + 120), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((60, 70, 60 + frame.width, 70 + frame.height), radius=26, fill=(46, 62, 110, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))
    img.paste(shadow, (fx - 60, fy - 60), shadow)
    img.paste(frame, (fx, fy), frame)

    # 底部品牌
    d.text((96, H - 92), 'LockWarden', font=font(FONT_BOLD, 30), fill=INK)
    d.text((96 + 210, H - 88), '加密密码库 · 兼容 Bitwarden / Vaultwarden', font=font(FONT_REGULAR, 20), fill=SUB)

    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    for slide in SLIDES:
        img = make(slide)
        png = os.path.join(OUT, slide['slug'] + '.png')
        jpg = os.path.join(OUT, slide['slug'] + '.jpg')
        img.save(png, 'PNG', optimize=True)
        img.save(jpg, 'JPEG', quality=92, optimize=True)
        print('%-12s %s  %d KB' % (slide['slug'], img.size, os.path.getsize(png) // 1024))


if __name__ == '__main__':
    main()
