"""Synthetic, offline tests. The audio is a tone, NOT a voice-quality preview."""
from array import array
import math
from pathlib import Path
import tempfile
import unittest
import wave

from PIL import Image
from story_studio_standard_render import card, render_standard, validate_plan, voice_qa


def fixture():
    return {'profile': 'ko-60-v1', 'language': 'ko', 'title': '합성 검사 영상 · 실제 제작본 아님',
            'scenes': [{'role': role, 'spoken': '합성 시험용 문장입니다.',
                        'caption': '검사용 도형과 시험음 · 실제 앱 화면 아님'} for role in
                       ['greeting', 'food_fact', 'ingredients', 'cooking', 'app_demo', 'closing']]}


def tone(path, seconds=2, amplitude=2000):
    samples = array('h', (round(amplitude*math.sin(2*math.pi*440*n/24000))
                         for n in range(round(seconds*24000))))
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(24000)
        output.writeframes(samples.tobytes())


class StandardTests(unittest.TestCase):
    def test_profile(self):
        for key, value in [('language', 'es'), ('profile', 'ko-300-v1'), ('scenes', [])]:
            plan = fixture()
            plan[key] = value
            with self.assertRaises(ValueError):
                validate_plan(plan)

    def test_text_is_not_truncated(self):
        plan = fixture()
        plan['scenes'][0]['spoken'] = '가'*51
        with self.assertRaises(ValueError):
            validate_plan(plan)

    def test_korean_layout(self):
        for index in range(6):
            result = card(fixture(), index, Image.new('RGB', (360, 640), '#9c7960'))
            self.assertEqual(result.size, (720, 1280))

    def test_long_and_silent_voice_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'voice.wav'
            tone(path, 9.6)
            with self.assertRaisesRegex(ValueError, 'shorten_script'):
                voice_qa(path)
            tone(path, 2, 0)
            with self.assertRaisesRegex(ValueError, 'silent_voice'):
                voice_qa(path)

    def test_full_minute_has_audio_and_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            images, voices = [], []
            for index in range(6):
                image, voice = root/f'panel-{index}.png', root/f'ko-{index}.wav'
                Image.new('RGB', (360, 640), (70+index*20, 90, 80)).save(image)
                tone(voice)
                images.append(image)
                voices.append(voice)
            result = render_standard(fixture(), images, voices, root/'ko.mp4')
            self.assertTrue(result['human_listening_review_required'])
            self.assertEqual(result['voice_seconds'], [2]*6)
            with self.assertRaisesRegex(ValueError, 'output_already_exists'):
                render_standard(fixture(), images, voices, root/'ko.mp4')


if __name__ == '__main__':
    unittest.main()
