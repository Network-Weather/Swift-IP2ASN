import XCTest

@testable import SwiftIP2ASN

/// Requires an explicit opt-in, then probes the default CDN URL once per process
/// so live smoke tests skip cleanly when the network is unavailable.
enum SkipIfCDNUnavailable {
    private actor State {
        var result: Result<Void, Error>?
        func decide() async -> Result<Void, Error> {
            if let r = result { return r }
            var req = URLRequest(url: RemoteDatabase.defaultURL)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 10
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    result = .success(())
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    result = .failure(XCTSkip("CDN \(RemoteDatabase.defaultURL) returned HTTP \(code); skipping network-dependent test"))
                }
            } catch {
                result = .failure(XCTSkip("CDN \(RemoteDatabase.defaultURL) unreachable: \(error.localizedDescription)"))
            }
            return result!
        }
    }
    private static let shared = State()

    static func ensure() async throws {
        guard ProcessInfo.processInfo.environment["IP2ASN_RUN_NETWORK"] == "1" else {
            throw XCTSkip("Live CDN smoke tests disabled; set IP2ASN_RUN_NETWORK=1 to enable")
        }
        switch await shared.decide() {
        case .success: return
        case .failure(let error): throw error
        }
    }
}

final class EmbeddedDatabaseTests: XCTestCase {

    /// Verifies that loadUltraCompact() throws .resourceNotFound (not fatalError)
    /// when the resource bundle doesn't contain ip2asn.ultra.
    /// Regression test for https://github.com/Network-Weather/Swift-IP2ASN/issues/1
    func testLoadUltraCompactThrowsResourceNotFoundForMissingBundle() throws {
        // Use the test target's bundle, which doesn't contain ip2asn.ultra
        let emptyBundle = Bundle(for: type(of: self))
        XCTAssertThrowsError(try EmbeddedDatabase.loadUltraCompact(from: emptyBundle)) { error in
            guard case EmbeddedDatabase.Error.resourceNotFound = error else {
                XCTFail("Expected .resourceNotFound, got \(error)")
                return
            }
        }
    }

    /// Packaging integrity check: verifies the resource bundle and database are
    /// present, loadable, and contain a reasonable number of entries.
    /// This test hard-fails (not XCTSkip) because a missing database means a
    /// broken release that will crash or degrade at runtime.
    func testEmbeddedDatabasePackagingIntegrity() throws {
        // 1. safeModule must find the resource bundle
        let bundle = Bundle.safeModule
        XCTAssertNotNil(bundle, "Bundle.safeModule should locate SwiftIP2ASN_SwiftIP2ASN.bundle")

        // 2. The .ultra resource must exist inside it
        let url = bundle?.url(forResource: "ip2asn", withExtension: "ultra")
        XCTAssertNotNil(url, "ip2asn.ultra must be present in the resource bundle")

        // 3. File should be non-trivial (current DB is ~3.4 MB)
        if let path = url?.path {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let size = attrs[.size] as? UInt64 ?? 0
            XCTAssertGreaterThan(size, 1_000_000, "ip2asn.ultra should be >1 MB (got \(size) bytes)")
        }

        // 4. Database must load and contain substantial data
        let db = try EmbeddedDatabase.loadUltraCompact()
        XCTAssertGreaterThan(db.entryCount, 100_000,
            "Embedded DB should have >100k entries (got \(db.entryCount))")
        XCTAssertGreaterThan(db.uniqueASNCount, 10_000,
            "Embedded DB should have >10k unique ASNs (got \(db.uniqueASNCount))")
    }

    func testEmbeddedUltraLookups() throws {
        let db = try EmbeddedDatabase.loadUltraCompact()

        // Canonical IPs that should be present in a current full DB
        let cases: [(String, UInt32)] = [
            ("8.8.8.8", 15169),  // Google
            ("1.1.1.1", 13335),  // Cloudflare
            ("52.84.228.25", 16509),  // Amazon CloudFront
            ("140.82.121.3", 36459)  // GitHub
        ]

        for (ip, expected) in cases {
            let result = db.lookup(ip)
            XCTAssertNotNil(result, "Embedded DB should contain \(ip)")
            XCTAssertEqual(result?.asn, expected, "\(ip) should be AS\(expected)")
        }
    }

