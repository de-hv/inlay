// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .strictMemorySafety(),
]

// scripts/build-app.sh writes the version and the git hash of the build to .build/build-info/inlay_build_info_values.h,
// outside of the sources: a plain 'swift build' gets the defaults of Sources/BuildInfo/BuildInfo.c. They aren't
// settings of the manifest: a setting that changes (the git hash changes with every commit) makes SwiftPM build
// everything again, while a header that changes only builds BuildInfo.c again, and links
let buildInfoSettings: [CSetting] = [
    .unsafeFlags(["-I", Context.packageDirectory + "/.build/build-info"]),
]

// With the Command Line Tools, an incremental build of the test target that follows a change in the app sources
// (or a plain 'swift build') fails with "plugin for module 'TestingMacros' not found": the compiler isn't told
// where the macros of Swift Testing are. Only a build of the test target from scratch gets it right.
// Pointing the compiler to the plugin directory of the toolchain in use makes every build work.
// Xcode keeps the plugin somewhere else and doesn't have the problem, so nothing is added for it
let testingMacrosSettings: [SwiftSetting] = {
    // The toolchain in use: DEVELOPER_DIR, then the choice of xcode-select, then Xcode.app, then the Command Line Tools
    let fileManager = FileManager.default
    let developerDir = Context.environment["DEVELOPER_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        ?? (try? fileManager.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
        ?? (fileManager.fileExists(atPath: "/Applications/Xcode.app") ? nil : "/Library/Developer/CommandLineTools")
    guard let developerDir else { return [] }
    let pluginDir = developerDir + "/usr/lib/swift/host/plugins/testing"
    return fileManager.fileExists(atPath: pluginDir + "/libTestingMacros.dylib")
        ? [.unsafeFlags(["-plugin-path", pluginDir])]
        : []
}()

let package = Package(
    name: "Inlay",
    platforms: [.macOS(.v14)],
    // Products define the executables and libraries a package produces, making them visible to other packages.
    products: [
        // The CLI client. It only talks to the server over a unix socket
        .executable(name: "inlay", targets: ["Cli"]),
        // The server (window manager + menu bar). scripts/build-app.sh wraps it into Inlay.app
        // It can't be called 'Inlay': on a case-insensitive file system it would overwrite the 'inlay' CLI
        .executable(name: "InlayApp", targets: ["InlayApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/InerziaSoft/ISSoundAdditions.git", exact: "2.0.1"),
        .package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.4.4"),
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.3.0"),
        .package(url: "https://github.com/soffes/HotKey.git", exact: "0.2.1"),
    ],
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    targets: [
        // Exposes the private _AXUIElementGetWindow function to swift
        .target(
            name: "PrivateApi",
            path: "Sources/PrivateApi",
            publicHeadersPath: "include",
        ),
        // Version and git hash of the build
        .target(
            name: "BuildInfo",
            cSettings: buildInfoSettings,
        ),
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .target(name: "BuildInfo"),
            ],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "AppBundle",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "ISSoundAdditions", package: "ISSoundAdditions"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
                .target(name: "Common"),
                .target(name: "PrivateApi"),
            ],
            swiftSettings: swiftSettings,
        ),
        .executableTarget(
            name: "InlayApp",
            dependencies: [
                .target(name: "AppBundle"),
            ],
            swiftSettings: swiftSettings,
        ),
        .executableTarget(
            name: "Cli",
            dependencies: [
                .target(name: "Common"),
            ],
            swiftSettings: swiftSettings,
        ),
        // Swift Testing suite. It builds and runs with the Command Line Tools alone: swift test
        .testTarget(
            name: "InlayTests",
            dependencies: [
                .target(name: "AppBundle"),
            ],
            // Config files that the tests read from the source tree
            exclude: ["fixtures"],
            swiftSettings: swiftSettings + testingMacrosSettings,
        ),
    ],
)
