import Compression
import Foundation
@_spi(IP2ASNDataPrep) import SwiftIP2ASN

/// Reproducible provenance settings for a ULT2 metadata trailer.
public struct UltraCompactBuildMetadata: Equatable, Sendable {
    /// Generation time. ULT2 stores this at whole-second precision.
    public let generationTimestamp: Date

    /// Stable identifier for the normalized input source.
    public let sourceIdentifier: String

    public init(generationTimestamp: Date, sourceIdentifier: String) {
        self.generationTimestamp = generationTimestamp
        self.sourceIdentifier = sourceIdentifier
    }
}

/// Errors produced while encoding ULT2 build metadata.
public enum UltraCompactBuilderError: Error, Equatable, Sendable {
    case invalidGenerationTimestamp
    case emptySourceIdentifier
    case sourceIdentifierTooLong
}

public enum UltraCompactBuilder {

    /// Build an ultra-compact (V2) database from an IPv4 TSV. The output contains zero IPv6 ranges.
    public static func createUltraCompact(
        from tsvPath: String,
        to outputPath: String,
        metadata: UltraCompactBuildMetadata? = nil
    ) throws {
        try createUltraCompact(
            ipv4TSV: tsvPath,
            ipv6TSV: nil,
            to: outputPath,
            metadata: metadata
        )
    }

    /// Build an ultra-compact (V2) dual-stack database from one or both iptoasn TSVs.
    ///
    /// - Parameters:
    ///   - ipv4TSV: Path to `ip2asn-v4.tsv`. Optional; pass nil to build IPv6-only.
    ///   - ipv6TSV: Path to `ip2asn-v6.tsv`. Optional; pass nil to build IPv4-only.
    ///   - outputPath: Where to write the zlib-compressed `.ultra` file.
    ///   - metadata: Reproducible provenance to encode, or `nil` for the legacy
    ///     ULT2 layout without a metadata trailer.
    public static func createUltraCompact(
        ipv4TSV: String?,
        ipv6TSV: String?,
        to outputPath: String,
        metadata: UltraCompactBuildMetadata? = nil
    ) throws {
        _ = try build(ipv4TSV: ipv4TSV, ipv6TSV: ipv6TSV, to: outputPath, metadata: metadata)
    }

    package struct RowCounts: Encodable {
        var total = 0
        var blank = 0
        var unrouted = 0
    }

    package static func build(
        ipv4TSV: String?, ipv6TSV: String?, to outputPath: String,
        metadata: UltraCompactBuildMetadata?
    ) throws -> RowCounts {
        guard ipv4TSV != nil || ipv6TSV != nil else {
            throw TSVInputError("Provide at least one IPv4 or IPv6 TSV input")
        }

        var counts = RowCounts()
        var asnNames: [UInt32: String] = [:]
        let v4Ranges = try readRanges(
            path: ipv4TSV, family: "IPv4", parse: parseIPv4ToUInt32, less: (<),
            names: &asnNames, counts: &counts
        )
        let v6Ranges = try readRanges(
            path: ipv6TSV, family: "IPv6", parse: parseIPv6ToPair, less: (<),
            names: &asnNames, counts: &counts
        )
        guard let v4Count = UInt32(exactly: v4Ranges.count),
            let v6Count = UInt32(exactly: v6Ranges.count),
            let nameCount = UInt32(exactly: asnNames.count)
        else { throw TSVInputError("Range or name count exceeds the ULT2 format limit") }

        var data = Data()
        data.append(contentsOf: "ULT2".utf8)
        data.append(UltraCompactFormat.currentFormatVersion)  // 1B format version
        data.append(metadata == nil ? 0 : UltraCompactFormat.metadataFlag)
        data.append(uint32LE(v4Count))
        data.append(uint32LE(v6Count))
        data.append(uint32LE(nameCount))

        for r in v4Ranges {
            data.append(uint32BE(r.start))
            data.append(encodeVarint(r.end - r.start))
            data.append(encodeVarint(r.asn))
        }

        for r in v6Ranges {
            data.append(uint64BE(r.start.hi))
            data.append(uint64BE(r.start.lo))
            data.append(uint64BE(r.end.hi))
            data.append(uint64BE(r.end.lo))
            data.append(encodeVarint(r.asn))
        }

        for (asn, name) in asnNames.sorted(by: { $0.key < $1.key }) {
            data.append(encodeVarint(asn))
            let nd = name.data(using: .utf8) ?? Data()
            data.append(encodeVarint(UInt32(nd.count)))
            data.append(nd)
        }

        if let metadata {
            try appendMetadata(metadata, to: &data)
        }

        let compressed = try zlibCompress(data)
        let limit = try UltraCompactFormat.decodedSizeLimit(compressedBytes: compressed.count)
        guard data.count <= limit else {
            throw TSVInputError("Encoded database exceeds the reader's decoded size limit of \(limit) bytes")
        }
        try compressed.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        return counts
    }

