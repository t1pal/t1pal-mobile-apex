# Dexcom G6 Authentication Test Vectors

> **Source**: CGMBLEKit (LoopKit)  
> **Protocol**: Dexcom G6 AES-128-ECB authentication  
> **Last Updated**: 2026-02-08

## Protocol Overview

The Dexcom G6 uses AES-128-ECB for mutual authentication:

1. **Key Derivation**: `cryptKey = "00" + transmitterId + "00" + transmitterId` (16 bytes as UTF-8)
2. **Token Hash**: Encrypt `token + token` (8 + 8 = 16 bytes) with cryptKey, return first 8 bytes
3. **Challenge Response**: Same algorithm, encrypt `challenge + challenge`

## Authentication Flow

```
Client                                    Transmitter
  |                                           |
  |----[AuthRequestTx: token]---------------->|
  |                                           |
  |<---[AuthRequestRx: tokenHash, challenge]--|
  |                                           |
  |  verify: tokenHash == AES(token+token)    |
  |                                           |
  |----[AuthChallengeTx: challengeHash]------>|
  |                                           |
  |<---[AuthChallengeRx: authenticated, bonded]|
```

## Message Formats

| Message | Opcode | Format |
|---------|--------|--------|
| AuthRequestTx | 0x01 | opcode(1) + token(8) + endByte(1) |
| AuthRequestRx | 0x03 | opcode(1) + tokenHash(8) + challenge(8) |
| AuthChallengeTx | 0x04 | opcode(1) + challengeHash(8) |
| AuthChallengeRx | 0x05 | opcode(1) + authenticated(1) + bonded(1) |

## Files

- `test-vectors.json` — Known-good test vectors from CGMBLEKit
- `constants.json` — Protocol constants and opcodes
