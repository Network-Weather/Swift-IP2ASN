import Foundation
import Testing

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

@Suite("Typed ASN lookup results")
struct ASNLookupResultTests {
    @Test("Typed lookups support strings, parsed addresses, and raw values")
    func supportsAllAddressInputs() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let database = try UltraCompactDatabase(path: fixture.database.path)
        let expectedIPv4 = ASNLookupResult(asn: 64_501, name: "Example IPv4 Network")
        let expectedIPv6 = ASNLookupResult(asn: 64_502, name: "Example IPv6 Network")

        #expect(database.lookupResult("198.51.100.10") == expectedIPv4)
        #expect(database.lookupResult("198.51.100.20") == expectedIPv4)
        #expect(database.lookupResult(ip: 0xC633_640F) == expectedIPv4)
        #expect(database.lookupResult(try #require(IPAddress(string: "198.51.100.15"))) == expectedIPv4)

        #expect(database.lookupResult("2001:db8::100") == expectedIPv6)
        #expect(database.lookupResult("2001:db8::1ff") == expectedIPv6)
        #expect(database.lookupResultV6(hi: 0x2001_0DB8_0000_0000, lo: 0x0000_0000_0000_0180) == expectedIPv6)
        #expect(database.lookupResult(try #require(IPAddress(string: "2001:db8::180"))) == expectedIPv6)
    }

    @Test("Typed and tuple APIs preserve identical hit and miss behavior")
    func preservesLegacyBehavior() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let database = try UltraCompactDatabase(path: fixture.database.path)

        for address in ["198.51.100.9", "198.51.100.10", "198.51.100.20", "198.51.100.21", "invalid"] {
            let typed = database.lookupResult(address)
            let legacy = database.lookup(address)
            #expect(typed?.asn == legacy?.asn)
            #expect(typed?.name == legacy?.name)
        }

        #expect(database.lookupResult("10.0.0.1") == nil)
        #expect(database.lookupResult("::1") == nil)
    }

    @Test("Lookup results are Codable, Hashable, and Sendable")
    func supportsValueSemantics() async throws {
        let result = ASNLookupResult(asn: 15_169, name: "GOOGLE")
        let encoded = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode(ASNLookupResult.self, from: encoded) == result)
        #expect(Set([result, result]).count == 1)

        let detachedResult = await Task.detached { result }.value
        #expect(detachedResult == result)
    }

    private func makeFixture() throws -> (directory: URL, database: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftIP2ASN-LookupResultTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let ipv4 = directory.appendingPathComponent("ipv4.tsv")
        let ipv6 = directory.appendingPathComponent("ipv6.tsv")
        let database = directory.appendingPathComponent("fixture.ultra")
        try "198.51.100.10\t198.51.100.20\t64501\tZZ\tExample IPv4 Network"
            .write(to: ipv4, atomically: true, encoding: .utf8)
        try "2001:db8::100\t2001:db8::1ff\t64502\tZZ\tExample IPv6 Network"
            .write(to: ipv6, atomically: true, encoding: .utf8)
        try UltraCompactBuilder.createUltraCompact(
            ipv4TSV: ipv4.path,
            ipv6TSV: ipv6.path,
            to: database.path
        )
        return (directory, database)
    }
}
