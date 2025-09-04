import XCTest

@testable import SwiftIP2ASN

final class IntegrationTests: XCTestCase {

    // Test well-known IP addresses from different continents
    // Note: These are example IPs and their ASN mappings may change over time
    // For production, these would be validated against current RIR data

    func testNorthAmericaIPs() async throws {
        // Skip if we can't fetch real data in CI
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping integration test in CI environment")
        }

        print("Building database from RIR data (this may take 10-30 seconds)...")
        let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()
        let stats = await ip2asn.getStatistics()
        print("Database built with \(stats.ipv4Entries) IPv4 and \(stats.ipv6Entries) IPv6 entries")

        // Test some well-known North American IPs
        let testCases = [
            // Google DNS
            ("8.8.8.8", "Google Public DNS", "US"),
            ("8.8.4.4", "Google Secondary DNS", "US"),

            // Cloudflare DNS
            ("1.1.1.1", "Cloudflare DNS", "US"),
            ("1.0.0.1", "Cloudflare Secondary", "US"),

            // Level 3/CenturyLink
            ("4.2.2.2", "Level 3 DNS", "US"),

            // AWS ranges
            ("52.94.76.0", "AWS US East", "US"),
            ("54.239.28.0", "AWS US West", "US"),

            // Microsoft Azure
            ("13.64.0.0", "Azure US West", "US"),

            // Canadian IPs
            ("24.114.0.0", "Shaw Communications", "CA"),
            ("142.59.0.0", "Bell Canada", "CA")
        ]

