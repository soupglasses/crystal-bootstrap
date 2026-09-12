# Source releases

Each date-based bootstrap release targets one upstream Crystal version. The
single [release.json](../release.json) pins that source commit, its shards, the
maintainer's generator host, and the release LLVM major. A later date can target
a new Crystal release and drop the old target; no compatibility matrix is required.
Use a numeric suffix such as `2026.09.12.1` for a second bootstrap of the same date.

## Maintainer workflow

1. Update the pins and adapt the generator/runtime only where the target requires
   it. Keep source notices current. Run relevant translator checks.
2. Run `make generate LLVM_CONFIG=llvm-config-20`. Inspect the unpacked output in
   `build/generated/1.21.0`. The command compares two independent translations,
   rejects unsupported lowering, and preserves the previous output on failure.
3. Commit maintained sources, pins and workflow. Generated trees and ZIPs must
   never enter the published Git history.
4. Run the **Bootstrap source release** workflow on that commit, or push the tag
   `bootstrap-<version>`. The workflow generates on a fresh GitHub runner, packages
   the result and obtains GitHub's artifact attestation. It creates a draft with
   all assets before publishing. An existing release is never overwritten; use a
   new version for corrections.

Enable GitHub immutable releases in repository settings before publication.
[Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
protect the release tag and uploaded assets. GitHub handles signing keys and
[artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations);
there is no project-maintained signing service or local provenance database.

The workflow intentionally stops at the source archive. It does not build stage0,
the final compiler, or an RPM. Its attestation proves the source archive's origin,
not compiler correctness or binary reproducibility.

## Distribution consumption

Download the named source ZIP, `SHA256SUMS` and `source.intoto.jsonl` from the
release. Before submitting sources to OBS or another build service:

```sh
gh attestation verify crystal-bootstrap-2026.09.12-crystal-1.21.0-llvm20.zip \
  --repo soupglasses/crystal-bootstrap \
  --signer-workflow soupglasses/crystal-bootstrap/.github/workflows/source-release.yml
sha256sum -c SHA256SUMS
gh release verify bootstrap-2026.09.12 --repo soupglasses/crystal-bootstrap
```

Inspect the verified attestation's source commit and workflow against the expected
release. The downloaded attestation bundle is also available for verification with
`gh attestation verify --bundle source.intoto.jsonl`. See the
[CLI verification reference](https://cli.github.com/manual/gh_attestation_verify).
Extract with `unzip`, which preserves the included shard symlinks.

The archive includes pinned upstream source and shards, readable C++ and runtime,
notices, a Makefile and a small offline native build driver. `SOURCE.json` describes
the generation settings. Native dependencies must be supplied by the distribution,
including the matching LLVM major. The [RPM example](../packaging/crystal-bootstrap.spec)
illustrates an OBS recipe; package names, license inventory and installation policy
need distribution review. This project does not publish RPM binaries.

The build driver uses fresh objects and stable workspace paths on every invocation.
It preserves upstream's final compiler features; intermediate bootstrap compilers
omit optional tools/libraries. Packagers control the final flags and configuration.
Validate the resulting compiler against a same-version upstream reference built
with identical dependencies, flags, paths, environment and empty caches. Record
actual hash mismatches rather than treating successful compilation as byte equality.
Guix's native dependency closure and the 1.21 compiler chain still need distribution
validation. Historical development results are in [reproducibility](reproducibility.md).
