import Foundation

/// Describes the identity and provenance encoded in an IP-to-ASN database.
///
/// Databases produced before metadata trailers were introduced still expose
/// their format, range counts, and a stable identifier. Their generation time
/// and source identifier are `nil` because those values were not encoded.
public struct DatabaseMetadata: Equatable, Sendable {
    /// ULT2 format version read from the database header.
    public let formatVersion: UInt8

    /// UTC generation time, stored at whole-second precision when available.
    public let generationTimestamp: Date?

    /// Identifier supplied by the database producer, such as `iptoasn.com`.
    public let sourceIdentifier: String?

    /// Number of encoded IPv4 ranges.
    public let ipv4RangeCount: Int

    /// Number of encoded IPv6 ranges.
    public let ipv6RangeCount: Int

    /// Stable SHA-256 identifier for the normalized database build.
    ///
    /// This identifier supports equality and provenance checks. It is not a
    /// signature and does not establish authenticity by itself.
    public let buildIdentifier: String

    public init(
        formatVersion: UInt8,
        generationTimestamp: Date?,
        sourceIdentifier: String?,
        ipv4RangeCount: Int,
        ipv6RangeCount: Int,
        buildIdentifier: String
    ) {
        self.formatVersion = formatVersion
        self.generationTimestamp = generationTimestamp
        self.sourceIdentifier = sourceIdentifier
        self.ipv4RangeCount = ipv4RangeCount
        self.ipv6RangeCount = ipv6RangeCount
        self.buildIdentifier = buildIdentifier
    }
}

/// Identifies how an ``UltraCompactDatabase`` entered the current process.
///
/// Origin is runtime context rather than encoded provenance, so the same build
/// identifier may appear with different origins in different processes.
public enum DatabaseOrigin: String, Equatable, Sendable {
    /// Loaded through ``EmbeddedDatabase`` from the package resource bundle.
    case embedded

    /// Loaded from an application-provided fallback database.
    case bundled

    /// Loaded from `RemoteDatabase`'s persistent disk cache.
    case diskCache

    /// Downloaded by ``RemoteDatabase`` during this process.
    case downloaded

    /// Loaded directly with ``UltraCompactDatabase/init(path:)``.
    case file

    /// Loaded directly with ``UltraCompactDatabase/init(data:)``.
    case memory
}
