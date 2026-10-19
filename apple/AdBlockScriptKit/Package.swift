// swift-tools-version: 6.0
import PackageDescription

// The parts of the script runtime that have nothing to do with a JavaScript
// engine: what a platform looks like, how `$done` payloads are read, how a run
// is bounded, and the runner itself. It builds for Linux (with the
// JavaScriptCore C API) so the same sources can be tested on a workstation and
// compiled into the tunnel extension.
let package = Package(
    name: "AdBlockScriptKit",
    platforms: [.iOS(.v15), .macOS(.v13), .tvOS(.v17)],
    products: [.library(name: "AdBlockScriptKit", targets: ["AdBlockScriptKit"])],
    targets: [
        // On Apple platforms `import JavaScriptCore` is the framework Swift
        // ships with; on Linux there is no module map for the C API, so this
        // system library supplies one. The shim header is the same C API either
        // way, which is what lets the engine be compiled and tested off-device.
        .systemLibrary(name: "CJavaScriptCore", path: "Sources/CJavaScriptCore"),
        .target(
            name: "AdBlockScriptKit",
            dependencies: ["CJavaScriptCore"],
            resources: [.copy("Resources/ScriptPrelude.js")]
            // No `unsafeFlags` here: Xcode refuses a package product that uses
            // them, and the extension already builds with `-Osize` from its own
            // target settings.
        ),
        .testTarget(
            name: "AdBlockScriptKitTests",
            dependencies: ["AdBlockScriptKit"],
            // The fixtures are what the tests read: the real compatibility
            // library scripts ship with, and real plugin files to parse.
            resources: [.copy("Fixtures")])
    ]
)
