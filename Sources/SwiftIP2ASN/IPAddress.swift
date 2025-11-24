import Foundation
import Network

// MARK: - IPAddress

/// High-performance IP address representation supporting both IPv4 and IPv6.
/// Uses raw bytes for efficient bit operations without per-bit dispatch overhead.
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

    @inlinable
    public var bitCount: Int {
        switch self {
        case .v4: return 32
        case .v6: return 128
        }
    }

    /// Returns raw bytes in network byte order (big-endian).
    @inlinable
    public var rawBytes: [UInt8] {
        switch self {
        case .v4(let addr): return Array(addr.rawValue)
        case .v6(let addr): return Array(addr.rawValue)
        }
    }

    /// Efficient bit access for trie traversal.
    /// Avoids per-call switch dispatch by using inline byte/bit extraction.
    @inlinable
    public func getBit(at index: Int) -> Bool {
        switch self {
        case .v4(let addr):
            guard index < 32 else { return false }
            let data = addr.rawValue
            let byteIndex = index >> 3  // index / 8
            let bitIndex = 7 - (index & 7)  // 7 - (index % 8)
            return (data[byteIndex] & (1 << bitIndex)) != 0

        case .v6(let addr):
            guard index < 128 else { return false }
            let data = addr.rawValue
            let byteIndex = index >> 3
            let bitIndex = 7 - (index & 7)
            return (data[byteIndex] & (1 << bitIndex)) != 0
        }
    }

    public var debugDescription: String {
        switch self {
        case .v4(let addr): return addr.debugDescription
        case .v6(let addr): return addr.debugDescription
        }
    }
}

// MARK: - IPv4 UInt32 Conversion

extension IPAddress {
    /// Convert IPv4 address to UInt32 for range-based lookups.
    /// Returns nil for IPv6 addresses.
    @inlinable
    public var ipv4UInt32: UInt32? {
        guard case .v4(let addr) = self else { return nil }
        let bytes = addr.rawValue
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    /// Create IPv4 address from UInt32.
    @inlinable
    public static func fromIPv4UInt32(_ value: UInt32) -> IPAddress? {
        let b0 = UInt8((value >> 24) & 0xFF)
        let b1 = UInt8((value >> 16) & 0xFF)
        let b2 = UInt8((value >> 8) & 0xFF)
        let b3 = UInt8(value & 0xFF)
        guard let addr = IPv4Address(Data([b0, b1, b2, b3])) else { return nil }
        return .v4(addr)
    }
}

// MARK: - IPRange

/// Represents an IP range using CIDR notation (network prefix).
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
            let prefix = Int(parts[1])
        else {
            return nil
        }

        let maxPrefix = address.bitCount
        guard prefix >= 0 && prefix <= maxPrefix else {
            return nil
        }

        self.start = address
        self.prefixLength = prefix
    }

    /// Check if address is within this range using efficient prefix comparison.
    @inlinable
    public func contains(_ address: IPAddress) -> Bool {
        // Check if address types match
        switch (start, address) {
        case (.v4, .v4), (.v6, .v6):
            break
        default:
            return false
        }

        // Use byte-level comparison for efficiency
        let startBytes = start.rawBytes
        let addrBytes = address.rawBytes

        // Compare full bytes
        let fullBytes = prefixLength >> 3
        for i in 0..<fullBytes {
            if startBytes[i] != addrBytes[i] {
                return false
            }
        }

        // Compare remaining bits
        let remainingBits = prefixLength & 7
        if remainingBits > 0 {
            let mask = UInt8(0xFF << (8 - remainingBits))
            if (startBytes[fullBytes] & mask) != (addrBytes[fullBytes] & mask) {
                return false
            }
        }

        return true
    }
}

// MARK: - Utility Functions

/// Parse IPv4 string to UInt32 efficiently.
/// Uses direct arithmetic instead of string splitting where possible.
@inlinable
public func parseIPv4ToUInt32(_ ip: String) -> UInt32? {
    var result: UInt32 = 0
    var octet: UInt32 = 0
    var octetCount = 0
    var digitCount = 0

    for char in ip.utf8 {
        if char == 0x2E {  // '.'
            guard digitCount > 0, octet <= 255, octetCount < 3 else { return nil }
            result = (result << 8) | octet
            octet = 0
            octetCount += 1
            digitCount = 0
        } else if char >= 0x30 && char <= 0x39 {  // '0'-'9'
            octet = octet * 10 + UInt32(char - 0x30)
            digitCount += 1
            if digitCount > 3 { return nil }
        } else {
            return nil
        }
    }

    guard digitCount > 0, octet <= 255, octetCount == 3 else { return nil }
    return (result << 8) | octet
}

/// Convert UInt32 to IPv4 string.
@inlinable
public func uint32ToIPv4String(_ ip: UInt32) -> String {
    let b0 = (ip >> 24) & 0xFF
    let b1 = (ip >> 16) & 0xFF
    let b2 = (ip >> 8) & 0xFF
    let b3 = ip & 0xFF
    return "\(b0).\(b1).\(b2).\(b3)"
}
