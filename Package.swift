// swift-tools-version: 6.0
// T1Pal Open Core — Shared infrastructure for AID ecosystem
//
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 T1Pal
//
// These packages provide cross-platform BLE, CGM, pump, algorithm, and
// Nightscout infrastructure for both T1Pal commercial apps and the
// open-source T1PalResearch AID.
//
// Consumable as:
//   .package(path: "../t1pal-mobile-apex")   // local development
//   .package(url: "https://...", from: "1.0.0")  // published release

import PackageDescription

let package = Package(
    name: "T1PalOpenCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "T1PalCore", targets: ["T1PalCore"]),
        .library(name: "T1PalCompatKit", targets: ["T1PalCompatKit"]),
        .library(name: "BLEKit", targets: ["BLEKit"]),
        .library(name: "CryptoValidation", targets: ["CryptoValidation"]),
        .library(name: "T1PalAlgorithm", targets: ["T1PalAlgorithm"]),
        .library(name: "NightscoutKit", targets: ["NightscoutKit"]),
        .library(name: "CGMKit", targets: ["CGMKit"]),
        .library(name: "CGMKitShare", targets: ["CGMKitShare"]),
        .library(name: "PumpKit", targets: ["PumpKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0"),
        .package(url: "https://github.com/krzyzanowskim/OpenSSL-Package.git", from: "3.3.2000"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        // MARK: - Foundation (Layer 0)

        .target(
            name: "T1PalCore",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "packages/T1PalCore/Sources/T1PalCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "T1PalCoreTests",
            dependencies: ["T1PalCore"],
            path: "packages/T1PalCore/Tests/T1PalCoreTests",
            resources: [.copy("Fixtures")]
        ),

        .target(
            name: "T1PalCompatKit",
            dependencies: [],
            path: "packages/T1PalCompatKit/Sources/T1PalCompatKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "T1PalCompatKitTests",
            dependencies: ["T1PalCompatKit"],
            path: "packages/T1PalCompatKit/Tests/T1PalCompatKitTests"
        ),

        // MARK: - Infrastructure (Layer 1)

        .target(
            name: "BLEKit",
            dependencies: ["T1PalCore"],
            path: "packages/BLEKit/Sources/BLEKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BLEKitTests",
            dependencies: ["BLEKit"],
            path: "packages/BLEKit/Tests/BLEKitTests",
            resources: [.copy("Fixtures")]
        ),

        .systemLibrary(
            name: "CLinuxOpenSSL",
            path: "packages/CLinuxOpenSSL/Sources/CLinuxOpenSSL",
            pkgConfig: "openssl",
            providers: [
                .apt(["libssl-dev"]),
            ]
        ),

        .target(
            name: "CryptoValidation",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "OpenSSL", package: "OpenSSL-Package", condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .visionOS, .macCatalyst])),
                .target(name: "CLinuxOpenSSL", condition: .when(platforms: [.linux])),
            ],
            path: "packages/CryptoValidation/Sources/CryptoValidation",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CryptoValidationTests",
            dependencies: ["CryptoValidation", "CGMKit"],
            path: "packages/CryptoValidation/Tests/CryptoValidationTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .target(
            name: "T1PalAlgorithm",
            dependencies: ["T1PalCore"],
            path: "packages/T1PalAlgorithm/Sources/T1PalAlgorithm",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "T1PalAlgorithmTests",
            dependencies: ["T1PalAlgorithm"],
            path: "packages/T1PalAlgorithm/Tests/T1PalAlgorithmTests",
            resources: [.copy("Fixtures")]
        ),

        // MARK: - Protocol Layer (Layer 2)

        .target(
            name: "NightscoutKit",
            dependencies: [
                "T1PalCore",
                "T1PalAlgorithm",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            path: "packages/NightscoutKit/Sources/NightscoutKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NightscoutKitTests",
            dependencies: ["NightscoutKit", "T1PalAlgorithm"],
            path: "packages/NightscoutKit/Tests/NightscoutKitTests",
            resources: [.copy("Fixtures")]
        ),

        // MARK: - Device Layer (Layer 3)

        .target(
            name: "CGMKitShare",
            dependencies: ["T1PalCore"],
            path: "packages/CGMKitShare/Sources/CGMKitShare",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .target(
            name: "CGMKit",
            dependencies: [
                "T1PalCore",
                "NightscoutKit",
                "BLEKit",
                "T1PalCompatKit",
                "CryptoValidation",
                "CGMKitShare",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
            ],
            path: "packages/CGMKit/Sources/CGMKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CGMKitTests",
            dependencies: ["CGMKit", "BLEKit", "T1PalCompatKit", "CryptoValidation"],
            path: "packages/CGMKit/Tests/CGMKitTests",
            resources: [.copy("Fixtures")]
        ),

        .target(
            name: "PumpKit",
            dependencies: [
                "T1PalCore",
                "NightscoutKit",
                "BLEKit",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "packages/PumpKit/Sources/PumpKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PumpKitTests",
            dependencies: ["PumpKit"],
            path: "packages/PumpKit/Tests/PumpKitTests",
            exclude: ["MedtronicPlaygroundStateTests.swift.disabled"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
