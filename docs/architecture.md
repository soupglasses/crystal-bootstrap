# Bootstrap architecture

The transpiler adds a C++ backend to upstream Crystal's frontend. It runs
semantic analysis with LLVM code generation disabled, then lowers the typed
compiler and its reachable library and shard bodies to C++11. Seed is the name
used in the implementation for this lowering and its runtime ABI.

## Frontend boundary

Parsing, macro expansion, type inference, overload resolution and generic
specialization all run through upstream code. The C++ backend works from the
resulting concrete types and resolved calls. It implements native layouts,
dispatch, primitives, closures and control flow as described in the
[lowering contract](lowering.md).

This depends on compiler internals rather than a stable frontend API, so an
upstream update may require changes to the adapter. The original investigation
used
[`Compiler#compile_configure_program`](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/src/compiler/crystal/compiler.cr)
and [`Program#semantic`](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/src/compiler/crystal/semantic.cr).
Generator-only hooks preserve layout queries until the C++ layout is known.
Stage0's LLVM backend keeps upstream's layout rules for the programs it compiles.

The snapshot must include initializers, runtime hooks, callbacks and macro
dependencies as well as resolved method calls. A `require` scan cannot establish
that closure. Library bodies have two roles: their C++ translation runs inside
stage0, and their original source is compiled into stage1. Expanding the
compiler's own macros during generation leaves its macro-processing algorithms
in stage0, ready to compile subsequent programs. Generic specialization works
the same way.

## Compiler chain

| Stage | Construction and role |
| --- | --- |
| Generator | Built and run by an existing Crystal compiler; emits the source snapshot. |
| `crystal-stage0` | Built from C++ and native dependencies; runs upstream compiler logic and its LLVM backend. |
| `crystal-stage1` | Upstream compiler built by stage0 through LLVM. |
| Final `crystal` | Same upstream source rebuilt by stage1, with the distribution's final build settings. |

Ordinary snapshot builds use native tools without invoking the generator or an
installed Crystal. The intermediate compilers omit optional features to reduce
the bootstrap workload; the distribution driver builds the final compiler with
upstream features enabled.

The stage0 entry point accepts source and output paths and uses upstream's
compiler API. It runs upstream initialization and shutdown. Fibers, subprocess
I/O and signal handling remain reachable even with multithreading disabled.

## Native implementation

C++11 gives the runtime exception transport and lambdas that can be compiled
with GCC or Clang. Boehm GC traces the Crystal object graph. The
[runtime adapters](runtime.md) handle operations whose upstream implementation
assumes a different layout or ownership model. Emitting C++ directly also avoids
a separate interpreter or parser for Seed.

Stage0 links LLVM to compile stage1. The native build compiles upstream's C++
LLVM bridge against the selected headers and libraries. Boehm GC, utf8proc and
PCRE2 supply collection, Unicode operations and regex support. The final
compiler needs its additional upstream libraries, listed in the
[archive README](../packaging/source-README.md). The complete Guix dependency
closure remains unverified; [research](research.md) records the rationale.

## Generation inputs and determinism

Each snapshot contains the generated units, shared declarations and runtime
headers, with a manifest of their hashes. The surrounding source tree includes
pinned upstream and shards, notices, build tools and `SOURCE.json` with target
and generation settings. [Releasing](releasing.md) describes archive publication and attestation.

The generator uses stable names and traversal order, and preserves source
locations on generated functions. It normalizes frontend temporary identifiers
and anonymous macro comments to remove host object addresses. The two generation
runs use the same source paths and declared environment, so their comparison
does not test independence from checkout location.

Macros can read files and environment variables, run commands, and
[compile helper programs](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/src/compiler/crystal/macros/macros.cr).
Changes to these inputs need review alongside source and toolchain changes.
The snapshot manifest and `SOURCE.json` do not capture every possible external
macro input or lock the distribution's native dependencies.

Compiler verification additionally controls LLVM, dependencies, flags, metadata,
source/output paths and cleared caches. The [verification guide](compiler-translation.md)
defines the checks; [historical results](reproducibility.md) record the tested
configuration and its limits.
