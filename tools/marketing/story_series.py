"""Offline, opt-in story pilot builder. Never imports the publisher or uses secrets.

Produces reviewed episode MP4s, a combined film, a complete reading edition,
subtitles, and provenance metadata. Existing 24-second production cards are untouched.
"""
import argparse
from array import array
import hashlib
import html
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import wave

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont, ImageOps

from story_music import RATE, score

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / 'assets/fonts/NanumGothic-Regular.ttf'
WIDTH, HEIGHT, FPS = 720, 1280, 24


def text(value, limit):
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise ValueError('invalid_text')
    return value


def asset(root, name):
    if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9_-]+\.png', name):
        raise ValueError('invalid_asset_name')
    target = (root / name).resolve()
    if not target.is_relative_to(root.resolve()) or not target.is_file():
        raise ValueError('asset_outside_series_or_missing')
    return target


def load_series(path):
    path = Path(path)
    if path.stat().st_size > 250_000:
        raise ValueError('series_too_large')
    data = json.loads(path.read_text(encoding='utf-8'))
    if data.get('schema_version') != 1 or not re.fullmatch(r'[a-z0-9-]{1,60}', data.get('id', '')):
        raise ValueError('invalid_series')
    for key in ('title', 'subtitle', 'disclosure', 'cta'):
        text(data.get(key), 120)
    if data.get('destination') != 'https://recipe-scout-workspace.web.app/':
        raise ValueError('unapproved_destination')
    if not isinstance(data.get('music'), dict) or data['music'].get('kind') != 'original_synthesis':
        raise ValueError('unreviewed_music_source')
    bible = data.get('bible', {})
    if not isinstance(bible, dict) or not all(bible.get(k) for k in ('premise', 'characters', 'timeline', 'invariants')):
        raise ValueError('missing_continuity_bible')
    episodes = data.get('episodes')
    if not isinstance(episodes, list) or not 1 <= len(episodes) <= 12:
        raise ValueError('invalid_episode_count')
    for number, episode in enumerate(episodes, 1):
        if type(episode.get('number')) is not int or episode['number'] != number:
            raise ValueError('episodes_must_be_consecutive')
        text(episode.get('title'), 60)
        text(episode.get('ending'), 180)
        if number > 1:
            text(episode.get('recap'), 200)
        asset(path.parent, episode.get('image'))
        chapter = episode.get('chapter')
        if not isinstance(chapter, list) or not 3 <= len(chapter) <= 40:
            raise ValueError('invalid_chapter')
        for paragraph in chapter:
            text(paragraph, 1500)
        scenes = episode.get('scenes')
        if not isinstance(scenes, list) or not 3 <= len(scenes) <= 12:
            raise ValueError('invalid_scenes')
        for scene in scenes:
            text(scene.get('caption'), 100)
            text(scene.get('narration'), 200)
    return data


def read_voice(path):
    with wave.open(str(path), 'rb') as source:
        if (source.getframerate(), source.getnchannels(), source.getsampwidth(), source.getcomptype()) != (RATE, 1, 2, 'NONE'):
            raise ValueError('narration_must_be_22050hz_mono_pcm16')
        if not RATE // 2 <= source.getnframes() <= RATE * 25:
            raise ValueError('invalid_narration_duration')
        samples = array('h', source.readframes(source.getnframes()))
    if sys.byteorder != 'little':
        samples.byteswap()
    peak = max(map(abs, samples), default=0)
    if peak < 100:
        raise ValueError('silent_narration')
    return array('f', (value / peak * .62 for value in samples))


def scene_seconds(voice):
    # Reserve breath before and after each scene; never truncate narration.
    return max(6, math.ceil(len(voice) / RATE + 1.1))


def caption_seconds(caption):
    # Give readers time to see the illustration, then read the Korean captions.
    text(caption, 100)
    return max(7, math.ceil(len(re.sub(r'\s', '', caption)) / 5 + 2))


def write_audio(values, output):
    samples = array('h')
    for value in values:
        if not math.isfinite(value) or abs(value) >= .98:
            raise ValueError('audio_would_clip')
        samples.append(round(value * 32767))
    if not samples:
        raise ValueError('empty_audio')
    peak = max(map(abs, samples)) / 32767
    rms = math.sqrt(sum((v / 32767) ** 2 for v in samples) / len(samples))
    if sys.byteorder != 'little':
        samples.byteswap()
    with wave.open(str(output), 'wb') as dest:
        dest.setparams((1, 2, RATE, len(samples), 'NONE', 'not compressed'))
        dest.writeframes(samples.tobytes())
    return {'peak': round(peak, 4), 'rms': round(rms, 4), 'sample_rate': RATE}


