from pathlib import Path
import tempfile
import unittest
import wave
import subprocess
import sys

from PIL import Image
from story_series import run_ffmpeg
from story_studio_reedit import layout, offset, chrome, speech_seconds, render_edition, validate_plan


class ReeditTests(unittest.TestCase):
    def test_scroll_moves_only_up_and_does_not_drop_lines(self):
        for language, text in [('ko', '비빔밥의 종류와 상세 조리법. '*35),
                               ('en', 'A bowl with carefully cooked vegetables. '*10),
                               ('es', '¿Cómo se cocina? Añade arroz y piña. '*12)]:
            strip, travel, lines = layout(text, language)
            self.assertGreater(lines, 4)
            self.assertEqual(strip.height, 400+travel)
            self.assertEqual(offset(travel,60,0),0)
            self.assertLess(offset(travel,60,10),offset(travel,60,50))
            self.assertEqual(offset(travel,60,61),travel)
            self.assertEqual(chrome('Bibimbap',language,1,10).size,(720,1280))

    def test_masks_cover_old_text_but_leave_illustration(self):
        layer=chrome('비빔밥','ko',1,3)
        for point in [(10,55),(50,285),(50,880),(50,1180)]:
            self.assertEqual(layer.getpixel(point)[3],255)
        self.assertEqual(layer.getpixel((360,550))[3],0)

    def test_invalid_input_fails_closed(self):
        for text in ['', 'x'*601]:
            with self.assertRaises(ValueError):layout(text,'ko')
        with self.assertRaises(ValueError):layout('hello','fr')

    def test_only_korean_plan_is_accepted(self):
        with tempfile.TemporaryDirectory(prefix='reedit-plan-test-') as temporary:
            root=Path(temporary)
            for i in range(3):
                with wave.open(str(root/f'ko-{i:02}.wav'),'wb') as wav:
                    wav.setparams((1,2,24000,0,'NONE','not compressed'))
                    wav.writeframes(b'\x01\x00'*240000)
            edition={'title':'비빔밥','chunks':['첫 문단.','둘째 문단.','마지막 문단.']}
            self.assertEqual(validate_plan({'ko':edition},root),{'ko':[11,11,11]})
            for plan in [{},{'en':edition},{'ko':edition,'en':edition,'es':edition}]:
                with self.assertRaisesRegex(ValueError,'korean_only_required'):
                    validate_plan(plan,root)

    def test_streamed_wav_uses_actual_samples_not_unknown_header_length(self):
        with tempfile.TemporaryDirectory(prefix='reedit-wave-test-') as temporary:
            target=Path(temporary)/'voice.wav'
            with wave.open(str(target),'wb') as wav:
                wav.setparams((1,2,24000,0,'NONE','not compressed'))
                wav.writeframes(b'\x01\x00'*48000)
            data=bytearray(target.read_bytes())
            self.assertEqual(data[36:40],b'data')
            data[4:8]=b'\xff'*4
            data[40:44]=b'\xff'*4
            target.write_bytes(data)
            self.assertEqual(speech_seconds(target),2)

    def test_actual_short_render_has_video_audio_and_exact_length(self):
        with tempfile.TemporaryDirectory(prefix='reedit-test-') as temporary:
            root=Path(temporary)
            # Synthetic fixture only, not customer media or paid speech.
            run_ffmpeg(['-f','lavfi','-i','color=c=0x596f62:s=720x1280:r=24',
                        '-f','lavfi','-i','sine=frequency=220:sample_rate=44100',
                        '-t','60','-c:v','libx264','-preset','ultrafast','-threads','2',
                        '-pix_fmt','yuv420p','-c:a','aac',str(root/'source.mp4')])
            # Exercise the actual subprocess entry point used before paid speech.
            command=[sys.executable,str(Path(__file__).with_name('story_studio_reedit.py')),
                     '--validate-source']
            checked=subprocess.run(command+[str(root/'source.mp4')],capture_output=True,timeout=120)
            self.assertEqual(checked.returncode,0,checked.stderr)
            rejected=subprocess.run(command+[str(root/'missing.mp4')],capture_output=True,timeout=120)
            self.assertNotEqual(rejected.returncode,0)
            for i in range(2):
                with wave.open(str(root/f'ko-{i:02}.wav'),'wb') as wav:
                    wav.setparams((1,2,24000,0,'NONE','not compressed'))
                    wav.writeframes(b'\x01\x00'*48000)
            self.assertEqual(speech_seconds(root/'ko-00.wav'),2)
            result=render_edition(root/'source.mp4',{'title':'비빔밥','chunks':['첫 설명입니다.','마지막 설명입니다.']},
                                  'ko',root,root/'result.mp4',[3,3])
            self.assertTrue(result['audio'])
            self.assertEqual(result['frames'],144)
            with self.assertRaises(ValueError):
                render_edition(root/'source.mp4',{},'ko',root,root/'result.mp4',[])


if __name__=='__main__':unittest.main()
