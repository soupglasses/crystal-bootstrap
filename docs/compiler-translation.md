# Compiler translation workbench

The generator emits the configured upstream compiler directly from its typed
program into readable C++11. Strict full snapshots compile and link into native
stage0 binaries that build the upstream compiler. Stage1 builds a final Crystal
whose SHA256 matches the controlled current-compiler builds. The direct older
compiler comparison differs; see [reproducibility](reproducibility.md). The published
[receipt](../bootstrap/verification.json) records the tested source and toolchain.

## Build and verify

```sh
make bootstrap CXX=clang++
make check-bootstrap BOOTSTRAP_HOST=/path/to/trusted-crystal
```

Set `CRYSTAL_SRC` and `LLVM_CONFIG` when their defaults do not select the intended
source and libraries. `make bootstrap` needs no existing Crystal compiler.
It compiles upstream's C++ LLVM
bridge and links the snapshot against LLVM, Boehm GC, utf8proc and PCRE2.

The stage0 driver accepts source and output paths as positional arguments. It
uses upstream `Crystal::Compiler`, with optional interpreter, XML, OpenSSL,
compression and multithreading features disabled. Whole-program startup calls
upstream `Crystal.main`, including runtime initialization and shutdown.

`tools/bootstrap.py --stage0 PATH` builds stage1 and the final compiler without
a host compiler. Adding `--host PATH` also builds repeated trusted references
and a trusted self-build. It keeps output/cache paths, flags, metadata and source
inputs constant. Reference acceptance requires reproducible references and the
final binary's SHA256 matching both trusted references. A source-only run reports
`source_chain_built`; only a successful reference audit sets `stage0_verified`.

The runner gives stage0 a 512 MiB stack limit, recorded in the report and
configurable with `--stage0-stack-mib`. Unoptimized generated C++ uses large
frames during recursive type inference; the full compiler exceeds a 64 MiB
stack. This limit reserves address space, not an immediate 512 MiB allocation.
Trusted builds and subsequent Crystal binaries retain their normal limits.

## Snapshot format

The generator finishes strict lowering before publishing a staging directory by
rename. The manifest hashes every member. Shared declarations live in
`program.hpp`; sorted function bodies are partitioned into numbered units with
limits of 200 functions and 2 MiB, preserving individual functions intact.
Unsupported code is an error. The explicit research-only `--bootstrap` option
can emit throwing stubs and must not be used for a release snapshot.

The native builder checks member digests and compiles sequentially at `-O0`.
`NATIVE_OPTIMIZE=1` selects modest optimization, which reduces stack use but adds
native compilation time. Direct builder calls accept `--optimize 0`, `1` or `2`.
`--precompile-header` reduces repeated header parsing. `--build-dir` retains
completed objects with stamps covering the compiler, command and input hashes.
A linker response file avoids argument length limits; the executable is replaced
only after a successful link. No build step invokes Crystal.

## Focused probes and measurements

`make check-compiler` compares upstream Location, Token, lexer, parser, C callback
and whole-program runtime probes with the trusted compiler. Each snapshot is
regenerated twice, built with Crystal paths disabled, executed and checked for
identical observable output. Corrupting a member must prevent replacement of the
existing binary. Component probes use `-O1`. The runtime probe schedules a fiber
and waits for a subprocess; collections exercise array buffer movement and
record copies, while lexical-state probes check shell status and regex captures.

On Linux x86-64, upstream revision
`f4acc09db3edbc51cf526ba97808fbaa3e857ea9`, a full native GCC build took 1,071 seconds
and peaked at 1,144,372 KiB RSS for an earlier snapshot. The historical development snapshot's
Clang build took 467 seconds at 838,784 KiB peak RSS. Stage0 then built stage1
in 447 seconds at 5,955,924 KiB; stage1 built the final compiler in 63 seconds
at 4,059,136 KiB. Logs and metrics remain under `build/`.

The published receipt includes source checksums and native library versions;
[notices](../bootstrap/notices/README.md) retain upstream licensing information.
Guix packaging and targets beyond the tested Linux x86-64 ABI remain future work.
See [the update procedure](plan.md) and [runtime](runtime.md) for representation
boundaries.