def music_audio(durations, episode, output):
    if not durations or any(type(d) is not int or d < 1 for d in durations):
        raise ValueError('invalid_scene_durations')
    # This path reads no voice files. A little more presence for standalone music.
    return write_audio((tone * 2 for tone in score(sum(durations), episode)), output)


def mix_audio(voices, durations, episode, output):
    if len(voices) != len(durations) or any(len(v) / RATE + .7 > d for v, d in zip(voices, durations)):
        raise ValueError('narration_would_be_truncated')
    seconds = sum(durations)
    music = score(seconds, episode)
    speech = array('f', [0]) * len(music)
    offset = 0
    for voice, duration in zip(voices, durations):
        start = offset + int(.35 * RATE)
        speech[start:start + len(voice)] = voice
        offset += int(duration * RATE)
    samples = array('h')
    duck = 1.0
    for i, (voice, tone) in enumerate(zip(speech, music)):
        desired = .34 if abs(voice) > .008 else 1.0
        duck += (desired - duck) * (.003 if desired < duck else .00008)
        value = voice + tone * duck
        if abs(value) >= .98:
            raise ValueError('audio_would_clip')
        samples.append(round(value * 32767))
    peak = max(map(abs, samples)) / 32767
    rms = math.sqrt(sum((v / 32767) ** 2 for v in samples) / len(samples))
    if sys.byteorder != 'little':
        samples.byteswap()
    with wave.open(str(output), 'wb') as dest:
        dest.setparams((1, 2, RATE, len(samples), 'NONE', 'not compressed'))
        dest.writeframes(samples.tobytes())
    return {'peak': round(peak, 4), 'rms': round(rms, 4), 'sample_rate': RATE}


def wrap(draw, value, font, width):
    result = []
    for paragraph in value.splitlines():
        line = ''
        for word in paragraph.split():
            candidate = f'{line} {word}'.strip()
            if draw.textlength(candidate, font=font) <= width:
                line = candidate
                continue
            if line:
                result.append(line)
                line = ''
            for char in word:
                if draw.textlength(line + char, font=font) > width and line:
                    result.append(line)
                    line = ''
                line += char
        if line.strip():
            result.append(line.strip())
    return result


