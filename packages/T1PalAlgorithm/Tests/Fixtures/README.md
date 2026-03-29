# Ecosystem Test Fixtures

This directory contains test fixtures imported from the DIY AID ecosystem for conformance testing.

## Contents

### `oref0-vectors/` (77 files)

Real-world algorithm test vectors captured from oref0 runs. Each file contains:
- Input state (glucose history, IOB, COB, profile)
- Expected output (temp basal rate, duration, reason)

**Source**: `rag-nightscout-ecosystem-alignment/conformance/vectors/basal-adjustment/`

**Usage**:
```swift
func testOref0Conformance() throws {
    let vectorURL = Bundle.module.url(forResource: "TV-001-2023-10-28_133013", 
                                       withExtension: "json",
                                       subdirectory: "oref0-vectors")!
    let data = try Data(contentsOf: vectorURL)
    let vector = try JSONDecoder().decode(TestVector.self, from: data)
    
    let output = try algorithm.calculate(vector.inputs)
    XCTAssertEqual(output.rate, vector.expected.rate, accuracy: 0.05)
}
```

### `oref0-examples/` (11 files)

Sample Nightscout data from oref0 documentation:

| File | Description |
|------|-------------|
| `glucose.json` | 274 CGM readings (24 hours) |
| `pumphistory.json` | Pump events (bolus, temp basal) |
| `carbhistory.json` | Carb entries |
| `profile.json` | Complete therapy profile |
| `iob.json` | IOB snapshot |
| `autosens.json` | Sensitivity ratio |
| `meal.json` | Active meal data |
| `suggested.json` | Algorithm suggestion |
| `basal_profile.json` | Basal schedule |
| `temp_basal.json` | Current temp basal |
| `clock.json` | Pump clock |

**Source**: `rag-nightscout-ecosystem-alignment/externals/oref0/examples/`

### `loopkit/InsulinKit/` (43 files)

Gold-standard IOB/insulin effect calculations from LoopKit:

| Category | Files | Purpose |
|----------|-------|---------|
| IOB calculations | `iob_from_*.json` | Validate IOB math |
| Insulin effects | `effect_from_*.json` | Glucose prediction |
| Dose normalization | `normalize_*.json` | Dose processing |
| Reservoir history | `reservoir_*.json` | Pump data handling |

**Critical for Loop algorithm port (ALG-015 through ALG-020)**

**Source**: `rag-nightscout-ecosystem-alignment/externals/Trio/LoopKit/LoopKitTests/Fixtures/InsulinKit/`

## How to Use

### 1. Add to Package.swift resources

```swift
.testTarget(
    name: "T1PalAlgorithmTests",
    dependencies: ["T1PalAlgorithm"],
    resources: [
        .copy("Fixtures/oref0-vectors"),
        .copy("Fixtures/oref0-examples"),
        .copy("Fixtures/loopkit"),
    ]
),
```

### 2. Create fixture loader

```swift
extension XCTestCase {
    func loadFixture<T: Decodable>(_ name: String, subdirectory: String) throws -> T {
        let url = Bundle.module.url(forResource: name, 
                                     withExtension: "json",
                                     subdirectory: subdirectory)!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

### 3. Run conformance tests

```swift
func testAllOref0Vectors() throws {
    let vectorDir = Bundle.module.url(forResource: "oref0-vectors", withExtension: nil)!
    let vectors = try FileManager.default.contentsOfDirectory(at: vectorDir, 
                                                               includingPropertiesForKeys: nil)
    for vectorURL in vectors where vectorURL.pathExtension == "json" {
        let vector = try loadVector(vectorURL)
        let output = try algorithm.calculate(vector.inputs)
        // Assert...
    }
}
```

## Updating Fixtures

To refresh fixtures from ecosystem analysis:

```bash
# From t1pal-mobile-workspace root
cp -r ../rag-nightscout-ecosystem-alignment/conformance/vectors/basal-adjustment/*.json \
      packages/T1PalAlgorithm/Tests/Fixtures/oref0-vectors/

cp ../rag-nightscout-ecosystem-alignment/externals/oref0/examples/*.json \
   packages/T1PalAlgorithm/Tests/Fixtures/oref0-examples/

cp ../rag-nightscout-ecosystem-alignment/externals/Trio/LoopKit/LoopKitTests/Fixtures/InsulinKit/*.json \
   packages/T1PalAlgorithm/Tests/Fixtures/loopkit/InsulinKit/
```

## License

These fixtures are derived from open-source projects:
- oref0: MIT License
- LoopKit: MIT License
- Trio: AGPL-3.0

See original repositories for full license terms.
