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
- Global speed limits, listening port, DHT, PEX, LSD and UPnP/NAT-PMP.
- **Network diagnostics** panel: actual port, local IP, UPnP/NAT-PMP mapping state and a
  TCP external reachability test.
- Dark, light or system appearance, applied immediately.
- Automatic session resume through resume data, with path validation.
- Errors visible with message and path in the inspector.
- Self-contained bundle: libtorrent and OpenSSL are included in the app.

## Requirements

- **macOS 15.0** (Sequoia) or later on Apple Silicon (arm64).
- **Xcode Command Line Tools** with Swift 6.x for local builds (tested with Swift 6.4).
  Full Xcode is not required for development; canonical release builds use Xcode 16.4
  as recorded in `Scripts/toolchain.env`.
- **CMake 3.20+** to build the engine dependencies (local builds tested with CMake 4.4.4).
  On macOS, install it with `brew install cmake`; no Homebrew libraries are needed at runtime.

The engine dependencies (`libtorrent`, OpenSSL and Boost headers) are **pinned** in
`Scripts/deps.env` and built from source with a macOS 15.0 deployment target. Homebrew
bottles are not used, so the dependency closure is source-pinned and the final bundle has
no external runtime paths.

This is intentionally **not** a promise that the app or DMG is bit-for-bit reproducible on
any Mac. The canonical release toolchain (Xcode, CMake and runner image) is recorded in
`Scripts/toolchain.env` and checked by CI. Local builds can use different tools, paths or
filesystem metadata; the published DMG is the artifact produced by CI and its SHA-256 is
the canonical checksum.

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

### Reproducibility and provenance

The project guarantees the following:

- every dependency source URL and SHA-256 is pinned in `Scripts/deps.env`;
- the complete dependency closure is copied into the app and checked by
  `Scripts/verify-bundle.sh`;
- the canonical build toolchain is recorded in `Scripts/toolchain.env` and verified by
  CI (`Scripts/check-toolchain.sh --strict` for release tags);
- the published release asset is the one built and checksummed by CI.

It does **not** guarantee bit-for-bit identical app or DMG files across arbitrary
machines, nor two byte-identical DMG runs. Xcode/SDK, CMake, the runner image, the checkout
path and the HFS+/UDIF timestamps written by `hdiutil` can change the bytes. In particular,
a DMG built locally is not expected to match the CI asset, so its hash must not be compared
with the published checksum. Use the published `.dmg.sha256` to verify the canonical
artifact.

For development, check your environment without blocking the build:

```bash
./Scripts/check-toolchain.sh --warn
```

CI uses `--strict` on tags. When the runner image or toolchain changes, update
`Scripts/toolchain.env` only after validating the new artifact and its checksum.

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

The local DMG is useful for testing the installer, but it is not the canonical release
artifact: `hdiutil`, HFS+/UDIF metadata and the local toolchain can change its bytes even
with the same app. Only the CI DMG and its published `.sha256` are canonical.

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
  if it is not writable, the app shows an error and does not add the torrent.
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
- Shows the actual port, local IP, UPnP/NAT-PMP mapping state and DHT nodes. Mapping
  failures are reported separately for TCP and UDP, together with the transport
  (UPnP or NAT-PMP) that produced them.
- **Test port** checks TCP reachability through check-host.net: the public IP is sent to the
  service only when you start the test. UDP/uTP traffic is not checked.
- If the port appears closed, enable UPnP/NAT-PMP on the router or forward TCP and UDP to the
  local IP; also check that you are not behind CGNAT.

### Settings

- Download folder, global download/upload limits, listening port, DHT, Peer Exchange (PEX),
  Local Service Discovery (LSD), UPnP/NAT-PMP.
- Start paused and sequential download defaults for new torrents; choices made in the add
  window apply only to the individual torrent.
- Dark, light or system appearance.
- The download folder applies to new torrents; torrents already added keep their own path.
- DHT and LSD apply immediately. Changing Peer Exchange recreates the libtorrent session
  in the background so the plugin is actually enabled or disabled; network controls are
  briefly disabled and active torrents are restored from resume data. If the new session
  cannot start, Vertex attempts to restore the previous configuration.
- Port and speed limits are validated: an invalid value is not applied and is reported
  with a message.

