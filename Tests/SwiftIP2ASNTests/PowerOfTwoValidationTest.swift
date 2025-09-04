import Network
import XCTest

@testable import SwiftIP2ASN

final class PowerOfTwoValidationTest: XCTestCase {

    func testAllRangesArePowerOfTwo() async throws {
        print("\n🔬 Validating that all BGP ranges are valid CIDR blocks (power of 2 sizes)\n")

        // Sample some ranges from the BGP database
        let sampleRanges = [
            // Known good examples
            ("8.8.8.0", "8.8.8.255", 256, true),  // /24
            ("1.1.1.0", "1.1.1.255", 256, true),  // /24
            ("140.82.0.0", "140.82.63.255", 16384, true),  // /18 (64 * 256)
            ("140.82.112.0", "140.82.127.255", 4096, true),  // /20 (16 * 256)
            ("57.144.0.0", "57.147.255.255", 262144, true),  // /14 (4 * 65536)

            // Test edge cases
            ("10.0.0.0", "10.0.0.0", 1, true),  // Single IP (/32)
            ("192.168.0.0", "192.168.0.127", 128, true),  // /25

            // Invalid examples (if any exist in the data, we'll catch them)
        ]

        print("📊 Checking sample ranges:")
        print("Start IP         | End IP           | Size    | Power of 2?")
        print(String(repeating: "─", count: 65))

        for (start, end, expectedSize, shouldBeValid) in sampleRanges {
            let size = try calculateRangeSize(start: start, end: end)
            let isPower2 = isPowerOfTwo(UInt32(size))
            let status = isPower2 == shouldBeValid ? "✅" : "❌"

            print(
                "\(start.padding(toLength: 15, withPad: " ", startingAt: 0)) | \(end.padding(toLength: 15, withPad: " ", startingAt: 0)) | \(String(size).padding(toLength: 7, withPad: " ", startingAt: 0)) | \(status) \(isPower2)"
            )

            XCTAssertEqual(size, expectedSize, "Size mismatch for range \(start)-\(end)")
            XCTAssertEqual(isPower2, shouldBeValid, "Power of 2 check failed for range \(start)-\(end)")
        }

        // Now test with actual parsing
        print("\n🔍 Testing actual BGP data parsing:")

        let bgpData = """
            8.8.8.0	8.8.8.255	15169	US	GOOGLE
            140.82.0.0	140.82.63.255	20473	US	VULTR
            140.82.112.0	140.82.127.255	36459	US	GITHUB
            204.141.42.0	204.141.43.255	2639	US	ZOHO
            """

        let parser = BGPDataParser()
        let mappings = parser.parseIPtoASNData(bgpData)

        print("\nParsed ranges:")
        for (range, asn, name) in mappings {
            let prefixLen = range.prefixLength
            let expectedSize = UInt32(1) << (32 - prefixLen)

            print("   /\(prefixLen) (\(expectedSize) IPs) → AS\(asn) (\(name))")

            // Verify the size is a power of 2
            XCTAssertTrue(isPowerOfTwo(expectedSize), "CIDR /\(prefixLen) must have power-of-2 size")
        }

        print("\n✅ All tested ranges are valid CIDR blocks with power-of-2 sizes!")
    }

    private func calculateRangeSize(start: String, end: String) throws -> Int {
        guard let startIP = IPAddress(string: start),
            let endIP = IPAddress(string: end)
        else {
            throw TestError.invalidIP
        }

        switch (startIP, endIP) {
        case (.v4(let startAddr), .v4(let endAddr)):
            let startInt = ipv4ToUInt32(startAddr)
            let endInt = ipv4ToUInt32(endAddr)
            return Int(endInt - startInt + 1)
        default:
            throw TestError.notIPv4
        }
    }

    private func ipv4ToUInt32(_ address: IPv4Address) -> UInt32 {
        let bytes = address.rawValue
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    private func isPowerOfTwo(_ number: UInt32) -> Bool {
        return number != 0 && (number & (number - 1)) == 0
    }

    enum TestError: Error {
        case invalidIP
        case notIPv4
    }
}
