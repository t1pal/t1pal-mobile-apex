// CGMKitShare - Cloud CGM clients without HealthKit
// SPDX-License-Identifier: AGPL-3.0-or-later

/// CGMKitShare provides cloud-based CGM data clients for apps
/// that need remote glucose data without local sensor access.
///
/// Included clients:
/// - DexcomShareClient: Dexcom Share/Clarity cloud API
/// - LibreLinkUpClient: Abbott LibreView/LibreLinkUp cloud API
///
/// This package explicitly excludes HealthKit dependencies to support
/// follower apps that shouldn't request health data permissions.