The network options in **Settings → Network** control how Vertex finds other peers and how
it makes itself reachable from the outside; they do not affect speed limits, queues or
folders.

- **DHT** — A distributed "phone book" without a tracker: it lets Vertex find peers for
  magnet links and trackerless torrents. If disabled, Vertex uses only trackers. Keep it on
  for normal use; disable it if you want tracker-only operation.
- **Peer Exchange (PEX)** — Connected clients share other peer addresses with each other.
  This speeds up discovery and helps recover the swarm when trackers are slow. It exchanges
  only addresses, not files. Disable it to reduce propagation of your IP through PEX; it
  does not make you anonymous. In Vertex, changing it recreates the session in the
  background without blocking the window; network controls are briefly disabled.
- **Local Service Discovery (LSD)** — Finds peers on the same local network via multicast.
  Useful for transfers between two home computers without going through the internet. On
  public or corporate networks it is better disabled because it announces torrents to the
  LAN.
- **UPnP / NAT-PMP** — Asks the router to open Vertex's listening port automatically. It
  improves incoming connections, seeding and reachability. If disabled, you must configure
  port forwarding manually; otherwise Vertex can only make outgoing connections. It is
  reasonable to disable it on untrusted routers or networks.
- **Network diagnostics** — Not a setting: it verifies the effective port, router mapping
  and external reachability.

For normal home use, leave all four toggles enabled. For maximum privacy, disable DHT, PEX
and LSD, and consider disabling UPnP/NAT-PMP as well; without port forwarding or a VPN that
provides an incoming port, the client will be less reachable.

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
- `Tests/VertexTests` — automated test suite (`VertexTestRunner`), including loopback libtorrent integration tests.
- `Tests/Fixtures` — deterministic v1/v2 torrent fixtures used by the integration tests.
- `.github/workflows/ci.yml` — CI/CD: build and test on push/PR, release only on tags.
- `Scripts/run-tests.sh` — runs the suite with LLVM coverage and writes JUnit/LCOV reports.
- `Scripts/deps.env` — pinned engine versions and SHA-256 checksums.
- `Scripts/toolchain.env` — canonical Xcode, CMake, macOS and runner image for release builds.
- `Scripts/check-toolchain.sh` — compares the current machine with the canonical toolchain.
- `Scripts/build-deps.sh` — builds libtorrent, OpenSSL and Boost headers for macOS 15.
- `Scripts/verify-bundle.sh` — verifies self-containment, `minos`, architecture and signature.
- `Scripts/make-icon.swift` — generates the `.icns` icon with CoreGraphics.
- `Scripts/make-dmg.sh` — creates the distributable DMG with SHA-256 checksum.
- `Resources/Info.plist` — bundle, `.torrent` association, minimum version.
- `Resources/en.lproj`, `Resources/it.lproj` — English and Italian UI and InfoPlist strings.
- `Resources/Licenses/` — license texts included in the bundle.

## Development

```bash
./Scripts/check-toolchain.sh --warn  # non-canonical local toolchains are allowed
./build.sh debug
./build.sh test
./Scripts/build-deps.sh --force      # rebuild the pinned dependencies
```

An automated test suite (`VertexTestRunner`, run via `./build.sh test`) covers formatters,
snapshot JSON deserialization (including separate TCP/UDP mapping errors), model
filtering/sorting, preferences, C++ bridge lifecycle and default save-path updates. A
dedicated `TorrentEngine` suite verifies magnet and file additions, selection and detail
loading (including failed fetches), file priorities, pause/resume, commands on removed
torrents, PEX session restarts and asynchronous shutdown. A `PortReachabilityTester` suite
uses a fake HTTP loader to cover open/closed ports, service errors, missing nodes, partial
timeouts, reset and invalid payloads, without contacting external services. It also runs deterministic
loopback integration tests with two libtorrent sessions: v1/v2 transfers, pause/resume,
resume reload after a session restart (including a PEX change), file priorities, removal
with and without `delete_files`, concurrent torrents and failure paths. No external
tracker or internet connection is used.

`./build.sh test` writes `dist/test-results.xml` (JUnit) and `dist/coverage/`
(`coverage.txt` plus LCOV). CI uploads both artifacts on every run. The suite is headless:
critical SwiftUI views are rendered off-screen with `ImageRenderer` without opening windows;
real external trackers are not exercised.

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
