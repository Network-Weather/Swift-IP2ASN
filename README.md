# SwiftIP2ASN

A high-performance Swift 6 library for IP address to ASN (Autonomous System Number) lookups. Provides microsecond-level lookup performance with automatic database updates and offline-first support.

## Features

- **High Performance**: ~1 million lookups per second using binary search on sorted arrays
- **Dual Stack Support**: Full support for both IPv4 and IPv6 addresses
- **Swift 6 Ready**: Built with actors and Sendable types for thread-safe concurrent access
- **Automatic Updates**: `RemoteDatabase` fetches updates from CDN with ETag-based caching
- **Offline-First**: Apps can bundle a database for immediate offline functionality
- **Memory Efficient**: ~3.4 MB compressed database covers 500K+ IP ranges

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Network-Weather/swift-ip2asn", from: "0.2.1")
]
```

## Quick Start

### Simple API (Recommended)

The easiest way to get started:

```swift
import SwiftIP2ASN

// Load embedded database (no network required)
let db = try IP2ASN.embedded()

// Perform lookups
if let result = db.lookup("8.8.8.8") {
    print("AS\(result.asn): \(result.name ?? "Unknown")")
    // Output: AS15169: GOOGLE
}
```

### Automatic Updates from CDN

For apps that need fresh data:

```swift
import SwiftIP2ASN

// First call downloads (~3.4 MB), subsequent calls use cache
let db = try await IP2ASN.remote()

if let result = db.lookup("8.8.8.8") {
    print("AS\(result.asn): \(result.name ?? "Unknown")")
}

// Check for updates (HEAD request first, ~200 bytes)
switch try await IP2ASN.refresh() {
case .alreadyCurrent:
    print("Database is up to date")
case .updated(let newDb):
    print("Updated to \(newDb.entryCount) entries")
}
```

### Offline-First Apps

Ship a bundled database for immediate offline functionality:

```swift
import SwiftIP2ASN

// Works immediately, even offline
let db = try await IP2ASN.remote(
    bundledPath: Bundle.main.path(forResource: "ip2asn", ofType: "ultra")
)

// Check for updates in background
Task { try? await IP2ASN.refresh() }
```

### Advanced: Direct RemoteDatabase Usage

For more control over caching and state:

```swift
import SwiftIP2ASN

let remote = RemoteDatabase(
    bundledDatabasePath: Bundle.main.path(forResource: "ip2asn", ofType: "ultra")
)

let db = try await remote.load()

switch try await remote.refresh() {
case .alreadyCurrent:
    break
case .updated(let newDb):
    print("Updated to \(newDb.entryCount) entries")
}
```

## Usage Examples

### IPv4 and IPv6 Lookups

```swift
let db = try EmbeddedDatabase.loadUltraCompact()

// IPv4
if let result = db.lookup("1.1.1.1") {
    print("Cloudflare: AS\(result.asn)")  // AS13335
}

// IPv4 by UInt32 (faster, no string parsing)
let googleDNS: UInt32 = 0x08_08_08_08  // 8.8.8.8
if let result = db.lookup(ip: googleDNS) {
    print("Google: AS\(result.asn)")  // AS15169
}
```

### Building a Custom Database

For advanced use cases, build a database from BGP data:

```swift
import SwiftIP2ASN
import IP2ASNDataPrep

// Fetch and parse BGP data
let fetcher = BGPDataFetcher()
let rawData = try await fetcher.fetchIPv4Data()

let parser = BGPDataParser()
let mappings = parser.parseIPtoASNData(rawData)

// Build database
let database = ASNDatabase()
await database.buildWithBGPData(bgpEntries: mappings.map {
    (range: $0.range, asn: $0.asn, name: $0.name)
})

// Lookup
if let result = await database.lookup("8.8.8.8") {
    print("ASN: \(result.asn)")
}
```

### CLI Tools

An executable `ip2asn-tools` is included for database management:

```bash
# Build the tool
swift build -c release

# Create an ultra-compact database from TSV
.build/release/ip2asn-tools build-ultra /path/to/ip2asn-v4.tsv output.ultra

# Lookup an IP
.build/release/ip2asn-tools lookup-ultra output.ultra 8.8.8.8
# Output: AS15169 GOOGLE

# Benchmark load times
.build/release/ip2asn-tools bench-ultra output.ultra 5
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

## Performance

| Operation | Time |
|-----------|------|
| Lookup (binary search) | ~1 microsecond |
| Load from disk | ~150 ms |
| Download from CDN | ~2-3 seconds |
| Refresh check (HEAD) | ~100 ms |

The library uses a binary search on sorted contiguous arrays, providing excellent cache locality and O(log n) lookup performance.

## Architecture

### Modules

- **SwiftIP2ASN**: Core library with lookup functionality
- **IP2ASNDataPrep**: Tools for fetching, parsing, and building databases

### Core Components

1. **UltraCompactDatabase**: High-performance lookup using sorted arrays
2. **RemoteDatabase**: Manages automatic updates with persistent caching
3. **EmbeddedDatabase**: Access to the bundled database resource
4. **IPAddress/IPRange**: Type-safe IP address representations
5. **CompressedTrie**: Alternative trie-based lookup structure

### Thread Safety

All database types are `Sendable` and safe for concurrent access:
- `UltraCompactDatabase` is an immutable struct
- `RemoteDatabase` is an actor with isolated state
- `ASNDatabase` is an actor for thread-safe mutations

## Data Sources

The library uses data from [iptoasn.com](https://iptoasn.com), which aggregates BGP routing information from global route collectors. The hosted database at `pkgs.networkweather.com` is updated daily.

## Requirements

- Swift 6.0+
- macOS 13.0+ / iOS 16.0+ / tvOS 16.0+ / watchOS 9.0+

## Testing

```bash
# Run all tests
swift test

# Run specific test suites
swift test --filter RemoteDatabaseTests
swift test --filter EmbeddedDatabaseTests
```

Note: Some tests require network access. Core unit tests run offline.

## Documentation

Full API documentation is available at: https://swift-ip2asn.networkweather.com

Generate documentation locally:

```bash
swift package generate-documentation --target SwiftIP2ASN
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

- Data provided by [iptoasn.com](https://iptoasn.com)
- Built with Swift 6 and modern concurrency features
- CDN hosting provided by Cloudflare R2

## Support

For issues, questions, or contributions, please visit:
https://github.com/Network-Weather/swift-ip2asn
