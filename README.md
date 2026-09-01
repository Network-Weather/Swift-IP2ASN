# SwiftIP2ASN

A high-performance Swift 6 library for IP address to ASN (Autonomous System Number) lookups. Provides microsecond-level lookup performance with automatic database updates and offline-first support.

## Features

- **High Performance**: ~1 million lookups per second using binary search on sorted arrays
- **Dual Stack Support**: IPv4 and IPv6 lookups against a single embedded database
- **Swift 6 Ready**: Built with `Sendable` value types for thread-safe concurrent access
- **Automatic Updates**: `RemoteDatabase` fetches updates from CDN with ETag-based caching
- **Offline-First**: Apps can bundle a database for immediate offline functionality
- **Memory Efficient**: ~4 MB compressed database covers hundreds of thousands of dual-stack ranges

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the planned work beyond database refreshes,
including reliability, database provenance, API stabilization, Linux support,
and the path to 1.0.

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Network-Weather/swift-ip2asn", from: "0.5.1")
]
```

## Quick Start

### Simple API (Recommended)

The easiest way to get started:

```swift
import SwiftIP2ASN

// Load embedded database (no network required)
let db = try IP2ASN.embedded()

// Perform a typed lookup
if let result = db.lookupResult("8.8.8.8") {
    print("AS\(result.asn): \(result.name ?? "Unknown")")
    // Output: AS15169: GOOGLE
}
```

### Automatic Updates from CDN

For apps that need fresh data:

```swift
import SwiftIP2ASN

// First call downloads (~4 MB), subsequent calls use cache
let db = try await IP2ASN.remote()

if let result = db.lookupResult("8.8.8.8") {
    print("AS\(result.asn): \(result.name ?? "Unknown")")
}

// One conditional GET; a current cache receives 304 with no response body
switch try await IP2ASN.refresh() {
case .alreadyCurrent:
    print("Database is up to date")
case .updated(let newDb):
    print("Updated to \(newDb.entryCount) entries")
}

// Detailed identity, origin, and persisted check/update timestamps
let details = try await IP2ASN.refreshDetails()
print(details.outcome)
print(details.status.databaseMetadata?.buildIdentifier as Any)
print(details.status.lastSuccessfulCheck as Any)
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

### Database Identity and Provenance

Every loaded database exposes a stable build identifier, encoded range counts,
and its runtime origin. Metadata-enabled builds also report when and from which
source they were generated:

```swift
let db = try await IP2ASN.remote()

print(db.metadata.buildIdentifier)
print(db.metadata.generationTimestamp as Any)
print(db.metadata.sourceIdentifier as Any)
print(db.origin) // embedded, bundled, diskCache, downloaded, file, or memory
```

Legacy ULT2 files have `nil` generation and source values because those fields
were not encoded, but still receive a deterministic build identifier.

### Lookup Semantics

`lookupResult(_:)` returns an `ASNLookupResult` with the BGP-origin ASN and the
source-provided AS name. It accepts either an address string or an already parsed
`IPAddress`; `lookupResult(ip:)` supports raw IPv4 integers. Invalid strings and
valid addresses absent from the routing dataset—including typical private,
loopback, and unrouted addresses—return `nil`.

```swift
let address = IPAddress(string: "2001:4860:4860::8888")!
if let result = db.lookupResult(address) {
    print("AS\(result.asn): \(result.name ?? "Unknown")")
}
```

Results do not claim IP geolocation, address ownership, or canonical CIDR
boundaries. The source stores exact inclusive ranges, but matched boundaries are
deferred until the library has a dedicated non-CIDR range type. Existing
tuple-returning `lookup` and `lookupV6` methods remain available during 0.x.

The static `IP2ASN` API maintains one active remote configuration. The most
recent `remote(bundledPath:)` call selects the configuration used by `refresh()`,
`refreshDetails()`, `status()`, `isCached()`, and `clearCache()`; calling
`remote()` with no path selects the default configuration again. Use separate
`RemoteDatabase` instances with distinct cache directories when you need
multiple independent configurations.

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

// IPv6
if let result = db.lookup("2001:4860:4860::8888") {
    print("Google v6: AS\(result.asn)")  // AS15169
}
```

### Building a Custom Database

To build a fresh ultra-compact dual-stack database from the
[iptoasn.com](https://iptoasn.com) TSVs (e.g. for a private fork or
non-default refresh cadence):

```swift
import Foundation
import IP2ASNDataPrep
import SwiftIP2ASN

// Combined v4 + v6 build → .ultra
try UltraCompactBuilder.createUltraCompact(
    ipv4TSV: "/path/to/ip2asn-v4.tsv",
    ipv6TSV: "/path/to/ip2asn-v6.tsv",
    to: "/path/to/out.ultra",
    metadata: UltraCompactBuildMetadata(
        generationTimestamp: Date(timeIntervalSince1970: 1_800_000_000),
        sourceIdentifier: "iptoasn.com"
    )
)

