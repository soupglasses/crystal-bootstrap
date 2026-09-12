# Maintaining crystal-bootstrap

## Purpose and acceptance

Maintain a readable source bootstrap for the upstream Crystal compiler, suitable
for a Guix source-build chain, with little adaptation between Crystal releases:

```text
generated C++ + native dependencies -> crystal-stage0
crystal-stage0 + upstream source    -> crystal-stage1
crystal-stage1 + upstream source    -> final Crystal
```

- Prioritize reliable construction of the final upstream compiler. General
  Crystal compatibility and passing the entire upstream test suite are outside
  scope. Fix defects that affect this workload or undermine its reliability;
  do not accumulate unrelated language features.
- Final acceptance is the source chain matching a reproducible same-version
  upstream reference under an identical recipe. Direct cross-version `n-1 -> n`
  equality is not required. Do not equate source-generation determinism with
  final compiler reproducibility or claim arbitrary upstream download hashes.
- Any pushed Git tag names a release; its commit selects the Crystal target in
  `release.json`. Do not validate tag spelling or add a tag prefix. New
  releases may drop the older target. Prefer updating the small adapter over
  maintaining compatibility profiles or a version matrix.
- GitHub Actions builds are authoritative for released sources. Local generation
  produces an unpacked tree without packaging or attestations. The release job
  generates, packages and attests source; distributions build the compiler chain.
  Keep generated sources out of Git history. Historical receipts describe only
  their recorded development revision, not a newer release.

## Architecture to preserve

- Reuse upstream parsing, macro expansion, type inference, overload resolution,
  generic specialization, compiler algorithms, and reachable library bodies.
  Implement the native representation and lowering that upstream does not supply.
- Generate readable C++11 directly from the typed program. Seed names the
  lowering conventions and runtime ABI; it does not need another parser.
  Preserve descriptive names, source references, structured control flow, and
  inspectable runtime helpers. Do not distribute LLVM IR, serialized heaps, or
  executable payloads as substitutes for source.
- Allow an existing Crystal compiler to build and run the generator. Ordinary
  snapshot builds must use native tools only, with no generator prerequisite,
  hidden Crystal invocation, or historical compiler binary fallback.
- Retain upstream's LLVM backend inside stage0 to compile stage1. GCC and Clang
  are acceptable native compilers; TinyCC compatibility is not a requirement.
  Select dependencies that can be built through Guix's source bootstrap, and
  verify the package closure before claiming Guix support.
- Prefer small adapters over new subsystems. Identify adapted operations by
  resolved type and overload, not method name alone. Keep upstream integration
  changes narrow and explain the representation mismatch they address.

## Where to work

| Location | Responsibility |
| --- | --- |
| `generator/main.cr`, `generator/inventory.cr` | Frontend invocation, generation options, reachable-program inventory. |
| `generator/emitter.cr` | Type representation, specialization, C++ emission, deterministic snapshot publication. |
| `generator/frontend.cr` | Generator-only upstream hooks; layout queries must survive until C++ layout is known. |
| `generator/compiler.cr`, `generator/stage0.cr` | Upstream compiler imports and the minimal stage0 entry point. |
| `runtime/` | Maintained C++ runtime and representation adapters. |
| `tools/build_snapshot.py`, `tools/measure.py` | Sequential native construction, object reuse, resource measurements. |
| `tools/generate.py`, `tools/package_source.py` | Local generation and CI source archive packaging. |
| `tools/build_source.py`, `tools/bootstrap.py` | Offline release build driver and developer comparison harness. |
| `tests/fixtures/`, `tests/compiler/`, `tests/runtime/` | Semantic regressions, real compiler components, allocation pressure. |
| `bootstrap/` | Source notices and historical development receipts. |
| `release.json`, `.github/workflows/`, `packaging/` | One target pin, GitHub source releases, and distribution examples. |

Consult [lowering](docs/lowering.md) and [runtime](docs/runtime.md) before changing
representations. Use [the update procedure](docs/plan.md) for full publication and
[research](docs/research.md) for the Guix and related-project rationale.

## Implementing and diagnosing changes

- Inspect the pinned upstream implementation and resolved types before adding
  a workaround. Preserve evaluation order, value copying, aliasing, lexical
  state, and cleanup across the affected boundary. A discarded or nil result
  can still have side effects.
