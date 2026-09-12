# Lowering and readability contract

Seed names the internal lowering conventions. The distributed format is readable
C++11 source; there is no separate language parser or independently bootstrapped
generator.

## Division of work

Upstream Crystal owns parsing, macro expansion, type inference, overload
selection, and generic instantiation. The generator follows resolved call targets
and concrete types. A documented runtime ABI adapts selected standard-library
operations to C++ helpers.

| Crystal construct | Output |
| --- | --- |
| Generic value struct | Named C++ struct with concrete fields. |
| Reference class | Traced allocation, pointer identity, and native inheritance. |
| Mixed union | Shared tagged representation with scalar bits or a traced pointer. |
| Dynamic call | Branches on resolved alternatives, with checked native casts. |
| Tuple / named tuple / static array | Native aggregate layout. |
| Resolved method | Named function with explicit receiver and arguments. |
| Captured mutable local | Shared GC cell. |
| Escaping proc | Thin callable handle with a traced lambda environment. |
| Synchronous yield block | Callable parameter with lexical control-flow tags. |
| Array | Traced header and buffer matching upstream fields; other methods lower upstream bodies. |
| Checked / wrapping integer arithmetic | Separate helpers with defined overflow behavior. |
| LLVM integer bit-count intrinsics | GCC/Clang builtins; no LLVM representation is emitted. |
| Raise / typed rescue | Rooted exception object with message and ancestry. |
| Return / break / next | Distinct lexical tags; rooted values bypass rescue. |
| Ensure | Cleanup after native unwinding; may replace pending control. |
| C call / callback | Foreign declarations, native calls and capture-free proc trampolines. |
| Symbol-to-enum coercion | Member-name matching, independent of symbol IDs. |
| Field initializer | Typed upstream initializer, executed during allocation. |
| Whole program | Upstream main wrapper calling the generated program body. |

See [Runtime](runtime.md) for the adapter list and ownership rules. Strict
translation fails before publication if it encounters an unsupported construct.
Compiler bootstrap execution is the scope of this implementation; compilable C++
alone does not establish that a runtime path behaves correctly.

## Semantics

Preserve value copying, reference identity, receiver mutation, evaluation order,
closure sharing, and cleanup. Materialize receivers and arguments before calls
because C++11 does not specify Crystal's evaluation order. Use unsigned arithmetic
or checked helpers rather than relying on signed overflow.

Functions containing explicit returns use rooted control transport so returns
can cross cleanup and synchronous block lambdas. Functions without explicit
returns use ordinary C++ returns. Break and next target their call and block,
respectively; rescue catches only Crystal exception transport. Loop break and
next have separate tags so cleanup runs before the loop resumes or exits. Forwarded blocks reuse the frontend's resolved proc and block metadata.

The native adapter boundary is intentionally smaller than Crystal's complete
runtime. Differential tests establish the supported behavior; neither a matching
method name nor compilable C++ establishes support for another overload.

## Readable generated source

Retain descriptive names for functions, fields, parameters, and locals. Encode
punctuation deterministically, avoid C++ reserved identifiers, and keep source
locations on generated functions. Canonicalize frontend temporary names rather
than emitting path-derived identifiers.

Preserve structured branches, loops, functions, and closure bodies. Keep runtime
helpers separately inspectable. Do not embed executable payloads, serialized
heaps, or LLVM output. Ordinary literals remain ordinary data.

Sort function declarations and definitions. Emit record layouts in dependency
order with forward declarations for reference cycles. Block specializations
are shared by typed definition and callable signature. Distinct typed definitions
with identical source signatures receive deterministic variant suffixes.
Adding an unused function may move source comments but must not change existing
executable output.

The examples contain explicit temporaries and control wrappers. Readability
needs continued review as compiler coverage grows: deterministic output and
source names alone do not make an entire compiler easy to audit.

Large snapshots can partition function bodies into deterministic C++ units.
See the [compiler workbench](compiler-translation.md) for publication, sequential
builds, memory measurements, and current full-compiler blockers.

## Native layout queries

The generator keeps `sizeof`, `instance_sizeof`, `alignof` and
`instance_alignof` as typed queries until C++ emission. Upstream cleanup normally
folds them using LLVM layouts, which can differ from generated C++ records and
unions. Using those constants for buffer copies or allocation truncates storage.
The generator-only [frontend hook](../generator/frontend.cr) preserves the
queries while retaining upstream validation. The generated stage0 compiler still
uses upstream's normal LLVM layout rules for programs it compiles.

## Lexical state

Block-local slots follow upstream `MetaVar` scope ownership, including
destructured arguments that appear as assignments after normalization. These
must shadow an outer variable with the same name. Captured outer variables
continue to refer to their existing slots.

Methods forward `$?` and `$~` through hidden pointer parameters described by
upstream's `special_vars` metadata. Shell status and regex captures therefore
update the caller's lexical frame.

## Nullable results

A nil-returning overload can have side effects even when dispatch widens its
result to a nullable reference. The conversion evaluates the call before
producing a typed null pointer. It must not replace the entire call with a null
literal.