// Load and look up either family
let db = try UltraCompactDatabase(path: "/path/to/out.ultra")
print(db.lookup("8.8.8.8")?.asn ?? 0)                // 15169
print(db.lookup("2001:4860:4860::8888")?.asn ?? 0)   // 15169
```

The same build is available via the CLI:

```bash
ip2asn build-ultra \
  --source iptoasn.com \
  --generated-at 2027-01-15T08:00:00Z \
  <v4.tsv> [v6.tsv] <out.ultra>
```

Pass only the v4 TSV for an IPv4-only database. Omit both metadata options to
produce the legacy ULT2 layout. Supplying the same normalized TSV inputs,
generation timestamp, and source identifier produces identical database bytes
and the same build identifier.

Automated database updates also write `ip2asn.manifest.json`. Its versioned JSON
schema records source URLs, SHA-256 digests of the downloaded archives and
decompressed builder inputs, the builder Git revision, output digest, database
build identifier, range counts, and generation time. The production manifest is
published alongside the database at
<https://pkgs.networkweather.com/db/ip2asn-v2.manifest.json>.

The manifest provides checksums and an audit trail; it is not a cryptographic
signature. Authenticity currently depends on HTTPS plus the repository's
reviewed update workflow. A future signed-manifest design would require clients
to pin a public key rather than trusting a signature served from the same origin.

### CLI

The `ip2asn` executable uses the bundled dual-stack database by default:

```bash
# Build the tool
swift build -c release

# Lookup is implied when the argument is an IP address
.build/release/ip2asn 1.1.1.1
# Output: AS13335 CLOUDFLARENET

# The explicit verb is equivalent and supports a custom database
.build/release/ip2asn lookup 8.8.8.8
.build/release/ip2asn lookup 8.8.8.8 --database output.ultra
# Output: AS15169 GOOGLE

# Print stable JSON metadata and artifact checksums
.build/release/ip2asn inspect
.build/release/ip2asn inspect --database output.ultra

# Parse and validate the bundled database and provenance manifest
.build/release/ip2asn validate

# Validate a downloaded or locally built artifact against its manifest
.build/release/ip2asn validate \
  --database output.ultra \
  --manifest ip2asn.manifest.json
```

`inspect` and `validate` emit sorted JSON for CI use. `validate` returns a
nonzero status for a malformed database, invalid manifest, or any mismatch in
the output digest, build identifier, format, counts, or generation timestamp.
When a custom database is supplied without a manifest, it performs database
format validation only.

Database development commands remain available as `build-ultra`,
`bench-ultra`, and their legacy compressed-format counterparts. The previous
`ip2asn-tools` executable name and `lookup-ultra` verb remain compatibility
aliases during the 0.x release line.

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
| Unchanged refresh (conditional GET) | ~100 ms, no response body |

The library uses a binary search on sorted contiguous arrays, providing excellent cache locality and O(log n) lookup performance.

## Architecture

### Modules

- **SwiftIP2ASN**: Core library with lookup functionality
- **IP2ASNDataPrep**: Optional library product for parsing TSV input and building databases
- **ip2asn**: Executable product for bundled lookups, artifact diagnostics, database builds, and benchmarks (`ip2asn-tools` remains an alias)

### Core Components

1. **UltraCompactDatabase**: High-performance lookup using sorted arrays
2. **RemoteDatabase**: Manages automatic updates with persistent caching
3. **EmbeddedDatabase**: Access to the bundled database resource
4. **IPAddress/IPRange**: Type-safe IP address representations
5. **CompressedDatabaseFormat**: Legacy IPv4-only format retained for CLI compatibility

### Thread Safety

All database types are `Sendable` and safe for concurrent access:
- `UltraCompactDatabase` is an immutable struct
- `RemoteDatabase` is an actor with isolated state

### Legacy Compatibility

- ULT2 is the only production database format. The older compressed format and
  its CLI commands are retained for compatibility during the 0.x release line.
- `ASNInfo` is retained for source compatibility but is not returned by the
  ULT2 lookup APIs. It is deprecated because its registry, allocation date, and
  country fields cannot be populated reliably. New code should use
  `ASNLookupResult`.

## Data Sources

The library uses data from [iptoasn.com](https://iptoasn.com), which aggregates
BGP routing information from global route collectors. The repository checks for
updates weekly; reviewed database and manifest pairs are then published to
`pkgs.networkweather.com`.

## Requirements

- Swift 6.1+
- macOS 13.0+ / iOS 16.0+ / tvOS 16.0+ / watchOS 9.0+

## Testing

```bash
# Run all tests
swift test

# Run specific test suites
swift test --filter RemoteDatabaseTests
swift test --filter EmbeddedDatabaseTests
```

The default suite is offline: `RemoteDatabase` behavior uses a deterministic
stub transport. Live CDN smoke tests and full source-data/format validation are
opt-in:

```bash
IP2ASN_RUN_NETWORK=1 swift test --filter RemoteDatabaseLiveCDNSmokeTests
IP2ASN_RUN_FORMAT_TESTS=1 swift test
```

## Documentation

Full API documentation is available at: https://ip2asn.networkweather.com

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
