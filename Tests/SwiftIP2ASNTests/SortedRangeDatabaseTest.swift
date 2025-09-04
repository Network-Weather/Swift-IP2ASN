import XCTest

@testable import SwiftIP2ASN

final class SortedRangeDatabaseTest: XCTestCase {

    func testBinarySearchWithOverlappingRanges() async throws {
        print("\n🔬 Testing Sorted Range Database with overlapping ranges\n")

        let database = SortedRangeDatabase()

        // Test data with overlapping ranges (from actual BGP data)
        let testData = [
            // Non-overlapping ranges
            ("1.0.0.0", "1.0.0.255", UInt32(13335), "CLOUDFLARENET"),
            ("1.0.4.0", "1.0.7.255", UInt32(38803), "GTELECOM"),

            // Overlapping ranges (actual case from BGP)
            ("1.6.220.0", "1.6.223.255", UInt32(9583), "SIFY-AS-IN"),
            ("1.6.221.0", "1.6.224.255", UInt32(9583), "SIFY-AS-IN-OVERLAP"),

            // More test ranges
            ("8.8.8.0", "8.8.8.255", UInt32(15169), "GOOGLE"),
            ("140.82.0.0", "140.82.63.255", UInt32(20473), "VULTR"),
            ("140.82.112.0", "140.82.127.255", UInt32(36459), "GITHUB")
        ]

        await database.buildFromBGPData(testData)

        let stats = await database.getStatistics()
        print("📊 Database Statistics:")
        print("   Total ranges: \(stats.totalRanges)")
        print("   Overlapping ranges: \(stats.overlaps)")
        print("   Non-power-of-2 ranges: \(stats.nonPowerOf2)")

        // Test lookups
        let testCases = [
            ("1.0.0.1", UInt32(13335), "Cloudflare"),
            ("1.0.4.5", UInt32(38803), "GTelecom"),
            ("1.6.220.5", UInt32(9583), "In overlapping range - should return most specific"),
            ("1.6.222.0", UInt32(9583), "In both overlapping ranges"),
            ("8.8.8.8", UInt32(15169), "Google DNS"),
            ("140.82.121.3", UInt32(36459), "GitHub"),
            ("1.0.2.0", UInt32(0), "Not routed - should return nil")
        ]

        print("\n🎯 Testing lookups:")
        for (ip, expectedASN, description) in testCases {
            if let result = await database.lookup(ip) {
                let status = result.asn == expectedASN ? "✅" : "❌"
                print(
                    "\(status) \(ip.padding(toLength: 15, withPad: " ", startingAt: 0)) → AS\(result.asn) (\(result.name ?? "Unknown")) - \(description)"
                )

                if expectedASN != 0 {
                    XCTAssertEqual(result.asn, expectedASN, "Lookup failed for \(ip)")
                }
            } else {
                let status = expectedASN == 0 ? "✅" : "❌"
                print("\(status) \(ip.padding(toLength: 15, withPad: " ", startingAt: 0)) → NOT FOUND - \(description)")

                if expectedASN != 0 {
                    XCTFail("Should have found ASN for \(ip)")
                }
            }
        }
    }

    func testPerformanceWithSimpleData() async throws {
        print("\n⚡ Testing performance with sample BGP data\n")

        print("📊 Using sample BGP data in TSV format...")

        // Sample BGP data in actual TSV format (start_ip\tend_ip\tasn\tcountry\tname)
        let bgpLines = """
            1.0.0.0\t1.0.0.255\t13335\tUS\tCLOUDFLARENET
            1.0.4.0\t1.0.7.255\t38803\tAU\tGTELECOM
            8.8.8.0\t8.8.8.255\t15169\tUS\tGOOGLE
            140.82.0.0\t140.82.63.255\t20473\tUS\tVULTR
            140.82.112.0\t140.82.127.255\t36459\tUS\tGITHUB
            157.240.0.0\t157.240.255.255\t32934\tUS\tFACEBOOK
            172.217.0.0\t172.217.255.255\t15169\tUS\tGOOGLE
            """.split(separator: "\n")

        // Parse TSV directly
        var entries: [(startIP: String, endIP: String, asn: UInt32, name: String?)] = []
        for line in bgpLines {
            let fields = line.split(separator: "\t").map { String($0) }
            if fields.count >= 5 {
                if let asn = UInt32(fields[2]) {
                    entries.append((fields[0], fields[1], asn, fields[4]))
                }
            }
        }

        print("🏗️ Building database with \(entries.count) entries...")
        let database = SortedRangeDatabase()

        let buildStart = Date()
        await database.buildFromBGPData(entries)
        let buildTime = Date().timeIntervalSince(buildStart)
        print("   Build time: \(String(format: "%.3f", buildTime)) seconds")

        let stats = await database.getStatistics()
        print("   Stats: \(stats.totalRanges) ranges, \(stats.overlaps) overlaps, \(stats.nonPowerOf2) non-power-of-2")

        // Performance test
        print("\n⏱️ Testing lookup performance...")
        let testIPs = [
            "8.8.8.8",
            "1.1.1.1",
            "140.82.121.3",
            "157.240.22.35",
            "17.253.144.10",
            "204.141.42.155",
            "180.222.119.247"
        ]

        for ip in testIPs {
            let start = Date()
            let result = await database.lookup(ip)
            let elapsed = Date().timeIntervalSince(start) * 1_000_000  // Convert to microseconds

            if let result = result {
                print("   \(ip) → AS\(result.asn) in \(String(format: "%.1f", elapsed))μs")
            } else {
                print("   \(ip) → NOT FOUND in \(String(format: "%.1f", elapsed))μs")
            }
        }

        // Bulk performance test
        print("\n📈 Bulk lookup test (100 random lookups)...")
        let bulkStart = Date()
        var found = 0
        for _ in 0..<100 {
            // Generate random IP within our test ranges
            let testRanges = ["1.0.0", "8.8.8", "140.82", "157.240", "172.217"]
            let prefix = testRanges.randomElement()!
            let ip = "\(prefix).\(Int.random(in: 0...255)).\(Int.random(in: 0...255))"
            if await database.lookup(ip) != nil {
                found += 1
            }
        }
        let bulkTime = Date().timeIntervalSince(bulkStart)
        let avgTime = bulkTime / 100.0 * 1_000_000  // microseconds per lookup

        print("   100 lookups in \(String(format: "%.3f", bulkTime))s")
        print("   Average: \(String(format: "%.1f", avgTime))μs per lookup")
        print("   Found: \(found)/100 IPs in database")

        // Verify it's fast enough
        XCTAssertLessThan(avgTime, 1000, "Average lookup should be under 1000μs")
    }
}
