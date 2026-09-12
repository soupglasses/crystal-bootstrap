# crystal-bootstrap

Bootstrap upstream Crystal from readable generated C++11, without installing a
historical Crystal compiler. **Release `2026.09.12` targets Crystal `1.21.0` on
Linux x86-64 with LLVM 20.** Each bootstrap release targets one Crystal version;
a later release can replace that target without retaining compatibility branches.

```text
Maintainer / GitHub Actions:
  Crystal source → upstream typed AST → generated C++ sources

Distribution build service:
  C++ sources + native libraries → crystal-stage0
  crystal-stage0 + upstream source → crystal-stage1
  crystal-stage1 + upstream source → Crystal
```

The Crystal-written transpiler reuses upstream parsing, macro expansion, type
inference and compiler implementations. We maintain C++ lowering and runtime
adapters, collectively called Seed. There is no separate parser or LLVM-to-C
conversion. Stage0 retains upstream's LLVM backend to build stage1.

## Generate locally

Install Python 3.12+, Make, a compatible LLVM development package, and the native
libraries required by the generator host (Boehm GC and PCRE2). Run:

```sh
make generate LLVM_CONFIG=llvm-config-20
```

This downloads the inputs pinned in [release.json](release.json), including an
official Crystal host used **only for generation**. To use an existing host:

```sh
make generate CRYSTAL=/path/to/crystal LLVM_CONFIG=/path/to/llvm-config
```

Output goes to `build/generated/1.21.0/`: generated C++, upstream/shard source,
notices and an offline build driver. Generation runs twice and requires identical
bytes with no unsupported stubs. Rerunning the command replaces the directory
only after success. `OUTPUT=/path/to/output` overrides the destination; separate
version directories can coexist. Local generation does not create a ZIP or
attestation. Generated files stay out of Git.

## Published sources and distribution builds

The [source release workflow](.github/workflows/source-release.yml) runs the same
`make generate` command on GitHub's runners, packages its output, and publishes a
ZIP, `SHA256SUMS` and a GitHub artifact attestation. GitHub builds are the release
authority. See [release and verification instructions](docs/plan.md).

After verifying and extracting a release ZIP:

```sh
make CXX=clang++ LLVM_CONFIG=llvm-config-20
./build/crystal --version
```

The extracted tree builds offline with native tools and libraries, without Git,
a generator or an existing Crystal executable. See its README for dependencies.
The [RPM spec](packaging/crystal-bootstrap.spec) is an illustrative OBS input
recipe, not a published or validated RPM package.

The release workflow verifies deterministic **source generation**. Distribution
build services perform and validate the compiler chain. Earlier experiments
completed the chain for a development revision with LLVM 22; those
[historical measurements](docs/reproducibility.md) do not certify this 1.21
release. Final acceptance is equality with a reproducible, same-version upstream
reference under matching build conditions. Cross-version `n-1 → n` equality is
not required, and arbitrary upstream download hashes are not a comparison recipe.

## Develop the transpiler

`make check CRYSTAL=/path/to/crystal CRYSTAL_SRC=/path/to/crystal-source` runs
differential fixtures. `make check-compiler` exercises real compiler components;
`make check-memory` checks allocation pressure. `make regen` refreshes examples
under `build/examples`, and `make check-snapshot` tests those examples using only
native tools. `make check-release` checks generation replacement and packaging.
These developer checks use local dependencies and do not download inputs.

- [Architecture](docs/architecture.md), [lowering](docs/lowering.md), [runtime](docs/runtime.md)
- [Compiler translation](docs/compiler-translation.md)
- [Guix and related-project research](docs/research.md)
