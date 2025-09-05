import Compression
import Foundation

/// Reader for compressed database format (delta-encoded and zlib-compressed)
public struct CompressedDatabaseFormat {

    /// Load compressed database into memory
    public static func loadCompressed(from path: String) throws -> CompactDatabase {
        let compressedData = try Data(contentsOf: URL(fileURLWithPath: path))
        let decompressed = try decompress(data: compressedData)

        return try CompactDatabase(data: decompressed)
    }

    static func decodeVarint(from data: Data, offset: inout Int) -> UInt32? {
        var result: UInt32 = 0
        var shift: UInt32 = 0

        while offset < data.count {
            let byte = data[offset]
            offset += 1

            result |= UInt32(byte & 0x7F) << shift

            if byte & 0x80 == 0 {
                return result
            }

            shift += 7
            if shift >= 32 {
                return nil  // Overflow
            }
        }

        return nil
    }

    private static func decompress(data: Data) throws -> Data {
        // Estimate decompressed size (10x is usually safe)
        let destinationBufferSize = data.count * 10
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = compression_decode_buffer(
            destinationBuffer, destinationBufferSize,
            data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! },
            data.count,
            nil, COMPRESSION_ZLIB
        )

        guard decompressedSize > 0 else {
            throw CompressionError.decompressionFailed
        }

        return Data(bytes: destinationBuffer, count: decompressedSize)
    }

}

/// Compact in-memory database loaded from compressed file
public class CompactDatabase {
    private var ranges: [(start: UInt32, end: UInt32, asn: UInt32)] = []

    init(data: Data) throws {
        // Verify magic
        guard data.count >= 12,
            String(data: data[0..<4], encoding: .utf8) == "IP2A"
        else {
            throw CompressionError.invalidFormat
        }

        // Read header
        let version = data[4..<8].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let count = data[8..<12].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        guard version == 1 else {
            throw CompressionError.unsupportedVersion
        }

        // Decode entries
        var offset = 12
        var prevStart: UInt32 = 0

        for _ in 0..<count {
            guard let deltaStart = CompressedDatabaseFormat.decodeVarint(from: data, offset: &offset),
                let rangeSize = CompressedDatabaseFormat.decodeVarint(from: data, offset: &offset),
                let asn = CompressedDatabaseFormat.decodeVarint(from: data, offset: &offset)
            else {
                throw CompressionError.corruptedData
            }

            let start = prevStart + deltaStart
            let end = start + rangeSize

            ranges.append((start, end, asn))
            prevStart = start
        }
    }

    public func lookup(_ ipString: String) -> UInt32? {
        guard let ip = ipStringToUInt32(ipString) else { return nil }

        // Binary search
        var left = 0
        var right = ranges.count - 1

        while left <= right {
            let mid = (left + right) / 2
            let range = ranges[mid]

            if ip < range.start {
                right = mid - 1
            } else if ip > range.end {
                left = mid + 1
            } else {
                return range.asn
            }
        }

        return nil
    }

    private func ipStringToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    public var entryCount: Int { ranges.count }
}

enum CompressionError: Error {
    case compressionFailed
    case decompressionFailed
    case invalidFormat
    case unsupportedVersion
    case corruptedData
}
