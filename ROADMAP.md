# SwiftIP2ASN Roadmap

Last reviewed: 2026-11-22

SwiftIP2ASN 0.6.0 focuses on reproducible ULT2
builds, reliable remote refreshes, and correctness of the public address helpers.
See [CHANGELOG.md](CHANGELOG.md) for the release notes.

## Current Baseline

SwiftIP2ASN 0.6.0 provides:

- offline IPv4 and IPv6 ASN lookups from an embedded database;
- the ULT2 ultra-compact database format and builder;
- a `Sendable`, immutable lookup database;
- typed lookup results while retaining the 0.x tuple APIs;
- reproducible database metadata and machine-readable provenance manifests;
- an actor-based remote database with persistent caching, conditional refresh,
  and observable status;
- an `ip2asn` command-line tool for bundled lookups, artifact inspection and
  validation, database builds, and benchmarks;
- weekly embedded-database update automation and verified R2 publication; and
- SwiftPM support for current Apple platforms.

New roadmap work should be opened as a GitHub issue and attached to the
relevant milestone before implementation begins.

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

`0.7 Linux → 1.0 contract`

### Lookup contract established in 0.6

Use `lookupResult` for new code. Keep the named result and tuple methods under
their existing names through 1.0. There is no required migration in 0.6. For
multiple inputs, `addresses.map { db.lookupResult($0) }` preserves input order
and represents each miss with `nil`. A dedicated batch API stays in research
until a representative dual-stack benchmark demonstrates a benefit over this
caller loop.

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

- [ ] Confirm the lookup compatibility policy with a clean external consumer.
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
