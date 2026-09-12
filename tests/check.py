#!/usr/bin/env python3
"""Exercise source -> upstream semantics -> C++ -> executable through the CLI."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures"
SNAPSHOTS = ROOT / "build/examples"
BUILD = ROOT / "build/check"
EXPECTED = {
    "compiler_values": "2\n1\n3\n42\n17\n1\n1\n1\n",
    "bit_counts": "8\n7\n64\n8\n16\n",
    "integer_text": "1\n1\n1\n1\n1\n9\n",
    "loop_control": "11\n2\n12\n13\n42\n",
    "unions": "8\n10\n3\n2\n7\n",
    "dispatch": "11\n22\n",
    "text": "4\n3\n1\n65\n0\n233\n2\n2\n0\n0\n",
    "tuples": "12\n7\n",
    "gc_pressure": "11999\n",
    "heap_objects": "17\n29\n",
    "arrays": "4\n4\n7\n4\n42\n42\n0\n1\n",
    "typed_exceptions": "1\n2\n3\n4\n5\n6\n7\n",
    "yield_blocks": "8\n12\n12\n8\n12\n9\n8\n25\n10\n10\n8\n36\n9\n",
    "collection": "2\n6\n7\n0\n1\n",
    "closures": "3\n6\n11\n10\n22\n22\n30\n",
    "cleanup": "6\n7\n8\n6\n9\n99\n10\n11\n5\n13\n12\n",
    "arithmetic": "-2147483648\n7\n1\n2\n3\n0\n1\n2\n",
    "replacement_exception": "",
}


def run(args, *, check=True, env=None):
    result = subprocess.run(
        [str(a) for a in args], cwd=ROOT, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180,
    )
    if check and result.returncode:
        raise RuntimeError(
            f"{shlex.join(str(a) for a in args)} exited {result.returncode}\n"
            + result.stderr.decode(errors="replace")
        )
    return result


def check_result(name, result, *, reference=False):
    assert result.stdout.decode() == EXPECTED[name], (name, result.stdout)
    if name == "replacement_exception":
        assert result.returncode == 1, (name, result.returncode)
        if reference:
            # The prototype intentionally omits Crystal's backtrace formatting.
            assert result.stderr.decode().splitlines()[0].startswith(
                "Unhandled exception: cleanup (Exception)"
            ), result.stderr
        else:
            assert result.stderr == b"cleanup\n", result.stderr
    else:
        assert result.returncode == 0, (name, result.returncode, result.stderr)
        assert result.stderr == b"", (name, result.stderr)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--regen", action="store_true")
    modes.add_argument("--snapshot-only", action="store_true")
    options = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    cpp_compilers = [shlex.split(os.environ.get("CXX", "g++"))]
    if shutil.which("clang++") and Path(cpp_compilers[0][0]).name != "clang++":
        cpp_compilers.append(["clang++"])
    gc_flags = shlex.split(run(["pkg-config", "--cflags", "--libs", "bdw-gc", "libutf8proc"]).stdout.decode())
    gc_cflags = shlex.split(run(["pkg-config", "--cflags", "bdw-gc", "libutf8proc"]).stdout.decode())
    host = shlex.split(os.environ.get("CRYSTAL", "crystal"))
    reference_compiler = shlex.split(os.environ.get("REFERENCE_CRYSTAL", os.environ.get("CRYSTAL", "crystal")))
    generator = ROOT / "build/crystal-to-cpp"
    env = dict(os.environ, LC_ALL="C", TZ="UTC", SOURCE_DATE_EPOCH="0")

    if not options.regen:
        manifest = json.loads((SNAPSHOTS / "manifest.json").read_text())
        for relative, expected in manifest["files"].items():
            assert digest(ROOT / relative) == expected, f"snapshot input/output digest differs: {relative}"

    if not options.regen:
        run(shlex.split(os.environ.get("CC", "cc")) + [
            "-c", ROOT / "tests/support/probe.c", "-o", BUILD / "probe.o", *gc_cflags
        ])

    generated = {}
    for fixture in sorted(FIXTURES.glob("*.cr")):
        name = fixture.stem
        if options.snapshot_only:
            source = SNAPSHOTS / (name + ".cpp")
        else:
            result = run([generator, fixture], env=env)
            generated[name] = result.stdout
            # Separate processes and different absolute paths expose upstream
            # temporary names derived from a source filename or global counters.
            with tempfile.TemporaryDirectory(prefix="seed-regen-") as directory:
                relocated = Path(directory) / fixture.name
                relocated.write_bytes(fixture.read_bytes())
                again = run([generator, relocated], env=env)
                assert again.stdout == result.stdout, f"non-deterministic output: {name}"
            source = BUILD / (name + ".cpp")
            source.write_bytes(result.stdout)
            if options.regen:
                continue
            assert source.read_bytes() == (SNAPSHOTS / source.name).read_bytes(), (
                f"snapshot differs: {name}; review make regen output"
            )
            reference = BUILD / (name + ".crystal")
            run(reference_compiler + ["build", fixture, "-o", reference, "-Dwithout_mt",
                        "--link-flags", shlex.join([str(BUILD / "probe.o"), *gc_flags])], env=env)
            check_result(name, run([reference], check=False), reference=True)

        for compiler in cpp_compilers:
            for optimize in ["-O0", "-O2"]:
                binary = BUILD / (name + "." + Path(compiler[0]).name + optimize)
                run(compiler + [
                    "-std=c++11", optimize, "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-variable", "-Wno-unused-but-set-variable",
                    "-Wno-unused-parameter", "-I", ROOT / "runtime", source,
                    BUILD / "probe.o", "-o", binary, *gc_flags,
                ])
                check_result(name, run([binary], check=False))
        print(f"PASS {name}: output, exit status, cleanup behavior")

    if options.regen:
        # Refresh only after every fixture generated deterministically.
        SNAPSHOTS.mkdir(parents=True, exist_ok=True)
        for name, data in generated.items():
            (SNAPSHOTS / (name + ".cpp")).write_bytes(data)
        upstream = Path(os.environ.get("CRYSTAL_SRC", ROOT / "../../crystal-lang/crystal")).resolve()
        inputs = [*sorted((ROOT / "generator").glob("*.cr")),
                  *sorted((ROOT / "runtime").glob("*.hpp")), ROOT / "tests/support/probe.c",
                  ROOT / "tests/runtime/memory.cpp",
                  *sorted(FIXTURES.glob("*.cr")), *sorted(SNAPSHOTS.glob("*.cpp"))]
        manifest = {
            "status": "feasibility examples; not a compiler snapshot",
            "upstream_revision": run(["git", "-C", upstream, "-c", "core.fsmonitor=false", "rev-parse", "HEAD"]).stdout.decode().strip(),
            "generator_host": run(host + ["--version"]).stdout.decode().strip(),
            "generation_environment": {"LC_ALL": "C", "TZ": "UTC", "SOURCE_DATE_EPOCH": "0"},
            "format": "C++11 source",
            "files": {str(path.relative_to(ROOT)): digest(path) for path in inputs},
        }
        (SNAPSHOTS / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        print(f"Regenerated {len(generated)} deterministic snapshots")
        return

    if not options.snapshot_only:
        for fixture in sorted((ROOT / "tests/unsupported").glob("*.cr")):
            result = run([generator, fixture], check=False, env=env)
            assert result.returncode == 1 and result.stdout == b"", fixture
            assert result.stderr.startswith(b"unsupported:"), result.stderr
            print(f"PASS rejected {fixture.name}: {result.stderr.decode().strip()}")

        # An unused definition before the entry must not perturb existing names.
        for stable_fixture in ["closures", "yield_blocks"]:
            original = FIXTURES / (stable_fixture + ".cr")
            with tempfile.TemporaryDirectory(prefix="seed-stability-") as directory:
                modified = Path(directory) / original.name
                modified.write_text("def unused(value : Int32)\n  value\nend\n" + original.read_text())
                original_cpp = generated[stable_fixture].decode().splitlines()
                modified_cpp = run([generator, modified], env=env).stdout.decode().splitlines()
                strip_locations = lambda lines: [line for line in lines if not line.startswith("//")]
                assert strip_locations(original_cpp) == strip_locations(modified_cpp)
        print("PASS stable output after unrelated definition")

    memory_results = []
    for compiler in cpp_compilers:
        for optimize in ["-O0", "-O2"]:
            binary = BUILD / ("memory." + Path(compiler[0]).name + optimize)
            run(compiler + ["-std=c++11", optimize, "-Wall", "-Wextra", "-Werror",
                            "-I", ROOT / "runtime", ROOT / "tests/runtime/memory.cpp",
                            "-o", binary, *gc_flags])
            result = run([binary])
            metrics = {key: int(value) for key, value in
                       (item.split("=") for item in result.stdout.decode().split())}
            memory_results.append({"compiler": compiler, "optimization": optimize, **metrics})
            print(f"PASS memory {compiler[0]} {optimize}: {result.stdout.decode().strip()}")

    report = {
        "mode": "snapshot-only" if options.snapshot_only else "differential",
        "compilers": [run(c + ["--version"]).stdout.decode().splitlines()[0] for c in cpp_compilers],
        "snapshots": {path.name: digest(path) for path in sorted(SNAPSHOTS.glob("*.cpp"))},
        "runtime_sha256": digest(ROOT / "runtime/seed_runtime.hpp"),
        "fixtures": list(EXPECTED),
        "memory_stress": memory_results,
        "bdw_gc_version": run(["pkg-config", "--modversion", "bdw-gc"]).stdout.decode().strip(),
    }
    if not options.snapshot_only:
        report["reference_compiler"] = run(reference_compiler + ["--version"]).stdout.decode().strip()
    (BUILD / (report["mode"] + ".json")).write_text(json.dumps(report, indent=2) + "\n")
    print("All feasibility checks passed")


if __name__ == "__main__":
    main()
