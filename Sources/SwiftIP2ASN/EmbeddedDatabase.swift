import Foundation

// MARK: - EmbeddedDatabase

/// Access to embedded database resources bundled with the package.
public enum EmbeddedDatabase {
    public enum Error: Swift.Error, Sendable {
        case resourceNotFound
        case downloadFailed(String)
        case invalidResponse
    }

    /// Loads the embedded Ultra-Compact database shipped as a SwiftPM resource.
    /// Place the file at `Sources/SwiftIP2ASN/Resources/ip2asn.ultra`.
    public static func loadUltraCompact() throws -> UltraCompactDatabase {
        guard let url = Bundle.module.url(forResource: "ip2asn", withExtension: "ultra") else {
            throw Error.resourceNotFound
        }
        return try UltraCompactDatabase(path: url.path)
    }
}

// MARK: - RemoteDatabase

/// Fetches and caches the IP2ASN database from a remote URL.
///
/// The database is cached permanently to disk and NEVER re-fetched once downloaded.
/// Use `refresh()` to check for updates (issues HEAD request, only downloads if changed).
///
/// Apps can ship with a bundled database for offline-first operation:
/// ```swift
/// let remote = RemoteDatabase(
///     bundledDatabasePath: Bundle.main.path(forResource: "ip2asn", ofType: "ultra")
/// )
/// let db = try await remote.load()  // Uses bundled DB if no cache exists
/// try await remote.refresh()         // Check for updates in background
/// ```
public actor RemoteDatabase {
    /// Default URL for the latest IP2ASN database.
    public static let defaultURL = URL(string: "https://pkgs.networkweather.com/db/ip2asn.ultra")!

    private let cacheURL: URL
    private let metadataURL: URL
    private let remoteURL: URL
    private let bundledDatabasePath: String?
    private var cachedDatabase: UltraCompactDatabase?

    /// Creates a RemoteDatabase fetcher.
    /// - Parameters:
    ///   - remoteURL: URL to fetch the database from (defaults to pkgs.networkweather.com)
    ///   - cacheDirectory: Directory to store the cached database (defaults to Application Support)
    ///   - bundledDatabasePath: Path to a database bundled with the app. Used as fallback when no
    ///     cached database exists, allowing offline-first operation. The app can later call
    ///     `refresh()` to check for updates.
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

    /// Loads the database using this priority:
    /// 1. In-memory cache (if already loaded)
    /// 2. Disk cache (from previous download)
    /// 3. Bundled database (if provided in init)
    /// 4. Remote fetch (downloads from network)
    ///
    /// Once loaded, the database is cached in memory. Call `refresh()` to check for updates.
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

    /// Result of a refresh check.
    public enum RefreshResult: Sendable {
        case alreadyCurrent
        case updated(UltraCompactDatabase)
    }

    /// Checks for updates and downloads only if the remote database has changed.
    /// Uses ETag/Last-Modified headers to avoid unnecessary downloads.
    ///
    /// If using a bundled database (no previous download), this will always download
    /// since we don't know the bundled database's version.
    ///
    /// - Returns: `.alreadyCurrent` if no update needed, `.updated(db)` if new database was downloaded
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

    /// Returns true if a cached database exists on disk.
    public func isCached() -> Bool {
        FileManager.default.fileExists(atPath: cacheURL.path)
    }

    /// Deletes the cached database, forcing a re-fetch on next load().
    public func clearCache() throws {
        cachedDatabase = nil
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            try FileManager.default.removeItem(at: metadataURL)
        }
    }

    /// Returns the path to the cached database file, if it exists.
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
