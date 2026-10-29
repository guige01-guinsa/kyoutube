"""Source-preserving recipe cards. Offline; no AI images or voice speed changes."""
from array import array
import json
from pathlib import Path
import sys
import tempfile
import wave
from PIL import Image, ImageDraw
from story_music import score
from story_series import WIDTH, HEIGHT, FPS, run_ffmpeg, validate_video, wrap, write_audio
from story_studio_render import studio_font
from story_studio_reedit import speech_seconds, encoding_options


def timing(voices):
    frames = []
    for index, path in enumerate(voices):
        seconds = speech_seconds(path)
        if seconds > (9.5 if index == 0 else 30):
            raise ValueError('voice_too_long')
        with wave.open(str(path), 'rb') as stream:
            samples = array('h', stream.readframes(stream.getframerate()*31))
        if sys.byteorder != 'little':
            samples.byteswap()
        if not samples or max(map(abs, samples)) < 100 or sum(abs(x) >= 32760 for x in samples)/len(samples) > .01:
            raise ValueError('voice_quality')
        import math
        frames.append(math.ceil((seconds+.4)*FPS))
    if not 150*FPS <= sum(frames) <= 180*FPS:
        raise ValueError('recipe_duration_review')
    return frames


def card(plan, index):
    canvas = Image.new('RGB', (WIDTH, HEIGHT), '#251f2b')
    draw = ImageDraw.Draw(canvas)
    small, heading, body = [studio_font('ko', size) for size in (20, 30, 30)]
    draw.text((40, 30), 'RECIPE SCOUT · 원본 영상 레시피', font=small, fill='#efd3a0')
    y = 90
    for line in wrap(draw, plan['title'], heading, 640):
        draw.text((40, y), line, font=heading, fill='#fff7e9'); y += 42
    y = max(210, y+30)
    scene = plan['scenes'][index]
    # Ingredient quantities are never converted, rounded, invented or shortened.
    for paragraph in scene['caption'].split(' / '):
        for line in wrap(draw, paragraph, body, 640):
            if y > 1110:
                raise ValueError('recipe_layout_review')
            draw.text((40, y), line, font=body, fill='#fff7e9'); y += 43
        y += 18
    draw.text((40, 1190), f"{index+1} / {len(plan['scenes'])} · AI 음성 · 검토용", font=small, fill='#dfd7c8')
    return canvas


def render_recipe(plan, voices, output):
    if plan.get('profile') != 'ko-180-source-v1' or plan.get('language') != 'ko':
        raise ValueError('recipe_profile')
    if not 4 <= len(plan['scenes']) == len(voices) <= 20 or Path(output).exists():
        raise ValueError('recipe_inputs')
    cards = [card(plan, i) for i in range(len(voices))]
    frames = timing(voices)
    seconds = sum(frames)/FPS
    with tempfile.TemporaryDirectory(prefix='recipe-render-') as directory:
        root = Path(directory)
        entries = []
        for i, (picture, count) in enumerate(zip(cards, frames)):
            picture.save(root/f'card-{i}.png')
            entries += [f"file 'card-{i}.png'", f'duration {count/FPS:.9f}']
        entries += [f"file 'card-{len(cards)-1}.png'"]
        (root/'cards.txt').write_text('\n'.join(entries), encoding='utf-8')
        write_audio((x*.25 for x in score(seconds, 2)), root/'music.wav')
        inputs = ['-f', 'concat', '-safe', '0', '-i', str(root/'cards.txt')]
        filters = []
        for i, path in enumerate(voices):
            inputs += ['-i', str(path)]
            filters += [f'[{i+1}:a]aresample=44100,aformat=channel_layouts=mono,'
                        'loudnorm=I=-18:TP=-2:LRA=7,aresample=44100,'
                        f'adelay=150,apad,atrim=duration={frames[i]/FPS:.9f},asetpts=PTS-STARTPTS[a{i}]']
        inputs += ['-i', str(root/'music.wav')]
        filters += [''.join(f'[a{i}]' for i in range(len(voices)))+f'concat=n={len(voices)}:v=0:a=1[voice]',
                    f'[voice][{len(voices)+1}:a]amix=inputs=2:duration=first:normalize=0,'
                    'alimiter=limit=0.95:level=false:latency=true[audio]']
        run_ffmpeg(['-filter_complex_threads','1',*inputs,'-filter_complex',';'.join(filters),
                    '-map','0:v','-map','[audio]','-t',f'{seconds:.9f}','-r',str(FPS),
                    '-pix_fmt','yuv420p',*encoding_options(seconds),'-movflags','+faststart',str(output)])
    result = validate_video(Path(output), seconds)
    if Path(output).stat().st_size > 45000000:
        raise ValueError('recipe_video_size')
    return {'video':result,'human_listening_review_required':True,'scene_frames':frames}


if __name__ == '__main__':
    try:
        root = Path(sys.argv[1]); plan = json.loads((root/'plan.json').read_text(encoding='utf-8'))
        result = render_recipe(plan,[root/f'ko-{i}.wav' for i in range(len(plan['scenes']))],root/'ko.mp4')
        (root/'quality.json').write_text(json.dumps(result),encoding='utf-8')
    except Exception:
        print('Source recipe render requires review; no automatic retry.',file=sys.stderr)
        sys.exit(1)
