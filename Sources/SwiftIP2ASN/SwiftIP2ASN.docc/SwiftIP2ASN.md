# ``SwiftIP2ASN``

A high-performance Swift library for IP address to ASN (Autonomous System Number) lookups using compressed trie data structures.

## Overview

SwiftIP2ASN provides microsecond-level lookup performance with no network access required after initial database construction. The library supports both IPv4 and IPv6 addresses and is built with Swift 6 concurrency features.

### Key Features

- **High Performance**: Microsecond-level lookup times using compressed trie data structures
- **Dual Stack Support**: Full support for both IPv4 and IPv6 addresses  
- **Swift 6 Ready**: Built with Swift 6 concurrency features and strict concurrency checking
- **Offline Operation**: After initial database build, all lookups are performed locally
- **Memory Efficient**: Uses compressed trie structures to minimize memory footprint
- **Type Safe**: Leverages Swift's type system for safe IP address handling

## Topics

### Essentials

- ``SwiftIP2ASN/SwiftIP2ASN``
- ``ASNDatabase``
- ``IPAddress``
- ``ASNInfo``

### Advanced Usage

- ``CompressedTrie``
- ``EmbeddedDatabase``
- ``CompressedDatabaseFormat``
- ``UltraCompactFormat``

### Database Management

- ``SortedRangeDatabase``
- ``OptimizedDatabaseFormat``

## Getting Started

### Basic Lookup

```swift
import SwiftIP2ASN

// Load from a prebuilt database
let ip2asn = try await SwiftIP2ASN.load(from: databaseURL)

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

### Using Embedded Database

```swift
import SwiftIP2ASN

let db = try EmbeddedDatabase.loadUltraCompact()
let result = db.lookup("8.8.8.8")
```

## Performance

The library uses a compressed trie data structure optimized for longest prefix matching:

- **Lookup Time**: O(32) for IPv4, O(128) for IPv6 (bit-level traversal)
- **Memory Usage**: Compressed tries reduce memory footprint by up to 50%
- **Lookup Performance**: Typical lookups complete in 1-10 microseconds

## Requirements

- Swift 6.0+
- macOS 13.0+ / iOS 16.0+ / tvOS 16.0+ / watchOS 9.0+