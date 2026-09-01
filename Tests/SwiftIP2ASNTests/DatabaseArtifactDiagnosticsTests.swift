import Foundation
import Testing

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

@Suite("Database artifact diagnostics")
struct DatabaseArtifactDiagnosticsTests {
    @Test("Inspection and manifest validation report exact artifact metadata")
    func inspectionAndValidation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let inspection = try DatabaseArtifactDiagnostics.inspect(
            databaseURL: fixture.databaseURL
        )
        #expect(inspection.schemaVersion == 1)
        #expect(inspection.artifact.byteCount > 0)
        #expect(inspection.artifact.sha256.count == 64)
        #expect(inspection.database.formatVersion == 2)
        #expect(inspection.database.generationTimestamp == fixture.generatedAt)
        #expect(inspection.database.sourceIdentifier == "test-source")
        #expect(inspection.database.ipv4RangeCount == 1)
        #expect(inspection.database.ipv6RangeCount == 0)
        #expect(inspection.database.totalRangeCount == 1)
        #expect(inspection.database.uniqueASNCount == 1)

        let report = try DatabaseArtifactDiagnostics.validate(
            databaseURL: fixture.databaseURL,
            manifestURL: fixture.manifestURL
        )
        #expect(report.valid)
        #expect(report.manifestValidated)
        #expect(report.artifact == inspection.artifact)
        #expect(report.database == inspection.database)

        let json = try DatabaseArtifactDiagnostics.encodedJSON(report)
        #expect(json.last == 0x0A)
        let object = try #require(
            JSONSerialization.jsonObject(with: json) as? [String: Any]
        )
        #expect(object["valid"] as? Bool == true)
        #expect(object["manifestValidated"] as? Bool == true)
    }

    @Test("Validation without a manifest still parses the complete database")
    func databaseOnlyValidation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let report = try DatabaseArtifactDiagnostics.validate(
            databaseURL: fixture.databaseURL
        )
        #expect(report.valid)
        #expect(!report.manifestValidated)
        #expect(report.database.totalRangeCount == 1)
    }

    @Test("Validation rejects a manifest for different database bytes")
    func rejectsArtifactDigestMismatch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let inspection = try DatabaseArtifactDiagnostics.inspect(
            databaseURL: fixture.databaseURL
        )

        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.manifestURL))
                as? [String: Any]
        )
        var output = try #require(object["output"] as? [String: Any])
        var artifact = try #require(output["artifact"] as? [String: Any])
        artifact["sha256"] = String(repeating: "0", count: 64)
        output["artifact"] = artifact
        object["output"] = output
        try JSONSerialization.data(withJSONObject: object)
            .write(to: fixture.manifestURL, options: .atomic)

        #expect(
            throws: DatabaseArtifactDiagnosticsError.manifestMismatch(
                field: "output.artifact.sha256",
                expected: inspection.artifact.sha256,
                actual: String(repeating: "0", count: 64)
            )
        ) {
            try DatabaseArtifactDiagnostics.validate(
                databaseURL: fixture.databaseURL,
                manifestURL: fixture.manifestURL
            )
        }

        let command = try runCLI([
            "validate",
            fixture.databaseURL.path,
            fixture.manifestURL.path
        ])
        #expect(command.status == 1)
        #expect(command.stdout.isEmpty)
        #expect(command.stderr.contains("manifest mismatch for output.artifact.sha256"))
    }

    @Test("Public CLI supports a bare IP and bundled validation")
    func publicCLI() throws {
        let help = try runCLI(["--help"])
        #expect(help.status == 0)
        #expect(help.stdout.contains("ip2asn lookup <ip>"))

        let lookup = try runCLI(["1.1.1.1"])
        #expect(lookup.status == 0)
        #expect(lookup.stdout == "AS13335 CLOUDFLARENET\n")
        #expect(lookup.stderr.isEmpty)

        let explicitLookup = try runCLI(["lookup", "2606:4700:4700::1111"])
        #expect(explicitLookup.status == 0)
        #expect(explicitLookup.stdout == "AS13335 CLOUDFLARENET\n")

        let inspection = try runCLI(["inspect"])
        #expect(inspection.status == 0)
        let inspectionObject = try #require(
            JSONSerialization.jsonObject(with: Data(inspection.stdout.utf8))
                as? [String: Any]
        )
        #expect(inspectionObject["schemaVersion"] as? Int == 1)

        let validation = try runCLI(["validate"])
        #expect(validation.status == 0)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(validation.stdout.utf8))
                as? [String: Any]
        )
        #expect(object["valid"] as? Bool == true)
        #expect(object["manifestValidated"] as? Bool == true)
    }

    private struct Fixture {
        let directory: URL
        let databaseURL: URL
        let manifestURL: URL
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftIP2ASN-Diagnostics-\(UUID().uuidString)")
            databaseURL = directory.appendingPathComponent("ip2asn.ultra")
            manifestURL = directory.appendingPathComponent("ip2asn.manifest.json")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let inputURL = directory.appendingPathComponent("ip2asn-v4.tsv")
            let archiveURL = directory.appendingPathComponent("ip2asn-v4.tsv.gz")
            try "203.0.113.0\t203.0.113.255\t64496\tZZ\tDocumentation Network"
                .write(to: inputURL, atomically: true, encoding: .utf8)
            try Data("source archive".utf8).write(to: archiveURL)
            try UltraCompactBuilder.createUltraCompact(
                from: inputURL.path,
                to: databaseURL.path,
                metadata: UltraCompactBuildMetadata(
                    generationTimestamp: generatedAt,
                    sourceIdentifier: "test-source"
                )
            )
            let manifest = try DatabaseBuildManifest.create(
                databaseURL: databaseURL,
                sourceInputs: [
                    DatabaseBuildManifest.SourceInput(
                        url: try #require(URL(string: "https://example.com/ip2asn-v4.tsv.gz")),
                        downloadedArtifactURL: archiveURL,
                        builderInputURL: inputURL
                    )
                ],
                builderVersion: "test-revision",
                generatedAt: generatedAt
            )
            try manifest.write(to: manifestURL)
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private struct CommandResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private func runCLI(_ arguments: [String]) throws -> CommandResult {
        let packageDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executableURL =
            packageDirectory
            .appendingPathComponent(".build/debug/ip2asn")
        #expect(FileManager.default.isExecutableFile(atPath: executableURL.path))

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(
                decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ),
            stderr: String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }
}