    func testEmbeddedUltraIPv6Lookups() throws {
        let db = try EmbeddedDatabase.loadUltraCompact()

        XCTAssertGreaterThan(db.ipv6EntryCount, 0, "Embedded DB should contain IPv6 ranges")

        // Stable, well-known dual-stack endpoints
        let cases: [(String, UInt32)] = [
            ("2001:4860:4860::8888", 15169),  // Google Public DNS
            ("2606:4700:4700::1111", 13335)   // Cloudflare 1.1.1.1
        ]

        for (ip, expected) in cases {
            let result = db.lookup(ip)
            XCTAssertNotNil(result, "Embedded DB should contain \(ip)")
            XCTAssertEqual(result?.asn, expected, "\(ip) should be AS\(expected)")
        }

        // ::1 (loopback) is not advertised in BGP and should miss
        XCTAssertNil(db.lookup("::1"), "Loopback should not resolve")
    }
}

// MARK: - IP2ASN Simple API Tests

final class IP2ASNSimpleAPITests: XCTestCase {

    func testSharedStateReusesOnlyTheSelectedConfiguration() async {
        let state = IP2ASNSharedState()

        let defaultDatabase = await state.database(bundledPath: nil)
        let repeatedDefaultDatabase = await state.database(bundledPath: nil)
        let activeDefaultDatabase = await state.databaseForActiveConfiguration()
        XCTAssertTrue(defaultDatabase === repeatedDefaultDatabase)
        XCTAssertTrue(defaultDatabase === activeDefaultDatabase)

        let firstBundledDatabase = await state.database(bundledPath: "/tmp/first.ultra")
        let repeatedFirstBundledDatabase = await state.database(bundledPath: "/tmp/first.ultra")
        let activeFirstBundledDatabase = await state.databaseForActiveConfiguration()
        XCTAssertFalse(defaultDatabase === firstBundledDatabase)
        XCTAssertTrue(firstBundledDatabase === repeatedFirstBundledDatabase)
        XCTAssertTrue(firstBundledDatabase === activeFirstBundledDatabase)

        let secondBundledDatabase = await state.database(bundledPath: "/tmp/second.ultra")
        let activeSecondBundledDatabase = await state.databaseForActiveConfiguration()
        XCTAssertFalse(firstBundledDatabase === secondBundledDatabase)
        XCTAssertTrue(secondBundledDatabase === activeSecondBundledDatabase)

        let reselectedDefaultDatabase = await state.database(bundledPath: nil)
        let activeReselectedDefaultDatabase = await state.databaseForActiveConfiguration()
        XCTAssertFalse(secondBundledDatabase === reselectedDefaultDatabase)
        XCTAssertFalse(defaultDatabase === reselectedDefaultDatabase)
        XCTAssertTrue(reselectedDefaultDatabase === activeReselectedDefaultDatabase)
    }

    func testIP2ASNEmbedded() throws {
        // Test the simple embedded() API
        let db = try IP2ASN.embedded()

        XCTAssertGreaterThan(db.entryCount, 100_000, "Should have substantial entries")
        XCTAssertEqual(db.origin, .embedded)
        XCTAssertEqual(db.metadata.ipv4RangeCount, db.ipv4EntryCount)
        XCTAssertEqual(db.metadata.ipv6RangeCount, db.ipv6EntryCount)
        XCTAssertEqual(db.metadata.buildIdentifier.count, 64)

        // Test lookups
        let google = db.lookup("8.8.8.8")
        XCTAssertNotNil(google)
        XCTAssertEqual(google?.asn, 15169)

        let cloudflare = db.lookup("1.1.1.1")
        XCTAssertNotNil(cloudflare)
        XCTAssertEqual(cloudflare?.asn, 13335)
    }

    func testUltraCompactDatabaseIsSendable() async throws {
        // Verify UltraCompactDatabase can be passed across actor boundaries
        let db = try IP2ASN.embedded()

        // Pass to a detached task (crosses actor boundary)
        let result = await Task.detached {
            // This compiles only if UltraCompactDatabase is Sendable
            return db.lookup("8.8.8.8")?.asn
        }.value

        XCTAssertEqual(result, 15169, "Should work across actor boundaries")
    }
}

