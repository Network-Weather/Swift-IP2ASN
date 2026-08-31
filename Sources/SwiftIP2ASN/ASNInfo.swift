import Foundation

/// Legacy ASN metadata model retained for source compatibility.
///
/// `UltraCompactDatabase` does not return this type because the ULT2 source
/// data does not provide reliable values for all of its fields. New lookup code
/// should use the result returned by `UltraCompactDatabase.lookup` until a
/// dedicated typed lookup result is introduced.
public struct ASNInfo: Sendable, Codable, Equatable {
    public let asn: UInt32
    public let countryCode: String?
    public let registry: String
    public let allocatedDate: Date?
    public let name: String?

    public init(
        asn: UInt32,
        countryCode: String? = nil,
        registry: String,
        allocatedDate: Date? = nil,
        name: String? = nil
    ) {
        self.asn = asn
        self.countryCode = countryCode
        self.registry = registry
        self.allocatedDate = allocatedDate
        self.name = name
    }
}
