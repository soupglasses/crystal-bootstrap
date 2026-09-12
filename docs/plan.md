# Source releases

A pushed Git tag creates a release. The tag is its version (for example,
`2026.09.12`); [release.json](../release.json) **at the tagged commit** selects
the Crystal source, shards, generator host and LLVM version. Any tag name works.
The `targets` list currently contains only Crystal 1.21.0. Later commits can
replace it or add targets; versions are not repeated in the workflow.

## Publish

1. Update the target pins in `release.json`. Run relevant checks and
   `make generate LLVM_CONFIG=llvm-config-20` (`TARGET=1.21.0` selects an entry).
2. Commit and push the maintained sources. Keep generated output out of Git.
3. Tag that commit and push the tag:

   ```sh
   git tag -m "2026.09.12" 2026.09.12 <commit>
   git push origin 2026.09.12
   ```

GitHub reads the tagged configuration into a build matrix. Each target generates
its sources twice and requires matching output. A final job collects the ZIPs,
checksums and attests them, and publishes `/releases/tag/2026.09.12` with the title
`2026.09.12 - Crystal 1.21.0` (or a comma-separated version list for several targets).
The run shows the tag, individual jobs show their Crystal version, and the final
job shows the release title. GitHub resolves the run name before reading files.
Publication uses the existing tag; there is no manual dispatch, tag prefix or
tag-name validation.

Local generation produces an unpacked tree labelled `dev`; CI supplies the tag
through `BOOTSTRAP_VERSION`. Tags containing filename separators are escaped in
archive filenames and retained exactly in `SOURCE.json` and the release.

Use a new tag for subsequent releases.

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
gh release verify 2026.09.12 --repo soupglasses/crystal-bootstrap
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