final class RemoteDatabaseLiveCDNSmokeTests: XCTestCase {
    override func setUp() async throws {
        try await SkipIfCDNUnavailable.ensure()
    }

    func testIP2ASNRemote() async throws {
        let db = try await IP2ASN.remote()

        XCTAssertGreaterThan(db.entryCount, 100_000, "Should have substantial entries")
        XCTAssertEqual(db.lookup("8.8.8.8")?.asn, 15169)
        let cached = await IP2ASN.isCached()
        XCTAssertTrue(cached, "Should be cached after remote load")
    }

    func testIP2ASNRefresh() async throws {
        _ = try await IP2ASN.remote()

        let result = try await IP2ASN.refresh()
        switch result {
        case .alreadyCurrent, .updated:
            break
        }
    }
}

// MARK: - RemoteDatabaseTests

private actor StubRemoteDatabaseHTTPTransport: RemoteDatabaseHTTPTransport {
    struct Configuration: Sendable {
        let databaseData: Data
        let getStatusCode: Int
        let headStatusCode: Int
        let headers: [String: String]
        let error: URLError?
        let delayNanoseconds: UInt64

        init(
            databaseData: Data,
            getStatusCode: Int = 200,
            headStatusCode: Int = 200,
            headers: [String: String] = [
                "ETag": "\"fixture-v1\"",
                "Last-Modified": "Sun, 30 Aug 2026 00:00:00 GMT"
            ],
            error: URLError? = nil,
            delayNanoseconds: UInt64 = 0
        ) {
            self.databaseData = databaseData
            self.getStatusCode = getStatusCode
            self.headStatusCode = headStatusCode
            self.headers = headers
            self.error = error
            self.delayNanoseconds = delayNanoseconds
        }
    }

    private let configuration: Configuration
    private var requests: [URLRequest] = []

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        if configuration.delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: configuration.delayNanoseconds)
        }

        if let error = configuration.error {
            throw error
        }

        let isHead = request.httpMethod == "HEAD"
        let statusCode = isHead ? configuration.headStatusCode : configuration.getStatusCode
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: configuration.headers
        )!
        return (isHead ? Data() : configuration.databaseData, response)
    }

    func requestedMethods() -> [String] {
        requests.map { $0.httpMethod ?? "GET" }
    }
}

final class RemoteDatabaseTests: XCTestCase {

    private let fixtureRemoteURL = URL(string: "https://fixture.invalid/ip2asn.ultra")!

