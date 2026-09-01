import Foundation
@_spi(IP2ASNDataPrep) import SwiftIP2ASN

/// Machine-readable provenance for a generated database artifact.
///
/// Digests detect accidental corruption and make builds auditable. They do not
/// establish authenticity unless the manifest is distributed through a trusted
/// channel or signed independently.
public struct DatabaseBuildManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public struct Builder: Codable, Equatable, Sendable {
        public let name: String
        public let version: String
    }

    public struct Artifact: Codable, Equatable, Sendable {
        public let byteCount: Int
        public let sha256: String
    }

    public struct Source: Codable, Equatable, Sendable {
        public let url: String
        public let downloadedArtifact: Artifact
        public let builderInput: Artifact
    }

    public struct Output: Codable, Equatable, Sendable {
        public let fileName: String
        public let artifact: Artifact
        public let buildIdentifier: String
        public let formatVersion: UInt8
        public let ipv4RangeCount: Int
        public let ipv6RangeCount: Int
        public let uniqueASNCount: Int
    }

    public let schemaVersion: Int
    public let generatedAt: Date
    public let builder: Builder
    public let sources: [Source]
    public let output: Output

    /// Describes one fetched source and the decompressed input passed to the builder.
    public struct SourceInput: Equatable, Sendable {
        public let url: URL
        public let downloadedArtifactURL: URL
        public let builderInputURL: URL

        public init(url: URL, downloadedArtifactURL: URL, builderInputURL: URL) {
            self.url = url
            self.downloadedArtifactURL = downloadedArtifactURL
            self.builderInputURL = builderInputURL
        }
    }

    /// Builds a manifest by hashing the exact source and output bytes on disk.
    public static func create(
        databaseURL: URL,
        sourceInputs: [SourceInput],
        builderVersion: String,
        generatedAt: Date
    ) throws -> DatabaseBuildManifest {
        guard !builderVersion.isEmpty else {
            throw DatabaseBuildManifestError.emptyBuilderVersion
        }
        guard !sourceInputs.isEmpty else {
            throw DatabaseBuildManifestError.missingSources
        }

        let databaseData = try Data(contentsOf: databaseURL)
        let database = try UltraCompactDatabase(data: databaseData)
        guard database.metadata.generationTimestamp == generatedAt else {
            throw DatabaseBuildManifestError.generationTimestampMismatch
        }

        let sources = try sourceInputs.map { source in
            Source(
                url: source.url.absoluteString,
                downloadedArtifact: try artifact(at: source.downloadedArtifactURL),
                builderInput: try artifact(at: source.builderInputURL)
            )
        }

        return DatabaseBuildManifest(
            schemaVersion: currentSchemaVersion,
            generatedAt: generatedAt,
            builder: Builder(
                name: "Swift-IP2ASN/ip2asn",
                version: builderVersion
            ),
            sources: sources,
            output: Output(
                fileName: databaseURL.lastPathComponent,
                artifact: artifact(for: databaseData),
                buildIdentifier: database.metadata.buildIdentifier,
                formatVersion: database.metadata.formatVersion,
                ipv4RangeCount: database.ipv4EntryCount,
                ipv6RangeCount: database.ipv6EntryCount,
                uniqueASNCount: database.uniqueASNCount
            )
        )
    }

    /// Writes stable, sorted JSON suitable for review and publication.
    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    private static func artifact(at url: URL) throws -> Artifact {
        artifact(for: try Data(contentsOf: url))
    }

    private static func artifact(for data: Data) -> Artifact {
        Artifact(
            byteCount: data.count,
            sha256: UltraCompactFormat.buildIdentifierDigest(for: data)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }
}

public enum DatabaseBuildManifestError: Error, Equatable, Sendable {
    case emptyBuilderVersion
    case missingSources
    case generationTimestampMismatch
}
