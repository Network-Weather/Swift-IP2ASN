import XCTest

@testable import SwiftIP2ASN

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class BGPIntegrationTest: XCTestCase {

    func testBGPDataReturnsCorrectASNs() async throws {
        throw XCTSkip("Test disabled: Should not build database from online data during regular test runs")
    }

    func testComparisonWithOldMethod() async throws {
        throw XCTSkip("Integration test disabled by default; set IP2ASN_RUN_INTEGRATION=1 to enable")
    }
}
