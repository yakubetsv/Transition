// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppModules",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AppModules",
            targets: ["AppModules"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nathantannar4/Transmission", from: "2.14.4"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AppModules",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Transmission", package: "Transmission"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