        for (ip, description, expectedCountry) in testCases {
            if let result = await ip2asn.lookup(ip) {
                print("\n✅ \(ip) (\(description)):")
                print("   ASN: \(result.asn)")
                print("   Country: \(result.countryCode ?? "N/A")")
                print("   Registry: \(result.registry)")

                if let country = result.countryCode {
                    XCTAssertEqual(
                        country, expectedCountry,
                        "IP \(ip) expected country \(expectedCountry) but got \(country)")
                }
            } else {
                XCTFail("Failed to lookup \(ip) (\(description))")
            }
        }
    }

    func testEuropeanIPs() async throws {
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping integration test in CI environment")
        }

        let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()

        let testCases = [
            // UK
            ("81.139.0.0", "British Telecom", "GB"),
            ("212.58.244.0", "BBC", "GB"),

            // Germany
            ("46.30.212.0", "Hetzner", "DE"),
            ("91.198.174.0", "Wikimedia", "NL"),

            // France
            ("185.15.56.0", "OVH", "FR"),

            // Netherlands
            ("94.142.240.0", "KPN", "NL"),

            // Switzerland
            ("193.222.51.0", "CERN", "CH")
        ]

        for (ip, description, expectedCountry) in testCases {
            if let result = await ip2asn.lookup(ip) {
                print("\n✅ \(ip) (\(description)):")
                print("   ASN: \(result.asn)")
                print("   Country: \(result.countryCode ?? "N/A")")
                print("   Registry: \(result.registry)")

                XCTAssertEqual(
                    result.registry, "ripencc",
                    "European IP \(ip) should be from RIPE NCC")
            } else {
                XCTFail("Failed to lookup \(ip) (\(description))")
            }
        }
    }

    func testAsianIPs() async throws {
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping integration test in CI environment")
        }

        let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()

        let testCases = [
            // Japan
            ("133.11.0.0", "University of Tokyo", "JP"),
            ("150.95.0.0", "NTT", "JP"),

            // China
            ("159.226.0.0", "Chinese Academy of Sciences", "CN"),
            ("202.108.0.0", "China Unicom", "CN"),

            // South Korea
            ("121.254.0.0", "Korea Telecom", "KR"),

            // Singapore
            ("103.24.77.0", "Singapore ISP", "SG"),

            // India
            ("103.87.124.0", "Indian ISP", "IN"),

            // Australia (part of APNIC)
            ("203.0.113.0", "Documentation Range", nil),  // This is actually reserved
            ("110.33.0.0", "Telstra", "AU")
        ]

        for (ip, description, expectedCountry) in testCases {
            if let result = await ip2asn.lookup(ip) {
                print("\n✅ \(ip) (\(description)):")
                print("   ASN: \(result.asn)")
                print("   Country: \(result.countryCode ?? "N/A")")
                print("   Registry: \(result.registry)")

                XCTAssertEqual(
                    result.registry, "apnic",
                    "Asian IP \(ip) should be from APNIC")
            } else {
                // Some IPs might not be allocated
                print("\n⚠️  \(ip) (\(description)): No ASN found (may be unallocated)")
            }
        }
    }

    func testLatinAmericanIPs() async throws {
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping integration test in CI environment")
        }

        let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()

        let testCases = [
            // Brazil
            ("200.160.0.0", "Brazilian ISP", "BR"),
            ("177.71.0.0", "Brazil Telecom", "BR"),

            // Mexico
            ("187.141.0.0", "Mexican ISP", "MX"),

            // Argentina
            ("190.210.0.0", "Argentine ISP", "AR"),

            // Chile
            ("200.27.0.0", "Chilean ISP", "CL")
        ]

        for (ip, description, expectedCountry) in testCases {
            if let result = await ip2asn.lookup(ip) {
                print("\n✅ \(ip) (\(description)):")
                print("   ASN: \(result.asn)")
                print("   Country: \(result.countryCode ?? "N/A")")
                print("   Registry: \(result.registry)")

                XCTAssertEqual(
                    result.registry, "lacnic",
                    "Latin American IP \(ip) should be from LACNIC")
            } else {
                XCTFail("Failed to lookup \(ip) (\(description))")
            }
        }
    }

    func testAfricanIPs() async throws {
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping integration test in CI environment")
        }

        let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()

        let testCases = [
            // South Africa
            ("196.32.0.0", "South African ISP", "ZA"),
            ("105.0.0.0", "African allocation", nil),

            // Egypt
            ("196.219.0.0", "Egyptian ISP", "EG"),

            // Kenya
            ("197.136.0.0", "Kenyan ISP", "KE"),

            // Nigeria
            ("197.210.0.0", "Nigerian ISP", "NG")
        ]

        for (ip, description, expectedCountry) in testCases {
            if let result = await ip2asn.lookup(ip) {
                print("\n✅ \(ip) (\(description)):")
                print("   ASN: \(result.asn)")
                print("   Country: \(result.countryCode ?? "N/A")")
                print("   Registry: \(result.registry)")

                XCTAssertEqual(
                    result.registry, "afrinic",
                    "African IP \(ip) should be from AFRINIC")
            } else {
                // Some African ranges might not be fully allocated
                print("\n⚠️  \(ip) (\(description)): No ASN found (may be unallocated)")
            }
        }
    }

    func testIPv6Addresses() async throws {
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping integration test in CI environment")
        }

        let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()

        let testCases = [
            // Google IPv6
            ("2001:4860:4860::8888", "Google Public DNS", "US", "arin"),

            // Cloudflare IPv6
            ("2606:4700:4700::1111", "Cloudflare DNS", "US", "arin"),

            // European IPv6
            ("2001:67c:2e8::", "European allocation", nil, "ripencc"),

            // APNIC IPv6
            ("2001:200::", "APNIC allocation", "JP", "apnic"),

            // LACNIC IPv6
            ("2001:1200::", "LACNIC allocation", nil, "lacnic"),

            // AFRINIC IPv6
            ("2001:4200::", "AFRINIC allocation", nil, "afrinic")
        ]

        for (ip, description, expectedCountry, expectedRegistry) in testCases {
            if let result = await ip2asn.lookup(ip) {
                print("\n✅ IPv6 \(ip) (\(description)):")
                print("   ASN: \(result.asn)")
                print("   Country: \(result.countryCode ?? "N/A")")
                print("   Registry: \(result.registry)")

                XCTAssertEqual(
                    result.registry, expectedRegistry,
                    "IPv6 \(ip) should be from \(expectedRegistry)")

                if let expectedCountry = expectedCountry,
                    let country = result.countryCode
                {
                    XCTAssertEqual(
                        country, expectedCountry,
                        "IPv6 \(ip) expected country \(expectedCountry) but got \(country)")
                }
            } else {
                print("\n⚠️  IPv6 \(ip) (\(description)): No ASN found (may be unallocated)")
            }
        }
    }

    func testPerformance() async throws {
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping performance test in CI environment")
        }

        let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()

        // Warm up
        _ = await ip2asn.lookup("8.8.8.8")

        let testIPs = [
            "8.8.8.8", "1.1.1.1", "192.168.1.1", "10.0.0.1",
            "52.94.76.1", "142.250.185.78", "151.101.1.140",
            "185.199.108.153", "172.217.16.142", "216.58.217.46"
        ]

        let startTime = Date()
        let iterations = 10000

        for _ in 0..<iterations {
            for ip in testIPs {
                _ = await ip2asn.lookup(ip)
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let totalLookups = iterations * testIPs.count
        let lookupsPerSecond = Double(totalLookups) / elapsed
        let microsecondsPerLookup = (elapsed * 1_000_000) / Double(totalLookups)

        print("\n📊 Performance Results:")
        print("   Total lookups: \(totalLookups)")
        print("   Total time: \(String(format: "%.2f", elapsed)) seconds")
        print("   Lookups per second: \(String(format: "%.0f", lookupsPerSecond))")
        print("   Microseconds per lookup: \(String(format: "%.2f", microsecondsPerLookup)) μs")

        // Assert performance is within expected range (< 100 microseconds per lookup)
        XCTAssertLessThan(
            microsecondsPerLookup, 100,
            "Lookup performance should be under 100 microseconds")
    }
}
