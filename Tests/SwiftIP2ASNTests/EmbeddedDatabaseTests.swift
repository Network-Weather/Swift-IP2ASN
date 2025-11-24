import XCTest

@testable import SwiftIP2ASN

final class EmbeddedDatabaseTests: XCTestCase {
    func testEmbeddedUltraLookups() throws {
        // Try to load the embedded Ultra DB; skip if not present
        let db: UltraCompactDatabase
        do {
            db = try EmbeddedDatabase.loadUltraCompact()
        } catch {
            throw XCTSkip("Embedded ip2asn.ultra not present; skipping embedded DB checks")
        }

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
}

// MARK: - IP2ASN Simple API Tests

final class IP2ASNSimpleAPITests: XCTestCase {

    func testIP2ASNEmbedded() throws {
        // Test the simple embedded() API
        let db = try IP2ASN.embedded()

        XCTAssertGreaterThan(db.entryCount, 100_000, "Should have substantial entries")

        // Test lookups
        let google = db.lookup("8.8.8.8")
        XCTAssertNotNil(google)
        XCTAssertEqual(google?.asn, 15169)

        let cloudflare = db.lookup("1.1.1.1")
        XCTAssertNotNil(cloudflare)
        XCTAssertEqual(cloudflare?.asn, 13335)
    }

    func testIP2ASNRemote() async throws {
        // Test the simple remote() API
        let db = try await IP2ASN.remote()

        XCTAssertGreaterThan(db.entryCount, 100_000, "Should have substantial entries")

        // Test lookup
        let google = db.lookup("8.8.8.8")
        XCTAssertNotNil(google)
        XCTAssertEqual(google?.asn, 15169)

        // Test that cache exists after load
        let cached = await IP2ASN.isCached()
        XCTAssertTrue(cached, "Should be cached after remote load")
    }

    func testIP2ASNRefresh() async throws {
        // First load
        _ = try await IP2ASN.remote()

        // Refresh should report already current (no changes)
        let result = try await IP2ASN.refresh()
        switch result {
        case .alreadyCurrent:
            break  // Expected
        case .updated:
            break  // Also acceptable if CDN updated
        }
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

// MARK: - RemoteDatabaseTests

final class RemoteDatabaseTests: XCTestCase {

    private func createTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftIP2ASNTest-\(UUID().uuidString)")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Basic Caching Tests

    func testRemoteDatabaseInitialState() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = RemoteDatabase(cacheDirectory: tempDir)

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

        let remote = RemoteDatabase(cacheDirectory: tempDir)

        // First load fetches from network
        let db = try await remote.load()
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

        let remote = RemoteDatabase(cacheDirectory: tempDir)

        // First load
        let db1 = try await remote.load()
        let count1 = db1.entryCount

        // Second load should use cache (same instance)
        let db2 = try await remote.load()
        XCTAssertEqual(db2.entryCount, count1, "Cached DB should match")

        // Create new instance pointing to same cache
        let remote2 = RemoteDatabase(cacheDirectory: tempDir)
        let db3 = try await remote2.load()
        XCTAssertEqual(db3.entryCount, count1, "New instance should use disk cache")
    }

    func testRemoteDatabaseClearCache() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = RemoteDatabase(cacheDirectory: tempDir)

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

    // MARK: - Refresh Tests

    func testRemoteDatabaseRefreshAlreadyCurrent() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = RemoteDatabase(cacheDirectory: tempDir)

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
    }

    func testRemoteDatabaseRefreshAfterClearDownloadsAgain() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = RemoteDatabase(cacheDirectory: tempDir)

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

    // MARK: - Bundled Database Tests

    func testBundledDatabaseFallback() async throws {
        guard let bundledPath = Bundle.module.url(forResource: "ip2asn", withExtension: "ultra")?.path
        else {
            throw XCTSkip("No embedded database to test with")
        }

        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = RemoteDatabase(
            cacheDirectory: tempDir,
            bundledDatabasePath: bundledPath
        )

        // Should not have a cached download
        let isCachedBefore = await remote.isCached()
        XCTAssertFalse(isCachedBefore, "Should not have cache initially")

        // Load should use bundled database (no network)
        let db = try await remote.load()
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

        let remote = RemoteDatabase(
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
        let remote2 = RemoteDatabase(
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
        let remote1 = RemoteDatabase(cacheDirectory: tempDir)
        let downloadedDB = try await remote1.load()
        let downloadedCount = downloadedDB.entryCount
        let isCached1 = await remote1.isCached()
        XCTAssertTrue(isCached1, "Should have cache")

        // Now create instance with bundled path - should still use cache
        let remote2 = RemoteDatabase(
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

        let remote = RemoteDatabase(
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

        let remote = RemoteDatabase(cacheDirectory: tempDir)
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

        let remote = RemoteDatabase(cacheDirectory: tempDir)
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

        let remote = RemoteDatabase(cacheDirectory: tempDir)
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
        let remote = RemoteDatabase(cacheDirectory: tempDir)
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

        let remote = RemoteDatabase(cacheDirectory: tempDir)

        // Multiple concurrent loads should all succeed and return same data
        async let db1 = remote.load()
        async let db2 = remote.load()
        async let db3 = remote.load()

        let (r1, r2, r3) = try await (db1, db2, db3)

        XCTAssertEqual(r1.entryCount, r2.entryCount)
        XCTAssertEqual(r2.entryCount, r3.entryCount)
    }

    func testRemoteDatabaseConcurrentLookups() async throws {
        let tempDir = createTempDir()
        defer { cleanup(tempDir) }

        let remote = RemoteDatabase(cacheDirectory: tempDir)
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
}
