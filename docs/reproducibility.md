# Compiler reproducibility results

These are historical development measurements for 1.22.0-dev, not verification
of the Crystal 1.21 source release. The generated tree is no longer tracked in Git.

The source bootstrap completes, and its final binary matches the current
compiler's reproducible self-build. It does **not** match the direct output of
Crystal 1.21. These are separate comparisons. Direct cross-version equality is not a release
requirement; same-version upstream reproducibility remains the acceptance goal.

## Controlled comparison

All comparisons use upstream revision
`f4acc09db3edbc51cf526ba97808fbaa3e857ea9`, Linux x86-64, LLVM 22.1.8,
`SOURCE_DATE_EPOCH=0`, one compiler thread, no debug information, and the flags
in the [verification receipt](../bootstrap/verification.json). Source, output
and cache paths are identical between builds, and the cache is cleared each
time. The compilers are built without release optimization.

| Build | SHA256 |
| --- | --- |
| Current trusted compiler, repeated twice | `00e4119a5c627039603883ddee40d456d830effb2b0554b0fb0a071fb7213737` |
| That reference rebuilding itself | `00e4119a5c627039603883ddee40d456d830effb2b0554b0fb0a071fb7213737` |
| Stage1 from the generated native stage0 | `3c51e12a74c22f1fe4779ef0b44e887d9f710ed7f874d0edb83a928e2ce8c935` |
| Final compiler built by stage1 | `00e4119a5c627039603883ddee40d456d830effb2b0554b0fb0a071fb7213737` |
| Crystal 1.21 compiling current source, repeated twice | `cf379382351e1bd4b412fb82525ecc584e8df1b5da0b50b151e091877d8842c7` |
| That 1.21-produced reference rebuilding current source | `00e4119a5c627039603883ddee40d456d830effb2b0554b0fb0a071fb7213737` |

Crystal 1.21 was built from its local upstream tag against LLVM 22.1.8 before
this comparison. This avoids attributing a change of LLVM backend version to
the translator. Its binary hash, version, measurements and comparison results
are in [the n-1 receipt](../bootstrap/n-1-verification.json).

Both paths converge to the same binary:

```text
Crystal 1.21 -> current compiler -> current compiler (00e4119…)
C++ stage0  -> stage1           -> current compiler (00e4119…)
```

Repeatability with one compiler does not guarantee identical output from a
different compiler version. Upstream changed compiler semantics and code
generation between these revisions, including
[unused yield-block value handling](https://github.com/crystal-lang/crystal/commit/43ae759b4b8c140851f177eebb338fa5b6d08243).
A diagnostic build reverting only that code-generation commit still did not
produce the direct 1.21 hash. The precise differences have not been isolated;
this result does not prove that commit is the sole cause. The measured snapshot
and final source retain upstream's current implementation.

Emulating historical code generation would add maintenance beyond producing the
current compiler. The verified result is the shared self-build fixed point;
this document does not substitute that result for direct `n-1` equality.

## Reproduce the checks

For an ordinary source-only build:

```sh
make bootstrap CXX=clang++
```

The [source-only receipt](../bootstrap/source-only-verification.json) records a
complete run with a failing `crystal` command first on PATH and `CRYSTAL` pointing
to that guard. Neither was invoked. This run used separate output/cache paths,
so its binary hashes are not compared to the table above.

For a strict audit against a selected trusted compiler:

```sh
make check-bootstrap BOOTSTRAP_HOST=/path/to/trusted-crystal
```

This compares repeated direct reference builds, their self-build, and the
bootstrap final under shared paths. It returns failure if any required hash
differs. With Crystal 1.21 as the reference, it will therefore fail the direct
comparison even though the self-build converges. To inspect reference
reproducibility without rebuilding stage0's chain:

```sh
python3 tools/bootstrap.py --host /path/to/crystal --output-dir build/reference-audit
```

The final hash is specific to the declared inputs and absolute paths. Crystal
embeds cache paths even without debug information. Matching hashes across
relocated builds, release-mode builds, other LLVM versions, or Guix environments
has not been established. The native stage0 executable itself need not have the
same hash across different native compilers.
