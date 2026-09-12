# Bootstrap runtime

The C++11 runtime uses Boehm GC for Crystal's object graph, traced allocations for
array backing storage, and native C++ exceptions for control transport. Boehm GC
is an external dependency; the runtime leaves global `operator new` unchanged.

## Ownership

| Value | Storage and lifetime |
| --- | --- |
| Reference class | Traced allocation with generated fields; aliases retain identity. |
| Mutable captured local | Traced cell shared by its closures and enclosing scope. |
| Proc | Callable handle with native-call and C-callback entry points; escaping environments are GC allocated. |
| Array | Traced header with upstream size, capacity, offset and buffer fields; backing storage is collectible. |
| Exception message | Atomic GC allocation; messages contain no heap pointers. |
| In-flight raise, return, break, next | Native exception with an explicitly rooted payload; the root is freed when transport is destroyed. |

Boehm documents that ordinary C++ allocations and native exception objects do
not reliably expose their contained pointers to the collector. Its supplied
allocator and temporary uncollectable allocations provide the needed tracing.
See the [collector interface](https://www.hboehm.info/gc/gcinterface.html).

GC payloads require trivial destruction. Generated class fields and closure
captures consist of scalar values and GC handles. Arrays intentionally need no
finalizer: their elements have trivial destruction and their allocator owns only
collectible memory. The runtime clears removed elements before `pop` and `clear`
so unused capacity cannot retain discarded objects. It uses byte-sized booleans
to avoid `std::vector<bool>` proxy storage. Appending accounts for the consumed
prefix of the buffer: upstream `shift` and `unshift` can move its logical start
without changing the total allocation capacity.

Resources such as files and foreign allocations require explicit cleanup.
Putting an owning `std::string`, default-allocated container, or `shared_ptr`
inside a GC object is unsupported. Upstream startup, fibers, signal handling
and subprocess I/O run through generated code. Native callbacks use C function
pointers; LLVM ownership remains governed by upstream wrappers.

## Runtime adapters

The generator preserves upstream type and overload resolution, then explicitly
adapts a small set of standard-library operations:

- `Array(T)` literals, capacity construction, indexing and assignment, push, pop,
  size, empty, clear, map, each, and Int32 sum.
- Array literal construction's `unsafe_build`, `to_unsafe`, and pointer indexing.
  These retain the unsafe pointer lifetime constraints around array growth.
- String-message exception construction, raising and reraising, ordered typed
  rescues, ancestry matching, and exception message access.
- Nullable reference `not_nil!`.
- Length-aware String operations, String::Builder, and forward Char::Reader operations.
- Integer-to-string conversion with base, precision, and uppercase options.
- Integer zero/population counts, mapping upstream intrinsic calls to GCC/Clang builtins.

These adapters cover representation boundaries. Other reachable methods lower
from upstream typed definitions, including Array overloads and custom exception
constructors. Exception subclasses retain generated state and ancestry.
Unions use one tagged representation with scalar bits and a traced pointer.
Generated reference classes use C++ inheritance and RTTI; dispatch branches use
resolved upstream alternatives and evaluate arguments once. This avoids a native
template instantiation for every combination of union alternatives. Scalar and
reference unions have differential probes. Mutable value types boxed inside
unions still need copy-semantics work; arbitrary polymorphic use of native
String/Array/IO adapters is not supported.

Strings store a byte pointer and explicit length, preserving embedded NUL bytes.
`String::Builder` uses a traced byte buffer and inherits generated IO.
`Char::Reader` decoding and character encoding reuse [utf8proc's C API](https://juliastrings.github.io/utf8proc/doc/utf8proc_8h.html).
The adapter exposes byte positions, character widths, invalid-byte state, and
forward reading. It does not implement the entire String, Unicode, or IO API.
Integer formatting uses bounded digit storage and a single GC allocation for
precision padding. The generator only substitutes the supported upstream
integer-formatting signature; IO formatting overloads still require lowering.

## Blocks and cleanup

Synchronous blocks borrow a stack lambda. Escaping procs capture traced cells;
only locals marked captured by upstream need those cells. Capture-free procs
use native function pointers without heap environments. Ordinary locals and
direct returns remain on the native stack, including inside GC callbacks.

Method returns, block breaks, and block nexts have distinct lexical tags and
rooted payloads. Rescue clauses catch only raised Crystal exceptions. `ensure`
saves pending transport, finishes native unwinding, executes cleanup, then resumes
the pending operation. This lets cleanup replace an exception or return without
throwing from a destructor during unwinding. Rescue `else` executes outside the
rescue scope.

## Memory validation

`make check` compares generated programs with the pinned upstream compiler.
`make check-snapshot` runs their native builds without Crystal. Both also run
[the runtime stress program](../tests/runtime/memory.cpp) with the selected C++
compiler and available Clang at `-O0` and `-O2`.

`make check-memory` runs the standalone stress test with the selected C++ compiler.

The stress program caps the GC heap at 32 MiB and allocates over 1 GiB cumulatively.
It maintains a small live set while discarding cyclic graphs, closures in arrays,
boxed procs held in unions, and replaced return signals. Pending raises and
returns survive forced collections while held in ordinary C++ exception storage.
The test checks retained values and reports allocation and heap counters in
`build/check/{differential,snapshot-only}.json`.

[The generated allocation-pressure fixture](../tests/fixtures/gc_pressure.cr)
additionally exercises the emitter's object layouts and closure captures under
the same heap limit. The limit belongs to the tests, not the runtime defaults.

The bounded-heap result applies to collector storage in these test workloads.
It does not bound process RSS, frontend specialization, generated source size,
native compiler memory, LLVM allocations or the live graph of a full compiler.
See [development build results](reproducibility.md) for measured compiler memory
use and the stage0 stack limit.
