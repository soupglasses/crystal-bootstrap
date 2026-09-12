"""Exercise source publication and the distribution archive through real files."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from generate import publish


class ReleaseTests(unittest.TestCase):
    def test_bootstrap_builds_inside_selected_source_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for destination in ('source', str(root / 'absolute-source')):
                with self.subTest(destination=destination):
                    source = root / destination
                    source.mkdir()
                    # Exercise recursive Make's variable inheritance without
                    # needing a generated compiler or native dependencies.
                    (source / 'Makefile').write_text(
                        'OUTPUT ?= build\n'
                        'all:\n'
                        '\tmkdir -p "$(OUTPUT)"\n'
                        '\ttouch "$(OUTPUT)/built"\n')
                    subprocess.run([
                        'make', '-f', str(ROOT / 'Makefile'), 'bootstrap',
                        f'OUTPUT={destination}', f'PYTHON={sys.executable}',
                    ], cwd=root, check=True, capture_output=True)
                    self.assertTrue((source / 'build/built').is_file())

    def test_failed_replacement_preserves_previous_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / '1.21.0'
            output.mkdir()
            (output / 'SOURCE.json').write_text('previous generation')
            with self.assertRaises(FileNotFoundError):
                publish(root / 'missing', output)
            self.assertEqual((output / 'SOURCE.json').read_text(), 'previous generation')

    def test_regeneration_and_separate_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for version in ('1.21.0', 'future'):
                staging = root / 'staging'
                staging.mkdir()
                (staging / 'SOURCE.json').write_text(version)
                publish(staging, root / version)
            staging.mkdir()
            (staging / 'SOURCE.json').write_text('regenerated')
            publish(staging, root / '1.21.0')
            self.assertEqual((root / '1.21.0/SOURCE.json').read_text(), 'regenerated')
            self.assertEqual((root / 'future/SOURCE.json').read_text(), 'future')

    def test_archive_is_deterministic_and_preserves_shard_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            source.mkdir()
            (source / 'SOURCE.json').write_text(json.dumps({
                'bootstrap_version': '2026.09.12', 'crystal': {'version': '1.21.0'}, 'llvm_major': 20}))
            (source / 'code.cpp').write_text('int main() { return 0; }\n')
            (source / 'lib').symlink_to('.', target_is_directory=True)
            command = [sys.executable, str(ROOT / 'tools/package_source.py'), str(source)]
            archives = []
            for name in ('first', 'second'):
                subprocess.run([*command, '--output-dir', str(root / name)], check=True, capture_output=True)
                archives.append(next((root / name).glob('*.zip')))
                os.utime(source / 'code.cpp', (123456, 123456))
            self.assertEqual(archives[0].read_bytes(), archives[1].read_bytes())
            with zipfile.ZipFile(archives[0]) as archive:
                link = next(info for info in archive.infolist() if info.filename.endswith('/lib'))
                self.assertEqual((link.external_attr >> 16) & 0o170000, 0o120000)
                self.assertEqual(archive.read(link), b'.')

    def test_tag_with_slash_keeps_its_name_in_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            source.mkdir()
            metadata = {'bootstrap_version': 'release/next',
                        'crystal': {'version': '1.21.0'}, 'llvm_major': 20}
            (source / 'SOURCE.json').write_text(json.dumps(metadata))
            subprocess.run([sys.executable, str(ROOT / 'tools/package_source.py'),
                            str(source), '--output-dir', str(root / 'dist')],
                           check=True, capture_output=True)
            archive = root / 'dist/crystal-bootstrap-release%2Fnext-crystal-1.21.0-llvm20.zip'
            with zipfile.ZipFile(archive) as zipped:
                name = next(name for name in zipped.namelist() if name.endswith('/SOURCE.json'))
                self.assertEqual(json.loads(zipped.read(name)), metadata)


if __name__ == '__main__':
    unittest.main()
