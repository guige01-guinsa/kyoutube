from pathlib import Path
import tempfile
import unittest
from story_studio_standard_render_test import tone
from story_studio_recipe_render import timing, card, render_recipe


class RecipeTests(unittest.TestCase):
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
