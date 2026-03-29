#if canImport(SwiftUI) && canImport(Observation)
// SPDX-License-Identifier: AGPL-3.0-or-later
// T1PalCore - ContextIndicatorView (DEPRECATED)
// This file is kept for backwards compatibility only.
// Canonical implementation is now in T1PalUI (ARCH-003)
//
// New code should import T1PalUI for ContextIndicatorView

import SwiftUI
import Observation

// MARK: - Deprecated Notice

/// ContextIndicatorView has graduated to T1PalUI
/// This stub exists for backwards compatibility
/// Import T1PalUI for the canonical implementation
@available(*, deprecated, message: "Import T1PalUI instead for ContextIndicatorView")
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public typealias ContextIndicatorViewLegacy = LegacyContextIndicatorView

/// Legacy placeholder - actual implementation is in T1PalUI
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public struct LegacyContextIndicatorView: View {  // swiftlint:disable:this type_name
    public init() {}
    
    public var body: some View {
        Text("⚠️ Use T1PalUI.ContextIndicatorView")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
#endif