    private func createTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftIP2ASNTest-\(UUID().uuidString)")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func embeddedDatabaseData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "ip2asn", withExtension: "ultra") else {
            throw XCTSkip("No embedded database fixture")
        }
        return try Data(contentsOf: url)
    }

    private func makeRemote(
        cacheDirectory: URL,
        bundledDatabasePath: String? = nil
    ) throws -> RemoteDatabase {
        try makeRemoteAndTransport(
            cacheDirectory: cacheDirectory,
            bundledDatabasePath: bundledDatabasePath
        ).remote
    }

    private func makeRemoteAndTransport(
        cacheDirectory: URL,
        bundledDatabasePath: String? = nil,
        configuration: StubRemoteDatabaseHTTPTransport.Configuration? = nil
    ) throws -> (remote: RemoteDatabase, transport: StubRemoteDatabaseHTTPTransport) {
        let resolvedConfiguration: StubRemoteDatabaseHTTPTransport.Configuration
        if let configuration {
            resolvedConfiguration = configuration
        } else {
            resolvedConfiguration = StubRemoteDatabaseHTTPTransport.Configuration(
                databaseData: try embeddedDatabaseData()
            )
        }
        let transport = StubRemoteDatabaseHTTPTransport(configuration: resolvedConfiguration)
        let remote = RemoteDatabase(
            remoteURL: fixtureRemoteURL,
            cacheDirectory: cacheDirectory,
            bundledDatabasePath: bundledDatabasePath,
            httpTransport: transport
        )
        return (remote, transport)
    }

    // MARK: - Basic Caching Tests

    func testRemoteDatabaseInitialState() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)

        // Should not be cached initially
        let isCached = await remote.isCached()
        XCTAssertFalse(isCached, "New RemoteDatabase should not have cache")

        // Cache path should be nil
        let path = await remote.cachePath()
        XCTAssertNil(path, "Cache path should be nil when not cached")
    }

    func testRemoteDatabaseFetchAndCache() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)

        // First load fetches from network
        let db = try await remote.load()
        XCTAssertEqual(db.origin, .downloaded)
        XCTAssertGreaterThan(db.entryCount, 100_000, "Should have substantial entries")
        XCTAssertGreaterThan(db.uniqueASNCount, 10_000, "Should have many unique ASNs")

        // Should be cached now
        let isCached = await remote.isCached()
        XCTAssertTrue(isCached, "Should be cached after load")

        // Cache path should exist
        let path = await remote.cachePath()
        XCTAssertNotNil(path, "Cache path should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path!), "Cache file should exist")
    }

    func testRemoteDatabaseUsesCache() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)

        // First load
        let db1 = try await remote.load()
        XCTAssertEqual(db1.origin, .downloaded)
        let count1 = db1.entryCount

        // Second load should use cache (same instance)
        let db2 = try await remote.load()
        XCTAssertEqual(db2.entryCount, count1, "Cached DB should match")

        // Create new instance pointing to same cache
        let remote2 = try makeRemote(cacheDirectory: tempDir)
        let db3 = try await remote2.load()
        XCTAssertEqual(db3.origin, .diskCache)
        XCTAssertEqual(db3.entryCount, count1, "New instance should use disk cache")
    }

    func testRemoteDatabaseUsesValidCacheWhenMetadataWriteIsMissing() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)
        let downloadedDatabase = try await remote.load()

        let metadataURL = tempDir.appendingPathComponent("ip2asn.meta.json")
        try FileManager.default.removeItem(at: metadataURL)

        let (reloadedRemote, transport) = try makeRemoteAndTransport(cacheDirectory: tempDir)
        let reloadedDatabase = try await reloadedRemote.load()

        XCTAssertEqual(reloadedDatabase.entryCount, downloadedDatabase.entryCount)
        let requestedMethods = await transport.requestedMethods()
        XCTAssertTrue(requestedMethods.isEmpty, "A valid cache should not require metadata to load")
    }

    func testRemoteDatabaseClearCache() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)

        // Load to create cache
        _ = try await remote.load()
        let isCachedBefore = await remote.isCached()
        XCTAssertTrue(isCachedBefore, "Should be cached")

        // Clear cache
        try await remote.clearCache()
        let isCachedAfter = await remote.isCached()
        let cachePathAfter = await remote.cachePath()
        XCTAssertFalse(isCachedAfter, "Should not be cached after clear")
        XCTAssertNil(cachePathAfter, "Cache path should be nil after clear")
    }

    func testRemoteDatabaseClearCacheCancelsInFlightFetch() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let configuration = StubRemoteDatabaseHTTPTransport.Configuration(
            databaseData: try embeddedDatabaseData(),
            delayNanoseconds: 500_000_000
        )
        let (remote, transport) = try makeRemoteAndTransport(
            cacheDirectory: tempDir,
            configuration: configuration
        )

        let loadTask = Task { try await remote.load() }
        for _ in 0..<100 {
            if !(await transport.requestedMethods()).isEmpty {
                break
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let requestedMethods = await transport.requestedMethods()
        XCTAssertEqual(requestedMethods, ["GET"])

        try await remote.clearCache()
        do {
            _ = try await loadTask.value
            XCTFail("Clearing the cache should cancel an in-flight fetch")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let isCached = await remote.isCached()
        let cachePath = await remote.cachePath()
        XCTAssertFalse(isCached)
        XCTAssertNil(cachePath)
    }

    // MARK: - Refresh Tests

    func testRemoteDatabaseRefreshAlreadyCurrent() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let (remote, transport) = try makeRemoteAndTransport(cacheDirectory: tempDir)

        // Load to create cache with metadata
        _ = try await remote.load()

        // Refresh should report already current (HEAD request only)
        let result = try await remote.refresh()
        switch result {
        case .alreadyCurrent:
            break  // Expected
        case .updated:
            XCTFail("Should not download again - database hasn't changed")
        }
        let requestedMethods = await transport.requestedMethods()
        XCTAssertEqual(requestedMethods, ["GET", "HEAD"])
    }

    func testRemoteDatabaseRefreshAfterClearDownloadsAgain() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)

        // Load, then clear
        _ = try await remote.load()
        try await remote.clearCache()

        // Refresh with no cache should download
        let result = try await remote.refresh()
        switch result {
        case .alreadyCurrent:
            XCTFail("Should download since no metadata exists")
        case .updated(let db):
            XCTAssertGreaterThan(db.entryCount, 100_000, "Should have entries")
        }
    }

    func testRemoteDatabaseRefreshWithoutValidatorsDownloadsAgain() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let configuration = StubRemoteDatabaseHTTPTransport.Configuration(
            databaseData: try embeddedDatabaseData(),
            headers: [:]
        )
        let (remote, transport) = try makeRemoteAndTransport(
            cacheDirectory: tempDir,
            configuration: configuration
        )

        _ = try await remote.load()
        let result = try await remote.refresh()
        guard case .updated = result else {
            XCTFail("A server without validators should trigger a new download")
            return
        }
        let requestedMethods = await transport.requestedMethods()
        XCTAssertEqual(requestedMethods, ["GET", "HEAD", "GET"])
    }

    func testRemoteDatabaseRefreshRejectsUnsupportedHead() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let configuration = StubRemoteDatabaseHTTPTransport.Configuration(
            databaseData: try embeddedDatabaseData(),
            headStatusCode: 405
        )
        let (remote, transport) = try makeRemoteAndTransport(
            cacheDirectory: tempDir,
            configuration: configuration
        )

        _ = try await remote.load()
        do {
            _ = try await remote.refresh()
            XCTFail("An unsupported HEAD response should fail refresh")
        } catch EmbeddedDatabase.Error.downloadFailed(let message) {
            XCTAssertTrue(message.contains("HTTP 405"))
        }
        let requestedMethods = await transport.requestedMethods()
        XCTAssertEqual(requestedMethods, ["GET", "HEAD"])
    }

    func testRemoteDatabaseRefreshRejectsUnsolicitedNotModified() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let configuration = StubRemoteDatabaseHTTPTransport.Configuration(
            databaseData: try embeddedDatabaseData(),
            headStatusCode: 304
        )
        let (remote, transport) = try makeRemoteAndTransport(
            cacheDirectory: tempDir,
            configuration: configuration
        )

        _ = try await remote.load()
        do {
            _ = try await remote.refresh()
            XCTFail("A non-conditional HEAD request should not receive HTTP 304")
        } catch EmbeddedDatabase.Error.downloadFailed(let message) {
            XCTAssertTrue(message.contains("HTTP 304"))
        }
        let requestedMethods = await transport.requestedMethods()
        XCTAssertEqual(requestedMethods, ["GET", "HEAD"])
    }

    func testRemoteDatabaseMapsTransportErrorsToDownloadFailure() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let configuration = StubRemoteDatabaseHTTPTransport.Configuration(
            databaseData: Data(),
            error: URLError(.timedOut)
        )
        let (remote, _) = try makeRemoteAndTransport(
            cacheDirectory: tempDir,
            configuration: configuration
        )

        do {
            _ = try await remote.load()
            XCTFail("A transport timeout should fail loading")
        } catch EmbeddedDatabase.Error.downloadFailed(let message) {
            XCTAssertTrue(message.contains("Download failed"))
        }
    }

    func testRemoteDatabaseRejectsServerErrorAndEmptyResponse() async throws {
        let serverErrorDir = createTempDir()
        let emptyResponseDir = createTempDir()
        defer {
            cleanup(serverErrorDir)
            cleanup(emptyResponseDir)
        }

        let serverErrorConfiguration = StubRemoteDatabaseHTTPTransport.Configuration(
            databaseData: Data(),
            getStatusCode: 503
        )
        let (serverErrorRemote, _) = try makeRemoteAndTransport(
            cacheDirectory: serverErrorDir,
            configuration: serverErrorConfiguration
        )
        do {
            _ = try await serverErrorRemote.load()
            XCTFail("A server error should fail loading")
        } catch EmbeddedDatabase.Error.downloadFailed(let message) {
            XCTAssertTrue(message.contains("HTTP 503"))
        }

        let emptyResponseConfiguration = StubRemoteDatabaseHTTPTransport.Configuration(
            databaseData: Data()
        )
        let (emptyResponseRemote, _) = try makeRemoteAndTransport(
            cacheDirectory: emptyResponseDir,
            configuration: emptyResponseConfiguration
        )
        do {
            _ = try await emptyResponseRemote.load()
            XCTFail("An empty response should fail loading")
        } catch EmbeddedDatabase.Error.invalidResponse {
            // Expected.
        }
    }

    // MARK: - Bundled Database Tests

    func testBundledDatabaseFallback() async throws {
        guard let bundledPath = Bundle.module.url(forResource: "ip2asn", withExtension: "ultra")?.path
        else {
            throw XCTSkip("No embedded database to test with")
        }

        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(
            cacheDirectory: tempDir,
            bundledDatabasePath: bundledPath
        )

        // Should not have a cached download
        let isCachedBefore = await remote.isCached()
        XCTAssertFalse(isCachedBefore, "Should not have cache initially")

        // Load should use bundled database (no network)
        let db = try await remote.load()
        XCTAssertEqual(db.origin, .bundled)
        XCTAssertGreaterThan(db.entryCount, 100_000, "Bundled DB should have entries")

        // Still no downloaded cache
        let isCachedAfter = await remote.isCached()
        XCTAssertFalse(isCachedAfter, "Should not have downloaded cache")
    }

    func testBundledDatabaseWithSubsequentRefresh() async throws {
        guard let bundledPath = Bundle.module.url(forResource: "ip2asn", withExtension: "ultra")?.path
        else {
            throw XCTSkip("No embedded database to test with")
        }

        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(
            cacheDirectory: tempDir,
            bundledDatabasePath: bundledPath
        )

        // Load bundled
        _ = try await remote.load()
        let isCachedBeforeRefresh = await remote.isCached()
        XCTAssertFalse(isCachedBeforeRefresh, "Should use bundled, not download")

        // Refresh should download (no metadata from bundled)
        let result = try await remote.refresh()
        switch result {
        case .alreadyCurrent:
            XCTFail("Should download since bundled has no metadata")
        case .updated(let db):
            XCTAssertGreaterThan(db.entryCount, 0, "Should have entries")
            // After refresh, cache should exist
            let isCachedAfterRefresh = await remote.isCached()
            XCTAssertTrue(isCachedAfterRefresh, "Should have cache after refresh")
        }

        // Next load should use downloaded cache, not bundled
        let remote2 = try makeRemote(
            cacheDirectory: tempDir,
            bundledDatabasePath: bundledPath
        )
        let isCached2 = await remote2.isCached()
        XCTAssertTrue(isCached2, "New instance should see cache")
    }

    func testCachedDatabaseTakesPriorityOverBundled() async throws {
        guard let bundledPath = Bundle.module.url(forResource: "ip2asn", withExtension: "ultra")?.path
        else {
            throw XCTSkip("No embedded database to test with")
        }

        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        // First, create a cache by loading without bundled path
        let remote1 = try makeRemote(cacheDirectory: tempDir)
        let downloadedDB = try await remote1.load()
        let downloadedCount = downloadedDB.entryCount
        let isCached1 = await remote1.isCached()
        XCTAssertTrue(isCached1, "Should have cache")

        // Now create instance with bundled path - should still use cache
        let remote2 = try makeRemote(
            cacheDirectory: tempDir,
            bundledDatabasePath: bundledPath
        )
        let isCached2 = await remote2.isCached()
        XCTAssertTrue(isCached2, "Should see existing cache")

        let db = try await remote2.load()
        XCTAssertEqual(db.entryCount, downloadedCount, "Should use cached, not bundled")
    }

    func testInvalidBundledPathFallsBackToNetwork() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(
            cacheDirectory: tempDir,
            bundledDatabasePath: "/nonexistent/path/to/database.ultra"
        )

        // Should fall back to network fetch
        let db = try await remote.load()
        XCTAssertGreaterThan(db.entryCount, 100_000, "Should fetch from network")
        let isCached = await remote.isCached()
        XCTAssertTrue(isCached, "Should cache after network fetch")
    }

    // MARK: - Lookup Tests

    func testRemoteDatabaseLookups() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)
        let db = try await remote.load()

        // Test well-known IPs
        let testCases: [(ip: String, expectedASN: UInt32, description: String)] = [
            ("8.8.8.8", 15169, "Google DNS"),
            ("1.1.1.1", 13335, "Cloudflare DNS"),
            ("140.82.121.3", 36459, "GitHub"),
            ("157.240.22.35", 32934, "Facebook/Meta"),
            ("17.253.144.10", 714, "Apple")
        ]

        for (ip, expectedASN, description) in testCases {
            let result = db.lookup(ip)
            XCTAssertNotNil(result, "\(description) (\(ip)) should be found")
            XCTAssertEqual(result?.asn, expectedASN, "\(ip) should be AS\(expectedASN)")
        }

        // Test that private IPs return ASN 0 ("Not routed")
        let privateIPs = ["192.168.1.1", "10.0.0.1", "172.16.0.1"]
        for ip in privateIPs {
            let result = db.lookup(ip)
            // iptoasn.com includes "Not routed" entries with ASN 0 for private ranges
            if let result = result {
                XCTAssertEqual(result.asn, 0, "Private IP \(ip) should be ASN 0 (not routed)")
            }
            // nil is also acceptable if the range isn't in the database
        }
    }

    func testRemoteDatabaseLookupByUInt32() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)
        let db = try await remote.load()

        // 8.8.8.8 as UInt32: (8 << 24) | (8 << 16) | (8 << 8) | 8 = 134744072
        let googleDNS: UInt32 = 0x08_08_08_08
        let result = db.lookup(ip: googleDNS)
        XCTAssertNotNil(result, "Should find Google DNS by UInt32")
        XCTAssertEqual(result?.asn, 15169, "Should be Google's ASN")
    }

    // MARK: - Performance Tests

    func testRemoteDatabaseLookupPerformance() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)
        let db = try await remote.load()

        // Generate random IPs for testing
        let testIPs: [UInt32] = (0..<1000).map { _ in
            UInt32.random(in: 0x0100_0000...0xDF00_0000)
        }

        measure {
            for ip in testIPs {
                _ = db.lookup(ip: ip)
            }
        }
    }

    func testRemoteDatabaseLoadFromCachePerformance() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        // Pre-populate cache
        let remote = try makeRemote(cacheDirectory: tempDir)
        _ = try await remote.load()

        // Get the cache path and measure loading directly from file
        guard let cachePath = await remote.cachePath() else {
            XCTFail("Cache should exist")
            return
        }

        // Measure loading UltraCompactDatabase directly from cache file
        measure {
            _ = try? UltraCompactDatabase(path: cachePath)
        }
    }

    // MARK: - Concurrency Tests

    func testRemoteDatabaseConcurrentLoads() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let (remote, transport) = try makeRemoteAndTransport(cacheDirectory: tempDir)

        // Multiple concurrent loads should all succeed and return same data
        async let db1 = remote.load()
        async let db2 = remote.load()
        async let db3 = remote.load()

        let (r1, r2, r3) = try await (db1, db2, db3)

        XCTAssertEqual(r1.entryCount, r2.entryCount)
        XCTAssertEqual(r2.entryCount, r3.entryCount)
        let requestedMethods = await transport.requestedMethods()
        XCTAssertEqual(requestedMethods, ["GET"])
    }

    func testRemoteDatabaseConcurrentLoadAndRefreshShareDownload() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let configuration = StubRemoteDatabaseHTTPTransport.Configuration(
            databaseData: try embeddedDatabaseData(),
            delayNanoseconds: 50_000_000
        )
        let (remote, transport) = try makeRemoteAndTransport(
            cacheDirectory: tempDir,
            configuration: configuration
        )

        async let loadedDatabase = remote.load()
        async let refreshResult = remote.refresh()
        let (database, result) = try await (loadedDatabase, refreshResult)

        XCTAssertGreaterThan(database.entryCount, 100_000)
        guard case .updated(let refreshedDatabase) = result else {
            XCTFail("Refresh without existing metadata should report an update")
            return
        }
        XCTAssertEqual(refreshedDatabase.entryCount, database.entryCount)

        let requestedMethods = await transport.requestedMethods()
        XCTAssertEqual(requestedMethods.filter { $0 == "GET" }.count, 1)
        XCTAssertEqual(requestedMethods.filter { $0 == "HEAD" }.count, 1)
    }

    func testRemoteDatabaseConcurrentLookups() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)
        let db = try await remote.load()

        // Concurrent lookups should all work correctly
        await withTaskGroup(of: (UInt32, String?).self) { group in
            let ips: [UInt32] = [0x08_08_08_08, 0x01_01_01_01, 0x8C_52_79_03]

            for ip in ips {
                group.addTask {
                    let result = db.lookup(ip: ip)
                    return (ip, result?.name)
                }
            }

            for await (ip, name) in group {
                XCTAssertNotNil(name, "IP \(ip) should have a name")
            }
        }
    }

    func testRemoteDatabaseSelfHealingCache() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        // Create a corrupted cache file
        let cacheURL = tempDir.appendingPathComponent("ip2asn.ultra")
        let metadataURL = tempDir.appendingPathComponent("ip2asn.meta.json")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "corrupted random data".data(using: .utf8)?.write(to: cacheURL)
        try "{}".data(using: .utf8)?.write(to: metadataURL)

        guard let bundledPath = Bundle.module.url(forResource: "ip2asn", withExtension: "ultra")?.path
        else {
            throw XCTSkip("No embedded database to test with")
        }

        let remote = try makeRemote(
            cacheDirectory: tempDir,
            bundledDatabasePath: bundledPath
        )

        // Load should catch the error, delete the corrupted cache, and fallback to bundled DB
        let db = try await remote.load()
        XCTAssertGreaterThan(db.entryCount, 100_000)

        // Stale cache files should have been removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path), "Corrupted cache file should have been deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path), "Metadata file should have been deleted")
    }

    func testRemoteDatabasePoisoningPrevention() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let configuration = StubRemoteDatabaseHTTPTransport.Configuration(
            databaseData: Data("invalid content".utf8)
        )
        let transport = StubRemoteDatabaseHTTPTransport(configuration: configuration)
        let remote = RemoteDatabase(
            remoteURL: fixtureRemoteURL,
            cacheDirectory: tempDir,
            bundledDatabasePath: nil,
            httpTransport: transport
        )

        // Loading should fail due to invalid format of the downloaded URL
        do {
            _ = try await remote.load()
            XCTFail("Should have failed to load invalid URL database")
        } catch {
            // Expected failure
        }

        // The disk cache should NOT have been written
        let cachePath = tempDir.appendingPathComponent("ip2asn.ultra").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachePath), "Cache should not be written for invalid database")
    }

    func testRemoteDatabaseRejectsTruncatedDatabaseWithoutCaching() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let validData = try embeddedDatabaseData()
        let configuration = StubRemoteDatabaseHTTPTransport.Configuration(
            databaseData: Data(validData.prefix(128))
        )
        let (remote, _) = try makeRemoteAndTransport(
            cacheDirectory: tempDir,
            configuration: configuration
        )

        do {
            _ = try await remote.load()
            XCTFail("A truncated database should fail validation")
        } catch {
            // The format reader owns the specific corruption error.
        }

        let cachePath = tempDir.appendingPathComponent("ip2asn.ultra").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachePath))
    }

    func testRemoteDatabaseRefreshForcesDownloadIfCacheMissing() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = try makeRemote(cacheDirectory: tempDir)

        // Load initially (fetches and caches)
        _ = try await remote.load()
        let isCachedBefore = await remote.isCached()
        XCTAssertTrue(isCachedBefore)

        // Manually delete the cache file but leave the metadata file
        let cacheURL = tempDir.appendingPathComponent("ip2asn.ultra")
        try FileManager.default.removeItem(at: cacheURL)
        let isCachedAfterDelete = await remote.isCached()
        XCTAssertFalse(isCachedAfterDelete)

        // Refresh should see that cache is missing (even if meta matches) and download it again
        let result = try await remote.refresh()
        switch result {
        case .alreadyCurrent:
            XCTFail("Should have updated because the cached file is missing")
        case .updated(let db):
            XCTAssertGreaterThan(db.entryCount, 0)
            let isCachedAfterRefresh = await remote.isCached()
            XCTAssertTrue(isCachedAfterRefresh, "Cache file should be re-downloaded")
        }
    }
}
