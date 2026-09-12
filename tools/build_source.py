#!/usr/bin/env python3
"""Build stage0 -> stage1 -> Crystal from an unpacked source release, offline."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import resource
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


@contextmanager
def workspace(output):
    # Stable paths matter for byte comparisons with upstream reference builds.
    with (output / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        work = output / 'work'
        if work.exists():
            shutil.rmtree(work)
        work.mkdir()
        yield work


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cxx', default=os.environ.get('CXX', 'c++'))
    parser.add_argument('--llvm-config', default=os.environ.get('LLVM_CONFIG', 'llvm-config'))
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'build')
    parser.add_argument('--final-flags', default='--release --no-debug --threads 1 -Dstrict_multi_assign -Dpreview_overload_order',
                        help='upstream final compiler build flags; optional features remain enabled')
    parser.add_argument('--stage0-stack-mib', type=int, default=512)
    args = parser.parse_args()
    metadata = json.loads((ROOT / 'SOURCE.json').read_text())
    llvm_config = str(Path(shutil.which(args.llvm_config) or args.llvm_config).resolve())

    def llvm(*flags):
        return subprocess.check_output([llvm_config, *flags], text=True).strip()

    if int(llvm('--version').split('.')[0]) != metadata['llvm_major']:
        parser.error(f'this generated source requires LLVM {metadata["llvm_major"]}')
    stack = args.stage0_stack_mib * 1024 * 1024
    _, hard = resource.getrlimit(resource.RLIMIT_STACK)
    if stack <= 0 or (hard != resource.RLIM_INFINITY and stack > hard):
        parser.error('stage0 stack must be positive and within the hard stack limit')
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    # A fresh workspace prevents external header/toolchain changes from reusing
    # stale objects. Preserve a prior completed chain if any build fails.
    with workspace(output) as work:
        upstream = work / 'upstream'
        shutil.copytree(ROOT / 'upstream', upstream, symlinks=True)
        bridge = upstream / 'src/llvm/ext/llvm_ext.o'
        subprocess.run([*shlex.split(args.cxx), '-c', str(bridge.with_suffix('.cc')),
                        '-o', str(bridge), *shlex.split(llvm('--cxxflags'))], check=True)
        stage0 = work / 'crystal-stage0'
        subprocess.run([sys.executable, str(ROOT / 'tools/build_snapshot.py'), str(ROOT / 'snapshot'),
                        '--cxx', args.cxx, '--precompile-header', '--object', str(bridge),
                        '--link-flags=' + llvm('--ldflags', '--libs', '--system-libs') + ' -lpcre2-8',
                        '-o', str(stage0)], check=True)
        env = dict(os.environ, LLVM_CONFIG=llvm_config, CRYSTAL_HAS_WRAPPER='1',
                   CRYSTAL_PATH=f'{upstream}/lib:{upstream}/src',
                   CRYSTAL_CACHE_DIR=str(work / 'cache'),
                   CRYSTAL_CONFIG_BUILD_COMMIT=os.environ.get('CRYSTAL_CONFIG_BUILD_COMMIT', metadata['crystal']['revision']),
                   CRYSTAL_CONFIG_TARGET=llvm('--host-target'))
        env.setdefault('SOURCE_DATE_EPOCH', '0')
        env.setdefault('LC_ALL', 'C')
        env.setdefault('TZ', 'UTC')
        source = upstream / 'src/compiler/crystal.cr'
        stage1 = work / 'crystal-stage1'

        def prepare_stage0():
            resource.setrlimit(resource.RLIMIT_STACK, (stack, hard))

        subprocess.run([str(stage0), str(source), str(stage1)], env=env,
                       preexec_fn=prepare_stage0, check=True)
        shutil.rmtree(work / 'cache', ignore_errors=True)
        final = work / 'crystal'
        subprocess.run([str(stage1), 'build', str(source), '-o', str(final),
                        *shlex.split(args.final_flags)], env=env, check=True)
        subprocess.run([str(final), '--version'], env=env, check=True)
        for binary in (stage0, stage1, final):
            binary.replace(output / binary.name)
    print(f'Built {output / "crystal"}')


if __name__ == '__main__':
    main()
