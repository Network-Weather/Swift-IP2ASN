# SwiftIP2ASN

A high-performance Swift 6 library for IP address to ASN (Autonomous System Number) lookups using compressed trie data structures. This library provides microsecond-level lookup performance with no network access required after initial database construction.

## Features

- **High Performance**: Microsecond-level lookup times using compressed trie data structures
- **Dual Stack Support**: Full support for both IPv4 and IPv6 addresses
- **Swift 6 Ready**: Built with Swift 6 concurrency features and strict concurrency checking
- **Offline Operation**: After initial database build, all lookups are performed locally
- **RIR Data Integration**: Automatically fetches and merges data from all five Regional Internet Registries (RIRs)
- **Memory Efficient**: Uses compressed trie structures to minimize memory footprint
- **Type Safe**: Leverages Swift's type system for safe IP address handling

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Network-Weather/swift-ip2asn", from: "1.0.0")
]
```

## Usage

### Basic Lookup

```swift
import SwiftIP2ASN

// Build database from online RIR data
let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()

// Lookup an IP address
if let asnInfo = await ip2asn.lookup("8.8.8.8") {
    print("ASN: \(asnInfo.asn)")
    print("Country: \(asnInfo.countryCode ?? "Unknown")")
    print("Registry: \(asnInfo.registry)")
}

// IPv6 lookup
if let asnInfo = await ip2asn.lookup("2001:4860:4860::8888") {
    print("ASN: \(asnInfo.asn)")
}
```

### Building and Caching Database

```swift
import SwiftIP2ASN

// Build and save database for later use
let builder = ASNDatabaseBuilder()
let databaseURL = URL(fileURLWithPath: "ip2asn.db")
try await builder.buildAndSave(to: databaseURL)

// Load pre-built database
let ip2asn = try await SwiftIP2ASN.load(from: databaseURL)
```

### Advanced Usage with IP Addresses

```swift
import SwiftIP2ASN

// Create IP address objects directly
let ipv4 = IPAddress(string: "192.168.1.1")!
let ipv6 = IPAddress(string: "2001:db8::1")!

let ip2asn = try await SwiftIP2ASN.buildFromOnlineData()

// Lookup using IP address objects
let result = await ip2asn.lookup(ipv4)
```

### Working with IP Ranges

```swift
// Parse CIDR notation
let range = IPRange(cidr: "192.168.0.0/16")!

// Check if an IP is within a range
let ip = IPAddress(string: "192.168.1.1")!
if range.contains(ip) {
    print("IP is within range")
}
```

### Database Statistics

```swift
let stats = await ip2asn.getStatistics()
print("Total nodes: \(stats.totalNodes)")
print("IPv4 entries: \(stats.ipv4Entries)")
print("IPv6 entries: \(stats.ipv6Entries)")
```

## Data Sources

The library fetches data from the following Regional Internet Registries:

- **ARIN** (American Registry for Internet Numbers)
- **RIPE NCC** (Réseaux IP Européens Network Coordination Centre)
- **APNIC** (Asia-Pacific Network Information Centre)
- **LACNIC** (Latin America and Caribbean Network Information Centre)
- **AFRINIC** (African Network Information Centre)

Data is fetched from the delegated-extended statistics files provided by each RIR.

## Performance

The library uses a compressed trie data structure optimized for longest prefix matching:

- **Lookup Time**: O(32) for IPv4, O(128) for IPv6 (bit-level traversal)
- **Memory Usage**: Compressed tries reduce memory footprint by up to 50%
- **Build Time**: Initial database construction takes 10-30 seconds depending on network speed
- **Lookup Performance**: Typical lookups complete in 1-10 microseconds

## Architecture

### Core Components

1. **IPAddress**: Type-safe representation of IPv4 and IPv6 addresses
2. **CompressedTrie**: High-performance trie implementation with path compression
3. **ASNDatabase**: Main database actor managing the trie and providing lookup functionality
4. **RIRDataFetcher**: Async/await based fetcher for RIR delegation files
5. **RIRDataParser**: Parser for RIR extended delegation format

### Concurrency

The library uses Swift's actor model for thread-safe database access:

- `ASNDatabase` is an actor ensuring thread-safe access
- All network operations use async/await
- Supports concurrent fetching from multiple RIRs

## Requirements

- Swift 6.0+
- macOS 13.0+ / iOS 16.0+ / tvOS 16.0+ / watchOS 9.0+

## Testing

Run the test suite:

```bash
swift test
```

Run with coverage:

```bash
swift test --enable-code-coverage
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is available under the MIT license. See the LICENSE file for more info.

## Acknowledgments

- Data provided by the five Regional Internet Registries
- Built with Swift 6 and modern concurrency features
- Inspired by the need for high-performance IP geolocation in Swift

## Support

For issues, questions, or contributions, please visit:
https://github.com/Network-Weather/swift-ip2asn