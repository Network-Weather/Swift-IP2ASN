# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build
swift build
swift build -c release

# Test
swift test
swift test --filter TestName    # Run specific test
swift test --enable-code-coverage

# Lint (if swiftlint available)
swiftlint

# Generate documentation
swift package --allow-writing-to-directory docs-out \
  generate-documentation --target SwiftIP2ASN \
  --output-path docs-out \
  --transform-for-static-hosting
```

## CLI Tool Usage

```bash
# Build the CLI
swift build -c release

# Build ultra-compact database from TSV
.build/release/ip2asn-tools build-ultra /path/to/ip2asn-v4.tsv output.ultra

# Build compressed database from TSV
.build/release/ip2asn-tools build-compressed /path/to/ip2asn-v4.tsv output.cdb

# Lookup IP address
.build/release/ip2asn-tools lookup-compressed /path/to/db.cdb 8.8.8.8

# Benchmark load times
.build/release/ip2asn-tools bench-ultra /path/to/db.ultra 5
```

## Architecture

This is a Swift 6 library for IP-to-ASN lookups using compressed trie data structures. It provides microsecond-level lookups with no network access after database construction.

### Module Structure

**SwiftIP2ASN** (main library) - Runtime lookup functionality:
- `SwiftIP2ASN.swift` - Main entry point struct
- `ASNDatabase.swift` - Actor managing trie and lookups (thread-safe)
- `CompressedTrie.swift` - High-performance trie with path compression
- `IPAddress.swift` - Type-safe IPv4/IPv6 representation
- `ASNInfo.swift` - ASN lookup result type
- `UltraCompactFormat.swift` - Ultra-compact on-disk format reader
- `CompressedDatabaseFormat.swift` - Delta-encoded format reader
- `EmbeddedDatabase.swift` - Access to bundled database resource
- `SortedRangeDatabase.swift` - Alternative sorted-range lookup implementation

**IP2ASNDataPrep** (build-time module) - Database construction:
- `RIRDataFetcher.swift` - Fetches RIR delegation files
- `BGPDataFetcher.swift` / `SimpleBGPFetcher.swift` - BGP route data fetching
- `UltraCompactBuilder.swift` - Builds .ultra format databases
- `CompressedDatabaseBuilder.swift` - Builds .cdb format databases

**ip2asn-tools** (CLI) - Command-line interface using both modules.

### Database Formats

- **Ultra-Compact (.ultra)**: Recommended default. Smallest size, modest decode cost at startup.
- **Compressed (.cdb)**: Delta-encoded format for comparison.
- **Embedded**: Ship prebuilt database at `Sources/SwiftIP2ASN/Resources/ip2asn.ultra`

### Concurrency Model (Swift 6.2)

- Uses Swift 6.2 with actors for thread-safe data structures
- `ASNDatabase` and `CompressedTrie` are actors for thread-safe access
- Database structs (`UltraCompactDatabase`, `CompactDatabase`, `OptimizedDatabase`, `BinaryDatabase`) are immutable `Sendable` structs safe for concurrent access
- All network operations use async/await
- Use `@concurrent` attribute to explicitly offload CPU-intensive work to background threads
- Prefer `nonisolated` for types that need background processing
- Async functions run on the caller's actor by default (no implicit offloading)

## Key Patterns

- **Trie nodes**: Use fixed-size `left`/`right` pointers instead of `Dictionary<Bool, Node>` (~3x memory savings)
- **Binary search databases**: Use contiguous `[UInt32]` arrays for cache-efficient lookups
- **Byte-by-byte parsing**: Avoid `withUnsafeBytes.load()` on unaligned offsets; use manual byte extraction
- **IPv4 lookups**: O(log n) binary search on sorted ranges, or O(32) bit-level trie traversal
- **IPv6 lookups**: O(128) bit-level trie traversal
- **Prefix calculation**: Use `count.trailingZeroBitCount` instead of `log2(Double(count))` for performance
- Most tests run offline; some integration tests fetch external data and are skipped by default
