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
- SHA-256: `7b417e2b66cfa8a287088c6b0c83f3f3edba2152987a3157edb07628cd3ed200`

## `fixture-v2.torrent`

- BitTorrent v2 only, piece size 16 KiB.
- Root directory: `vertex-fixture-v2`
- Files:
  - `data.bin` — 32768 bytes
  - `second.bin` — 16384 bytes
- SHA-256: `41abb445025a64fe37e65d25114cea1c0532cc4b247b229e4d4081d1c9871a54`

The bytes of every file are:

```text
byte[i] = i % 251
```

for `i` from 0 to `size - 1`. The Swift integration helper uses the same
pattern, so the torrents can be seeded from a temporary directory.

The torrent files were generated with libtorrent 2.1.2 and have no creation
date or trackers. The checksums above pin their exact bytes. Regenerate them
only when the fixture contents intentionally change, update the checksums and
keep this document in sync.
