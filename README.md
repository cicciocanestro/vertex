# Vertex

[Italiano](README.it.md) · **English**

**Native macOS BitTorrent client**, written in SwiftUI and powered by libtorrent 2.1.
No Electron, no ads, no telemetry. Open source under the MIT license.

[![Release](https://img.shields.io/github/v/release/cicciocanestro/vertex?display_name=tag&sort=semver)](https://github.com/cicciocanestro/vertex/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B%20arm64-lightgrey)](#requirements)
[![CI](https://github.com/cicciocanestro/vertex/actions/workflows/ci.yml/badge.svg)](https://github.com/cicciocanestro/vertex/actions/workflows/ci.yml)

![Vertex interface](docs/screenshot.jpg)

## Download

[**Download the latest DMG**](https://github.com/cicciocanestro/vertex/releases/latest)

1. Open the DMG.
2. Drag **Vertex** into **Applications**.
3. On first launch, macOS may ask for confirmation (see below).

### Signing and notarization

The current release is **ad-hoc signed and not notarized**. On another Mac, Gatekeeper
may block the first launch:

- right-click **Vertex** in Finder and choose **Open**, or
- go to **System Settings → Privacy & Security** and choose **Open Anyway**.

Developer ID signing, hardened runtime and Apple notarization are the next distribution
step. Until then, expect this one-time confirmation.

### Requirements

- **macOS 15.0 (Sequoia)** or later.
- **Apple Silicon (arm64)**. The current build is not universal; Intel is not supported yet.

Verify the download with the published checksum:

```bash
shasum -a 256 -c Vertex-*.dmg.sha256
```

## Features

- Native **SwiftUI** interface with light, dark and system appearance.
- **libtorrent 2.1** engine: DHT, PEX, LSD, UPnP/NAT-PMP, HTTP/UDP trackers, magnet links,
  v1 and v2 torrents.
- Add from magnet links, `.torrent` files, drag and drop, clipboard, Finder or browser.
- Search, filters, sorting and an inspector with statistics, files/priorities and trackers.
- Pause/resume, sequential download, resume data and visible error details.
- Global speed limits, listening port, DHT, PEX, LSD and UPnP/NAT-PMP controls.
- **Interface binding**: pin the engine to one local address, so traffic only leaves through
  it. It is what makes the client usable behind CGNAT together with a WireGuard tunnel and
  port forwarding on a VPS.
- **Network diagnostics**: effective port, local IP, mapping state and TCP reachability.
- Italian or English interface based on the system language.
- **No telemetry**. The only network traffic is BitTorrent and, when you start the port
  test, api.ipify.org and check-host.net.
- Self-contained bundle: libtorrent and OpenSSL are included in the app.

## Build from source

```bash
git clone https://github.com/cicciocanestro/vertex.git
cd vertex
./build.sh
open dist/Vertex.app
```

Source builds require Xcode Command Line Tools with Swift 5.10+ (tested with Swift 6.4) and
CMake 3.20+. The first build compiles the pinned engine dependencies from
`Scripts/deps.env`; later builds reuse `.build/vertex-deps`. No Homebrew libraries are
needed at runtime.

```bash
./build.sh          # release build
./build.sh debug    # debug build
./build.sh test     # automated test suite
```

## Usage

### Adding a torrent

- **Add** in the header, or `⌘N` / `⌘O`.
- Paste a magnet link or choose/drop a `.torrent` file; drag and drop also works on the main
  window.
- Magnet links opened from a browser or Finder are handled by Vertex.
- The destination is validated: a file path uses its containing folder; an unwritable
  folder produces an error and the torrent is not added.
- Options in the add window (folder, start paused, sequential) apply only to that torrent.

### Managing torrents

- Pause/resume, remove with or without deleting files, **Show in Finder**, copy magnet link
  and sequential download.
- Selecting a torrent opens the inspector with statistics, file priorities and trackers.
- On error, the actual message is shown in the row; the message and path are shown in the
  inspector.

### Network diagnostics

- Open from the port in the status bar, **Settings → Network → Network diagnostics**, or
  `⌘⇧D`.
- Shows the effective port, local IP, UPnP/NAT-PMP state and DHT nodes. Mapping errors are
  reported separately for TCP and UDP, with the transport that produced them.
- **Test port** checks TCP reachability through check-host.net; the public IP is sent only
  when you start the test. UDP/uTP is not tested.
- If the port is closed, enable UPnP/NAT-PMP or forward TCP/UDP to the local IP; check
  whether you are behind CGNAT.
- When an interface is bound, the panel shows that address instead of the LAN one and names
  the transport that failed. A binding whose address is no longer available is reported
  explicitly: the engine does not fall back to the physical interface.

### Settings

- Download folder, global speed limits, listening port, DHT, PEX, LSD, UPnP/NAT-PMP.
- **Network interface**: binding the client to one local IPv4 address (for example the
  address of a WireGuard tunnel) sets both the listening socket and the outgoing source, and
  libtorrent rejects traffic arriving on the other interfaces. Removing the binding restores
  the default of listening on every interface. Only literal IPv4 addresses are accepted; if
  the address disappears while the client runs, listening fails and the diagnostics panel
  reports why.
- Start-paused and sequential defaults for new torrents; per-torrent choices stay local to
  the add window.
- Dark, light or system appearance.
- DHT and LSD apply immediately. Changing PEX recreates the libtorrent session in the
  background and restores active torrents from resume data. Port and speed limits are
  validated and invalid values are reported.
- Leave DHT, PEX, LSD and UPnP enabled for normal home use. Disable DHT/PEX/LSD for less
  peer discovery and UPnP on untrusted routers. BitTorrent is not anonymous.

### Shortcuts

| Action | Shortcut |
| --- | --- |
| Add `.torrent` file | `⌘O` |
| Add magnet link | `⌘N` |
| Paste magnet from clipboard | `⌘⇧V` |
| Search | `⌘F` |
| Pause / resume | `⌘P` |
| Remove torrent | `⌘⌫` |
| Show in Finder | `⌘⇧R` |
| Copy magnet link | `⌘⇧C` |
| Show / hide inspector | `⌘I` |
| Network diagnostics | `⌘⇧D` |
| Filters | `⌘1` … `⌘5` |
| Settings | `⌘,` |

Pause/Resume and Remove act on the selected torrent; without a selection they show a
notice.

### Where data is stored

- Default downloads: `~/Downloads/Vertex`
- State and resume data: `~/Library/Application Support/Vertex/resume`
- Preferences: `UserDefaults` (`app.vertex.torrent`)

There is no telemetry. The app is not sandboxed and accesses the chosen folders and the
download folder.

## Technical details

### Reproducibility and provenance

- Every dependency URL and SHA-256 is pinned in `Scripts/deps.env`.
- The full dependency closure is copied into the app and checked by
  `Scripts/verify-bundle.sh`.
- The canonical toolchain is recorded in `Scripts/toolchain.env` and checked by CI;
  release tags use `Scripts/check-toolchain.sh --strict`.
- The published DMG is the artifact built and checksummed by CI. Local app/DMG files are
  not expected to be bit-for-bit identical: Xcode/SDK, CMake, runner image, checkout path
  and HFS+/UDIF timestamps can change the bytes.
- Use the published `.dmg.sha256` to verify the canonical artifact. Do not compare a local
  DMG hash with the CI asset.

### DMG and release

```bash
./Scripts/make-dmg.sh            # rebuild and create the DMG
./Scripts/make-dmg.sh --no-build # use the existing dist/Vertex.app
```

The DMG contains the app, an **Applications** link, a bilingual `Leggimi.txt` readme and
the volume icon. It produces:

- `Vertex-<version>-macOS<minimum>-<arch>.dmg`
- `Vertex-...dmg.sha256`

The script verifies signature, dependencies, `minos` and architecture before creating the
DMG and after mounting it.

Publishing is handled by CI: pushes to `main` produce a build artifact, while only `v*`
tags create a GitHub Release. The tag must match `Info.plist`; published assets are not
overwritten. The current DMG is arm64-only; a universal release requires dependencies for
both architectures.

### Architecture

- `Sources/CTorrent` — C++/C bridge to libtorrent: session, adding torrents, JSON snapshot,
  file/tracker details, resume data, priorities, path validation and commands.
- `Sources/VertexKit` — core application library:
  - `Engine/TorrentEngine.swift` — serialized engine polling and published state;
  - `Engine/PortReachabilityTester.swift` — external TCP test;
  - `Views/` — list, rows, inspector, add sheet, settings, diagnostics, status bar;
  - `Utilities/` — input validation, drop handling, localization, network info;
  - `Design/` — palette, shared components, modal chrome;
  - `Models/` — snapshot models, filters, sorting, formatting;
  - `DebugSupport.swift` — demo data and screenshot capture, DEBUG builds only.
- `Sources/Vertex` — SwiftUI entry point (`@main`, AppDelegate, URL handling, window).
- `Tests/VertexTests` — automated suite, including loopback libtorrent integration tests.
- `Tests/Fixtures` — deterministic v1/v2 torrent fixtures.
- `Scripts/` — pinned dependency build, bundle verification, DMG, localization check,
  toolchain check and test runner.
- `Resources/` — `Info.plist`, localizations and third-party licenses.
- `.github/workflows/ci.yml` — build/test on push and PR; release on tags.

### Development and tests

```bash
./Scripts/check-toolchain.sh --warn  # local, non-canonical toolchains are allowed
./build.sh debug
./build.sh test
./Scripts/build-deps.sh --force      # rebuild pinned dependencies
```

`./build.sh test` writes `dist/test-results.xml` (JUnit) and `dist/coverage/` (text plus
LCOV). CI uploads both. The suite covers formatters, snapshot JSON decoding, models,
preferences, the C++ bridge lifecycle, the engine (add, detail, priorities, pause/resume,
PEX restart, shutdown), network reachability with a fake HTTP loader and command routing.
Loopback integration tests exercise v1/v2 transfers, resume reload, file priorities,
removal and failure paths without external trackers. SwiftUI views and modal variants are
rendered off-screen with `ImageRenderer`; the UPnP/NAT-PMP smoke test runs only with
`VERTEX_TEST_UPNP=1` in CI.

DEBUG builds provide demo data and window capture (`VERTEX_DEMO=1`,
`VERTEX_SNAPSHOT=/path/image.png`).

## Limitations

- macOS 15.0+ on Apple Silicon (arm64); Intel requires a universal build with dependencies
  for both architectures.
- Ad-hoc, not notarized signature: expect a Gatekeeper confirmation on another Mac.
- Italian or English interface based on the system language; no other translations.
- Deliberately minimal: no RSS, built-in torrent search or scheduler.
- There is no ratio limit: seeding continues until you pause or remove the torrent.
- Moving data of an already added torrent is not supported.
- The DMG is specific to the build Mac's architecture (arm64 on Apple Silicon).

## Contributing

Issues and pull requests are welcome. Before opening a PR, run `./build.sh test` and keep
the English and Italian README/localization tables in sync.

## Changelog

Changes between versions are documented in [`CHANGELOG.md`](CHANGELOG.md).

## License

Vertex is distributed under the **MIT License**: see [`LICENSE`](LICENSE).

Bundled libraries keep their own licenses:

- **libtorrent-rasterbar** — BSD 3-Clause
- **OpenSSL** — Apache License 2.0
- **Boost** (headers only at build time) — Boost Software License 1.0

Full texts are in [`Resources/Licenses/`](Resources/Licenses) and
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). They are also included in the bundle
under **Vertex → Open source licenses**.