def overlay(data, episode, caption, last=False):
    layer = Image.new('RGBA', (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(layer)
    # Fixed safe areas: captions stay clear of the usual right-hand Shorts controls.
    for y in range(HEIGHT):
        top = max(0, min(1, (300 - y) / 100)) * 175
        bottom = max(0, min(1, (y - 760) / 270)) * 224
        draw.line((0, y, WIDTH, y), fill=(12, 21, 20, round(max(top, bottom))))
    small = ImageFont.truetype(str(FONT), 22)
    title = ImageFont.truetype(str(FONT), 36)
    body = ImageFont.truetype(str(FONT), 40)
    label = f"{episode['number']:02d}  {episode['title']}"
    if draw.textlength(data['title'], font=title) > 630 or draw.textlength(label, font=small) > 630:
        raise ValueError('title_overflow')
    draw.text((44, 55), 'RECIPE SCOUT  /  ORIGINAL STORY', font=small, fill='#efd3a0')
    draw.text((44, 98), data['title'], font=title, fill='#fff7e9')
    draw.text((44, 154), label, font=small, fill='#f5e9d7')
    lines = wrap(draw, caption, body, 560)
    if len(lines) > 4:
        raise ValueError('caption_overflow')
    for i, line in enumerate(lines):
        draw.text((44, 884 + i * 59), line, font=body, fill='#fff7e9', stroke_width=1)
    draw.rounded_rectangle((44, 1150, 620, 1153), radius=1, fill='#bda57a')
    audio_label = '창작 음악' if data.get('audio_mode') == 'music_only' else '합성 음성'
    draw.text((44, 1180), f'홍보용 창작 이야기 · AI 삽화 · {audio_label}', font=small, fill='#dfd7c8')
    if last:
        draw.text((44, 1090), '요리 영상 검색 · 저장 | 레시피 스카우트', font=small, fill='#efd3a0')
    return layer


def run_ffmpeg(args, timeout=240):
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-hide_banner', '-loglevel', 'error', '-nostdin', *args],
                   check=True, timeout=timeout)


def stamp(seconds):
    milliseconds = round(seconds * 1000)
    return f'{milliseconds // 3600000:02}:{milliseconds // 60000 % 60:02}:{milliseconds // 1000 % 60:02},{milliseconds % 1000:03}'


def subtitles(scenes, durations, music_only=False):
    parts, start = [], 0
    for index, (scene, duration) in enumerate(zip(scenes, durations), 1):
        content = scene['caption'] if music_only else scene['narration']
        parts.append(f"{index}\n{stamp(start)} --> {stamp(start + duration)}\n{content}\n")
        start += duration
    return '\n'.join(parts)


def validate_video(path, expected_seconds):
    frames = imageio_ffmpeg.read_frames(str(path))
    try:
        metadata = next(frames)
    finally:
        frames.close()
    if metadata['source_size'] != (WIDTH, HEIGHT) or metadata['codec'] != 'h264' or metadata['fps'] != FPS:
        raise ValueError('invalid_video_format')
    if metadata['pix_fmt'].split('(')[0] != 'yuv420p':
        raise ValueError('invalid_pixel_format')
    count, seconds = imageio_ffmpeg.count_frames_and_secs(str(path))
    if count != expected_seconds * FPS or abs(seconds - expected_seconds) > .1:
        raise ValueError('invalid_video_length')
    # Require an actual audio stream and decode it, not merely a filename/metadata flag.
    run_ffmpeg(['-i', str(path), '-map', '0:a:0', '-f', 'null', '-'])
    return {'seconds': seconds, 'frames': count, 'size': [WIDTH, HEIGHT], 'audio': True,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def render_episode(data, episode, root, voice_dir, output, music_only=False):
    number = episode['number']
    if music_only:
        durations = [caption_seconds(scene['caption']) for scene in episode['scenes']]
    else:
        voices = [read_voice(voice_dir / f'ep{number:02}-scene{i:02}.wav') for i in range(1, len(episode['scenes']) + 1)]
        durations = [scene_seconds(voice) for voice in voices]
    if sum(durations) > 180:
        raise ValueError('episode_too_long')
    target = output / f'episode-{number:02}.mp4'
    audio_path = output / f'episode-{number:02}-mix.wav'
    stats = music_audio(durations, number, audio_path) if music_only else mix_audio(voices, durations, number, audio_path)
    image = asset(root, episode['image'])
    with tempfile.TemporaryDirectory(prefix='story-render-') as temporary:
        temp = Path(temporary)
        # Reuse original art unmodified; resize/composite only in generated video frames.
        with Image.open(image) as source:
            background = ImageOps.fit(source.convert('RGB'), (WIDTH, HEIGHT))
        background.save(temp / 'background.png')
        rows = ['ffconcat version 1.0']
        for index, (scene, duration) in enumerate(zip(episode['scenes'], durations)):
            title_layer = overlay(data, episode, scene['caption'], index == len(durations) - 1)
            name = f'overlay-{index:02}.png'
            title_layer.save(temp / name)
            rows.extend([f"file '{name}'", f'duration {duration}'])
            if index == 0:
                poster = background.convert('RGBA')
                poster.alpha_composite(title_layer)
                poster.convert('RGB').save(output / f'episode-{number:02}-poster.jpg', quality=94)
        rows.append(f"file 'overlay-{len(durations)-1:02}.png'")
        (temp / 'overlays.ffconcat').write_text('\n'.join(rows), encoding='utf-8')
        # Slow camera movement affects the illustration only; typography remains fixed.
        # Decode/scale the still once, then generate its camera frames. Looping
        # the input with d=1 needlessly rescaled a large picture on every frame.
        frame_count = sum(durations) * FPS
        filters = (f"[0:v]scale=1080:1920,zoompan=z='min(1.045,1+on*0.000025)':"
                   f"x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d={frame_count}:s={WIDTH}x{HEIGHT}:fps={FPS}[bg];"
                   f'[1:v]fps={FPS}[titles];[bg][titles]overlay=0:0:format=auto,format=yuv420p[v]')
        run_ffmpeg(['-filter_complex_threads', '1', '-i', str(temp / 'background.png'),
                    '-f', 'concat', '-safe', '0', '-i', str(temp / 'overlays.ffconcat'),
                    '-i', str(audio_path), '-filter_complex', filters, '-map', '[v]', '-map', '2:a:0',
                    '-t', str(sum(durations)), '-r', str(FPS), '-c:v', 'libx264', '-preset', 'veryfast',
                    '-crf', '21', '-threads', '2', '-c:a', 'aac', '-b:a', '128k', '-ar', '44100',
                    '-movflags', '+faststart', str(target)])
    (output / f'episode-{number:02}.srt').write_text(subtitles(episode['scenes'], durations, music_only), encoding='utf-8')
    return {'number': number, 'title': episode['title'], 'durations': durations,
            'audio_levels': stats, **validate_video(target, sum(durations))}


def export_reading_edition(data, output):
    esc = html.escape
    chapters = []
    for ep in data['episodes']:
        paragraphs = ''.join(f'<p>{esc(p)}</p>' for p in ep['chapter'])
        chapters.append(f'<section id="episode-{ep["number"]}"><h2>{ep["number"]}화 · {esc(ep["title"])}</h2>{paragraphs}</section>')
    document = f'''<!doctype html><html lang="ko"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>{esc(data['title'])}</title><style>
body{{margin:0;background:#f8f3e9;color:#28372d;font-family:serif;line-height:2}}
main{{max-width:700px;margin:auto;padding:64px 24px}}h1{{font-size:2.4em;line-height:1.4}}
h2{{margin-top:3em}}p{{word-break:keep-all}}.meta{{font:14px sans-serif;color:#706c61}}a{{color:#365d48}}
@media print{{section{{break-before:page}}body{{background:white}}}}
</style><main><p class="meta">RECIPE SCOUT ORIGINAL STORY</p><h1>{esc(data['title'])}</h1>
<p>{esc(data['subtitle'])}</p><p class="meta">{esc(data['disclosure'])}<br>실제 이용자의 경험담이 아닌 허구입니다.</p>
{''.join(chapters)}<hr><p>{esc(data['cta'])}</p><p>레시피 스카우트에서 요리 영상을 검색하고 저장해 보세요.</p>
<p><a href="{esc(data['destination'], quote=True)}">레시피 스카우트 열기</a></p></main></html>'''
    (output / 'novel.html').write_text(document, encoding='utf-8')
    plain = [data['title'], data['subtitle'], data['disclosure'], '실제 이용자의 경험담이 아닌 허구입니다.']
    for ep in data['episodes']:
        plain.extend([f"\n{ep['number']}화 · {ep['title']}", *ep['chapter']])
    (output / 'novel.txt').write_text('\n\n'.join(plain), encoding='utf-8')


def build(source, voices, output, music_only=False):
    if music_only == (voices is not None):
        raise ValueError('choose_exactly_one_audio_mode')
    source, output = Path(source).resolve(), Path(output).resolve()
    voices = Path(voices).resolve() if voices is not None else None
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    data = load_series(source)
    if output.exists():
        raise ValueError('output_exists_choose_a_new_directory')
    data['audio_mode'] = 'music_only' if music_only else 'narrated_preview'
    if music_only:
        data['disclosure'] = '레시피 스카우트 홍보용 창작 이야기 · AI 삽화 · 창작 음악 · 내레이션 없음'
    else:
        # Validate every narration input before producing any deliverables.
        for ep in data['episodes']:
            for index in range(1, len(ep['scenes']) + 1):
                read_voice(voices / f'ep{ep["number"]:02}-scene{index:02}.wav')
    output.mkdir(parents=True)
    export_reading_edition(data, output)
    reports = []
    for ep in data['episodes']:
        reports.append(render_episode(data, ep, source.parent, voices, output, music_only))
        print(f"Episode {ep['number']} rendered and verified.", flush=True)
    concat = output / 'episodes.ffconcat'
    concat.write_text('ffconcat version 1.0\n' + '\n'.join(
        f"file 'episode-{ep['number']:02}.mp4'" for ep in data['episodes']), encoding='utf-8')
    run_ffmpeg(['-f', 'concat', '-safe', '0', '-i', str(concat), '-c', 'copy',
                '-movflags', '+faststart', str(output / 'complete-story.mp4')])
    combined = validate_video(output / 'complete-story.mp4', sum(sum(r['durations']) for r in reports))
    manifest = {'series_id': data['id'], 'title': data['title'], 'status': 'local_review_only',
                'upload_attempted': False, 'publishing_authorized': False,
                'source_sha256': source_hash,
                'disclosure': data['disclosure'], 'music': data['music'],
                'audio_mode': data['audio_mode'],
                'narration': 'none' if music_only else 'Local Windows Korean synthetic voice; preview, not a cloned human voice.',
                'episodes': reports, 'combined': combined}
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Completed local-review package: {output}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--series', type=Path, required=True)
    audio = parser.add_mutually_exclusive_group(required=True)
    audio.add_argument('--narration-dir', type=Path)
    audio.add_argument('--music-only', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.series, args.narration_dir, args.output, args.music_only)