- Respect native layout and ownership. GC-managed payloads cannot depend on C++
  destructors for cleanup; pointers held in exception transport need explicit
  roots. Keep adapter layouts compatible with upstream methods that manipulate
  the same fields. Layout queries for generated C++ must not use LLVM constants.
- Diagnose the failing stage: generation, native compilation/linking, stage0
  execution, stage1 execution, or byte comparison. Preserve logs and inputs,
  reduce the failure, and add an observable regression when it protects behavior.
  A crash, timeout, and OOM require different remedies.
- Change maintained generator/runtime sources, then regenerate. Temporary edits
  to isolated generated output can help diagnosis, but must not become published
  fixes. Strict translation must fail on unsupported constructs; the generator's
  research-only `--bootstrap` stub mode is never acceptable release output.
- Keep the upstream checkout unchanged for normal work. Use a separate copy for
  diagnostic patches and preserve symlinks when copying shards: their `lib/`
  links can form cycles. Keep temporary compilers, objects, and caches in `build/`.

## Verification proportional to the change

Use the Makefile interfaces; set `CRYSTAL_SRC`, `CRYSTAL`, `LLVM_CONFIG`, and `CXX`
explicitly when their defaults do not identify the intended inputs. The default
upstream location is `../../crystal-lang/crystal`.

| Change or claim | Relevant verification |
| --- | --- |
| Lowering or adapter semantics | `make check CRYSTAL=/path/to/crystal` for differential fixtures. |
| Compiler integration, callbacks, collections, lexical state | `make check-compiler CRYSTAL=/path/to/crystal`. |
| Allocation or ownership | `make check-memory`, plus affected generated probes. |
| Locally generated example snapshots without Crystal | `make check-snapshot`. |
| Full candidate bootstrap | `make bootstrap SNAPSHOT=build/candidate CXX=clang++`. |
| Final binary equality | `make check-bootstrap BOOTSTRAP_HOST=/path/to/trusted-crystal`. |

- Test effects through realistic interfaces: output, exit status, retained values,
  collection under pressure, and actual compiler construction. Do not replace
  these with assertions about incidental emitter formatting or internal calls.
- Start with the affected probe. Run the full chain before declaring a changed
  full snapshot verified; do not repeat expensive successful builds without a
  new change or unresolved concern. Documentation-only changes need no compiler
  rebuild. Upstream tests may supply useful regressions, not a conformance gate.
- `check-bootstrap` uses the existing `build/crystal-stage0`; it does not rebuild
  it. Bind evidence to the candidate's actual manifest and binary hashes.
- Keep source, output, cache paths, metadata, flags, native dependencies and LLVM
  version controlled for binary comparisons. Clear compilation caches between
  compared builds. Report LLVM/path differences instead of assuming equivalence.
- Verify source-only operation with Crystal unavailable or blocked. A successful
  `source_chain_built` result is distinct from `stage0_verified`, which also
  requires the trusted comparison. Compilable C++ alone proves neither.

## Resources and publication

- Preserve deterministic partitioning and sequential native compilation to keep
  peak memory manageable. Use completed object caches during diagnosis, but
  invalidate affected artifacts when compiler, headers, commands, or dependencies
  change. Account for the separately built LLVM bridge when changing toolchains.
- Measure native build memory separately from stage0 runtime memory. The current
  `-O0` path needs a larger stage0 stack; use the runner's explicit stack limit.
  Optimization, heap limits, and stack limits are measured trade-offs, not fixes
  to apply blindly. Check disk capacity before duplicating full snapshots/caches.
- Generate candidates into fresh directories and compare two independent runs
  byte for byte, including manifests, with identical declared inputs. Source
  paths and macro inputs matter; do not claim relocation independence from a
  comparison that held them constant.
- Publish generated sources, runtime, pinned upstream/shards and notices together
  through the GitHub workflow in [the release procedure](docs/plan.md). Use
  GitHub-native attestations and immutable releases; do not build a parallel local
  provenance/signing system. Never attest a local archive as a GitHub build.
- Keep native consumer builds offline and independent of Git or preexisting
  Crystal. Preserve final upstream compiler features and allow distribution build
  settings. Do not run a full compiler/RPM build just to verify source packaging.
- Preserve prior local generation on failure. Keep different target outputs in
  separate directories; do not delete another version's output on regeneration.
