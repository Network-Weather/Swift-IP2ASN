import Compression
import Foundation

// MARK: - OptimizedDatabaseFormat

/// Optimized database format with normalized ASN names.
///
/// File Format:
/// - Header: 16 bytes
///   - magic: "ASN2" (4 bytes BE)
///   - version: 2 (2 bytes BE)
///   - flags: compression flags (2 bytes BE)
///   - rangeCount: number of ranges (4 bytes BE)
///   - asnTableOffset: offset to ASN name table (4 bytes BE)
/// - Ranges: 12 bytes each
///   - startIP (4 bytes BE)
///   - endIP (4 bytes BE)
///   - asn (4 bytes BE)
/// - ASN Table:
///   - count (4 bytes BE)
///   - entries: asn (4 bytes BE) + nameLen (2 bytes BE) + name bytes
///
/// Compression: Optional ZLIB
public enum OptimizedDatabaseFormat {

    public static let magic: UInt32 = 0x4153_4E32  // "ASN2"
    public static let version: UInt16 = 2

    /// Header structure (16 bytes).
    public struct Header {
        let magic: UInt32
        let version: UInt16
        let flags: UInt16
        let rangeCount: UInt32
        let asnTableOffset: UInt32
    }

    // MARK: - Compression

    static func compressData(_ data: Data) throws -> Data {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { buffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { srcBuffer -> Int in
            compression_encode_buffer(
                buffer, data.count,
                srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                data.count,
                nil, COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else {
            throw OptimizedFormatError.compressionFailed
        }

        return Data(bytes: buffer, count: compressedSize)
    }

    static func decompressData(_ data: Data) throws -> Data {
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

        throw OptimizedFormatError.decompressionFailed
    }

    // MARK: - Builder

    /// Create optimized database file from TSV.
    public static func createOptimized(
        from tsvPath: String,
        to outputPath: String,
        compress: Bool = true
    ) throws {
        // Parse TSV and build unique ASN table
        let content = try String(contentsOfFile: tsvPath, encoding: .utf8)
        let lines = content.split(separator: "\n")

        var ranges: [(start: UInt32, end: UInt32, asn: UInt32)] = []
        var asnNames: [UInt32: String] = [:]

        for line in lines {
            let fields = line.split(separator: "\t")
            guard fields.count >= 5,
                let start = parseIPv4ToUInt32(String(fields[0])),
                let end = parseIPv4ToUInt32(String(fields[1])),
                let asn = UInt32(fields[2])
            else { continue }

            ranges.append((start, end, asn))

            if asn > 0 && asnNames[asn] == nil {
                asnNames[asn] = String(fields[4])
            }
        }

        ranges.sort { $0.start < $1.start }

        var data = Data()

        // Write header
        data.append(contentsOf: withUnsafeBytes(of: magic.bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: version.bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(compress ? 1 : 0).bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(ranges.count).bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16 + ranges.count * 12).bigEndian) { Data($0) })

        // Write ranges (12 bytes each)
        for range in ranges {
            data.append(contentsOf: withUnsafeBytes(of: range.start.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: range.end.bigEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: range.asn.bigEndian) { Data($0) })
        }

        // Write ASN name table
        data.append(contentsOf: withUnsafeBytes(of: UInt32(asnNames.count).bigEndian) { Data($0) })

        for (asn, name) in asnNames.sorted(by: { $0.key < $1.key }) {
            data.append(contentsOf: withUnsafeBytes(of: asn.bigEndian) { Data($0) })
            let nameData = Data(name.utf8)
            data.append(contentsOf: withUnsafeBytes(of: UInt16(nameData.count).bigEndian) { Data($0) })
            data.append(nameData)
        }

        // Optionally compress and save
        if compress {
            let compressed = try compressData(data)
            try compressed.write(to: URL(fileURLWithPath: outputPath))
        } else {
            try data.write(to: URL(fileURLWithPath: outputPath))
        }
    }
}

// MARK: - OptimizedDatabase

/// Thread-safe, immutable database loaded from optimized format.
///
/// After initialization, all data is immutable and lookups are safe
/// to call from any thread without synchronization.
public struct OptimizedDatabase: Sendable {
    /// Stored as contiguous arrays for cache efficiency.
    private let startIPs: [UInt32]
    private let endIPs: [UInt32]
    private let asns: [UInt32]
    private let asnNames: [UInt32: String]

    public var rangeCount: Int { startIPs.count }
    public var uniqueASNCount: Int { asnNames.count }

    public init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let fileData = try Data(contentsOf: url)

        // Check if compressed
        let magic = fileData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 0, as: UInt32.self).bigEndian
        }

        let data: Data
        if magic == OptimizedDatabaseFormat.magic {
            data = fileData
        } else {
            data = try OptimizedDatabaseFormat.decompressData(fileData)
        }

        try self.init(data: data)
    }

    private init(data: Data) throws {
        guard data.count >= 16 else {
            throw OptimizedFormatError.invalidFormat
        }

        // Parse header
        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).bigEndian }
        guard magic == OptimizedDatabaseFormat.magic else {
            throw OptimizedFormatError.invalidFormat
        }

        let rangeCount = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self).bigEndian }
        let asnTableOffset = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self).bigEndian }

        // Pre-allocate arrays
        var startIPs: [UInt32] = []
        var endIPs: [UInt32] = []
        var asns: [UInt32] = []
        startIPs.reserveCapacity(Int(rangeCount))
        endIPs.reserveCapacity(Int(rangeCount))
        asns.reserveCapacity(Int(rangeCount))

        // Parse ranges
        var offset = 16
        for _ in 0..<rangeCount {
            let start = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).bigEndian }
            let end = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 4, as: UInt32.self).bigEndian }
            let asn = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 8, as: UInt32.self).bigEndian }

            startIPs.append(start)
            endIPs.append(end)
            asns.append(asn)
            offset += 12
        }

        // Parse ASN name table
        var asnNames: [UInt32: String] = [:]
        offset = Int(asnTableOffset)

        guard offset + 4 <= data.count else {
            throw OptimizedFormatError.invalidFormat
        }

        let asnCount = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).bigEndian }
        offset += 4
        asnNames.reserveCapacity(Int(asnCount))

        for _ in 0..<asnCount {
            guard offset + 6 <= data.count else {
                throw OptimizedFormatError.invalidFormat
            }

            let asn = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).bigEndian }
            let nameLen = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 4, as: UInt16.self).bigEndian }
            offset += 6

            guard offset + Int(nameLen) <= data.count else {
                throw OptimizedFormatError.invalidFormat
            }

            let nameData = data[offset..<offset + Int(nameLen)]
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

    /// Look up ASN for an IPv4 address string.
    public func lookup(_ ipString: String) -> (asn: UInt32, name: String?)? {
        guard let ip = parseIPv4ToUInt32(ipString) else { return nil }
        return lookup(ip: ip)
    }

    /// Look up ASN for an IPv4 address as UInt32.
    public func lookup(ip: UInt32) -> (asn: UInt32, name: String?)? {
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

    public var statistics: (ranges: Int, uniqueASNs: Int) {
        return (rangeCount, uniqueASNCount)
    }
}

// MARK: - OptimizedFormatError

public enum OptimizedFormatError: Error, Sendable {
    case invalidFormat
    case compressionFailed
    case decompressionFailed
}
