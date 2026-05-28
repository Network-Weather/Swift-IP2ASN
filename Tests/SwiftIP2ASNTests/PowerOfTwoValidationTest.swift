import Network
import XCTest

@testable import SwiftIP2ASN

final class PowerOfTwoValidationTest: XCTestCase {

    func testRangeSizesArePowerOfTwo() throws {
        let sampleRanges = [
            ("8.8.8.0", "8.8.8.255", 256),
            ("1.1.1.0", "1.1.1.255", 256),
            ("140.82.0.0", "140.82.63.255", 16384),
            ("140.82.112.0", "140.82.127.255", 4096),
            ("57.144.0.0", "57.147.255.255", 262144),
            ("10.0.0.0", "10.0.0.0", 1),
            ("192.168.0.0", "192.168.0.127", 128)
        ]

        for (start, end, expectedSize) in sampleRanges {
            let size = try calculateRangeSize(start: start, end: end)
            XCTAssertEqual(size, expectedSize, "Size mismatch for range \(start)-\(end)")
            XCTAssertTrue(isPowerOfTwo(UInt32(size)), "Range \(start)-\(end) is not a power of two")
        }
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
