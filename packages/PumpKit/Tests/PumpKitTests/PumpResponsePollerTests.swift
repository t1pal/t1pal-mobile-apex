// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpResponsePollerTests.swift
// PumpKitTests
//
// Tests for PumpResponsePoller utilities.
// Trace: PROD-HARDEN-021

import Testing
import Foundation
@testable import PumpKit

/// Actor to safely track read counts in tests
private actor ReadCounter {
    var count = 0
    
    func increment() -> Int {
        count += 1
        return count
    }
    
    func getCount() -> Int {
        return count
    }
}

@Suite("PumpResponsePoller Tests", .serialized)
struct PumpResponsePollerTests {
    
    // MARK: - pollUntilChanged Tests
    
    @Test("Poll until changed - immediate change")
    func pollUntilChangedImmediateChange() async throws {
        // Given: A value that changes on first read
        let counter = ReadCounter()
        
        // When: Polling until changed
        let result = try await PumpResponsePoller.pollUntilChanged(
            timeout: 1.0,
            pollInterval: 0.01,
            operation: "test",
            readValue: {
                let c = await counter.increment()
                return Data([UInt8(c)])
            },
            hasChanged: { (data: Data) in
                data.first ?? 0 > 0
            }
        )
        
        // Then: First read succeeds
        #expect(result.first == 1)
        let count = await counter.getCount()
        #expect(count == 1)
    }
    
    @Test("Poll until changed - delayed change")
    func pollUntilChangedDelayedChange() async throws {
        // Given: A value that changes after 3 reads
        let counter = ReadCounter()
        
        // When: Polling until changed
        let result = try await PumpResponsePoller.pollUntilChanged(
            timeout: 1.0,
            pollInterval: 0.01,
            operation: "test",
            readValue: {
                let c = await counter.increment()
                return Data([c >= 3 ? 0xFF : 0x00])
            },
            hasChanged: { (data: Data) in
                data.first == 0xFF
            }
        )
        
        // Then: Change detected after 3 reads
        #expect(result.first == 0xFF)
        let count = await counter.getCount()
        #expect(count == 3)
    }
    
