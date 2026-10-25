# Vertex

**English** · [Italiano](README.it.md)

**Native macOS BitTorrent client**, written in SwiftUI and powered by libtorrent.
A minimal interface with light/dark/system appearance, an inspector panel, search, filters
and full support for magnet links and `.torrent` files.

![Vertex interface](docs/screenshot.jpg)

## Features

- **libtorrent 2.1** engine: DHT, PEX, LSD, UPnP/NAT-PMP, HTTP/UDP trackers, magnet links,
  v1 and v2 torrents.
- **Italian or English interface**: Italian when the system language is Italian, English for
  any other language.
- App version and build are shown in the header and in Settings → About.
- Add from magnet links, `.torrent` files, drag and drop, clipboard, double-click in Finder
  or magnet links opened from a browser (registered `magnet` scheme).
- Download, seed, pause/resume, file verification and metadata retrieval.
- Instant search, filters (all, downloading, seeding, completed, paused) and sorting.
- Inspector with statistics, files with priorities and tracker status.
- Global speed limits, listening port, DHT, UPnP/NAT-PMP.
- **Network diagnostics** panel: actual port, local IP, UPnP/NAT-PMP mapping state and a
  TCP external reachability test.
- Dark, light or system appearance, applied immediately.
- Automatic session resume through resume data, with path validation.
- Errors visible with message and path in the inspector.
- Self-contained bundle: libtorrent and OpenSSL are included in the app.

## Requirements

- **macOS 15.0** (Sequoia) or later on Apple Silicon (arm64).
- **Xcode Command Line Tools** with Swift 6.x (tested with Swift 6.4). Full Xcode is not required.
- **CMake 3.20+** to build the engine dependencies. On macOS, install it with
  `brew install cmake`; no Homebrew libraries are needed at runtime.

The engine dependencies (`libtorrent`, OpenSSL and Boost headers) are **pinned** in
`Scripts/deps.env` and built from source with a macOS 15.0 deployment target. Homebrew
bottles are not used, so the build is reproducible and the final bundle has no external
runtime paths.

The first `./build.sh` may take a few minutes to build the dependencies; later builds
reuse `.build/vertex-deps`.

Tested on Apple Silicon. The build is `arm64`; a universal release requires dependencies
built for both architectures, and Intel has not been tested.

## Installation

