"""Bounded, offline studio renderer. No network, shell strings or model code."""
import json
import math
from pathlib import Path
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont, ImageOps
from story_music import score
from story_series import FONT, WIDTH, HEIGHT, FPS, wrap, run_ffmpeg, write_audio, validate_video

LABELS = {
    'ko': ('홍보용 허구 · AI 삽화 · 창작 음악', '요리 영상 검색과 저장 · Recipe Scout'),
    'en': ('Fiction · AI illustration · Original music', 'Find and save cooking videos · Recipe Scout'),
    'es': ('Ficción · Ilustración de IA · Música original', 'Busca y guarda recetas · Recipe Scout'),
}


def validate(data):
    if data['series']['language'] not in LABELS:
        raise ValueError('invalid_language')
    settings = data['recipe']['settings']
    for key, low, high in [('font_size', 32, 48), ('scene_seconds', 10, 10), ('music_gain', .2, 1.5)]:
        value = settings[key]
        if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError('invalid_settings')
        if key != 'music_gain' and type(value) is not int:
            raise ValueError('invalid_settings')
    draft = data['episode']['draft']
    if len(draft['captions']) != 6 or any(not isinstance(c, str) or not c.strip() or len(c) > 60 for c in draft['captions']):
        raise ValueError('invalid_captions')
    if not isinstance(draft['title'], str) or not 1 <= len(draft['title']) <= 45:
        raise ValueError('invalid_title')
    number = data['episode']['number']
    if type(number) is not int or not 1 <= number <= 1000:
        raise ValueError('invalid_episode')
    return settings, draft


def layer(data, caption, last=False):
    settings, draft = validate(data)
    image = Image.new('RGBA', (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    for y in range(HEIGHT):
        opacity = max(max(0, min(1, (310-y)/100))*195, max(0, min(1, (y-750)/250))*235)
        draw.line((0, y, WIDTH, y), fill=(12, 21, 20, round(opacity)))
    small = ImageFont.truetype(str(FONT), 21)
    title = ImageFont.truetype(str(FONT), 30)
    body = ImageFont.truetype(str(FONT), settings['font_size'])
    draw.text((44, 55), 'RECIPE SCOUT / ORIGINAL STORY', font=small, fill='#efd3a0')
    title_lines = wrap(draw, f"{data['episode']['number']:02d} · {draft['title']}", title, 580)
    if len(title_lines) > 3:
        raise ValueError('title_overflow')
    for i, line in enumerate(title_lines):
        draw.text((44, 105+i*42), line, font=title, fill='#fff7e9')
    lines = wrap(draw, caption, body, 550)
    if len(lines) > 4:
        raise ValueError('caption_overflow')
    for i, line in enumerate(lines):
        draw.text((44, 865+i*56), line, font=body, fill='#fff7e9', stroke_width=1)
    disclosure, cta = LABELS[data['series']['language']]
    draw.text((44, 1180), disclosure, font=small, fill='#dfd7c8')
    if last:
        for i, line in enumerate(wrap(draw, cta, small, 560)):
            draw.text((44, 1100+i*28), line, font=small, fill='#efd3a0')
    return image


def render(data, image_paths, output):
    settings, draft = validate(data)
    output = Path(output)
    if output.exists():
        raise ValueError('output_already_exists')
    # Check all typography BEFORE video encoding. Never silently truncate a line.
    overlays = [layer(data, c, i == 5) for i, c in enumerate(draft['captions'])]
    durations, seconds = [10] * 6, 60
    if len(image_paths) != 6:
        raise ValueError('six_panels_required')
    with tempfile.TemporaryDirectory(prefix='story-studio-render-') as temporary:
        temp = Path(temporary)
        for i, image_path in enumerate(image_paths):
            with Image.open(image_path) as original:
                if original.width * original.height > 20_000_000:
                    raise ValueError('image_too_large')
                ImageOps.fit(original.convert('RGB'), (WIDTH, HEIGHT)).save(temp/f'background-{i}.png')
        rows = ['ffconcat version 1.0']
        for i, (overlay, duration) in enumerate(zip(overlays, durations)):
            overlay.save(temp/f'layer-{i}.png')
            rows.extend([f"file 'layer-{i}.png'", f'duration {duration}'])
        rows.append("file 'layer-5.png'")
        (temp/'overlays.ffconcat').write_text('\n'.join(rows), encoding='utf-8')
        write_audio((v * 2 * settings['music_gain'] for v in score(seconds, (data['episode']['number']-1) % 12 + 1)), temp/'music.wav')
        filters = (f"[0:v]scale=1080:1920,zoompan=z='1+mod(on,240)*0.0001':"
                   f"x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d={10*FPS}:s={WIDTH}x{HEIGHT}:fps={FPS}[bg];"
                   f'[1:v]fps={FPS}[titles];[bg][titles]overlay=0:0:format=auto,format=yuv420p[v]')
        run_ffmpeg(['-filter_complex_threads','1','-framerate','1/10','-i',str(temp/'background-%d.png'),'-f','concat','-safe','0',
                    '-i',str(temp/'overlays.ffconcat'),'-i',str(temp/'music.wav'),'-filter_complex',filters,
                    '-map','[v]','-map','2:a:0','-t',str(seconds),'-r',str(FPS),'-c:v','libx264','-preset','veryfast',
                    '-crf','21','-threads','2','-c:a','aac','-b:a','128k','-ar','44100','-movflags','+faststart',str(output)])
    return validate_video(output, seconds)


if __name__ == '__main__':
    try:
        source = Path(sys.argv[1])
        if source.stat().st_size > 250000:
            raise ValueError('input_too_large')
        data = json.loads(source.read_text(encoding='utf-8'))
        directory = Path(sys.argv[2])
        images = [directory/f'panel-{i}.png' for i in range(6)]
        for language in ('ko', 'en', 'es'):
            edition = data['episode']['draft'] if language == 'ko' else data['episode']['draft']['translations'][language]
            translated = {**data, 'series': {**data['series'], 'language': language},
                          'episode': {**data['episode'], 'draft': edition}}
            render(translated, images, directory/f'{language}.mp4')
        print('Story preview rendered and verified.')
    except Exception:
        print('Story preview failed validation or rendering.', file=sys.stderr)
        sys.exit(1)
