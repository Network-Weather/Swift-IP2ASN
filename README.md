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
    .package(url: "https://github.com/Network-Weather/swift-ip2asn", from: "0.1.0")
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

### Persisting a Database (compressed file)

Note: The actor-based `ASNDatabase` in this package focuses on in-memory lookups.
For persistence, use the provided compact on-disk formats and load-time readers.

Example using the compressed delta-encoded format:

```swift
import SwiftIP2ASN
import IP2ASNDataPrep

// Create a compressed database from a TSV dump (startIP\tendIP\tasn\tcountry\tname)
try CompressedDatabaseBuilder.createCompressed(from: "/path/to/ip2asn-v4.tsv", to: "/path/to/ip2asn.cdb")

// Load the compressed database for fast lookups
let db = try CompressedDatabaseFormat.loadCompressed(from: "/path/to/ip2asn.cdb")

// Lookups
let asn = db.lookup("8.8.8.8")  // -> UInt32?
```

Alternatively, see builder APIs in the `IP2ASNDataPrep` module (e.g., optimized/ultra-compact writers) and
the corresponding readers in `SwiftIP2ASN` for different
trade-offs between size, speed, and metadata.

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

### CLI Tools

An executable `ip2asn-tools` is included for convenience:

```bash
# Build the tool
swift build -c release

# Create a compressed DB from a TSV file
.build/release/ip2asn-tools build-compressed /path/to/ip2asn-v4.tsv /path/to/ip2asn.cdb

# Lookup an IP using the compressed DB
.build/release/ip2asn-tools lookup-compressed /path/to/ip2asn.cdb 8.8.8.8
```

### Embedded Database

The library can ship with a prebuilt Ultra-Compact database as a SwiftPM resource.

- Place the file at: `Sources/SwiftIP2ASN/Resources/ip2asn.ultra`
- Access from your app:

```swift
import SwiftIP2ASN

let db = try EmbeddedDatabase.loadUltraCompact()
let result = db.lookup("8.8.8.8")
```

Rebuilding the embedded database from TSV:

```bash
swift build -c release
.build/release/ip2asn-tools build-ultra /path/to/ip2asn-v4.tsv Sources/SwiftIP2ASN/Resources/ip2asn.ultra
```

On release, you can also attach the same `ip2asn.ultra` as a GitHub Release asset.

## Benchmarking

You can benchmark database load times using the included CLI. This measures the time to
read the on-disk file, decompress, and construct the in-memory structures.

- Ultra-Compact format:
  - Build: `.build/release/ip2asn-tools build-ultra /path/to/ip2asn-v4.tsv /tmp/ip2asn.ultra`
  - Bench: `.build/release/ip2asn-tools bench-ultra /tmp/ip2asn.ultra 5`
- Compressed format (optional comparison):
  - Build: `.build/release/ip2asn-tools build-compressed /path/to/ip2asn-v4.tsv /tmp/ip2asn.cdb`
  - Bench: `.build/release/ip2asn-tools bench-compressed /tmp/ip2asn.cdb 5`

Example output (Ultra-Compact):

```
UltraCompact load: avg=35.82 ms, min=35.12 ms, max=37.33 ms over 5 iters
```

Notes:
- These numbers are warm-start (OS cache) and intended as a practical guide. Cold starts will be
  slower; warm starts reflect normal app restarts.
- We recommend Ultra-Compact as the default for apps; it minimizes on-disk size with a modest
  one-time decode cost at startup. Lookups are microsecond-level thereafter.

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

Note: Some tests involve external data or tools and are skipped by default. The core
unit tests run offline and complete in under a second.

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
