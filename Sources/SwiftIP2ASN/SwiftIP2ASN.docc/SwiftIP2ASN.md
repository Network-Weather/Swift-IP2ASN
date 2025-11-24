# ``SwiftIP2ASN``

A high-performance Swift library for IP address to ASN (Autonomous System Number) lookups.

## Overview

SwiftIP2ASN provides microsecond-level lookup performance with comprehensive caching
and automatic update support. The library supports both IPv4 and IPv6 addresses and
is built with Swift 6 concurrency features.

### Key Features

- **High Performance**: ~1 million lookups per second using binary search on sorted arrays
- **Dual Stack Support**: Full support for both IPv4 and IPv6 addresses
- **Swift 6 Ready**: Built with actors and Sendable types for thread-safe concurrent access
- **Automatic Updates**: ``RemoteDatabase`` fetches updates from CDN with ETag-based caching
- **Offline-First**: Apps can bundle a database for immediate offline functionality
- **Memory Efficient**: ~3.4 MB compressed database covers 500K+ IP ranges

## Getting Started

### Quick Start with Embedded Database

The simplest way to use SwiftIP2ASN is with the pre-built embedded database:

```swift
import SwiftIP2ASN

// Load the embedded database (~3.4 MB, 500K+ IP ranges)
let db = try EmbeddedDatabase.loadUltraCompact()

// Perform lookups
if let result = db.lookup("8.8.8.8") {
    print("AS\(result.asn): \(result.name ?? "Unknown")")
    // Output: AS15169: GOOGLE
}
```

### Automatic Updates with RemoteDatabase

For apps that need fresh data, use ``RemoteDatabase``:

```swift
let remote = RemoteDatabase()

// First call downloads, subsequent calls use cache
let db = try await remote.load()

// Check for updates (HEAD request, ~200 bytes)
switch try await remote.refresh() {
case .alreadyCurrent:
    print("Database is current")
case .updated(let newDb):
    print("Updated to \(newDb.entryCount) entries")
}
```

### Offline-First Apps

Ship a bundled database for immediate offline functionality:

```swift
let remote = RemoteDatabase(
    bundledDatabasePath: Bundle.main.path(forResource: "ip2asn", ofType: "ultra")
)

// Works immediately, even offline
let db = try await remote.load()

// Check for updates in background
Task { try? await remote.refresh() }
```

## Topics

### Essentials

- ``EmbeddedDatabase``
- ``RemoteDatabase``
- ``UltraCompactDatabase``

### IP Address Types

- ``IPAddress``
- ``IPRange``

### Database Building

- ``ASNDatabase``
- ``CompressedTrie``
- ``ASNInfo``

### Alternative Formats

- ``CompressedDatabaseFormat``
- ``SortedRangeDatabase``
- ``OptimizedDatabaseFormat``

## Performance

| Operation | Time |
|-----------|------|
| Lookup (binary search) | ~1 microsecond |
| Load from disk | ~150 ms |
| Download from CDN | ~2-3 seconds |
| Refresh check (HEAD) | ~100 ms |

## Data Sources

The database is sourced from [iptoasn.com](https://iptoasn.com), which aggregates
BGP routing data from global route collectors. The hosted database at
`pkgs.networkweather.com` is updated daily.

## Requirements

- Swift 6.0+
- macOS 13.0+ / iOS 16.0+ / tvOS 16.0+ / watchOS 9.0+
