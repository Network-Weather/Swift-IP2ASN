import XCTest

@testable import SwiftIP2ASN

final class IPAddressTests: XCTestCase {
    func testIPv4Parsing() {
        XCTAssertNotNil(IPAddress(string: "192.168.1.1"))
        XCTAssertNotNil(IPAddress(string: "0.0.0.0"))
        XCTAssertNotNil(IPAddress(string: "255.255.255.255"))

        // Note: Network.IPv4Address is more permissive than expected
        // It accepts various formats like "1.1" which expands to "1.1.0.0"
        XCTAssertNil(IPAddress(string: "256.256.256.256"))
        XCTAssertNil(IPAddress(string: "invalid"))
    }

    func testIPv6Parsing() {
        XCTAssertNotNil(IPAddress(string: "2001:db8::1"))
        XCTAssertNotNil(IPAddress(string: "::1"))
        XCTAssertNotNil(IPAddress(string: "::"))
        XCTAssertNotNil(IPAddress(string: "2001:0db8:0000:0000:0000:0000:0000:0001"))
        XCTAssertNotNil(IPAddress(string: "fe80::1"))

        XCTAssertNil(IPAddress(string: "gggg::1"))
        XCTAssertNil(IPAddress(string: "2001:db8::1::2"))
    }

    func testIPv4BitAccess() {
        guard let ip = IPAddress(string: "192.168.1.1") else { return }

        // 192 = 11000000
        XCTAssertTrue(ip.getBit(at: 0))
        XCTAssertTrue(ip.getBit(at: 1))
        XCTAssertFalse(ip.getBit(at: 2))
        XCTAssertFalse(ip.getBit(at: 3))
        XCTAssertFalse(ip.getBit(at: 4))
        XCTAssertFalse(ip.getBit(at: 5))
        XCTAssertFalse(ip.getBit(at: 6))
        XCTAssertFalse(ip.getBit(at: 7))
    }

    func testIPv6BitAccess() {
        guard let ip = IPAddress(string: "2001:db8::1") else { return }

        // 2001 = 0010 0000 0000 0001
        // First byte: 0x20 = 00100000
        XCTAssertFalse(ip.getBit(at: 0))
        XCTAssertFalse(ip.getBit(at: 1))
        XCTAssertTrue(ip.getBit(at: 2))
        XCTAssertFalse(ip.getBit(at: 3))
        XCTAssertFalse(ip.getBit(at: 4))
        XCTAssertFalse(ip.getBit(at: 5))
        XCTAssertFalse(ip.getBit(at: 6))
        XCTAssertFalse(ip.getBit(at: 7))
    }

    func testIPRangeParsing() {
        let range1 = IPRange(cidr: "192.168.0.0/16")
        XCTAssertNotNil(range1)
        XCTAssertEqual(range1?.prefixLength, 16)

        let range2 = IPRange(cidr: "2001:db8::/32")
        XCTAssertNotNil(range2)
        XCTAssertEqual(range2?.prefixLength, 32)

        XCTAssertNil(IPRange(cidr: "invalid"))
        XCTAssertNil(IPRange(cidr: "192.168.0.0/33"))
        XCTAssertNil(IPRange(cidr: "2001:db8::/129"))
    }

    func testIPv4RangeContains() {
        guard let range = IPRange(cidr: "192.168.0.0/16") else { return }

        guard let ip1 = IPAddress(string: "192.168.0.0") else { return }
        XCTAssertTrue(range.contains(ip1))
        guard let ip2 = IPAddress(string: "192.168.1.1") else { return }
        XCTAssertTrue(range.contains(ip2))
        guard let ip3 = IPAddress(string: "192.168.255.255") else { return }
        XCTAssertTrue(range.contains(ip3))

        guard let ip4 = IPAddress(string: "192.169.0.0") else { return }
        XCTAssertFalse(range.contains(ip4))
        guard let ip5 = IPAddress(string: "10.0.0.1") else { return }
        XCTAssertFalse(range.contains(ip5))
    }

    func testIPv6RangeContains() {
        guard let range = IPRange(cidr: "2001:db8::/32") else { return }

        guard let ip1 = IPAddress(string: "2001:db8::1") else { return }
        XCTAssertTrue(range.contains(ip1))
        guard let ip2 = IPAddress(string: "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff") else { return }
        XCTAssertTrue(range.contains(ip2))

        guard let ip3 = IPAddress(string: "2001:db9::1") else { return }
        XCTAssertFalse(range.contains(ip3))
        guard let ip4 = IPAddress(string: "2002:db8::1") else { return }
        XCTAssertFalse(range.contains(ip4))
    }

    func testMixedTypeRangeContains() {
        guard let ipv4Range = IPRange(cidr: "192.168.0.0/16") else { return }
        guard let ipv6Address = IPAddress(string: "2001:db8::1") else { return }

        XCTAssertFalse(ipv4Range.contains(ipv6Address))

        guard let ipv6Range = IPRange(cidr: "2001:db8::/32") else { return }
        guard let ipv4Address = IPAddress(string: "192.168.1.1") else { return }

        XCTAssertFalse(ipv6Range.contains(ipv4Address))
    }

    func testDebugDescription() {
        guard let ipv4 = IPAddress(string: "192.168.1.1") else { return }
        XCTAssertEqual(ipv4.debugDescription, "192.168.1.1")

        // Network framework uses compressed notation
        guard let ipv6 = IPAddress(string: "2001:db8::1") else { return }
        XCTAssertEqual(ipv6.debugDescription, "2001:db8::1")
    }
}

