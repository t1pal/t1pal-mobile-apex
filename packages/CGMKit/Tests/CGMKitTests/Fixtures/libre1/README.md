# Libre 1 FRAM Test Vectors

> **Source**: xDrip (Android), DiaBLE (iOS)  
> **Protocol**: Libre 1 unencrypted FRAM  
> **Task**: LIBRE-SYNTH-006  
> **Last Updated**: 2026-02-13

## Protocol Overview

Libre 1 sensors use **unencrypted** NFC FRAM memory (344 bytes). Data is read directly via ISO 15693 NFC commands without decryption.

## FRAM Structure (344 bytes)

| Section | Offset | Size | Description |
|---------|--------|------|-------------|
| Header  | 0-23   | 24   | CRC, state, failure info |
| Body    | 24-319 | 296  | Trend (16×6) + History (32×6) + age |
| Footer  | 320-343| 24   | CRC, region, maxLife, calibration |

## Sensor Identification

| patchInfo[0] | Type | Notes |
|--------------|------|-------|
| 0xDF | Libre 1 | Original |
| 0xA2 | Libre 1 | Newer variant |
| 0xE5, 0xE6 | Libre US 14day | Encrypted |
| 0x70 | Libre Pro/H | Professional |

## Glucose Record Format (6 bytes)

Each trend/history reading is 6 bytes with bit-packed fields:

- **rawValue**: bits 0-13 (14 bits) - raw glucose value
- **quality**: bits 14-22 (9 bits) - quality flags
- **qualityFlags**: bits 23-24 (2 bits) - additional flags
- **hasError**: bit 25 (1 bit) - error indicator
- **rawTemperature**: bits 26-37 (12 bits, shifted left 2)
- **temperatureAdjustment**: bits 38-46 (9 bits, shifted left 2)
- **negativeAdjustment**: bit 47 (1 bit) - if set, adjustment is negative

## Files

- `fixture_libre1_fram.json` — Full FRAM test vectors with parsing structure

## Key Differences from Libre 2

| Aspect | Libre 1 | Libre 2 |
|--------|---------|---------|
| Encryption | None | XOR stream cipher |
| NFC Read | Direct | Requires decryption |
| BLE | Via transmitter only | Native BLE |
| patchInfo[0] | 0xDF, 0xA2 | 0x9D, 0xC5 |
