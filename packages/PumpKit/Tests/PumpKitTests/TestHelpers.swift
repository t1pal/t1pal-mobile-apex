// SPDX-License-Identifier: MIT
//
// TestHelpers.swift
// PumpKitTests
//
// Shared test utilities for PumpKit tests
// MDT-HIST-020: Consolidated hex utilities

import Foundation

// MARK: - Data Hex Extensions

extension Data {
    /// Initialize Data from a hex string
    /// Supports both contiguous ("a7594040") and spaced ("a7 59 40 40") formats
    init?(hexString: String) {
        let hex = hexString.replacingOccurrences(of: " ", with: "")
        guard hex.count % 2 == 0 else { return nil }
        
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
    
    /// Convert Data to hex string
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
