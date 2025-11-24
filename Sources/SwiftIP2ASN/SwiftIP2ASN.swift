import Foundation

// MARK: - IP2ASN

/// Simple, top-level API for IP-to-ASN lookups.
///
/// This provides the easiest way to get started with SwiftIP2ASN:
///
/// ```swift
/// // Load embedded database (no network required)
/// let db = try IP2ASN.embedded()
///
/// // Lookup an IP
/// if let result = db.lookup("8.8.8.8") {
///     print("AS\(result.asn): \(result.name ?? "Unknown")")
/// }
/// ```
///
/// For automatic updates from CDN:
///
/// ```swift
/// let db = try await IP2ASN.remote()
///
/// // Check for updates periodically
/// let updated = try await IP2ASN.refresh()
/// ```
///
/// For offline-first apps with bundled database:
///
/// ```swift
/// let db = try await IP2ASN.remote(bundledPath: Bundle.main.path(forResource: "ip2asn", ofType: "ultra"))
/// ```
public enum IP2ASN {

    // MARK: - Shared State

    /// Actor to manage shared RemoteDatabase instances safely.
    private actor SharedState {
        var defaultDB = RemoteDatabase()
        var customDB: RemoteDatabase?

        func getDB(bundledPath: String?) -> RemoteDatabase {
            if let bundledPath = bundledPath {
                if customDB == nil {
                    customDB = RemoteDatabase(bundledDatabasePath: bundledPath)
                }
                return customDB!
            }
            return defaultDB
        }

        func getActiveDB() -> RemoteDatabase {
            customDB ?? defaultDB
        }

        func clearCustomDB() {
            customDB = nil
        }
    }

    private static let shared = SharedState()

    // MARK: - Embedded Database (Synchronous)

    /// Load the embedded database bundled with the library.
    ///
    /// This is the simplest way to get started - no network required.
    /// The database is bundled with the SwiftIP2ASN package.
    ///
    /// - Returns: An `UltraCompactDatabase` ready for lookups.
    /// - Throws: `EmbeddedDatabase.Error.resourceNotFound` if the bundled database is missing.
    ///
    /// ```swift
    /// let db = try IP2ASN.embedded()
    /// if let result = db.lookup("8.8.8.8") {
    ///     print("AS\(result.asn)")  // AS15169
    /// }
    /// ```
    public static func embedded() throws -> UltraCompactDatabase {
        try EmbeddedDatabase.loadUltraCompact()
    }

    // MARK: - Remote Database (Async)

    /// Load database with automatic CDN updates.
    ///
    /// On first call, downloads from CDN (~3.4 MB). Subsequent calls use the
    /// persistent disk cache. The database is cached in Application Support.
    ///
    /// - Parameter bundledPath: Optional path to a bundled database for offline-first operation.
    ///   When provided, works immediately even without network.
    /// - Returns: An `UltraCompactDatabase` ready for lookups.
    ///
    /// ```swift
    /// // Basic usage - downloads on first call
    /// let db = try await IP2ASN.remote()
    ///
    /// // Offline-first - uses bundled DB, updates in background
    /// let db = try await IP2ASN.remote(bundledPath: Bundle.main.path(forResource: "ip2asn", ofType: "ultra"))
    /// ```
    public static func remote(bundledPath: String? = nil) async throws -> UltraCompactDatabase {
        let db = await shared.getDB(bundledPath: bundledPath)
        return try await db.load()
    }

    /// Check for database updates from CDN.
    ///
    /// Issues a HEAD request first (~200 bytes) to check if an update is available.
    /// Only downloads the full database (~3.4 MB) if the remote version is newer.
    ///
    /// - Returns: The refresh result indicating whether an update was downloaded.
    ///
    /// ```swift
    /// switch try await IP2ASN.refresh() {
    /// case .alreadyCurrent:
    ///     print("Database is up to date")
    /// case .updated(let db):
    ///     print("Updated to \(db.entryCount) entries")
    /// }
    /// ```
    @discardableResult
    public static func refresh() async throws -> RemoteDatabase.RefreshResult {
        let db = await shared.getActiveDB()
        return try await db.refresh()
    }

    /// Check if a downloaded database cache exists.
    ///
    /// - Returns: `true` if a cached database exists on disk.
    public static func isCached() async -> Bool {
        let db = await shared.getActiveDB()
        return await db.isCached()
    }

    /// Clear the downloaded database cache.
    ///
    /// After calling this, the next `remote()` call will either use the bundled
    /// database (if provided) or download fresh from CDN.
    public static func clearCache() async throws {
        let db = await shared.getActiveDB()
        try await db.clearCache()
    }
}

// MARK: - SwiftIP2ASN (Legacy)

/// Main entry point for IP to ASN lookups using trie-based database.
///
/// > Note: For most use cases, prefer the simpler ``IP2ASN`` API which uses
/// > the more efficient `UltraCompactDatabase`.
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
