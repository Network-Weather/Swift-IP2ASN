import Foundation
import Testing

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

@Suite("Database build manifest")
struct DatabaseBuildManifestTests {
    @Test("Manifest records exact source and output provenance")
    func recordsProvenance() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftIP2ASN-ManifestTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )

        let sourceArchive = temporaryDirectory.appendingPathComponent("ip2asn-v4.tsv.gz")
        let builderInput = temporaryDirectory.appendingPathComponent("ip2asn-v4.tsv")
        let databaseURL = temporaryDirectory.appendingPathComponent("ip2asn.ultra")
        let manifestURL = temporaryDirectory.appendingPathComponent("ip2asn.manifest.json")
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let input = "203.0.113.0\t203.0.113.255\t64496\tZZ\tDocumentation Network"

        try Data("downloaded archive".utf8).write(to: sourceArchive)
        try input.write(to: builderInput, atomically: true, encoding: .utf8)
        try UltraCompactBuilder.createUltraCompact(
            from: builderInput.path,
            to: databaseURL.path,
            metadata: UltraCompactBuildMetadata(
                generationTimestamp: generatedAt,
                sourceIdentifier: "iptoasn.com"
            )
        )

        let manifest = try DatabaseBuildManifest.create(
            databaseURL: databaseURL,
            sourceInputs: [
                DatabaseBuildManifest.SourceInput(
                    url: try #require(URL(string: "https://iptoasn.com/data/ip2asn-v4.tsv.gz")),
                    downloadedArtifactURL: sourceArchive,
                    builderInputURL: builderInput
                )
            ],
            builderVersion: "test-revision",
            generatedAt: generatedAt
        )
        try manifest.write(to: manifestURL)

        #expect(manifest.schemaVersion == 1)
        #expect(manifest.generatedAt == generatedAt)
        #expect(manifest.builder.name == "Swift-IP2ASN/ip2asn")
        #expect(manifest.builder.version == "test-revision")
        #expect(manifest.sources.count == 1)
        #expect(manifest.sources[0].url == "https://iptoasn.com/data/ip2asn-v4.tsv.gz")
        #expect(manifest.sources[0].downloadedArtifact.byteCount == 18)
        #expect(manifest.sources[0].downloadedArtifact.sha256.count == 64)
        #expect(manifest.sources[0].builderInput.byteCount == input.utf8.count)
        #expect(manifest.sources[0].builderInput.sha256.count == 64)
        #expect(manifest.output.fileName == "ip2asn.ultra")
        #expect(manifest.output.artifact.byteCount > 0)
        #expect(manifest.output.artifact.sha256.count == 64)
        #expect(manifest.output.buildIdentifier.count == 64)
        #expect(manifest.output.artifact.sha256 != manifest.output.buildIdentifier)
        #expect(manifest.output.formatVersion == 2)
        #expect(manifest.output.ipv4RangeCount == 1)
        #expect(manifest.output.ipv6RangeCount == 0)
        #expect(manifest.output.uniqueASNCount == 1)

        let json = try String(contentsOf: manifestURL, encoding: .utf8)
        #expect(json.hasSuffix("\n"))
        #expect(json.contains("\"generatedAt\" : \"2027-01-15T08:00:00Z\""))
        #expect(json.contains("https://iptoasn.com/data/ip2asn-v4.tsv.gz"))
    }

    @Test("Manifest rejects incomplete provenance")
    func rejectsIncompleteProvenance() throws {
        let missingURL = URL(fileURLWithPath: "/does-not-matter")
        #expect(throws: DatabaseBuildManifestError.emptyBuilderVersion) {
            try DatabaseBuildManifest.create(
                databaseURL: missingURL,
                sourceInputs: [],
                builderVersion: "",
                generatedAt: Date(timeIntervalSince1970: 0)
            )
        }
        #expect(throws: DatabaseBuildManifestError.missingSources) {
            try DatabaseBuildManifest.create(
                databaseURL: missingURL,
                sourceInputs: [],
                builderVersion: "revision",
                generatedAt: Date(timeIntervalSince1970: 0)
            )
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftIP2ASN-ManifestMismatch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let inputURL = temporaryDirectory.appendingPathComponent("input.tsv")
        let databaseURL = temporaryDirectory.appendingPathComponent("database.ultra")
        try "203.0.113.0\t203.0.113.255\t64496\tZZ\tDocumentation Network"
            .write(to: inputURL, atomically: true, encoding: .utf8)
        try UltraCompactBuilder.createUltraCompact(
            from: inputURL.path,
            to: databaseURL.path,
            metadata: UltraCompactBuildMetadata(
                generationTimestamp: Date(timeIntervalSince1970: 100),
                sourceIdentifier: "test"
            )
        )
        #expect(throws: DatabaseBuildManifestError.generationTimestampMismatch) {
            try DatabaseBuildManifest.create(
                databaseURL: databaseURL,
                sourceInputs: [
                    DatabaseBuildManifest.SourceInput(
                        url: try #require(URL(string: "https://example.invalid/input.tsv")),
                        downloadedArtifactURL: inputURL,
                        builderInputURL: inputURL
                    )
                ],
                builderVersion: "revision",
                generatedAt: Date(timeIntervalSince1970: 101)
            )
        }
    }
}
