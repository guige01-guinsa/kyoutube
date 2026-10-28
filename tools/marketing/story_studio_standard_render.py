"""Offline Korean 60-second pilot assembler; no API calls or uploads.

Requires six approved PNGs and six supplied PCM16 WAVs. A long voice is rejected,
never cut or accelerated. The app-demo panel must be an approved real capture.
"""
from array import array
import json
from pathlib import Path
import sys
import tempfile
import wave

from PIL import Image, ImageDraw
from story_music import score
from story_series import WIDTH, HEIGHT, FPS, run_ffmpeg, validate_video, wrap, write_audio
from story_studio_render import background, studio_font
from story_studio_reedit import speech_seconds, encoding_options


def validate_plan(plan):
    if plan.get('profile') != 'ko-60-v1' or plan.get('language') != 'ko':
        raise ValueError('korean_pilot_required')
    title = plan.get('title')
    if not isinstance(title, str) or not title.strip() or len(title) > 45:
        raise ValueError('invalid_title')
    scenes = plan.get('scenes')
    roles = ['greeting', 'food_fact', 'ingredients', 'cooking', 'app_demo', 'closing']
    if not isinstance(scenes, list) or len(scenes) != 6:
        raise ValueError('six_scenes_required')
    for role, scene in zip(roles, scenes):
        if scene.get('role') != role:
            raise ValueError('invalid_scene_order')
        for key, limit in [('spoken', 50), ('caption', 60)]:
            value = scene.get(key)
            if not isinstance(value, str) or not value.strip() or len(value) > limit:
                raise ValueError('invalid_scene_text')
    return scenes


def voice_qa(path):
    seconds = speech_seconds(path)
    if seconds > 9.5:
        raise ValueError('shorten_script_no_truncation')
    with wave.open(str(path), 'rb') as source:
        samples = array('h', source.readframes(source.getframerate() * 10))
    if sys.byteorder != 'little':
        samples.byteswap()
    if not samples or max(map(abs, samples)) < 100:
        raise ValueError('silent_voice')
    if sum(abs(v) >= 32760 for v in samples) / len(samples) > .01:
        raise ValueError('clipped_voice')
    return seconds


def card(plan, index, original):
    canvas = background(original, index == 4)
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 0, WIDTH, 260), fill='#251f2b')
    draw.rectangle((0, 840, WIDTH, HEIGHT), fill='#251f2b')
    small, heading, body = [studio_font('ko', size) for size in (21, 32, 40)]
    draw.text((44, 38), 'RECIPE SCOUT / 한식 1분', font=small, fill='#efd3a0')
    for content, font, y, limit, step in [
            (plan['title'], heading, 95, 3, 44),
            (plan['scenes'][index]['caption'], body, 875, 4, 54)]:
        lines = wrap(draw, content, font, 630)
        if len(lines) > limit:
            raise ValueError('text_overflow')
        for n, line in enumerate(lines):
            draw.text((44, y+n*step), line, font=font, fill='#fff7e9')
    if index == 4:
        draw.text((44, 285), '실제 앱 화면 · 한국어', font=small, fill='#efd3a0')
    draw.text((44, 1160), 'AI 음성 · 창작 삽화 · 창작 음악', font=small, fill='#dfd7c8')
    draw.text((44, 1205), f'{index+1} / 6 · 검토용', font=small, fill='#dfd7c8')
    return canvas


def render_standard(plan, images, voices, output):
    validate_plan(plan)
    output = Path(output)
    if output.exists():
        raise ValueError('output_already_exists')
    if len(images) != 6 or len(voices) != 6:
        raise ValueError('six_assets_required')
    # Complete audio/layout preflight before starting any encoding.
    durations = [voice_qa(path) for path in voices]
    cards = []
    for index, path in enumerate(images):
        with Image.open(path) as original:
            if original.width * original.height > 20_000_000:
                raise ValueError('image_too_large')
            cards.append(card(plan, index, original))
    with tempfile.TemporaryDirectory(prefix='story-standard-') as temporary:
        temp = Path(temporary)
        for index, image in enumerate(cards):
            image.save(temp/f'card-{index}.png')
        write_audio((value * .25 for value in score(60, 2)), temp/'music.wav')
        inputs = ['-framerate', '1/10', '-i', str(temp/'card-%d.png')]
        filters = []
        for index, path in enumerate(voices):
            inputs += ['-i', str(path)]
            filters.append(f'[{index+1}:a]aresample=44100,aformat=channel_layouts=mono,'
                           'loudnorm=I=-18:TP=-2:LRA=7,aresample=44100,'
                           f'adelay=250,apad,atrim=duration=10,asetpts=PTS-STARTPTS[a{index}]')
        inputs += ['-i', str(temp/'music.wav')]
        filters += [''.join(f'[a{i}]' for i in range(6))+'concat=n=6:v=0:a=1[voice]',
                    '[voice][7:a]amix=inputs=2:duration=first:normalize=0,'
                    'alimiter=limit=0.95:level=false:latency=true[audio]']
        run_ffmpeg(['-filter_complex_threads', '1', *inputs, '-filter_complex', ';'.join(filters),
                    '-map', '0:v', '-map', '[audio]', '-t', '60', '-r', str(FPS),
                    '-pix_fmt', 'yuv420p', *encoding_options(60), '-movflags', '+faststart', str(output)])
    measured = validate_video(output, 60)
    if not 59.9 <= measured['seconds'] <= 60:
        raise ValueError('video_duration_exceeds_profile')
    if output.stat().st_size > 45_000_000:
        raise ValueError('video_too_large')
    return {'video': measured, 'voice_seconds': durations, 'language': 'ko',
            'human_listening_review_required': True}


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('directory_required')
        directory = Path(sys.argv[1])
        source = directory/'plan.json'
        if source.stat().st_size > 50_000:
            raise ValueError('plan_too_large')
        plan = json.loads(source.read_text(encoding='utf-8'))
        result = render_standard(plan, [directory/f'panel-{i}.png' for i in range(6)],
                                 [directory/f'ko-{i}.wav' for i in range(6)], directory/'ko.mp4')
        (directory/'quality.json').write_text(json.dumps(result), encoding='utf-8')
        print('Korean 60-second review video assembled. Human listening review required.')
    except Exception:
        print('Standard renderer stopped; inspect inputs. No automatic retry.', file=sys.stderr)
        sys.exit(1)
