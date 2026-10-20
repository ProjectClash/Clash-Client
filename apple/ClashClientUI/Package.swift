// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ClashClientUI", platforms: [.iOS(.v15), .macOS(.v13), .tvOS(.v17)], products: [.library(name: "ClashClientUI", targets: ["ClashClientUI"])], dependencies: [.package(path: "../ClashClientKit")], targets: [.target(name: "ClashClientUI", dependencies: ["ClashClientKit"], resources: [.copy("Resources/FieldCopy")], swiftSettings: [.unsafeFlags(["-Osize"], .when(platforms: [.iOS, .macOS], configuration: .release))]), .testTarget(name: "ClashClientUITests", dependencies: ["ClashClientUI"])])
