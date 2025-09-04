import XCTest

@testable import SwiftIP2ASN

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class BGPIntegrationTest: XCTestCase {

    func testBGPDataReturnsCorrectASNs() async throws {
        // Build database with BGP data
        let ip2asn = try await SwiftIP2ASN.buildWithBGPData()

        // Test the specific Facebook IP the user asked about
        let facebookIP = "57.144.220.1"

        if let result = await ip2asn.lookup(facebookIP) {
            print("\n✅ Lookup result for \(facebookIP):")
            print("   ASN: \(result.asn)")
            print("   Name: \(result.name ?? "N/A")")
            print("   Registry: \(result.registry)")

            // This is the critical test - Facebook's IP must return ASN 32934
            XCTAssertEqual(result.asn, 32934, "IP \(facebookIP) should return Facebook's ASN 32934")
            XCTAssertNotEqual(result.asn, 0, "ASN should never be 0 for valid IP ranges")
            XCTAssertTrue(result.name?.contains("FACEBOOK") ?? false, "Should identify as Facebook/Meta")
        } else {
            XCTFail("Failed to lookup \(facebookIP)")
        }

        // Test other well-known IPs to ensure they don't return 0
        let testCases: [(String, UInt32, String)] = [
            ("8.8.8.8", 15169, "Google"),
            ("1.1.1.1", 13335, "Cloudflare"),
            ("52.94.76.0", 16509, "Amazon"),
            ("13.64.0.0", 8075, "Microsoft"),
            ("157.240.1.1", 32934, "Facebook"),
        ]

        print("\n🔍 Verifying ASN lookups return actual ASN values (not 0):")
        for (ip, expectedASN, company) in testCases {
            if let result = await ip2asn.lookup(ip) {
                let checkmark = result.asn == expectedASN ? "✅" : "⚠️"
                print(
                    "\(checkmark) \(ip.padding(toLength: 15, withPad: " ", startingAt: 0)) → AS\(result.asn) (expected AS\(expectedASN) for \(company))"
                )

                // Critical: ASN should never be 0
                XCTAssertNotEqual(result.asn, 0, "ASN should never be 0 for \(ip)")
                XCTAssertEqual(result.asn, expectedASN, "\(ip) should return AS\(expectedASN) for \(company)")
            } else {
                XCTFail("Failed to lookup \(ip)")
            }
        }

        // Get statistics
        let stats = await ip2asn.getStatistics()
        print("\n📊 Database Statistics:")
        print("   Total nodes: \(stats.totalNodes)")
        print("   IPv4 entries: \(stats.ipv4Entries)")
        print("   IPv6 entries: \(stats.ipv6Entries)")
        print("   IPv4 depth: \(stats.ipv4Depth)")
        print("   IPv6 depth: \(stats.ipv6Depth)")

        // Verify we have actual data
        XCTAssertGreaterThan(stats.totalNodes, 0, "Database should contain nodes")
        XCTAssertGreaterThan(stats.ipv4Entries, 0, "Database should contain IPv4 entries")
    }

    func testComparisonWithOldMethod() async throws {
        print("\n🔬 Comparing old RIR method vs new BGP method:")

        // Build with old method (RIR data - returns ASN 0)
        let oldDB = try await SwiftIP2ASN.buildFromOnlineData()

        // Build with new method (BGP data - returns actual ASNs)
        let newDB = try await SwiftIP2ASN.buildWithBGPData()

        let testIP = "57.144.220.1"

        print("\nResults for \(testIP):")

        if let oldResult = await oldDB.lookup(testIP) {
            print("   Old method (RIR): ASN=\(oldResult.asn)")
            XCTAssertEqual(oldResult.asn, 0, "Old RIR method incorrectly returns ASN 0")
        }

        if let newResult = await newDB.lookup(testIP) {
            print("   New method (BGP): ASN=\(newResult.asn)")
            XCTAssertEqual(newResult.asn, 32934, "New BGP method correctly returns Facebook's ASN")
        }

        print("\n✅ New BGP method fixes the ASN=0 problem!")
    }
}
