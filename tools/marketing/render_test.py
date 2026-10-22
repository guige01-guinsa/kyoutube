import json
from pathlib import Path
import tempfile
import imageio_ffmpeg
from render import render

with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / 'source.json'
    output = Path(directory) / 'video.mp4'
    source.write_text(json.dumps({'scenes': [
        '오늘 저녁 메뉴가 고민되시나요?',
        '3분 이내 요리 영상을 찾아 저장해 보세요.',
        '채널 프로필의 링크에서 Recipe Scout 확인',
    ]}), encoding='utf-8')
    render(source, output)
    frames = imageio_ffmpeg.read_frames(str(output))
    try:
        video = next(frames)
    finally:
        frames.close()
    assert video['source_size'] == (720, 1280)
    assert video['codec'] == 'h264'
    assert video['pix_fmt'].split('(')[0] == 'yuv420p'
    assert video['fps'] == 24
    assert 23.9 <= video['duration'] <= 24.1
    frame_count, seconds = imageio_ffmpeg.count_frames_and_secs(str(output))
    assert frame_count == 576
    assert 23.9 <= seconds <= 24.1
    assert output.stat().st_size > 1000
    print('Render passed: 720×1280, H.264, 24 seconds.')
