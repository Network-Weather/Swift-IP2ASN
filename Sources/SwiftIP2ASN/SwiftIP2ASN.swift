import Foundation

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct SwiftIP2ASN: Sendable {
    private let database: ASNDatabase

    public init(database: ASNDatabase) {
        self.database = database
    }

    // Database building from raw data has moved to the IP2ASNDataPrep module.
    // Keep the library focused on lookups given a prepared database.

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
