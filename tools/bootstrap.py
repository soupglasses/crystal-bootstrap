#!/usr/bin/env python3
"""Build the bootstrap chain and compare it with controlled upstream builds."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import sys
import time
from compiler_probe import environment, FLAGS

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, help="optional trusted compiler for reproducibility comparisons")
    parser.add_argument("--stage0", type=Path)
    parser.add_argument("--stage0-stack-mib", type=int, default=512,
                        help="stack limit for the generated native compiler (default: 512 MiB)")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/bootstrap-chain")
    args = parser.parse_args()
    if not args.host and not args.stage0:
        parser.error("provide --stage0 to bootstrap, or --host to check trusted builds")
    if args.stage0_stack_mib <= 0:
        parser.error("--stage0-stack-mib must be positive")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report_path = output / "report.json"
    # Preflight failures must not leave a stale successful report either.
    report_path.unlink(missing_ok=True)
    for compiler in (args.host, args.stage0):
        if compiler and compiler.resolve().is_relative_to(output):
            parser.error("compiler input must be outside --output-dir to prevent overwriting it")
    upstream, env = environment()
    work = output / "work"
    work.mkdir(exist_ok=True)
    source = upstream / "src/compiler/crystal.cr"
    env.update(CRYSTAL_CONFIG_BUILD_COMMIT=subprocess.check_output(
        ["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True).strip(),
        CRYSTAL_CONFIG_TARGET=subprocess.check_output(
        [env.get("LLVM_CONFIG", "llvm-config"), "--host-target"], text=True).strip(),
        CRYSTAL_CACHE_DIR=str(work / "cache"))
    report = {"source_revision": env["CRYSTAL_CONFIG_BUILD_COMMIT"],
              "configuration": {key: env[key] for key in (
                  "SOURCE_DATE_EPOCH", "LC_ALL", "TZ", "CRYSTAL_CONFIG_TARGET", "CRYSTAL_CACHE_DIR", "CRYSTAL_PATH", "CRYSTAL_CONFIG_BUILD_COMMIT")},
              "builds": [], "source_chain_built": False, "stage0_verified": False}
    stage0_stack = args.stage0_stack_mib * 1024 * 1024
    if args.stage0:
        _, hard_stack = resource.getrlimit(resource.RLIMIT_STACK)
        if hard_stack != resource.RLIM_INFINITY and stage0_stack > hard_stack:
            parser.error("stage0 stack exceeds the hard limit; raise ulimit -Hs or lower --stage0-stack-mib")
        report["stage0_stack_bytes"] = stage0_stack

    def prepare_stage0():
        # Unoptimized C++ temporaries make upstream's recursive type inference
        # exceed the usual 8 MiB stack. This changes only the bootstrap process.
        _, hard = resource.getrlimit(resource.RLIMIT_STACK)
        resource.setrlimit(resource.RLIMIT_STACK, (stage0_stack, hard))
    report_path = output / "report.json"
    # A failed rerun must not leave a previous successful acceptance report.
    report_path.write_text(json.dumps(report, indent=2) + "\n")

    def build(name, compiler, bootstrap=False):
        # The working output/cache paths stay identical across all builds;
        # each invocation starts without cached object files.
        shutil.rmtree(work / "cache", ignore_errors=True)
        binary = work / "crystal"
        binary.unlink(missing_ok=True)
        command = [str(compiler), str(source), str(binary)] if bootstrap else [
            str(compiler), "build", *FLAGS, "-Dwithout_mt", "--no-debug", "--threads", "1",
            str(source), "-o", str(binary)]
        start = time.monotonic()
        metrics = output / (name + ".metrics.json")
        with (output / (name + ".log")).open("wb") as log:
            result = subprocess.run([sys.executable, str(ROOT / "tools/measure.py"),
                                     str(metrics), *command], env=env, cwd=ROOT,
                                    stdout=log, stderr=subprocess.STDOUT,
                                    preexec_fn=prepare_stage0 if bootstrap else None)
        measured = json.loads(metrics.read_text())
        if result.returncode:
            report["failed_build"] = {"name": name, **measured}
            report_path.write_text(json.dumps(report, indent=2) + "\n")
            result.check_returncode()
        saved = output / name
        shutil.copy2(binary, saved)
        entry = {"name": name, "command": command, "compiler_sha256": digest(compiler),
                 "sha256": digest(saved), "version": subprocess.check_output([str(saved), "--version"], env=env, text=True).strip(), "wall_seconds": round(time.monotonic() - start, 3)}
        entry["peak_rss_kib"] = measured["peak_rss_kib"]
        report["builds"].append(entry)
        report_path.write_text(json.dumps(report, indent=2) + "\n")
        print(f"{name}: {entry['sha256']}", flush=True)
        return saved

    first = fixed = None
    if args.host:
        host = args.host.resolve()
        report["host_version"] = subprocess.check_output([str(host), "--version"], env=env, text=True).strip()
        first = build("reference", host)
        second = build("reference-repeat", host)
        report["same_host_reproducible"] = digest(first) == digest(second)
        fixed = build("reference-self", first)
        report["cross_generation_reproducible"] = digest(first) == digest(fixed)
    if args.stage0:
        stage1 = build("stage1", args.stage0.resolve(), bootstrap=True)
        final = build("crystal", stage1)
        report["source_chain_built"] = True
        if first and fixed:
            report["stage1_matches_reference"] = digest(stage1) == digest(first)
            report["final_matches_reference"] = digest(final) == digest(first)
            report["final_matches_reference_self"] = digest(final) == digest(fixed)
            report["stage0_verified"] = all(report[key] for key in (
                "same_host_reproducible", "cross_generation_reproducible",
                "final_matches_reference", "final_matches_reference_self"))
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k not in ("builds", "configuration")}, indent=2))
    if args.host:
        accepted = report["same_host_reproducible"] and report["cross_generation_reproducible"]
        return 0 if accepted and (not args.stage0 or report["stage0_verified"]) else 1
    return 0 if report["source_chain_built"] else 1


if __name__ == "__main__":
    sys.exit(main())
