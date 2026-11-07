#!/usr/bin/env python3
"""ノコリカ App Store スクリーンショット（凝った枠）を書き出す。"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance

ROOT = Path(__file__).resolve().parent
ICON = ROOT.parent / "assets" / "icon" / "ios_icon.png"

W3 = "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"
W6 = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"
W8 = "/System/Library/Fonts/ヒラギノ角ゴシック W8.ttc"

STATUS_CROP = 168  # Dynamic Island 付近まで切る

# ブランド
INK = (14, 11, 12)
INK2 = (24, 16, 15)
CORAL = (252, 118, 92)
CORAL_DEEP = (232, 78, 58)
PEACH = (255, 214, 198)
MIST = (245, 236, 230)
MUTE = (176, 152, 142)
WHITE = (255, 255, 255)


def fnt(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def s(n: float, scale: float) -> int:
    return int(round(n * scale))


def lerp(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(len(a)))


def soft_noise(w: int, h: int, amount: int = 18) -> Image.Image:
    import random

    rnd = random.Random(7)
    sw, sh = max(1, w // 4), max(1, h // 4)
    layer = Image.new("L", (sw, sh))
    px = layer.load()
    for y in range(sh):
        for x in range(sw):
            px[x, y] = rnd.randint(0, amount)
    return layer.resize((w, h), Image.Resampling.BILINEAR).filter(
        ImageFilter.GaussianBlur(0.8)
    )


def base_canvas(w: int, h: int, mood: str = "dark") -> Image.Image:
    """ムード別の背景。"""
    img = Image.new("RGB", (w, h), INK if mood != "light" else (255, 244, 238))
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    if mood == "dark":
        # 上：コーラル、下：インク
        for i in range(8):
            r = s(420 + i * 80, w / 1179)
            cx, cy = int(w * 0.72), int(h * 0.08)
            alpha = 55 - i * 5
            draw.ellipse(
                (cx - r, cy - r, cx + r, cy + r),
                fill=(*CORAL, max(8, alpha)),
            )
        for i in range(6):
            r = s(280 + i * 70, w / 1179)
            cx, cy = int(w * 0.12), int(h * 0.92)
            draw.ellipse(
                (cx - r, cy - r, cx + r, cy + r),
                fill=(*CORAL_DEEP, max(6, 28 - i * 4)),
            )
        # 斜めハイライト帯
        band = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        bd = ImageDraw.Draw(band)
        pts = [
            (int(w * 0.55), -s(40, w / 1179)),
            (w + s(40, w / 1179), int(h * 0.18)),
            (w + s(40, w / 1179), int(h * 0.32)),
            (int(w * 0.35), -s(40, w / 1179)),
        ]
        bd.polygon(pts, fill=(255, 255, 255, 14))
        band = band.filter(ImageFilter.GaussianBlur(s(18, w / 1179)))
        overlay = Image.alpha_composite(overlay, band)
    elif mood == "coral":
        strip = Image.new("RGB", (1, h))
        px = strip.load()
        for y in range(h):
            t = y / (h - 1)
            px[0, y] = lerp((255, 140, 110), (40, 18, 22), t**0.85)
        img = strip.resize((w, h), Image.Resampling.BILINEAR)
        for i in range(5):
            r = s(300 + i * 90, w / 1179)
            draw.ellipse(
                (int(w * 0.1) - r, int(h * 0.2) - r, int(w * 0.1) + r, int(h * 0.2) + r),
                fill=(255, 255, 255, max(6, 30 - i * 5)),
            )
    else:  # light
        for i in range(7):
            r = s(380 + i * 70, w / 1179)
            draw.ellipse(
                (
                    int(w * 0.8) - r,
                    int(h * 0.0) - r,
                    int(w * 0.8) + r,
                    int(h * 0.0) + r,
                ),
                fill=(*CORAL, max(10, 40 - i * 5)),
            )
        for i in range(5):
            r = s(260 + i * 60, w / 1179)
            draw.ellipse(
                (
                    int(w * 0.05) - r,
                    int(h * 0.75) - r,
                    int(w * 0.05) + r,
                    int(h * 0.75) + r,
                ),
                fill=(255, 180, 140, max(8, 28 - i * 4)),
            )

    img = Image.alpha_composite(img.convert("RGBA"), overlay)
    noise = soft_noise(w, h, 22 if mood != "light" else 14)
    noise_rgba = Image.merge(
        "RGBA",
        (
            Image.new("L", (w, h), 255),
            Image.new("L", (w, h), 255),
            Image.new("L", (w, h), 255),
            noise.point(lambda v: int(v * 0.55)),
        ),
    )
    img = Image.alpha_composite(img, noise_rgba)
    return img


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, im.size[0] - 1, im.size[1] - 1), radius=radius, fill=255
    )
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def phone_frame(shot: Image.Image, scale: float) -> Image.Image:
    """細いベゼル＋Dynamic Island風の端末枠。"""
    pad = s(14, scale)
    radius = s(78, scale)
    island_w, island_h = s(180, scale), s(48, scale)
    bezel = Image.new(
        "RGBA",
        (shot.width + pad * 2, shot.height + pad * 2),
        (0, 0, 0, 0),
    )
    d = ImageDraw.Draw(bezel)
    # 外側メタル感
    d.rounded_rectangle(
        (0, 0, bezel.width - 1, bezel.height - 1),
        radius=radius,
        fill=(28, 24, 24, 255),
    )
    d.rounded_rectangle(
        (1, 1, bezel.width - 2, bezel.height - 2),
        radius=radius - 1,
        outline=(90, 70, 62, 180),
        width=max(1, s(2, scale)),
    )
    inner = rounded(shot, radius - pad)
    bezel.paste(inner, (pad, pad), inner)
    # Dynamic Island
    ix = (bezel.width - island_w) // 2
    iy = pad + s(18, scale)
    d = ImageDraw.Draw(bezel)
    d.rounded_rectangle(
        (ix, iy, ix + island_w, iy + island_h),
        radius=island_h // 2,
        fill=(8, 8, 10, 255),
    )
    return bezel


def drop_shadow(size, box, scale, radius_extra=0):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(layer).rounded_rectangle(
        (x0, y0 + s(24, scale), x1, y1 + s(12, scale)),
        radius=s(78, scale) + radius_extra,
        fill=(0, 0, 0, 150),
    )
    return layer.filter(ImageFilter.GaussianBlur(s(36, scale)))


def brand_pill(draw, xy, text, scale, fill=CORAL):
    font = fnt(W6, s(28, scale))
    x, y = xy
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pad_x, pad_y = s(22, scale), s(12, scale)
    w, h = tw + pad_x * 2, th + pad_y * 2
    draw.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=fill)
    draw.text((x + pad_x, y + pad_y - s(2, scale)), text, font=font, fill=WHITE)


def draw_title_block(
    draw,
    center_x,
    y,
    eyebrow,
    lines,
    sub,
    scale,
    ink=WHITE,
    mute=MUTE,
    accent=CORAL,
    align="center",
):
    eyebrow_font = fnt(W6, s(30, scale))
    title_font = fnt(W8, s(78, scale))
    sub_font = fnt(W3, s(32, scale))
    anchor = "mt" if align == "center" else "lt"
    draw.text((center_x, y), eyebrow, font=eyebrow_font, fill=accent, anchor=anchor)
    y += s(58, scale)
    for line in lines:
        draw.text((center_x, y), line, font=title_font, fill=ink, anchor=anchor)
        y += s(92, scale)
    y += s(4, scale)
    draw.text((center_x, y), sub, font=sub_font, fill=mute, anchor=anchor)
    return y + s(48, scale)


def load_shot(name: str, crop_top=None, crop_bottom=0) -> Image.Image:
    im = Image.open(ROOT / name).convert("RGBA")
    if crop_top is None:
        # 1179基準のセーフエリアを解像度に合わせて切る
        crop_top = int(round(STATUS_CROP * (im.width / 1179)))
    bottom = im.height - crop_bottom if crop_bottom else im.height
    return im.crop((0, crop_top, im.width, bottom))


def paste_phone(canvas, phone, x, y, scale):
    shadow = drop_shadow(
        canvas.size, (x, y, x + phone.width, y + phone.height), scale
    )
    canvas.alpha_composite(shadow)
    canvas.paste(phone, (x, y), phone)
    return canvas


def compose_standard(spec, w, h):
    scale = w / 1179
    mood = spec.get("mood", "dark")
    canvas = base_canvas(w, h, mood)
    draw = ImageDraw.Draw(canvas)

    ink = WHITE if mood != "light" else INK
    mute = MUTE if mood != "light" else (120, 96, 88)

    # 左上に小さなブランド
    icon = Image.open(ICON).convert("RGBA").resize((s(54, scale), s(54, scale)), Image.Resampling.LANCZOS)
    icon = rounded(icon, s(12, scale))
    canvas.paste(icon, (s(48, scale), s(56, scale)), icon)
    draw.text(
        (s(118, scale), s(68, scale)),
        "ノコリカ",
        font=fnt(W6, s(30, scale)),
        fill=ink,
    )

    y = s(150, scale)
    draw_title_block(
        draw,
        w // 2,
        y,
        spec["eyebrow"],
        spec["lines"],
        spec["sub"],
        scale,
        ink=ink,
        mute=mute,
        accent=CORAL if mood != "coral" else WHITE,
    )

    # 透かし数字
    if "watermark" in spec:
        wm = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        wd = ImageDraw.Draw(wm)
        wd.text(
            (w // 2, s(430, scale)),
            spec["watermark"],
            font=fnt(W8, s(420, scale)),
            fill=(*CORAL, 28) if mood != "light" else (*CORAL_DEEP, 35),
            anchor="mt",
        )
        canvas = Image.alpha_composite(canvas, wm)

    shot = load_shot(spec["src"], crop_bottom=spec.get("crop_bottom", 0))
    if spec.get("boost"):
        shot = ImageEnhance.Contrast(shot).enhance(1.05)
        shot = ImageEnhance.Color(shot).enhance(1.08)

    side = s(70, scale)
    top = s(500, scale)
    bottom = s(48, scale)
    avail_w = w - side * 2
    avail_h = h - top - bottom
    fit = min(avail_w / shot.width, avail_h / shot.height) * spec.get("phone_scale", 1.0)
    shot = shot.resize(
        (int(shot.width * fit), int(shot.height * fit)), Image.Resampling.LANCZOS
    )
    phone = phone_frame(shot, scale)
    x = (w - phone.width) // 2
    y = top + (avail_h - phone.height) // 2
    # 少し下に食い込ませて臨場感
    y = min(y, h - phone.height + s(40, scale))
    canvas = paste_phone(canvas, phone, x, max(top - s(20, scale), y), scale)

    # フローティングチップ
    for chip in spec.get("chips", []):
        cx = s(chip["x"], scale)
        cy = s(chip["y"], scale)
        chip_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        cd = ImageDraw.Draw(chip_layer)
        font = fnt(W6, s(26, scale))
        text = chip["text"]
        bbox = cd.textbbox((0, 0), text, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        pad_x, pad_y = s(20, scale), s(14, scale)
        rw, rh = tw + pad_x * 2, th + pad_y * 2
        cd.rounded_rectangle(
            (cx, cy, cx + rw, cy + rh),
            radius=rh // 2,
            fill=(255, 255, 255, 235) if mood == "dark" else (30, 20, 18, 230),
        )
        cd.text(
            (cx + pad_x, cy + pad_y - s(2, scale)),
            text,
            font=font,
            fill=INK if mood == "dark" else WHITE,
        )
        chip_layer = chip_layer.filter(ImageFilter.GaussianBlur(0.2))
        # soft shadow under chip
        sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle(
            (cx, cy + s(6, scale), cx + rw, cy + rh + s(6, scale)),
            radius=rh // 2,
            fill=(0, 0, 0, 60),
        )
        sh = sh.filter(ImageFilter.GaussianBlur(s(10, scale)))
        canvas = Image.alpha_composite(canvas, sh)
        canvas = Image.alpha_composite(canvas, chip_layer)

    return canvas.convert("RGB")


def compose_hero(w, h):
    scale = w / 1179
    canvas = base_canvas(w, h, "coral")

    icon = Image.open(ICON).convert("RGBA")
    icon_size = s(220, scale)
    icon = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    icon = rounded(icon, s(50, scale))
    icon_y = s(160, scale)
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        (
            (w - icon_size) // 2,
            icon_y + s(18, scale),
            (w - icon_size) // 2 + icon_size,
            icon_y + icon_size + s(18, scale),
        ),
        radius=s(50, scale),
        fill=(0, 0, 0, 100),
    )
    sh = sh.filter(ImageFilter.GaussianBlur(s(26, scale)))
    canvas = Image.alpha_composite(canvas, sh)
    canvas.paste(icon, ((w - icon_size) // 2, icon_y), icon)

    # テキスト＆ピルは別レイヤー（RGBAで確実に描く）
    text_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(text_layer)
    draw.text(
        (w // 2, s(420, scale)),
        "ノコリカ",
        font=fnt(W8, s(96, scale)),
        fill=WHITE,
        anchor="mt",
    )
    draw.text(
        (w // 2, s(540, scale)),
        "営業日の残りを、数える。",
        font=fnt(W6, s(42, scale)),
        fill=PEACH,
        anchor="mt",
    )
    # アクセント線
    line_w = s(72, scale)
    ly = s(620, scale)
    draw.rounded_rectangle(
        ((w - line_w) // 2, ly, (w + line_w) // 2, ly + s(6, scale)),
        radius=s(3, scale),
        fill=(*WHITE, 180),
    )

    features = ["残り営業日", "期限カード", "ウィジェット"]
    font = fnt(W6, s(26, scale))
    gaps = s(14, scale)
    widths = []
    for t in features:
        bb = draw.textbbox((0, 0), t, font=font)
        widths.append(bb[2] - bb[0] + s(36, scale))
    total = sum(widths) + gaps * (len(features) - 1)
    x = (w - total) // 2
    y = s(660, scale)
    for t, ww in zip(features, widths):
        rh = s(56, scale)
        draw.rounded_rectangle(
            (x, y, x + ww, y + rh),
            radius=rh // 2,
            fill=(255, 255, 255, 48),
            outline=(255, 255, 255, 140),
            width=max(1, s(2, scale)),
        )
        draw.text((x + ww // 2, y + rh // 2), t, font=font, fill=WHITE, anchor="mm")
        x += ww + gaps
    canvas = Image.alpha_composite(canvas, text_layer)

    # 端末はもっと上まで見せる
    shot = load_shot("IMG_0655.PNG")
    fit = (w * 0.86) / shot.width
    shot = shot.resize((int(shot.width * fit), int(shot.height * fit)), Image.Resampling.LANCZOS)
    phone = phone_frame(shot, scale)
    peek_y = s(760, scale)
    canvas = paste_phone(canvas, phone, (w - phone.width) // 2, peek_y, scale)

    fade = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fade)
    fade_h = s(280, scale)
    for i in range(fade_h):
        a = int(210 * (i / max(1, fade_h)))
        fd.line([(0, h - fade_h + i), (w, h - fade_h + i)], fill=(36, 16, 18, a))
    canvas = Image.alpha_composite(canvas, fade)

    foot = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(foot).text(
        (w // 2, h - s(88, scale)),
        "祝日も休日も、のぞいて数えるカレンダー",
        font=fnt(W3, s(30, scale)),
        fill=(255, 232, 222, 255),
        anchor="mm",
    )
    canvas = Image.alpha_composite(canvas, foot)
    return canvas.convert("RGB")


def compose_widget(w, h):
    """実機ホームの代わりに、ウィジェット実体に近いカードを描く。差し替え推奨。"""
    scale = w / 1179
    canvas = base_canvas(w, h, "dark")
    draw = ImageDraw.Draw(canvas)

    icon = Image.open(ICON).convert("RGBA").resize((s(54, scale), s(54, scale)), Image.Resampling.LANCZOS)
    icon = rounded(icon, s(12, scale))
    canvas.paste(icon, (s(48, scale), s(56, scale)), icon)
    draw.text((s(118, scale), s(68, scale)), "ノコリカ", font=fnt(W6, s(30, scale)), fill=WHITE)

    draw_title_block(
        draw,
        w // 2,
        s(150, scale),
        "ホーム画面",
        ["開かなくても", "残りがわかる"],
        "ウィジェットで、今日時点の残り営業日",
        scale,
    )

    panel_w, panel_h = s(1000, scale), s(1480, scale)
    panel = Image.new("RGBA", (panel_w, panel_h), (0, 0, 0, 0))
    wall = Image.new("RGB", (panel_w, panel_h))
    px = wall.load()
    for y in range(panel_h):
        t = y / max(1, panel_h - 1)
        col = lerp((48, 28, 36), (18, 24, 48), t)
        for x in range(panel_w):
            px[x, y] = col
    panel.paste(wall, (0, 0))
    pd = ImageDraw.Draw(panel)
    pd.text((s(40, scale), s(36, scale)), "10:08", font=fnt(W6, s(28, scale)), fill=(255, 255, 255, 200))

    app_colors = [(70, 130, 220), (90, 180, 120), (220, 120, 90), (170, 110, 200)]
    tile = s(96, scale)
    gap = s(36, scale)
    row_w = tile * 4 + gap * 3
    sx = (panel_w - row_w) // 2
    sy = panel_h - s(220, scale)
    pd.rounded_rectangle(
        (s(48, scale), sy - s(28, scale), panel_w - s(48, scale), sy + tile + s(36, scale)),
        radius=s(36, scale),
        fill=(255, 255, 255, 28),
    )
    for i, c in enumerate(app_colors):
        x = sx + i * (tile + gap)
        pd.rounded_rectangle((x, sy, x + tile, sy + tile), radius=s(22, scale), fill=(*c, 210))

    card_w, card_h = s(900, scale), s(340, scale)
    cx = (panel_w - card_w) // 2
    cy = s(160, scale)
    card = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    for yy in range(card_h):
        t = yy / max(1, card_h - 1)
        col = lerp((30, 120, 225), (12, 68, 155), t)
        cd.line([(0, yy), (card_w, yy)], fill=(*col, 255))
    card = rounded(card, s(40, scale))
    glow = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        (card_w - s(240, scale), -s(90, scale), card_w + s(60, scale), s(190, scale)),
        fill=(255, 255, 255, 45),
    )
    card = Image.alpha_composite(card, glow.filter(ImageFilter.GaussianBlur(s(18, scale))))
    cd = ImageDraw.Draw(card)
    cd.text((s(36, scale), s(30, scale)), "残り営業日", font=fnt(W6, s(26, scale)), fill=(220, 235, 255))
    mini = Image.open(ICON).convert("RGBA").resize((s(44, scale), s(44, scale)), Image.Resampling.LANCZOS)
    mini = rounded(mini, s(10, scale))
    card.paste(mini, (card_w - s(80, scale), s(24, scale)), mini)
    cd = ImageDraw.Draw(card)
    cd.text((s(36, scale), s(78, scale)), "18", font=fnt(W8, s(112, scale)), fill=WHITE)
    bar_y = s(220, scale)
    bar_x0, bar_x1 = s(36, scale), card_w - s(200, scale)
    cd.rounded_rectangle((bar_x0, bar_y, bar_x1, bar_y + s(10, scale)), radius=s(5, scale), fill=(255, 255, 255, 40))
    cd.rounded_rectangle(
        (bar_x0, bar_y, bar_x0 + int((bar_x1 - bar_x0) * 0.55), bar_y + s(10, scale)),
        radius=s(5, scale),
        fill=(235, 248, 255, 245),
    )
    cd.text((s(36, scale), s(260, scale)), "2026年11月", font=fnt(W3, s(24, scale)), fill=(190, 215, 245))
    cd.text((bar_x1, s(260, scale)), "最終 11/30", font=fnt(W3, s(24, scale)), fill=(190, 215, 245), anchor="rt")
    ring_box = (card_w - s(170, scale), s(90, scale), card_w - s(60, scale), s(200, scale))
    cd.ellipse(ring_box, outline=(255, 255, 255, 45), width=s(9, scale))
    cd.arc(ring_box, start=-90, end=110, fill=(230, 245, 255, 245), width=s(9, scale))
    cd.text(
        ((ring_box[0] + ring_box[2]) // 2, (ring_box[1] + ring_box[3]) // 2),
        "55%",
        font=fnt(W6, s(26, scale)),
        fill=WHITE,
        anchor="mm",
    )
    panel.paste(card, (cx, cy), card)

    small_w, small_h = s(430, scale), s(430, scale)
    small = Image.new("RGBA", (small_w, small_h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(small)
    for yy in range(small_h):
        t = yy / max(1, small_h - 1)
        col = lerp((34, 128, 230), (14, 72, 160), t)
        sd.line([(0, yy), (small_w, yy)], fill=(*col, 255))
    small = rounded(small, s(40, scale))
    sd = ImageDraw.Draw(small)
    sd.text((s(28, scale), s(28, scale)), "残り営業日", font=fnt(W6, s(24, scale)), fill=(220, 235, 255))
    sd.text((s(28, scale), s(90, scale)), "18", font=fnt(W8, s(120, scale)), fill=WHITE)
    sd.text((s(28, scale), s(250, scale)), "最終 11/30", font=fnt(W3, s(24, scale)), fill=(190, 215, 245))
    sd.text((s(28, scale), s(300, scale)), "2026年11月", font=fnt(W3, s(22, scale)), fill=(170, 200, 235))
    panel.paste(small, (s(70, scale), s(560, scale)), small)

    peek = load_shot("IMG_0655.PNG").crop((0, 0, 1179, 900))
    peek_w = s(430, scale)
    peek = peek.resize((peek_w, int(900 * (peek_w / 1179))), Image.Resampling.LANCZOS)
    peek = rounded(peek, s(36, scale))
    panel.paste(peek, (s(520, scale), s(560, scale)), peek)

    panel = rounded(panel, s(56, scale))
    px0 = (w - panel_w) // 2
    py0 = s(500, scale)
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        (px0, py0 + s(18, scale), px0 + panel_w, py0 + panel_h + s(10, scale)),
        radius=s(56, scale),
        fill=(0, 0, 0, 140),
    )
    canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(s(30, scale))))
    canvas.paste(panel, (px0, py0), panel)

    foot = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(foot).text(
        (w // 2, h - s(72, scale)),
        "ホームを長押し → ウィジェットから追加",
        font=fnt(W3, s(28, scale)),
        fill=MUTE,
        anchor="mm",
    )
    canvas = Image.alpha_composite(canvas, foot)
    return canvas.convert("RGB")


def compose_search(w, h):
    scale = w / 1179
    canvas = base_canvas(w, h, "dark")
    draw = ImageDraw.Draw(canvas)
    icon = Image.open(ICON).convert("RGBA").resize((s(54, scale), s(54, scale)), Image.Resampling.LANCZOS)
    icon = rounded(icon, s(12, scale))
    canvas.paste(icon, (s(48, scale), s(56, scale)), icon)
    draw.text((s(118, scale), s(68, scale)), "ノコリカ", font=fnt(W6, s(30, scale)), fill=WHITE)

    draw_title_block(
        draw,
        w // 2,
        s(150, scale),
        "検索",
        ["会議もメモも", "すぐ見つかる"],
        "キーワードで、過去と未来の予定を横断",
        scale,
    )

    # 背景にカレンダー、手前に検索結果カード
    bg = load_shot("IMG_0655.PNG")
    side = s(70, scale)
    top = s(500, scale)
    avail_w = w - side * 2
    avail_h = h - top - s(40, scale)
    fit = min(avail_w / bg.width, avail_h / bg.height) * 0.98
    bg = bg.resize((int(bg.width * fit), int(bg.height * fit)), Image.Resampling.LANCZOS)
    phone = phone_frame(bg, scale)
    # 暗幕
    dim = Image.new("RGBA", phone.size, (0, 0, 0, 120))
    phone = Image.alpha_composite(phone, dim)
    x = (w - phone.width) // 2
    canvas = paste_phone(canvas, phone, x, top - s(10, scale), scale)

    # 検索パネル（実スクショの上半分）
    search = load_shot("IMG_0652.PNG", crop_bottom=1500)
    sw = s(980, scale)
    sh_h = int(search.height * (sw / search.width))
    search = search.resize((sw, sh_h), Image.Resampling.LANCZOS)
    search = rounded(search, s(36, scale))
    sx = (w - sw) // 2
    sy = s(980, scale)
    shad = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shad).rounded_rectangle(
        (sx, sy + s(14, scale), sx + sw, sy + sh_h + s(10, scale)),
        radius=s(36, scale),
        fill=(0, 0, 0, 140),
    )
    canvas = Image.alpha_composite(canvas, shad.filter(ImageFilter.GaussianBlur(s(22, scale))))
    canvas.paste(search, (sx, sy), search)

    chip = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(chip)
    text = "「会議」でヒット"
    font = fnt(W6, s(28, scale))
    bb = cd.textbbox((0, 0), text, font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    cx, cy = s(90, scale), s(880, scale)
    rw, rh = tw + s(44, scale), th + s(28, scale)
    cd.rounded_rectangle((cx, cy, cx + rw, cy + rh), radius=rh // 2, fill=(255, 255, 255, 240))
    cd.text((cx + s(22, scale), cy + s(12, scale)), text, font=font, fill=INK)
    canvas = Image.alpha_composite(canvas, chip)
    return canvas.convert("RGB")


def compose_split(w, h):
    """営業日番号づけを強調する2画面寄り構図。"""
    scale = w / 1179
    canvas = base_canvas(w, h, "light")
    draw = ImageDraw.Draw(canvas)

    icon = Image.open(ICON).convert("RGBA").resize((s(54, scale), s(54, scale)), Image.Resampling.LANCZOS)
    icon = rounded(icon, s(12, scale))
    canvas.paste(icon, (s(48, scale), s(56, scale)), icon)
    draw.text((s(118, scale), s(68, scale)), "ノコリカ", font=fnt(W6, s(30, scale)), fill=INK)

    draw_title_block(
        draw,
        w // 2,
        s(140, scale),
        "営業日の番号",
        ["第3営業日、", "すぐにわかる"],
        "一覧で、その月の何営業日目かを表示",
        scale,
        ink=INK,
        mute=(120, 96, 88),
        accent=CORAL_DEEP,
    )

    shot = load_shot("IMG_0655.PNG")
    # リスト付近を主役に下寄りクロップ（上のカウントは残しつつ）
    # 端末全体は小さめに2枚重ね
    fit = (w * 0.78) / shot.width
    shot_r = shot.resize((int(shot.width * fit), int(shot.height * fit)), Image.Resampling.LANCZOS)
    phone = phone_frame(shot_r, scale)

    # 背面に淡い2枚目
    back = phone.copy()
    back = ImageEnhance.Brightness(back).enhance(0.85)
    back = back.rotate(6, resample=Image.Resampling.BICUBIC, expand=True)
    bx = w - back.width + s(40, scale)
    by = s(560, scale)
    # shadow
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse(
        (bx + s(40, scale), by + back.height - s(40, scale), bx + back.width - s(40, scale), by + back.height + s(40, scale)),
        fill=(80, 40, 30, 50),
    )
    sh = sh.filter(ImageFilter.GaussianBlur(s(30, scale)))
    canvas = Image.alpha_composite(canvas, sh)
    canvas.paste(back, (bx, by), back)

    fx = -s(20, scale)
    fy = s(620, scale)
    canvas = paste_phone(canvas, phone, fx, fy, scale)

    # 強調ラベル
    labels = [
        (s(520, scale), s(980, scale), "第3営業日"),
        (s(520, scale), s(1180, scale), "第4営業日"),
    ]
    for lx, ly, text in labels:
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        font = fnt(W6, s(30, scale))
        bb = ld.textbbox((0, 0), text, font=font)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        rw, rh = tw + s(40, scale), th + s(28, scale)
        ld.rounded_rectangle((lx, ly, lx + rw, ly + rh), radius=rh // 2, fill=(*CORAL_DEEP, 245))
        ld.text((lx + s(20, scale), ly + s(12, scale)), text, font=font, fill=WHITE)
        sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle(
            (lx, ly + s(8, scale), lx + rw, ly + rh + s(8, scale)),
            radius=rh // 2,
            fill=(0, 0, 0, 50),
        )
        sh = sh.filter(ImageFilter.GaussianBlur(s(10, scale)))
        canvas = Image.alpha_composite(canvas, sh)
        canvas = Image.alpha_composite(canvas, layer)

    return canvas.convert("RGB")



def wide_backdrop(w2: int, h: int) -> Image.Image:
    """左右つながる背景（幅は2枚分）。"""
    scale = (w2 // 2) / 1179
    img = Image.new("RGB", (w2, h), INK)
    overlay = Image.new("RGBA", (w2, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    # 中央付近を軸にコーラルグロー（継ぎ目でつながる）
    for i in range(10):
        r = s(500 + i * 90, scale)
        cx, cy = w2 // 2, int(h * 0.18)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(*CORAL, max(6, 48 - i * 4)))
    for i in range(7):
        r = s(360 + i * 80, scale)
        cx, cy = int(w2 * 0.18), int(h * 0.85)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(*CORAL_DEEP, max(5, 26 - i * 3)))
    for i in range(7):
        r = s(360 + i * 80, scale)
        cx, cy = int(w2 * 0.82), int(h * 0.75)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(90, 140, 220, max(5, 22 - i * 3)))
    # 水平の光帯（左右をつなぐ）
    band = Image.new("RGBA", (w2, h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    bd.rectangle((0, int(h * 0.22), w2, int(h * 0.38)), fill=(255, 255, 255, 12))
    band = band.filter(ImageFilter.GaussianBlur(s(40, scale)))
    overlay = Image.alpha_composite(overlay, band)
    img = Image.alpha_composite(img.convert("RGBA"), overlay)
    noise = soft_noise(w2, h, 20)
    noise_rgba = Image.merge(
        "RGBA",
        (
            Image.new("L", (w2, h), 255),
            Image.new("L", (w2, h), 255),
            Image.new("L", (w2, h), 255),
            noise.point(lambda v: int(v * 0.5)),
        ),
    )
    return Image.alpha_composite(img, noise_rgba)


def compose_diptych(w: int, h: int):
    """01-02 が横スワイプで1枚に見えるペア。"""
    scale = w / 1179
    w2 = w * 2
    canvas = wide_backdrop(w2, h)

    # 継ぎ目をまたぐ巨大数字
    wm = Image.new("RGBA", (w2, h), (0, 0, 0, 0))
    ImageDraw.Draw(wm).text(
        (w2 // 2, s(360, scale)),
        "15",
        font=fnt(W8, s(520, scale)),
        fill=(*CORAL, 38),
        anchor="mm",
    )
    canvas = Image.alpha_composite(canvas, wm)

    # 左コピー
    left = Image.new("RGBA", (w2, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(left)
    icon = Image.open(ICON).convert("RGBA").resize((s(54, scale), s(54, scale)), Image.Resampling.LANCZOS)
    icon = rounded(icon, s(12, scale))
    left.paste(icon, (s(48, scale), s(56, scale)), icon)
    ld.text((s(118, scale), s(68, scale)), "ノコリカ", font=fnt(W6, s(30, scale)), fill=WHITE)
    ld.text((w // 2, s(150, scale)), "ホーム画面", font=fnt(W6, s(30, scale)), fill=CORAL, anchor="mt")
    ld.text((w // 2, s(208, scale)), "開かなくても", font=fnt(W8, s(78, scale)), fill=WHITE, anchor="mt")
    ld.text((w // 2, s(300, scale)), "残りがわかる", font=fnt(W8, s(78, scale)), fill=WHITE, anchor="mt")
    ld.text(
        (w // 2, s(400, scale)),
        "ウィジェットで、今日の残り営業日",
        font=fnt(W3, s(32, scale)),
        fill=MUTE,
        anchor="mt",
    )
    canvas = Image.alpha_composite(canvas, left)

    # 右コピー
    right = Image.new("RGBA", (w2, h), (0, 0, 0, 0))
    rd = ImageDraw.Draw(right)
    right.paste(icon, (w + s(48, scale), s(56, scale)), icon)
    rd.text((w + s(118, scale), s(68, scale)), "ノコリカ", font=fnt(W6, s(30, scale)), fill=WHITE)
    rd.text((w + w // 2, s(150, scale)), "アプリを開けば", font=fnt(W6, s(30, scale)), fill=CORAL, anchor="mt")
    rd.text((w + w // 2, s(208, scale)), "最終営業日まで", font=fnt(W8, s(78, scale)), fill=WHITE, anchor="mt")
    rd.text((w + w // 2, s(300, scale)), "ひと目でわかる", font=fnt(W8, s(78, scale)), fill=WHITE, anchor="mt")
    rd.text(
        (w + w // 2, s(400, scale)),
        "祝日も休日も、のぞいて数える",
        font=fnt(W3, s(32, scale)),
        fill=MUTE,
        anchor="mt",
    )
    canvas = Image.alpha_composite(canvas, right)

    # 2台の端末を継ぎ目にまたがせて配置
    home = load_shot("IMG_0657.PNG", crop_top=int(round(120 * (1170 / 1179))))
    app = load_shot("IMG_0655.PNG")

    phone_h_target = h - s(540, scale) + s(60, scale)
    def fit_phone(shot):
        fit = phone_h_target / shot.height
        fit = min(fit, (w * 0.82) / shot.width)
        resized = shot.resize((int(shot.width * fit), int(shot.height * fit)), Image.Resampling.LANCZOS)
        return phone_frame(resized, scale)

    phone_l = fit_phone(home)
    phone_r = fit_phone(app)

    # 継ぎ目を大きくまたがせる（スワイプで1枚に見える）
    y = s(500, scale)
    overlap = s(300, scale)
    xl = w - phone_l.width + overlap
    xr = w - overlap

    # 影
    for phone, x in ((phone_l, xl), (phone_r, xr)):
        sh = drop_shadow(canvas.size, (x, y, x + phone.width, y + phone.height), scale)
        canvas = Image.alpha_composite(canvas, sh)
        canvas.paste(phone, (x, y), phone)

    # 継ぎ目の薄いガイド（自然なつながり用・ほぼ見えない）
    seam = Image.new("RGBA", (w2, h), (0, 0, 0, 0))
    ImageDraw.Draw(seam).line([(w, 0), (w, h)], fill=(255, 255, 255, 8), width=2)
    canvas = Image.alpha_composite(canvas, seam)

    # フローティングチップ
    chips = [
        (xl + s(40, scale), y + s(80, scale), "残り 15日"),
        (xr + phone_r.width - s(260, scale), y + s(200, scale), "最終営業日 11/30"),
    ]
    chip_layer = Image.new("RGBA", (w2, h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(chip_layer)
    font = fnt(W6, s(26, scale))
    for cx, cy, text in chips:
        bb = cd.textbbox((0, 0), text, font=font)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        rw, rh = tw + s(40, scale), th + s(26, scale)
        cd.rounded_rectangle((cx, cy, cx + rw, cy + rh), radius=rh // 2, fill=(255, 255, 255, 235))
        cd.text((cx + s(20, scale), cy + s(11, scale)), text, font=font, fill=INK)
    canvas = Image.alpha_composite(canvas, chip_layer)

    left_img = canvas.crop((0, 0, w, h)).convert("RGB")
    right_img = canvas.crop((w, 0, w2, h)).convert("RGB")
    return left_img, right_img



SCREENS = [
    {"kind": "diptych_left", "file": "01_home_widget.png"},
    {"kind": "diptych_right", "file": "02_nokori.png"},
    {
        "kind": "standard",
        "file": "03_kigen.png",
        "src": "IMG_0650.PNG",
        "eyebrow": "期限カード",
        "lines": ["振り込みまで", "あと何日"],
        "sub": "締めも提出も、名前をつけて足すだけ",
        "watermark": "21",
        "mood": "dark",
        "boost": True,
        "chips": [{"x": 80, "y": 1320, "text": "期限日をカレンダーに表示"}],
    },
    {
        "kind": "standard",
        "file": "04_edit_kigen.png",
        "src": "IMG_0658.PNG",
        "eyebrow": "くり返しと通知",
        "lines": ["毎月の期限を", "自動で追う"],
        "sub": "休日のずらしも、当日の通知も",
        "mood": "coral",
        "boost": True,
        "chips": [
            {"x": 70, "y": 1500, "text": "毎月繰り返す"},
            {"x": 620, "y": 1680, "text": "当日に通知"},
        ],
    },
    {
        "kind": "standard",
        "file": "05_week.png",
        "src": "IMG_0651.PNG",
        "eyebrow": "週表示",
        "lines": ["一週間を", "時間で見渡す"],
        "sub": "終日も会議も、同じタイムラインに",
        "mood": "dark",
        "boost": True,
        "chips": [{"x": 700, "y": 1100, "text": "色分けできる"}],
    },
    {
        "kind": "split",
        "file": "06_eigyobi_bangou.png",
    },
    {
        "kind": "standard",
        "file": "07_tooi.png",
        "src": "IMG_0654.PNG",
        "eyebrow": "月をまたいで",
        "lines": ["遠い期限も", "数字で追える"],
        "sub": "年をまたぐ締め切りまで、残り日数",
        "watermark": "80",
        "mood": "dark",
        "boost": True,
    },
    {
        "kind": "standard",
        "file": "08_search.png",
        "src": "IMG_0659.PNG",
        "eyebrow": "検索",
        "lines": ["会議もメモも", "すぐ見つかる"],
        "sub": "キーワードで、過去と未来の予定を横断",
        "mood": "dark",
        "boost": True,
        "chips": [{"x": 80, "y": 1100, "text": "複数ヒット"}],
    },
    {
        "kind": "standard",
        "file": "09_settings.png",
        "src": "IMG_0660.PNG",
        "eyebrow": "休み方は自由",
        "lines": ["曜日も出勤も", "自分仕様に"],
        "sub": "営業曜日の選択、休日のずらし、バックアップ",
        "mood": "light",
        "boost": True,
        "phone_scale": 0.98,
        "chips": [{"x": 90, "y": 1380, "text": "曜日ごとに営業日を選べる"}],
    },
    {
        "kind": "standard",
        "file": "10_calendar.png",
        "src": "IMG_0649.PNG",
        "eyebrow": "カレンダー",
        "lines": ["最終営業日を", "一目で"],
        "sub": "青い印で、その月の終わりがわかる",
        "mood": "dark",
        "boost": True,
        "watermark": "30",
        "chips": [{"x": 640, "y": 1360, "text": "最終営業日"}],
    },
]



_DIPTCH_CACHE = {}


def render_one(spec, w, h):
    kind = spec["kind"]
    if kind in ("diptych_left", "diptych_right"):
        key = (w, h)
        if key not in _DIPTCH_CACHE:
            _DIPTCH_CACHE[key] = compose_diptych(w, h)
        left, right = _DIPTCH_CACHE[key]
        return left if kind == "diptych_left" else right
    if kind == "hero":
        return compose_hero(w, h)
    if kind == "widget":
        return compose_widget(w, h)
    if kind == "search":
        return compose_search(w, h)
    if kind == "split":
        return compose_split(w, h)
    return compose_standard(spec, w, h)


def main():
    targets = [
        (1179, 2556, ROOT / "store"),
        (1320, 2868, ROOT / "store_6_9"),
    ]
    for w, h, folder in targets:
        folder.mkdir(parents=True, exist_ok=True)
        _DIPTCH_CACHE.clear()
        # 古いファイル名の掃除
        for stale in folder.glob("*.png"):
            stale.unlink()
        for spec in SCREENS:
            img = render_one(spec, w, h)
            out = folder / spec["file"]
            img.save(out, "PNG", optimize=True)
            print(f"{folder.name}/{out.name}")


if __name__ == "__main__":
    main()
