# SwiftIP2ASN Roadmap

Last reviewed: 2026-08-30

This roadmap describes the intended direction of SwiftIP2ASN after the 0.4
dual-stack release. It is an ordered plan, not a calendar commitment. Minor
release numbers may change as work is scoped, but correctness and compatibility
work should land before feature or platform expansion.

## Current Baseline

SwiftIP2ASN 0.4.1 provides:

- offline IPv4 and IPv6 ASN lookups from an embedded database;
- the ULT2 ultra-compact database format and builder;
- a `Sendable`, immutable lookup database;
- an actor-based remote database with persistent caching and manual refresh;
- a command-line tool for building, querying, and benchmarking databases;
- weekly embedded-database update automation; and
- SwiftPM support for current Apple platforms.

There is no committed feature backlog beyond this document. New work should be
opened as a GitHub issue and attached to the relevant milestone before
implementation begins.

## Product Direction

SwiftIP2ASN should remain a small, dependable lookup library rather than grow
into a general network-intelligence system. Its primary use case is answering
"which ASN announces this address?" quickly, locally, and without making a
network request during lookup.

Roadmap decisions follow these principles:

1. **Offline lookup is the core product.** Network access is optional and only
   used to acquire or refresh a database.
2. **Correctness precedes compression ratios.** Malformed or surprising input
   must fail safely and must never poison the cache.
3. **Compatibility is explicit.** Additive APIs are preferred before 1.0, and
   future library releases continue reading released ULT2 files unless a
   documented security issue makes that impossible.
4. **Freshness should be observable.** Applications should be able to identify
   the database they loaded without inspecting cache files or HTTP headers.
5. **Performance claims are measured.** Format or lookup changes require
   before-and-after measurements using representative dual-stack data.
6. **Platform expansion must be complete.** A supported platform receives the
   lookup API, remote-update behavior where applicable, documentation, and CI.

## Delivery Sequence

`0.4.x reliability → 0.5 provenance → 0.6 API → 0.7 Linux → 1.0 contract`

Items are ordered within each milestone. A milestone should satisfy its exit
criteria before work depending on it is considered complete: metadata builds on
the hardened parser and transport, typed results build on the metadata decision,
and Linux support follows the intended long-term API rather than porting symbols
that are about to be retired.

## Milestone 0.4.x — Establish a Reliable Baseline

Goal: remove ambiguity and nondeterminism from the existing product before
adding new public behavior.

### Public contract and documentation

- [x] Reconcile README and DocC content with the actual public API, including
      removal of references to the retired trie, mutable database, and fetching
      architecture.
- [x] Publish the actual Swift toolchain and platform support policy.
- [x] Document which tests are offline, opt-in validation, performance, or live
      CDN smoke tests.
- [x] Decide and document the status of `ASNInfo`, the legacy compressed format,
      and its CLI commands. Do not remove them silently.

### Simple API state semantics

- [x] Define whether repeated `IP2ASN.remote(bundledPath:)` calls may select
      different bundles. The current first-path-wins behavior must not remain
      implicit.
- [x] Make `refresh()`, `isCached()`, and `clearCache()` operate on a clearly
      identified remote-database configuration.
- [x] Cover transitions between the default, bundled, cached, cleared, and
      refreshed states with tests.
- [x] Keep direct `RemoteDatabase` construction as the explicit API for callers
      needing multiple independent configurations.

### Deterministic remote-update tests

- [x] Introduce an injectable HTTP transport or session so cache and refresh
      tests do not depend on the production CDN.
- [x] Test `200`, `304`, missing validators, unsupported `HEAD`, timeouts,
      truncated responses, invalid database payloads, and server errors locally.
- [x] Keep a small, separately identified live-CDN smoke test; it may skip when
      the network is unavailable without hiding failures in offline behavior.
- [x] Verify concurrent `load()` and `refresh()` calls do not perform redundant
      downloads or expose partially updated state.

### Parser and cache hardening

- [x] Validate declared counts against available input before reserving memory.
- [x] Reject integer overflow, reversed ranges, invalid ordering, and malformed
      name-table data.
- [x] Replace broad `corruptedData` failures with specific public validation
      diagnostics before stabilizing the error contract.
