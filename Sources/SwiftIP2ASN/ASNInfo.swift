import Foundation

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
