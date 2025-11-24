import Compression
import Foundation

// MARK: - CompressedDatabaseFormat

/// Reader for compressed database format (delta-encoded and zlib-compressed).
///
/// File Format:
/// - Header: "IP2A" (4 bytes) + version (4 bytes LE) + count (4 bytes LE)
/// - Ranges: For each range:
///   - deltaStart varint (delta from previous start)
///   - rangeSize varint (end - start)
///   - asn varint
///
/// Compression: ZLIB
public enum CompressedDatabaseFormat {

    /// Load compressed database into memory.
    public static func loadCompressed(from path: String) throws -> CompactDatabase {
        let url = URL(fileURLWithPath: path)
        let compressedData = try Data(contentsOf: url)
        let decompressed = try decompress(data: compressedData)

        return try CompactDatabase(data: decompressed)
    }

    /// Decode a varint from Data at the given offset.
    @inlinable
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
                return nil
            }
        }

        return nil
    }

    private static func decompress(data: Data) throws -> Data {
        // Use adaptive buffer sizing
        var bufferSize = data.count * 8
        var attempts = 0
        let maxAttempts = 3

        while attempts < maxAttempts {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            let decompressedSize = data.withUnsafeBytes { srcBuffer -> Int in
                compression_decode_buffer(
                    buffer, bufferSize,
                    srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil, COMPRESSION_ZLIB
                )
            }

            if decompressedSize > 0 {
                return Data(bytes: buffer, count: decompressedSize)
            }

            bufferSize *= 2
            attempts += 1
        }

        throw CompressionError.decompressionFailed
    }
}

// MARK: - CompactDatabase

/// Thread-safe, immutable database loaded from compressed format.
///
/// After initialization, all data is immutable and lookups are safe
/// to call from any thread without synchronization.
public struct CompactDatabase: Sendable {
    /// Stored as contiguous arrays for cache efficiency.
    private let startIPs: [UInt32]
    private let endIPs: [UInt32]
    private let asns: [UInt32]

    public var entryCount: Int { startIPs.count }

    init(data: Data) throws {
        // Verify magic
        guard data.count >= 12,
            String(data: data[0..<4], encoding: .utf8) == "IP2A"
        else {
            throw CompressionError.invalidFormat
        }

        // Read header
        let version = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 4, as: UInt32.self).littleEndian
        }
        let count = data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 8, as: UInt32.self).littleEndian
        }

        guard version == 1 else {
            throw CompressionError.unsupportedVersion
        }

        // Pre-allocate arrays
        var startIPs: [UInt32] = []
        var endIPs: [UInt32] = []
        var asns: [UInt32] = []
        startIPs.reserveCapacity(Int(count))
        endIPs.reserveCapacity(Int(count))
        asns.reserveCapacity(Int(count))

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

            let start = prevStart &+ deltaStart
            let end = start &+ rangeSize

            startIPs.append(start)
            endIPs.append(end)
            asns.append(asn)

            prevStart = start
        }

        self.startIPs = startIPs
        self.endIPs = endIPs
        self.asns = asns
    }

    /// Look up ASN for an IPv4 address string.
    public func lookup(_ ipString: String) -> UInt32? {
        guard let ip = parseIPv4ToUInt32(ipString) else { return nil }
        return lookup(ip: ip)
    }

    /// Look up ASN for an IPv4 address as UInt32.
    public func lookup(ip: UInt32) -> UInt32? {
        var left = 0
        var right = startIPs.count - 1

        while left <= right {
            let mid = (left + right) >> 1
            let start = startIPs[mid]
            let end = endIPs[mid]

            if ip < start {
                right = mid - 1
            } else if ip > end {
                left = mid + 1
            } else {
                return asns[mid]
            }
        }

        return nil
    }
}

// MARK: - CompressionError

public enum CompressionError: Error, Sendable {
    case compressionFailed
    case decompressionFailed
    case invalidFormat
    case unsupportedVersion
    case corruptedData
}
