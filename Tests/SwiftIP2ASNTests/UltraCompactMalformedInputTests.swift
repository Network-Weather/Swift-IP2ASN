import Compression
import Foundation
import XCTest

@testable import SwiftIP2ASN

final class UltraCompactMalformedInputTests: XCTestCase {
    func testRejectsImpossibleHeaderCountsBeforeAllocation() throws {
        let raw = makeHeader(v4Count: .max)
        try assertCorrupted(raw)
    }

    func testRejectsOverlongUInt32Varints() throws {
        var raw = makeHeader(v4Count: 1)
        appendUInt32BE(0, to: &raw)
        raw.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0x10])
        try assertCorrupted(raw)

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
        try assertCorrupted(raw)
    }

    func testRejectsOverlappingOrUnsortedIPv4Ranges() throws {
        var overlapping = makeHeader(v4Count: 2)
        appendIPv4Range(start: 10, size: 10, asn: 1, to: &overlapping)
        appendIPv4Range(start: 20, size: 10, asn: 2, to: &overlapping)
        try assertCorrupted(overlapping)

        var unsorted = makeHeader(v4Count: 2)
        appendIPv4Range(start: 100, size: 10, asn: 1, to: &unsorted)
        appendIPv4Range(start: 50, size: 10, asn: 2, to: &unsorted)
        try assertCorrupted(unsorted)
    }

    func testRejectsReversedOrOverlappingIPv6Ranges() throws {
        var reversed = makeHeader(v6Count: 1)
        appendIPv6Range(startHi: 1, startLo: 0, endHi: 0, endLo: .max, asn: 1, to: &reversed)
        try assertCorrupted(reversed)

        var overlapping = makeHeader(v6Count: 2)
        appendIPv6Range(startHi: 0, startLo: 10, endHi: 0, endLo: 20, asn: 1, to: &overlapping)
        appendIPv6Range(startHi: 0, startLo: 20, endHi: 0, endLo: 30, asn: 2, to: &overlapping)
        try assertCorrupted(overlapping)
    }

    func testRejectsInvalidUTF8AndDuplicateASNNames() throws {
        var invalidUTF8 = makeHeader(asnCount: 1)
        invalidUTF8.append(contentsOf: UltraCompactFormat.encodeVarint(1))
        invalidUTF8.append(contentsOf: UltraCompactFormat.encodeVarint(1))
        invalidUTF8.append(0xFF)
        try assertCorrupted(invalidUTF8)

        var duplicate = makeHeader(asnCount: 2)
        appendASNName(asn: 1, name: "A", to: &duplicate)
        appendASNName(asn: 1, name: "B", to: &duplicate)
        try assertCorrupted(duplicate)
    }

    func testAllowsAdjacentRangesAndAdditiveTrailingData() throws {
        var raw = makeHeader(v4Count: 2, flags: 0xFF)
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

    private func assertCorrupted(
        _ raw: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let compressed = try compress(raw)
        XCTAssertThrowsError(try UltraCompactDatabase(data: compressed), file: file, line: line) { error in
            guard case UltraCompactError.corruptedData = error else {
                XCTFail("Expected corruptedData, got \(error)", file: file, line: line)
                return
            }
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