    // MARK: helpers

    private struct RangeRecord<Address> {
        let start: Address
        let end: Address
        let asn: UInt32
        let line: Int
    }

    private static func readRanges<Address>(
        path: String?, family: String, parse: (String) -> Address?, less: (Address, Address) -> Bool,
        names: inout [UInt32: String], counts: inout RowCounts
    ) throws -> [RangeRecord<Address>] {
        guard let path else { return [] }
        var ranges: [RangeRecord<Address>] = []
        try forEachTSVLine(path: path) { line, number in
            counts.total += 1
            if line.isEmpty {
                counts.blank += 1
                return
            }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 5 else { throw TSVInputError("\(path):\(number): expected five TSV columns") }
            guard let start = parse(String(fields[0])), let end = parse(String(fields[1])) else {
                throw TSVInputError("\(path):\(number): invalid \(family) range endpoint")
            }
            guard !less(end, start) else {
                throw TSVInputError("\(path):\(number): \(family) range ends before it starts")
            }
            let digits = fields[2].hasPrefix("AS") ? fields[2].dropFirst(2) : fields[2]
            guard digits.utf8.allSatisfy({ (48...57).contains($0) }), let asn = UInt32(digits) else {
                throw TSVInputError("\(path):\(number): invalid ASN")
            }
            if asn == 0 {
                counts.unrouted += 1
                return
            }
            ranges.append(RangeRecord(start: start, end: end, asn: asn, line: number))
            if names[asn] == nil { names[asn] = String(fields[4]) }
        }

        ranges.sort { less($0.start, $1.start) }
        for (previous, next) in zip(ranges, ranges.dropFirst()) where !less(previous.end, next.start) {
            throw TSVInputError("\(path):\(next.line): \(family) range overlaps line \(previous.line)")
        }
        return ranges
    }

    private static func uint32LE(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func uint32BE(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
    private static func uint64BE(_ v: UInt64) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
    private static func uint64LE(_ v: UInt64) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private static func appendMetadata(_ metadata: UltraCompactBuildMetadata, to data: inout Data) throws {
        let timestamp = metadata.generationTimestamp.timeIntervalSince1970
        guard timestamp.isFinite, timestamp >= 0, timestamp < Double(UInt64.max) else {
            throw UltraCompactBuilderError.invalidGenerationTimestamp
        }
        guard !metadata.sourceIdentifier.isEmpty else {
            throw UltraCompactBuilderError.emptySourceIdentifier
        }
        let sourceData = Data(metadata.sourceIdentifier.utf8)
        guard let sourceLength = UInt32(exactly: sourceData.count) else {
            throw UltraCompactBuilderError.sourceIdentifierTooLong
        }

        data.append(UltraCompactFormat.metadataTrailerMagic)
        data.append(uint64LE(UInt64(timestamp.rounded(.towardZero))))
        data.append(encodeVarint(sourceLength))
        data.append(sourceData)
        data.append(UltraCompactFormat.buildIdentifierDigest(for: data))
    }

    private static func encodeVarint(_ value: UInt32) -> Data {
        var v = value
        var out = Data()
        while v >= 0x80 {
            out.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    private static func zlibCompress(_ data: Data) throws -> Data {
        // Allow headroom; zlib output can occasionally exceed input for small/random data.
        let capacity = max(data.count + 64, data.count * 2)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { dst.deallocate() }
        let written = data.withUnsafeBytes { src -> Int in
            compression_encode_buffer(
                dst, capacity,
                src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                nil, COMPRESSION_ZLIB
            )
        }
        if written <= 0 { throw NSError(domain: "compress", code: -1) }
        return Data(bytes: dst, count: written)
    }
}
