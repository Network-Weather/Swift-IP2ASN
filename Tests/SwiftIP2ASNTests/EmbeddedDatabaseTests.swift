import XCTest
@testable import SwiftIP2ASN

final class EmbeddedDatabaseTests: XCTestCase {
    func testEmbeddedUltraLookups() throws {
        // Try to load the embedded Ultra DB; skip if not present
        let db: UltraCompactDatabase
        do {
            db = try EmbeddedDatabase.loadUltraCompact()
        } catch {
            throw XCTSkip("Embedded ip2asn.ultra not present; skipping embedded DB checks")
        }

        // Canonical IPs that should be present in a current full DB
        let cases: [(String, UInt32)] = [
            ("8.8.8.8", 15169),       // Google
            ("1.1.1.1", 13335),       // Cloudflare
            ("52.84.228.25", 16509),  // Amazon CloudFront
            ("140.82.121.3", 36459)   // GitHub
        ]

        for (ip, expected) in cases {
            let result = db.lookup(ip)
            XCTAssertNotNil(result, "Embedded DB should contain \(ip)")
            XCTAssertEqual(result?.asn, expected, "\(ip) should be AS\(expected)")
        }
    }
}

