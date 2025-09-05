import Foundation

public enum EmbeddedDatabase {
    public enum Error: Swift.Error {
        case resourceNotFound
    }

    /// Loads the embedded Ultra-Compact database shipped as a SwiftPM resource.
    /// Place the file at `Sources/SwiftIP2ASN/Resources/ip2asn.ultra`.
    public static func loadUltraCompact() throws -> UltraCompactDatabase {
        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle(for: Sentinel.self)
        #endif

        if let url = bundle.url(forResource: "ip2asn", withExtension: "ultra") {
            return try UltraCompactDatabase(path: url.path)
        }
        throw Error.resourceNotFound
    }
}

private final class Sentinel: NSObject {}
