import Foundation

// MARK: - Shared convenience API state

/// Maintains the single active configuration used by the `IP2ASN` convenience
/// API. Kept internal so configuration transitions can be tested without
/// touching the process-wide singleton or performing network requests.
actor IP2ASNSharedState {
    private var activeBundledPath: String?
    private var activeDatabase = RemoteDatabase()

    func database(bundledPath: String?) -> RemoteDatabase {
        if bundledPath != activeBundledPath {
            activeBundledPath = bundledPath
            activeDatabase = RemoteDatabase(bundledDatabasePath: bundledPath)
        }
        return activeDatabase
    }

    func databaseForActiveConfiguration() -> RemoteDatabase {
        activeDatabase
    }
}

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
///
/// `IP2ASN` is a convenience singleton with one active remote configuration.
/// Each call to ``remote(bundledPath:)`` selects the configuration subsequently
/// used by ``refresh()``, ``isCached()``, and ``clearCache()``. Calling
/// `remote()` without a path selects the default configuration again. Create
/// separate ``RemoteDatabase`` actors with distinct cache directories when an
/// application needs multiple independent configurations.
public enum IP2ASN {

    // MARK: - Shared State

    private static let shared = IP2ASNSharedState()

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
    /// On first call, downloads from CDN (~4 MB). Subsequent calls use the
    /// persistent disk cache. The database is cached in Application Support.
    ///
    /// - Parameter bundledPath: Optional path to a bundled database for offline-first operation.
    ///   When provided, works immediately even without network. This call also
    ///   selects the active configuration used by the static cache-management
    ///   methods. Passing a different path replaces the previous in-memory
    ///   `RemoteDatabase`; passing `nil` selects the default configuration.
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
        let db = await shared.database(bundledPath: bundledPath)
        return try await db.load()
    }

    /// Check for database updates from CDN.
    ///
    /// Issues a HEAD request first (~200 bytes) to check if an update is available.
    /// Only downloads the full database (~4 MB) if the remote version is newer.
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
        let db = await shared.databaseForActiveConfiguration()
        return try await db.refresh()
    }

    /// Check if a downloaded database cache exists.
    ///
    /// - Returns: `true` if a cached database exists on disk.
    public static func isCached() async -> Bool {
        let db = await shared.databaseForActiveConfiguration()
        return await db.isCached()
    }

    /// Clear the downloaded database cache.
    ///
    /// After calling this, the next `remote()` call will either use the bundled
    /// database (if provided) or download fresh from CDN.
    public static func clearCache() async throws {
        let db = await shared.databaseForActiveConfiguration()
        try await db.clearCache()
    }
}
