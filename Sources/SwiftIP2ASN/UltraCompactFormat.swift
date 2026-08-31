import Compression
import Foundation

// MARK: - UltraCompactFormat

/// Ultra-compact dual-stack database format.
///
/// File Format (magic `ULT2`, zlib-compressed payload):
/// - Header (18 bytes):
///   - 4 bytes: magic `"ULT2"`
///   - 1 byte:  format version (matches the magic; currently 2)
///   - 1 byte:  flags (bit 0: metadata trailer; unknown bits ignored)
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
/// - Optional metadata trailer (when flags bit 0 is set):
///   - 4 bytes: metadata magic `"UMD1"`
///   - 8 bytes LE: generation time as Unix seconds
///   - varint: source identifier byte length
///   - source identifier bytes: UTF-8
///   - 32 bytes: SHA-256 of all preceding uncompressed bytes
///
/// Forward compatibility: readers verify the magic and reject unknown
/// format versions. Readers ignore flag bits they do not understand.
public enum UltraCompactFormat {

    /// Current on-disk format version, matching the magic (`ULT2` → 2).
    /// Bump (and update the magic) when the layout changes.
    public static let currentFormatVersion: UInt8 = 2

    /// Header flag indicating that a version-1 metadata trailer follows the
    /// ASN name table. Released readers ignore this bit and trailing bytes.
    public static let metadataFlag: UInt8 = 1 << 0

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

            if shift == 28, byte & 0xF0 != 0 {
                return nil
            }
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

            if shift == 28, byte & 0xF0 != 0 {
                return nil
            }
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

    /// Encoded build identity and provenance.
    public let metadata: DatabaseMetadata

    /// Runtime source from which this database instance was loaded.
    public let origin: DatabaseOrigin

    public var entryCount: Int { v4StartIPs.count + v6StartHi.count }
    public var ipv4EntryCount: Int { v4StartIPs.count }
    public var ipv6EntryCount: Int { v6StartHi.count }
    public var uniqueASNCount: Int { asnNames.count }

    public init(path: String) throws {
        try self.init(path: path, origin: .file)
    }

    init(path: String, origin: DatabaseOrigin) throws {
        let url = URL(fileURLWithPath: path)
        let compressed = try Data(contentsOf: url)
        try self.init(compressedData: compressed, origin: origin)
    }

    public init(data: Data) throws {
        try self.init(data: data, origin: .memory)
    }

    init(data: Data, origin: DatabaseOrigin) throws {
        try self.init(compressedData: data, origin: origin)
    }

    private init(compressedData: Data, origin: DatabaseOrigin) throws {
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
        // Unknown flag bits remain ignored so additive features do not require
        // a format-version bump.
        let flags = decompressed[5]

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

        func readUInt64LE(at offset: Int) -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<8 {
                value |= UInt64(decompressed[offset + index]) << UInt64(index * 8)
            }
            return value
        }

        let v4Count = Int(readUInt32LE(at: 6))
        let v6Count = Int(readUInt32LE(at: 10))
        let asnCount = Int(readUInt32LE(at: 14))

        func validationFailed(
            section: UltraCompactValidationIssue.Section,
            entryIndex: Int? = nil,
            field: UltraCompactValidationIssue.Field,
            reason: UltraCompactValidationIssue.Reason,
            value: UInt64? = nil
        ) -> UltraCompactError {
            .validationFailed(
                UltraCompactValidationIssue(
                    section: section,
                    entryIndex: entryIndex,
                    field: field,
                    reason: reason,
                    value: value
                )
            )
        }

