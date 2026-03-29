# Libre 2 Decryption Test Vectors

> **Source**: LibreTransmitter (LoopKit)  
> **Protocol**: Libre 2 XOR-based stream cipher  
> **Last Updated**: 2026-02-08

## Protocol Overview

Libre 2 uses a custom XOR-based stream cipher for both FRAM and BLE data encryption.
The cipher uses the sensor UID as a key seed, with additional parameters (patch info,
block number) to generate per-block or per-packet key streams.

## Decryption Methods

### FRAM Decryption

- **Input**: 344 bytes (43 blocks × 8 bytes), sensor UID (8 bytes), patch info (6 bytes)
- **Output**: 344 bytes decrypted FRAM
- **Algorithm**: Per-block XOR with generated keystream

### BLE Decryption

- **Input**: 46 bytes encrypted BLE notification, sensor UID (8 bytes)
- **Output**: 44 bytes decrypted (first 2 bytes removed, last 2 bytes CRC)
- **Algorithm**: Stream XOR with chained keystream generation

## Key Constants

```swift
static let key: [UInt16] = [0xA0C5, 0x6860, 0x0000, 0x14C6]
```

## Files

- `test-vectors.json` — Known-good test vectors from LibreTransmitter
- `constants.json` — Protocol constants and crypto parameters
- `fixture_libre_fram.json` — Full FRAM (344 bytes) and BLE (46 bytes) vectors with parsing structure (LIBRE-SYNTH-001)
