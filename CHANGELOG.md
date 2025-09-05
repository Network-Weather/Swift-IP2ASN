# Changelog

All notable changes to this project will be documented in this file.

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

