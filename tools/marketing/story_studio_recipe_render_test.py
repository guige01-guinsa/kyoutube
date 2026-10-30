from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
from story_studio_standard_render_test import tone
from story_studio_recipe_render import timing, card, render_recipe
from story_studio_recipe_sketch import sketch, ink_fraction, BOX
from story_studio_recipe_sketch import verify_encoded_sketches
from story_series import run_ffmpeg


class RecipeTests(unittest.TestCase):
    def test_encoded_text_only_or_black_video_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for color in ('white','black'):
                Image.new('RGB',(720,1280),color).save(root/'blank.png')
                path=root/f'{color}.mp4'
                run_ffmpeg(['-loop','1','-i',str(root/'blank.png'),'-t','1','-r','24',
                            '-pix_fmt','yuv420p','-c:v','libx264','-preset','ultrafast',str(path)])
                with self.assertRaisesRegex(ValueError,'recipe_sketch_missing'):
                    verify_encoded_sketches(path,[24])

    def test_source_sketches_are_visible_and_scene_specific_without_network(self):
        plan={'food':'김치찌개','title':'김치찌개', 'recipe':{'ingredients':['김치', '두부', '대파']},
              'scenes':[{'role':'ingredients','caption':'신김치 1컵(150g) / 두부 / 대파'},
                        {'role':'cooking','caption':'양파와 대파를 썰어주세요.'},
                        {'role':'cooking','caption':'김치와 물을 넣고 끓여주세요.'}]}
        drawings=[sketch(plan, i) for i in range(3)]
        self.assertEqual(len({picture.tobytes() for picture in drawings}),3)
        for i, picture in enumerate(drawings):
            self.assertGreater(ink_fraction(picture),.003)
            self.assertLess(ink_fraction(picture),.4)
            self.assertGreater(ink_fraction(card(plan,i).crop(BOX)),.003)
        with patch('story_studio_recipe_render.sketch',return_value=Image.new('RGB',(640,430),'white')):
            with self.assertRaisesRegex(ValueError,'recipe_sketch_missing'): card(plan,0)
        meals=[]
        for food in ('김치찌개', '불고기', '비빔밥'):
            other={**plan,'food':food,'scenes':[{'role':'greeting','caption':'원본 레시피'}]}
            meals.append(sketch(other,0).tobytes())
        self.assertEqual(len(set(meals)),3)

    def test_fractional_scene_lengths_render_the_entire_narration_timeline(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            durations = [5.1, 11.2, 4.55, 5.7, 1.1, 5.6, 4.75,
                         6.95, 6.25, 4.95, 9.8, 7.4, 7.05, 9.95]
            voices = []
            for i, seconds in enumerate(durations):
                path = root/f'{i}.wav'; tone(path, seconds); voices.append(path)
            plan = {'profile':'ko-180-source-v1', 'language':'ko',
                    'title':'합성 검사 · 소수점 길이',
                    'scenes':[{'caption':'검사 재료 200g / 원문 계량 유지'} for _ in voices]}
            result = render_recipe(plan, voices, root/'fractional.mp4')
            self.assertEqual(result['video']['frames'], 2308)
            self.assertAlmostEqual(result['video']['seconds'], 2308/24, delta=.1)
            self.assertTrue(result['video']['audio'])
            self.assertEqual(result['visuals']['verified_frames'],len(voices))
            self.assertGreater(result['visuals']['min_ink_fraction'],.003)

    def test_short_recipe_keeps_actual_voice_length(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'voice.wav'; tone(p,1)
            frames=timing([p]*14)
            self.assertLess(sum(frames)/24,150)
            self.assertGreater(sum(frames)/24,0)
            self.assertLess(sum(frames)/24,30)
            self.assertAlmostEqual(sum(frames)/24,14*1.4166666667)

    def test_complete_three_minutes_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            voices = []
            for i in range(17):
                path = root/f'{i}.wav'; tone(path, 7.6 if i == 0 else 10.35); voices.append(path)
            plan = {'profile':'ko-180-source-v1','language':'ko','title':'합성 검사 · 원본 레시피',
                    'scenes':[{'caption':'검사 재료 200g / 간장 2큰술(20g) / 후추 약간'} for _ in voices]}
            self.assertEqual(sum(timing(voices)),4320)
            result = render_recipe(plan,voices,root/'ko.mp4')
            self.assertEqual(result['video']['seconds'],180)
            self.assertEqual(result['video']['frames'],4320)
            self.assertTrue(result['video']['audio'])
            with self.assertRaises(ValueError): render_recipe(plan,voices,root/'ko.mp4')

    def test_overflow_fails_instead_of_dropping_source(self):
        plan={'title':'검사','scenes':[{'caption':'재료 '*1500}]}
        with self.assertRaisesRegex(ValueError,'recipe_layout_review'): card(plan,0)

    def test_duration_limit_does_not_truncate_or_speed_voice(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'voice.wav'; tone(p,9.6)
            with self.assertRaisesRegex(ValueError,'voice_too_long'): timing([p]*20)


if __name__=='__main__': unittest.main()
