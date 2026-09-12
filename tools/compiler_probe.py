#!/usr/bin/env python3
"""Record full-compiler semantic inventory or attempt native source translation."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FLAGS = ["-D" + flag for flag in (
    "without_interpreter", "without_libxml2", "without_openssl", "without_zlib",
    "strict_multi_assign", "preview_overload_order")]


def environment():
    upstream = Path(os.environ.get("CRYSTAL_SRC", ROOT / "../../crystal-lang/crystal")).resolve()
    return upstream, dict(os.environ, CRYSTAL_PATH=f"{upstream}/lib:{upstream}/src",
                         CRYSTAL_CACHE_DIR=str(ROOT / "build/cache"),
                         CRYSTAL_HAS_WRAPPER="1", LC_ALL="C", TZ="UTC", SOURCE_DATE_EPOCH="0")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["inventory", "translate", "lexer", "stage0", "stage0-inventory"])
    parser.add_argument("--bootstrap", action="store_true")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/compiler-snapshot")
    args = parser.parse_args()
    upstream, env = environment()
    prefix = ROOT / "build" / ("compiler-" + args.mode)
    prefix.parent.mkdir(parents=True, exist_ok=True)
    command = [str(ROOT / "build/crystal-to-cpp"), *FLAGS]
    if args.bootstrap:
        command += ["--bootstrap"]
    if args.mode in ("inventory", "stage0-inventory"):
        command += ["--inventory"]
    else:
        if args.mode in ("translate", "stage0"):
            command += ["--program"]
        command += ["--output-dir", str(args.output_dir)]
    input_source = ROOT / "generator/stage0.cr" if args.mode.startswith("stage0") else ROOT / "tests/compiler/lexer.cr" if args.mode == "lexer" else upstream / "src/compiler/crystal.cr"
    command += [str(input_source)]
    output = prefix.with_suffix(".json" if "inventory" in args.mode else ".stdout")
    log = prefix.with_suffix(".log")
    with output.open("wb") as stdout, log.open("wb") as stderr:
        result = subprocess.run([sys.executable, str(ROOT / "tools/measure.py"),
                                 str(prefix.with_suffix(".metrics.json")), *command],
                                env=env, stdout=stdout, stderr=stderr)
    print(prefix.with_suffix(".metrics.json").read_text())
    if result.returncode:
        print(log.read_text()[:12000], file=sys.stderr)
    else:
        print(f"Wrote {output if 'inventory' in args.mode else args.output_dir}")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
