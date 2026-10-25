// swift-tools-version: 5.10
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let depsPrefix = ProcessInfo.processInfo.environment["VERTEX_DEPS_PREFIX"]
    ?? packageDirectory.appendingPathComponent(".build/vertex-deps").path

let package = Package(
    name: "Vertex",
    platforms: [.macOS("15.0")],
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
                .define("TORRENT_ABI_VERSION", to: "2"),
                .unsafeFlags([
                    "-I\(depsPrefix)/include"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(depsPrefix)/lib",
                    "-Xlinker", "-rpath", "-Xlinker", "\(depsPrefix)/lib"
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
            dependencies: ["VertexKit", "CTorrent"],
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
