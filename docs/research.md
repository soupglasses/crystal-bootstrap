# Bootstrap research

Sources reviewed on 2026-09-12. These precedents inform the design; they do not
establish that Crystal's complete compiler can already follow this path.

## Guix and the implementation language

GNU Mes combines a small Scheme interpreter written in restricted C with a C
compiler written in Scheme. Mes can be built using M2-Planet and mescc-tools;
Mes/MesCC then build a bootstrappable TinyCC, leading to a C toolchain capable
of building later GNU tools. See the [GNU Mes project](https://www.gnu.org/software/mes/)
and [bootstrap process](https://www.gnu.org/software/mes/manual/html_node/The-Mes-Bootstrap-Process.html).
This is a simplified compiler spine, not the full dependency graph.

| Candidate | Fit for this project | Decision |
| --- | --- | --- |
| C or C++ compiled by GCC | Existing source-bootstrap toolchain and native runtime facilities. | C++11 is the prototype output; GCC is the baseline. |
| C supported by TinyCC | Earlier foothold, but fewer language/runtime facilities. | Optional; compatibility is not a project requirement. |
| M2-Planet's C subset | Earlier foothold, but a deliberately restricted C language and environment. | Defer; avoid constraining the project before proving the compiler path. |
| Scheme on Mes | An existing early language, but Mes supports the subset needed for MesCC rather than arbitrary Scheme software. | Viable alternative, not an assumption that Guile code runs on Mes. |
| Scheme on Guile | Convenient compiler implementation language with a relevant Camlboot precedent. | No separate subset compiler is needed in the revised design. |
| Crystal | Direct access to upstream parser and semantic analysis. | Preferred generator language; intentionally a maintainer dependency. |

[M2-Planet](https://github.com/oriansj/M2-Planet) describes itself as a
self-hosting compiler for a C subset.
[TinyCC](https://bellard.org/tcc/tcc-doc.html) implements substantial C99 support.
Neither compiler directly parses Crystal. Generating native source from the
upstream typed program supplies that bridge. Requiring TinyCC would add runtime
work that a later GCC C++ toolchain can avoid. GCC documents its native
[bootstrap build](https://gcc.gnu.org/install/build.html) and
[language configuration](https://gcc.gnu.org/install/configure.html).

The [Mes manual](https://www.gnu.org/software/mes/manual/mes.html) also documents
its restricted Scheme support and Nyacc-based C compiler. Nyacc or yacc can save
parser work; neither provides Crystal type inference or macro semantics.

Adopt explicit inputs, pinned toolchains, small stage boundaries, and rebuild
checks. Verify platform support and the complete Guix recipe when packaging;
avoid treating a schematic chain as proof that every native dependency is
available at its earliest stage. The Mes manual's
[deployment discussion](https://www.gnu.org/software/mes/manual/mes.pdf) distinguishes
Guix from live-bootstrap, including generated-tool bootstrapping details.

## Closest precedents

**Camlboot** is the closest architectural example for a small language beneath
a larger compiler. It implements an OCaml interpreter in MiniML, then compiles
MiniML using a compiler written in Guile Scheme. This demonstrates a practical
subset-plus-bootstrap arrangement, but its interpreter is a maintained source
implementation, not an automatically lowered copy of the full compiler.
See the [project](https://github.com/Ekdohibs/camlboot) and the authors'
[paper](https://arxiv.org/abs/2202.09231). Reusing a mature language frontend and
runtime is more relevant here than reproducing its precise execution strategy.

**Nim's csources** demonstrates distributing generated C source for bootstrapping
a self-hosted compiler. This is closely aligned with allowing a current compiler
to prepare the source snapshot. See
[csources_v2](https://github.com/nim-lang/csources_v2). This project similarly
distributes generated native source, choosing C++11 to reuse closure and exception
facilities. Seed now describes internal lowering conventions rather than a
separate serialized language.

**Zig** replaced its C++ bootstrap implementation with a generated WebAssembly
snapshot and a small C translator/runtime. Its
[design account](https://ziglang.org/news/goodbye-cpp/) illustrates keeping the
bootstrap executor small while regenerating the compiler payload. The checked-in
Wasm input differs from the readable source snapshot proposed here.

**mrustc** is an alternative compiler written in C++ that emits C and builds
upstream Rust. Its [README](https://github.com/thepowersgang/mrustc) describes
bootstrap-focused correctness and reduced diagnostic ambitions. It shows that
a slow bootstrap compiler can be useful, while its separate frontend and
version-specific support illustrate maintenance this project hopes to avoid.

**LLVM-CBE** already translates LLVM IR to C. Its
[README](https://github.com/JuliaHubOSS/llvm-cbe) documents support tied to a
particular LLVM version (LLVM 20 when reviewed). It is excluded from the proposed
generation path: this project requires readable source that retains a direct
relationship to Crystal definitions and control flow. Translating lowered LLVM
IR back to C does not serve that source-level design. No LLVM-CBE experiment is
required by the plan.

## Evidence from the Crystal checkout

Investigation used revision
[`f4acc09db3edbc51cf526ba97808fbaa3e857ea9`](https://github.com/crystal-lang/crystal/tree/f4acc09db3edbc51cf526ba97808fbaa3e857ea9),
whose `src/VERSION` is `1.22.0-dev`.

- [`shard.yml`](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/shard.yml)
  declares Crystal `>= 1.13.0`, also reflected in the warning in
  [`src/compiler/requires.cr`](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/src/compiler/requires.cr).
  The existing dependency is a compatibility ladder, not necessarily one build
  for every intervening release.
- [`semantic.cr`](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/src/compiler/crystal/semantic.cr)
  performs whole-program typing and cleanup. This is the proposed generator
  integration point; it is not a stable public serialization API.
- [`exception.cr`](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/src/compiler/crystal/codegen/exception.cr)
  and [`primitives.cr`](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/src/compiler/crystal/codegen/primitives.cr)
  show substantial lowering for exceptions, closures, overflow, and other
  primitives. A syntax-only transpiler would miss essential behavior.
- [`lib_llvm.cr`](https://github.com/crystal-lang/crystal/blob/f4acc09db3edbc51cf526ba97808fbaa3e857ea9/src/llvm/lib_llvm.cr)
  derives configuration and link flags through compile-time commands. These
  must be controlled inputs to deterministic generation.

The principal feasibility risk is faithfully lowering this typed program and
runtime into a small native implementation. The principal maintenance risk is
upstream internal API and primitive changes. A compact adapter, explicit
coverage inventory, and end-to-end bootstrap tests address these risks more
directly than designing a broad new language first.
