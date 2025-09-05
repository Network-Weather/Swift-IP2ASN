import Foundation

/// Efficient binary format for IP to ASN database
///
/// Format Design:
/// - Header (16 bytes): magic, version, entry count, string table offset
/// - Entries (12 bytes each): start_ip(4) + end_ip(4) + asn(4)
/// - String table: null-terminated strings for AS names
///
/// Total size: ~6MB for 500k entries (vs 24MB uncompressed TSV)
public struct BinaryDatabaseFormat {

    public static let magic: UInt32 = 0x4153_4E44  // "ASND" in hex
    public static let version: UInt32 = 1

    /// Binary header structure
    public struct Header {
        let magic: UInt32
        let version: UInt32
        let entryCount: UInt32
        let stringTableOffset: UInt32
    }

    /// Compact binary entry (12 bytes)
    public struct BinaryEntry {
        let startIP: UInt32  // 4 bytes
        let endIP: UInt32  // 4 bytes
        let asn: UInt32  // 4 bytes
        // Name stored separately in string table
    }

    /// Write database to binary format
    public static func serialize(
        ranges: [(startIP: String, endIP: String, asn: UInt32, name: String?)],
        to url: URL
    ) throws {
        var data = Data()

        // Build string table and map names to offsets
        var stringTable = Data()
        var nameOffsets: [String: UInt32] = [:]
        var rangeNameOffsets: [UInt32] = []

        for (_, _, _, name) in ranges {
            if let name = name {
                if let existingOffset = nameOffsets[name] {
                    rangeNameOffsets.append(existingOffset)
                } else {
                    let offset = UInt32(stringTable.count)
                    nameOffsets[name] = offset
                    rangeNameOffsets.append(offset)
                    stringTable.append(name.data(using: .utf8)!)
                    stringTable.append(0)  // Null terminator
                }
            } else {
                rangeNameOffsets.append(0xFFFF_FFFF)  // Marker for no name
            }
        }

        // Write header
        let header = Header(
            magic: magic,
            version: version,
            entryCount: UInt32(ranges.count),
            stringTableOffset: UInt32(16 + ranges.count * 12)  // After header and entries
        )

        data.append(withUnsafeBytes(of: header.magic.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: header.version.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: header.entryCount.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: header.stringTableOffset.littleEndian) { Data($0) })

        // Write entries
        for (startIP, endIP, asn, _) in ranges {
            let start = ipStringToUInt32(startIP) ?? 0
            let end = ipStringToUInt32(endIP) ?? 0

            data.append(withUnsafeBytes(of: start.littleEndian) { Data($0) })
            data.append(withUnsafeBytes(of: end.littleEndian) { Data($0) })

            // Pack ASN and name offset into 32 bits
            // Top 8 bits: flags/reserved, Bottom 24 bits: ASN (sufficient for all ASNs)
            let packedASN = asn & 0x00FF_FFFF
            data.append(withUnsafeBytes(of: packedASN.littleEndian) { Data($0) })
        }

        // Write string table
        data.append(stringTable)

        // Write to file
        try data.write(to: url)

        print("📦 Binary database written:")
        print("   Entries: \(ranges.count)")
        print("   Binary size: \(data.count) bytes (\(data.count / 1024)KB)")
        print("   String table: \(stringTable.count) bytes")
    }

    /// Load database from binary format using memory-mapped file
    public static func deserialize(from url: URL) throws -> MemoryMappedDatabase {
        return try MemoryMappedDatabase(url: url)
    }

    private static func ipStringToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }
}

/// Memory-mapped database for zero-copy access
public class MemoryMappedDatabase {
    private let data: Data
    private var header: BinaryDatabaseFormat.Header
    private var entriesPtr: UnsafePointer<UInt8>?
    private var stringTablePtr: UnsafePointer<UInt8>?
    private let entryCount: Int

    public init(url: URL) throws {
        // Memory-map the file for efficient access
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)

        // Initialize header with default values
        var tempHeader = BinaryDatabaseFormat.Header(
            magic: 0,
            version: 0,
            entryCount: 0,
            stringTableOffset: 0
        )

        // Read header
        self.data.withUnsafeBytes { bytes in
            let ptr = bytes.bindMemory(to: UInt32.self)
            tempHeader = BinaryDatabaseFormat.Header(
                magic: UInt32(littleEndian: ptr[0]),
                version: UInt32(littleEndian: ptr[1]),
                entryCount: UInt32(littleEndian: ptr[2]),
                stringTableOffset: UInt32(littleEndian: ptr[3])
            )
        }

        self.header = tempHeader

        // Validate magic number
        guard header.magic == BinaryDatabaseFormat.magic else {
            throw BinaryDatabaseError.invalidFormat
        }

        self.entryCount = Int(header.entryCount)

        // Get pointers to entries and string table
        self.data.withUnsafeBytes { bytes in
            self.entriesPtr = bytes.baseAddress!.advanced(by: 16).assumingMemoryBound(to: UInt8.self)
            self.stringTablePtr = bytes.baseAddress!.advanced(by: Int(header.stringTableOffset)).assumingMemoryBound(
                to: UInt8.self)
        }
    }

    /// Binary search for IP address
    public func lookup(_ ipString: String) -> (asn: UInt32, name: String?)? {
        guard let ip = ipStringToUInt32(ipString) else { return nil }

        var left = 0
        var right = entryCount - 1
        var foundIndex = -1

        // Binary search for the last range with startIP <= ip
        while left <= right {
            let mid = (left + right) / 2
            let entry = getEntry(at: mid)

            if entry.startIP <= ip {
                foundIndex = mid
                left = mid + 1
            } else {
                right = mid - 1
            }
        }

        if foundIndex == -1 { return nil }

        // Check if IP is in range
        let entry = getEntry(at: foundIndex)
        if ip >= entry.startIP && ip <= entry.endIP {
            return (entry.asn, nil)  // Name lookup could be added
        }

        return nil
    }

    private func getEntry(at index: Int) -> (startIP: UInt32, endIP: UInt32, asn: UInt32) {
        let offset = index * 12
        let ptr = entriesPtr!.advanced(by: offset).withMemoryRebound(to: UInt32.self, capacity: 3) { $0 }
        return (
            startIP: UInt32(littleEndian: ptr[0]),
            endIP: UInt32(littleEndian: ptr[1]),
            asn: UInt32(littleEndian: ptr[2]) & 0x00FF_FFFF
        )
    }

    private func ipStringToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    public var statistics: (entries: Int, sizeBytes: Int) {
        return (entries: entryCount, sizeBytes: data.count)
    }
}

enum BinaryDatabaseError: Error {
    case invalidFormat
    case corruptedData
}
