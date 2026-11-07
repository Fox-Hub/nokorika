#!/usr/bin/env python3
"""App Store ヘッダ画像をセーフゾーン付きで再生成する。

iPhone のプロダクトページでは左右が大きく見切れるため、
重要テキストは幅の 18〜78%・高さの 18〜82% に収める。
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "creative_assets"
ICON = ROOT.parent / "assets" / "icon" / "ios_icon.png"

W3 = "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"
W6 = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"
W8 = "/System/Library/Fonts/ヒラギノ角ゴシック W8.ttc"

INK = (18, 12, 14)
CORAL = (252, 118, 92)
MUTE = (190, 168, 160)
WHITE = (255, 255, 255)


def fnt(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def lerp(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(len(a)))


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, im.size[0] - 1, im.size[1] - 1), radius=radius, fill=255
    )
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def bg(w: int, h: int) -> Image.Image:
    img = Image.new("RGB", (w, h), INK)
    strip = Image.new("RGB", (1, h))
    px = strip.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = lerp((42, 22, 24), (14, 10, 12), t**0.9)
    img = strip.resize((w, h))
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for i in range(7):
        r = int(w * (0.18 + i * 0.04))
        d.ellipse(
            (int(w * 0.78) - r, int(h * -0.15) - r, int(w * 0.78) + r, int(h * -0.15) + r),
            fill=(*CORAL, max(8, 36 - i * 4)),
        )
    for i in range(5):
        r = int(w * (0.12 + i * 0.03))
        d.ellipse(
            (int(w * 0.08) - r, int(h * 1.05) - r, int(w * 0.08) + r, int(h * 1.05) + r),
            fill=(*CORAL, max(6, 22 - i * 3)),
        )
    return Image.alpha_composite(img.convert("RGBA"), overlay)


def widget_card(size: int) -> Image.Image:
    """ヘッダ用の残り営業日ウィジェットカード。"""
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card)
    for yy in range(size):
        t = yy / max(1, size - 1)
        col = lerp((34, 128, 230), (14, 72, 160), t)
        cd.line([(0, yy), (size, yy)], fill=(*col, 255))
    card = rounded(card, max(18, size // 12))
    cd = ImageDraw.Draw(card)
    pad = size // 14
    cd.text((pad, pad), "残り営業日", font=fnt(W6, max(18, size // 14)), fill=(220, 235, 255))
    cd.text((pad, int(size * 0.22)), "15", font=fnt(W8, max(64, size // 3)), fill=WHITE)
    cd.text(
        (pad, int(size * 0.72)),
        "最終 11/30",
        font=fnt(W3, max(16, size // 16)),
        fill=(190, 215, 245),
    )
    cd.text(
        (pad, int(size * 0.84)),
        "2026年11月",
        font=fnt(W3, max(14, size // 18)),
        fill=(170, 200, 235),
    )
    ring = (
        int(size * 0.58),
        int(size * 0.28),
        int(size * 0.90),
        int(size * 0.60),
    )
    cd.ellipse(ring, outline=(255, 255, 255, 45), width=max(4, size // 40))
    cd.arc(ring, start=-90, end=120, fill=(230, 245, 255, 245), width=max(4, size // 40))
    cd.text(
        ((ring[0] + ring[2]) // 2, (ring[1] + ring[3]) // 2),
        "79%",
        font=fnt(W6, max(16, size // 16)),
        fill=WHITE,
        anchor="mm",
    )
    return card


def phone_with_widget(h: int) -> Image.Image:
    """ホーム風の端末モック（高さ基準）。"""
    phone_h = int(h * 0.78)
    phone_w = int(phone_h * 0.48)
    scale = phone_w / 390

    wall = Image.new("RGB", (phone_w, phone_h))
    px = wall.load()
    for y in range(phone_h):
        t = y / max(1, phone_h - 1)
        col = lerp((48, 28, 40), (18, 20, 42), t)
        for x in range(phone_w):
            px[x, y] = col

    card = widget_card(int(phone_w * 0.72))
    wall_rgba = wall.convert("RGBA")
    wall_rgba.paste(card, (int(phone_w * 0.14), int(phone_h * 0.12)), card)

    # ドック風
    d = ImageDraw.Draw(wall_rgba)
    dock_y = phone_h - int(88 * scale)
    d.rounded_rectangle(
        (int(24 * scale), dock_y, phone_w - int(24 * scale), phone_h - int(28 * scale)),
        radius=int(22 * scale),
        fill=(255, 255, 255, 28),
    )
    for i, c in enumerate([(70, 130, 220), (90, 180, 120), (220, 120, 90), (170, 110, 200)]):
        tw = int(52 * scale)
        gap = int(18 * scale)
        total = tw * 4 + gap * 3
        sx = (phone_w - total) // 2
        x = sx + i * (tw + gap)
        y = dock_y + int(14 * scale)
        d.rounded_rectangle((x, y, x + tw, y + tw), radius=int(12 * scale), fill=(*c, 220))

    # アプリアイコン＋名前
    icon = Image.open(ICON).convert("RGBA").resize(
        (int(52 * scale), int(52 * scale)), Image.Resampling.LANCZOS
    )
    icon = rounded(icon, int(12 * scale))
    wall_rgba.paste(icon, (int(36 * scale), int(phone_h * 0.48)), icon)
    d.text(
        (int(36 * scale) + int(26 * scale), int(phone_h * 0.48) + int(60 * scale)),
        "ノコリカ",
        font=fnt(W6, max(14, int(18 * scale))),
        fill=(255, 255, 255, 210),
        anchor="mt",
    )

    pad = max(8, int(10 * scale))
    bezel = Image.new("RGBA", (phone_w + pad * 2, phone_h + pad * 2), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bezel)
    radius = int(48 * scale)
    bd.rounded_rectangle(
        (0, 0, bezel.width - 1, bezel.height - 1),
        radius=radius,
        fill=(28, 24, 24, 255),
    )
    inner = rounded(wall_rgba, radius - pad)
    bezel.paste(inner, (pad, pad), inner)
    # Dynamic Island
    iw, ih = int(120 * scale), int(32 * scale)
    bd.rounded_rectangle(
        ((bezel.width - iw) // 2, pad + int(14 * scale), (bezel.width + iw) // 2, pad + int(14 * scale) + ih),
        radius=ih // 2,
        fill=(8, 8, 10, 255),
    )
    return bezel


def compose_header(w: int, h: int) -> Image.Image:
    """文字のみ・中央主役。App Store の戻る／共有ボタン帯を避ける。"""
    canvas = bg(w, h)
    draw = ImageDraw.Draw(canvas)

    # --- セーフゾーン ---
    # 上: 戻る／共有ボタン / 左右: 端のクロップ
    safe_t = int(h * 0.24)
    safe_b = int(h * 0.90)
    cx = w // 2
    max_text_w = int(w * 0.70)

    # ブランド（中央）
    icon_s = max(56, w // 40)
    icon = Image.open(ICON).convert("RGBA").resize(
        (icon_s, icon_s), Image.Resampling.LANCZOS
    )
    icon = rounded(icon, max(12, icon_s // 5))
    brand_gap = max(18, w // 100)
    brand_font = fnt(W6, max(34, w // 46))
    brand_w = (
        icon_s
        + brand_gap
        + draw.textbbox((0, 0), "ノコリカ", font=brand_font)[2]
    )
    brand_x = cx - brand_w // 2
    brand_y = safe_t
    canvas.paste(icon, (brand_x, brand_y), icon)
    draw.text(
        (brand_x + icon_s + brand_gap, brand_y + icon_s // 2),
        "ノコリカ",
        font=brand_font,
        fill=WHITE,
        anchor="lm",
    )

    # アイブロウ
    ey = brand_y + icon_s + max(40, h // 22)
    draw.text(
        (cx, ey),
        "残り営業日",
        font=fnt(W6, max(34, w // 50)),
        fill=CORAL,
        anchor="mt",
    )

    # 大見出し（1行・できるだけ大きく）
    title = "今月、あと何日"
    title_size = max(96, min(220, int(w * 0.055)))
    while title_size > 72:
        title_font = fnt(W8, title_size)
        tw = draw.textbbox((0, 0), title, font=title_font)[2]
        if tw <= max_text_w:
            break
        title_size -= 4
    title_font = fnt(W8, title_size)

    ty = ey + max(52, h // 18)
    draw.text((cx, ty), title, font=title_font, fill=WHITE, anchor="mt")

    return canvas.convert("RGB")


def save_preview(im: Image.Image, path: Path, max_w: int = 960) -> None:
    ratio = max_w / im.width
    prev = im.resize((max_w, int(im.height * ratio)), Image.Resampling.LANCZOS)
    prev.save(path, "PNG", optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    sizes = [
        (3840, 1646, "header_21x9_3840x1646"),
        (5244, 2950, "universal_16x9_5244x2950"),
    ]
    for w, h, stem in sizes:
        img = compose_header(w, h)
        png = OUT / f"{stem}.png"
        jpg = OUT / f"{stem}.jpg"
        img.save(png, "PNG", optimize=True)
        img.save(jpg, "JPEG", quality=92, optimize=True)
        save_preview(img, OUT / f"preview_{stem}.png")
        # アップロード用（preview と取り違えない名前）
        upload = OUT / f"UPLOAD_{stem.split('_', 1)[1] if '_' in stem else stem}.png"
        # UPLOAD_3840x1646 / UPLOAD_5244x2950 形式に寄せる
        if "3840" in stem:
            upload = OUT / "UPLOAD_header_3840x1646.png"
        else:
            upload = OUT / "UPLOAD_header_5244x2950.png"
        img.save(upload, "PNG", optimize=True)
        print(f"{png.name}: {img.size[0]}x{img.size[1]}")
        print(f"  -> {upload.name}")


if __name__ == "__main__":
    main()
