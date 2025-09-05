import XCTest

@testable import SwiftIP2ASN

final class SwiftIP2ASNBasicTests: XCTestCase {
    func testPackageLoads() throws {
        // Minimal smoke test to ensure the module builds and links.
        _ = ASNInfo(asn: 1, registry: "test")
    }
}
