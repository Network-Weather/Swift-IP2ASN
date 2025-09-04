import Foundation

/// Improved ASN Database that uses actual BGP data
public actor ASNDatabaseV2 {
    private let trie: CompressedTrie
    private var isBuilt = false

    public init() {
        self.trie = CompressedTrie()
    }

    /// Builds database from IPtoASN.com data (contains real ASN mappings)
    public func buildFromBGPData() async throws {
        let fetcher = BGPDataFetcher()
        let parser = BGPDataParser()

        print("Fetching IPv4 BGP data...")
        let ipv4Data = try await fetcher.fetchIPv4Data()
        print("IPv4 data fetched: \(ipv4Data.count) characters")

        print("Fetching IPv6 BGP data...")
        let ipv6Data = try await fetcher.fetchIPv6Data()
        print("IPv6 data fetched: \(ipv6Data.count) characters")

        print("Parsing BGP data...")
        let ipv4Mappings = parser.parseIPtoASNData(ipv4Data)
        print("Parsed \(ipv4Mappings.count) IPv4 mappings")
        let ipv6Mappings = parser.parseIPtoASNData(ipv6Data)
        print("Parsed \(ipv6Mappings.count) IPv6 mappings")

        print("Building trie with \(ipv4Mappings.count) IPv4 and \(ipv6Mappings.count) IPv6 entries...")

        // Insert IPv4 mappings
        for (range, asn, name) in ipv4Mappings {
            let asnInfo = ASNInfo(
                asn: asn,
                countryCode: nil,  // IPtoASN includes country but we'd need to parse it
                registry: "bgp",
                allocatedDate: nil,
                name: name
            )
            await trie.insert(range: range, asnInfo: asnInfo)
        }

        // Insert IPv6 mappings
        for (range, asn, name) in ipv6Mappings {
            let asnInfo = ASNInfo(
                asn: asn,
                countryCode: nil,
                registry: "bgp",
                allocatedDate: nil,
                name: name
            )
            await trie.insert(range: range, asnInfo: asnInfo)
        }

        isBuilt = true
        print("Database built successfully!")
    }

    /// Alternative: Build from RouteViews data
    public func buildFromRouteViews() async throws {
        let fetcher = BGPDataFetcher()
        let parser = BGPDataParser()

        print("Fetching RouteViews BGP data...")
        let bgpData = try await fetcher.fetchRouteViewsData()

        print("Parsing RouteViews data...")
        let mappings = parser.parseRouteViewsData(bgpData)

        print("Building trie with \(mappings.count) entries...")

        for (range, asn) in mappings {
            let asnInfo = ASNInfo(
                asn: asn,
                countryCode: nil,
                registry: "routeviews",
                allocatedDate: nil,
                name: nil
            )
            await trie.insert(range: range, asnInfo: asnInfo)
        }

        isBuilt = true
    }

    /// Alternative: Build from local MaxMind GeoLite2 ASN database
    public func buildFromMaxMind(csvPath: String) async throws {
        let content = try String(contentsOfFile: csvPath)
        let lines = content.split(separator: "\n")

        // Skip header
        for line in lines.dropFirst() {
            let fields = line.split(separator: ",").map { String($0) }
            guard fields.count >= 3 else { continue }

            let network = fields[0].trimmingQuotes
            let asnString = fields[1].trimmingQuotes
            let orgName = fields[2].trimmingQuotes

            guard let range = IPRange(cidr: network),
                let asn = UInt32(asnString)
            else { continue }

            let asnInfo = ASNInfo(
                asn: asn,
                countryCode: nil,
                registry: "maxmind",
                allocatedDate: nil,
                name: orgName
            )

            await trie.insert(range: range, asnInfo: asnInfo)
        }

        isBuilt = true
    }

    public func lookup(_ address: IPAddress) async -> ASNInfo? {
        guard isBuilt else { return nil }
        return await trie.lookup(address)
    }

    public func lookup(_ addressString: String) async -> ASNInfo? {
        guard let address = IPAddress(string: addressString) else {
            return nil
        }
        return await lookup(address)
    }

    public func getStatistics() async -> TrieStatistics {
        return await trie.getStatistics()
    }
}

/// Updated main interface to use proper BGP data
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct SwiftIP2ASNV2: Sendable {
    private let database: ASNDatabaseV2

    public init(database: ASNDatabaseV2) {
        self.database = database
    }

    /// Builds database from BGP data (contains actual ASN mappings)
    public static func buildFromBGPData() async throws -> SwiftIP2ASNV2 {
        let database = ASNDatabaseV2()
        try await database.buildFromBGPData()
        return SwiftIP2ASNV2(database: database)
    }

    /// Builds database from RouteViews BGP dumps
    public static func buildFromRouteViews() async throws -> SwiftIP2ASNV2 {
        let database = ASNDatabaseV2()
        try await database.buildFromRouteViews()
        return SwiftIP2ASNV2(database: database)
    }

    /// Builds database from local MaxMind GeoLite2 ASN CSV
    public static func buildFromMaxMind(csvPath: String) async throws -> SwiftIP2ASNV2 {
        let database = ASNDatabaseV2()
        try await database.buildFromMaxMind(csvPath: csvPath)
        return SwiftIP2ASNV2(database: database)
    }

    public func lookup(_ address: String) async -> ASNInfo? {
        return await database.lookup(address)
    }

    public func lookup(_ address: IPAddress) async -> ASNInfo? {
        return await database.lookup(address)
    }

    public func getStatistics() async -> TrieStatistics {
        return await database.getStatistics()
    }
}

// Helper to trim quotes from CSV fields
extension String {
    var trimmingQuotes: String {
        return self.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}
