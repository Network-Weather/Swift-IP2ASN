import Compression
import Foundation
import XCTest

@testable import SwiftIP2ASN

final class CompressedDatabaseReaderTests: XCTestCase {
    func testLookupFromSmallCompressedDB() throws {
        // Build a tiny compressed database in-memory (no network, no external tools)
        // Entries (IPv4 only):
        //  - 1.1.1.0/24  -> AS13335
        //  - 8.8.8.0/24  -> AS15169
        // The on-disk format matches CompressedDatabaseFormat (IP2A magic + varints, zlib-compressed)

        struct Entry {
            let start: String
            let end: String
            let asn: UInt32
        }
        var entries = [
            Entry(start: "1.1.1.0", end: "1.1.1.255", asn: 13335),
            Entry(start: "8.8.8.0", end: "8.8.8.255", asn: 15169)
        ]

        // Sort by start IP
        entries.sort { ipToUInt32($0.start)! < ipToUInt32($1.start)! }

        // Build uncompressed payload
        var payload = Data()
        payload.append(contentsOf: "IP2A".utf8)  // magic
        payload.append(uint32LE(1))  // version
        payload.append(uint32LE(UInt32(entries.count)))  // count

        var prevStart: UInt32 = 0
        for e in entries {
            let s = ipToUInt32(e.start)!
            let eip = ipToUInt32(e.end)!
            let deltaStart = s &- prevStart
            let rangeSize = eip &- s
            payload.append(encodeVarint(deltaStart))
            payload.append(encodeVarint(rangeSize))
            payload.append(encodeVarint(e.asn))
            prevStart = s
        }

        // Compress with zlib
        let compressed = try zlibCompress(payload)

        // Write to a temp file
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.cdb")
        try compressed.write(to: tmpURL)

        // Load using the library reader and verify lookups
        let db = try CompressedDatabaseFormat.loadCompressed(from: tmpURL.path)

        XCTAssertEqual(db.lookup("1.1.1.1"), 13335)
        XCTAssertEqual(db.lookup("8.8.8.8"), 15169)
        XCTAssertNil(db.lookup("9.9.9.9"))
    }

    // MARK: - Helpers
    private func ipToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    private func uint32LE(_ v: UInt32) -> Data {
        withUnsafeBytes(of: v.littleEndian) { Data($0) }
    }

    private func encodeVarint(_ value: UInt32) -> Data {
        var v = value
        var out = Data()
        while v >= 0x80 {
            out.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    private func zlibCompress(_ data: Data) throws -> Data {
        // Allocate generous output buffer to avoid failure when compressed size ~ input size
        let cap = max(128, data.count * 2)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { dst.deallocate() }
        let written = data.withUnsafeBytes { src -> Int in
            compression_encode_buffer(
                dst, cap,
                src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                nil, COMPRESSION_ZLIB
            )
        }
        if written <= 0 { throw NSError(domain: "compress", code: -1) }
        return Data(bytes: dst, count: written)
    }
}
