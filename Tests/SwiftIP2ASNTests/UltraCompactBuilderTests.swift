import Foundation
import Testing

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

@Suite("Ultra-compact database builder")
struct UltraCompactBuilderTests {
    @Test("ASN 0 rows are omitted and adjacent same-ASN ranges remain lookupable")
    func omitsASNZeroAndSupportsAdjacentSameASNRanges() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let ipv4TSV = temporaryDirectory.appendingPathComponent("ip2asn-v4.tsv")
        let databaseURL = temporaryDirectory.appendingPathComponent("ip2asn.ultra")
        let contents = [
            "10.0.0.0\t10.0.0.3\t0\tZZ\tNot routed",
            "10.0.0.4\t10.0.0.7\t64500\tZZ\tAdjacent Network",
            "10.0.0.8\t10.0.0.11\t64500\tZZ\tAdjacent Network"
        ].joined(separator: "\n")

        try contents.write(to: ipv4TSV, atomically: true, encoding: .utf8)
        try UltraCompactBuilder.createUltraCompact(
            from: ipv4TSV.path,
            to: databaseURL.path
        )

        let database = try UltraCompactDatabase(path: databaseURL.path)
        #expect(database.uniqueASNCount == 1)
        #expect(database.lookup("10.0.0.0") == nil)
        #expect(database.lookup("10.0.0.3") == nil)

        for address in ["10.0.0.4", "10.0.0.7", "10.0.0.8", "10.0.0.11"] {
            let result = try #require(database.lookup(address))
            #expect(result.asn == 64500)
            #expect(result.name == "Adjacent Network")
        }
    }

    @Test("Dual-stack ranges preserve inclusive boundaries and names")
    func buildsDualStackRangesWithBoundariesAndNames() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let ipv4TSV = temporaryDirectory.appendingPathComponent("ip2asn-v4.tsv")
        let ipv6TSV = temporaryDirectory.appendingPathComponent("ip2asn-v6.tsv")
        let databaseURL = temporaryDirectory.appendingPathComponent("ip2asn.ultra")

        try "198.51.100.10\t198.51.100.20\t64501\tZZ\tExample IPv4 Network"
            .write(to: ipv4TSV, atomically: true, encoding: .utf8)
        try "2001:db8::100\t2001:db8::1ff\t64502\tZZ\tExample IPv6 Network"
            .write(to: ipv6TSV, atomically: true, encoding: .utf8)

        try UltraCompactBuilder.createUltraCompact(
            ipv4TSV: ipv4TSV.path,
            ipv6TSV: ipv6TSV.path,
            to: databaseURL.path
        )

        let database = try UltraCompactDatabase(path: databaseURL.path)
        #expect(database.entryCount == 2)
        #expect(database.ipv4EntryCount == 1)
        #expect(database.ipv6EntryCount == 1)
        #expect(database.uniqueASNCount == 2)

        for address in ["198.51.100.10", "198.51.100.20"] {
            let result = try #require(database.lookup(address))
            #expect(result.asn == 64501)
            #expect(result.name == "Example IPv4 Network")
        }
        #expect(database.lookup("198.51.100.9") == nil)
        #expect(database.lookup("198.51.100.21") == nil)

        for address in ["2001:db8::100", "2001:db8::1ff"] {
            let result = try #require(database.lookup(address))
            #expect(result.asn == 64502)
            #expect(result.name == "Example IPv6 Network")
        }
        #expect(database.lookup("2001:db8::ff") == nil)
        #expect(database.lookup("2001:db8::200") == nil)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SwiftIP2ASN-UltraCompactBuilderTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}
