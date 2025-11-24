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

    func testRemoteDatabaseCaching() async throws {
        // Use a temp directory for testing
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftIP2ASNTest-\(UUID().uuidString)")

        let remote = RemoteDatabase(cacheDirectory: tempDir)

        // Should not be cached initially
        let isCachedBefore = await remote.isCached()
        XCTAssertFalse(isCachedBefore, "Should not be cached before first load")

        // First load fetches from network
        let db = try await remote.load()
        XCTAssertGreaterThan(db.entryCount, 100_000, "Should have substantial entries")

        // Should be cached now
        let isCachedAfter = await remote.isCached()
        XCTAssertTrue(isCachedAfter, "Should be cached after load")

        // Verify lookups work
        let result = db.lookup("8.8.8.8")
        XCTAssertEqual(result?.asn, 15169, "Google DNS should be AS15169")

        // Second load should use cache (no network)
        let db2 = try await remote.load()
        XCTAssertEqual(db2.entryCount, db.entryCount, "Cached DB should match")

        // Refresh should report already current (HEAD request only, no download)
        let refreshResult = try await remote.refresh()
        switch refreshResult {
        case .alreadyCurrent:
            break  // Expected
        case .updated:
            XCTFail("Should not have downloaded again - database hasn't changed")
        case .noCacheToRefresh:
            XCTFail("Cache should exist")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
}
