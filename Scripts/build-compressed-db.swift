#!/usr/bin/env swift
import Foundation

// Simple CLI to build a compressed database from a TSV file
// Usage: build-compressed-db.swift /path/to/ip2asn-v4.tsv /path/to/output.cdb

@discardableResult
func run(_ args: [String]) -> Int32 {
    var args = args
    guard args.count == 3 else {
        fputs("Usage: build-compressed-db.swift <input.tsv> <output.cdb>\n", stderr)
        exit(2)
    }

    let input = args[1]
    let output = args[2]

    do {
        try CompressedDatabaseFormat.createCompressed(from: input, to: output)
        print("✅ Wrote: \(output)")
        return 0
    } catch {
        fputs("❌ Failed: \(error)\n", stderr)
        return 1
    }
}

exit(run(CommandLine.arguments))
