"""Opt-in offline re-editor: original video/music plus upward text and supplied WAVs.

No network, AI image calls, generated speech or publication in this module.
The old text is baked into the video: opaque panels cover it, not inpainting.
"""
import json
import math
from pathlib import Path
import sys
import tempfile
import wave

from PIL import Image, ImageDraw
from story_series import WIDTH, HEIGHT, FPS, run_ffmpeg, validate_video, wrap
from story_studio_render import studio_font

READ_HEIGHT, READ_Y, LINE = 400, 770, 48
LABELS = {
    'ko': ('비빔밥 음식 백과', 'AI 음성 · AI 삽화 · 기존 음악 재사용'),
    'en': ('BIBIMBAP / FOOD GUIDE', 'AI voice · AI illustrations · Reused music'),
    'es': ('BIBIMBAP / GUÍA CULINARIA', 'Voz e ilustraciones de IA · Misma música'),
}


def speech_seconds(path):
    path = Path(path)
    if not path.is_file() or not 1000 <= path.stat().st_size <= 12_000_000:
        raise ValueError('invalid_voice_file')
    with wave.open(str(path), 'rb') as source:
        if source.getcomptype() != 'NONE' or source.getsampwidth() != 2 or source.getnchannels() not in (1, 2):
            raise ValueError('invalid_voice_format')
        rate = source.getframerate()
        if not 8000 <= rate <= 48000:
            raise ValueError('invalid_voice_duration')
        # Streaming WAV may advertise an unknown frame count. Measure actual PCM,
        # bounded to 91 seconds, instead of trusting the container's placeholder.
        pcm = source.readframes(rate * 91)
        frame_bytes = source.getnchannels() * source.getsampwidth()
        seconds = len(pcm) / frame_bytes / rate
        if len(pcm) % frame_bytes or not .5 <= seconds <= 90:
            raise ValueError('invalid_voice_duration')
    return seconds


def layout(text, language):
    if language not in LABELS or not isinstance(text, str) or not text.strip() or len(text) > 600:
        raise ValueError('invalid_scroll_text')
    font = studio_font(language, 34)
    measure = ImageDraw.Draw(Image.new('RGB', (WIDTH, HEIGHT)))
    lines = []
    for paragraph in text.splitlines():
        lines.extend(wrap(measure, paragraph, font, 624) if paragraph else [''])
    if not 1 <= len(lines) <= 45:
        raise ValueError('scroll_text_overflow')
    # First and final lines each pass through the same comfortable reading band.
    travel = max(0, (len(lines) - 1) * LINE)
    image = Image.new('RGB', (WIDTH, READ_HEIGHT + travel), '#182522')
    draw = ImageDraw.Draw(image)
    for index, line in enumerate(lines):
        draw.text((48, 165 + index * LINE), line, font=font, fill='#fff9ed')
    return image, travel, len(lines)


def offset(travel, seconds, time):
    return round(travel * min(1, max(0, time / seconds)))


def chrome(title, language, part, count):
    if language not in LABELS or not isinstance(title, str) or not 1 <= len(title) <= 45:
        raise ValueError('invalid_reedit_title')
    image = Image.new('RGBA', (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WIDTH, 309), fill='#182522')
    draw.rectangle((0, 760, WIDTH, HEIGHT), fill='#182522')
    small, body = studio_font(language, 22), studio_font(language, 32)
    draw.text((44, 43), '레시피 스카우트 / 음식 백과' if language == 'ko' else 'RECIPE SCOUT / FOOD LIBRARY', font=small, fill='#e7c88a')
    lines = wrap(draw, title, body, 620)
    if len(lines) > 3:
        raise ValueError('reedit_title_overflow')
    for i, line in enumerate(lines):
        draw.text((44, 100 + 44*i), line, font=body, fill='#fff9ed')
    draw.text((44, 252), f'{LABELS[language][0]}  {part:02}/{count:02}', font=small, fill='#e7c88a')
    draw.text((44, 1195), LABELS[language][1], font=small, fill='#dfd7c8')
    return image


