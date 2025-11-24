import Foundation

// MARK: - EmbeddedDatabase

/// Provides access to the IP2ASN database bundled with the SwiftIP2ASN package.
///
/// This enum offers a simple way to load the pre-built database that ships with the library.
/// For apps that need automatic updates, see ``RemoteDatabase`` instead.
///
/// ## Overview
///
/// The embedded database contains IP-to-ASN mappings from [iptoasn.com](https://iptoasn.com),
/// which aggregates BGP routing data. It's updated periodically with library releases.
///
/// ## Usage
///
/// ```swift
/// import SwiftIP2ASN
///
/// // Load the embedded database
/// let db = try EmbeddedDatabase.loadUltraCompact()
///
/// // Perform lookups
/// if let result = db.lookup("8.8.8.8") {
///     print("AS\(result.asn): \(result.name ?? "Unknown")")
///     // Output: AS15169: GOOGLE
/// }
/// ```
///
/// ## Topics
///
/// ### Loading the Database
///
/// - ``loadUltraCompact()``
///
/// ### Errors
///
/// - ``Error``
public enum EmbeddedDatabase {

    /// Errors that can occur when loading or fetching databases.
    public enum Error: Swift.Error, Sendable {
        /// The embedded database resource was not found in the bundle.
        case resourceNotFound

        /// A network request failed with the given error message.
        case downloadFailed(String)

        /// The server returned an empty or invalid response.
        case invalidResponse
    }

    /// Loads the embedded Ultra-Compact database shipped as a SwiftPM resource.
    ///
    /// The database file is located at `Sources/SwiftIP2ASN/Resources/ip2asn.ultra`
    /// and is included automatically when you add SwiftIP2ASN as a dependency.
    ///
    /// - Returns: An ``UltraCompactDatabase`` ready for IP lookups.
    /// - Throws: ``Error/resourceNotFound`` if the database file is missing.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let db = try EmbeddedDatabase.loadUltraCompact()
    /// print("Loaded \(db.entryCount) IP ranges")
    /// print("Covering \(db.uniqueASNCount) unique ASNs")
    /// ```
    public static func loadUltraCompact() throws -> UltraCompactDatabase {
        guard let url = Bundle.module.url(forResource: "ip2asn", withExtension: "ultra") else {
            throw Error.resourceNotFound
        }
        return try UltraCompactDatabase(path: url.path)
    }
}

// MARK: - RemoteDatabase

