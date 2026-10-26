# Test fixtures

These are tiny deterministic torrents used by the integration tests. They are
generated from local files and contain no trackers, so the tests never need an
external network.

## `fixture-v1.torrent`

- BitTorrent v1, piece size 16 KiB.
- Root directory: `vertex-fixture-v1`
- Files:
  - `data.bin` — 32768 bytes
  - `second.bin` — 16384 bytes

## `fixture-v2.torrent`

- BitTorrent v2 only, piece size 16 KiB.
- Root directory: `vertex-fixture-v2`
- Files:
  - `data.bin` — 32768 bytes
  - `second.bin` — 16384 bytes

The bytes of every file are:

```text
byte[i] = i % 251
```

for `i` from 0 to `size - 1`. The Swift integration helper uses the same
pattern, so the torrents can be seeded from a temporary directory.

The torrent files were generated with libtorrent 2.1.2 and have no creation
date or trackers. Regenerate them only when the fixture contents intentionally
change, and keep this document in sync.
