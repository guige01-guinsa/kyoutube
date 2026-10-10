"""Create a caption-led 30-second vertical Recipe Scout YouTube Short draft."""

from __future__ import annotations

import subprocess
from pathlib import Path

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = ROOT / "outputs" / "youtube-short"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

WIDTH, HEIGHT = 1080, 1920
BACKGROUND = "#fbf7f3"
PLUM = "#724466"
PLUM_DARK = "#48283f"
PEACH = "#f8d8c0"
TEXT = "#2b2529"
MUTED = "#6f626a"
FONT = Path(r"C:\Windows\Fonts\malgun.ttf")
FONT_BOLD = Path(r"C:\Windows\Fonts\malgunbd.ttf")

ASSETS = {
    "ingredients": Path(r"C:\Users\ADMIN\AppData\Local\Temp\codex-clipboard-3e7d636b-db1c-45dc-b12c-df9a4a9dc0b3.png"),
    "shopping": Path(r"C:\Users\ADMIN\AppData\Local\Temp\codex-clipboard-311de51a-a967-4895-ac72-f092b6fa5fc0.png"),
}


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_BOLD if bold else FONT, size)


def center_text(draw: ImageDraw.ImageDraw, y: int, value: str, size: int, color: str, bold: bool = False) -> int:
    active_font = font(size, bold)
    box = draw.multiline_textbbox((0, 0), value, font=active_font, spacing=10, align="center")
    height = box[3] - box[1]
    draw.multiline_text(((WIDTH - (box[2] - box[0])) / 2, y), value, font=active_font, fill=color, spacing=10, align="center")
    return y + height


def rounded_panel(image: Image.Image, rect: tuple[int, int, int, int], radius: int = 34) -> None:
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    sx1, sy1, sx2, sy2 = rect
    shadow_draw.rounded_rectangle((sx1, sy1 + 12, sx2, sy2 + 12), radius=radius, fill=(53, 28, 46, 32))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    ImageDraw.Draw(image).rounded_rectangle(rect, radius=radius, fill="white", outline="#eadce3", width=2)


def image_panel(base: Image.Image, source: Path, top: int) -> None:
    source_image = Image.open(source).convert("RGB")
    outer = (54, top, WIDTH - 54, top + 940)
    rounded_panel(base, outer)
    available_w, available_h = outer[2] - outer[0] - 24, outer[3] - outer[1] - 24
    scale = min(available_w / source_image.width, available_h / source_image.height)
    resized = source_image.resize((round(source_image.width * scale), round(source_image.height * scale)), Image.Resampling.LANCZOS)
    x = outer[0] + (available_w - resized.width) // 2 + 12
    y = outer[1] + (available_h - resized.height) // 2 + 12
    mask = Image.new("L", resized.size, 255)
    base.paste(resized, (x, y), mask)


