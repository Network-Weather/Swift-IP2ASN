import Foundation

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct SwiftIP2ASN: Sendable {
    private let database: ASNDatabase

    public init(database: ASNDatabase) {
        self.database = database
    }

    /// Builds database from online RIR data (NOTE: RIR data doesn't contain ASN mappings)
    @available(*, deprecated, message: "Use buildWithBGPData() instead - RIR data doesn't contain ASN mappings")
    public static func buildFromOnlineData() async throws -> SwiftIP2ASN {
        let database = ASNDatabase()
        try await database.buildFromRIRData()
        return SwiftIP2ASN(database: database)
    }

    /// Builds database with real BGP data containing actual ASN mappings
    public static func buildWithBGPData() async throws -> SwiftIP2ASN {
        let database = ASNDatabase()

        // Get BGP data
        let fetcher = SimpleBGPFetcher()
        let bgpData = try await fetcher.fetchCurrentBGPData()

        // Convert to format with IPRange
        var bgpEntries: [(range: IPRange, asn: UInt32, name: String?)] = []
        for (cidr, asn, name) in bgpData {
            guard let range = IPRange(cidr: cidr) else { continue }
            bgpEntries.append((range: range, asn: asn, name: name))
        }

        // Build database with BGP data including names
        await database.buildWithBGPData(bgpEntries: bgpEntries)

        return SwiftIP2ASN(database: database)
    }

    public static func load(from url: URL) async throws -> SwiftIP2ASN {
        let database = ASNDatabase()
        try await database.load(from: url)
        return SwiftIP2ASN(database: database)
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
