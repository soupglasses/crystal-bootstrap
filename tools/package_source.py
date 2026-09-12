#!/usr/bin/env python3
"""Package freshly generated sources for the GitHub release workflow."""
import argparse
import json
import os
from pathlib import Path
import stat
import zipfile

from generate import digest


def members(root):
    # Do not follow shard lib/ symlinks, which can point back to their parents.
    for directory, directories, files in os.walk(root, followlinks=False):
        for name in sorted(directories + files):
            path = Path(directory) / name
            if path.is_symlink() or path.is_file():
                yield path


def archive_source(source, destination, identity):
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(members(source)):
            info = zipfile.ZipInfo(f'{identity}/{path.relative_to(source).as_posix()}', (1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            mode = stat.S_IFLNK | 0o777 if path.is_symlink() else stat.S_IFREG | (0o755 if path.stat().st_mode & 0o111 else 0o644)
            info.external_attr = mode << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, os.readlink(path).encode() if path.is_symlink() else path.read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output-dir', type=Path, default=Path('dist'))
    args = parser.parse_args()
    metadata = json.loads((args.source / 'SOURCE.json').read_text())
    identity = f'crystal-bootstrap-{metadata["bootstrap_version"]}-crystal-{metadata["crystal"]["version"]}-llvm{metadata["llvm_major"]}'
    args.output_dir.mkdir(parents=True, exist_ok=True)
    destination = args.output_dir / (identity + '.zip')
    temporary = destination.with_suffix('.zip.partial')
    archive_source(args.source, temporary, identity)
    temporary.replace(destination)
    (args.output_dir / 'SHA256SUMS').write_text(f'{digest(destination)}  {destination.name}\n')
    print(destination)


if __name__ == '__main__':
    main()
