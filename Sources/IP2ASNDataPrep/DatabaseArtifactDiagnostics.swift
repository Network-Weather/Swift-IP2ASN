import Foundation
@_spi(IP2ASNDataPrep) import SwiftIP2ASN

package enum DatabaseArtifactDiagnostics {
    package struct Artifact: Codable, Equatable, Sendable {
        package let byteCount: Int
        package let sha256: String
    }

    package struct Database: Codable, Equatable, Sendable {
        package let buildIdentifier: String
        package let formatVersion: UInt8
        package let generationTimestamp: Date?
        package let sourceIdentifier: String?
        package let ipv4RangeCount: Int
        package let ipv6RangeCount: Int
        package let totalRangeCount: Int
        package let uniqueASNCount: Int
    }

    package struct InspectionReport: Codable, Equatable, Sendable {
        package let schemaVersion: Int
        package let artifact: Artifact
        package let database: Database
    }

    package struct ValidationReport: Codable, Equatable, Sendable {
        package let schemaVersion: Int
        package let valid: Bool
        package let manifestValidated: Bool
        package let artifact: Artifact
        package let database: Database
    }

    package static func inspect(databaseURL: URL) throws -> InspectionReport {
        let data = try Data(contentsOf: databaseURL)
        let database = try UltraCompactDatabase(data: data)
        return report(data: data, database: database)
    }

    package static func validate(
        databaseURL: URL,
        manifestURL: URL? = nil
    ) throws -> ValidationReport {
        let inspection = try inspect(databaseURL: databaseURL)

        if let manifestURL {
            let manifestData = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let manifest: DatabaseBuildManifest
            do {
                manifest = try decoder.decode(DatabaseBuildManifest.self, from: manifestData)
            } catch {
                throw DatabaseArtifactDiagnosticsError.invalidManifest(
                    field: "document",
                    reason: "not valid schema-version 1 JSON"
                )
            }
            try validate(manifest: manifest, against: inspection)
        }

        return ValidationReport(
            schemaVersion: 1,
            valid: true,
            manifestValidated: manifestURL != nil,
            artifact: inspection.artifact,
            database: inspection.database
        )
    }

    package static func encodedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    private static func report(data: Data, database: UltraCompactDatabase) -> InspectionReport {
        InspectionReport(
            schemaVersion: 1,
            artifact: Artifact(
                byteCount: data.count,
                sha256: digest(for: data)
            ),
            database: Database(
                buildIdentifier: database.metadata.buildIdentifier,
                formatVersion: database.metadata.formatVersion,
                generationTimestamp: database.metadata.generationTimestamp,
                sourceIdentifier: database.metadata.sourceIdentifier,
                ipv4RangeCount: database.ipv4EntryCount,
                ipv6RangeCount: database.ipv6EntryCount,
                totalRangeCount: database.entryCount,
                uniqueASNCount: database.uniqueASNCount
            )
        )
    }

    private static func validate(
        manifest: DatabaseBuildManifest,
        against inspection: InspectionReport
    ) throws {
        guard manifest.schemaVersion == DatabaseBuildManifest.currentSchemaVersion else {
            throw mismatch(
                field: "schemaVersion",
                expected: String(DatabaseBuildManifest.currentSchemaVersion),
                actual: String(manifest.schemaVersion)
            )
        }
        guard !manifest.builder.name.isEmpty else {
            throw invalid(field: "builder.name", reason: "must not be empty")
        }
        guard !manifest.builder.version.isEmpty else {
            throw invalid(field: "builder.version", reason: "must not be empty")
        }
        guard !manifest.sources.isEmpty else {
            throw invalid(field: "sources", reason: "must contain at least one source")
        }

        for (index, source) in manifest.sources.enumerated() {
            guard let url = URL(string: source.url), url.scheme?.lowercased() == "https" else {
                throw invalid(field: "sources[\(index)].url", reason: "must be an HTTPS URL")
            }
            try validate(artifact: source.downloadedArtifact, field: "sources[\(index)].downloadedArtifact")
            try validate(artifact: source.builderInput, field: "sources[\(index)].builderInput")
        }
        try validate(artifact: manifest.output.artifact, field: "output.artifact")

        try requireEqual(
            field: "output.artifact.byteCount",
            expected: inspection.artifact.byteCount,
            actual: manifest.output.artifact.byteCount
        )
        try requireEqual(
            field: "output.artifact.sha256",
            expected: inspection.artifact.sha256,
            actual: manifest.output.artifact.sha256
        )
        try requireEqual(
            field: "output.buildIdentifier",
            expected: inspection.database.buildIdentifier,
            actual: manifest.output.buildIdentifier
        )
        try requireEqual(
            field: "output.formatVersion",
            expected: inspection.database.formatVersion,
            actual: manifest.output.formatVersion
        )
        try requireEqual(
            field: "output.ipv4RangeCount",
            expected: inspection.database.ipv4RangeCount,
            actual: manifest.output.ipv4RangeCount
        )
        try requireEqual(
            field: "output.ipv6RangeCount",
            expected: inspection.database.ipv6RangeCount,
            actual: manifest.output.ipv6RangeCount
        )
        try requireEqual(
            field: "output.uniqueASNCount",
            expected: inspection.database.uniqueASNCount,
            actual: manifest.output.uniqueASNCount
        )

        guard let generationTimestamp = inspection.database.generationTimestamp else {
            throw invalid(
                field: "database.generationTimestamp",
                reason: "is required when validating a manifest"
            )
        }
        guard generationTimestamp == manifest.generatedAt else {
            throw mismatch(
                field: "generatedAt",
                expected: ISO8601DateFormatter().string(from: generationTimestamp),
                actual: ISO8601DateFormatter().string(from: manifest.generatedAt)
            )
        }
    }

    private static func validate(
        artifact: DatabaseBuildManifest.Artifact,
        field: String
    ) throws {
        guard artifact.byteCount >= 0 else {
            throw invalid(field: "\(field).byteCount", reason: "must not be negative")
        }
        guard artifact.sha256.count == 64,
            artifact.sha256.allSatisfy({ "0123456789abcdef".contains($0) })
        else {
            throw invalid(field: "\(field).sha256", reason: "must be 64 lowercase hexadecimal characters")
        }
    }

    private static func digest(for data: Data) -> String {
        UltraCompactFormat.buildIdentifierDigest(for: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func requireEqual<T: Equatable>(
        field: String,
        expected: T,
        actual: T
    ) throws {
        guard expected == actual else {
            throw mismatch(field: field, expected: String(describing: expected), actual: String(describing: actual))
        }
    }

    private static func invalid(
        field: String,
        reason: String
    ) -> DatabaseArtifactDiagnosticsError {
        .invalidManifest(field: field, reason: reason)
    }

    private static func mismatch(
        field: String,
        expected: String,
        actual: String
    ) -> DatabaseArtifactDiagnosticsError {
        .manifestMismatch(field: field, expected: expected, actual: actual)
    }
}

package enum DatabaseArtifactDiagnosticsError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidManifest(field: String, reason: String)
    case manifestMismatch(field: String, expected: String, actual: String)

    package var description: String {
        switch self {
        case .invalidManifest(let field, let reason):
            "invalid manifest \(field): \(reason)"
        case .manifestMismatch(let field, let expected, let actual):
            "manifest mismatch for \(field): expected \(expected), got \(actual)"
        }
    }
}
