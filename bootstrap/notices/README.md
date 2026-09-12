# Source notices

The generated snapshots contain translated portions of Crystal, its standard
library and its compiler's shards. Their original notices and licenses apply to
those portions. Generation does not replace those licenses with this project's
license.

- `crystal/` preserves upstream's root license, notice, REUSE configuration and
  license texts from the original development snapshot. A release also includes the full
  pinned upstream tree and its authoritative notices under `upstream/`.
- `markd/`, `reply/` and `sanitize/` preserve the licenses of the compiler shards
  recorded in the release
  `SOURCE.json`; original notices also accompany each shard under `upstream/lib/`.
- `source-files.md` preserves copyright and license comment blocks from upstream
  source files, including embedded ports and algorithms with separate notices.
- `llvm/LICENSE` supplies the Apache license with LLVM exceptions referenced by
  upstream's Dragonbox port. It was copied from the installed LLVM source license.

These notices conservatively include source for platforms disabled in the
published configuration. Native libraries are external build inputs; their
versions are selected by the distribution build recipe. No native library binaries
are included in the snapshot.
