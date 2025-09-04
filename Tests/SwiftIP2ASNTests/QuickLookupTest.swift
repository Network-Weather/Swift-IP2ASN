import XCTest

@testable import SwiftIP2ASN

final class QuickLookupTest: XCTestCase {

    func testSpecificIPLookup() async throws {
        print("Building database from RIR data...")
        let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()

        let testIP = "57.144.220.1"

        print("\nLooking up IP: \(testIP)")

        if let result = await ip2asn.lookup(testIP) {
            print("\n📍 Results for \(testIP):")
            print("   ASN: \(result.asn)")
            print("   Country Code: \(result.countryCode ?? "N/A")")
            print("   Registry: \(result.registry)")
            print("   Allocated Date: \(result.allocatedDate?.description ?? "N/A")")
            print("   Name: \(result.name ?? "N/A")")
        } else {
            print("❌ No result found for \(testIP)")
        }

        // Also check the IP range it belongs to
        let testRange = "57.144.0.0/12"
        if let range = IPRange(cidr: testRange) {
            print("\nChecking if \(testIP) is in range \(testRange):")
            if let ip = IPAddress(string: testIP) {
                print("   In range: \(range.contains(ip))")
            }
        }

        // Check neighboring IPs
        print("\nChecking neighboring IPs:")
        let neighbors = ["57.144.220.0", "57.144.220.2", "57.144.0.0", "57.0.0.0"]
        for neighborIP in neighbors {
            if let result = await ip2asn.lookup(neighborIP) {
                print("   \(neighborIP): ASN=\(result.asn), Country=\(result.countryCode ?? "N/A")")
            } else {
                print("   \(neighborIP): No result")
            }
        }
    }
}
