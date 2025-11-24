# Changelog

All notable changes to this project will be documented in this file.

## [0.2.1] - 2025-11-24

### Added
- **Simple `IP2ASN` API**: New top-level enum for the easiest possible usage
  ```swift
  let db = try IP2ASN.embedded()           // Sync, no network
  let db = try await IP2ASN.remote()       // Async, auto-updates from CDN
  let db = try await IP2ASN.remote(bundledPath: path)  // Offline-first
  ```
- Tests verifying `UltraCompactDatabase` works across actor boundaries

### Fixed
- **`UltraCompactDatabase` is now `Sendable`**: Changed from class to struct
  - Can now be safely passed across actor boundaries
  - Required for Swift 6 strict concurrency

### Changed
- `SwiftIP2ASN` struct marked as legacy; prefer new `IP2ASN` API

## [0.2.0] - 2025-11-24

### Added
- **RemoteDatabase**: New actor for automatic database updates from CDN
  - Persistent disk caching in Application Support directory
  - ETag/Last-Modified based refresh checking (HEAD request first)
  - Support for bundled databases enabling offline-first apps
  - Thread-safe concurrent access via Swift actors
- **CDN Hosting**: Database now hosted at `pkgs.networkweather.com/db/ip2asn.ultra`
  - Daily updates from iptoasn.com BGP routing data
  - Cloudflare R2 for global distribution
- **Comprehensive DocC Documentation**: All public APIs fully documented
  - Code examples in documentation comments
  - Topics organization for discoverability

### Changed
- Updated embedded database to November 2025 BGP data
- Improved README with RemoteDatabase usage examples
- Enhanced test coverage with 16 new RemoteDatabase tests

### Technical Details
- `RemoteDatabase.load()` priority: memory cache → disk cache → bundled → network
- `RemoteDatabase.refresh()` uses HEAD request (~200 bytes) before downloading (~3.4 MB)
- Cache stored at `~/Library/Application Support/SwiftIP2ASN/`

## [0.1.0] - 2025-09-04

- Split package into two modules:
  - `SwiftIP2ASN` (library): Read-time lookups and in-memory structures
  - `IP2ASNDataPrep` (tools): Fetchers, parsers, and database writers
- Adopt Ultra-Compact format as default for app embedding; retained Compressed format reader
- Added `ip2asn-tools` executable with commands:
  - `build-ultra`, `lookup-ultra`, `bench-ultra`
  - `build-compressed`, `lookup-compressed`, `bench-compressed`
- Restructured tests: fast, offline unit tests by default; heavy/network tests opt-in via env vars
- README updates and release checklist; added CI workflow (macOS) for build + tests

