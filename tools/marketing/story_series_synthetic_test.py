import copy
from array import array
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import wave

from PIL import Image, ImageDraw, ImageFont
from story_music import RATE, score
from story_series import (asset, export_reading_edition, load_series, mix_audio,
                          overlay, read_voice, scene_seconds, stamp, subtitles, build, wrap, FONT,
                          caption_seconds, music_audio, write_audio)

# Public CI uses synthetic data only; private manuscripts/images are not needed.
FIXTURE = None
SOURCE = None


def setUpModule():
    global FIXTURE, SOURCE
    FIXTURE = tempfile.TemporaryDirectory(prefix='story-synthetic-tests-')
    root = Path(FIXTURE.name)
    SOURCE = root/'series.json'
    data = {
        'schema_version': 1, 'id': 'synthetic-check', 'title': '검사 이야기',
        'subtitle': '공개 검사 자료', 'disclosure': '검사용 허구', 'cta': '앱에서 확인',
        'destination': 'https://recipe-scout-workspace.web.app/',
        'music': {'kind': 'original_synthesis'},
        'bible': {'premise': '검사', 'characters': ['가상 인물'],
                  'timeline': '순서 유지', 'invariants': ['검사만 수행']},
        'episodes': [
            {'number': i, 'title': f'검사 {i}', 'ending': '다음 검사',
             'recap': '앞선 검사', 'image': f'episode-{i:02}.png',
             'chapter': ['독립적으로 만든 검사용 문장입니다.']*8,
             'scenes': [{'caption': '검사용 자막', 'narration': '검사용 낭독'}]*3}
            for i in range(1, 4)]}
    for episode in data['episodes']:
        Image.new('RGB', (16, 16), '#566c62').save(root/episode['image'])
    SOURCE.write_text(json.dumps(data), encoding='utf-8')


def tearDownModule():
    FIXTURE.cleanup()


