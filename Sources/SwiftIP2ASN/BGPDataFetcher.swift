import Foundation
import Network

public struct BGPDataFetcher: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches IP-to-ASN mapping data from IPtoASN.com service
    /// This provides daily updated BGP dumps with actual ASN assignments
    public func fetchIPv4Data() async throws -> String {
        let url = URL(string: "https://iptoasn.com/data/ip2asn-v4.tsv.gz")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw BGPError.downloadFailed
        }

        // Save to temp file and decompress using system gunzip
        let tempGzPath = "/tmp/ip2asn-v4-\(UUID().uuidString).tsv.gz"
        let tempTsvPath = "/tmp/ip2asn-v4-\(UUID().uuidString).tsv"

        try data.write(to: URL(fileURLWithPath: tempGzPath))

        // Use system gunzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", tempGzPath]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let decompressedData = pipe.fileHandleForReading.readDataToEndOfFile()

        // Clean up temp file
        try? FileManager.default.removeItem(atPath: tempGzPath)

        guard let content = String(data: decompressedData, encoding: .utf8) else {
            throw BGPError.invalidData
        }

        return content
    }

    public func fetchIPv6Data() async throws -> String {
        let url = URL(string: "https://iptoasn.com/data/ip2asn-v6.tsv.gz")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw BGPError.downloadFailed
        }

        // Save to temp file and decompress using system gunzip
        let tempGzPath = "/tmp/ip2asn-v6-\(UUID().uuidString).tsv.gz"

        try data.write(to: URL(fileURLWithPath: tempGzPath))

        // Use system gunzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", tempGzPath]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let decompressedData = pipe.fileHandleForReading.readDataToEndOfFile()

        // Clean up temp file
        try? FileManager.default.removeItem(atPath: tempGzPath)

        guard let content = String(data: decompressedData, encoding: .utf8) else {
            throw BGPError.invalidData
        }

        return content
    }

    /// Alternative: Use RouteViews data (more complex but authoritative)
    public func fetchRouteViewsData() async throws -> String {
        // RouteViews provides BGP dumps at:
        // http://archive.routeviews.org/bgpdata/
        // These need MRT format parsing which is complex

        // For simplicity, we can use processed data from:
        // https://thyme.apnic.net/current/data-raw-table
        let url = URL(string: "https://thyme.apnic.net/current/data-raw-table")!
        let (data, _) = try await session.data(from: url)

        guard let content = String(data: data, encoding: .utf8) else {
            throw BGPError.invalidData
        }

        return content
    }
}

public struct BGPDataParser: Sendable {

    /// Parses IPtoASN.com TSV format:
    /// Format: range_start\trange_end\tAS_number\tcountry_code\tAS_description
    public func parseIPtoASNData(_ data: String) -> [(range: IPRange, asn: UInt32, name: String)] {
        var results: [(range: IPRange, asn: UInt32, name: String)] = []

        let lines = data.split(separator: "\n")
        for line in lines {
            let fields = line.split(separator: "\t").map { String($0) }

            guard fields.count >= 5 else { continue }

            let startIP = fields[0]
            let endIP = fields[1]
            let asnString = fields[2]
            // let countryCode = fields[3]
            let asName = fields[4]

            // Parse ASN (remove "AS" prefix if present)
            let asnNumber = asnString.replacingOccurrences(of: "AS", with: "")
            guard let asn = UInt32(asnNumber), asn > 0 else { continue }

            // Convert IP range to CIDR
            guard let range = convertRangeToCIDR(start: startIP, end: endIP) else { continue }

            results.append((range: range, asn: asn, name: asName))
        }

        return results
    }

    /// Parses RouteViews/APNIC format:
    /// Format: prefix\tAS_path (we take the origin AS)
    public func parseRouteViewsData(_ data: String) -> [(range: IPRange, asn: UInt32)] {
        var results: [(range: IPRange, asn: UInt32)] = []

        let lines = data.split(separator: "\n")
        for line in lines {
            let fields = line.split(separator: "\t").map { String($0) }

            guard fields.count >= 2 else { continue }

            let prefix = fields[0]
            let asPath = fields[1]

            // Get origin AS (last AS in the path)
            let asNumbers = asPath.split(separator: " ")
            guard let lastAS = asNumbers.last,
                let asn = UInt32(lastAS)
            else { continue }

            // Parse CIDR prefix
            guard let range = IPRange(cidr: prefix) else { continue }

            results.append((range: range, asn: asn))
        }

        return results
    }

