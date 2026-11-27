"""
生成应用商店宣传图。

竖屏：1080x1920（9:16），手机样机，5 张
横屏：1920x1280（3:2），平板样机，5 张

统一风格：浅色底 + 蓝紫渐变卡片 + 大标题 + 半透明胶囊标签 + 圆角设备样机。
所有截图使用应用内「演示数据」或本机测试数据，不含真实账号信息；
截图里的「演示数据」角标会被同色覆盖掉。

用法：python tools/make_promo.py
输出：docs/store-promo/portrait/*.png、docs/store-promo/landscape/*.png
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

DOCS = r'D:\workspace\docs'
OUT_PORTRAIT = os.path.join(DOCS, 'store-promo', 'portrait')
OUT_LANDSCAPE = os.path.join(DOCS, 'store-promo', 'landscape')

FONT_BOLD = r'C:\Windows\Fonts\msyhbd.ttc'
FONT_REGULAR = r'C:\Windows\Fonts\msyh.ttc'


# 截图顶部状态栏（时间/电量）需要裁掉，避免营销图里出现系统信息
CROP_TOP = {
    'store/01-vault.jpg': 86,
    'mk-editor.jpeg': 112,
    'generator-phone.jpeg': 112,
    'sub-security-bold.jpeg': 112,
    'local-mode-setup.jpeg': 112,
    'store-tablet/01-vault.png': 64,
    'store-tablet/02-editor.png': 64,
    'store-tablet/04-settings.png': 64,
    'store-tablet/05-folders.png': 64,
    'tablet-generator-2col.jpeg': 84,
}

BG = (236, 239, 246)
CARD_FROM = (47, 107, 255)
CARD_TO = (123, 92, 255)

# 竖屏：手机（浅色界面，演示数据）
PORTRAIT_SLIDES = [
    {
        'title': ['跨平台同步密码', '和私人信息'],
        'subtitle': ['一台服务器，手机、平板随时打开'],
        'image': 'store/01-vault.jpg',
        'slug': 'vault',
        'mask': (290, 92, 486, 172),
        'pills': ['端到端加密', '跨设备同步'],
    },
    {
        'title': ['密码和验证码', '一处管理'],
        'subtitle': ['用户名、密码、TOTP 两步验证都在一起'],
        'image': 'mk-editor.jpeg',
        'slug': 'editor',
        'pills': ['两步验证', '自定义字段'],
    },
    {
        'title': ['内置密码生成器', '长一点更安全'],
        'subtitle': ['长度、数字、特殊字符随手调'],
        'image': 'generator-phone.jpeg',
        'slug': 'generator',
        'pills': ['最长 30 位', '数字符号可调'],
    },
    {
        'title': ['指纹解锁', '再加一道隐私锁'],
        'subtitle': ['防截屏、自动锁定，别人碰不到'],
        'image': 'sub-security-bold.jpeg',
        'slug': 'security',
        'pills': ['指纹解锁', '防截屏'],
    },
    {
        'title': ['没有服务器', '也能放心用'],
        'subtitle': ['本机保险库，数据只加密存在这台设备'],
        'image': 'local-mode-setup.jpeg',
        'slug': 'local-mode',
        'pills': ['无需服务器', '数据不出设备'],
    },
]

# 横屏：平板（深色界面，演示数据）
LANDSCAPE_SLIDES = [
    {
        'title': ['平板大屏', '用起来更顺手'],
        'subtitle': ['同一份数据，手机和平板都在用'],
        'image': 'store-tablet/01-vault.png',
        'slug': 'tablet-vault',
        'mask': (300, 86, 500, 148),
        'pills': ['端到端加密', '跨设备同步'],
        'points': ['大屏浏览，条目一目了然', '收藏、文件夹、回收站都在', '手机、平板同一份数据'],
    },
    {
        'title': ['密码和验证码', '一处管理'],
        'subtitle': ['用户名、密码、TOTP 两步验证都在一起'],
        'image': 'store-tablet/02-editor.png',
        'slug': 'tablet-editor',
        'pills': ['两步验证', '自定义字段'],
        'points': ['用户名、密码、网址、备注', '自定义字段（含隐藏字段）', 'TOTP 密钥与登录信息同条管理'],
    },
    {
        'title': ['生成器两栏排布', '大屏一屏放完'],
        'subtitle': ['长度、数字、特殊字符随手调'],
        'image': 'tablet-generator-2col.jpeg',
        'slug': 'tablet-generator',
        'pills': ['最长 30 位', '数字符号可调'],
        'points': ['左栏预览与字符集', '右栏滑杆与一键复制', '不用滚动，一屏就能设完'],
    },
    {
        'title': ['深色浅色', '随心切换'],
        'subtitle': ['外观跟随系统，也能手动指定'],
        'image': 'store-tablet/04-settings.png',
        'slug': 'tablet-settings',
        'mask': (300, 86, 500, 148),
        'pills': ['深浅色主题', '自动锁定'],
        'points': ['一键切换浅色 / 深色主题', '自动锁定时间可设', '防截屏、生物识别集中管理'],
    },
    {
        'title': ['左滑即可操作', '批量更省事'],
        'subtitle': ['收藏、删除、多选，一划就有'],
        'image': 'store-tablet/05-folders.png',
        'slug': 'tablet-folders',
        'mask': (300, 86, 500, 148),
        'pills': ['滑动操作', '批量管理'],
        'points': ['左滑显示收藏与删除', '长按进入多选批量处理', '文件夹内同样适用'],
    },
]


def gradient(size, c1, c2):
    base = Image.new('RGB', (256, 256))
    px = base.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510.0
            px[x, y] = (
                int(c1[0] + (c2[0] - c1[0]) * t),
                int(c1[1] + (c2[1] - c1[1]) * t),
                int(c1[2] + (c2[2] - c1[2]) * t),
            )
    return base.resize(size, Image.BILINEAR)


def rounded_mask(size, radius):
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def paste_round(base, img, box, radius):
    x0, y0, x1, y1 = box
    w, h = max(1, x1 - x0), max(1, y1 - y0)
    layer = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    layer.paste(img.resize((w, h), Image.LANCZOS), (0, 0))
    layer.putalpha(rounded_mask((w, h), radius))
    base.alpha_composite(layer, (x0, y0))


def load_shot(slide):
    img = Image.open(os.path.join(DOCS, slide['image'])).convert('RGB')
    if 'mask' in slide:
        # 用角标旁边的背景色平涂，覆盖「演示数据」标记
        x0, y0, x1, y1 = slide['mask']
        fill = img.getpixel((min(img.width - 5, x1 + 220), y0 + 14))
        ImageDraw.Draw(img).rectangle([x0, y0, x1, y1], fill=fill)
    top = CROP_TOP.get(slide['image'], 0)
    if top > 0:
        img = img.crop((0, top, img.width, img.height))
    return img


def device_frame(canvas, shot, frame_box, corner=54, pad=12):
    x0, y0, x1, y1 = frame_box
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x0 + 10, y0 + 26, x1 + 10, y1 + 26], radius=corner, fill=(24, 32, 64, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
    ImageDraw.Draw(canvas).rounded_rectangle(frame_box, radius=corner, fill=(255, 255, 255, 255))
    paste_round(canvas, shot, (x0 + pad, y0 + pad, x1 - pad, y1 - pad), corner - pad)


def draw_soft_circles(canvas, layout):
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for cx, cy, r, alpha in layout:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, alpha))
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(40)))


def draw_dots(canvas, x, y, step=26, cols=4, rows=3, radius=3, alpha=70):
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for r in range(rows):
        for c in range(cols):
            px, py = x + c * step, y + r * step
            d.ellipse([px - radius, py - radius, px + radius, py + radius], fill=(255, 255, 255, alpha))
    canvas.alpha_composite(layer)


def draw_pills(canvas, pills, font, x, y, gap=16, pad_x=22, height=48):
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = x
    for text in pills:
        width = int(d.textlength(text, font=font))
        box = [cx, y, cx + width + pad_x * 2, y + height]
        d.rounded_rectangle(box, radius=height // 2, fill=(255, 255, 255, 46))
        d.text((cx + pad_x, y + 10), text, font=font, fill=(255, 255, 255, 235))
        cx = box[2] + gap
    canvas.alpha_composite(layer)
    return y + height


def draw_points(canvas, points, font, x, y):
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i, line in enumerate(points):
        oy = y + i * 52
        d.ellipse([x, oy + 12, x + 12, oy + 24], fill=(255, 255, 255, 220))
        d.text((x + 32, oy), line, font=font, fill=(255, 255, 255, 225))
    canvas.alpha_composite(layer)


def fit_text_lines(draw, lines, font, fill, x, y, line_h):
    for i, line in enumerate(lines):
        draw.text((x, y + i * line_h), line, font=font, fill=fill)
    return y + len(lines) * line_h


def portrait(slide, index):
    W, H = 1080, 1920
    canvas = Image.new('RGBA', (W, H), BG + (255,))
    grad = gradient((1000, 1776), CARD_FROM, CARD_TO)
    card = Image.new('RGBA', grad.size, (0, 0, 0, 0))
    card.paste(grad, (0, 0))
    card.putalpha(rounded_mask(grad.size, 64))
    canvas.alpha_composite(card, (40, 72))

    draw_soft_circles(canvas, [(880, 300, 220, 46), (220, 1620, 260, 36)])
    draw_dots(canvas, 128, 1712, cols=5, rows=2)

    d = ImageDraw.Draw(canvas)
    f_title = ImageFont.truetype(FONT_BOLD, 78)
    f_sub = ImageFont.truetype(FONT_REGULAR, 34)
    f_pill = ImageFont.truetype(FONT_REGULAR, 26)
    f_brand = ImageFont.truetype(FONT_BOLD, 30)

    d.rounded_rectangle([128, 168, 224, 178], radius=5, fill=(255, 255, 255, 235))
    y = fit_text_lines(d, slide['title'], f_title, (255, 255, 255, 255), 128, 214, 100)
    y = fit_text_lines(d, slide['subtitle'], f_sub, (255, 255, 255, 226), 128, y + 26, 52)
    draw_pills(canvas, slide['pills'], f_pill, 128, y + 34)

    shot = load_shot(slide)
    frame_w = 540
    inner_w = frame_w - 24
    inner_h = int(shot.height * inner_w / shot.width)
    device_frame(canvas, shot, (W // 2 - frame_w // 2, 672,
                                W // 2 + frame_w // 2, 672 + inner_h + 24))

    brand_w = int(d.textlength('LockWarden', font=f_brand))
    d.text((1032 - brand_w - 58, 158), 'LockWarden', font=f_brand, fill=(255, 255, 255, 205))
    path = os.path.join(OUT_PORTRAIT, '%02d-%s.png' % (index, slide['slug']))
    canvas.convert('RGB').save(path, 'PNG')
    return path


def landscape(slide, index):
    W, H = 1920, 1280
    canvas = Image.new('RGBA', (W, H), BG + (255,))
    grad = gradient((1800, 1160), CARD_FROM, CARD_TO)
    card = Image.new('RGBA', grad.size, (0, 0, 0, 0))
    card.paste(grad, (0, 0))
    card.putalpha(rounded_mask(grad.size, 64))
    canvas.alpha_composite(card, (60, 60))

    draw_soft_circles(canvas, [(1500, 240, 240, 38), (300, 1080, 300, 32)])

    d = ImageDraw.Draw(canvas)
    f_title = ImageFont.truetype(FONT_BOLD, 78)
    f_sub = ImageFont.truetype(FONT_REGULAR, 34)
    f_pill = ImageFont.truetype(FONT_REGULAR, 27)
    f_point = ImageFont.truetype(FONT_REGULAR, 29)
    f_brand = ImageFont.truetype(FONT_BOLD, 30)

    d.rounded_rectangle([140, 196, 236, 206], radius=5, fill=(255, 255, 255, 235))
    y = fit_text_lines(d, slide['title'], f_title, (255, 255, 255, 255), 140, 240, 100)
    y = fit_text_lines(d, slide['subtitle'], f_sub, (255, 255, 255, 226), 140, y + 26, 50)
    py = draw_pills(canvas, slide['pills'], f_pill, 140, y + 34)
    draw_points(canvas, slide['points'], f_point, 140, py + 40)

    shot = load_shot(slide)
    # 平板样机：更粗的边框 + 更小的圆角
    frame_w = 940
    pad = 16
    inner_w = frame_w - pad * 2
    inner_h = int(shot.height * inner_w / shot.width)
    frame_h = inner_h + pad * 2
    device_frame(canvas, shot, (1820 - frame_w, 640 - frame_h // 2,
                                1820, 640 + frame_h // 2 + frame_h % 2), corner=34, pad=pad)

    d.text((198, 1108), 'LockWarden', font=f_brand, fill=(255, 255, 255, 205))
    path = os.path.join(OUT_LANDSCAPE, '%02d-%s.png' % (index, slide['slug']))
    canvas.convert('RGB').save(path, 'PNG')
    return path


def main():
    os.makedirs(OUT_PORTRAIT, exist_ok=True)
    os.makedirs(OUT_LANDSCAPE, exist_ok=True)
    for folder in (OUT_PORTRAIT, OUT_LANDSCAPE):
        for f in os.listdir(folder):
            if f.endswith('.png'):
                os.remove(os.path.join(folder, f))
    for i, slide in enumerate(PORTRAIT_SLIDES, start=1):
        p = portrait(slide, i)
        print('portrait  %-34s %s' % (os.path.basename(p), Image.open(p).size))
    for i, slide in enumerate(LANDSCAPE_SLIDES, start=1):
        p = landscape(slide, i)
        print('landscape %-34s %s' % (os.path.basename(p), Image.open(p).size))


if __name__ == '__main__':
    main()
