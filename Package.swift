// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NewWorldView",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "NewWorldROM", targets: ["NewWorldROM"]),
        .executable(name: "NewWorldViewCLI", targets: ["NewWorldViewCLI"])
    ],
    dependencies: [
        // Versioned SPM deps cannot expose unsafe flags; pin the Capstone 0.1.2 tag by revision.
        .package(url: "https://github.com/Lakr233/libcapstone-spm.git", revision: "dcf8f40adcfce8720f817ebbe35f49938db42bfd")
    ],
    targets: [
        .target(
            name: "NewWorldROM",
            dependencies: [
                .product(name: "Capstone", package: "libcapstone-spm")
            ],
            path: "Sources/NewWorldROM",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedLibrary("z")
            ]
        ),
        .testTarget(
            name: "NewWorldROMTests",
            dependencies: ["NewWorldROM"],
            path: "Tests/NewWorldROMTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
        .executableTarget(
            name: "NewWorldViewCLI",
            dependencies: ["NewWorldROM"],
            path: "Sources/NewWorldViewCLI"
        )
    ]
)
