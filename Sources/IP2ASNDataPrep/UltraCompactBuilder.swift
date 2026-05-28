import Compression
import Foundation
import SwiftIP2ASN

public enum UltraCompactBuilder {

    /// Build an ultra-compact (V2) database from an IPv4 TSV. The output contains zero IPv6 ranges.
    public static func createUltraCompact(from tsvPath: String, to outputPath: String) throws {
        try createUltraCompact(ipv4TSV: tsvPath, ipv6TSV: nil, to: outputPath)
    }

    /// Build an ultra-compact (V2) dual-stack database from one or both iptoasn TSVs.
    ///
    /// - Parameters:
    ///   - ipv4TSV: Path to `ip2asn-v4.tsv`. Optional; pass nil to build IPv6-only.
    ///   - ipv6TSV: Path to `ip2asn-v6.tsv`. Optional; pass nil to build IPv4-only.
    ///   - outputPath: Where to write the zlib-compressed `.ultra` file.
    public static func createUltraCompact(ipv4TSV: String?, ipv6TSV: String?, to outputPath: String) throws {
        precondition(ipv4TSV != nil || ipv6TSV != nil, "Need at least one TSV input")

        var v4Ranges: [(start: UInt32, end: UInt32, asn: UInt32)] = []
        var v6Ranges: [(startHi: UInt64, startLo: UInt64, endHi: UInt64, endLo: UInt64, asn: UInt32)] = []
        var asnNames: [UInt32: String] = [:]

        if let v4Path = ipv4TSV {
            let lines = try String(contentsOfFile: v4Path).split(separator: "\n")
            for line in lines {
                let f = line.split(separator: "\t").map(String.init)
                guard f.count >= 5,
                    let s = ipv4ToUInt32(f[0]),
                    let e = ipv4ToUInt32(f[1])
                else { continue }
                let asnString = f[2].replacingOccurrences(of: "AS", with: "")
                guard let a = UInt32(asnString), a != 0 else { continue }
                v4Ranges.append((s, e, a))
                if asnNames[a] == nil { asnNames[a] = f[4] }
            }
            v4Ranges.sort { $0.start < $1.start }
        }

        if let v6Path = ipv6TSV {
            let lines = try String(contentsOfFile: v6Path).split(separator: "\n")
            for line in lines {
                let f = line.split(separator: "\t").map(String.init)
                guard f.count >= 5,
                    let s = parseIPv6ToPair(f[0]),
                    let e = parseIPv6ToPair(f[1])
                else { continue }
                let asnString = f[2].replacingOccurrences(of: "AS", with: "")
                guard let a = UInt32(asnString), a != 0 else { continue }
                v6Ranges.append((s.hi, s.lo, e.hi, e.lo, a))
                if asnNames[a] == nil { asnNames[a] = f[4] }
            }
            v6Ranges.sort {
                if $0.startHi != $1.startHi { return $0.startHi < $1.startHi }
                return $0.startLo < $1.startLo
            }
        }

        var data = Data()
        data.append(contentsOf: "ULT2".utf8)
        data.append(UltraCompactFormat.currentFormatVersion)  // 1B format version
        data.append(0)                                         // 1B flags (reserved)
        data.append(uint32LE(UInt32(v4Ranges.count)))
        data.append(uint32LE(UInt32(v6Ranges.count)))
        data.append(uint32LE(UInt32(asnNames.count)))

        for r in v4Ranges {
            data.append(uint32BE(r.start))
            data.append(encodeVarint(r.end &- r.start))
            data.append(encodeVarint(r.asn))
        }

        for r in v6Ranges {
            data.append(uint64BE(r.startHi))
            data.append(uint64BE(r.startLo))
            data.append(uint64BE(r.endHi))
            data.append(uint64BE(r.endLo))
            data.append(encodeVarint(r.asn))
        }

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

    private static func ipv4ToUInt32(_ ip: String) -> UInt32? {
        let p = ip.split(separator: ".").compactMap { UInt32($0) }
        guard p.count == 4 else { return nil }
        return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]
    }

    private static func uint32LE(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func uint32BE(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
    private static func uint64BE(_ v: UInt64) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }

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
