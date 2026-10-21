// swift-tools-version: 5.10
import Foundation
import PackageDescription

let homebrew = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] ?? "/opt/homebrew"
let libtorrent = "\(homebrew)/opt/libtorrent-rasterbar"
let boost = "\(homebrew)/opt/boost"
let openssl = "\(homebrew)/opt/openssl@4"

let package = Package(
    name: "Vertex",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Vertex", targets: ["Vertex"])
    ],
    targets: [
        .target(
            name: "CTorrent",
            path: "Sources/CTorrent",
            publicHeadersPath: "include",
            cxxSettings: [
                .define("TORRENT_USE_OPENSSL", to: "1"),
                .unsafeFlags([
                    "-I\(libtorrent)/include",
                    "-I\(boost)/include",
                    "-I\(openssl)/include"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(libtorrent)/lib",
                    "-L\(openssl)/lib"
                ]),
                .linkedLibrary("torrent-rasterbar"),
                .linkedLibrary("ssl"),
                .linkedLibrary("crypto")
            ]
        ),
        .executableTarget(
            name: "Vertex",
            dependencies: ["CTorrent"],
            path: "Sources/Vertex"
        )
    ],
    cxxLanguageStandard: .cxx17
)
