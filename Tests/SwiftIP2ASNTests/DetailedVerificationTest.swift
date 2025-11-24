import XCTest

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

final class DetailedVerificationTest: XCTestCase {

    func testDetailedIPVerification() throws {
        print("\n🔬 DETAILED VERIFICATION: Testing embedded database lookups\n")

        // Test against the embedded database which has real BGP data
        let db = try EmbeddedDatabase.loadUltraCompact()

        // Well-known IPs that should be in any current BGP database
        let testCases: [(ip: String, description: String)] = [
            ("8.8.8.8", "Google DNS"),
            ("1.1.1.1", "Cloudflare DNS"),
            ("140.82.121.3", "GitHub"),
            ("157.240.22.35", "Facebook/Meta"),
            ("17.253.144.10", "Apple"),
            ("52.94.76.1", "Amazon AWS"),
            ("204.141.42.155", "Should be in some ASN"),
            ("180.222.119.247", "Should be in some ASN")
        ]

        print("📊 Embedded Database Lookups:")
        print(String(repeating: "─", count: 60))

        var foundCount = 0
        for (ip, description) in testCases {
            if let result = db.lookup(ip) {
                print(
                    "✅ \(ip.padding(toLength: 18, withPad: " ", startingAt: 0)) → AS\(result.asn) (\(result.name ?? "unknown"))"
                )
                foundCount += 1
            } else {
                print("❌ \(ip.padding(toLength: 18, withPad: " ", startingAt: 0)) → NOT FOUND (\(description))")
            }
        }

        print(String(repeating: "─", count: 60))
        print("Found: \(foundCount)/\(testCases.count)")

        // Critical IPs should always be found
        XCTAssertNotNil(db.lookup("8.8.8.8"), "Google DNS must be found")
        XCTAssertNotNil(db.lookup("1.1.1.1"), "Cloudflare DNS must be found")
        XCTAssertNotNil(db.lookup("140.82.121.3"), "GitHub must be found")
    }
}
