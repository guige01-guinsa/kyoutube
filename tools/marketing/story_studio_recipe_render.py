"""Source-preserving sketch recipe cards. Offline, with unchanged audio speed."""
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
from story_studio_recipe_sketch import sketch, BOX, ink_fraction, verify_encoded_sketches


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
    if not 0 < sum(frames) <= 180*FPS:
        raise ValueError('recipe_duration_review')
    return frames


def card(plan, index):
    canvas = Image.new('RGB', (WIDTH, HEIGHT), '#f5eedf')
    draw = ImageDraw.Draw(canvas)
    small, heading = [studio_font('ko', size) for size in (20, 30)]
    draw.text((40, 30), 'RECIPE SCOUT · 원본 영상 레시피', font=small, fill='#72543c')
    y = 90
    for line in wrap(draw, plan['title'], heading, 640):
        draw.text((40, y), line, font=heading, fill='#352a32'); y += 42
    if y > 222: raise ValueError('recipe_layout_review')
    scene = plan['scenes'][index]
    picture = sketch(plan, index)
    if not .003 <= ink_fraction(picture) <= .4: raise ValueError('recipe_sketch_missing')
    canvas.paste(picture, BOX[:2])
    draw.rounded_rectangle(BOX, radius=18, outline='#d3c4ad', width=2)
    # Ingredient quantities are never converted, rounded, invented or shortened.
    for size in (30, 28, 26, 24):
        body = studio_font('ko', size)
        paragraphs = [wrap(draw, p, body, 640) for p in scene['caption'].split(' / ')]
        if sum(len(p)*(size+11)+12 for p in paragraphs) <= 445: break
    else: raise ValueError('recipe_layout_review')
    y = 685
    for paragraph in paragraphs:
        for line in paragraph:
            draw.text((40, y), line, font=body, fill='#352a32'); y += size+11
        y += 12
    draw.text((40, 1190), f"{index+1} / {len(plan['scenes'])} · AI 음성 · 조리 개념 스케치", font=small, fill='#72543c')
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
                    # Image concat timestamps can end before fractional narration
                    # boundaries. Generate the exact planned frame count; extend
                    # only the final still within the existing audio timeline.
                    '-vf',f'fps={FPS},tpad=stop_mode=clone:stop_duration={seconds:.9f}',
                    '-frames:v',str(sum(frames)),
                    '-pix_fmt','yuv420p',*encoding_options(seconds),'-movflags','+faststart',str(output)])
    result = validate_video(Path(output), seconds)
    visuals = verify_encoded_sketches(Path(output), frames)
    if Path(output).stat().st_size > 45000000:
        raise ValueError('recipe_video_size')
    return {'video':result,'visuals':visuals,'human_listening_review_required':True,'scene_frames':frames}


if __name__ == '__main__':
    try:
        root = Path(sys.argv[1]); plan = json.loads((root/'plan.json').read_text(encoding='utf-8'))
        result = render_recipe(plan,[root/f'ko-{i}.wav' for i in range(len(plan['scenes']))],root/'ko.mp4')
        (root/'quality.json').write_text(json.dumps(result),encoding='utf-8')
    except Exception:
        print('Source recipe render requires review; no automatic retry.',file=sys.stderr)
        sys.exit(1)