- [x] Add a corpus of malformed ULT2 fixtures.
- [x] Add fuzz or property-based parser coverage.
- [x] Verify database and metadata writes remain atomic and coherent across
      cancellation and process interruption.

### Exit criteria

- The default test suite is fully offline and deterministic.
- Live-network tests are isolated and clearly reported.
- All supported Apple-platform builds pass in CI using the documented minimum
  Swift 6.1 toolchain.
- Public documentation names only APIs that exist and states the 6.1 toolchain
  requirement accurately.
- The simple API has documented, tested configuration semantics.

## Milestone 0.5 — Make Database Freshness Observable and Efficient

Goal: let applications identify, audit, and refresh the database without
guesswork or unnecessary requests.

### Database metadata

- [ ] Define public `DatabaseMetadata` containing at least the format version,
      generation timestamp, source identifier, IPv4 and IPv6 range counts, and
      a stable build identifier.
- [ ] Extend ULT2 additively, using its reserved flags or a compatible trailer,
      so existing 0.4 readers can continue reading new files.
- [ ] Expose metadata on `UltraCompactDatabase` and distinguish embedded,
      bundled, disk-cache, and downloaded origins where that distinction is
      meaningful.
- [ ] Make metadata reproducible: identical normalized inputs and builder
      settings must produce the same build identifier and database bytes.

The source country field may be considered for a later result-format extension,
but it must be documented as routing-data attribution, not IP geolocation.

### Refresh protocol

- [ ] Replace the mandatory `HEAD`-then-`GET` flow with conditional requests
      (`If-None-Match` and `If-Modified-Since`) or document why a two-request
      flow remains necessary.
- [ ] Return useful refresh state, including the database metadata and whether
      the active database came from a bundle, cache, or download.
- [ ] Define behavior for servers without ETags or Last-Modified headers.
- [ ] Expose last successful check/update information without adding automatic
      background scheduling to the library.

### Artifact provenance

- [ ] Publish a machine-readable build manifest alongside hosted databases.
- [ ] Include source URLs, source digests, builder version, output digest,
      counts, and generation time in the manifest.
- [ ] Decide the trust model for hosted artifacts. A checksum detects accidental
      corruption but is not authenticity when served from the same origin; if
      authenticity is required, use a signed manifest and a pinned public key.
- [ ] Add update-workflow sanity thresholds for unexpected range-count or file
      size changes, while allowing an explicit maintainer override.

### Exit criteria

- A caller can report exactly which database build is active.
- An unchanged remote database requires one conditional request and no body
  download.
- Bundled and cached databases can be compared using database metadata rather
  than cache-file presence alone.
- Newly generated databases remain readable by the 0.4 ULT2 reader.
- The hosted artifact can be traced back to normalized source inputs and a
  builder version.

## Milestone 0.6 — Stabilize the Lookup API

Goal: provide an expressive result API while giving existing callers a clear
migration path toward 1.0.

### Typed results

- [ ] Introduce a small `ASNLookupResult` value type with `asn` and `name` as
      its guaranteed fields.
- [ ] Evaluate including the matched start/end range. Avoid claiming CIDR
      semantics unless the source range is proven to be a canonical CIDR.
- [ ] If country attribution is added, define its source and limitations and
      encode it without materially regressing load time or memory use.
- [ ] Resolve `ASNInfo`: either deprecate it in favor of the lookup result or
      redefine it only if every retained field has a reliable data source.

Because Swift cannot overload a method only by return type, the tuple-returning
`lookup` API should remain available during 0.x under its existing signature.
Typed results should first use a distinct method name, followed by a documented
1.0 migration decision.

### Address and batch APIs

- [ ] Add lookup from `IPAddress` so parsed addresses can be reused.
- [ ] Review the public raw `(hi, lo)` IPv6 API and provide a type-safe
      alternative before considering deprecation.
- [ ] Add a batch lookup API only after measuring its benefit over a caller loop;
      specify input-order preservation and miss representation.
- [ ] Document string parsing, invalid-address, private-address, and unrouted
      behavior consistently.

### Builder and CLI usability

- [ ] Replace whole-file TSV loading with streaming parsing to bound peak memory
      on large source files.
- [ ] Produce a build summary containing counts, skipped-row reasons, metadata,
      and output digest.
- [ ] Add a validation/inspection CLI command suitable for CI and hosted
      artifact diagnostics.
