from pathlib import Path
import tempfile
import unittest
from PIL import Image
from story_studio_render import layer, render, validate, studio_font, demo_indices, background

ROOT = Path(__file__).resolve().parents[2]


def fixture(language='ko'):
    captions = {'ko': '오늘의 한 그릇, 다음 이야기의 시작.',
                'en': 'One shared meal. A new chapter begins.',
                'es': 'Una comida compartida. Comienza otra historia.'}
    return {'series': {'language': language}, 'recipe': {'settings': {'font_size': 40, 'scene_seconds': 10, 'music_gain': 1}},
            'episode': {'number': 4, 'draft': {'title': 'Recipe Scout', 'captions': [captions[language]] * 6}}}


class StudioRenderTests(unittest.TestCase):
    def test_demo_is_explicit_and_captures_are_contained(self):
        data = fixture()
        self.assertEqual(demo_indices(data), set())
        data['episode']['brief'] = '[APP_DEMO:bibimbap-v1]\nA new story.'
        self.assertEqual(demo_indices(data), {2, 3})
        for language in ('ko', 'en', 'es'):
            data['series']['language'] = language
            self.assertEqual(layer(data, 'Recipe Scout', is_demo=True).size, (720, 1280))
        for brief in ['[APP_DEMO:unknown]', 'prefix [APP_DEMO:bibimbap-v1]']:
            data['episode']['brief'] = brief
            with self.assertRaises(ValueError):
                demo_indices(data)
        capture = Image.new('RGB', (418, 215), 'white')
        canvas = background(capture, True)
        self.assertEqual(canvas.size, (720, 1280))
        self.assertEqual(canvas.getpixel((360, 575)), (255, 255, 255))
        self.assertNotEqual(canvas.getpixel((0, 0)), (255, 255, 255))

    def test_spanish_accents_have_real_glyphs(self):
        font = studio_font('es', 40)
        missing = bytes(font.getmask(chr(0x10ffff)))
        for character in 'áéíóúüñÁÉÍÓÚÜÑ¿¡':
            self.assertNotEqual(bytes(font.getmask(character)), missing, character)
        data = fixture('es')
        data['episode']['draft']['title'] = 'Un tazón, una historia'
        self.assertEqual(layer(data, '¿Qué aprendió? Cocinó, escuchó y sonrió.').size, (720, 1280))

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
            data = fixture('es')
            data['episode']['brief'] = '[APP_DEMO:bibimbap-v1]'
            images[2] = ROOT/'assets/story_demos/bibimbap-source.jpg'
            images[3] = ROOT/'assets/story_demos/bibimbap-draft.jpg'
            result = render(data, images, directory/'preview.mp4')
            self.assertTrue((directory/'preview.mp4').stat().st_size > 10000)
            self.assertIsInstance(result, dict)
            with self.assertRaises(ValueError):
                render(fixture(), images, directory/'preview.mp4')


if __name__ == '__main__':
    unittest.main()
