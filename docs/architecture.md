# Bootstrap architecture

## Boundary and responsibilities

An existing Crystal binary may build and run the generator. Maintainers publish
its deterministic source output; builders compile that snapshot with an existing
source-bootstrappable C++ toolchain. Independent regeneration is not required.

| Component | Responsibility |
| --- | --- |
| `crystal-to-cpp` | Reuse the pinned Crystal frontend; lower resolved types, functions, and primitives to readable C++11. |
| Seed | Internal lowering conventions and runtime operations; no serialized language or independent parser. |
| Bootstrap snapshot | Generated compiler and reachable library source, runtime, configuration, and provenance. |
| `crystal-stage0` | Native compilation of the snapshot; runs upstream compiler logic, including its LLVM backend. |
| `crystal-stage1` | Normal upstream compiler built by stage0 through LLVM. |
| Final `crystal` | Rebuild of the same upstream source with stage1, compared against a trusted build. |

Full generated compiler snapshots compile and link with GCC and Clang. The
historical development snapshot completes the compiler chain and matches the trusted
self-build; see [reproducibility](reproducibility.md) for the direct `n-1`
comparison. The locally generated examples are smaller regression programs. Stage names are local to this
project and unrelated to the [Stage0 project](https://github.com/oriansj/stage0-posix).

## Direct source generation

At the investigated upstream revision,
[`Compiler#compile_configure_program`](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/src/compiler/crystal/compiler.cr)
parses, runs `Program#semantic`, then generates code. Setting `no_codegen` lets
the prototype access the typed result without generating LLVM IR for its input.
The generator executable itself is compiled normally by Crystal.

The typed result exposes instantiated methods and resolved call targets. It
still needs explicit lowering for layouts, dispatch, primitives, closures, and
control flow. This is a backend project, not a syntax substitution tool.

For a complete snapshot, generate the compiler and its reachable standard
library and shard implementations together. Include initializers, runtime
hooks, foreign callbacks, and macro dependencies. A scan of `require` statements
cannot establish this closure. The original standard library remains input to
stage1 compilation; its generated counterpart supplies stage0's execution needs.

Expanding the compiler's own macros and specializing its generics during snapshot
creation preserves the compiler algorithms that process macros and generics in
future input programs. There is no need to maintain a separate Crystal frontend.

## Why C++11

A separate Seed syntax and parser add a second source format to maintain. Direct
source emission removes that layer. C++11 also supplies exception transport and
closure facilities that would otherwise require a custom C runtime. GCC is the
baseline toolchain; TinyCC compatibility is not a requirement.

The runtime uses Boehm-allocated closure environments and shared GC cells, with
traced array buffers matching the upstream fields. Native raises and nonlocal control carry explicit
temporary GC roots. An explicit cleanup helper executes `ensure` after native
unwinding, allowing cleanup to replace a pending exception or return.

A small documented set of standard-library methods uses native runtime adapters.
This reduces bootstrap implementation work while retaining upstream semantics
as the differential test reference. The supported ABI and memory-pressure tests
are described in [Runtime](runtime.md). Foreign callbacks, field initialization and complete compiler source translation
are implemented. Runtime startup and the full compiler chain have passed the configured build.

## Native dependencies

Stage0 links compatible LLVM libraries and preserves upstream's
LLVM backend to build stage1. LLVM does not produce the snapshot. Removing LLVM
from stage0 would require additional backend integration and is outside the
first bootstrap milestone.

Select one Linux x86-64 libc/LLVM configuration initially. LLVM's C API still
requires its native implementation and relevant C++ runtime. The native build compiles upstream
`src/llvm/ext/llvm_ext.cc` with the selected LLVM headers and links the resulting
object with LLVM; no Crystal-produced object is needed. Reuse Boehm GC and native libraries where their semantics fit. UTF-8 character
decoding uses utf8proc, a C library; the exact Guix package closure still needs
verification for a release.

The stage0 driver uses upstream's compiler API with explicit optional-feature
flags. It accepts a source path and an output path. Disabling multithreading
does not establish that fibers and process I/O are unnecessary. Linux's current
default event loop is epoll, so libevent is not an unconditional requirement.

## Reproducibility

A full snapshot manifest must record source and shard digests, generator version,
host Crystal version, runtime ABI, target layout, native dependencies, flags,
declared environment and build epoch, macro command inputs, and output hashes.

Use stable names and traversal, deterministic file ordering, relative source
references, and canonicalized upstream temporary identifiers. Anonymous macro comments use their original source locations, removing host
object addresses. The full snapshot still treats source paths as declared inputs;
normalization across different checkout paths remains release work.
Generate twice in different directories and compare complete output bytes.
Different declared target configurations may produce different snapshots.

Macros may inspect files, the environment, or subprocess output, and
[`macro_compile`](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/src/compiler/crystal/macros/macros.cr)
can compile helper programs. Those inputs need capture and verification for a
full compiler snapshot; the current fixtures do not establish that coverage.

Normal snapshot builds must neither run the generator nor find an installed
Crystal as a fallback. Regeneration with stage1 is an explicit consistency
check. It is not an independent-origin requirement.
