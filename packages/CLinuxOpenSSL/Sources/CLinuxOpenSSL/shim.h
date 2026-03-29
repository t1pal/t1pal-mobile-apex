// SPDX-License-Identifier: AGPL-3.0-or-later
//
// shim.h
// CLinuxOpenSSL - Shim header for system OpenSSL
//
// Trace: EC-LIB-017
//
// This header re-exports OpenSSL EC functions needed for P-256 operations.
// On Linux, this links against system OpenSSL (libssl, libcrypto).

#ifndef CLINUXOPENSSL_SHIM_H
#define CLINUXOPENSSL_SHIM_H

#include <openssl/ec.h>
#include <openssl/bn.h>
#include <openssl/obj_mac.h>
#include <openssl/err.h>

#endif // CLINUXOPENSSL_SHIM_H
