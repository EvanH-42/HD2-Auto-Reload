"""Check performance build combinations and the exact packaged Lua payload."""
from pathlib import Path
import itertools
import json
import struct
import subprocess
import sys
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from package import ARCHIVE


class PerfBuildTests(unittest.TestCase):
    def test_flags_and_packaged_payload(self):
        for tactical, debug, perf in itertools.product((False, True), repeat=3):
            with self.subTest(tactical=tactical, debug=debug, perf=perf):
                flags = [flag for enabled, flag in (
                    (tactical, '--enable-tactical-reload'), (debug, '--debug'), (perf, '--perf')) if enabled]
                subprocess.run([sys.executable, str(ROOT / 'scripts/build.py'), *flags],
                               cwd=ROOT, check=True, capture_output=True)
                suffix = ('-tactical' if tactical else '') + ('-debug' if debug else '') + ('-perf' if perf else '')
                entry = (ROOT / 'build' / ('auto_reload_entry' + suffix.replace('-', '_') + '.lua')).read_bytes()
                self.assertIn(f'local PERF = {str(perf).lower()} -- PERF_BUILD_FLAG'.encode(), entry)
                self.assertIn(f'local DEBUG = {str(debug).lower()} -- DEBUG_BUILD_FLAG'.encode(), entry)
                self.assertIn(f'local ENABLE_TACTICAL_RELOAD = {str(tactical).lower()}'.encode(), entry)
                self.assertIn(b'local NATIVE_RELOAD = false -- NATIVE_RELOAD_FLAG', entry)
                with zipfile.ZipFile(ROOT / 'build' / ('Auto-Reload-v0.7.0' + suffix + '.zip')) as archive:
                    self.assertIsNone(archive.testzip())
                    self.assertEqual(json.loads(archive.read('manifest.json'))['Guid'],
                                     '4df5aee3-3c5d-47fc-b0e9-0a40f7988738')
                    payload = archive.read('Addon/' + ARCHIVE)
                    record = struct.unpack_from('<7Q6I', payload, 104)
                    start, size = record[2], record[7]
                    length, mode = struct.unpack_from('<II', payload, start)
                    body = payload[start + 8:start + size]
                    self.assertEqual(mode, 2)
                    self.assertEqual(len(body), length)
                    self.assertEqual(body, entry)

    def test_perf_does_not_bypass_native_verification(self):
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/build.py'), '--perf', '--native-reload'],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('requires --game-dir', result.stderr)

    def test_optimization_stage_artifacts(self):
        artifacts = []
        for stage in ('p1', 'p2'):
            subprocess.run([sys.executable, str(ROOT / 'scripts/build.py'), '--enable-tactical-reload',
                            '--optimization-stage', stage], cwd=ROOT, check=True, capture_output=True)
            entry = (ROOT / 'build' / f'auto_reload_entry_tactical_{stage}_perf.lua').read_bytes()
            self.assertIn(f'local OPTIMIZATION_STAGE = {stage[-1]} -- OPTIMIZATION_STAGE_FLAG'.encode(), entry)
            self.assertIn(b'local PERF = true -- PERF_BUILD_FLAG', entry)
            self.assertIn(b'local ENABLE_TACTICAL_RELOAD = true', entry)
            self.assertIn(b'local NATIVE_RELOAD = false -- NATIVE_RELOAD_FLAG', entry)
            self.assertNotIn(b'-- FAST_CONTEXT_READER_INSERT', entry)
            output = ROOT / 'build' / f'Auto-Reload-v0.7.0-tactical-{stage}-perf.zip'
            artifacts.append(output)
            with zipfile.ZipFile(output) as archive:
                self.assertIsNone(archive.testzip())
                manifest = json.loads(archive.read('manifest.json'))
                self.assertEqual(manifest['Guid'], '4df5aee3-3c5d-47fc-b0e9-0a40f7988738')
                payload = archive.read('Addon/' + ARCHIVE)
                record = struct.unpack_from('<7Q6I', payload, 104)
                self.assertEqual(payload[record[2] + 8:record[2] + record[7]], entry)
        self.assertTrue(all(path.is_file() for path in artifacts))
        self.assertNotEqual(artifacts[0].read_bytes(), artifacts[1].read_bytes())

    def test_optimization_stage_rejects_other_modes(self):
        for stage in ('p1', 'p2'):
            for flags in ([], ['--enable-tactical-reload', '--native-reload']):
                result = subprocess.run([sys.executable, str(ROOT / 'scripts/build.py'),
                                         '--optimization-stage', stage, *flags],
                                        cwd=ROOT, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertIn('p1/p2 require', result.stderr)


if __name__ == '__main__':
    unittest.main()
