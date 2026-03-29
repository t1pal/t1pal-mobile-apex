// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CECShim.c
// Stub implementation for EC point operations
//
// Trace: EC-LIB-016
//
// STATUS: STUB - Returns errors for all operations
// Full implementation requires linking against BoringSSL.
//
// To complete EC-LIB-016:
// 1. Add dependency on CCryptoBoringSSL
// 2. Replace stubs with actual BoringSSL calls
// 3. Verify on Apple platform (iOS/macOS)

#include "include/CECShim.h"
#include <stdlib.h>

// Stub implementations - all return NULL/error

ECGroupRef ec_group_p256(void) {
    // TODO: return EC_GROUP_new_by_curve_name(NID_X9_62_prime256v1)
    return NULL;
}

void ec_group_free(ECGroupRef group) {
    // TODO: EC_GROUP_free((EC_GROUP*)group)
    (void)group;
}

ECPointRef ec_point_new(ECGroupRef group) {
    // TODO: return EC_POINT_new((EC_GROUP*)group)
    (void)group;
    return NULL;
}

void ec_point_free(ECPointRef point) {
    // TODO: EC_POINT_free((EC_POINT*)point)
    (void)point;
}

int ec_point_from_bytes(ECGroupRef group, ECPointRef point, const uint8_t* bytes, size_t len) {
    // TODO: EC_POINT_oct2point
    (void)group; (void)point; (void)bytes; (void)len;
    return -1; // Not implemented
}

int ec_point_to_bytes(ECGroupRef group, ECPointRef point, uint8_t* out, size_t out_len) {
    // TODO: EC_POINT_point2oct
    (void)group; (void)point; (void)out; (void)out_len;
    return -1; // Not implemented
}

int ec_point_add(ECGroupRef group, ECPointRef result, ECPointRef a, ECPointRef b) {
    // TODO: EC_POINT_add
    (void)group; (void)result; (void)a; (void)b;
    return -1; // Not implemented
}

int ec_point_mul(ECGroupRef group, ECPointRef result, ECPointRef point, const uint8_t* scalar, size_t scalar_len) {
    // TODO: EC_POINT_mul
    (void)group; (void)result; (void)point; (void)scalar; (void)scalar_len;
    return -1; // Not implemented
}

int ec_point_mul_base(ECGroupRef group, ECPointRef result, const uint8_t* scalar, size_t scalar_len) {
    // TODO: EC_POINT_mul with NULL point (uses generator)
    (void)group; (void)result; (void)scalar; (void)scalar_len;
    return -1; // Not implemented
}

int ec_point_is_on_curve(ECGroupRef group, ECPointRef point) {
    // TODO: EC_POINT_is_on_curve
    (void)group; (void)point;
    return -1; // Not implemented
}
