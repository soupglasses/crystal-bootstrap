# Building and verifying the compiler

Use the Makefile entry points. Set `CRYSTAL`, `CRYSTAL_SRC`, `LLVM_CONFIG` and
`CXX` explicitly when their defaults select different inputs. Developer checks
use a local upstream checkout with populated shards; the default source path is
`../../crystal-lang/crystal`. They do not download dependencies.

## Focused checks

| Command | Coverage |
| --- | --- |
| `make check` | Differential fixtures: values, aliasing, dispatch, evaluation order, closures, cleanup, text and arithmetic. |
| `make check-compiler` | Real compiler components, callbacks, collections, lexical state and whole-program startup. |
| `make check-memory` | Standalone runtime stress under a bounded GC heap. |
| `make regen` | Regenerate example snapshots under `build/examples`. |
| `make check-snapshot` | Build and run those examples with native tools alone. |
| `make check-release` | Generation replacement, archive determinism, shard symlinks and build entry points. |

For a semantic change, start with the affected differential fixture. These
checks compare stdout, stderr and exit status with upstream. Unhandled-error
fixtures compare the exception message and status because native diagnostics
omit Crystal's backtrace formatting.
Compiler probes also compare independent generations, build with Crystal paths
disabled, and verify that a corrupt snapshot cannot replace an existing binary.

The compiler probes include Location, Token, lexer and parser workloads. Runtime
probes schedule a fiber and wait for a subprocess; collection probes exercise
array buffer movement and record copies. Lexical-state probes check shell status
and regex captures. [Runtime](runtime.md#memory-validation) describes the
allocation tests. These are regressions for the bootstrap workload, not a
Crystal conformance suite.

## Build an unpacked source tree

After `make generate`, build the compiler chain without an installed Crystal:

```sh
make bootstrap OUTPUT=build/generated/1.21.0 CXX=clang++ LLVM_CONFIG=llvm-config-20
./build/generated/1.21.0/build/crystal --version
```

`OUTPUT` selects the unpacked tree to build. The command runs that tree's
offline build driver, starting with fresh native objects and caches. All three
compilers are written under its `build/` directory, and the final compiler
enables upstream's full feature set. For distribution
settings, see the [archive README](../packaging/source-README.md).

## Develop a snapshot and audit stage0

For a generator change, translate into a fresh candidate directory using the
selected local upstream source, then build it with native tools:

```sh
make stage0-snapshot SNAPSHOT=build/candidate CRYSTAL=/path/to/crystal \
  CRYSTAL_SRC=/path/to/crystal-source LLVM_CONFIG=/path/to/llvm-config
make stage0 SNAPSHOT=build/candidate CXX=clang++ \
  CRYSTAL_SRC=/path/to/crystal-source LLVM_CONFIG=/path/to/llvm-config
make check-bootstrap BOOTSTRAP_HOST=/path/to/trusted-crystal \
  CRYSTAL_SRC=/path/to/crystal-source LLVM_CONFIG=/path/to/llvm-config
```

`make stage0` writes the repository's `build/crystal-stage0`. `check-bootstrap`
uses that binary without rebuilding it. The binary produced by
`make bootstrap` is in the unpacked tree and must be selected explicitly when
using the comparison harness below. Keep the candidate manifest and native
binary hashes with the report to identify the build being checked.

The audit builds two trusted references, a reference self-build, stage1 and the
bootstrap final. It holds output/cache paths, flags, metadata and source inputs
constant, clearing caches between builds. Acceptance requires reproducible
references and a final hash matching both the direct reference and its self-build.
Use a trusted compiler of the same upstream version; direct cross-version
`n-1 -> n` equality is not required.

The developer harness uses reduced compiler features and no release optimization
for all compared builds. An audit of a distribution's final binary must use that
distribution's recipe. Historical results are in [reproducibility](reproducibility.md).

To use an explicit stage0 path, or build the reduced chain without a trusted
reference, invoke the comparison harness directly:

```sh
CRYSTAL_SRC=/path/to/crystal-source LLVM_CONFIG=/path/to/llvm-config \
  python3 tools/bootstrap.py --stage0 /path/to/crystal-stage0
```

Add `--host /path/to/trusted-crystal` for the reference comparison; omit
`--stage0` for a reference-only audit. A completed chain sets
`source_chain_built`; `stage0_verified` additionally requires the reference
comparison. Reports and logs go to `build/bootstrap-chain`, or `--output-dir`.
Verify source-only operation with Crystal unavailable or blocked.

## Native build behavior

Strict translation fails on unsupported constructs before publishing the
snapshot. The research-only `--bootstrap` generator option can emit throwing
stubs and must not be used for release output.

The snapshot splits function bodies into deterministic translation units while
keeping individual functions intact. The native builder verifies the manifest
hashes and compiles units sequentially to limit peak memory. The previous
executable remains in place until linking succeeds.

The developer stage0 build retains completed objects and precompiles the shared
header. Object stamps cover the compiler, commands and generated inputs; rebuild
affected artifacts when external headers or dependencies change. The upstream
LLVM bridge is built separately and also needs rebuilding after a toolchain
change.

Native builds default to `-O0`. `NATIVE_OPTIMIZE=1` on `make stage0` trades longer
native compilation for lower stage0 stack use. The runner gives stage0 a
512 MiB stack limit because unoptimized C++ frames in recursive type inference
exceed ordinary limits. This reserves address space rather than allocating the
whole stack immediately. `--stage0-stack-mib` changes the runner's limit;
subsequent Crystal builds retain their normal limits.

Distinguish generation, native compilation/linking, stage0 execution, stage1
execution and byte comparison when diagnosing a failure. Preserve the inputs
and logs, reduce the failing workload, and add an observable regression. A
crash, timeout and OOM need different remedies. Native build memory and stage0
runtime memory must be measured separately.
