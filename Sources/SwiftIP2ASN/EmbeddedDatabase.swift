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
/// Use `forceRefresh()` to explicitly update the cached database.
public actor RemoteDatabase {
    /// Default URL for the latest IP2ASN database.
    public static let defaultURL = URL(string: "https://pkgs.networkweather.com/db/ip2asn.ultra")!

    private let cacheURL: URL
    private let remoteURL: URL
    private var cachedDatabase: UltraCompactDatabase?

    /// Creates a RemoteDatabase fetcher.
    /// - Parameters:
    ///   - remoteURL: URL to fetch the database from (defaults to pkgs.networkweather.com)
    ///   - cacheDirectory: Directory to store the cached database (defaults to Application Support)
    public init(
        remoteURL: URL = RemoteDatabase.defaultURL,
        cacheDirectory: URL? = nil
    ) {
        self.remoteURL = remoteURL

        let cacheDir =
            cacheDirectory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent("SwiftIP2ASN", isDirectory: true)

        self.cacheURL = cacheDir.appendingPathComponent("ip2asn.ultra")
    }

    /// Loads the database, fetching from remote only if not already cached.
    /// Once cached, the database is NEVER re-fetched automatically.
    public func load() async throws -> UltraCompactDatabase {
        // Return in-memory cache if available
        if let db = cachedDatabase {
            return db
        }

        // Check disk cache
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            let db = try UltraCompactDatabase(path: cacheURL.path)
            cachedDatabase = db
            return db
        }

        // Fetch from remote (only happens once per device)
        return try await fetchAndCache()
    }

    /// Forces a refresh of the cached database from the remote URL.
    /// Use sparingly - the database updates infrequently.
    @discardableResult
    public func forceRefresh() async throws -> UltraCompactDatabase {
        return try await fetchAndCache()
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
    }

    /// Returns the path to the cached database file, if it exists.
    public func cachePath() -> String? {
        FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL.path : nil
    }

    // MARK: - Private

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

        // Load and cache in memory
        let db = try UltraCompactDatabase(data: data)
        cachedDatabase = db
        return db
    }
}
