"""Focused safeguards for destructive media replacement (no cluster access)."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import production as p


def metadata(codec='h264'):
    return {'format': {'duration': '10'}, 'chapters': [], 'streams': [
        {'index': 0, 'codec_type': 'video', 'codec_name': codec, 'pix_fmt': 'yuv420p10le',
         'width': 1920, 'height': 1080, 'r_frame_rate': '24/1', 'color_transfer': 'bt709'},
        {'index': 1, 'codec_type': 'subtitle', 'codec_name': 'subrip',
         'tags': {'language': 'eng'}, 'disposition': {'original': 1, 'hearing_impaired': 1}}]}


class Safeguards(unittest.TestCase):
    def test_lost_subtitle_flag_rejected(self):
        a, b = metadata(), metadata('hevc')
        b['streams'][1]['disposition']['original'] = 0
        with self.assertRaisesRegex(RuntimeError, 'metadata changed'):
            p.metadata_checks(a, b)

    def test_duration_and_resolution_changes_rejected(self):
        for field in ('duration', 'width'):
            a, b = metadata(), metadata('hevc')
            if field == 'duration':
                b['format']['duration'] = '8'
            else:
                b['streams'][0]['width'] = 1280
            with self.assertRaises(RuntimeError):
                p.metadata_checks(a, b)

    def test_matching_metadata_passes(self):
        p.metadata_checks(metadata(), metadata('hevc'))

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.source = self.root / 'episode.mkv'
        self.source.write_bytes(b'original' * 128)
        os.utime(self.source, (1, 1))
        self.state = self.root / 'state'
        self.state.mkdir()
        self.root_patch = patch.object(p, 'ROOTS', {'sonarr': self.root})
        self.state_patch = patch.object(p, 'STATE', self.state)
        self.root_patch.start()
        self.state_patch.start()

    def tearDown(self):
        self.root_patch.stop()
        self.state_patch.stop()
        self.tmp.cleanup()

    def test_hdr_skipped_before_write(self):
        m = metadata()
        m['streams'][0]['color_transfer'] = 'smpte2084'
        with patch.object(p, 'probe', return_value=m):
            self.assertEqual(p.process(self.source)['status'], 'skipped')
        self.assertEqual(self.source.read_bytes(), b'original' * 128)

    def test_hardlinked_source_skipped(self):
        os.link(self.source, self.root / 'download.mkv')
        with patch.object(p, 'probe', return_value=metadata()):
            self.assertEqual(p.process(self.source)['reason'], 'Hardlinked source')

    def test_failed_validation_never_replaces(self):
        with patch.object(p, 'probe', return_value=metadata()), \
             patch.object(p, 'not_playing'), \
             patch.object(p, 'managed_file', return_value=(1, 2)), \
             patch.object(p, 'plex', return_value=f'<MediaContainer><Directory key="1"><Location path="{self.root}"/></Directory></MediaContainer>'.encode()), \
             patch.object(p, 'encode', side_effect=lambda s, o, m: o.write_bytes(b'encoded')), \
             patch.object(p, 'validate', side_effect=RuntimeError('decode failed')):
            with self.assertRaisesRegex(RuntimeError, 'decode failed'):
                p.process(self.source)
        self.assertEqual(self.source.read_bytes(), b'original' * 128)
        self.assertEqual(list(self.root.glob('.fileflows-*')), [])
        self.assertEqual(json.loads(next(self.state.glob('*.json')).read_text())['phase'], 'failed_before_replacement')

    def test_source_changed_during_encode_never_replaced(self):
        def encode(s, o, m):
            o.write_bytes(b'encoded')
            s.write_bytes(b'new upgrade from sonarr')
        with patch.object(p, 'probe', return_value=metadata()), \
             patch.object(p, 'not_playing'), \
             patch.object(p, 'managed_file', return_value=(1, 2)), \
             patch.object(p, 'plex', return_value=f'<MediaContainer><Directory key="1"><Location path="{self.root}"/></Directory></MediaContainer>'.encode()), \
             patch.object(p, 'encode', side_effect=encode), \
             patch.object(p, 'validate', return_value=metadata('hevc')):
            with self.assertRaisesRegex(RuntimeError, 'Source changed'):
                p.process(self.source)
        self.assertEqual(self.source.read_bytes(), b'new upgrade from sonarr')


if __name__ == '__main__':
    unittest.main()
