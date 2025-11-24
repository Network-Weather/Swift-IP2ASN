import Compression
import Foundation

// MARK: - UltraCompactFormat

/// Ultra-compact database format using delta encoding.
///
/// File Format:
/// - Header: "ULTR" (4 bytes) + rangeCount (4 bytes LE) + asnCount (4 bytes LE)
/// - Ranges: For each range:
///   - First range: absolute startIP (4 bytes BE)
///   - Subsequent: gap varint (0 = contiguous, or gap | 0x80000000)
///   - Size varint (end - start)
///   - ASN varint
/// - ASN Table: count (4 bytes LE) + entries (asn varint + nameLen varint + name bytes)
///
/// Compression: ZLIB
public enum UltraCompactFormat {

    // MARK: - Varint Encoding

    /// Encode a UInt32 as a variable-length integer (Protocol Buffers style).
    @inlinable
    public static func encodeVarint(_ value: UInt32) -> [UInt8] {
        var result: [UInt8] = []
        var current = value

        while current >= 0x80 {
            result.append(UInt8((current & 0x7F) | 0x80))
            current >>= 7
        }
        result.append(UInt8(current))

        return result
    }

    /// Decode a varint from a buffer at the given offset.
    /// Updates offset to point past the decoded value.
    @inlinable
    public static func decodeVarint(from buffer: UnsafeRawBufferPointer, offset: inout Int) -> UInt32? {
        var result: UInt32 = 0
        var shift: UInt32 = 0

        while offset < buffer.count {
            let byte = buffer.load(fromByteOffset: offset, as: UInt8.self)
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

    /// Decode a varint from Data at the given offset.
    @inlinable
    public static func decodeVarint(from data: Data, offset: inout Int) -> UInt32? {
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
}

// MARK: - UltraCompactDatabase

/// Thread-safe, immutable database loaded from ultra-compact format.
///
/// After initialization, all data is immutable and lookups are safe
/// to call from any thread without synchronization.
public struct UltraCompactDatabase: Sendable {
    /// Stored as contiguous arrays for cache efficiency.
    private let startIPs: [UInt32]
    private let endIPs: [UInt32]
    private let asns: [UInt32]
    private let asnNames: [UInt32: String]

    public var entryCount: Int { startIPs.count }
    public var uniqueASNCount: Int { asnNames.count }

    // MARK: - Initialization

    public init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let compressed = try Data(contentsOf: url)
        try self.init(compressedData: compressed)
    }

    public init(data: Data) throws {
        try self.init(compressedData: data)
    }

    private init(compressedData: Data) throws {
        let decompressed = try Self.decompress(compressedData)

        guard decompressed.count >= 12 else {
            throw UltraCompactError.invalidFormat
        }

        // Parse header (safe byte-by-byte reading to avoid alignment issues)
        let magic = String(data: decompressed[0..<4], encoding: .utf8)
        guard magic == "ULTR" else {
            throw UltraCompactError.invalidFormat
        }

        // Read UInt32 little-endian safely (byte-by-byte)
        func readUInt32LE(at offset: Int) -> UInt32 {
            return UInt32(decompressed[offset]) | (UInt32(decompressed[offset + 1]) << 8)
                | (UInt32(decompressed[offset + 2]) << 16) | (UInt32(decompressed[offset + 3]) << 24)
        }

        // Read UInt32 big-endian safely (byte-by-byte)
        func readUInt32BE(at offset: Int) -> UInt32 {
            return (UInt32(decompressed[offset]) << 24) | (UInt32(decompressed[offset + 1]) << 16)
                | (UInt32(decompressed[offset + 2]) << 8) | UInt32(decompressed[offset + 3])
        }

        let rangeCount = readUInt32LE(at: 4)

        // Pre-allocate arrays
        var startIPs: [UInt32] = []
        var endIPs: [UInt32] = []
        var asns: [UInt32] = []
        startIPs.reserveCapacity(Int(rangeCount))
        endIPs.reserveCapacity(Int(rangeCount))
        asns.reserveCapacity(Int(rangeCount))

        var offset = 12

        // Decode ranges
        // Builder format: every range has absolute start IP (big-endian) + size varint + asn varint
        for _ in 0..<rangeCount {
            guard offset + 4 <= decompressed.count else {
                throw UltraCompactError.corruptedData
            }

            let startIP = readUInt32BE(at: offset)
            offset += 4

            guard let size = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset),
                let asn = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset)
            else {
                throw UltraCompactError.corruptedData
            }

            let endIP = startIP &+ size
            startIPs.append(startIP)
            endIPs.append(endIP)
            asns.append(asn)
        }

        // Parse ASN name table
        guard offset + 4 <= decompressed.count else {
            throw UltraCompactError.corruptedData
        }

        let asnTableCount = readUInt32LE(at: offset)
        offset += 4

        var asnNames: [UInt32: String] = [:]
        asnNames.reserveCapacity(Int(asnTableCount))

        for _ in 0..<asnTableCount {
            guard let asn = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset),
                let nameLen = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset)
            else {
                throw UltraCompactError.corruptedData
            }

            guard offset + Int(nameLen) <= decompressed.count else {
                throw UltraCompactError.corruptedData
            }

            let nameData = decompressed[offset..<offset + Int(nameLen)]
            if let name = String(data: nameData, encoding: .utf8) {
                asnNames[asn] = name
            }
            offset += Int(nameLen)
        }

        self.startIPs = startIPs
        self.endIPs = endIPs
        self.asns = asns
        self.asnNames = asnNames
    }

    // MARK: - Lookup

    /// Look up ASN for an IPv4 address string.
    /// Returns nil if address is invalid or not found.
    public func lookup(_ ipString: String) -> (asn: UInt32, name: String?)? {
        guard let ip = parseIPv4ToUInt32(ipString) else { return nil }
        return lookup(ip: ip)
    }

    /// Look up ASN for an IPv4 address as UInt32.
    public func lookup(ip: UInt32) -> (asn: UInt32, name: String?)? {
        // Binary search
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
                let asn = asns[mid]
                return (asn, asnNames[asn])
            }
        }

        return nil
    }

    // MARK: - Decompression

    private static func decompress(_ data: Data) throws -> Data {
        // Use adaptive buffer sizing based on typical compression ratios
        // Start with 8x and grow if needed
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

            // Buffer might be too small, try larger
            bufferSize *= 2
            attempts += 1
        }

        throw UltraCompactError.decompressionFailed
    }
}

// MARK: - Error

public enum UltraCompactError: Error, Sendable {
    case compressionFailed
    case decompressionFailed
    case invalidFormat
    case corruptedData
}

// MARK: - Compatibility Alias

public typealias CompactError = UltraCompactError
