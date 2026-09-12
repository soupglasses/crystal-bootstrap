# Crystal bootstrap sources

This directory contains readable generated C++11, its runtime, pinned upstream
Crystal and shard sources, and the native build driver. `SOURCE.json` records
the target and generation settings. No Crystal executable is required to build it.

On Linux x86-64, install a C/C++ compiler, Python 3, Make, pkg-config, the LLVM
major specified in `SOURCE.json` (development libraries and tools), Boehm GC,
utf8proc, PCRE2, libxml2, OpenSSL, zlib and readline development packages. Then:

```sh
make CXX=clang++ LLVM_CONFIG=llvm-config-20
./build/crystal --version
```

The command performs `C++ -> crystal-stage0 -> crystal-stage1 -> crystal`, using
fresh native objects and caches. It uses no network, Git or existing Crystal.
Stage0 runs with a 512 MiB stack limit; allow enough memory for upstream type
inference (the earlier prototype needed about 6 GiB). C++ units compile serially.

Only the intermediate compilers omit optional features. The final build uses
upstream's full compiler source without those feature exclusions. Set
`FINAL_FLAGS`, `CRYSTAL_CONFIG_PATH`, `CRYSTAL_CONFIG_LIBRARY_PATH`,
`CRYSTAL_CONFIG_BUILD_COMMIT`, and other upstream build settings as needed for
the distribution recipe. Install `build/crystal` and `upstream/src` as the
compiler and standard library, respectively.

GitHub's attestation establishes the origin of this source archive. The release
workflow compares two complete translations; it does not build or certify the
compiler chain. Distribution build services must validate the final compiler
and compare SHA256 with a same-version upstream reference under an identical
recipe, including LLVM, dependencies, flags, source/output paths and caches.
Byte equality with arbitrary upstream binary downloads is not promised.

See https://github.com/soupglasses/crystal-bootstrap for the generator, workflow,
release verification instructions, and packaging example.
