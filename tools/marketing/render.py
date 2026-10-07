"""Render original, silent 24-second app-feature cards; no third-party media."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from PIL import Image, ImageDraw, ImageFont


def render(source, output):
    campaign = json.loads(Path(source).read_text(encoding='utf-8'))
    scenes = campaign['scenes']
    if len(scenes) != 3 or any(not isinstance(s, str) or not 1 <= len(s) <= 72 for s in scenes):
        raise ValueError('invalid_scenes')
    font_path = os.environ.get('MARKETING_FONT', '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
    font = ImageFont.truetype(font_path, 52)
    small = ImageFont.truetype(font_path, 30)
    with tempfile.TemporaryDirectory() as directory:
        for index, text in enumerate(scenes):
            image = Image.new('RGB', (720, 1280), '#102b25')
            draw = ImageDraw.Draw(image)
            draw.rounded_rectangle((36, 240, 684, 1000), 36, fill='#edf5df')
            draw.text((48, 120), 'Recipe Scout', font=font, fill='#edf5df')
            lines = []
            for paragraph in text.splitlines():
                line = ''
                for word in paragraph.split():
                    candidate = f'{line} {word}'.strip()
                    if draw.textlength(candidate, font=font) <= 560:
                        line = candidate
                        continue
                    if line:
                        lines.append(line)
                    line = ''
                    for character in word:
                        if draw.textlength(line + character, font=font) > 560:
                            lines.append(line)
                            line = ''
                        line += character
                if line:
                    lines.append(line)
            y = 610 - len(lines) * 38
            for line in lines:
                draw.text((80, y), line, font=font, fill='#102b25')
                y += 76
            draw.text((48, 1100), '레시피 스카우트 · 앱 기능 안내', font=small, fill='#edf5df')
            image.save(Path(directory) / f'{index:02}.png')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', '1/8', '-i',
                        str(Path(directory) / '%02d.png'), '-t', '24', '-r', '24',
                        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(output)],
                       check=True, timeout=120)


if __name__ == '__main__':
    render(sys.argv[1], sys.argv[2])
