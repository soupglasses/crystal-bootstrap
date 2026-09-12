# Releasing source archives

Push a three-part numeric tag, such as `2026.09.12`, to publish a source
release. [release.json](../release.json) at that commit selects the Crystal
targets, shards, generator host and LLVM major. The workflow derives its build
matrix and release title from those targets. A new release may drop an older
target.

## Publish

1. Update the pins in `release.json`. Run the affected
   [developer checks](compiler-translation.md), `make check-release`, and
   `make generate LLVM_CONFIG=llvm-config-20` for each target (`TARGET=1.21.0`
   selects an entry). Use the configured LLVM major.
2. Commit and push the maintained sources. Keep generated output out of Git.
3. Tag the commit and push the tag, substituting the new release version:

   ```sh
   git tag -m "2026.09.12" 2026.09.12 <commit>
   git push origin 2026.09.12
   ```

The [workflow](../.github/workflows/source-release.yml) generates each target
twice and requires byte-identical snapshots with no unsupported paths. It
packages the sources, writes `SHA256SUMS`, attests the ZIPs, then publishes the
release with a title such as `2026.09.12 - Crystal 1.21.0`. Several targets appear
as a comma-separated version list.

Local generation produces an unpacked tree labelled `dev`; CI supplies the tag
through `BOOTSTRAP_VERSION`. Use a new tag for each subsequent release.

Enable [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
in repository settings before publication to protect the release tag and assets.
GitHub manages attestation signing. The workflow publishes source archives;
compiler construction and binary comparison run in the distribution build service.

## Verify a download

Download the source ZIP, `SHA256SUMS` and `source.intoto.jsonl` from the release.
For example:

```sh
gh attestation verify crystal-bootstrap-2026.09.12-crystal-1.21.0-llvm20.zip \
  --repo soupglasses/crystal-bootstrap \
  --source-ref refs/tags/2026.09.12 \
  --signer-workflow soupglasses/crystal-bootstrap/.github/workflows/source-release.yml
sha256sum -c SHA256SUMS
gh release verify 2026.09.12 --repo soupglasses/crystal-bootstrap
```

Check that the verified attestation identifies the expected source commit and
workflow. To use the downloaded bundle, add `--bundle source.intoto.jsonl` to
the attestation command above. See the [attestation CLI reference](https://cli.github.com/manual/gh_attestation_verify)
and [release verification reference](https://cli.github.com/manual/gh_release_verify).
For a release with several targets, `SHA256SUMS` lists every ZIP; download them
all or check the entry for the selected archive. Extract with `unzip` to preserve
shard symlinks.

## Distribution builds

The archive's [README](../packaging/source-README.md) lists dependencies and build
settings. The native build runs offline and clears objects and caches before
each build.
Workspace paths stay fixed across runs because they can affect the final binary.
Packagers select the final flags and configuration, with upstream's optional
compiler features enabled.

Validate the resulting compiler against a reproducible same-version upstream
reference with identical LLVM, dependencies, flags, metadata, environment,
source/output paths and cleared caches. Comparing an arbitrary upstream binary
download does not control those inputs. The developer comparison harness uses
reduced compiler features, so its result does not verify a distribution recipe
with different settings.

The [RPM spec](../packaging/crystal-bootstrap.spec) is an OBS example requiring
review of package names, licensing and installation policy. The Guix dependency
closure and the configured 1.21 compiler chain remain unverified. Earlier
[development results](reproducibility.md) apply only to their recorded inputs.
