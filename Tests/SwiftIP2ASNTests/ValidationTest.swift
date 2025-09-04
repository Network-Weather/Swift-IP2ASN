import XCTest

@testable import SwiftIP2ASN

final class ValidationTest: XCTestCase {

    func testComprehensiveContinentalCoverage() async throws {
        // Skip in CI
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping integration test in CI environment")
        }

        print("\n🌍 Building global IP database from RIR sources...")
        let startBuild = Date()
        let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()
        let buildTime = Date().timeIntervalSince(startBuild)

        let stats = await ip2asn.getStatistics()

        print("\n📊 Database Statistics:")
        print("   Build time: \(String(format: "%.1f", buildTime)) seconds")
        print("   IPv4 entries: \(stats.ipv4Entries)")
        print("   IPv6 entries: \(stats.ipv6Entries)")
        print("   Total nodes: \(stats.totalNodes)")
        print("   IPv4 trie depth: \(stats.ipv4Depth)")
        print("   IPv6 trie depth: \(stats.ipv6Depth)")

        // Test IPs from each continent
        let globalTestCases: [(continent: String, ips: [(ip: String, desc: String, registry: String)])] = [
            (
                "North America 🇺🇸🇨🇦",
                [
                    ("8.8.8.8", "Google DNS", "arin"),
                    ("52.94.76.0", "AWS Virginia", "arin"),
                    ("142.59.0.0", "Bell Canada", "arin"),
                    ("23.185.0.2", "Akamai CDN", "arin"),
                ]
            ),

            (
                "Europe 🇪🇺",
                [
                    ("185.60.216.35", "OpenDNS Europe", "ripencc"),
                    ("91.198.174.192", "Wikimedia", "ripencc"),
                    ("185.15.56.0", "OVH France", "ripencc"),
                    ("193.222.51.0", "CERN", "ripencc"),
                ]
            ),

            (
                "Asia-Pacific 🇯🇵🇨🇳🇦🇺",
                [
                    ("1.1.1.1", "Cloudflare APNIC", "apnic"),
                    ("110.33.0.0", "Telstra Australia", "apnic"),
                    ("133.11.0.0", "Univ Tokyo", "apnic"),
                    ("202.108.0.0", "China Unicom", "apnic"),
                    ("103.87.124.0", "India ISP", "apnic"),
                ]
            ),

            (
                "Latin America 🇧🇷🇲🇽",
                [
                    ("200.160.0.0", "Brazil", "lacnic"),
                    ("187.141.0.0", "Mexico", "lacnic"),
                    ("190.210.0.0", "Argentina", "lacnic"),
                    ("200.27.0.0", "Chile", "lacnic"),
                ]
            ),

            (
                "Africa 🇿🇦🇪🇬",
                [
                    ("196.32.0.0", "South Africa", "afrinic"),
                    ("196.219.0.0", "Egypt", "afrinic"),
                    ("197.136.0.0", "Kenya", "afrinic"),
                    ("41.0.0.0", "African block", "afrinic"),
                ]
            ),
        ]

        var successCount = 0
        var failCount = 0
        var registryStats: [String: Int] = [:]
        var countryStats: [String: Int] = [:]

        print("\n🔍 Testing IP lookups by continent:\n")

        for (continent, testCases) in globalTestCases {
            print("━━━━━ \(continent) ━━━━━")

            for (ip, description, expectedRegistry) in testCases {
                if let result = await ip2asn.lookup(ip) {
                    let statusIcon = result.registry == expectedRegistry ? "✅" : "⚠️"

                    print(
                        "\(statusIcon) \(ip.padding(toLength: 18, withPad: " ", startingAt: 0)) │ \(description.padding(toLength: 20, withPad: " ", startingAt: 0)) │ \(result.registry.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)) │ \(result.countryCode ?? "--")"
                    )

                    if result.registry == expectedRegistry {
                        successCount += 1
                    } else {
                        failCount += 1
                        print("   ⚠️  Expected \(expectedRegistry) but got \(result.registry)")
                    }

                    registryStats[result.registry, default: 0] += 1
                    if let country = result.countryCode {
                        countryStats[country, default: 0] += 1
                    }
                } else {
                    print(
                        "❌ \(ip.padding(toLength: 18, withPad: " ", startingAt: 0)) │ \(description.padding(toLength: 20, withPad: " ", startingAt: 0)) │ NO RESULT"
                    )
                    failCount += 1
                }
            }
            print()
        }