- [ ] Make invalid arguments and malformed input return stable, actionable
      errors rather than precondition failures.

### Exit criteria

- New applications can use a named, documented result type without tuples.
- Existing 0.4 lookup source continues to compile throughout the 0.6 line.
- All result fields have precise semantics backed by stored source data.
- The builder has bounded input-reading memory and reports rejected records.
- CLI validation can verify both embedded and downloaded production artifacts.

## Milestone 0.7 — Support Server-Side Swift

Goal: make the core library a credible dependency for Linux services and
command-line applications, not only Apple-platform apps.

### Portability work

- [ ] Replace or abstract Apple-only `Network` address parsing.
- [ ] Replace or abstract Apple-only `Compression` usage while retaining ULT2
      zlib compatibility.
- [ ] Use `FoundationNetworking` where required for remote updates.
- [ ] Define a Linux cache location following the XDG base-directory convention,
      with an explicit override still available.
- [ ] Audit file replacement and permissions behavior on Darwin and Linux.

### Support and CI

- [ ] Add an Ubuntu CI job for debug and release builds, unit tests, the CLI,
      and a database round trip.
- [ ] Keep public lookup and metadata behavior consistent across Darwin and
      Linux.
- [ ] Document any platform-specific remote cache or networking behavior.
- [ ] Establish the minimum supported Swift version and Linux distribution
      assumptions for the 1.0 line.

### Exit criteria

- `swift build`, `swift test`, and the documented CLI workflow pass on the
  supported Ubuntu environment.
- The same ULT2 fixture produces identical lookup results on Darwin and Linux.
- No Apple-only framework is required by the core lookup target.
- Remote refresh and cache tests pass deterministically on both platforms.

## Milestone 1.0 — Commit to the Contract

Goal: publish a narrow, durable API and compatibility policy suitable for
long-term adoption.

- [ ] Finalize the typed lookup API and complete announced deprecations.
- [ ] Decide whether the legacy compressed format stays supported, moves to a
      separate product, or is removed. Record the decision in the migration
      guide and changelog.
- [ ] Promise continued reading of released ULT2 databases and document how
      future format versions will be negotiated.
- [ ] Define semantic-versioning expectations for API, format, metadata, and
      hosted-artifact changes.
- [ ] Establish benchmark baselines for load time, peak memory, IPv4 lookup,
      IPv6 lookup, and database size; gate material regressions in CI.
- [ ] Add release automation covering tests, documentation, changelog, tag, and
      a clean-package consumer build.
- [ ] Publish a migration guide from the tuple lookup API and any retired legacy
      symbols.

### Exit criteria

- The public API has no placeholder or disconnected model types.
- Compatibility and support policies are documented and tested with fixtures.
- Release artifacts are reproducible and traceable.
- Performance claims in README and DocC are generated from or linked to a
  repeatable benchmark procedure.
- A clean external SwiftPM package can consume the tagged release on every
  supported platform.

## Research Backlog

These items are intentionally not assigned to a release. They require evidence
that they solve a measured user or performance problem:

- memory-mapped or block-compressed loading to reduce peak memory;
- a more compact IPv6 encoding or a ULT3 format;
- SIMD or specialized batch lookup;
- additional data sources or configurable source merging; and
- a build-tool plugin for embedding custom databases.

Moving an item out of research requires a short design note with the use case,
alternatives, compatibility impact, and benchmark or security rationale.

## Explicit Non-Goals

- IP geolocation, VPN/proxy detection, reputation, or threat intelligence.
- A live BGP collector or mutable routing table inside application processes.
- Automatic background refresh scheduling; applications control their own
  lifecycle and network policy.
- A hosted lookup API, user interface, or analytics service.
- A format rewrite solely to produce a smaller headline file size.
- Platform claims without CI coverage.

## Definition of Done for Roadmap Work

Every roadmap change should include, as applicable:

- unit tests and deterministic failure-path coverage;
- compatibility fixtures for format changes;
- performance and memory measurements for hot-path or format changes;
- public DocC and README updates;
- a changelog entry and migration notes for user-visible behavior; and
- an issue or design note recording decisions that affect the 1.0 contract.

Completed work should be removed from the active milestone sections and recorded
in `CHANGELOG.md`; this file should describe remaining direction rather than
duplicate release history.
