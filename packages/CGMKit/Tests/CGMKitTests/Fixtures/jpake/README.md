# Dexcom G7 J-PAKE Protocol Fixtures

Reference data extracted from open-source implementations for cross-validation.

## Sources

- **xDrip libkeks**: `externals/xDrip/libkeks/` - Java/BouncyCastle implementation
- **DiaBLE**: `externals/DiaBLE/DiaBLE/DexcomG7.swift` - Swift implementation (partial)
- **G7SensorKit**: `externals/G7SensorKit/` - LoopKit implementation

## Protocol Overview (RFC 8236)

J-PAKE (Password Authenticated Key Exchange by Juggling) is a PAKE protocol that:
1. Uses a shared secret (sensor code) known to both parties
2. Establishes a secure session key
3. Provides zero-knowledge proofs to prevent password exposure

## Message Format

Each J-PAKE round uses a 160-byte packet structure:

```
Offset  Size  Field
------  ----  -----
0       32    Point 1 X coordinate (g^x1 or A)
32      32    Point 1 Y coordinate
64      32    Point 2 X coordinate (V = g^v for ZKP)
96      32    Point 2 Y coordinate  
128     32    ZKP hash/exponent (r = v - hash * x)
```

## Curve Parameters (secp256r1 / P-256)

```json
{
  "name": "secp256r1",
  "field_size": 32,
  "packet_size": 160,
  "generator_x": "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296",
  "generator_y": "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5",
  "order_n": "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551"
}
```

## Party Identifiers (xDrip constants)

- Client ("alice"): `36C69656E647` (6 bytes)
- Server ("bob"): `375627675627` (6 bytes)

## Password Format

- **4-digit code**: Raw UTF-8 bytes (`"1234"` → `0x31 0x32 0x33 0x34`)
- **6-digit code**: Prefix `"00"` + UTF-8 (`"123456"` → `0x30 0x30 0x31 0x32 0x33 0x34 0x35 0x36`)

## Protocol Flow

### Round 1
1. Generate x1, x2 (random exponents)
2. Compute g^x1, g^x2 (public keys)
3. Generate ZKP for x1: (V1 = g^v1, r1 = v1 - hash * x1)
4. Generate ZKP for x2: (V2 = g^v2, r2 = v2 - hash * x2)
5. Send packet with g^x1, ZKP1 (or g^x2, ZKP2 depending on phase)

### Round 2  
1. Receive remote g^x3, g^x4 (and verify ZKPs)
2. Compute A = (g^x1 + g^x3 + g^x4)^(x2 * s) where s = password
3. Generate ZKP for x2*s
4. Send packet with A, ZKP

### Key Derivation
1. Compute K = SHA256(shared_secret.x_coordinate)
2. Truncate to 16 bytes for AES-128 key

## Test Vectors

See `round1-format.json`, `round2-format.json`, `constants.json`.

## Trace

- PROTO-CMP-002: Import DiaBLE G7 J-PAKE captures
- JPAKE-REF-001: Reference analysis  
- PRD-008 REQ-BLE-008: Dexcom G7 BLE authentication
