import Foundation

protocol RemoteDatabaseHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

private struct URLSessionRemoteDatabaseHTTPTransport: RemoteDatabaseHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

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
/// - ``loadUltraCompact(from:)``
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
    /// - Parameter bundle: The bundle to load the resource from. Defaults to `.module`.
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
    public static func loadUltraCompact(from bundle: Bundle? = .safeModule) throws -> UltraCompactDatabase {
        let url = try ultraCompactURL(from: bundle)
        return try UltraCompactDatabase(path: url.path, origin: .embedded)
    }

    package static func ultraCompactURL(from bundle: Bundle? = .safeModule) throws -> URL {
        guard let url = bundle?.url(forResource: "ip2asn", withExtension: "ultra") else {
            throw Error.resourceNotFound
        }
        return url
    }

    package static func manifestURL(from bundle: Bundle? = .safeModule) throws -> URL {
        guard let url = bundle?.url(forResource: "ip2asn.manifest", withExtension: "json") else {
            throw Error.resourceNotFound
        }
        return url
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
/// // First call downloads (~4 MB), subsequent calls use cache
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
/// // Sends one conditional GET; a current cache receives no response body
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
/// - ``refreshDetails()``
/// - ``status()``
/// - ``RefreshResult``
/// - ``RefreshDetails``
/// - ``Status``
///
/// ### Cache Management
///
/// - ``isCached()``
/// - ``cachePath()``
/// - ``clearCache()``
public actor RemoteDatabase {

    /// The default URL for fetching the IP2ASN database.
    ///
    /// Points to `https://pkgs.networkweather.com/db/ip2asn-v2.ultra`, the dual-stack
    /// V2 format introduced in 0.4.0. The pre-0.4.0 IPv4-only file remains at
    /// `/db/ip2asn.ultra` for compatibility with older library versions.
    public static let defaultURL = URL(string: "https://pkgs.networkweather.com/db/ip2asn-v2.ultra")!

    private let cacheURL: URL
    private let metadataURL: URL
    private let remoteURL: URL
    private let bundledDatabasePath: String?
    private let httpTransport: any RemoteDatabaseHTTPTransport
    private var cachedDatabase: UltraCompactDatabase?
    private var fetchTask: Task<UltraCompactDatabase, Swift.Error>?
    private var refreshTask: Task<RefreshDetails, Swift.Error>?

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
        self.httpTransport = URLSessionRemoteDatabaseHTTPTransport()

        let cacheDir =
            cacheDirectory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent("SwiftIP2ASN", isDirectory: true)

        self.cacheURL = cacheDir.appendingPathComponent("ip2asn.ultra")
        self.metadataURL = cacheDir.appendingPathComponent("ip2asn.meta.json")
    }

    /// Internal initializer used to exercise remote behavior without contacting
    /// the production CDN. The public initializer always uses `URLSession`.
    init(
        remoteURL: URL,
        cacheDirectory: URL?,
        bundledDatabasePath: String?,
        httpTransport: any RemoteDatabaseHTTPTransport
    ) {
        self.remoteURL = remoteURL
        self.bundledDatabasePath = bundledDatabasePath
        self.httpTransport = httpTransport

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
            do {
                let db = try UltraCompactDatabase(path: cacheURL.path, origin: .diskCache)
                cachedDatabase = db
                return db
            } catch {
                // Remove corrupted or incompatible cached database and metadata
                try? FileManager.default.removeItem(at: cacheURL)
                try? FileManager.default.removeItem(at: metadataURL)
            }
        }

        // Use bundled database if provided (works offline)
        if let bundledPath = bundledDatabasePath,
            FileManager.default.fileExists(atPath: bundledPath)
        {
            let db = try UltraCompactDatabase(path: bundledPath, origin: .bundled)
            cachedDatabase = db
            return db
        }

        // Fetch from remote (only happens if no bundled DB and no cache)
        return try await fetchAndCacheOnce()
    }

    /// The result of a ``refresh()`` operation.
    public enum RefreshResult: Sendable {
        /// The cached database is already current; no download was needed.
        case alreadyCurrent

        /// A new database was downloaded and is now cached.
        case updated(UltraCompactDatabase)
    }

    /// Current database identity and persisted remote-update timestamps.
    public struct Status: Equatable, Sendable {
        /// Metadata for the active in-memory database, if one has been loaded.
        public let databaseMetadata: DatabaseMetadata?

        /// Runtime origin of the active database, if one has been loaded.
        public let origin: DatabaseOrigin?

        /// Most recent successful remote response, including `304` responses.
        public let lastSuccessfulCheck: Date?

        /// Most recent successful database download and cache replacement.
        public let lastSuccessfulUpdate: Date?
    }

    /// Detailed result of a conditional refresh operation.
    public struct RefreshDetails: Sendable {
        public enum Outcome: String, Equatable, Sendable {
            /// The server returned `304 Not Modified` and the cache was retained.
            case notModified

            /// A response body was validated and installed as the active cache.
            case updated
        }

        public let outcome: Outcome
        public let database: UltraCompactDatabase
        public let status: Status
    }

    /// Checks for database updates and downloads only if the remote has changed.
    ///
    /// This method sends one conditional `GET` using the cached ETag and/or
    /// Last-Modified value. A `304 Not Modified` response retains the cache; a
    /// successful response body is validated and installed atomically.
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
        let details = try await refreshDetails()
        switch details.outcome {
        case .notModified:
            return .alreadyCurrent
        case .updated:
            return .updated(details.database)
        }
    }

    /// Performs a conditional refresh and returns database identity, origin,
    /// and successful check/update timestamps with the outcome.
    ///
    /// Servers without ETag or Last-Modified support receive an unconditional
    /// `GET`, so refresh remains correct but downloads the body each time.
    @discardableResult
    public func refreshDetails() async throws -> RefreshDetails {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { try await performRefresh() }
        refreshTask = task
        do {
            let result = try await task.value
            refreshTask = nil
            return result
        } catch {
            refreshTask = nil
            throw error
        }
    }

    /// Returns active database identity and persisted update timestamps.
    ///
    /// Database metadata and origin are `nil` until ``load()`` or a refresh has
    /// installed an in-memory database. Successful check/update timestamps are
    /// restored from the disk-cache sidecar when available.
    public func status() -> Status {
        makeStatus(cacheMetadata: isCached() ? loadMetadata() : nil)
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
        refreshTask?.cancel()
        refreshTask = nil
        fetchTask?.cancel()
        fetchTask = nil
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
        let lastSuccessfulCheck: Date?
        let lastSuccessfulUpdate: Date?
    }

    private func loadMetadata() -> CacheMetadata? {
        guard let data = try? Data(contentsOf: metadataURL),
            let meta = try? JSONDecoder().decode(CacheMetadata.self, from: data)
        else {
            return nil
        }
        return meta
    }

    private func saveMetadata(_ metadata: CacheMetadata) {
        let meta = metadata
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    private func makeStatus(cacheMetadata: CacheMetadata?) -> Status {
        Status(
            databaseMetadata: cachedDatabase?.metadata,
            origin: cachedDatabase?.origin,
            lastSuccessfulCheck: cacheMetadata?.lastSuccessfulCheck,
            lastSuccessfulUpdate: cacheMetadata?.lastSuccessfulUpdate
        )
    }

    private func performRefresh() async throws -> RefreshDetails {
        if let fetchTask {
            let database = try await fetchTask.value
            return RefreshDetails(
                outcome: .updated,
                database: database,
                status: makeStatus(cacheMetadata: loadMetadata())
            )
        }

        guard isCached() else {
            let database = try await fetchAndCacheOnce()
            return RefreshDetails(
                outcome: .updated,
                database: database,
                status: makeStatus(cacheMetadata: loadMetadata())
            )
        }

        let storedMetadata = loadMetadata()
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        if let etag = storedMetadata?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = storedMetadata?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        let isConditional =
            request.value(forHTTPHeaderField: "If-None-Match") != nil
            || request.value(forHTTPHeaderField: "If-Modified-Since") != nil

        let (data, response) = try await performRequest(request, operation: "Refresh")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddedDatabase.Error.downloadFailed("Refresh failed: non-HTTP response")
        }

        let checkedAt = Date()
        if httpResponse.statusCode == 304 {
            guard isConditional, isCached() else {
                throw EmbeddedDatabase.Error.downloadFailed(
                    "Refresh failed: unsolicited HTTP 304"
                )
            }

            let database: UltraCompactDatabase
            if let cachedDatabase {
                database = cachedDatabase
            } else {
                do {
                    database = try UltraCompactDatabase(path: cacheURL.path, origin: .diskCache)
                    cachedDatabase = database
                } catch {
                    // The validator describes an unusable local file. Remove both
                    // parts of the cache and recover with an unconditional download.
                    try? FileManager.default.removeItem(at: cacheURL)
                    try? FileManager.default.removeItem(at: metadataURL)
                    let recoveredDatabase = try await fetchAndCacheOnce()
                    return RefreshDetails(
                        outcome: .updated,
                        database: recoveredDatabase,
                        status: makeStatus(cacheMetadata: loadMetadata())
                    )
                }
            }

            let metadata = CacheMetadata(
                etag: httpResponse.value(forHTTPHeaderField: "ETag") ?? storedMetadata?.etag,
                lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
                    ?? storedMetadata?.lastModified,
                lastSuccessfulCheck: checkedAt,
                lastSuccessfulUpdate: storedMetadata?.lastSuccessfulUpdate
            )
            saveMetadata(metadata)
            return RefreshDetails(
                outcome: .notModified,
                database: database,
                status: makeStatus(cacheMetadata: metadata)
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw EmbeddedDatabase.Error.downloadFailed("Refresh failed: HTTP \(httpResponse.statusCode)")
        }
        let database = try cacheDownloadedDatabase(data, response: httpResponse, checkedAt: checkedAt)
        return RefreshDetails(
            outcome: .updated,
            database: database,
            status: makeStatus(cacheMetadata: loadMetadata())
        )
    }

    private func performRequest(
        _ request: URLRequest,
        operation: String
    ) async throws -> (Data, URLResponse) {
        do {
            return try await httpTransport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EmbeddedDatabase.Error.downloadFailed(
                "\(operation) failed: \(error.localizedDescription)"
            )
        }
    }

    private func fetchAndCacheOnce() async throws -> UltraCompactDatabase {
        if let fetchTask {
            return try await fetchTask.value
        }

        let task = Task { try await fetchAndCache() }
        fetchTask = task

        do {
            let database = try await task.value
            fetchTask = nil
            return database
        } catch {
            fetchTask = nil
            throw error
        }
    }

    private func fetchAndCache() async throws -> UltraCompactDatabase {
        // Ensure cache directory exists
        let cacheDir = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Download
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        let (data, response) = try await performRequest(request, operation: "Download")

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw EmbeddedDatabase.Error.downloadFailed("HTTP \(status)")
        }

        guard !data.isEmpty else {
            throw EmbeddedDatabase.Error.invalidResponse
        }

        return try cacheDownloadedDatabase(data, response: httpResponse, checkedAt: Date())
    }

    private func cacheDownloadedDatabase(
        _ data: Data,
        response: HTTPURLResponse,
        checkedAt: Date
    ) throws -> UltraCompactDatabase {
        guard !data.isEmpty else {
            throw EmbeddedDatabase.Error.invalidResponse
        }

        // Validate and parse the database first before writing to disk.
        let db = try UltraCompactDatabase(data: data, origin: .downloaded)

        // Write to disk cache (atomic to prevent corruption)
        try data.write(to: cacheURL, options: .atomic)

        saveMetadata(
            CacheMetadata(
                etag: response.value(forHTTPHeaderField: "ETag"),
                lastModified: response.value(forHTTPHeaderField: "Last-Modified"),
                lastSuccessfulCheck: checkedAt,
                lastSuccessfulUpdate: checkedAt
            )
        )

        // Cache in memory
        cachedDatabase = db
        return db
    }
}
