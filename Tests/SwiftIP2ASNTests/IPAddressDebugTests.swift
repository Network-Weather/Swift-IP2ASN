import XCTest

@testable import SwiftIP2ASN

final class IPAddressDebugTests: XCTestCase {
    func testBasicIPv6Parsing() {
        // Test various IPv6 formats
        let testCases = [
            ("2001:db8::1", true),
            ("::1", true),
            ("::", true),
            ("2001:0db8:0000:0000:0000:0000:0000:0001", true),
            ("fe80::1", true),
            ("2001:db8:0:0:0:0:0:1", true)
        ]

        for (ip, shouldParse) in testCases {
            let parsed = IPAddress(string: ip)
            if shouldParse {
                XCTAssertNotNil(parsed, "Failed to parse valid IPv6: \(ip)")
            } else {
                XCTAssertNil(parsed, "Should not parse invalid IPv6: \(ip)")
            }
        }
    }

    func testIPv6RangeParsing() {
        let ranges = [
            "2001:db8::/32",
            "fe80::/10",
            "::/0",
            "2001:db8::/128"
        ]

        for rangeStr in ranges {
            let range = IPRange(cidr: rangeStr)
            XCTAssertNotNil(range, "Failed to parse IPv6 range: \(rangeStr)")
        }
    }
}
