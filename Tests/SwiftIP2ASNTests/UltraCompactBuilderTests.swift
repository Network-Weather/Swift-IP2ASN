import Compression
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
        #expect(database.origin == .file)
        #expect(database.metadata.formatVersion == 2)
        #expect(database.metadata.generationTimestamp == nil)
        #expect(database.metadata.sourceIdentifier == nil)
        #expect(database.metadata.ipv4RangeCount == 2)
        #expect(database.metadata.ipv6RangeCount == 0)
        #expect(database.metadata.buildIdentifier.count == 64)
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

    @Test("Metadata is reproducible and remains readable by the released layout")
    func buildsReproducibleMetadataTrailer() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let ipv4TSV = temporaryDirectory.appendingPathComponent("ip2asn-v4.tsv")
        let firstURL = temporaryDirectory.appendingPathComponent("first.ultra")
        let secondURL = temporaryDirectory.appendingPathComponent("second.ultra")
        let changedURL = temporaryDirectory.appendingPathComponent("changed.ultra")
        try "203.0.113.0\t203.0.113.255\t64496\tZZ\tDocumentation Network"
            .write(to: ipv4TSV, atomically: true, encoding: .utf8)

        let generationTimestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let metadata = UltraCompactBuildMetadata(
            generationTimestamp: generationTimestamp,
            sourceIdentifier: "iptoasn.com"
        )
        try UltraCompactBuilder.createUltraCompact(
            from: ipv4TSV.path,
            to: firstURL.path,
            metadata: metadata
        )
        try UltraCompactBuilder.createUltraCompact(
            from: ipv4TSV.path,
            to: secondURL.path,
            metadata: metadata
        )

        let firstData = try Data(contentsOf: firstURL)
        let secondData = try Data(contentsOf: secondURL)
        #expect(firstData == secondData)

        let database = try UltraCompactDatabase(data: firstData)
        #expect(database.origin == .memory)
        #expect(database.metadata.formatVersion == 2)
        #expect(database.metadata.generationTimestamp == generationTimestamp)
        #expect(database.metadata.sourceIdentifier == "iptoasn.com")
        #expect(database.metadata.ipv4RangeCount == 1)
        #expect(database.metadata.ipv6RangeCount == 0)
        #expect(database.metadata.buildIdentifier.count == 64)

        let legacyCounts = try readCountsUsingReleasedLayout(firstData)
        #expect(legacyCounts.ipv4 == 1)
        #expect(legacyCounts.ipv6 == 0)
        #expect(legacyCounts.names == 1)
        #expect(legacyCounts.trailingBytes > 0)

        try UltraCompactBuilder.createUltraCompact(
            from: ipv4TSV.path,
            to: changedURL.path,
            metadata: UltraCompactBuildMetadata(
                generationTimestamp: generationTimestamp,
                sourceIdentifier: "different-source"
            )
        )
        let changedDatabase = try UltraCompactDatabase(path: changedURL.path)
        let changedData = try Data(contentsOf: changedURL)
        #expect(changedDatabase.metadata.buildIdentifier != database.metadata.buildIdentifier)
        #expect(changedData != firstData)
    }

    @Test("Stable build identifiers use standard SHA-256")
    func usesStandardSHA256() {
        let input = Data("abc".utf8)
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(
            StableSHA256.hexDigest(input) == expected
        )
        #expect(StableSHA256.portableDigest(input).map { String(format: "%02x", $0) }.joined() == expected)
    }

    @Test("Invalid build metadata is rejected")
    func rejectsInvalidBuildMetadata() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let ipv4TSV = temporaryDirectory.appendingPathComponent("ip2asn-v4.tsv")
        let databaseURL = temporaryDirectory.appendingPathComponent("ip2asn.ultra")
        try "203.0.113.0\t203.0.113.255\t64496\tZZ\tDocumentation Network"
            .write(to: ipv4TSV, atomically: true, encoding: .utf8)

        #expect(throws: UltraCompactBuilderError.emptySourceIdentifier) {
            try UltraCompactBuilder.createUltraCompact(
                from: ipv4TSV.path,
                to: databaseURL.path,
                metadata: UltraCompactBuildMetadata(
                    generationTimestamp: Date(timeIntervalSince1970: 0),
                    sourceIdentifier: ""
                )
            )
        }
        #expect(throws: UltraCompactBuilderError.invalidGenerationTimestamp) {
            try UltraCompactBuilder.createUltraCompact(
                from: ipv4TSV.path,
                to: databaseURL.path,
                metadata: UltraCompactBuildMetadata(
                    generationTimestamp: Date(timeIntervalSince1970: -1),
                    sourceIdentifier: "iptoasn.com"
                )
            )
        }
    }

    @Test("Streaming reads preserve split UTF-8, CRLF, blank rows, and the final unterminated row")
    func streamingRows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("ranges.tsv")
        let output = directory.appendingPathComponent("out.ultra")
        let prefix = "1.1.1.1\t1.1.1.1\tAS42\t\t"
        let name = String(repeating: "x", count: 65_535 - prefix.utf8.count) + "é"
        try (prefix + name + "\r\n\r\n1.1.1.2\t1.1.1.2\t0\tZZ\tUnrouted")
            .write(to: input, atomically: true, encoding: .utf8)
        let rows = try UltraCompactBuilder.build(ipv4TSV: input.path, ipv6TSV: nil, to: output.path, metadata: nil)
        #expect(rows.total == 3)
        #expect(rows.blank == 1)
        #expect(rows.unrouted == 1)
        let database = try UltraCompactDatabase(path: output.path)
        #expect(database.lookupResult("1.1.1.1") == ASNLookupResult(asn: 42, name: name))
    }

    @Test("A failed build identifies the source row and preserves an existing output")
    func rejectsInvalidSource() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("ranges.tsv")
        let output = directory.appendingPathComponent("out.ultra")
        let original = Data("previous output".utf8)
        try original.write(to: output)
        for (row, reason) in [
            ("1.0.0.256\t1.0.1.0\t42\tZZ\tExample", "endpoint"),
            ("1.0.0.2\t1.0.0.1\t42\tZZ\tExample", "ends before"),
            ("1.0.0.1\t1.0.0.2\t4AS2\tZZ\tExample", "invalid ASN"),
            ("1.0.0.1\t1.0.0.2\t42\tZZ\tExample", "overlaps"),
            ("1.0.0.1\t1.0.0.2", "columns"),
            (String(repeating: "x", count: 1024 * 1024 + 1), "exceeds")
        ] {
            try ("1.0.0.0\t1.0.0.1\t17\tZZ\tFirst\n" + row)
                .write(to: input, atomically: true, encoding: .utf8)
            #expect {
                try UltraCompactBuilder.createUltraCompact(from: input.path, to: output.path)
            } throws: { error in
                String(describing: error).contains("\(input.path):2:")
                    && String(describing: error).contains(reason)
            }
            #expect(try Data(contentsOf: output) == original)
        }
        #expect(throws: TSVInputError.self) {
            try UltraCompactBuilder.createUltraCompact(ipv4TSV: nil, ipv6TSV: nil, to: output.path)
        }
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

    private func readCountsUsingReleasedLayout(
        _ compressed: Data
    ) throws -> (ipv4: UInt32, ipv6: UInt32, names: UInt32, trailingBytes: Int) {
        let capacity = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let written = compressed.withUnsafeBytes { source in
            compression_decode_buffer(
                destination,
                capacity,
                source.bindMemory(to: UInt8.self).baseAddress!,
                compressed.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard written >= 18 else { throw UltraCompactError.decompressionFailed }
        let data = Data(bytes: destination, count: written)

        func uint32LE(at offset: Int) -> UInt32 {
            UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)
        }

        let ipv4Count = uint32LE(at: 6)
        let ipv6Count = uint32LE(at: 10)
        let nameCount = uint32LE(at: 14)
        var offset = 18
        for _ in 0..<ipv4Count {
            offset += 4
            guard UltraCompactFormat.decodeVarint(from: data, offset: &offset) != nil,
                UltraCompactFormat.decodeVarint(from: data, offset: &offset) != nil
            else { throw UltraCompactError.invalidFormat }
        }
        for _ in 0..<ipv6Count {
            offset += 32
            guard UltraCompactFormat.decodeVarint(from: data, offset: &offset) != nil else {
                throw UltraCompactError.invalidFormat
            }
        }
        for _ in 0..<nameCount {
            guard UltraCompactFormat.decodeVarint(from: data, offset: &offset) != nil,
                let length = UltraCompactFormat.decodeVarint(from: data, offset: &offset)
            else { throw UltraCompactError.invalidFormat }
            offset += Int(length)
        }
        return (ipv4Count, ipv6Count, nameCount, data.count - offset)
    }
}
