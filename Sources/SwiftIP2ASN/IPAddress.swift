import Foundation
import Network

public enum IPAddress: Sendable, Hashable {
    case v4(IPv4Address)
    case v6(IPv6Address)
    
    public init?(string: String) {
        if let v4 = IPv4Address(string) {
            self = .v4(v4)
        } else if let v6 = IPv6Address(string) {
            self = .v6(v6)
        } else {
            return nil
        }
    }
    
    public var bitCount: Int {
        switch self {
        case .v4: return 32
        case .v6: return 128
        }
    }
    
    public func getBit(at index: Int) -> Bool {
        switch self {
        case .v4(let addr):
            guard index < 32 else { return false }
            let data = addr.rawValue
            let byteIndex = index / 8
            let bitIndex = 7 - (index % 8)
            return (data[byteIndex] & (1 << bitIndex)) != 0
            
        case .v6(let addr):
            guard index < 128 else { return false }
            let data = addr.rawValue
            let byteIndex = index / 8
            let bitIndex = 7 - (index % 8)
            return (data[byteIndex] & (1 << bitIndex)) != 0
        }
    }
    
    public var debugDescription: String {
        switch self {
        case .v4(let addr):
            return addr.debugDescription
        case .v6(let addr):
            return addr.debugDescription
        }
    }
}

public struct IPRange: Sendable {
    public let start: IPAddress
    public let prefixLength: Int
    
    public init(start: IPAddress, prefixLength: Int) {
        self.start = start
        self.prefixLength = prefixLength
    }
    
    public init?(cidr: String) {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let address = IPAddress(string: String(parts[0])),
              let prefix = Int(parts[1]) else {
            return nil
        }
        
        let maxPrefix = address.bitCount
        guard prefix >= 0 && prefix <= maxPrefix else {
            return nil
        }
        
        self.start = address
        self.prefixLength = prefix
    }
    
    public func contains(_ address: IPAddress) -> Bool {
        // Check if address types match
        switch (start, address) {
        case (.v4, .v4), (.v6, .v6):
            break
        default:
            return false
        }
        
        // Check prefix bits
        for i in 0..<prefixLength {
            if start.getBit(at: i) != address.getBit(at: i) {
                return false
            }
        }
        
        return true
    }
}