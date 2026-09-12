# Source-generation feasibility report

## Result

The generator emits readable C++11 directly from upstream's typed program.
The runtime now covers GC-managed reference objects, arrays, captured cells and
procs, rooted exception transport, typed rescues, cleanup, and synchronous yield
blocks, tagged unions, inherited dispatch, tuples, and UTF-8 text. Real upstream
Location, Token, lexer and parser components run through split C++ snapshots. No LLVM IR is
translated or embedded. See the [compiler workbench](compiler-translation.md)
for full native builds and compiler-chain verification.

The [runtime report](runtime.md) describes ownership, adapters, memory tests, and
remaining limitations. The full historical development snapshot now builds stage1 and the
final compiler. Its final hash matches repeated current-compiler reference
builds and the self-build of Crystal 1.21's output. See the
[reproducibility report](reproducibility.md) for the direct `n-1` difference.

## Test configuration

Tested on Linux x86-64 on 2026-09-12:

- Upstream Crystal: `f4acc09db3edbc51cf526ba97808fbaa3e857ea9`, `1.22.0-dev`.
- Generator host: [Crystal `1.21.0`](https://github.com/crystal-lang/crystal/releases/tag/1.21.0)
  (`57cf7da50`), using the local upstream source
  and its populated shard directories. The official host archive's SHA-256 was
  verified against its release metadata:
  `744561ee3cee1b06d106cf9ae99b8064b4e017518ac414d6dd23cfafe36560c9`.
- Reference: a compiler built from that same upstream checkout, linked with
  LLVM `22.1.8`. The checkout was not modified.
- UTF-8 decoding: system utf8proc 2.11.3.
- Boehm GC: system `bdw-gc` 8.2.12, using its C++ allocator header.
- Native compilers: GCC `16.2.1 20260810` and Clang `22.1.8`, both using C++11 at
  `-O0` and `-O2`. This does not establish an oldest supported compiler version.

Generate the examples with `make regen` under `build/examples`.
Their local manifest records the revision,
generator-host version, generation environment, and local source/output hashes.
It is an example manifest, not a complete native-dependency or upstream-source
closure lock.

## Behavioral checks

| Probe | What it exercises | Result |
| --- | --- | --- |
| [loop control](../tests/fixtures/loop_control.cr) | Loop break values and next through ensure | Matches reference |
| [integer text](../tests/fixtures/integer_text.cr) | Signed/unsigned limits, formatting options, invalid base | Matches reference |
| [bit counts](../tests/fixtures/bit_counts.cr) | Leading/trailing zero counts and population count | Matches reference |
| [unions](../tests/fixtures/unions.cr) | Scalar union storage and narrowing | Matches reference |
| [dispatch](../tests/fixtures/dispatch.cr) | Inherited fields and dynamic receiver dispatch | Matches reference |
| [text](../tests/fixtures/text.cr) | Embedded NUL bytes, UTF-8 character counts and reader positions | Matches reference |
| [tuples](../tests/fixtures/tuples.cr) | Constant tuple and enum extraction | Matches reference |
| [arrays](../tests/fixtures/arrays.cr) | Native Array adapter: literals, aliasing, mutation, Bool storage, map, each and sum | Matches reference |
| [heap objects](../tests/fixtures/heap_objects.cr) | Reference identity, cycles, nullable links, and escaping procs held in arrays | Matches reference |
| [GC pressure](../tests/fixtures/gc_pressure.cr) | More than 1 GiB cumulative allocation under a 32 MiB heap limit, preserving a live closure | Matches reference |
| [typed exceptions](../tests/fixtures/typed_exceptions.cr) | Ordered typed rescues, subclass ancestry, reraising, overflow, bounds errors and rescue else | Matches reference |
| [yield blocks](../tests/fixtures/yield_blocks.cr) | Mutation and return, break and next through ensure | Matches reference |
| [collection](../tests/fixtures/collection.cr) | A two-element `PairBuffer(T)`, mapping to Int32 and Bool specializations, captured offset, original value preservation | Matches reference |
| [closures](../tests/fixtures/closures.cr) | Escaping mutable capture, copied proc sharing state, independent counters, sibling closures and enclosing-scope mutation | Matches reference |
| [cleanup](../tests/fixtures/cleanup.cr) | Normal completion, early returns, rescued errors, nested cleanup order, cleanup exception overriding a return | Matches reference |
| [replacement exception](../tests/fixtures/replacement_exception.cr) | An exception raised during cleanup replaces an already pending exception | Matches exception message and exit status |
| [arithmetic](../tests/fixtures/arithmetic.cr) | Checked/wrapping overflow, left-to-right argument and receiver evaluation, a loop | Matches reference |

Successful probes compare stdout, stderr, and exit status. The unhandled-error
probe compares the exception message and status: the prototype intentionally
omits Crystal's backtrace and diagnostic formatting.

Every fixture is generated in separate processes under different absolute paths,
with byte-identical output. Adding an unrelated definition preserves generated
code except source-location comments. Snapshot builds compile the checked-in
examples without invoking Crystal or requiring the upstream source or LLVM.

The reproducible entry points are `make check`, `make regen`, and
`make check-snapshot`, documented in the [README](../README.md). Local test
reports are written to `build/check/differential.json` and
`build/check/snapshot-only.json`.

## Findings that affect the design

**Use explicit traced ownership.** GC-allocated environments replace
`std::function` and `shared_ptr`. Array headers and backing allocations are
traced; removed references are cleared. Native exception storage holds temporary
roots so values survive collection while transport is pending, and releases
those roots when transport is handled or replaced.

**Use native helpers where their boundary is small.** Array operations have
small adapters over traced raw buffers. Other reachable overloads lower from
upstream typed definitions. Custom exception constructors and state follow
upstream code with a shared runtime exception representation. The boundary is documented in [Runtime](runtime.md).

**Ensure must run after native unwinding.** A throwing C++ destructor cannot
replace an exception already being unwound. The cleanup helper saves pending
transport, executes cleanup, then resumes it. Return, break and next carry
separate lexical tags and bypass typed rescues.

**Evaluation order and specialization need explicit handling.** Receivers and
arguments are materialized in Crystal order. Blocks with the same signature may
have distinct upstream typed definitions, so their generated names also retain
a deterministic call-site identity.

## Memory results

The four native runtime stress configurations allocated approximately 3.15 GB
cumulatively under an enforced 32 MiB GC heap limit. Final collector heap sizes
ranged from 3,817,472 to 4,132,864 bytes in the differential run. The generated Crystal allocation-pressure
fixture also passed against the reference compiler and all four native builds.
The standalone runtime test passed Clang's undefined-behavior sanitizer as well.

A negative probe rejects executable type-body side effects in fixture entry
mode. Array construction, captured blocks, custom exception construction and
128-bit arithmetic now have positive differential coverage. Both proc and
yield-block naming remain stable when an unrelated definition is added.

## Full compiler result and limits

The strict snapshot contains 72,613 definitions in 418 C++ translation units,
with no unsupported paths. Independent regeneration produced identical bytes
for all 423 members, including the manifest. The native Clang build took 467
seconds at 838,784 KiB peak RSS. Stage0 built stage1 in 447 seconds at 5,955,924
KiB peak RSS; stage1 built the final compiler in 63 seconds at 4,059,136 KiB.
A separate source-only run completed with a failing `crystal` command on PATH.

The [published receipt](../bootstrap/verification.json) binds the final matching
hash to the source snapshot, native build, source checksums and dependencies.
The [reproducibility report](reproducibility.md) records the distinction between
a direct older-compiler build and its current-compiler self-build. These results
do not establish identical bytes across different LLVM versions or paths.

Guix packaging and other target ABIs remain unverified. General Crystal
conformance is outside scope; the complete compiler chain is the acceptance
workload. The runtime measurements describe that workload, not a universal bound
on future compiler source versions or programs.