/// Fetches, caches, and manages IP2ASN database updates from a remote server.
///
/// `RemoteDatabase` provides automatic database management with these key features:
/// - **Persistent caching**: Downloads once, uses forever (until you call ``refresh()``)
/// - **Efficient updates**: Uses HTTP ETag/Last-Modified headers to avoid re-downloading unchanged data
/// - **Offline-first support**: Apps can bundle a database for immediate offline use
///
/// ## Overview
///
/// The database is fetched from [pkgs.networkweather.com](https://pkgs.networkweather.com)
/// by default, which hosts daily-updated BGP routing data from iptoasn.com.
///
/// ## Basic Usage
///
/// ```swift
/// let remote = RemoteDatabase()
///
/// // First call downloads (~3.4 MB), subsequent calls use cache
/// let db = try await remote.load()
///
/// // Perform lookups
/// if let result = db.lookup("8.8.8.8") {
///     print("AS\(result.asn): \(result.name ?? "Unknown")")
/// }
/// ```
///
/// ## Checking for Updates
///
/// ```swift
/// // Issues HEAD request first (~200 bytes), only downloads if changed
/// switch try await remote.refresh() {
/// case .alreadyCurrent:
///     print("Database is up to date")
/// case .updated(let newDb):
///     print("Downloaded new database with \(newDb.entryCount) entries")
/// }
/// ```
///
/// ## Offline-First Apps
///
/// Apps can ship with a bundled database for immediate offline functionality:
///
/// ```swift
/// let remote = RemoteDatabase(
///     bundledDatabasePath: Bundle.main.path(forResource: "ip2asn", ofType: "ultra")
/// )
///
/// // Works immediately, even offline
/// let db = try await remote.load()
///
/// // Check for updates in the background
/// Task {
///     try? await remote.refresh()
/// }
/// ```
///
/// ## Thread Safety
///
/// `RemoteDatabase` is an actor, ensuring all operations are thread-safe.
/// You can safely call methods from multiple tasks concurrently.
///
/// ## Topics
///
/// ### Creating a RemoteDatabase
///
/// - ``init(remoteURL:cacheDirectory:bundledDatabasePath:)``
/// - ``defaultURL``
///
/// ### Loading and Refreshing
///
/// - ``load()``
/// - ``refresh()``
/// - ``RefreshResult``
///
/// ### Cache Management
///
/// - ``isCached()``
/// - ``cachePath()``
/// - ``clearCache()``
public actor RemoteDatabase {

    /// The default URL for fetching the IP2ASN database.
    ///
    /// Points to `https://pkgs.networkweather.com/db/ip2asn.ultra`, which is
    /// updated daily with fresh BGP routing data.
    public static let defaultURL = URL(string: "https://pkgs.networkweather.com/db/ip2asn.ultra")!

    private let cacheURL: URL
    private let metadataURL: URL
    private let remoteURL: URL
    private let bundledDatabasePath: String?
    private var cachedDatabase: UltraCompactDatabase?

    /// Creates a new RemoteDatabase instance.
    ///
    /// - Parameters:
    ///   - remoteURL: The URL to fetch the database from. Defaults to ``defaultURL``.
    ///   - cacheDirectory: Directory for storing the cached database. Defaults to
    ///     `~/Library/Application Support/SwiftIP2ASN/` on macOS.
    ///   - bundledDatabasePath: Optional path to a database file bundled with your app.
    ///     When provided, ``load()`` will use this file if no cached download exists,
    ///     enabling offline-first operation.
    ///
    /// ## Example: Custom Cache Location
    ///
    /// ```swift
    /// let cacheDir = FileManager.default.temporaryDirectory
    ///     .appendingPathComponent("MyApp/IP2ASN")
    /// let remote = RemoteDatabase(cacheDirectory: cacheDir)
    /// ```
    ///
    /// ## Example: Bundled Database
    ///
    /// ```swift
    /// let remote = RemoteDatabase(
    ///     bundledDatabasePath: Bundle.main.path(forResource: "ip2asn", ofType: "ultra")
    /// )
    /// ```
    public init(
        remoteURL: URL = RemoteDatabase.defaultURL,
        cacheDirectory: URL? = nil,
        bundledDatabasePath: String? = nil
    ) {
        self.remoteURL = remoteURL
        self.bundledDatabasePath = bundledDatabasePath

        let cacheDir =
            cacheDirectory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent("SwiftIP2ASN", isDirectory: true)

        self.cacheURL = cacheDir.appendingPathComponent("ip2asn.ultra")
        self.metadataURL = cacheDir.appendingPathComponent("ip2asn.meta.json")
    }

    /// Loads the IP2ASN database, fetching from network only if necessary.
    ///
    /// The database is loaded using this priority order:
    /// 1. **In-memory cache**: Returns immediately if already loaded
    /// 2. **Disk cache**: Loads from a previous download
    /// 3. **Bundled database**: Uses the file specified in `bundledDatabasePath`
    /// 4. **Network fetch**: Downloads from `remoteURL` (requires network)
    ///
    /// Once loaded, the database is cached in memory for fast subsequent access.
    /// Call ``refresh()`` to check for updates.
    ///
    /// - Returns: An ``UltraCompactDatabase`` ready for IP lookups.
    /// - Throws: ``EmbeddedDatabase/Error/downloadFailed(_:)`` if network fetch fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let remote = RemoteDatabase()
    /// let db = try await remote.load()
    /// print("Loaded \(db.entryCount) IP ranges")
    /// ```
    public func load() async throws -> UltraCompactDatabase {
        // Return in-memory cache if available
        if let db = cachedDatabase {
            return db
        }

        // Check disk cache (downloaded updates take priority over bundled)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            let db = try UltraCompactDatabase(path: cacheURL.path)
            cachedDatabase = db
            return db
        }

        // Use bundled database if provided (works offline)
        if let bundledPath = bundledDatabasePath,
            FileManager.default.fileExists(atPath: bundledPath)
        {
            let db = try UltraCompactDatabase(path: bundledPath)
            cachedDatabase = db
            return db
        }

        // Fetch from remote (only happens if no bundled DB and no cache)
        return try await fetchAndCache()
    }

    /// The result of a ``refresh()`` operation.
    public enum RefreshResult: Sendable {
        /// The cached database is already current; no download was needed.
        case alreadyCurrent

        /// A new database was downloaded and is now cached.
        case updated(UltraCompactDatabase)
    }

    /// Checks for database updates and downloads only if the remote has changed.
    ///
    /// This method uses HTTP ETag and Last-Modified headers to efficiently check
    /// for updates. The typical flow is:
    /// 1. Send HEAD request (~200 bytes)
    /// 2. Compare ETag/Last-Modified with stored metadata
    /// 3. Download only if changed (~3.4 MB)
    ///
    /// If using a bundled database (no previous download metadata), this will
    /// always download since the bundled version cannot be compared.
    ///
    /// - Returns: ``RefreshResult/alreadyCurrent`` if no update needed,
    ///   or ``RefreshResult/updated(_:)`` with the new database if downloaded.
    /// - Throws: ``EmbeddedDatabase/Error/downloadFailed(_:)`` if the request fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Check for updates in the background
    /// Task {
    ///     switch try await remote.refresh() {
    ///     case .alreadyCurrent:
    ///         print("Already up to date")
    ///     case .updated(let db):
    ///         print("Updated to \(db.entryCount) entries")
    ///     }
    /// }
    /// ```
    @discardableResult
    public func refresh() async throws -> RefreshResult {
        // Load stored metadata (ETag/Last-Modified from previous download)
        let storedMeta = loadMetadata()

        // Issue HEAD request to check if remote has changed
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "HEAD"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw EmbeddedDatabase.Error.downloadFailed("HEAD request failed: HTTP \(status)")
        }

        let remoteETag = httpResponse.value(forHTTPHeaderField: "ETag")
        let remoteLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        // Check if we already have this version (only if we have metadata from a previous download)
        if let storedETag = storedMeta?.etag, let remoteETag = remoteETag {
            if storedETag == remoteETag {
                return .alreadyCurrent
            }
        } else if let storedLastModified = storedMeta?.lastModified,
            let remoteLastModified = remoteLastModified
        {
            if storedLastModified == remoteLastModified {
                return .alreadyCurrent
            }
        }

        // No metadata (using bundled DB) or remote is newer - download it
        let db = try await fetchAndCache()
        return .updated(db)
    }

    /// Returns whether a downloaded database cache exists on disk.
    ///
    /// This does not check for bundled databases, only for previously downloaded ones.
    ///
    /// - Returns: `true` if a cached database file exists.
    public func isCached() -> Bool {
        FileManager.default.fileExists(atPath: cacheURL.path)
    }

    /// Deletes the cached database and metadata from disk.
    ///
    /// After calling this method:
    /// - ``isCached()`` will return `false`
    /// - ``load()`` will use the bundled database (if provided) or fetch from network
    /// - ``refresh()`` will always download (no metadata to compare)
    ///
    /// - Throws: If file deletion fails.
    public func clearCache() throws {
        cachedDatabase = nil
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            try FileManager.default.removeItem(at: metadataURL)
        }
    }

    /// Returns the file path of the cached database, if it exists.
    ///
    /// - Returns: The absolute path to the cached `.ultra` file, or `nil` if not cached.
    public func cachePath() -> String? {
        FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL.path : nil
    }

    // MARK: - Private

    private struct CacheMetadata: Codable {
        let etag: String?
        let lastModified: String?
    }

    private func loadMetadata() -> CacheMetadata? {
        guard let data = try? Data(contentsOf: metadataURL),
            let meta = try? JSONDecoder().decode(CacheMetadata.self, from: data)
        else {
            return nil
        }
        return meta
    }

    private func saveMetadata(etag: String?, lastModified: String?) {
        let meta = CacheMetadata(etag: etag, lastModified: lastModified)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    private func fetchAndCache() async throws -> UltraCompactDatabase {
        // Ensure cache directory exists
        let cacheDir = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Download
        let (data, response) = try await URLSession.shared.data(from: remoteURL)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw EmbeddedDatabase.Error.downloadFailed("HTTP \(status)")
        }

        guard !data.isEmpty else {
            throw EmbeddedDatabase.Error.invalidResponse
        }

        // Write to disk cache (atomic to prevent corruption)
        try data.write(to: cacheURL, options: .atomic)

        // Save ETag/Last-Modified for future refresh checks
        let etag = httpResponse.value(forHTTPHeaderField: "ETag")
        let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
        saveMetadata(etag: etag, lastModified: lastModified)

        // Load and cache in memory
        let db = try UltraCompactDatabase(data: data)
        cachedDatabase = db
        return db
    }
}
