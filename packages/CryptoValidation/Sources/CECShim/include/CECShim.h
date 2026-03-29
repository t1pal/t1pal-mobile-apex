// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CECShim.h
// Thin C wrapper for EC point operations
//
// Purpose: Expose EC_POINT_add/mul from BoringSSL to Swift
// Trace: EC-LIB-016
//
// NOTE: This is a skeleton for EC-LIB-016. Full implementation requires:
// 1. Linking against BoringSSL (from swift-crypto)
// 2. Implementing ec_point_add/mul wrappers
// 3. Managing EC_GROUP/EC_POINT lifetimes

#ifndef CECSHIM_H
#define CECSHIM_H

#include <stdint.h>
#include <stddef.h>

// Opaque handles (to be backed by BoringSSL types)
typedef void* ECGroupRef;
typedef void* ECPointRef;

// Initialize P-256 group (returns NULL on error)
ECGroupRef ec_group_p256(void);

// Free group
void ec_group_free(ECGroupRef group);

// Create point at infinity
ECPointRef ec_point_new(ECGroupRef group);

// Free point
void ec_point_free(ECPointRef point);

// Set point from uncompressed bytes (65 bytes for P-256)
// Returns 0 on success, -1 on error
int ec_point_from_bytes(ECGroupRef group, ECPointRef point, const uint8_t* bytes, size_t len);

// Get point as uncompressed bytes
// Returns number of bytes written, or -1 on error
int ec_point_to_bytes(ECGroupRef group, ECPointRef point, uint8_t* out, size_t out_len);

// Point addition: result = a + b
// Returns 0 on success, -1 on error
int ec_point_add(ECGroupRef group, ECPointRef result, ECPointRef a, ECPointRef b);

// Scalar multiplication: result = scalar * point
// scalar is 32 bytes for P-256
// Returns 0 on success, -1 on error
int ec_point_mul(ECGroupRef group, ECPointRef result, ECPointRef point, const uint8_t* scalar, size_t scalar_len);

// Scalar base multiplication: result = scalar * G (generator)
// Returns 0 on success, -1 on error
int ec_point_mul_base(ECGroupRef group, ECPointRef result, const uint8_t* scalar, size_t scalar_len);

// Check if point is on curve
// Returns 1 if valid, 0 if invalid, -1 on error
int ec_point_is_on_curve(ECGroupRef group, ECPointRef point);

#endif // CECSHIM_H
