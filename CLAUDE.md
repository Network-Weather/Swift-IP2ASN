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

This is a Swift 6 library for IP-to-ASN lookups via a precomputed ultra-compact on-disk format. It provides microsecond-level lookups with no network access after database construction.

### Module Structure

**SwiftIP2ASN** (main library) - Runtime lookup functionality:
- `SwiftIP2ASN.swift` - `IP2ASN` enum: top-level entry point for embedded/remote DB
- `IPAddress.swift` - Type-safe IPv4/IPv6 representation
- `ASNInfo.swift` - ASN lookup result type
- `UltraCompactFormat.swift` - Ultra-compact on-disk format reader (`UltraCompactDatabase`)
- `CompressedDatabaseFormat.swift` - Delta-encoded format reader (used by CLI)
- `EmbeddedDatabase.swift` - Access to bundled database resource
- `RemoteDatabase.swift` - CDN-hosted database with ETag-based refresh
- `BundleAccessor.swift` - Module-bundle resolution fallback

**IP2ASNDataPrep** (build-time module) - Database construction:
- `UltraCompactBuilder.swift` - Builds `.ultra` format databases from iptoasn TSV
- `CompressedDatabaseBuilder.swift` - Builds `.cdb` format databases from TSV

**ip2asn-tools** (CLI) - Command-line interface for build/lookup/benchmark.

### Database Formats

- **Ultra-Compact V2 (.ultra)**: Default and only production format. Magic `ULT2`; holds both IPv4 (delta-varint, 4-byte addrs) and IPv6 (absolute, 16-byte addrs) ranges plus a shared ASN name table. Built by `UltraCompactBuilder`, read by `UltraCompactDatabase`.
- **Compressed (.cdb)**: Legacy format kept for CLI `build-compressed`/`lookup-compressed`/`bench-compressed` commands.
- **Embedded**: Bundled at `Sources/SwiftIP2ASN/Resources/ip2asn.ultra`; refreshed weekly via `.github/workflows/update-database.yml` from both `ip2asn-v4.tsv.gz` and `ip2asn-v6.tsv.gz`.
- **CDN URL**: `RemoteDatabase` fetches from `https://pkgs.networkweather.com/db/ip2asn-v2.ultra` (new in 0.4.0; pre-0.4.0 consumers continue to read `/db/ip2asn.ultra`).

### Concurrency Model

- Swift 6.1 (`swift-tools-version: 6.1`); no Swift 6.2/6.3-only features in use.
- `RemoteDatabase` is an actor; `UltraCompactDatabase` is an immutable `Sendable` struct.
- All network operations use async/await.

## Key Patterns

- **Byte-by-byte parsing**: Avoid `withUnsafeBytes.load()` on unaligned offsets; use manual byte extraction.
- **IPv4 lookups**: O(log n) binary search on parallel `[UInt32]` start/end arrays.
- **IPv6 lookups**: O(log n) binary search on parallel `[UInt64]` (hi, lo) arrays; addresses compared lexicographically via `compare128`.
- Most tests run offline; the auto-update workflow runs the full suite against a freshly built dual-stack DB before opening its PR.
