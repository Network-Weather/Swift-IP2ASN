/// A typed IP-to-ASN lookup result.
///
/// The result intentionally contains only fields backed by the ULT2 database.
/// It does not imply that an address is geolocated, registered to the named
/// organization, or contained in a canonical CIDR prefix.
public struct ASNLookupResult: Codable, Equatable, Hashable, Sendable {
    /// Border Gateway Protocol autonomous system number for the matched range.
    public let asn: UInt32

    /// Source-provided autonomous-system name, when encoded in the database.
    public let name: String?

    public init(asn: UInt32, name: String? = nil) {
        self.asn = asn
        self.name = name
    }
}
