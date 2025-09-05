import Compression
import Foundation

public enum UltraCompactBuilder {
    /// Build ultra-compact database from TSV (startIP\tendIP\tasn\tcountry\torg)
    public static func createUltraCompact(from tsvPath: String, to outputPath: String) throws {
        let lines = try String(contentsOfFile: tsvPath).split(separator: "\n")
        var ranges: [(start: UInt32, end: UInt32, asn: UInt32)] = []
        var asnNames: [UInt32: String] = [:]

        for line in lines {
            let f = line.split(separator: "\t").map(String.init)
            guard f.count >= 5,
                  let s = ipToUInt32(f[0]),
                  let e = ipToUInt32(f[1]) else { continue }
            // ASN can be either numeric or prefixed as "AS12345"; normalize
            let asnString = f[2].replacingOccurrences(of: "AS", with: "")
            guard let a = UInt32(asnString) else { continue }
            ranges.append((s, e, a))
            if asnNames[a] == nil { asnNames[a] = f[4] }
        }

        ranges.sort { $0.start < $1.start }

        var data = Data()
        data.append(contentsOf: "ULTR".utf8)
        data.append(uint32LE(UInt32(ranges.count)))
        data.append(uint32LE(UInt32(asnNames.count)))

        for r in ranges {
            // Write absolute start (big-endian)
            data.append(uint32BE(r.start))
            // Write size and ASN as varints
            let size = r.end &- r.start
            data.append(encodeVarint(size))
            data.append(encodeVarint(r.asn))
        }

        // ASN table (count + entries)
        data.append(uint32LE(UInt32(asnNames.count)))
        for (asn, name) in asnNames.sorted(by: { $0.key < $1.key }) {
            data.append(encodeVarint(asn))
            let nd = name.data(using: .utf8) ?? Data()
            data.append(encodeVarint(UInt32(nd.count)))
            data.append(nd)
        }

        let compressed = try zlibCompress(data)
        try compressed.write(to: URL(fileURLWithPath: outputPath))
    }

    // MARK: helpers
    private static func ipToUInt32(_ ip: String) -> UInt32? {
        let p = ip.split(separator: ".").compactMap { UInt32($0) }
        guard p.count == 4 else { return nil }
        return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]
    }
    private static func uint32LE(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func uint32BE(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
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
