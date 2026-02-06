// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [:]
)
#endif

let package = Package(
    name: "Moremaid",
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox", from: "0.26.2"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
    ]
)