class StoryTests(unittest.TestCase):
    def setUp(self):
        self.data = load_series(SOURCE)

    def load_variant(self, change):
        data = copy.deepcopy(self.data)
        change(data)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for ep in data['episodes']:
                Image.new('RGB', (16, 16)).save(root / f"episode-{ep['number']:02}.png")
            source = root / 'series.json'
            source.write_text(json.dumps(data), encoding='utf-8')
            return load_series(source)

    def test_three_episodes_have_novel_and_continuity(self):
        self.assertEqual(len(self.data['episodes']), 3)
        self.assertEqual([e['number'] for e in self.data['episodes']], [1, 2, 3])
        self.assertTrue(all(len(e['chapter']) >= 8 for e in self.data['episodes']))
        self.assertEqual(self.data['music']['kind'], 'original_synthesis')

    def test_episode_gap_rejected(self):
        with self.assertRaises(ValueError):
            self.load_variant(lambda d: d['episodes'][1].update(number=4))

    def test_unknown_music_rejected(self):
        with self.assertRaises(ValueError):
            self.load_variant(lambda d: d['music'].update(kind='youtube_download'))

    def test_empty_continuity_rejected(self):
        with self.assertRaises(ValueError):
            self.load_variant(lambda d: d.update(bible={}))

    def test_foreign_destination_rejected(self):
        with self.assertRaises(ValueError):
            self.load_variant(lambda d: d.update(destination='https://example.com'))

    def test_asset_cannot_traverse_or_use_url(self):
        for name in ('../secret.png', 'https://example.com/a.png', '/tmp/a.png', r'C:\a.png'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                asset(SOURCE.parent, name)

    def test_all_captions_fit(self):
        for ep in self.data['episodes']:
            for index, scene in enumerate(ep['scenes']):
                image = overlay(self.data, ep, scene['caption'], index == len(ep['scenes']) - 1)
                self.assertEqual(image.size, (720, 1280))
                self.assertEqual(image.mode, 'RGBA')

    def test_overflow_rejected(self):
        with self.assertRaises(ValueError):
            overlay(self.data, self.data['episodes'][0], '가\n' * 10)

    def test_title_overflow_rejected(self):
        data = copy.deepcopy(self.data)
        data['title'] = '긴 제목' * 30
        with self.assertRaisesRegex(ValueError, 'title_overflow'):
            overlay(data, data['episodes'][0], '짧은 자막')

    def test_korean_wrap_preserves_words(self):
        draw = ImageDraw.Draw(Image.new('RGB', (720, 1280)))
        font = ImageFont.truetype(str(FONT), 40)
        lines = wrap(draw, '요리사는 오늘도 작은 문을 열기로 했다.', font, 560)
        self.assertEqual(' '.join(lines), '요리사는 오늘도 작은 문을 열기로 했다.')
        self.assertNotEqual(lines[-1], '다.')
        self.assertTrue(all(draw.textlength(line, font=font) <= 560 for line in lines))

    def test_long_unbroken_word_still_fits(self):
        draw = ImageDraw.Draw(Image.new('RGB', (720, 1280)))
        font = ImageFont.truetype(str(FONT), 40)
        lines = wrap(draw, '가' * 50, font, 560)
        self.assertEqual(''.join(lines), '가' * 50)
        self.assertTrue(all(draw.textlength(line, font=font) <= 560 for line in lines))

    def test_existing_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = root / 'keep.txt'
            marker.write_text('preserve', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'output_exists'):
                build(SOURCE, root / 'missing-voices', root)
            self.assertEqual(marker.read_text(encoding='utf-8'), 'preserve')

    def test_score_deterministic_non_silent_with_fades(self):
        first = score(3)
        self.assertEqual(first, score(3))
        self.assertEqual(len(first), RATE * 3)
        self.assertGreater(max(map(abs, first)), .01)
        self.assertLessEqual(max(map(abs, first)), .131)
        self.assertEqual(first[0], 0)
        self.assertLess(abs(first[-1]), .001)

    def test_bounded_score(self):
        for seconds in (0, -1, 241):
            with self.assertRaises(ValueError):
                score(seconds)

    def test_voice_format_and_silence_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            wav = Path(directory) / 'voice.wav'
            with wave.open(str(wav), 'wb') as f:
                f.setparams((1, 2, RATE, RATE, 'NONE', 'not compressed'))
                f.writeframes(b'\0\0' * RATE)
            with self.assertRaisesRegex(ValueError, 'silent'):
                read_voice(wav)
            with wave.open(str(wav), 'wb') as f:
                f.setparams((2, 2, RATE, RATE, 'NONE', 'not compressed'))
                f.writeframes(b'\0\0\0\0' * RATE)
            with self.assertRaisesRegex(ValueError, 'mono'):
                read_voice(wav)

    def test_voice_timing_and_mix_cannot_truncate(self):
        voice = array('f', [.1]) * (RATE * 7)
        self.assertEqual(scene_seconds(voice), 9)
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'mix.wav'
            with self.assertRaises(ValueError):
                mix_audio([voice], [6], 1, target)
            stats = mix_audio([voice], [9], 1, target)
            self.assertLess(stats['peak'], .98)
            self.assertGreater(stats['rms'], 0)
            with wave.open(str(target), 'rb') as wav:
                self.assertEqual(wav.getnframes(), RATE * 9)

    def test_subtitles_follow_exact_scene_boundaries(self):
        result = subtitles([{'narration': '첫 장면'}, {'narration': '다음 장면'}], [6, 7])
        self.assertIn('00:00:00,000 --> 00:00:06,000', result)
        self.assertIn('00:00:06,000 --> 00:00:13,000', result)
        self.assertEqual(stamp(3661.125), '01:01:01,125')

    def test_music_only_subtitles_use_visible_captions(self):
        result = subtitles([{'caption': '보이는 자막', 'narration': '읽지 않는 음성'}], [7], True)
        self.assertIn('보이는 자막', result)
        self.assertNotIn('읽지 않는 음성', result)

    def test_caption_reading_time(self):
        self.assertEqual(caption_seconds('짧은 자막'), 7)
        self.assertEqual(caption_seconds('가' * 100), 22)
        with self.assertRaises(ValueError):
            caption_seconds('')

    def test_music_only_wave_contains_only_synthesized_score(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'music.wav'
            stats = music_audio([3], 1, target)
            self.assertGreater(stats['rms'], .01)
            self.assertLessEqual(stats['peak'], .261)
            with wave.open(str(target), 'rb') as wav:
                self.assertEqual(wav.getnframes(), RATE * 3)
                self.assertEqual(wav.getnchannels(), 1)
                expected = array('h', (round(v * 2 * 32767) for v in score(3, 1)))
                if __import__('sys').byteorder != 'little':
                    expected.byteswap()
                self.assertEqual(wav.readframes(wav.getnframes()), expected.tobytes())

    def test_invalid_audio_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'music.wav'
            for values in ([1], [float('nan')], []):
                with self.assertRaises(ValueError):
                    write_audio(values, target)
            for durations in ([], [0], [True], [2.5]):
                with self.assertRaises(ValueError):
                    music_audio(durations, 1, target)

    def test_audio_mode_must_be_explicit(self):
        for voices, mode in ((None, False), (Path('voice'), True)):
            with self.assertRaisesRegex(ValueError, 'choose_exactly_one_audio_mode'):
                build(SOURCE, voices, Path('unused-output'), mode)

    def test_music_only_build_never_reads_voice_and_records_mode(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch('story_series.read_voice', side_effect=AssertionError('voice must not be read')), \
                patch('story_series.render_episode', return_value={'durations': [7]}) as render, \
                patch('story_series.run_ffmpeg'), patch('story_series.validate_video', return_value={}):
            output = Path(directory) / 'new'
            build(SOURCE, None, output, True)
            self.assertEqual(render.call_count, 3)
            for call in render.call_args_list:
                self.assertIsNone(call.args[3])
                self.assertTrue(call.args[5])
                self.assertEqual(call.args[0]['audio_mode'], 'music_only')
            manifest = json.loads((output / 'manifest.json').read_text(encoding='utf-8'))
            self.assertEqual(manifest['narration'], 'none')
            self.assertEqual(manifest['audio_mode'], 'music_only')
            self.assertNotIn('합성 음성', manifest['disclosure'])
            self.assertFalse(manifest['upload_attempted'])

    def test_reading_edition_escapes_html_and_keeps_chapter_order(self):
        data = copy.deepcopy(self.data)
        data['episodes'][0]['chapter'][0] = '<script>alert(1)</script>'
        with tempfile.TemporaryDirectory() as directory:
            export_reading_edition(data, Path(directory))
            page = (Path(directory) / 'novel.html').read_text(encoding='utf-8')
            self.assertNotIn('<script>', page)
            self.assertIn('&lt;script&gt;', page)
            self.assertLess(page.index('1화 ·'), page.index('2화 ·'))
            self.assertLess(page.index('2화 ·'), page.index('3화 ·'))
            self.assertIn('실제 이용자의 경험담이 아닌 허구', page)


if __name__ == '__main__':
    unittest.main()
