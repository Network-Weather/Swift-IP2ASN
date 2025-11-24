import Foundation

// MARK: - SwiftIP2ASN

/// Main entry point for IP to ASN lookups.
///
/// Thread Safety:
/// - Uses actor-based `ASNDatabase` for thread-safe lookups.
/// - All public methods are async and safe to call concurrently.
///
/// Usage:
/// ```swift
/// let ip2asn = try await SwiftIP2ASN.load(from: databaseURL)
/// let info = await ip2asn.lookup("8.8.8.8")
/// ```
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct SwiftIP2ASN: Sendable {
    private let database: ASNDatabase

    public init(database: ASNDatabase) {
        self.database = database
    }

    /// Load a pre-built database from a URL.
    public static func load(from url: URL) async throws -> SwiftIP2ASN {
        let database = ASNDatabase()
        try await database.load(from: url)
        return SwiftIP2ASN(database: database)
    }

    /// Look up ASN info for an IP address string.
    public func lookup(_ address: String) async -> ASNInfo? {
        return await database.lookup(address)
    }

    /// Look up ASN info for an IPAddress.
    public func lookup(_ address: IPAddress) async -> ASNInfo? {
        return await database.lookup(address)
    }

    /// Get database statistics.
    public func getStatistics() async -> TrieStatistics {
        return await database.getStatistics()
    }
}
