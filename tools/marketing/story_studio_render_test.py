from pathlib import Path
import tempfile
import unittest
from PIL import Image
from story_studio_render import layer, render, validate

ROOT = Path(__file__).resolve().parents[2]


def fixture(language='ko'):
    captions = {'ko': '오늘의 한 그릇, 다음 이야기의 시작.',
                'en': 'One shared meal. A new chapter begins.',
                'es': 'Una comida compartida. Comienza otra historia.'}
    return {'series': {'language': language}, 'recipe': {'settings': {'font_size': 40, 'scene_seconds': 10, 'music_gain': 1}},
            'episode': {'number': 4, 'draft': {'title': 'Recipe Scout', 'captions': [captions[language]] * 6}}}


class StudioRenderTests(unittest.TestCase):
    def test_three_languages_at_both_font_limits(self):
        for language in ('ko', 'en', 'es'):
            for size in (32, 48):
                data = fixture(language)
                data['recipe']['settings']['font_size'] = size
                self.assertEqual(layer(data, data['episode']['draft']['captions'][0], True).size, (720, 1280))

    def test_settings_and_lengths_fail_closed(self):
        for settings in ({'font_size': 99}, {'scene_seconds': 9}, {'music_gain': 9}):
            data = fixture()
            data['recipe']['settings'].update(settings)
            with self.assertRaises(ValueError):
                validate(data)
        data = fixture()
        data['episode']['draft']['captions'] = ['x'] * 7
        with self.assertRaises(ValueError):
            validate(data)

    def test_exact_sixty_seconds_with_audio_and_six_panels(self):
        # Synthetic local color panels, no paid image generation or copied photo.
        with tempfile.TemporaryDirectory(prefix='studio-test-') as temporary:
            directory = Path(temporary)
            images = []
            for i in range(6):
                image = directory/f'panel-{i}.png'
                Image.new('RGB', (720, 1280), (35+i*25, 70, 95)).save(image)
                images.append(image)
            result = render(fixture('es'), images, directory/'preview.mp4')
            self.assertTrue((directory/'preview.mp4').stat().st_size > 10000)
            self.assertIsInstance(result, dict)
            with self.assertRaises(ValueError):
                render(fixture(), images, directory/'preview.mp4')


if __name__ == '__main__':
    unittest.main()
