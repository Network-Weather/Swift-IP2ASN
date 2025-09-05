import XCTest

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

final class RIRDataParserTests: XCTestCase {
    func testParseIPv4Allocation() {
        let parser = RIRDataParser()

        let data = """
            # Header comment
            arin|US|ipv4|8.0.0.0|16777216|19921201|allocated|12345
            arin|CA|ipv4|24.0.0.0|65536|20000101|assigned|67890
            """

        let allocations = parser.parse(data, registry: "arin")

        XCTAssertEqual(allocations.count, 2)

        let first = allocations[0]
        XCTAssertEqual(first.asn, 12345)
        XCTAssertEqual(first.countryCode, "US")
        XCTAssertEqual(first.registry, "arin")
        XCTAssertEqual(first.range.prefixLength, 8)

        let second = allocations[1]
        XCTAssertEqual(second.asn, 67890)
        XCTAssertEqual(second.countryCode, "CA")
        XCTAssertEqual(second.range.prefixLength, 16)
    }

    func testParseIPv6Allocation() {
        let parser = RIRDataParser()

        let data = """
            ripencc|DE|ipv6|2001:db8::|32|20080101|allocated|64512
            ripencc|FR|ipv6|2001:db9::|48|20100601|assigned|64513
            """

        let allocations = parser.parse(data, registry: "ripencc")

        XCTAssertEqual(allocations.count, 2)

        let first = allocations[0]
        XCTAssertEqual(first.asn, 64512)
        XCTAssertEqual(first.countryCode, "DE")
        XCTAssertEqual(first.registry, "ripencc")
        XCTAssertEqual(first.range.prefixLength, 32)

        let second = allocations[1]
        XCTAssertEqual(second.asn, 64513)
        XCTAssertEqual(second.countryCode, "FR")
        XCTAssertEqual(second.range.prefixLength, 48)
    }

    func testParseIgnoresInvalidLines() {
        let parser = RIRDataParser()

        let data = """
            # Comment line

            arin|US|asn|12345|1|20000101|allocated
            arin|US|ipv4|invalid|256|20000101|allocated|12345
            arin|US|ipv4|8.0.0.0|256|20000101|reserved|12345
            arin|US|ipv4|8.0.0.0|256|20000101|allocated|12345
            invalid|line|format
            """

        let allocations = parser.parse(data, registry: "arin")

        XCTAssertEqual(allocations.count, 1)
        XCTAssertEqual(allocations[0].range.prefixLength, 24)
    }

    func testParseWithMissingFields() {
        let parser = RIRDataParser()

        let data = """
            arin|*|ipv4|10.0.0.0|256|20000101|allocated
            arin|US|ipv4|192.168.0.0|256|20000101|allocated|
            """

        let allocations = parser.parse(data, registry: "arin")

        XCTAssertEqual(allocations.count, 2)

        XCTAssertNil(allocations[0].countryCode)
        XCTAssertEqual(allocations[0].asn, 0)

        XCTAssertEqual(allocations[1].countryCode, "US")
        XCTAssertEqual(allocations[1].asn, 0)
    }

    func testParseAllRIRData() {
        let parser = RIRDataParser()

        let data: [RIR: String] = [
            .arin: "arin|US|ipv4|8.0.0.0|256|20000101|allocated|12345",
            .ripe: "ripencc|NL|ipv4|5.0.0.0|256|20000101|allocated|67890",
            .apnic: "apnic|JP|ipv6|2001:200::|32|20000101|allocated|64512"
        ]

        let allocations = parser.parseAll(data)

        XCTAssertEqual(allocations.count, 3)

        let registries = Set(allocations.map { $0.registry })
        XCTAssertEqual(registries.count, 3)
        XCTAssertTrue(registries.contains("arin"))
        XCTAssertTrue(registries.contains("ripencc"))
        XCTAssertTrue(registries.contains("apnic"))
    }

    func testDateParsing() {
        let parser = RIRDataParser()

        let data = """
            arin|US|ipv4|8.0.0.0|256|20201231|allocated|12345
            """

        let allocations = parser.parse(data, registry: "arin")

        XCTAssertEqual(allocations.count, 1)
        XCTAssertNotNil(allocations[0].allocatedDate)

        if let date = allocations[0].allocatedDate {
            var calendar = Calendar(identifier: .gregorian)
            guard let utcTimeZone = TimeZone(identifier: "UTC") else { return }
            calendar.timeZone = utcTimeZone
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2020)
            XCTAssertEqual(components.month, 12)
            XCTAssertEqual(components.day, 31)
        }
    }
}
