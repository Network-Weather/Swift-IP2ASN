import Compression
import Foundation

/// Builder for the compressed delta-encoded database format written by tools.
public enum CompressedDatabaseBuilder {
    /// Create a compressed database file from TSV (startIP\tendIP\tasn...)
    public static func createCompressed(from tsvPath: String, to outputPath: String) throws {
        print("📦 Creating compressed database...")

        let text = try String(contentsOfFile: tsvPath)
        var entries: [(start: UInt32, end: UInt32, asn: UInt32)] = []

        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t").map { String($0) }
            guard fields.count >= 3,
                let start = ipStringToUInt32(fields[0]),
                let end = ipStringToUInt32(fields[1]),
                let asn = UInt32(fields[2])
            else { continue }
            entries.append((start, end, asn))
        }

        entries.sort { $0.start < $1.start }
        print("   Parsed \(entries.count) entries")

        var binary = Data()
        binary.append(contentsOf: "IP2A".utf8)
        binary.append(uint32LE(1))
        binary.append(uint32LE(UInt32(entries.count)))

        var prevStart: UInt32 = 0
        for e in entries {
            let deltaStart = e.start &- prevStart
            let rangeSize = e.end &- e.start
            binary.append(encodeVarint(deltaStart))
            binary.append(encodeVarint(rangeSize))
            binary.append(encodeVarint(e.asn))
            prevStart = e.start
        }

        print("   Uncompressed: \(binary.count) bytes")
        let compressed = try zlibCompress(binary)
        try compressed.write(to: URL(fileURLWithPath: outputPath))
        print("   Compressed: \(compressed.count) bytes (")
    }

    // MARK: helpers
    private static func ipStringToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    private static func uint32LE(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

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
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { dst.deallocate() }
        let written = data.withUnsafeBytes { src -> Int in
            compression_encode_buffer(
                dst, data.count,
                src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                nil, COMPRESSION_ZLIB
            )
        }
        if written <= 0 { throw NSError(domain: "compress", code: -1) }
        return Data(bytes: dst, count: written)
    }
}
