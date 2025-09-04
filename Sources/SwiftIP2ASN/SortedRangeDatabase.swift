import Foundation
import Network

/// A sorted array-based database for IP to ASN lookups
/// Handles overlapping and arbitrary-sized ranges efficiently
public actor SortedRangeDatabase {

    /// Represents an IP range with its ASN mapping
    struct IPRangeEntry: Comparable {
        let startIP: UInt32  // For IPv4, stored as UInt32
        let endIP: UInt32
        let asn: UInt32
        let name: String?

        static func < (lhs: IPRangeEntry, rhs: IPRangeEntry) -> Bool {
            // Sort by start IP, then by end IP for overlapping ranges
            if lhs.startIP != rhs.startIP {
                return lhs.startIP < rhs.startIP
            }
            return lhs.endIP < rhs.endIP
        }

        func contains(_ ip: UInt32) -> Bool {
            return ip >= startIP && ip <= endIP
        }
    }

    /// Sorted array of IP ranges
    private var ipv4Ranges: [IPRangeEntry] = []

    /// Statistics
    private var overlappingRanges = 0
    private var nonPowerOf2Ranges = 0

    public init() {}

    /// Build database from BGP data entries
    public func buildFromBGPData(_ entries: [(startIP: String, endIP: String, asn: UInt32, name: String?)]) async {
        var ranges: [IPRangeEntry] = []

        for entry in entries {
            guard let start = ipStringToUInt32(entry.startIP),
                let end = ipStringToUInt32(entry.endIP)
            else {
                continue
            }

            // Check if range size is power of 2
            let rangeSize = end - start + 1
            if !isPowerOfTwo(rangeSize) {
                nonPowerOf2Ranges += 1
            }

            ranges.append(
                IPRangeEntry(
                    startIP: start,
                    endIP: end,
                    asn: entry.asn,
                    name: entry.name
                ))
        }

        // Sort ranges by start IP, then end IP
        ranges.sort()

        // Count overlaps
        for i in 0..<ranges.count - 1 {
            if ranges[i].endIP >= ranges[i + 1].startIP {
                overlappingRanges += 1
            }
        }

        ipv4Ranges = ranges

        print("📊 Database built with \(ranges.count) ranges")
        print("   Overlapping ranges: \(overlappingRanges)")
        print("   Non-power-of-2 ranges: \(nonPowerOf2Ranges)")
    }

    /// Lookup ASN for an IP address using binary search
    public func lookup(_ ipString: String) -> (asn: UInt32, name: String?)? {
        guard let ip = ipStringToUInt32(ipString) else {
            return nil
        }

        // Binary search to find all potential ranges
        // First, find the last range with startIP <= ip
        var left = 0
        var right = ipv4Ranges.count - 1
        var foundIndex = -1

        while left <= right {
            let mid = (left + right) / 2

            if ipv4Ranges[mid].startIP <= ip {
                foundIndex = mid
                left = mid + 1
            } else {
                right = mid - 1
            }
        }

        // No range found
        if foundIndex == -1 {
            return nil
        }

        // Check backwards from foundIndex to find all overlapping ranges
        // that could contain this IP
        var candidates: [IPRangeEntry] = []

        // Start from foundIndex and go backwards while ranges could still contain IP
        var idx = foundIndex
        while idx >= 0 {
            if ipv4Ranges[idx].endIP < ip {
                // This range ends before our IP, so no need to check further back
                break
            }
            if ipv4Ranges[idx].contains(ip) {
                candidates.append(ipv4Ranges[idx])
            }
            idx -= 1
        }

        // Also check forward from foundIndex+1 in case of overlaps
        idx = foundIndex + 1
        while idx < ipv4Ranges.count && ipv4Ranges[idx].startIP <= ip {
            if ipv4Ranges[idx].contains(ip) {
                candidates.append(ipv4Ranges[idx])
            }
            idx += 1
        }

        // If multiple candidates (overlapping ranges), prefer:
        // 1. Most specific (smallest range)
        // 2. If same size, use the first one
        if let bestMatch = candidates.min(by: {
            let size1 = $0.endIP - $0.startIP
            let size2 = $1.endIP - $1.startIP
            return size1 < size2
        }) {
            return (bestMatch.asn, bestMatch.name)
        }

        return nil
    }

    /// Get database statistics
    public func getStatistics() -> (totalRanges: Int, overlaps: Int, nonPowerOf2: Int) {
        return (ipv4Ranges.count, overlappingRanges, nonPowerOf2Ranges)
    }

    // MARK: - Helper functions

    private func ipStringToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    private func isPowerOfTwo(_ n: UInt32) -> Bool {
        return n != 0 && (n & (n - 1)) == 0
    }
}
