import Compression
import Foundation
import XCTest

@testable import SwiftIP2ASN

final class UltraCompactMalformedInputTests: XCTestCase {
    func testRejectsImpossibleHeaderCountsBeforeAllocation() throws {
        let raw = makeHeader(v4Count: .max)
        try assertValidationFailure(
            raw,
            equals: .init(
                section: .ipv4Ranges,
                field: .count,
                reason: .exceedsAvailableData,
                value: UInt64(UInt32.max)
            )
        )
    }

    func testRejectsOverlongUInt32Varints() throws {
        var raw = makeHeader(v4Count: 1)
        appendUInt32BE(0, to: &raw)
        raw.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0x10])
        try assertValidationFailure(
            raw,
            equals: .init(
                section: .ipv4Ranges,
                entryIndex: 0,
                field: .rangeSize,
                reason: .malformedVarint
            )
        )

        var dataOffset = 0
        XCTAssertNil(UltraCompactFormat.decodeVarint(from: Data([0xFF, 0xFF, 0xFF, 0xFF, 0x10]), offset: &dataOffset))

        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0x10]
        bytes.withUnsafeBytes { buffer in
            var bufferOffset = 0
            XCTAssertNil(UltraCompactFormat.decodeVarint(from: buffer, offset: &bufferOffset))
        }
    }

    func testRejectsOverflowingIPv4Range() throws {
        var raw = makeHeader(v4Count: 1)
        appendUInt32BE(.max, to: &raw)
        raw.append(contentsOf: UltraCompactFormat.encodeVarint(1))
        raw.append(contentsOf: UltraCompactFormat.encodeVarint(64512))
        try assertValidationFailure(
            raw,
            equals: .init(
                section: .ipv4Ranges,
                entryIndex: 0,
                field: .endAddress,
                reason: .arithmeticOverflow
            )
        )
    }

    func testRejectsOverlappingOrUnsortedIPv4Ranges() throws {
        var overlapping = makeHeader(v4Count: 2)
        appendIPv4Range(start: 10, size: 10, asn: 1, to: &overlapping)
        appendIPv4Range(start: 20, size: 10, asn: 2, to: &overlapping)
        let issue = UltraCompactValidationIssue(
            section: .ipv4Ranges,
            entryIndex: 1,
            field: .startAddress,
            reason: .overlappingOrUnsortedRange
        )
        try assertValidationFailure(overlapping, equals: issue)

        var unsorted = makeHeader(v4Count: 2)
        appendIPv4Range(start: 100, size: 10, asn: 1, to: &unsorted)
        appendIPv4Range(start: 50, size: 10, asn: 2, to: &unsorted)
        try assertValidationFailure(unsorted, equals: issue)
    }

    func testRejectsReversedOrOverlappingIPv6Ranges() throws {
        var reversed = makeHeader(v6Count: 1)
        appendIPv6Range(startHi: 1, startLo: 0, endHi: 0, endLo: .max, asn: 1, to: &reversed)
        try assertValidationFailure(
            reversed,
            equals: .init(
                section: .ipv6Ranges,
                entryIndex: 0,
                field: .endAddress,
                reason: .reversedRange
            )
        )

        var overlapping = makeHeader(v6Count: 2)
        appendIPv6Range(startHi: 0, startLo: 10, endHi: 0, endLo: 20, asn: 1, to: &overlapping)
        appendIPv6Range(startHi: 0, startLo: 20, endHi: 0, endLo: 30, asn: 2, to: &overlapping)
        try assertValidationFailure(
            overlapping,
            equals: .init(
                section: .ipv6Ranges,
                entryIndex: 1,
                field: .startAddress,
                reason: .overlappingOrUnsortedRange
            )
        )
    }

    func testRejectsInvalidUTF8AndDuplicateASNNames() throws {
        var invalidUTF8 = makeHeader(asnCount: 1)
        invalidUTF8.append(contentsOf: UltraCompactFormat.encodeVarint(1))
        invalidUTF8.append(contentsOf: UltraCompactFormat.encodeVarint(1))
        invalidUTF8.append(0xFF)
        try assertValidationFailure(
            invalidUTF8,
            equals: .init(
                section: .asnNames,
                entryIndex: 0,
                field: .name,
                reason: .invalidUTF8
            )
        )

        var duplicate = makeHeader(asnCount: 2)
        appendASNName(asn: 1, name: "A", to: &duplicate)
        appendASNName(asn: 1, name: "B", to: &duplicate)
        try assertValidationFailure(
            duplicate,
            equals: .init(
                section: .asnNames,
                entryIndex: 1,
                field: .asn,
                reason: .duplicateValue,
                value: 1
            )
        )
    }

    func testReportsTruncatedASNName() throws {
        var raw = makeHeader(asnCount: 1)
        raw.append(contentsOf: UltraCompactFormat.encodeVarint(64512))
        raw.append(contentsOf: UltraCompactFormat.encodeVarint(8))
        raw.append(contentsOf: "short".utf8)

        try assertValidationFailure(
            raw,
            equals: .init(
                section: .asnNames,
                entryIndex: 0,
                field: .name,
                reason: .truncated,
                value: 8
            )
        )
    }

    func testRejectsTamperedMetadataBuildIdentifier() throws {
        var raw = makeHeader(flags: UltraCompactFormat.metadataFlag)
        raw.append(contentsOf: "UMD1".utf8)
        appendUInt64LE(1_800_000_000, to: &raw)
        let source = Data("iptoasn.com".utf8)
        raw.append(contentsOf: UltraCompactFormat.encodeVarint(UInt32(source.count)))
        raw.append(source)
        raw.append(StableSHA256.digest(raw))
        raw[raw.count - 1] ^= 0x01

        try assertValidationFailure(
            raw,
            equals: .init(
                section: .metadata,
                field: .buildIdentifier,
                reason: .invalidValue
            )
        )
    }

    func testAllowsAdjacentRangesAndAdditiveTrailingData() throws {
        var raw = makeHeader(v4Count: 2, flags: 0xFE)
        appendIPv4Range(start: 10, size: 10, asn: 1, to: &raw)
        appendIPv4Range(start: 21, size: 10, asn: 2, to: &raw)
        raw.append(contentsOf: "future trailer".utf8)

        let database = try UltraCompactDatabase(data: compress(raw))
        XCTAssertEqual(database.entryCount, 2)
        XCTAssertEqual(database.lookup(ip: 20)?.asn, 1)
        XCTAssertEqual(database.lookup(ip: 21)?.asn, 2)
    }

    func testGeneratedNonOverlappingIPv4DatabasesRoundTrip() throws {
        var seed: UInt32 = 0xC0FFEE

        for _ in 0..<100 {
            var raw = makeHeader(v4Count: 25)
            var expectedRanges: [(start: UInt32, end: UInt32, asn: UInt32)] = []
            var previousEnd: UInt32 = 0

            for index in 0..<25 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let gap = (seed % 7) + 1
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let size = seed % 64
                let start = previousEnd + gap
                let asn = UInt32(index + 1)
                appendIPv4Range(start: start, size: size, asn: asn, to: &raw)
                expectedRanges.append((start, start + size, asn))
                previousEnd = start + size
            }

            let database = try UltraCompactDatabase(data: compress(raw))
            XCTAssertEqual(database.entryCount, expectedRanges.count)
            for range in expectedRanges {
                XCTAssertEqual(database.lookup(ip: range.start)?.asn, range.asn)
                XCTAssertEqual(database.lookup(ip: range.end)?.asn, range.asn)
            }
        }
    }

    private func assertValidationFailure(
        _ raw: Data,
        equals expectedIssue: UltraCompactValidationIssue,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let compressed = try compress(raw)
        XCTAssertThrowsError(try UltraCompactDatabase(data: compressed), file: file, line: line) { error in
            guard case UltraCompactError.validationFailed(let issue) = error else {
                XCTFail("Expected validationFailed, got \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(issue, expectedIssue, file: file, line: line)
        }
    }

    private func makeHeader(
        v4Count: UInt32 = 0,
        v6Count: UInt32 = 0,
        asnCount: UInt32 = 0,
        flags: UInt8 = 0
    ) -> Data {
        var data = Data("ULT2".utf8)
        data.append(UltraCompactFormat.currentFormatVersion)
        data.append(flags)
        appendUInt32LE(v4Count, to: &data)
        appendUInt32LE(v6Count, to: &data)
        appendUInt32LE(asnCount, to: &data)
        return data
    }

    private func appendIPv4Range(
        start: UInt32,
        size: UInt32,
        asn: UInt32,
        to data: inout Data
    ) {
        appendUInt32BE(start, to: &data)
        data.append(contentsOf: UltraCompactFormat.encodeVarint(size))
        data.append(contentsOf: UltraCompactFormat.encodeVarint(asn))
    }

    private func appendIPv6Range(
        startHi: UInt64,
        startLo: UInt64,
        endHi: UInt64,
        endLo: UInt64,
        asn: UInt32,
        to data: inout Data
    ) {
        appendUInt64BE(startHi, to: &data)
        appendUInt64BE(startLo, to: &data)
        appendUInt64BE(endHi, to: &data)
        appendUInt64BE(endLo, to: &data)
        data.append(contentsOf: UltraCompactFormat.encodeVarint(asn))
    }

    private func appendASNName(asn: UInt32, name: String, to data: inout Data) {
        let nameData = Data(name.utf8)
        data.append(contentsOf: UltraCompactFormat.encodeVarint(asn))
        data.append(contentsOf: UltraCompactFormat.encodeVarint(UInt32(nameData.count)))
        data.append(nameData)
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private func appendUInt64BE(_ value: UInt64, to data: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }

    private func appendUInt64LE(_ value: UInt64, to data: inout Data) {
        for shift in stride(from: 0, through: 56, by: 8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }

    private func compress(_ data: Data) throws -> Data {
        let capacity = max(data.count * 2, data.count + 64)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }

        let written = data.withUnsafeBytes { source in
            compression_encode_buffer(
                destination,
                capacity,
                source.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard written > 0 else {
            throw UltraCompactError.compressionFailed
        }
        return Data(bytes: destination, count: written)
    }
}
