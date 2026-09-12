#!/usr/bin/env python3
"""Generate an unpacked, source-only bootstrap tree from release.json."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

from compiler_probe import FLAGS

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def download(url, path, expected=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        temporary = path.with_suffix(path.suffix + '.partial')
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'crystal-bootstrap-source-release'})
            with urllib.request.urlopen(request, timeout=120) as response, temporary.open('wb') as output:
                shutil.copyfileobj(response, output)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    if expected and digest(path) != expected:
        raise ValueError(f'download checksum mismatch: {path}; remove it and retry')


def extract(archive, destination):
    # Extract through Python's data filter: repository tarballs contain symlinks,
    # but cannot write outside their extraction directory or create devices.
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        with tarfile.open(archive) as source:
            source.extractall(temporary, filter='data')
        entries = list(Path(temporary).iterdir())
        if len(entries) != 1 or not entries[0].is_dir():
            raise ValueError(f'expected one archive root: {archive}')
        shutil.move(str(entries[0]), destination)


def fetch_source(repository, revision, destination, downloads):
    archive = downloads / f'{repository.replace("/", "-")}-{revision}.tar.gz'
    download(f'https://codeload.github.com/{repository}/tar.gz/{revision}', archive)
    extract(archive, destination)


def compare(first, second):
    names = sorted(p.name for p in first.iterdir())
    if names != sorted(p.name for p in second.iterdir()):
        raise ValueError('independent generation produced different members')
    for name in names:
        if digest(first / name) != digest(second / name):
            raise ValueError(f'non-deterministic generated member: {name}')


def publish(staging, output):
    # Keep the last complete result if generation or replacement fails. Never
    # replace an unrelated directory supplied accidentally as --output-dir.
    backup = output.with_name(output.name + ".previous")
    for existing in (output, backup):
        if existing.is_symlink() or (existing.exists() and not (existing / 'SOURCE.json').is_file()):
            raise ValueError(f'refusing to replace a non-generated directory: {existing}')
    if backup.exists():
        if not output.exists():
            backup.rename(output)
        else:
            shutil.rmtree(backup)
    if output.exists():
        if not (output / "SOURCE.json").is_file():
            raise ValueError(f"refusing to replace a non-generated directory: {output}")
        output.rename(backup)
    try:
        staging.rename(output)
    except BaseException:
        if backup.exists():
            backup.rename(output)
        raise
    if backup.exists():
        shutil.rmtree(backup)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--crystal', default=os.environ.get('CRYSTAL'),
                        help='generator host; otherwise download the pinned official host')
    parser.add_argument('--llvm-config', default=os.environ.get('LLVM_CONFIG', 'llvm-config'))
    parser.add_argument('--output-dir', type=Path, help='default: build/generated/<Crystal version>')
    args = parser.parse_args()
    config = json.loads((ROOT / 'release.json').read_text())
    target = config['crystal']
    output = (args.output_dir or ROOT / 'build/generated' / target['version']).absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.is_symlink():
        parser.error('output must not be a symlink')
    work = ROOT / 'build/generate' / target['version']
    work.mkdir(parents=True, exist_ok=True)
    # One target uses stable source paths for macro expansion. Also lock the
    # destination so two target versions cannot replace the same output.
    with (work / '.lock').open('a') as lock, output.with_name(output.name + '.lock').open('a') as destination_lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(destination_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        generate(args, config, work, output)


def generate(args, config, work, output):
    target = config['crystal']
    llvm_config = str(Path(shutil.which(args.llvm_config) or args.llvm_config).resolve())
    llvm_version = subprocess.check_output([llvm_config, '--version'], text=True).strip()
    downloads = work / 'downloads'
    for name in ('upstream', 'first', 'second', 'cache', 'host'):
        if (work / name).exists():
            shutil.rmtree(work / name)
    upstream = work / 'upstream'
    print(f'Fetching Crystal {target["version"]} at {target["revision"]}', flush=True)
    fetch_source('crystal-lang/crystal', target['revision'], upstream, downloads)
    (upstream / 'lib').mkdir(exist_ok=True)
    for name, shard in config['shards'].items():
        fetch_source(shard['repository'], shard['revision'], upstream / 'lib' / name, downloads)
    if (upstream / 'src/VERSION').read_text().strip() != target['version']:
        raise ValueError('source version differs from release.json')
    if args.crystal:
        host = shutil.which(args.crystal) or str(Path(args.crystal).resolve())
    else:
        host_archive = downloads / f'crystal-host-{config["generator_host"]["version"]}.tar.gz'
        download(config['generator_host']['url'], host_archive, config['generator_host']['sha256'])
        extract(host_archive, work / 'host')
        host = str(work / 'host/bin/crystal')
    env = dict(os.environ, CRYSTAL_PATH=f'{upstream}/lib:{upstream}/src',
               CRYSTAL_CACHE_DIR=str(work / 'cache'), CRYSTAL_HAS_WRAPPER='1',
               LLVM_CONFIG=llvm_config, LC_ALL='C', TZ='UTC', SOURCE_DATE_EPOCH='0')
    generator = work / 'crystal-to-cpp'
    print('Building the generator', flush=True)
    subprocess.run([host, 'build', str(ROOT / 'generator/main.cr'), '-o', str(generator),
                    '-Dwithout_mt', *FLAGS, '--threads', '1', '--error-trace'], env=env, check=True)
    for name in ('first', 'second'):
        print(f'Transpiling Crystal {target["version"]}: {name} process', flush=True)
        subprocess.run([str(generator), *FLAGS, '--program', '--output-dir', str(work / name),
                        str(ROOT / 'generator/stage0.cr')], env=env, check=True)
    compare(work / 'first', work / 'second')
    manifest = json.loads((work / 'first/manifest.json').read_text())
    if manifest['unsupported_paths']:
        raise ValueError('snapshot contains unsupported paths')
    with tempfile.TemporaryDirectory(prefix=output.name + '.staging-', dir=output.parent) as temporary:
        staging = Path(temporary) / 'source'
        staging.mkdir()
        shutil.move(work / 'first', staging / 'snapshot')
        shutil.move(upstream, staging / 'upstream')
        shutil.copytree(ROOT / 'bootstrap/notices', staging / 'notices')
        (staging / 'tools').mkdir()
        for name in ('build_snapshot.py', 'build_source.py'):
            shutil.copy2(ROOT / 'tools' / name, staging / 'tools' / name)
        shutil.copy2(ROOT / 'packaging/source.Makefile', staging / 'Makefile')
        shutil.copy2(ROOT / 'packaging/source-README.md', staging / 'README.md')
        shutil.copy2(ROOT / 'LICENSE', staging / 'LICENSE')
        metadata = {
            'format': 1, 'bootstrap_version': config['version'], 'crystal': target,
            'shards': config['shards'], 'llvm_major': int(llvm_version.split('.')[0]),
            'generation_llvm_version': llvm_version,
            'snapshot_manifest_sha256': digest(staging / 'snapshot/manifest.json'),
            'bootstrap_flags': ['-Dwithout_mt', *FLAGS],
            'generation_repeated_identically': True,
            'compiler_chain_built_by_release_workflow': False,
        }
        (staging / 'SOURCE.json').write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n')
        publish(staging, output)
    shutil.rmtree(work / 'second')
    print(f'Generated {output} ({manifest["definitions"]:,} definitions; two identical runs)', flush=True)


if __name__ == '__main__':
    main()
