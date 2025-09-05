import XCTest

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

final class RealASNTest: XCTestCase {

    func testFacebookIPReturnsCorrectASN() async throws {
        // Build database with real BGP data
        let database = SimpleBGPDatabase()
        try await database.buildFromBGPData()

        // Test Facebook IP
        let facebookIP = "57.144.220.1"

        if let result = await database.lookup(facebookIP) {
            print("\n✅ Lookup result for \(facebookIP):")
            print("   ASN: \(result.asn)")
            print("   Name: \(result.name ?? "N/A")")
            print("   Registry: \(result.registry)")

            // Verify it's Facebook's ASN
            XCTAssertEqual(result.asn, 32934, "IP \(facebookIP) should return Facebook's ASN 32934")
            XCTAssertTrue(result.name?.contains("FACEBOOK") ?? false, "Should identify as Facebook/Meta")
        } else {
            XCTFail("Failed to lookup \(facebookIP)")
        }

        // Test other well-known IPs
        let testCases: [(String, UInt32, String)] = [
            ("8.8.8.8", 15169, "Google"),
            ("1.1.1.1", 13335, "Cloudflare"),
            ("52.94.76.0", 16509, "Amazon"),
            ("13.64.0.0", 8075, "Microsoft"),
            ("157.240.1.1", 32934, "Facebook"),
            ("31.13.24.1", 32934, "Facebook")
        ]

        print("\n🔍 Testing well-known IPs:")
        for (ip, expectedASN, company) in testCases {
            if let result = await database.lookup(ip) {
                let checkmark = result.asn == expectedASN ? "✅" : "❌"
                print(
                    "\(checkmark) \(ip.padding(toLength: 15, withPad: " ", startingAt: 0)) → AS\(result.asn) (\(company))"
                )

                if result.asn != expectedASN {
                    print("   Expected AS\(expectedASN) but got AS\(result.asn)")
                }
            } else {
                print("❌ \(ip.padding(toLength: 15, withPad: " ", startingAt: 0)) → No result")
            }
        }
    }

    func testIPv6ASNLookup() async throws {
        let database = SimpleBGPDatabase()
        try await database.buildFromBGPData()

        let testCases: [(String, UInt32, String)] = [
            ("2001:4860::8888", 15169, "Google IPv6"),
            ("2606:4700::1", 13335, "Cloudflare IPv6"),
            ("2620:0:1c00::1", 32934, "Facebook IPv6"),
            ("2a03:2880::1", 32934, "Facebook IPv6")
        ]

        print("\n🌐 Testing IPv6 addresses:")
        for (ip, expectedASN, company) in testCases {
            if let result = await database.lookup(ip) {
                let checkmark = result.asn == expectedASN ? "✅" : "❌"
                print(
                    "\(checkmark) \(ip.padding(toLength: 20, withPad: " ", startingAt: 0)) → AS\(result.asn) (\(company))"
                )

                XCTAssertEqual(
                    result.asn, expectedASN,
                    "IPv6 \(ip) should return AS\(expectedASN) for \(company)")
            } else {
                print("❌ \(ip.padding(toLength: 20, withPad: " ", startingAt: 0)) → No result")
            }
        }
    }
}