        // Validate the cheapest possible representation before reserving arrays.
        // This prevents hostile count fields from causing excessive allocation.
        let (minimumV4Bytes, v4SizeOverflow) = v4Count.multipliedReportingOverflow(by: 6)
        let (minimumV6Bytes, v6SizeOverflow) = v6Count.multipliedReportingOverflow(by: 33)
        let (minimumASNBytes, asnSizeOverflow) = asnCount.multipliedReportingOverflow(by: 2)
        let availablePayloadBytes = decompressed.count - 18
        guard !v4SizeOverflow, minimumV4Bytes <= availablePayloadBytes else {
            throw validationFailed(
                section: .ipv4Ranges,
                field: .count,
                reason: .exceedsAvailableData,
                value: UInt64(v4Count)
            )
        }
        let bytesAfterIPv4Minimum = availablePayloadBytes - minimumV4Bytes
        guard !v6SizeOverflow, minimumV6Bytes <= bytesAfterIPv4Minimum else {
            throw validationFailed(
                section: .ipv6Ranges,
                field: .count,
                reason: .exceedsAvailableData,
                value: UInt64(v6Count)
            )
        }
        let bytesAfterRangeMinimum = bytesAfterIPv4Minimum - minimumV6Bytes
        guard !asnSizeOverflow, minimumASNBytes <= bytesAfterRangeMinimum else {
            throw validationFailed(
                section: .asnNames,
                field: .count,
                reason: .exceedsAvailableData,
                value: UInt64(asnCount)
            )
        }

        var v4StartIPs: [UInt32] = []
        var v4EndIPs: [UInt32] = []
        var v4Asns: [UInt32] = []
        v4StartIPs.reserveCapacity(v4Count)
        v4EndIPs.reserveCapacity(v4Count)
        v4Asns.reserveCapacity(v4Count)

        var offset = 18