    @Test("Poll until changed - timeout")
    func pollUntilChangedTimeout() async throws {
        // Given: A value that never changes
        let counter = ReadCounter()
        
        // When: Polling until timeout
        do {
            _ = try await PumpResponsePoller.pollUntilChanged(
                timeout: 0.1,
                pollInterval: 0.02,
                operation: "test-timeout",
                readValue: {
                    _ = await counter.increment()
                    return Data([0x00])
                },
                hasChanged: { (_: Data) in false }
            )
            Issue.record("Expected timeout error")
        } catch let error as PumpTimeoutError {
            // Then: Timeout error with details
            #expect(error.operation == "test-timeout")
            #expect(abs(error.timeout - 0.1) < 0.01)
            #expect(error.detail?.contains("polls") ?? false)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
        
        // Verify some polls occurred
        let count = await counter.getCount()
        #expect(count > 0)
    }
    
    // MARK: - pollForResponseCode Tests
    
    @Test("Poll for response code - success code")
    func pollForResponseCodeSuccessCode() async throws {
        // Given: Response returns 0xDD after 2 polls
        let counter = ReadCounter()
        
        // When: Polling for response code
        let result = try await PumpResponsePoller.pollForResponseCode(
            timeout: 1.0,
            pollInterval: 0.01,
            operation: "response",
            readValue: {
                let c = await counter.increment()
                return c >= 2 ? Data([0xDD, 0x01, 0x02]) : Data([0x00])
            }
        )
        
        // Then: Returns data with success code
        #expect(result.first == 0xDD)
        #expect(result.count == 3)
    }
    
    @Test("Poll for response code - alternative codes")
    func pollForResponseCodeAlternativeCodes() async throws {
        // Given: Response returns 0xAA
        let result = try await PumpResponsePoller.pollForResponseCode(
            timeout: 1.0,
            pollInterval: 0.01,
            operation: "response",
            readValue: { Data([0xAA, 0x42]) }
        )
        
        // Then: 0xAA is accepted
        #expect(result.first == 0xAA)
    }
    
    @Test("Poll for response code - custom valid codes")
    func pollForResponseCodeCustomValidCodes() async throws {
        // Given: Custom valid codes
        let result = try await PumpResponsePoller.pollForResponseCode(
            timeout: 1.0,
            pollInterval: 0.01,
            operation: "custom",
            validCodes: [0x42],
            readValue: { Data([0x42]) }
        )
        
        // Then: Custom code accepted
        #expect(result.first == 0x42)
    }
    
    @Test("Poll for response code - timeout")
    func pollForResponseCodeTimeout() async throws {
        // Given: Response never returns valid code
        do {
            _ = try await PumpResponsePoller.pollForResponseCode(
                timeout: 0.1,
                pollInterval: 0.02,
                operation: "stuck",
                readValue: { Data([0x00]) }
            )
            Issue.record("Expected timeout error")
        } catch let error as PumpTimeoutError {
            // Then: Timeout with stuck code info
            #expect(error.detail?.contains("0x00") ?? false)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - pollResponseCount Tests
    
    @Test("Poll response count - change detected")
    func pollResponseCountChange() async throws {
        // Given: responseCount changes from 5 to 6
        let counter = ReadCounter()
        
        // When: Polling for change
        let newValue = try await PumpResponsePoller.pollResponseCount(
            initialValue: 5,
            timeout: 1.0,
            readValue: {
                let c = await counter.increment()
                return c >= 2 ? Data([6]) : Data([5])
            }
        )
        
        // Then: New value returned
        #expect(newValue == 6)
    }
    
    @Test("Poll response count - wraparound")
    func pollResponseCountWraparound() async throws {
        // Given: responseCount wraps from 255 to 0
        let newValue = try await PumpResponsePoller.pollResponseCount(
            initialValue: 255,
            timeout: 1.0,
            readValue: { Data([0]) }
        )
        
        // Then: Wraparound detected
        #expect(newValue == 0)
    }
    
    // MARK: - withRetry Tests
    
    @Test("With retry - immediate success")
    func withRetryImmediateSuccess() async throws {
        // Given: Operation succeeds immediately
        let counter = ReadCounter()
        
        // When: Executing with retry
        let result = try await withRetry(maxAttempts: 3, operation: "test") {
            _ = await counter.increment()
            return "success"
        }
        
        // Then: Single attempt
        #expect(result == "success")
        let count = await counter.getCount()
        #expect(count == 1)
    }
    
    @Test("With retry - eventual success")
    func withRetryEventualSuccess() async throws {
        // Given: Operation fails twice then succeeds
        let counter = ReadCounter()
        
        // When: Executing with retry
        let result: String = try await withRetry(
            maxAttempts: 3,
            backoff: 0.01,
            operation: "eventual"
        ) {
            let c = await counter.increment()
            if c < 3 {
                throw NSError(domain: "test", code: c)
            }
            return "success"
        }
        
        // Then: Succeeded on third attempt
        #expect(result == "success")
        let count = await counter.getCount()
        #expect(count == 3)
    }
    
    @Test("With retry - all attempts fail")
    func withRetryAllFail() async throws {
        // Given: Operation always fails
        let counter = ReadCounter()
        
        // When: All attempts fail
        do {
            let _: String = try await withRetry(
                maxAttempts: 3,
                backoff: 0.01,
                operation: "fail"
            ) {
                let c = await counter.increment()
                throw NSError(domain: "test", code: c)
            }
            Issue.record("Expected error")
        } catch {
            // Then: Last error thrown
            let count = await counter.getCount()
            #expect(count == 3)
        }
    }
    
    // MARK: - PumpTimeoutError Tests
    
    @Test("PumpTimeoutError description with detail")
    func pumpTimeoutErrorDescription() {
        // Given: Error with detail
        let error = PumpTimeoutError(
            operation: "read status",
            timeout: 5.0,
            detail: "stuck on 0x00"
        )
        
        // Then: Description includes all info
        #expect(error.description.contains("read status"))
        #expect(error.description.contains("5.0"))
        #expect(error.description.contains("stuck on 0x00"))
    }
    
    @Test("PumpTimeoutError description without detail")
    func pumpTimeoutErrorNoDetail() {
        // Given: Error without detail
        let error = PumpTimeoutError(operation: "connect", timeout: 30.0)
        
        // Then: Description without detail suffix
        #expect(error.description.contains("connect"))
        #expect(error.description.contains("30.0"))
        #expect(!error.description.contains(":"))
    }
}
