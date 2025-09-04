import Compression
import Foundation

/// Ultra-compact database format with compression
/// Uses bit-packing and delta encoding for maximum compression
public struct CompressedDatabaseFormat {

    /// Create a compressed database file
    public static func createCompressed(
        from tsvPath: String,
        to outputPath: String
    ) throws {
        print("📦 Creating compressed database...")

        // Read and parse TSV data
        let data = try String(contentsOfFile: tsvPath)
        var entries: [(start: UInt32, end: UInt32, asn: UInt32)] = []

        for line in data.split(separator: "\n") {
            let fields = line.split(separator: "\t").map { String($0) }
            guard fields.count >= 3,
                let start = ipStringToUInt32(fields[0]),
                let end = ipStringToUInt32(fields[1]),
                let asn = UInt32(fields[2])
            else { continue }

            entries.append((start, end, asn))
        }

        // Sort entries
        entries.sort { $0.start < $1.start }

        print("   Parsed \(entries.count) entries")

        // Create binary data with delta encoding
        var binaryData = Data()

        // Header: magic + version + count
        binaryData.append(contentsOf: "IP2A".utf8)  // 4 bytes magic
        binaryData.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian) { Data($0) })
        binaryData.append(contentsOf: withUnsafeBytes(of: UInt32(entries.count).littleEndian) { Data($0) })

        // Delta-encode the entries for better compression
        var prevStart: UInt32 = 0
        for entry in entries {
            // Store delta from previous start
            let deltaStart = entry.start - prevStart
            let rangeSize = entry.end - entry.start

            // Variable-length encoding for deltas
            binaryData.append(contentsOf: encodeVarint(deltaStart))
            binaryData.append(contentsOf: encodeVarint(rangeSize))
            binaryData.append(contentsOf: encodeVarint(entry.asn))

            prevStart = entry.start
        }

        print("   Uncompressed: \(binaryData.count) bytes")

        // Compress with zlib
        let compressed = try compress(data: binaryData)
        try compressed.write(to: URL(fileURLWithPath: outputPath))

        print("   Compressed: \(compressed.count) bytes (\(compressed.count / 1024)KB)")
        print("   Compression ratio: \(String(format: "%.1f", Double(binaryData.count) / Double(compressed.count)))x")
    }

    /// Load compressed database into memory
    public static func loadCompressed(from path: String) throws -> CompactDatabase {
        let compressedData = try Data(contentsOf: URL(fileURLWithPath: path))
        let decompressed = try decompress(data: compressedData)

        return try CompactDatabase(data: decompressed)
    }

    // MARK: - Variable-length integer encoding (like Protocol Buffers)

    private static func encodeVarint(_ value: UInt32) -> Data {
        var data = Data()
        var current = value

        while current >= 0x80 {
            data.append(UInt8((current & 0x7F) | 0x80))
            current >>= 7
        }
        data.append(UInt8(current))

        return data
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

    // MARK: - Compression helpers

    private static func compress(data: Data) throws -> Data {
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { destinationBuffer.deallocate() }

        let compressedSize = compression_encode_buffer(
            destinationBuffer, data.count,
            data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! },
            data.count,
            nil, COMPRESSION_ZLIB
        )

        guard compressedSize > 0 else {
            throw CompressionError.compressionFailed
        }

        return Data(bytes: destinationBuffer, count: compressedSize)
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

    private static func ipStringToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
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