def slide(title: str, subtitle: str, asset: Path | None = None, note: str | None = None) -> Image.Image:
    page = Image.new("RGBA", (WIDTH, HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(page)
    draw.rounded_rectangle((0, 0, WIDTH, 22), radius=0, fill=PLUM)
    draw.rounded_rectangle((54, 68, 262, 126), radius=29, fill="#f4e6ef")
    draw.text((86, 80), "RECIPE SCOUT", font=font(23, True), fill=PLUM)
    title_bottom = center_text(draw, 190, title, 60, TEXT, True)
    subtitle_bottom = center_text(draw, title_bottom + 28, subtitle, 32, MUTED)
    if asset:
        image_panel(page, asset, subtitle_bottom + 64)
    elif note:
        top = subtitle_bottom + 100
        rounded_panel(page, (70, top, WIDTH - 70, top + 700), 42)
        note_y = center_text(draw, top + 176, note, 55, PLUM, True)
        center_text(draw, note_y + 42, "메뉴 선택부터 구매처 확인까지", 32, MUTED)
        center_text(draw, note_y + 94, "한 번에 이어집니다", 32, MUTED)
    if note and asset:
        panel_top = 1550
        rounded_panel(page, (68, panel_top, WIDTH - 68, panel_top + 168), 30)
        center_text(draw, panel_top + 44, note, 29, PLUM, True)
    return page.convert("RGB")


def purchase_slide() -> Image.Image:
    page = Image.new("RGBA", (WIDTH, HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(page)
    draw.rounded_rectangle((0, 0, WIDTH, 22), radius=0, fill=PLUM)
    draw.rounded_rectangle((54, 68, 262, 126), radius=29, fill="#f4e6ef")
    draw.text((86, 80), "RECIPE SCOUT", font=font(23, True), fill=PLUM)
    title_bottom = center_text(draw, 190, "④ 등록된 재료는 구매처 연결", 60, TEXT, True)
    center_text(draw, title_bottom + 28, "상품 규격을 확인하고 필요한 수량을 고르세요", 32, MUTED)

    panel = (70, 530, WIDTH - 70, 1320)
    rounded_panel(page, panel, 44)
    # Draw the header after the panel shadow so it stays crisp on all Pillow builds.
    draw = ImageDraw.Draw(page)
    draw.rounded_rectangle((54, 68, 262, 126), radius=29, fill="#f4e6ef")
    draw.text((86, 80), "RECIPE SCOUT", font=font(23, True), fill=PLUM)
    title_bottom = center_text(draw, 190, "④ 등록된 재료는 구매처 연결", 60, TEXT, True)
    center_text(draw, title_bottom + 28, "상품 규격을 확인하고 필요한 수량을 고르세요", 32, MUTED)
    draw.text((116, 600), "제휴 상품", font=font(28, True), fill=PLUM)
    draw.text((116, 678), "국간장 500ml", font=font(54, True), fill=TEXT)
    draw.text((116, 758), "샘표 · 500ml", font=font(30), fill=MUTED)
    draw.rounded_rectangle((116, 842, WIDTH - 116, 960), radius=28, fill="#f7efe6")
    draw.text((150, 874), "필요량 2큰술 · 판매 규격은 구매처에서 확인", font=font(27), fill=TEXT)
    draw.rounded_rectangle((116, 1035, WIDTH - 116, 1162), radius=32, fill=PLUM)
    button_font = font(39, True)
    label = "↗  쿠팡에서 구매"
    label_box = draw.textbbox((0, 0), label, font=button_font)
    draw.text(((WIDTH - (label_box[2] - label_box[0])) / 2, 1072), label, font=button_font, fill="white")
    center_text(draw, 1455, "등록된 제휴상품에 한해 구매처 연결을 지원합니다", 30, PLUM, True)
    return page.convert("RGB")


def main() -> None:
    missing = [str(path) for path in ASSETS.values() if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing screen assets: " + ", ".join(missing))

    slides = [
        slide(
            "오늘 저녁,\n장보기가 쉬워집니다",
            "레시피와 인분만 고르세요",
            note="필요한 재료와 양을 바로 계산해 드려요",
        ),
        slide("① 오늘 만들 메뉴 선택", "먹고 싶은 레시피를 고르면", ASSETS["ingredients"]),
        slide("② 필요한 재료와 양 확인", "인분에 맞춰 장보기 목록을 준비해요", ASSETS["ingredients"]),
        slide("③ 장보기 목록 완성", "빠진 재료를 한눈에 확인하세요", ASSETS["shopping"]),
        purchase_slide(),
        slide(
            "레시피 스카우트",
            "오늘의 장보기를 더 간편하게",
            note="Google Play에서 ‘레시피 스카우트’를 검색하세요",
        ),
    ]

    frames = []
    for index, page in enumerate(slides, start=1):
        path = OUTPUT_DIR / f"slide-{index:02}.png"
        page.save(path, quality=95)
        frames.append(path)

    concat = OUTPUT_DIR / "recipe-scout-short-concat.txt"
    concat.write_text("".join(f"file '{frame.as_posix()}'\nduration 5\n" for frame in frames), encoding="utf-8")
    output = OUTPUT_DIR / "recipe-scout-30sec-tutorial-short.mp4"
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    subprocess.run(
        [
            ffmpeg,
            "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", str(concat),
            "-r", "30",
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart",
            "-c:v", "libx264",
            "-crf", "20",
            str(output),
        ],
        check=True,
    )
    print(output)


if __name__ == "__main__":
    main()
