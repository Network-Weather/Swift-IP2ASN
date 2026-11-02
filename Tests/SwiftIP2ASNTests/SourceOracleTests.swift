import Foundation
import XCTest

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

/// Checks the bundled database against the exact TSV files it was built from.
///
/// The manifest proves which inputs went in and which bytes came out; this test
/// proves the bytes answer correctly. For every source row, the first and last
/// address must resolve to the row's ASN (or to no result for ASN 0 rows).
///
/// The sources are read from `IP2ASN_SOURCE_DIR` (default `/tmp`) as
/// `ip2asn-v4.tsv` and `ip2asn-v6.tsv`, which is where the update workflow
/// leaves them. When they are absent or are not the manifest's builder inputs,
/// the test skips, unless `IP2ASN_REQUIRE_SOURCE_ORACLE=1`, in which case it
/// fails so a CI run cannot pass without checking.
final class SourceOracleTests: XCTestCase {
    private struct Mismatch: CustomStringConvertible {
        let line: String
        let address: String
        let got: (asn: UInt32, name: String?)?

        var description: String {
            let found = got.map { "AS\($0.asn) \($0.name ?? "<nil>")" } ?? "no result"
            return "\(address) → \(found); source row: \(line)"
        }
    }

    func testBundledDatabaseMatchesSourceRows() throws {
        let environment = ProcessInfo.processInfo.environment
        let required = environment["IP2ASN_REQUIRE_SOURCE_ORACLE"] == "1"
        let directory = URL(fileURLWithPath: environment["IP2ASN_SOURCE_DIR"] ?? "/tmp")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            DatabaseBuildManifest.self,
            from: Data(contentsOf: EmbeddedDatabase.manifestURL())
        )
        let database = try EmbeddedDatabase.loadUltraCompact()

        var checkedFamilies = 0
        for family in ["v4", "v6"] {
            let fileName = "ip2asn-\(family).tsv"
            let sourceURL = directory.appendingPathComponent(fileName)
            guard let source = manifest.sources.first(where: { $0.url.hasSuffix("ip2asn-\(family).tsv.gz") }) else {
                XCTFail("Manifest has no \(family) source")
                continue
            }
            guard let data = FileManager.default.contents(atPath: sourceURL.path) else {
                try skipOrFail(required, "\(sourceURL.path) is missing")
                continue
            }
            let digest = StableSHA256.digest(data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard digest == source.builderInput.sha256, data.count == source.builderInput.byteCount else {
                try skipOrFail(
                    required,
                    "\(sourceURL.path) (SHA-256 \(digest)) is not the manifest's builder input "
                        + "(\(source.builderInput.sha256))"
                )
                continue
            }

            let result = try check(data: data, family: family, database: database)
            XCTAssertEqual(
                result.failures, 0,
                "\(result.failures) of \(result.rows * 2) \(family) boundary lookups disagree with the "
                    + "source. First \(result.samples.count):\n"
                    + result.samples.map(\.description).joined(separator: "\n")
            )
            XCTAssertGreaterThan(result.rows, 50_000, "Suspiciously few \(family) source rows")
            checkedFamilies += 1
        }
        if checkedFamilies == 0 {
            try skipOrFail(required, "No source TSV matched the manifest")
        }
    }

    private func check(
        data: Data,
        family: String,
        database: UltraCompactDatabase
    ) throws -> (rows: Int, failures: Int, samples: [Mismatch]) {
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        var rows = 0
        var failures = 0
        var samples: [Mismatch] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 5, let asn = UInt32(fields[2]) else {
                XCTFail("Unparseable \(family) source row: \(line)")
                continue
            }
            rows += 1
            for address in [String(fields[0]), String(fields[1])] {
                let got: (asn: UInt32, name: String?)?
                if family == "v4" {
                    let value = try XCTUnwrap(parseIPv4ToUInt32(address), "Bad IPv4 \(address)")
                    got = database.lookup(ip: value)
                } else {
                    let pair = try XCTUnwrap(parseIPv6ToPair(address), "Bad IPv6 \(address)")
                    got = database.lookupV6(hi: pair.hi, lo: pair.lo)
                }
                let correct = asn == 0 ? got == nil : got?.asn == asn && got?.name == String(fields[4])
                if !correct {
                    failures += 1
                    if samples.count < 10 {
                        samples.append(Mismatch(line: String(line), address: address, got: got))
                    }
                }
            }
        }
        return (rows, failures, samples)
    }

    private func skipOrFail(_ required: Bool, _ reason: String) throws {
        if required {
            XCTFail("IP2ASN_REQUIRE_SOURCE_ORACLE=1 but \(reason)")
        } else {
            throw XCTSkip("\(reason); set IP2ASN_SOURCE_DIR to the build inputs to run")
        }
    }
}