def validate_plan(plan, directory):
    if not isinstance(plan, dict) or set(plan) != {'ko'}:
        raise ValueError('korean_only_required')
    durations = {}
    for language, edition in plan.items():
        chunks = edition['chunks']
        if not isinstance(chunks, list) or not 3 <= len(chunks) <= 32:
            raise ValueError('invalid_chunk_count')
        chrome(edition['title'], language, 1, len(chunks))
        durations[language] = []
        for index, text in enumerate(chunks):
            _, travel, lines = layout(text, language)
            seconds = math.ceil(speech_seconds(directory/f'{language}-{index:02}.wav') + 1)
            # Do not speed speech up or squeeze unreadable text into a fixed 60s.
            if travel / seconds > 38:
                raise ValueError('narration_too_fast_for_scroll')
            durations[language].append(seconds)
        if not 30 <= sum(durations[language]) <= 900:
            raise ValueError('edition_duration_out_of_bounds')
    return durations


def render_edition(source, edition, language, voices, output, durations):
    output = Path(output)
    if output.exists():
        raise ValueError('output_already_exists')
    with tempfile.TemporaryDirectory(prefix='story-reedit-') as temporary:
        temp = Path(temporary)
        start = 0
        rows = ['ffconcat version 1.0']
        for index, (text, seconds) in enumerate(zip(edition['chunks'], durations)):
            scroll, travel, _ = layout(text, language)
            scroll.save(temp/'scroll.png')
            chrome(edition['title'], language, index+1, len(durations)).save(temp/'chrome.png')
            # Original video and music run continuously across chunks and loop at 60s.
            # Only music volume is lowered so the new narration remains intelligible.
            filters = (
                f'[0:v]setpts=PTS-STARTPTS[base];[base][2:v]overlay=0:0:format=auto[masked];'
                f"[3:v]crop={WIDTH}:{READ_HEIGHT}:0:'min({travel},{travel}*t/{seconds})'[scroll];"
                f'[masked][scroll]overlay=0:{READ_Y}:format=auto,format=yuv420p[v];'
                '[0:a]asetpts=PTS-STARTPTS,volume=0.22[music];'
                '[1:a]aformat=sample_rates=44100:channel_layouts=stereo,apad[voice];'
                '[music][voice]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.92[a]')
            target = temp/f'part-{index:02}.mp4'
            run_ffmpeg(['-filter_complex_threads','1','-stream_loop','-1','-ss',str(start % 60),'-i',str(source),
                        '-i',str(voices/f'{language}-{index:02}.wav'),
                        '-loop','1','-framerate',str(FPS),'-i',str(temp/'chrome.png'),
                        '-loop','1','-framerate',str(FPS),'-i',str(temp/'scroll.png'),
                        '-filter_complex',filters,'-map','[v]','-map','[a]','-t',str(seconds),
                        '-r',str(FPS),'-c:v','libx264','-preset','ultrafast','-crf','25','-threads','2',
                        '-c:a','aac','-b:a','128k','-ar','44100',str(target)], timeout=180)
            rows.append(f"file '{target.name}'")
            start += seconds
        (temp/'parts.ffconcat').write_text('\n'.join(rows), encoding='utf-8')
        run_ffmpeg(['-f','concat','-safe','0','-i',str(temp/'parts.ffconcat'),'-map','0:v:0','-map','0:a:0',
                    '-c','copy','-movflags','+faststart',str(output)])
    if output.stat().st_size > 104857600:
        raise ValueError('reedit_video_too_large')
    return validate_video(output, sum(durations))


def main(directory):
    source = directory/'source.mp4'
    validate_video(source, 60)
    plan_file = directory/'narration.json'
    if plan_file.stat().st_size > 150000:
        raise ValueError('plan_too_large')
    plan = json.loads(plan_file.read_text(encoding='utf-8'))
    durations = validate_plan(plan, directory)
    result = {}
    for language, edition in plan.items():
        result[language] = render_edition(source, edition, language, directory, directory/f'{language}.mp4', durations[language])
    (directory/'reedit-result.json').write_text(json.dumps(result), encoding='utf-8')


if __name__ == '__main__':
    try:
        if len(sys.argv) == 3 and sys.argv[1] == '--validate-source':
            validate_video(Path(sys.argv[2]), 60)
            print('Source video verified; no paid API calls performed.')
        elif len(sys.argv) == 2:
            main(Path(sys.argv[1]))
            print('Narrated re-edit verified; no upload performed.')
        else:
            raise ValueError('invalid_arguments')
    except Exception:
        print('Narrated re-edit stopped safely; review required.', file=sys.stderr)
        sys.exit(1)
