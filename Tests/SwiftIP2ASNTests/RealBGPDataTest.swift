import XCTest

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class RealBGPDataTest: XCTestCase {

    func testRealIPtoASNDatabase() async throws {
        throw XCTSkip("Test disabled: Should not build database from online data during regular test runs")

        print("\n🌍 Fetching REAL BGP data from IPtoASN.com...")
        print("This will download the actual IP-to-ASN database (may take a moment)\n")

        // Use the V2 database that can fetch real data
        let database = ASNDatabaseV2()

        do {
            // This fetches from https://iptoasn.com/data/ip2asn-v4.tsv.gz
            try await database.buildFromBGPData()

            print("\n✅ Successfully built database from real BGP data!")

            let stats = await database.getStatistics()
            print("\n📊 Database Statistics:")
            print("   Total nodes: \(stats.totalNodes)")
            print("   IPv4 entries: \(stats.ipv4Entries)")
            print("   IPv6 entries: \(stats.ipv6Entries)")

            // Test the specific IPs you mentioned
            print("\n🔍 Testing specific IPs with real BGP data:")

            let testIPs = [
                "204.141.42.155",
                "180.222.119.247",
                "57.144.220.1",  // Facebook
                "8.8.8.8",  // Google
                "1.1.1.1"  // Cloudflare
            ]

            for ip in testIPs {
                if let result = await database.lookup(ip) {
                    print("\n✅ \(ip):")
                    print("   ASN: \(result.asn)")
                    print("   Name: \(result.name ?? "N/A")")
                    print("   Registry: \(result.registry)")

                    XCTAssertNotEqual(result.asn, 0, "ASN should not be 0 for \(ip)")
                } else {
                    print("\n❌ \(ip): Not found")
                }
            }

        } catch {
            print("\n⚠️ Error fetching real BGP data: \(error)")
            print("This might be due to:")
            print("1. Network connectivity issues")
            print("2. IPtoASN.com being temporarily unavailable")
            print("3. Gzip decompression issues")

            // Try to understand the error
            if let bgpError = error as? BGPError {
                switch bgpError {
                case .downloadFailed:
                    print("→ Failed to download the BGP data file")
                case .decompressionFailed:
                    print("→ Failed to decompress the gzipped data")
                case .invalidData:
                    print("→ Data format was invalid")
                case .parseError:
                    print("→ Failed to parse the BGP data")
                }
            }

            throw error
        }
    }

    func testSimpleFetchAndParse() async throws {
        throw XCTSkip("Network-dependent test disabled by default; set IP2ASN_RUN_NETWORK=1 to enable")
        print("\n🧪 Testing BGP data fetching and parsing...")

        let fetcher = BGPDataFetcher()
        let parser = BGPDataParser()

        do {
            print("Fetching IPv4 BGP data from IPtoASN.com...")
            let ipv4Data = try await fetcher.fetchIPv4Data()

            print("Data fetched! First 500 characters:")
            print(String(ipv4Data.prefix(500)))

            print("\nParsing BGP data...")
            let mappings = parser.parseIPtoASNData(ipv4Data)

            print("Parsed \(mappings.count) IP range mappings")

            // Show first 10 entries
            print("\nFirst 10 entries:")
            for (index, (range, asn, name)) in mappings.prefix(10).enumerated() {
                print("\(index+1). Range → AS\(asn) (\(name))")
            }

            XCTAssertGreaterThan(mappings.count, 0, "Should parse at least some mappings")

        } catch {
            print("\nError: \(error)")
            throw error
        }
    }
}
