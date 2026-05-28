import Compression
import Foundation

// MARK: - UltraCompactFormat

/// Ultra-compact dual-stack database format.
///
/// File Format (magic `ULT2`, zlib-compressed payload):
/// - Header (18 bytes):
///   - 4 bytes: magic `"ULT2"`
///   - 1 byte:  format version (matches the magic; currently 2)
///   - 1 byte:  flags (current: 0; unknown bits ignored by readers)
///   - 4 bytes LE: v4 range count
///   - 4 bytes LE: v6 range count
///   - 4 bytes LE: ASN name-table count
/// - IPv4 ranges (v4 count entries):
///   - 4 bytes BE: absolute start IP
///   - varint: size (end - start)
///   - varint: ASN
/// - IPv6 ranges (v6 count entries):
///   - 16 bytes BE: absolute start IP
///   - 16 bytes BE: absolute end IP
///   - varint: ASN
/// - ASN name table (asn count entries):
///   - varint: ASN
///   - varint: nameLen
///   - nameLen bytes: UTF-8 name
///
/// Forward compatibility: readers verify the magic and reject unknown
/// format versions. Flag bits are reserved for additive features; readers
/// should ignore bits they don't understand.
public enum UltraCompactFormat {

    /// Current on-disk format version, matching the magic (`ULT2` → 2).
    /// Bump (and update the magic) when the layout changes.
    public static let currentFormatVersion: UInt8 = 2

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

/// Thread-safe, immutable database loaded from ultra-compact dual-stack format.
public struct UltraCompactDatabase: Sendable {
    // IPv4: stored as parallel UInt32 arrays for cache-friendly binary search.
    private let v4StartIPs: [UInt32]
    private let v4EndIPs: [UInt32]
    private let v4Asns: [UInt32]

    // IPv6: stored as (hi, lo) UInt64 pairs so 128-bit ranges fit native types.
    private let v6StartHi: [UInt64]
    private let v6StartLo: [UInt64]
    private let v6EndHi: [UInt64]
    private let v6EndLo: [UInt64]
    private let v6Asns: [UInt32]

    private let asnNames: [UInt32: String]

    public var entryCount: Int { v4StartIPs.count + v6StartHi.count }
    public var ipv4EntryCount: Int { v4StartIPs.count }
    public var ipv6EntryCount: Int { v6StartHi.count }
    public var uniqueASNCount: Int { asnNames.count }

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

        guard decompressed.count >= 18 else {
            throw UltraCompactError.invalidFormat
        }

        let magic = String(data: decompressed[0..<4], encoding: .utf8)
        guard magic == "ULT2" else {
            throw UltraCompactError.invalidFormat
        }

        let formatVersion = decompressed[4]
        guard formatVersion == UltraCompactFormat.currentFormatVersion else {
            throw UltraCompactError.unsupportedVersion(formatVersion)
        }
        // Flags byte at offset 5: ignored today; readers should tolerate unknown
        // bits so additive flags don't require a version bump.
        _ = decompressed[5]

        func readUInt32LE(at offset: Int) -> UInt32 {
            return UInt32(decompressed[offset]) | (UInt32(decompressed[offset + 1]) << 8)
                | (UInt32(decompressed[offset + 2]) << 16) | (UInt32(decompressed[offset + 3]) << 24)
        }

        func readUInt32BE(at offset: Int) -> UInt32 {
            return (UInt32(decompressed[offset]) << 24) | (UInt32(decompressed[offset + 1]) << 16)
                | (UInt32(decompressed[offset + 2]) << 8) | UInt32(decompressed[offset + 3])
        }

        func readUInt64BE(at offset: Int) -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<8 { v = (v << 8) | UInt64(decompressed[offset + i]) }
            return v
        }

        let v4Count = Int(readUInt32LE(at: 6))
        let v6Count = Int(readUInt32LE(at: 10))
        let asnCount = Int(readUInt32LE(at: 14))

        var v4StartIPs: [UInt32] = []
        var v4EndIPs: [UInt32] = []
        var v4Asns: [UInt32] = []
        v4StartIPs.reserveCapacity(v4Count)
        v4EndIPs.reserveCapacity(v4Count)
        v4Asns.reserveCapacity(v4Count)

        var offset = 18

