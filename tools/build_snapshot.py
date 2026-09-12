#!/usr/bin/env python3
"""Build a source snapshot sequentially, without invoking Crystal or its generator."""
import argparse
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--cxx", default=os.environ.get("CXX", "g++"))
    parser.add_argument("--optimize", choices=("0", "1", "2"), default="0",
                        help="native optimization level (default: 0); 1 reduces recursive stack use")
    parser.add_argument("--object", type=Path, action="append", default=[])
    parser.add_argument("--link-flags", default="")
    parser.add_argument("--build-dir", type=Path, help="retain objects and resume unchanged compilation steps")
    parser.add_argument("--precompile-header", action="store_true", help="precompile the shared header with GCC or Clang")
    args = parser.parse_args()
    source = args.snapshot.resolve()
    manifest = json.loads((source / "manifest.json").read_text())
    if manifest["format"] != 1:
        raise ValueError("unsupported snapshot format")
    for name, digest in manifest["files"].items():
        path = source / name
        if Path(name).name != name or path.is_symlink():
            raise ValueError(f"invalid snapshot member: {name}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"snapshot digest mismatch: {name}")
    units = manifest["units"]
    if len(units) != len(set(units)) or any(name not in manifest["files"] or not name.endswith(".cpp") for name in units):
        raise ValueError("invalid translation unit list")
    flags = shlex.split(subprocess.check_output(
        ["pkg-config", "--cflags", "--libs", "bdw-gc", "libutf8proc"], text=True))
    cflags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "bdw-gc", "libutf8proc"], text=True))
    compiler = shlex.split(args.cxx)
    compiler_version = subprocess.check_output(compiler + ["--version"], text=True).strip()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    steps = []
    # One native compiler process at a time is intentional: source partitioning
    # must reduce the peak, rather than multiply it through parallel builds.
    if args.build_dir:
        args.build_dir.mkdir(parents=True, exist_ok=True)
    directory_context = nullcontext(args.build_dir.resolve()) if args.build_dir else tempfile.TemporaryDirectory(prefix="seed-native-", dir=output.parent)
    with directory_context as directory:
        build = Path(directory)
        common = compiler + cflags + ["-std=c++11", "-O" + args.optimize, "-I", str(source)]
        headers = {name: digest for name, digest in manifest["files"].items() if not name.endswith(".cpp")}

        def compile_step(command, artifact, inputs):
            stamp = artifact.with_suffix(artifact.suffix + ".json")
            signature = {"command": command, "compiler": compiler_version, "inputs": inputs}
            if artifact.exists() and stamp.exists() and json.loads(stamp.read_text()) == signature:
                return True
            # A failed compiler may leave an output file. Only a completed step
            # gets a stamp, so interruption cannot make that file reusable.
            stamp.unlink(missing_ok=True)
            subprocess.run(command, check=True)
            stamp.write_text(json.dumps(signature, sort_keys=True) + "\n")
            return False

        if args.precompile_header:
            header = build / "precompiled.hpp"
            include = '#include ' + json.dumps(str(source / "program.hpp")) + '\n'
            # Clang checks this wrapper's mtime when loading its PCH. Rewriting
            # identical bytes would invalidate a correctly reused header.
            if not header.exists() or header.read_text() != include:
                header.write_text(include)
            precompiled = header.with_suffix(".hpp.gch")
            compile_step(common + ["-x", "c++-header", str(header), "-o", str(precompiled)], precompiled, headers)
            common += ["-include", str(header)]
        objects = []
        for index, unit in enumerate(units):
            obj = build / f"{index}.o"
            command = common + ["-c", str(source / unit), "-o", str(obj)]
            start = time.monotonic()
            reused = compile_step(command, obj, {**headers, unit: manifest["files"][unit]})
            steps.append({"unit": unit, "reused": reused, "wall_seconds": round(time.monotonic() - start, 3)})
            objects.append(obj)
        binary = build / "program"
        # A response file avoids ARG_MAX for the eventual compiler snapshot.
        response = build / "link.rsp"
        response.write_text("\n".join('"' + str(path).replace("\\", "\\\\").replace('"', '\\"') + '"'
                                      for path in [*objects, *[path.resolve() for path in args.object]]) + "\n")
        subprocess.run(compiler + ["@" + str(response), *flags, *shlex.split(args.link_flags), "-o", str(binary)], check=True)
        os.replace(binary, output)
    (output.parent / (output.name + ".build.json")).write_text(json.dumps({
        "source_manifest_sha256": hashlib.sha256((source / "manifest.json").read_bytes()).hexdigest(),
        "definitions": manifest["definitions"], "units": steps,
        "compiler": compiler_version.splitlines()[0],
        "optimization": args.optimize,
        "objects": [{"name": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                    for path in args.object],
        "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
