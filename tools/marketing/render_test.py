import json
from pathlib import Path
import subprocess
import tempfile
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
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'quiet', '-print_format', 'json',
                                               '-show_streams', '-show_format', str(output)]))
    video = next(s for s in info['streams'] if s['codec_type'] == 'video')
    assert (video['width'], video['height']) == (720, 1280)
    assert video['pix_fmt'] == 'yuv420p'
    assert 23.9 <= float(info['format']['duration']) <= 24.1
    assert output.stat().st_size > 1000
    print('Render passed: 720×1280, H.264, 24 seconds.')
