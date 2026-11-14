// swift-tools-version: 5.9
 
 
 
 
 
 
 
 
 
 
 
 
 

import PackageDescription

 
 
import class Foundation.ProcessInfo

let package = Package(
    name: "swift-certificates",
    products: [
        .library(
            name: "X509",
            targets: ["X509"]
        )
    ],
    targets: [
        .target(
            name: "X509",
            dependencies: [
                "_CertificateInternals",
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            exclude: [
                "CMakeLists.txt"
            ]
        ),
        .target(
            name: "_CertificateInternals",
            exclude: [
                "CMakeLists.txt"
            ]
        ),
    ]
)

 
 
 
if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.1.0"),
    ]
} else {
    package.dependencies += [
        .package(path: "../swift-crypto"),
        .package(path: "../swift-asn1"),
    ]
}

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(.enableExperimentalFeature("StrictConcurrency=complete"))
    target.swiftSettings = settings
}

 
for target in package.targets {
    switch target.type {
    case .regular, .test, .executable:
        var settings = target.swiftSettings ?? []
         
        settings.append(.enableUpcomingFeature("MemberImportVisibility"))
        target.swiftSettings = settings
    case .macro, .plugin, .system, .binary:
        ()   
    @unknown default:
        ()   
    }
}
 
