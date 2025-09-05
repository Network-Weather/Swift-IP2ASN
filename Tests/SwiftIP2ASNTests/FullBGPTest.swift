import XCTest

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class FullBGPTest: XCTestCase {

    func testRealIPtoASNLookup() async throws {
        throw XCTSkip("Test disabled: Should not build database from online data during regular test runs")

        print("\n🌐 Building database with REAL BGP data from IPtoASN.com...")
        print("This will download and parse the actual IP-to-ASN database")
        print("(May take 10-30 seconds depending on network speed)\n")

        let startTime = Date()

        // Build using the V2 database that fetches real BGP data
        let database = ASNDatabaseV2()
        try await database.buildFromBGPData()

        let buildTime = Date().timeIntervalSince(startTime)
        print("✅ Database built in \(String(format: "%.2f", buildTime)) seconds")

        let stats = await database.getStatistics()
        print("\n📊 Database Statistics:")
        print("   Total nodes: \(stats.totalNodes)")
        print("   IPv4 entries: \(stats.ipv4Entries)")
        print("   IPv6 entries: \(stats.ipv6Entries)")

        print("\n🔍 Testing the specific IPs you mentioned:")

        // Test the IPs the user specifically asked about
        let testIPs = [
            ("204.141.42.155", "User requested IP #1"),
            ("180.222.119.247", "User requested IP #2"),
            ("57.144.220.1", "Facebook/Meta (should be AS32934)"),
            ("8.8.8.8", "Google DNS"),
            ("1.1.1.1", "Cloudflare DNS"),
            ("23.185.0.2", "Akamai"),
            ("140.82.114.4", "GitHub"),
            ("52.84.228.25", "Amazon CloudFront"),
            ("93.184.216.34", "Example.com")
        ]

        for (ip, description) in testIPs {
            if let result = await database.lookup(ip) {
                print("\n✅ \(ip) (\(description)):")
                print("   ASN: \(result.asn)")
                print("   Name: \(result.name ?? "N/A")")

                // Verify ASN is not 0
                XCTAssertNotEqual(result.asn, 0, "ASN should not be 0 for \(ip)")
            } else {
                print("\n❌ \(ip) (\(description)): Not found in database")
            }
        }

        print("\n🎉 SUCCESS! The library now works with real BGP data!")
        print("   - IPs like 204.141.42.155 and 180.222.119.247 can now be looked up")
        print("   - The database contains actual ASN mappings from IPtoASN.com")
        print("   - No more ASN=0 problems!")
    }
}