        for _ in 0..<v4Count {
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
            v4StartIPs.append(startIP)
            v4EndIPs.append(startIP &+ size)
            v4Asns.append(asn)
        }

        var v6StartHi: [UInt64] = []
        var v6StartLo: [UInt64] = []
        var v6EndHi: [UInt64] = []
        var v6EndLo: [UInt64] = []
        var v6Asns: [UInt32] = []
        v6StartHi.reserveCapacity(v6Count)
        v6StartLo.reserveCapacity(v6Count)
        v6EndHi.reserveCapacity(v6Count)
        v6EndLo.reserveCapacity(v6Count)
        v6Asns.reserveCapacity(v6Count)

        for _ in 0..<v6Count {
            guard offset + 32 <= decompressed.count else {
                throw UltraCompactError.corruptedData
            }
            let sHi = readUInt64BE(at: offset)
            let sLo = readUInt64BE(at: offset + 8)
            let eHi = readUInt64BE(at: offset + 16)
            let eLo = readUInt64BE(at: offset + 24)
            offset += 32
            guard let asn = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset) else {
                throw UltraCompactError.corruptedData
            }
            v6StartHi.append(sHi)
            v6StartLo.append(sLo)
            v6EndHi.append(eHi)
            v6EndLo.append(eLo)
            v6Asns.append(asn)
        }

        var asnNames: [UInt32: String] = [:]
        asnNames.reserveCapacity(asnCount)

        for _ in 0..<asnCount {
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

        self.v4StartIPs = v4StartIPs
        self.v4EndIPs = v4EndIPs
        self.v4Asns = v4Asns
        self.v6StartHi = v6StartHi
        self.v6StartLo = v6StartLo
        self.v6EndHi = v6EndHi
        self.v6EndLo = v6EndLo
        self.v6Asns = v6Asns
        self.asnNames = asnNames
    }

    // MARK: - Lookup

    /// Look up ASN for an IPv4 or IPv6 address given as a string.
    public func lookup(_ ipString: String) -> (asn: UInt32, name: String?)? {
        if let v4 = parseIPv4ToUInt32(ipString) {
            return lookup(ip: v4)
        }
        if let (hi, lo) = parseIPv6ToPair(ipString) {
            return lookupV6(hi: hi, lo: lo)
        }
        return nil
    }

    /// Look up ASN for an IPv4 address given as UInt32.
    public func lookup(ip: UInt32) -> (asn: UInt32, name: String?)? {
        guard !v4StartIPs.isEmpty else { return nil }
        var left = 0
        var right = v4StartIPs.count - 1
        while left <= right {
            let mid = (left + right) >> 1
            if ip < v4StartIPs[mid] {
                right = mid - 1
            } else if ip > v4EndIPs[mid] {
                left = mid + 1
            } else {
                let asn = v4Asns[mid]
                return (asn, asnNames[asn])
            }
        }
        return nil
    }

    /// Look up ASN for an IPv6 address given as a (hi, lo) UInt64 pair (network byte order).
    public func lookupV6(hi: UInt64, lo: UInt64) -> (asn: UInt32, name: String?)? {
        guard !v6StartHi.isEmpty else { return nil }
        var left = 0
        var right = v6StartHi.count - 1
        while left <= right {
            let mid = (left + right) >> 1
            if compare128(hi, lo, v6StartHi[mid], v6StartLo[mid]) < 0 {
                right = mid - 1
            } else if compare128(hi, lo, v6EndHi[mid], v6EndLo[mid]) > 0 {
                left = mid + 1
            } else {
                let asn = v6Asns[mid]
                return (asn, asnNames[asn])
            }
        }
        return nil
    }

    @inline(__always)
    private func compare128(_ aHi: UInt64, _ aLo: UInt64, _ bHi: UInt64, _ bLo: UInt64) -> Int {
        if aHi != bHi { return aHi < bHi ? -1 : 1 }
        if aLo != bLo { return aLo < bLo ? -1 : 1 }
        return 0
    }

    // MARK: - Decompression

    private static func decompress(_ data: Data) throws -> Data {
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

        throw UltraCompactError.decompressionFailed
    }
}

// MARK: - Error

public enum UltraCompactError: Error, Sendable {
    case compressionFailed
    case decompressionFailed
    case invalidFormat
    case corruptedData
    case unsupportedVersion(UInt8)
}

public typealias CompactError = UltraCompactError
