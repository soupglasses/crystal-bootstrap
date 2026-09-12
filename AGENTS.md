# Maintaining crystal-bootstrap

## Scope

Maintain a readable C++11 source bootstrap for the upstream Crystal compiler,
suitable for a Guix source-build chain. The generator reuses upstream's typed
program; native tools build stage0, stage0 builds stage1, and stage1 rebuilds
upstream Crystal.

The acceptance workload is reliable construction of the final upstream compiler.
Fix defects that affect that workload or threaten its reliability. General
Crystal conformance and the entire upstream test suite are outside scope.
Prefer a small adapter update over compatibility profiles or older targets
without a continuing purpose.

Final acceptance requires a reproducible same-version upstream reference and
matching final bytes under an identical recipe. Direct cross-version `n-1 -> n`
equality is not required. Source-generation determinism, a completed compiler
chain and final binary equality are separate claims. Historical verification records apply
only to their recorded source, snapshot and toolchain.

## Design constraints

- Reuse upstream parsing, macro expansion, typing, overload resolution, generic
  specialization, compiler algorithms and reachable library bodies. Implement
  the native representation and lowering upstream does not supply.
- Emit readable C++11 directly from the typed program. Seed names the lowering
  conventions and runtime ABI. Keep descriptive names, source references,
  structured control flow and inspectable helpers. LLVM IR, serialized heaps
  and executable payloads are not substitutes for source.
- An existing Crystal compiler may build and run the generator. Native snapshot
  builds must work without it, including without a hidden invocation or binary
  fallback. Retain stage0's upstream LLVM backend to compile stage1.
- GCC and Clang are acceptable native compilers; TinyCC support is not required.
  Select dependencies available through Guix's source bootstrap and verify the
  complete package closure before claiming Guix support.
- Keep adapters narrow. Identify operations by resolved type and overload, and
  explain the representation mismatch. Consult [lowering](docs/lowering.md)
  and [runtime](docs/runtime.md) before changing representations.

## Working on a change

The maintained implementation lives in `generator/` and `runtime/`. `tools/`
contains generation, native construction, packaging and comparison drivers.
Semantic fixtures, compiler component probes and allocation tests live under
`tests/`. `release.json`, `.github/` and `packaging/` define source publication
and distribution examples. `notices/` supplies notices included in source
archives; `docs/verification/` holds dated development evidence. Keep generated
sources out of Git.

Inspect the pinned upstream implementation and resolved types before adding a
workaround. Preserve evaluation order, copying, aliasing, lexical state and
cleanup. A discarded or nil result can still have side effects. Adapter layouts
must remain compatible with upstream methods that manipulate their fields;
generated C++ layout queries must survive frontend cleanup instead of becoming
LLVM constants. GC payloads cannot depend on C++ destructors, and native
exception transport needs explicit roots for managed pointers.

Diagnose the failing stage: generation, native compilation/linking, stage0,
stage1 or byte comparison. Preserve inputs and logs, reduce the failure, and
add an observable regression where it protects behavior. Distinguish crashes,
timeouts and OOMs before changing optimization or resource limits.

Change maintained sources, then regenerate into a fresh candidate directory.
Temporary generated-code edits may help diagnosis but cannot become release
fixes. Strict translation must fail on unsupported constructs; research-only
`--bootstrap` stubs are never acceptable release output.

Keep the normal upstream checkout unchanged. Use a separate copy for diagnostic
patches and preserve shard symlinks when copying: their `lib/` links can form
cycles. Keep temporary compilers, objects and caches in `build/`; check disk
capacity before duplicating full snapshots or caches. Preserve previous local
generation on failure and keep different targets in separate output directories.

## Verification

Use the [Makefile entry points](docs/compiler-translation.md). Set `CRYSTAL`,
`CRYSTAL_SRC`, `LLVM_CONFIG` and `CXX` when the defaults select unintended inputs.
The default upstream checkout is `../../crystal-lang/crystal`.

| Change | Check |
| --- | --- |
| Lowering or adapter semantics | `make check` |
| Compiler integration, callbacks, collections or lexical state | `make check-compiler` |
| Allocation or ownership | `make check-memory` and the affected generated probes |
| Example snapshots using native tools alone | `make check-snapshot` |
| Generation replacement, packaging or build entry points | `make check-release` |
| Unpacked source tree | `make bootstrap OUTPUT=build/generated/<version>` |
| Developer candidate and binary comparison | `make stage0 SNAPSHOT=build/candidate`, then `make check-bootstrap BOOTSTRAP_HOST=/path/to/trusted-crystal` |

Test observable behavior through realistic interfaces: output, exit status,
retained values, collection under pressure and compiler construction. Avoid
assertions about emitter formatting, internal calls or incidental command text.
Start with the affected probe and run the checks appropriate to the change.
Documentation edits need no compiler rebuild. Run the full chain before calling
a changed full snapshot verified; do not repeat successful expensive builds
without a new change or unresolved concern.

`check-bootstrap` audits the existing repository `build/crystal-stage0` without
rebuilding it. `make bootstrap` builds inside the selected unpacked tree. Bind
comparison evidence to the actual candidate manifest and binary hashes. The
developer audit uses reduced compiler features; it does not verify a different
distribution recipe.

For comparisons, control source/output/cache paths, metadata, flags, native
dependencies, LLVM and environment; clear caches between builds. Report differing
inputs instead of assuming equivalence. Verify source-only operation with Crystal
unavailable or blocked. `source_chain_built` records completion;
`stage0_verified` additionally requires the trusted comparison.

## Build resources and publication

Keep snapshot partitioning deterministic and native compilation sequential.
Completed object caches help diagnosis, but invalidate affected artifacts after
compiler, header, command or dependency changes. The separately built LLVM bridge
also needs rebuilding after a toolchain change. Measure native build memory and
stage0 runtime memory separately. Use the runner's explicit stage0 stack limit
for the unoptimized C++ build; treat optimization, stack and heap limits as
measured trade-offs.

Compare two independent generations byte for byte, including manifests, with
identical declared inputs. Source paths and macro inputs matter; a comparison
holding them constant does not prove relocation independence.

Follow [releasing](docs/releasing.md). Three-part numeric tags select commits;
`release.json` at those commits supplies the target list for the CI matrix and
release title. Keep release selection in the workflow tag filter. GitHub Actions
generates, packages and attests released sources. Local generation produces an
unpacked tree. Use GitHub-native attestations and
immutable releases, and never attest a local archive as a GitHub build.

Publish generated sources, runtime, pinned upstream/shards and notices together.
Consumer builds must be offline and independent of Git and preexisting Crystal.
Preserve the final compiler's upstream features and distribution build settings.
Packaging checks do not require a full compiler or RPM build.

## Documentation

Write for compiler engineers familiar with transpilation and bootstrapping.
Verify behavior against the code; fix implementation defects when needed instead
of documenting accidental behavior as a contract. Explain semantic constraints
and the reasons for design choices, including trade-offs and unresolved work. Keep build requirements, public references and
verification limits when editing for clarity. Avoid tutorials on familiar
concepts and file inventories that duplicate the source tree.

Keep build and diagnostic procedures in the verification guide, publication in
`docs/releasing.md`, design contracts in architecture/lowering/runtime, and dated
measurements with their verification records in `docs/reproducibility.md`.
Research should retain useful precedents, references and open constraints; remove settled
feasibility checklists and repeated progress reports. Update links when moving
content. GitHub is the target Markdown renderer; Mermaid is suitable for compiler
flows and comparisons.
