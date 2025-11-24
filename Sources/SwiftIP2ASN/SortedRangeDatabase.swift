import Foundation

// MARK: - SortedRangeDatabase

/// High-performance sorted array database for IP to ASN lookups.
///
/// Uses binary search with O(log n) lookup time. Handles overlapping
/// ranges by preferring the most specific (smallest) match.
///
/// Thread Safety:
/// - Build phase: Call `buildFromBGPData()` once.
/// - Lookup phase: After building, `lookup()` is actor-isolated and safe.
public actor SortedRangeDatabase {

    // MARK: - Types

    /// Compact IP range entry (16 bytes).
    private struct IPRangeEntry: Comparable {
        let startIP: UInt32
        let endIP: UInt32
        let asn: UInt32
        let nameIndex: Int32  // Index into names array, -1 if no name

        @inlinable
        static func < (lhs: IPRangeEntry, rhs: IPRangeEntry) -> Bool {
            if lhs.startIP != rhs.startIP {
                return lhs.startIP < rhs.startIP
            }
            return lhs.endIP < rhs.endIP
        }

        @inlinable
        func contains(_ ip: UInt32) -> Bool {
            ip >= startIP && ip <= endIP
        }

        @inlinable
        var rangeSize: UInt32 {
            endIP - startIP
        }
    }

    // MARK: - Properties

    /// Sorted array of IP ranges for binary search.
    private var ranges: [IPRangeEntry] = []

    /// Deduplicated name storage.
    private var names: [String] = []

    /// Statistics.
    private var overlappingRanges = 0
    private var nonPowerOf2Ranges = 0

    public init() {}

    // MARK: - Build Phase

    /// Build database from BGP data entries.
    public func buildFromBGPData(
        _ entries: [(startIP: String, endIP: String, asn: UInt32, name: String?)]
    ) {
        // Build name index for deduplication
        var nameToIndex: [String: Int32] = [:]
        var tempRanges: [IPRangeEntry] = []
        tempRanges.reserveCapacity(entries.count)

        for entry in entries {
            guard let start = parseIPv4ToUInt32(entry.startIP),
                let end = parseIPv4ToUInt32(entry.endIP)
            else {
                continue
            }

            // Track non-power-of-2 ranges
            let rangeSize = end - start + 1
            if !rangeSize.isPowerOfTwo {
                nonPowerOf2Ranges += 1
            }

            // Deduplicate names
            let nameIndex: Int32
            if let name = entry.name {
                if let existingIndex = nameToIndex[name] {
                    nameIndex = existingIndex
                } else {
                    nameIndex = Int32(names.count)
                    names.append(name)
                    nameToIndex[name] = nameIndex
                }
            } else {
                nameIndex = -1
            }

            tempRanges.append(
                IPRangeEntry(
                    startIP: start,
                    endIP: end,
                    asn: entry.asn,
                    nameIndex: nameIndex
                ))
        }

        // Sort by start IP, then end IP
        tempRanges.sort()

        // Count overlaps
        for i in 0..<(tempRanges.count - 1) {
            if tempRanges[i].endIP >= tempRanges[i + 1].startIP {
                overlappingRanges += 1
            }
        }

        ranges = tempRanges
    }

    // MARK: - Lookup Phase

    /// Look up ASN for an IPv4 address string.
    public func lookup(_ ipString: String) -> (asn: UInt32, name: String?)? {
        guard let ip = parseIPv4ToUInt32(ipString) else {
            return nil
        }
        return lookup(ip: ip)
    }

    /// Look up ASN for an IPv4 address as UInt32.
    /// Returns the most specific (smallest) matching range.
    public func lookup(ip: UInt32) -> (asn: UInt32, name: String?)? {
        guard !ranges.isEmpty else { return nil }

        // Binary search to find the last range with startIP <= ip
        var left = 0
        var right = ranges.count - 1
        var foundIndex = -1

        while left <= right {
            let mid = (left + right) >> 1

            if ranges[mid].startIP <= ip {
                foundIndex = mid
                left = mid + 1
            } else {
                right = mid - 1
            }
        }

        guard foundIndex >= 0 else { return nil }

        // Find best (most specific) match among candidates
        var bestMatch: IPRangeEntry?
        var bestSize: UInt32 = .max

        // Check backwards from foundIndex
        var idx = foundIndex
        while idx >= 0 && ranges[idx].startIP <= ip {
            let range = ranges[idx]
            if range.contains(ip) && range.rangeSize < bestSize {
                bestMatch = range
                bestSize = range.rangeSize
            }
            // Early exit: if we've gone past ranges that could contain ip
            if range.endIP < ip && idx < foundIndex {
                break
            }
            idx -= 1
        }

        // Check forwards from foundIndex+1 for overlapping ranges
        idx = foundIndex + 1
        while idx < ranges.count && ranges[idx].startIP <= ip {
            let range = ranges[idx]
            if range.contains(ip) && range.rangeSize < bestSize {
                bestMatch = range
                bestSize = range.rangeSize
            }
            idx += 1
        }

        guard let match = bestMatch else { return nil }

        let name: String? = match.nameIndex >= 0 ? names[Int(match.nameIndex)] : nil
        return (match.asn, name)
    }

    // MARK: - Statistics

    public func getStatistics() -> (totalRanges: Int, overlaps: Int, nonPowerOf2: Int, uniqueNames: Int) {
        return (ranges.count, overlappingRanges, nonPowerOf2Ranges, names.count)
    }
}

// MARK: - UInt32 Extension

extension UInt32 {
    @inlinable
    var isPowerOfTwo: Bool {
        self != 0 && (self & (self - 1)) == 0
    }
}
