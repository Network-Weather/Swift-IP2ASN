import XCTest

@testable import SwiftIP2ASN

final class IntegrationTests: XCTestCase {
    override func setUp() async throws {
        throw XCTSkip("Integration tests disabled by default")
    }
}