    private func convertRangeToCIDR(start: String, end: String) -> IPRange? {
        guard let startIP = IPAddress(string: start),
            let endIP = IPAddress(string: end)
        else { return nil }

        switch (startIP, endIP) {
        case (.v4(let startAddr), .v4(let endAddr)):
            // Convert IPv4 addresses to UInt32 for calculation
            let startInt = ipv4ToUInt32(startAddr)
            let endInt = ipv4ToUInt32(endAddr)

            // Calculate the number of addresses in the range
            let rangeSize = endInt - startInt + 1

            // CRITICAL: Verify this is a power of 2
            if !isPowerOfTwo(rangeSize) {
                print("❌ ERROR: Range \(start) - \(end) has size \(rangeSize) which is NOT a power of 2!")
                print("   This is invalid for CIDR notation!")
                print("   Start: \(startInt), End: \(endInt)")
                // For now, let's continue but log it
                // In production, this should probably throw an error
            }

            // Find the correct prefix length for this specific range
            // Must check that the start address is aligned to the CIDR boundary
            for prefixLen in (8...32).reversed() {
                let mask = ~((UInt32(1) << (32 - prefixLen)) - 1)
                let network = startInt & mask
                let broadcast = network | ~mask

                // Check if this CIDR block exactly matches our range
                if network == startInt && broadcast == endInt {
                    return IPRange(start: startIP, prefixLength: prefixLen)
                }
            }

            // If we get here, something is wrong!
            print("⚠️ WARNING: Could not find exact CIDR for range \(start) - \(end)")
            print("   Size: \(rangeSize), Start aligned: \(startInt & 0xFFFF_FF00)")

            // Try to find the best fit
            let prefixLength = calculatePrefixLength(rangeSize: rangeSize, startAddr: startInt)
            return IPRange(start: startIP, prefixLength: prefixLength)

        case (.v6, .v6):
            // For IPv6, use a default for now (proper calculation would be similar but with 128-bit math)
            return IPRange(start: startIP, prefixLength: 48)

        default:
            return nil
        }
    }

    private func ipv4ToUInt32(_ address: IPv4Address) -> UInt32 {
        let bytes = address.rawValue
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    private func isPowerOfTwo(_ n: UInt32) -> Bool {
        // A number is a power of 2 if it has exactly one bit set
        // This can be checked with n & (n - 1) == 0 (and n != 0)
        return n != 0 && (n & (n - 1)) == 0
    }

    private func calculatePrefixLength(rangeSize: UInt32, startAddr: UInt32) -> Int {
        // Find the smallest CIDR that contains this range starting at this address

        for prefixLen in (8...32).reversed() {
            let mask = ~((UInt32(1) << (32 - prefixLen)) - 1)
            let network = startAddr & mask
            let blockSize = UInt32(1) << (32 - prefixLen)

            // Check if start is aligned and range fits
            if network == startAddr && blockSize >= rangeSize {
                return prefixLen
            }
        }

        // Default to /24 if nothing else works
        return 24
    }
}

public enum BGPError: Error {
    case downloadFailed
    case decompressionFailed
    case invalidData
    case parseError
}

/// Alternative simplified approach using Team Cymru whois service
public struct CymruWhoisFetcher: Sendable {

    /// Fetches ASN for a single IP using DNS-based service
    /// This is good for testing but not for bulk database building
    public func lookupASN(for ip: String) async throws -> (asn: UInt32, name: String) {
        // Team Cymru provides a whois service at whois.cymru.com
        // For DNS lookups: origin.asn.cymru.com
        // Format: reversed_ip.origin.asn.cymru.com returns TXT record with ASN

        // This would require DNS lookups or whois protocol implementation
        // For now, returning placeholder
        throw BGPError.parseError
    }
}
