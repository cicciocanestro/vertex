// swift-tools-version: 5.10
import Foundation
import PackageDescription

let homebrew = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] ?? "/opt/homebrew"
let libtorrent = "\(homebrew)/opt/libtorrent-rasterbar"
let boost = "\(homebrew)/opt/boost"
let openssl = "\(homebrew)/opt/openssl@4"

let package = Package(
    name: "Vertex",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vertex", targets: ["Vertex"]),
        .library(name: "VertexKit", targets: ["VertexKit"])
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
        .target(
            name: "VertexKit",
            dependencies: ["CTorrent"],
            path: "Sources/VertexKit"
        ),
        .executableTarget(
            name: "Vertex",
            dependencies: ["VertexKit"],
            path: "Sources/Vertex"
        ),
        .executableTarget(
            name: "VertexTestRunner",
            dependencies: ["VertexKit", "CTorrent"],
            path: "Tests/VertexTests"
        )
    ],
    cxxLanguageStandard: .cxx17
)
