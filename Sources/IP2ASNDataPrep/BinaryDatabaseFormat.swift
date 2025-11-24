import Foundation
import SwiftIP2ASN

// MARK: - BinaryDatabaseFormat

/// Efficient binary format for IP to ASN database.
///
/// Format Design:
/// - Header (16 bytes): magic, version, entry count, string table offset
/// - Entries (12 bytes each): start_ip(4) + end_ip(4) + asn(4)
/// - String table: null-terminated strings for AS names
///
/// Total size: ~6MB for 500k entries (vs 24MB uncompressed TSV)
public enum BinaryDatabaseFormat {

    public static let magic: UInt32 = 0x4153_4E44  // "ASND" in hex
    public static let version: UInt32 = 1

    /// Binary header structure.
    public struct Header {
        let magic: UInt32
        let version: UInt32
        let entryCount: UInt32
        let stringTableOffset: UInt32
    }

    /// Write database to binary format.
    public static func serialize(
        ranges: [(startIP: String, endIP: String, asn: UInt32, name: String?)],
        to url: URL
    ) throws {
        var data = Data()

        // Build string table and map names to offsets
        var stringTable = Data()
        var nameOffsets: [String: UInt32] = [:]

        for (_, _, _, name) in ranges {
            if let name = name, nameOffsets[name] == nil {
                let offset = UInt32(stringTable.count)
                nameOffsets[name] = offset
                stringTable.append(Data(name.utf8))
                stringTable.append(0)  // Null terminator
            }
        }

        // Write header
        data.append(contentsOf: withUnsafeBytes(of: magic.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: version.littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(ranges.count).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16 + ranges.count * 12).littleEndian) { Data($0) })

        // Write entries
        for (startIP, endIP, asn, _) in ranges {
            let start = parseIPv4ToUInt32(startIP) ?? 0
            let end = parseIPv4ToUInt32(endIP) ?? 0

            data.append(contentsOf: withUnsafeBytes(of: start.littleEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: end.littleEndian) { Data($0) })
            data.append(contentsOf: withUnsafeBytes(of: (asn & 0x00FF_FFFF).littleEndian) { Data($0) })
        }

        // Write string table
        data.append(stringTable)

        // Write to file
        try data.write(to: url)
    }

    /// Load database from binary format.
    public static func deserialize(from url: URL) throws -> BinaryDatabase {
        return try BinaryDatabase(url: url)
    }
}

// MARK: - BinaryDatabase

/// Thread-safe, immutable database loaded from binary format.
///
/// Uses contiguous arrays for cache-efficient binary search.
/// All data is immutable after initialization.
public struct BinaryDatabase: Sendable {
    private let startIPs: [UInt32]
    private let endIPs: [UInt32]
    private let asns: [UInt32]

    public var entryCount: Int { startIPs.count }

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)

        guard data.count >= 16 else {
            throw BinaryDatabaseError.invalidFormat
        }

        // Read header
        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).littleEndian }
        guard magic == BinaryDatabaseFormat.magic else {
            throw BinaryDatabaseError.invalidFormat
        }

        let count = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self).littleEndian }

        // Pre-allocate arrays
        var startIPs: [UInt32] = []
        var endIPs: [UInt32] = []
        var asns: [UInt32] = []
        startIPs.reserveCapacity(Int(count))
        endIPs.reserveCapacity(Int(count))
        asns.reserveCapacity(Int(count))

        // Read entries
        var offset = 16
        for _ in 0..<count {
            guard offset + 12 <= data.count else {
                throw BinaryDatabaseError.corruptedData
            }

            let start = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian }
            let end = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 4, as: UInt32.self).littleEndian }
            let asn =
                data.withUnsafeBytes { $0.load(fromByteOffset: offset + 8, as: UInt32.self).littleEndian } & 0x00FF_FFFF

            startIPs.append(start)
            endIPs.append(end)
            asns.append(asn)
            offset += 12
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

    public var statistics: (entries: Int, memoryBytes: Int) {
        let arrayBytes = (startIPs.count + endIPs.count + asns.count) * MemoryLayout<UInt32>.size
        return (entries: entryCount, memoryBytes: arrayBytes)
    }
}

// MARK: - Legacy Alias

/// Compatibility alias for MemoryMappedDatabase.
public typealias MemoryMappedDatabase = BinaryDatabase

// MARK: - Error

public enum BinaryDatabaseError: Error, Sendable {
    case invalidFormat
    case corruptedData
}