        for index in 0..<v4Count {
            guard offset + 4 <= decompressed.count else {
                throw validationFailed(
                    section: .ipv4Ranges,
                    entryIndex: index,
                    field: .startAddress,
                    reason: .truncated
                )
            }
            let startIP = readUInt32BE(at: offset)
            offset += 4
            guard let size = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset) else {
                throw validationFailed(
                    section: .ipv4Ranges,
                    entryIndex: index,
                    field: .rangeSize,
                    reason: .malformedVarint
                )
            }
            guard let asn = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset) else {
                throw validationFailed(
                    section: .ipv4Ranges,
                    entryIndex: index,
                    field: .asn,
                    reason: .malformedVarint
                )
            }
            let (endIP, endOverflow) = startIP.addingReportingOverflow(size)
            guard !endOverflow else {
                throw validationFailed(
                    section: .ipv4Ranges,
                    entryIndex: index,
                    field: .endAddress,
                    reason: .arithmeticOverflow
                )
            }
            if let previousEnd = v4EndIPs.last, startIP <= previousEnd {
                throw validationFailed(
                    section: .ipv4Ranges,
                    entryIndex: index,
                    field: .startAddress,
                    reason: .overlappingOrUnsortedRange
                )
            }
            v4StartIPs.append(startIP)
            v4EndIPs.append(endIP)
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

        func compare128(_ aHi: UInt64, _ aLo: UInt64, _ bHi: UInt64, _ bLo: UInt64) -> Int {
            if aHi != bHi { return aHi < bHi ? -1 : 1 }
            if aLo != bLo { return aLo < bLo ? -1 : 1 }
            return 0
        }

        for index in 0..<v6Count {
            guard offset + 32 <= decompressed.count else {
                throw validationFailed(
                    section: .ipv6Ranges,
                    entryIndex: index,
                    field: .startAddress,
                    reason: .truncated
                )
            }
            let sHi = readUInt64BE(at: offset)
            let sLo = readUInt64BE(at: offset + 8)
            let eHi = readUInt64BE(at: offset + 16)
            let eLo = readUInt64BE(at: offset + 24)
            offset += 32
            guard let asn = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset) else {
                throw validationFailed(
                    section: .ipv6Ranges,
                    entryIndex: index,
                    field: .asn,
                    reason: .malformedVarint
                )
            }
            guard compare128(sHi, sLo, eHi, eLo) <= 0 else {
                throw validationFailed(
                    section: .ipv6Ranges,
                    entryIndex: index,
                    field: .endAddress,
                    reason: .reversedRange
                )
            }
            if let previousEndHi = v6EndHi.last,
                let previousEndLo = v6EndLo.last,
                compare128(sHi, sLo, previousEndHi, previousEndLo) <= 0
            {
                throw validationFailed(
                    section: .ipv6Ranges,
                    entryIndex: index,
                    field: .startAddress,
                    reason: .overlappingOrUnsortedRange
                )
            }
            v6StartHi.append(sHi)
            v6StartLo.append(sLo)
            v6EndHi.append(eHi)
            v6EndLo.append(eLo)
            v6Asns.append(asn)
        }

        var asnNames: [UInt32: String] = [:]
        asnNames.reserveCapacity(asnCount)

        for index in 0..<asnCount {
            guard let asn = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset) else {
                throw validationFailed(
                    section: .asnNames,
                    entryIndex: index,
                    field: .asn,
                    reason: .malformedVarint
                )
            }
            guard let nameLen = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset) else {
                throw validationFailed(
                    section: .asnNames,
                    entryIndex: index,
                    field: .nameLength,
                    reason: .malformedVarint
                )
            }
            let nameLength = Int(nameLen)
            guard nameLength <= decompressed.count - offset else {
                throw validationFailed(
                    section: .asnNames,
                    entryIndex: index,
                    field: .name,
                    reason: .truncated,
                    value: UInt64(nameLen)
                )
            }
            let nameData = decompressed[offset..<offset + nameLength]
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw validationFailed(
                    section: .asnNames,
                    entryIndex: index,
                    field: .name,
                    reason: .invalidUTF8
                )
            }
            guard asnNames[asn] == nil else {
                throw validationFailed(
                    section: .asnNames,
                    entryIndex: index,
                    field: .asn,
                    reason: .duplicateValue,
                    value: UInt64(asn)
                )
            }
            asnNames[asn] = name
            offset += nameLength
        }

        var generationTimestamp: Date?
        var sourceIdentifier: String?
        let buildIdentifier: String

        if flags & UltraCompactFormat.metadataFlag != 0 {
            let magic = UltraCompactFormat.metadataTrailerMagic
            guard offset + magic.count <= decompressed.count else {
                throw validationFailed(
                    section: .metadata,
                    field: .trailerMagic,
                    reason: .truncated
                )
            }
            guard decompressed[offset..<offset + magic.count].elementsEqual(magic) else {
                throw validationFailed(
                    section: .metadata,
                    field: .trailerMagic,
                    reason: .invalidValue
                )
            }
            offset += magic.count

            guard offset + 8 <= decompressed.count else {
                throw validationFailed(
                    section: .metadata,
                    field: .generationTimestamp,
                    reason: .truncated
                )
            }
            let generatedAtSeconds = readUInt64LE(at: offset)
            generationTimestamp = Date(timeIntervalSince1970: TimeInterval(generatedAtSeconds))
            offset += 8

            guard let sourceLength = UltraCompactFormat.decodeVarint(from: decompressed, offset: &offset) else {
                throw validationFailed(
                    section: .metadata,
                    field: .sourceIdentifier,
                    reason: .malformedVarint
                )
            }
            let sourceByteCount = Int(sourceLength)
            guard sourceByteCount <= decompressed.count - offset else {
                throw validationFailed(
                    section: .metadata,
                    field: .sourceIdentifier,
                    reason: .truncated,
                    value: UInt64(sourceLength)
                )
            }
            let sourceData = decompressed[offset..<offset + sourceByteCount]
            guard let source = String(data: sourceData, encoding: .utf8) else {
                throw validationFailed(
                    section: .metadata,
                    field: .sourceIdentifier,
                    reason: .invalidUTF8
                )
            }
            guard !source.isEmpty else {
                throw validationFailed(
                    section: .metadata,
                    field: .sourceIdentifier,
                    reason: .invalidValue
                )
            }
            sourceIdentifier = source
            offset += sourceByteCount

            let digestLength = 32
            guard digestLength <= decompressed.count - offset else {
                throw validationFailed(
                    section: .metadata,
                    field: .buildIdentifier,
                    reason: .truncated
                )
            }
            let storedDigest = Data(decompressed[offset..<offset + digestLength])
            let expectedDigest = StableSHA256.digest(Data(decompressed[..<offset]))
            guard storedDigest == expectedDigest else {
                throw validationFailed(
                    section: .metadata,
                    field: .buildIdentifier,
                    reason: .invalidValue
                )
            }
            buildIdentifier = storedDigest.map { String(format: "%02x", $0) }.joined()
        } else {
            buildIdentifier = StableSHA256.hexDigest(decompressed)
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
        self.metadata = DatabaseMetadata(
            formatVersion: formatVersion,
            generationTimestamp: generationTimestamp,
            sourceIdentifier: sourceIdentifier,
            ipv4RangeCount: v4Count,
            ipv6RangeCount: v6Count,
            buildIdentifier: buildIdentifier
        )
        self.origin = origin
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
        guard !data.isEmpty else {
            throw UltraCompactError.decompressionFailed
        }
        let (initialBufferSize, initialSizeOverflow) = data.count.multipliedReportingOverflow(by: 8)
        guard !initialSizeOverflow else {
            throw UltraCompactError.decompressionFailed
        }

        var bufferSize = initialBufferSize
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

            attempts += 1
            if attempts < maxAttempts {
                let (nextBufferSize, sizeOverflow) = bufferSize.multipliedReportingOverflow(by: 2)
                guard !sizeOverflow else {
                    throw UltraCompactError.decompressionFailed
                }
                bufferSize = nextBufferSize
            }
        }

        throw UltraCompactError.decompressionFailed
    }
}