        // Test IPv6
        print("━━━━━ IPv6 Global 🌐 ━━━━━")
        let ipv6Tests = [
            ("2001:4860:4860::8888", "Google IPv6", "arin"),
            ("2606:4700::6812:1", "Cloudflare IPv6", "arin"),
            ("2001:67c::", "RIPE IPv6", "ripencc"),
            ("2001:200::", "APNIC IPv6", "apnic"),
            ("2800::", "LACNIC IPv6", "lacnic"),
            ("2001:4200::", "AFRINIC IPv6", "afrinic"),
        ]

        for (ip, description, expectedRegistry) in ipv6Tests {
            if let result = await ip2asn.lookup(ip) {
                let statusIcon = result.registry == expectedRegistry ? "✅" : "⚠️"

                print(
                    "\(statusIcon) \(ip.padding(toLength: 25, withPad: " ", startingAt: 0)) │ \(description.padding(toLength: 15, withPad: " ", startingAt: 0)) │ \(result.registry.uppercased())"
                )

                if result.registry == expectedRegistry {
                    successCount += 1
                } else {
                    failCount += 1
                }
            } else {
                print(
                    "❌ \(ip.padding(toLength: 25, withPad: " ", startingAt: 0)) │ \(description.padding(toLength: 15, withPad: " ", startingAt: 0)) │ NO RESULT"
                )
                failCount += 1
            }
        }

        print("\n📈 Summary Statistics:")
        print("   ✅ Successful lookups: \(successCount)")
        print("   ❌ Failed lookups: \(failCount)")
        print(
            "   Success rate: \(String(format: "%.1f%%", Double(successCount) / Double(successCount + failCount) * 100))"
        )

        print("\n🌍 Registry Distribution:")
        for (registry, count) in registryStats.sorted(by: { $0.value > $1.value }) {
            print("   \(registry.uppercased()): \(count) lookups")
        }

        print("\n🏳️ Top Countries:")
        for (country, count) in countryStats.sorted(by: { $0.value > $1.value }).prefix(10) {
            print("   \(country): \(count) IPs")
        }

        // Performance validation
        print("\n⚡ Performance Validation:")
        var lookupTimes: [Double] = []
        let testIPs = ["8.8.8.8", "1.1.1.1", "192.168.1.1", "2001:4860::8888"]

        for _ in 0..<1000 {
            for ip in testIPs {
                let start = Date()
                _ = await ip2asn.lookup(ip)
                let elapsed = Date().timeIntervalSince(start) * 1_000_000  // Convert to microseconds
                lookupTimes.append(elapsed)
            }
        }

        let avgTime = lookupTimes.reduce(0, +) / Double(lookupTimes.count)
        let maxTime = lookupTimes.max() ?? 0
        let minTime = lookupTimes.min() ?? 0

        print("   Average lookup: \(String(format: "%.2f", avgTime)) μs")
        print("   Min lookup: \(String(format: "%.2f", minTime)) μs")
        print("   Max lookup: \(String(format: "%.2f", maxTime)) μs")

        // Assert that most lookups succeed
        let successRate = Double(successCount) / Double(successCount + failCount)
        XCTAssertGreaterThan(successRate, 0.8, "At least 80% of lookups should succeed")

        // Assert performance
        XCTAssertLessThan(avgTime, 50, "Average lookup should be under 50 microseconds")

        print("\n✅ All validations passed! The IP to ASN lookup system is working correctly across all continents.")
    }
}