If a release is available, download the DMG from the
[**Releases**](https://github.com/cicciocanestro/vertex/releases) section, open it and drag
**Vertex** into the Applications folder.

Alternatively, build from source:

```bash
git clone https://github.com/cicciocanestro/vertex.git
cd vertex
./build.sh
open dist/Vertex.app
```

`build.sh` builds the pinned dependencies, generates the icon if missing, copies the
licenses into the bundle, rewrites the dylib paths and verifies that the app is
self-contained.

## Building

```bash
./build.sh          # release build
./build.sh debug    # debug build
./build.sh test     # run automated test suite
open dist/Vertex.app
```

The script:

1. builds the pinned dependencies from `Scripts/deps.env` if needed;
2. builds the Swift package;
3. creates `dist/Vertex.app`;
4. generates the icon if missing;
5. copies `libtorrent`, OpenSSL and the licenses into the bundle;
6. rewrites the dylib paths and applies an ad-hoc signature;
7. verifies that the bundle has no external dependencies and that every binary's
   `minos` does not exceed the value declared in `Info.plist`.

If you run `swift build` without `build.sh`, build the dependencies first and set the
prefix:

```bash
./Scripts/build-deps.sh
export VERTEX_DEPS_PREFIX="$PWD/.build/vertex-deps"
swift build -c release
```

To force a dependency rebuild:

```bash
./build.sh release --rebuild-deps
```

## DMG release

```bash
./Scripts/make-dmg.sh            # rebuild and create the DMG
./Scripts/make-dmg.sh --no-build # use the existing dist/Vertex.app
```

It produces in `dist/`:

- `Vertex-<version>-macOS<minimum version>-<architecture>.dmg`
- `Vertex-...dmg.sha256`

The DMG contains `Vertex.app`, a link to **Applications**, a `Leggimi.txt` readme (Italian
and English) and the volume icon. Licenses are included in the app and available from the
**Vertex → Open source licenses** menu. The script checks the signature, dependencies,
`minos` and architecture both before creating the DMG and after mounting it, then generates
the SHA-256 checksum.

The build is `arm64` on Apple Silicon. A universal release requires dependencies built for
both architectures; the Intel build has not been tested.

Publishing is handled by CI: pushes to `main` produce a build artifact, while only `v*`
tags create a GitHub Release. The tag must match the version in `Info.plist`; published
assets are never overwritten.

The app is **ad-hoc signed** because the build environment has no Developer ID certificate.
The DMG is therefore distributable, but Gatekeeper warnings described in the notes may appear
on another Mac. For warning-free public distribution, sign with Developer ID, enable the
hardened runtime and notarize the app with `notarytool` and `stapler` before creating the DMG.

## Usage

### Adding a torrent

- **Add** button in the header, or `⌘N` / `⌘O`.
- In the add window you can paste a magnet link or choose/drop a `.torrent` file; drag and
  drop also works on the rest of the window.
- Magnet links opened from the browser or Finder are handled by the app as a BitTorrent client.
- The destination folder is validated: if a file is selected, its containing folder is used;
  if it is not writable, the app falls back to the default destination.
- The add window options (folder, start paused, sequential download) apply **only to that
  torrent**. Defaults are configured in Settings.

### Managing torrents

- Pause/resume, remove with or without deleting files, "Show in Finder", copy magnet link
  and sequential download.
- Selecting a torrent opens the inspector with statistics, files (with priorities) and trackers.
- On error, the actual message and the involved path are shown in the row and in the inspector.

### Network diagnostics

- Open it from the port number in the status bar, from **Settings → Network → Network
  diagnostics**, or with `⌘⇧D`.
- Shows the actual port, local IP, UPnP/NAT-PMP mapping state and DHT nodes.
- **Test port** checks TCP reachability through check-host.net: the public IP is sent to the
  service only when you start the test. UDP/uTP traffic is not checked.
- If the port appears closed, enable UPnP/NAT-PMP on the router or forward TCP and UDP to the
  local IP; also check that you are not behind CGNAT.

### Settings

- Download folder, global download/upload limits, listening port, DHT, UPnP/NAT-PMP.
- Start paused and sequential download defaults for new torrents; choices made in the add
  window apply only to the individual torrent.
- Dark, light or system appearance.
- The download folder applies to new torrents; torrents already added keep their own path.

## Shortcuts

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

Pause/Resume and Remove act on the selected torrent; without a selection they show an alert.

## Where data is stored

- Default downloads: `~/Downloads/Vertex`
- State and resume data: `~/Library/Application Support/Vertex/resume`
- Preferences: `UserDefaults` (`app.vertex.torrent`)

There is no telemetry. The only network connections are those of the BitTorrent engine and,
only when you start the port test, those to api.ipify.org and check-host.net.
The app is not sandboxed and accesses the chosen folders and the download folder.

## Architecture

- `Sources/CTorrent` — C++/C bridge to libtorrent: session, adding torrents, JSON snapshot,
  file/tracker details, resume data, priorities, path validation and commands.
- `Sources/VertexKit` — core application library:
  - `Engine/TorrentEngine.swift` — engine polling and published state;
  - `Engine/PortReachabilityTester.swift` — external TCP test via check-host.net;
  - `Views/` — list, rows, inspector, add window, settings, network diagnostics, status bar;
  - `Utilities/NetworkInfo.swift` — local IP detection;
  - `Utilities/Localization.swift` — `L`/`LF` helpers for dynamic strings;
  - `Design/` — adaptive palette, components, animations;
  - `Models/` and `Utilities/` — models and formatting;
  - `DebugSupport.swift` — demo data and screenshot capture, DEBUG builds only.
- `Sources/Vertex` — SwiftUI app entry point (`@main`, AppDelegate, URL handling, window setup).
- `Tests/VertexTests` — automated test suite (`VertexTestRunner`).
- `.github/workflows/ci.yml` — CI/CD: build and test on push/PR, release only on tags.
- `Scripts/deps.env` — pinned engine versions and SHA-256 checksums.
- `Scripts/build-deps.sh` — builds libtorrent, OpenSSL and Boost headers for macOS 15.
- `Scripts/verify-bundle.sh` — verifies self-containment, `minos`, architecture and signature.
- `Scripts/make-icon.swift` — generates the `.icns` icon with CoreGraphics.
- `Scripts/make-dmg.sh` — creates the distributable DMG with SHA-256 checksum.
- `Resources/Info.plist` — bundle, `.torrent` association, minimum version.
- `Resources/en.lproj`, `Resources/it.lproj` — English and Italian UI and InfoPlist strings.
- `Resources/Licenses/` — license texts included in the bundle.

## Development

```bash
./build.sh debug
./build.sh test
./Scripts/build-deps.sh --force   # rebuild the pinned dependencies
```

An automated test suite (`VertexTestRunner`, run via `./build.sh test`) covers formatters, snapshot JSON deserialization, model filtering/sorting, preferences and C++ bridge lifecycle. CI runs on GitHub Actions on every push and pull request (`.github/workflows/ci.yml`); `v*` tags publish the release.

DEBUG builds provide demo data and automatic window capture (`VERTEX_DEMO=1`,
`VERTEX_SNAPSHOT=/path/image.png`).

## Limitations

- macOS 15.0 or later on Apple Silicon (arm64); Intel requires a universal build with dependencies compiled for both architectures.
- Ad-hoc, not notarized signature: on another Mac you may need to choose "Open Anyway" from
  the Finder context menu. For distribution, signing with Developer ID and notarization is
  recommended.
- Interface in Italian or English based on the system language; no other translations are
  provided.
- Deliberately minimal client: no RSS, built-in torrent search, scheduler or automatic ratio
  limit.
- Seeding continues until the torrent is paused.
- Moving the data of an already added torrent is not supported.
- The generated DMG is specific to the build Mac's architecture (arm64 on Apple Silicon).

## Changelog

Changes between versions are documented in [`CHANGELOG.md`](CHANGELOG.md).

## License

Vertex is distributed under the **MIT License**: see [`LICENSE`](LICENSE).

The bundled libraries keep their own licenses:

- **libtorrent-rasterbar** — BSD 3-Clause
- **OpenSSL** — Apache License 2.0
- **Boost** (headers only at build time) — Boost Software License 1.0

Full texts are in [`Resources/Licenses/`](Resources/Licenses) and in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). They are also included in the bundle and
available from **Vertex → Open source licenses**.
