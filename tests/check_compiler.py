#!/usr/bin/env python3
"""Compare real upstream compiler components through published native snapshots."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from compiler_probe import environment, FLAGS


def run(command, timeout=240, **kwargs):
    return subprocess.run([str(arg) for arg in command], check=True, timeout=timeout,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def main():
    _, env = environment()
    build = ROOT / "build/compiler-check"
    build.mkdir(parents=True, exist_ok=True)
    flags = shlex.split(run(["pkg-config", "--cflags", "--libs", "bdw-gc", "libutf8proc"]).stdout.decode())
    probe = build / "probe.o"
    run(["cc", "-c", ROOT / "tests/support/probe.c", "-o", probe, *flags])
    reference = shlex.split(os.environ.get("REFERENCE_CRYSTAL", str(ROOT / "build/reference-crystal")))
    reports = []
    for name, expected in [("location", b"12\n34\n"), ("token", b"1\n1\n"),
                           ("native_abi", b"-3\n7\n7\n42\n"),
                           ("lexer", b"1\n" * 7), ("parser", b"2\n1\n1\n1\n"),
                           ("runtime", b"42\nchild\n"), ("collections", b"100\n0\noutside\n200\n"),
                           ("special_vars", b"true\n123\n")]:
        source = ROOT / "tests/compiler" / (name + ".cr")
        with tempfile.TemporaryDirectory(prefix=name + "-", dir=build) as directory:
            work = Path(directory)
            snapshots = [work / "first", work / "second"]
            for snapshot in snapshots:
                run([ROOT / "build/crystal-to-cpp", *FLAGS,
                     *(["--program"] if name in ("runtime", "collections", "special_vars") else []), "--output-dir", snapshot,
                     "--functions-per-unit", "2" if name in ("location", "token") else "200", source], env=env)
            members = sorted(path.name for path in snapshots[0].iterdir())
            assert members == sorted(path.name for path in snapshots[1].iterdir())
            for member in members:
                assert (snapshots[0] / member).read_bytes() == (snapshots[1] / member).read_bytes(), member
            metrics = build / (name + ".metrics.json")
            binary = build / name
            native_env = dict(env, CRYSTAL="/no-crystal-permitted", CRYSTAL_PATH="/no-crystal-sources")
            run([sys.executable, ROOT / "tools/measure.py", metrics,
                 sys.executable, ROOT / "tools/build_snapshot.py", snapshots[0],
                 "--optimize", "1",
                 "--object", probe, "--link-flags=-lpcre2-8", "--precompile-header",
                 "-o", binary], env=native_env, timeout=600)
            result = run([binary])
            assert result.stdout == expected and not result.stderr, result
            reference_binary = work / "reference"
            run([*reference, "build", *FLAGS, "-Dwithout_mt", source, "-o", reference_binary,
                 "--link-flags", shlex.join([str(probe), *flags])], env=env)
            upstream_result = run([reference_binary])
            assert (result.stdout, result.stderr) == (upstream_result.stdout, upstream_result.stderr)
            # A damaged member must be rejected before it can replace the binary.
            before = binary.read_bytes()
            (snapshots[0] / "main.cpp").write_text("invalid C++")
            rejected = subprocess.run([sys.executable, str(ROOT / "tools/build_snapshot.py"),
                                       str(snapshots[0]), "-o", str(binary)], capture_output=True)
            assert rejected.returncode and b"digest mismatch" in rejected.stderr
            assert binary.read_bytes() == before
            report = json.loads(metrics.read_text())
            report["component"] = name
            report["snapshot"] = json.loads((snapshots[1] / "manifest.json").read_text())
            reports.append(report)
            print(f"PASS compiler {name}: deterministic split snapshot, native/reference output, digest rejection", flush=True)
    (build / "report.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.stderr.buffer.write(error.stderr or b"")
        raise
