# Upgrading to 0.6.0

Update your Swift package dependency, keep your existing lookup code and ULT2 databases, and check any scripts that build a database from TSV files.

## Update an app from 0.5.x

Choose 0.6.0 in your package manager. If your `Package.swift` pins an exact 0.5.x release, change the pin to `exact: "0.6.0"`. If your version requirement already allows 0.6.0, run `swift package update swift-ip2asn` and check the version in `Package.resolved`. The minimum toolchain is Swift 6.1.

Both tuple-returning `lookup` calls and typed `lookupResult` calls compile as before. Existing ULT2 files and the on-disk cache work with 0.6.0. Apps using ``RemoteDatabase`` can keep their refresh schedule. When validators are available, `refresh()` sends them to the server and bypasses URLSession’s local HTTP cache. This fixes a refresh that could return HTTP 404 after a successful download.

If you use ``IPRange`` for subnet membership, partial-byte prefixes such as IPv4 `/25` and IPv6 `/127` now work correctly. An out-of-range prefix length passed to `init(start:prefixLength:)` makes `contains` return `false`.

## Update a custom database build

The ULT2 builder now stops on malformed input and identifies the source file, line, and reason. If an existing TSV stops building, check the reported row for missing columns, an invalid endpoint or ASN, a reversed range, or an overlap with another routed range. Start and end addresses are inclusive, so two routed rows sharing an endpoint overlap. Each row can contain up to 1 MiB. Blank lines and rows with ASN 0 are counted and skipped.

A successful `ip2asn build-ultra` writes the compressed database to the output path and a JSON report to standard output. Scripts can capture the report and read the output digest and range count.

```sh
ip2asn build-ultra ip2asn-v4.tsv ip2asn-v6.tsv out.ultra > build-report.json &&
  jq '{sha256: .artifact.sha256, ranges: .database.totalRangeCount, rows: .rows}' build-report.json
```

The report counts every input row in `rows.total`. Subtract `rows.blank` and `rows.unrouted` to get the number of stored ranges. Build errors go to standard error and return a nonzero exit status. If your pipeline uses the provenance manifest, continue generating it with the existing manifest options.

Scripts that run `bench-ultra` or `bench-compressed` should check the exit status before reading timings. An invalid iteration count exits with status 2, and a database load error exits with status 1.

## Check which data you loaded

The 0.6.0 package bundles the database generated on November 16, 2026. The project checks the upstream data weekly, and the hosted database can advance independently of the Swift package. To identify the database your app actually used, read its `metadata.buildIdentifier` and `metadata.generationTimestamp`. The CLI command `ip2asn inspect` reports the identity of its bundled database, and `ip2asn inspect --database out.ultra` inspects a specific file.

[Full 0.6.0 release notes](https://github.com/Network-Weather/Swift-IP2ASN/releases/tag/v0.6.0)