// MARK: - Error

/// Structured context for a malformed ULT2 payload.
///
/// Inspect this value when ``UltraCompactError/validationFailed(_:)`` is
/// thrown to identify the section, entry, field, and validation rule that
/// rejected the database.
public struct UltraCompactValidationIssue: Equatable, Sendable {
    /// Logical section of the ULT2 payload being decoded.
    public enum Section: String, Equatable, Sendable {
        case ipv4Ranges
        case ipv6Ranges
        case asnNames
        case metadata
    }

    /// Field within the section that failed validation.
    public enum Field: String, Equatable, Sendable {
        case count
        case startAddress
        case endAddress
        case rangeSize
        case asn
        case nameLength
        case name
        case trailerMagic
        case generationTimestamp
        case sourceIdentifier
        case buildIdentifier
    }

    /// Rule violated by the encoded field.
    public enum Reason: String, Equatable, Sendable {
        case exceedsAvailableData
        case truncated
        case malformedVarint
        case arithmeticOverflow
        case reversedRange
        case overlappingOrUnsortedRange
        case invalidUTF8
        case duplicateValue
        case invalidValue
    }

    /// Payload section containing the rejected field.
    public let section: Section

    /// Zero-based entry index, or `nil` when the issue applies to a section count.
    public let entryIndex: Int?

    /// Encoded field that failed validation.
    public let field: Field

    /// Validation rule violated by the field.
    public let reason: Reason

    /// Encoded count, length, or duplicate ASN when one helps diagnose the issue.
    public let value: UInt64?

    /// Creates structured validation context.
    public init(
        section: Section,
        entryIndex: Int? = nil,
        field: Field,
        reason: Reason,
        value: UInt64? = nil
    ) {
        self.section = section
        self.entryIndex = entryIndex
        self.field = field
        self.reason = reason
        self.value = value
    }
}

/// Errors produced while encoding or loading an ultra-compact database.
public enum UltraCompactError: Error, Sendable {
    case compressionFailed
    case decompressionFailed
    case invalidFormat

    /// A legacy catch-all retained for source compatibility.
    ///
    /// New ULT2 validation failures use ``validationFailed(_:)``.
    @available(*, deprecated, message: "Inspect validationFailed(_:) for structured diagnostics")
    case corruptedData

    /// The payload structure was recognized, but a field failed validation.
    case validationFailed(UltraCompactValidationIssue)
    case unsupportedVersion(UInt8)
}

public typealias CompactError = UltraCompactError
