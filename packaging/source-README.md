# Crystal bootstrap sources

This tree contains generated C++11, runtime, pinned Crystal and shard sources,
and an offline native build driver. `SOURCE.json` records the target and
generation settings.

On Linux x86-64, install a C/C++ compiler, Python 3, Make, pkg-config, the LLVM
major specified in `SOURCE.json` (development libraries and tools), Boehm GC,
utf8proc, PCRE2, libxml2, OpenSSL, zlib and readline development packages. Then:

```sh
make CXX=clang++ LLVM_CONFIG=llvm-config-20
./build/crystal --version
```

Use the LLVM major from `SOURCE.json` in the command above. The build compiles
C++ into stage0, uses stage0 to build stage1, then rebuilds Crystal with stage1.
It uses fresh native objects and caches, without network access, Git or an
existing Crystal executable. C++ units compile serially. Stage0 has a 512 MiB
stack limit; an earlier development build needed about 6 GiB peak RSS during
upstream type inference.

The intermediate compilers omit optional features; the final compiler enables
them. Set `FINAL_FLAGS`, `CRYSTAL_CONFIG_PATH`, `CRYSTAL_CONFIG_LIBRARY_PATH`,
`CRYSTAL_CONFIG_BUILD_COMMIT`, and other upstream settings for the distribution
recipe. Install `build/crystal` and `upstream/src` as the compiler and standard
library. A failed build preserves the previous completed binaries.

GitHub's attestation establishes the source archive's origin. The release
workflow checks deterministic generation; distribution builders validate the
compiler chain. Compare the final binary with a reproducible same-version
upstream reference using identical LLVM, dependencies, flags, metadata,
environment, source/output paths and cleared caches.

The [project repository](https://github.com/soupglasses/crystal-bootstrap)
contains the generator, release verification instructions and packaging example.
