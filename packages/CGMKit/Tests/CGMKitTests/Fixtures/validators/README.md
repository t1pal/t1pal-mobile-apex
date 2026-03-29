# Cross-Implementation Validators

> **Trace**: PROTO-CMP-004
> **Purpose**: Validate T1Pal implementations match reference implementations

## Overview

This directory contains test fixtures for cross-implementation validation.
The validators ensure our CGM protocol implementations produce identical output
to reference implementations from CGMBLEKit, LibreTransmitter, and xDrip.

## Validated Protocols

| Protocol | Reference | Tests | Status |
|----------|-----------|-------|--------|
| G6 Auth | CGMBLEKit | 10 | ✅ Validated |
| Libre2 Crypto | LibreTransmitter | 19 | ✅ Validated |
| G7 J-PAKE | xDrip libkeks | 12 | ✅ Validated |

## Validator Pattern

Each validator follows the same pattern:

```swift
protocol ImplementationValidator {
    associatedtype Input
    associatedtype Output
    
    /// Name of the reference implementation
    var referenceName: String { get }
    
    /// Run our implementation
    func runOurImplementation(_ input: Input) throws -> Output
    
    /// Expected output from reference
    func expectedOutput(for input: Input) -> Output
    
    /// Compare outputs
    func validate(_ input: Input) throws -> ValidationResult
}
```

## Test Vector Sources

- **g6auth/**: CGMBLEKit TransmitterIDTests vectors
- **libre2/**: LibreTransmitter PreLibre2 examples
- **jpake/**: xDrip libkeks and DiaBLE captures

## Validation Levels

1. **Constant Matching**: Key constants (magic bytes, curves)
2. **Function Matching**: Individual crypto functions
3. **Flow Matching**: Complete protocol sequences
4. **Interop Matching**: Can authenticate with real devices

## Adding New Validators

1. Extract test vectors from reference implementation
2. Create fixtures in appropriate subdirectory
3. Implement `ImplementationValidator` conformance
4. Add tests to `CrossImplementationValidatorTests.swift`
