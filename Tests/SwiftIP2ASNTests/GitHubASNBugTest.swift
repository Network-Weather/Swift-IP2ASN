import XCTest

@testable import SwiftIP2ASN

final class GitHubASNBugTest: XCTestCase {

    func testGitHubIPReturnsCorrectASN() async throws {
        print("\n🐛 Testing bug fix: GitHub IP should return AS36459, not AS20473\n")

        // The actual BGP data for these ranges
        let bgpData = """
            140.82.0.0	140.82.63.255	20473	US	AS-VULTR
            140.82.112.0	140.82.127.255	36459	US	GITHUB
            """

        print("📊 BGP Data ranges:")
        print("   140.82.0.0 - 140.82.63.255 → AS20473 (Vultr)")
        print("   140.82.112.0 - 140.82.127.255 → AS36459 (GitHub)")
        print("   Note: These ranges do NOT overlap!\n")

        let parser = BGPDataParser()
        let mappings = parser.parseIPtoASNData(bgpData)

        print("🔧 Parsed CIDR blocks:")
        for (range, asn, name) in mappings {
            let prefixLen = range.prefixLength
            let size = UInt32(1) << (32 - prefixLen)

            // Get the start IP for display
            let startIP: String
            switch range.start {
            case .v4(let addr):
                startIP = "\(addr)"
            case .v6(let addr):
                startIP = "\(addr)"
            }

            print("   \(startIP)/\(prefixLen) (\(size) IPs) → AS\(asn) (\(name))")
        }

        // Build database
        let database = ASNDatabase()
        var entries: [(range: IPRange, asn: UInt32, name: String?)] = []
        for (range, asn, name) in mappings {
            entries.append((range: range, asn: asn, name: name))
        }
        await database.buildWithBGPData(bgpEntries: entries)

        // Test the specific IP
        print("\n🎯 Testing IP lookups:")

        let testCases = [
            // IPs in Vultr range (140.82.0.0 - 140.82.63.255)
            ("140.82.0.1", 20473, "Vultr"),
            ("140.82.32.50", 20473, "Vultr"),
            ("140.82.63.255", 20473, "Vultr"),

            // IPs in GitHub range (140.82.112.0 - 140.82.127.255)
            ("140.82.112.1", 36459, "GitHub"),
            ("140.82.121.3", 36459, "GitHub"),  // The critical test case!
            ("140.82.127.255", 36459, "GitHub"),

            // IPs in the gap (should not be found)
            ("140.82.64.1", 0, "Gap - not in either range"),
            ("140.82.100.1", 0, "Gap - not in either range")
        ]

        var passed = 0
        var failed = 0

        for (ip, expectedASN, description) in testCases {
            if let result = await database.lookup(ip) {
                let status = result.asn == expectedASN ? "✅" : "❌"
                print(
                    "\(status) \(ip.padding(toLength: 15, withPad: " ", startingAt: 0)) → AS\(result.asn) (expected AS\(expectedASN) - \(description))"
                )

                if result.asn == expectedASN {
                    passed += 1
                } else {
                    failed += 1
                    print("   ⚠️ BUG: Expected AS\(expectedASN) but got AS\(result.asn)!")
                }
            } else {
                if expectedASN == 0 {
                    print(
                        "✅ \(ip.padding(toLength: 15, withPad: " ", startingAt: 0)) → NOT FOUND (correctly not in any range)"
                    )
                    passed += 1
                } else {
                    print(
                        "❌ \(ip.padding(toLength: 15, withPad: " ", startingAt: 0)) → NOT FOUND (expected AS\(expectedASN) - \(description))"
                    )
                    failed += 1
                }
            }
        }

        print("\n📊 Results: \(passed) passed, \(failed) failed")

        // The critical assertion
        let githubIP = "140.82.121.3"
        let result = await database.lookup(githubIP)
        XCTAssertNotNil(result, "140.82.121.3 must be found")
        XCTAssertEqual(result?.asn, 36459, "140.82.121.3 MUST return AS36459 (GitHub), not AS20473 (Vultr)")

        if failed == 0 {
            print("\n✅ BUG FIXED! GitHub IP 140.82.121.3 correctly returns AS36459!")
        }
    }
}
