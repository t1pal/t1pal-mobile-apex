# T1Pal Open Core

> **License**: AGPL-3.0-or-later  
> **Status**: Active

Cross-platform infrastructure packages for the AID (Automated Insulin Delivery) ecosystem. These modules power both the commercial T1Pal apps and the open-source T1PalResearch AID.

## Packages

| Package | Layer | Purpose |
|---------|-------|---------|
| **T1PalCore** | 0 | Core types, glucose models, GRDB persistence |
| **T1PalCompatKit** | 0 | Platform capability detection |
| **BLEKit** | 1 | Cross-platform Bluetooth Low Energy abstraction |
| **CryptoValidation** | 1 | Elliptic curve crypto (J-PAKE for Dexcom G7) |
| **T1PalAlgorithm** | 1 | AID algorithm adapters (oref0/oref1, Loop) |
| **NightscoutKit** | 2 | Nightscout REST/WebSocket API client |
| **CGMKit** | 3 | CGM protocols (Dexcom G6/G7, Libre 2/3) |
| **CGMKitShare** | 3 | Cloud CGM clients (Dexcom Share, LibreLinkUp) |
| **PumpKit** | 3 | Pump protocols (Omnipod, Medtronic, Tandem, Dana) |

## Usage

### As a local dependency (development)

```swift
// In your Package.swift
dependencies: [
    .package(path: "../t1pal-mobile-apex"),
]
```

### Individual package

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "CGMKit", package: "T1PalOpenCore"),
        .product(name: "NightscoutKit", package: "T1PalOpenCore"),
    ]
)
```

## Building

```bash
swift build          # Build all packages
swift test           # Run all tests
swift build --skip-tests -c release  # Release build
```

## Relationship to t1pal-mobile-workspace

This repo contains the open-source core extracted from the T1Pal monorepo.
The monorepo depends on this package for its infrastructure layer and adds
proprietary app packages (T1PalAIDKit, T1PalRemoteKit, etc.) on top.

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE) for details.

Commercial licensing available for embedding in proprietary products.
Contact: licensing@t1pal.org
