# Changelog

All notable changes to this project will be documented in this file.

## [0.4.1] - 2026-07-14

### Added
- Unit tests verifying new cache behaviors (self-healing, poisoning prevention, missing cache refresh).

### Changed
- **Self-Healing Disk Cache.** `RemoteDatabase.load` now intercepts corrupted/invalid format cache files, deletes them automatically, and recovers by falling back to the bundled database or network fetch.
- **Cache Poisoning Prevention.** `RemoteDatabase.fetchAndCache` parses and validates database format before writing to disk cache, preventing CDN/network failures from corrupting cached data.
- **Robust Cache Refresh.** `RemoteDatabase.refresh` checks file presence on disk (`isCached()`) rather than just stored metadata, ensuring missing database files are re-downloaded even if ETags match.
- **Auto-update workflow** updated to run all format validation tests (`IP2ASN_RUN_FORMAT_TESTS=1`) in CI before opening PRs.
- Refreshed embedded `ip2asn.ultra` database to July 2026 iptoasn.com snapshot (~4.18 MB).

## [0.4.0] - 2026-05-28

### Added
- **IPv6 lookups.** `UltraCompactDatabase.lookup` transparently routes IPv4
  strings to a `UInt32` binary search and IPv6 strings to a 128-bit
  `(hi, lo)` UInt64 binary search.
- **Dual-stack embedded DB.** Bundled `ip2asn.ultra` now built from both
  `ip2asn-v4.tsv` (~446K ranges) and `ip2asn-v6.tsv` (~119K ranges) for a
  combined ~565K ranges across ~86K unique ASNs (~4 MB compressed).
- **New on-disk format `ULT2` (version 2)** with a 1-byte version + 1-byte
  flags field after the magic for future additive evolution. Readers reject
  unknown versions and ignore unknown flag bits.
- CLI: `ip2asn-tools build-ultra <v4.tsv> [v6.tsv] <out.ultra>` — pass
  either or both inputs.
- Auto-update workflow fetches both TSVs weekly.

### Changed
- `IP2ASN.remote()` / `RemoteDatabase.defaultURL` now points at
  `https://pkgs.networkweather.com/db/ip2asn-v2.ultra`. The pre-0.4.0
  IPv4-only file remains at `/db/ip2asn.ultra` for older clients.
- README, DocC, and CLAUDE.md updated to reflect dual-stack reality.

### Removed (breaking)
The following public types had no production callers — they were a parallel
BGP-fetching architecture documented in the old README. Pre-1.0 license to
break:
- `ASNDatabase`, `CompressedTrie`, `SortedRangeDatabase`, the legacy
  `SwiftIP2ASN` struct
- `BGPDataFetcher`, `BGPDataParser`, `SimpleBGPFetcher`
- `RIRDataFetcher` / `RIR` / `RIRDataParser`, `BinaryDatabaseFormat`
- `IPAllocation`

Migrate reads to `IP2ASN.embedded()` / `IP2ASN.remote()` returning
`UltraCompactDatabase`; migrate builds to
`UltraCompactBuilder.createUltraCompact(ipv4TSV:ipv6TSV:to:)`.

### Test suite
- Pruned ~30 redundant/inert test files; final count 42 with much faster
  runtime (~5s parallel).
- Added IPv6 lookup coverage (`testEmbeddedUltraIPv6Lookups`).
- Network-dependent tests now skip cleanly when the default CDN URL is
  unreachable.

## [0.3.1] - 2026-05-27

### Changed
- Refreshed embedded `ip2asn.ultra` to 2026-05-27 iptoasn.com snapshot
  (~3.5 MB; ~525K IPv4 ranges).
- Auto-update workflow now runs the full `swift test` suite (not just
  `EmbeddedDatabaseTests`) against a freshly built database before opening
  its PR. Workflow-opened PRs aren't triggered by `ci.yml` due to GitHub's
  `GITHUB_TOKEN` anti-recursion safety, so the in-workflow test step is
  the only gate.
- Bumped GitHub Actions to Node 24-compatible versions
  (`actions/checkout@v6`, `peter-evans/create-pull-request@v8`,
  `actions/upload-pages-artifact@v3`, `actions/deploy-pages@v4`).

## [0.3.0] - 2026-03-13

### Added
- **Weekly auto-update workflow** (`.github/workflows/update-database.yml`)
  that fetches the latest iptoasn.com TSV every Monday and opens a PR
  refreshing `Sources/SwiftIP2ASN/Resources/ip2asn.ultra`.

### Changed
- Refreshed embedded database to March 2026 BGP data.

### Fixed
- `Bundle.module` no longer crashes via `fatalError` when the resource is
  missing in unusual bundle layouts; `EmbeddedDatabase.loadUltraCompact`
  now throws `Error.resourceNotFound` instead, surfaced through a safe
  `BundleAccessor` fallback.

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

