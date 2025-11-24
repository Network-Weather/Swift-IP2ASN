import Foundation

// MARK: - EmbeddedDatabase

/// Access to embedded database resources bundled with the package.
public enum EmbeddedDatabase {
    public enum Error: Swift.Error, Sendable {
        case resourceNotFound
    }

    /// Loads the embedded Ultra-Compact database shipped as a SwiftPM resource.
    /// Place the file at `Sources/SwiftIP2ASN/Resources/ip2asn.ultra`.
    public static func loadUltraCompact() throws -> UltraCompactDatabase {
        guard let url = Bundle.module.url(forResource: "ip2asn", withExtension: "ultra") else {
            throw Error.resourceNotFound
        }
        return try UltraCompactDatabase(path: url.path)
    }
}
