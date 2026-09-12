# Bootstrap design rationale

The bootstrap starts at a native C++ toolchain. C++11 supplies exception
transport and lambdas, while upstream Crystal supplies the frontend and compiler
algorithms. This leaves native layout and lowering as the main implementation
work. [Architecture](architecture.md) describes that boundary.

## Guix constraints

[GNU Mes](https://www.gnu.org/software/mes/) documents an earlier
[bootstrap path](https://www.gnu.org/software/mes/manual/html_node/The-Mes-Bootstrap-Process.html)
through M2-Planet, Mes/MesCC and TinyCC toward a GNU toolchain. Starting this
project at GCC lets us use C++11. Targeting TinyCC or M2-Planet's restricted C
would mean implementing more of the runtime ourselves. GCC's
[bootstrap build](https://gcc.gnu.org/install/build.html) and
[language configuration](https://gcc.gnu.org/install/configure.html) describe
the requirements for that choice.

We still need to verify the complete Guix package closure: LLVM and its C++
runtime, Boehm GC, utf8proc, PCRE2, the final compiler's optional libraries, and
the build tools. Using LLVM's C API does not remove its native implementation
from the dependency graph. The local compiler-chain results establish a build
on the tested host, not availability of all these inputs through Guix. The
[Mes deployment discussion](https://www.gnu.org/software/mes/manual/mes.pdf)
explains where Guix's process differs from live-bootstrap.

## Related projects

[Nim's csources](https://github.com/nim-lang/csources_v2) distributes generated
native source to bootstrap a self-hosted compiler. That is the publication model
used here. [mrustc](https://github.com/thepowersgang/mrustc) also builds an
upstream compiler through generated C, but implements its own Rust frontend in
C++. Its focus on bootstrap correctness, with limited diagnostics, is relevant
to this project. Reusing Crystal's frontend avoids maintaining that part of a
second compiler across upstream versions.

[Camlboot](https://github.com/Ekdohibs/camlboot) takes an interpreter approach:
an OCaml interpreter written in MiniML, built with a MiniML compiler written in
Guile Scheme. The authors' [paper](https://arxiv.org/abs/2202.09231) describes the
bootstrap and its trust implications. [Zig's redesign](https://ziglang.org/news/goodbye-cpp/)
uses a generated WebAssembly snapshot and a small C translator/runtime. These
are useful examples of reducing the implementation needed to run a compiler;
Crystal-bootstrap instead translates the compiler bodies into native source.

[LLVM-CBE](https://github.com/JuliaHubOSS/llvm-cbe) translates LLVM IR to C. We
generate from the typed Crystal program to preserve source definitions and
structured control flow in the output. LLVM is still needed inside stage0
to compile the next stage.

## Maintenance risk

The original investigation used Crystal revision
[`f4acc09db3edbc51cf526ba97808fbaa3e857ea9`](https://github.com/crystal-lang/crystal/tree/f4acc09db3edbc51cf526ba97808fbaa3e857ea9).
The [architecture](architecture.md) records the frontend integration and macro
inputs; the [development results](reproducibility.md) record the completed chain.

Updates need particular attention to upstream internal APIs, primitives and
representation assumptions. Keeping the adapter small limits that work, but
only a compiler-chain build and comparison can verify an updated target.
Language support grows as the compiler workload requires it or when a defect
threatens that workload's reliability.
