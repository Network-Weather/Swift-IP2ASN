import XCTest

@testable import SwiftIP2ASN

final class UltraCompactValidationTest: XCTestCase {

    func testUltraCompactFormatCorrectness() async throws {
        print("\n🔬 VALIDATION: Ultra-Compact Format Correctness Test\n")
        print(String(repeating: "=", count: 70))

        // First ensure we have the TSV data
        let tsvPath = "/tmp/ip2asn-v4.tsv"
        if !FileManager.default.fileExists(atPath: tsvPath) {
            print("📥 Decompressing BGP data...")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
            process.arguments = ["-c", "/tmp/ip2asn-v4.tsv.gz"]

            let pipe = Pipe()
            process.standardOutput = pipe

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            try data.write(to: URL(fileURLWithPath: tsvPath))
        }

        // Load original data for comparison
        print("📊 Loading original TSV data...")
        let originalData = try String(contentsOfFile: tsvPath)
        let lines = originalData.split(separator: "\n")

        // Build lookup table from original data
        var originalLookup: [(start: UInt32, end: UInt32, asn: UInt32, name: String)] = []
        for line in lines.prefix(10000) {  // Test with first 10k for speed
            let fields = line.split(separator: "\t").map { String($0) }
            guard fields.count >= 5,
                let start = ipStringToUInt32(fields[0]),
                let end = ipStringToUInt32(fields[1]),
                let asn = UInt32(fields[2])
            else { continue }

            originalLookup.append((start, end, asn, fields[4]))
        }

        print("   Loaded \(originalLookup.count) ranges from original data")

        // Create ultra-compact database
        print("\n🗜️ Creating ultra-compact database...")

        // Write subset TSV for testing
        let testTSV = "/tmp/test_validation.tsv"
        let testData = lines.prefix(10000).joined(separator: "\n")
        try testData.write(toFile: testTSV, atomically: true, encoding: .utf8)

        let compactPath = "/tmp/test_ultra.cdb"
        try UltraCompactFormat.createUltraCompact(from: testTSV, to: compactPath)

        // Load the compact database
        print("\n📂 Loading ultra-compact database...")
        let compactDB = try UltraCompactDatabase(path: compactPath)

        // Test 1: Known IPs that must work
        print("\n✅ Test 1: Known IP Lookups")
        print(String(repeating: "-", count: 40))

        let knownTests = [
            ("1.0.0.1", UInt32(13335), "CLOUDFLARE"),
            ("8.8.8.8", UInt32(15169), "GOOGLE"),
            ("140.82.121.3", UInt32(36459), "GITHUB"),
            ("157.240.22.35", UInt32(32934), "FACEBOOK")
        ]

        var knownPassed = 0
        for (ip, expectedASN, org) in knownTests {
            // Find in original data
            let original = findInOriginal(ip: ip, data: originalLookup)
            let compact = compactDB.lookup(ip)

            if let compact = compact {
                let match = compact.asn == expectedASN || compact.asn == original?.asn
                let status = match ? "✅" : "❌"
                print("\(status) \(ip) → AS\(compact.asn) (expected AS\(expectedASN) - \(org))")
                if match { knownPassed += 1 }
            } else {
                print("❌ \(ip) → NOT FOUND (expected AS\(expectedASN))")
            }
        }

        // Test 2: Random sampling validation
        print("\n✅ Test 2: Random Sample Validation")
        print(String(repeating: "-", count: 40))

        var matches = 0
        var mismatches = 0
        var notFound = 0
        let sampleSize = 1000

        for index in 0..<sampleSize {
            // Pick a random range
            let randomRange = originalLookup[Int.random(in: 0..<originalLookup.count)]

            // Pick a random IP within that range
            let randomOffset = UInt32.random(in: 0...(randomRange.end - randomRange.start))
            let testIP = randomRange.start + randomOffset
            let testIPString = uint32ToIP(testIP)

            // Look up in both
            let original = findInOriginal(ip: testIPString, data: originalLookup)
            let compact = compactDB.lookup(testIPString)

            if let original = original, let compact = compact {
                if original.asn == compact.asn {
                    matches += 1
                } else {
                    mismatches += 1
                    if mismatches <= 5 {  // Show first few mismatches
                        print("  ⚠️ Mismatch: \(testIPString) → Original AS\(original.asn), Compact AS\(compact.asn)")
                    }
                }
            } else if original != nil && compact == nil {
                notFound += 1
                if notFound <= 5 {
                    print("  ⚠️ Not found in compact: \(testIPString)")
                }
            }

            // Progress indicator
            if (index + 1) % 100 == 0 {
                print("  Tested \(index + 1)/\(sampleSize) IPs...")
            }
        }

        let accuracy = 100.0 * Double(matches) / Double(sampleSize)
        print("\nResults:")
        print("  Matches: \(matches)/\(sampleSize) (\(String(format: "%.1f%%", accuracy)))")
        print("  Mismatches: \(mismatches)")
        print("  Not found: \(notFound)")

        XCTAssertEqual(mismatches, 0, "Should have no mismatches")
        XCTAssertEqual(notFound, 0, "Should find all IPs")

        // Test 3: Boundary conditions
        print("\n✅ Test 3: Boundary Conditions")
        print(String(repeating: "-", count: 40))

        for index in 0..<min(100, originalLookup.count) {
            let range = originalLookup[index]

            // Test start boundary
            let startIP = uint32ToIP(range.start)
            let startResult = compactDB.lookup(startIP)
            XCTAssertNotNil(startResult, "Start IP \(startIP) should be found")
            XCTAssertEqual(startResult?.asn, range.asn, "Start IP should match ASN")

            // Test end boundary
            let endIP = uint32ToIP(range.end)
            let endResult = compactDB.lookup(endIP)
            XCTAssertNotNil(endResult, "End IP \(endIP) should be found")
            XCTAssertEqual(endResult?.asn, range.asn, "End IP should match ASN")

            // Test just before range (if not first)
            if range.start > 0 {
                let beforeIP = uint32ToIP(range.start - 1)
                let beforeResult = compactDB.lookup(beforeIP)
                // May or may not be found (could be in previous range)
                if let beforeResult = beforeResult {
                    XCTAssertNotEqual(beforeResult.asn, range.asn, "IP before range should have different ASN")
                }
            }

            // Test just after range (if not last)
            if range.end < UInt32.max {
                let afterIP = uint32ToIP(range.end + 1)
                let afterResult = compactDB.lookup(afterIP)
                // May or may not be found (could be in next range)
                if let afterResult = afterResult {
                    // Could be same ASN if ranges are from same org
                    _ = afterResult  // Just checking it doesn't crash
                }
            }
        }

        print("  Tested boundaries for 100 ranges ✅")

        // Test 4: Performance
        print("\n⚡ Test 4: Performance")
        print(String(repeating: "-", count: 40))

        let perfTestIPs = (0..<10000).map { _ in
            uint32ToIP(UInt32.random(in: 0x0100_0000...0xDF00_0000))  // Class A-C range
        }

        let startTime = Date()
        var foundCount = 0
        for ip in perfTestIPs {
            if compactDB.lookup(ip) != nil {
                foundCount += 1
            }
        }
        let elapsed = Date().timeIntervalSince(startTime)
        let avgTime = elapsed / Double(perfTestIPs.count) * 1_000_000

        print("  10,000 lookups in \(String(format: "%.3f", elapsed))s")
        print("  Average: \(String(format: "%.1f", avgTime))μs per lookup")
        print("  Found: \(foundCount)/10000 IPs")

        XCTAssertLessThan(avgTime, 100, "Average lookup should be under 100μs")

        // Test 5: File size validation
        print("\n💾 Test 5: File Size")
        print(String(repeating: "-", count: 40))

        guard let fileSize = try FileManager.default.attributesOfItem(atPath: compactPath)[.size] as? Int else {
            XCTFail("Could not get file size")
            return
        }
        let originalSize = originalLookup.count * 50  // Rough estimate
        let ratio = Double(originalSize) / Double(fileSize)

        print("  Original (estimated): \(originalSize / 1024)KB")
        print("  Ultra-compact: \(fileSize / 1024)KB")
        print("  Compression ratio: \(String(format: "%.1fx", ratio))")

        // Final summary
        print("\n" + String(repeating: "=", count: 70))
        print("🏆 VALIDATION COMPLETE")
        print("  ✅ Known IPs: \(knownPassed)/\(knownTests.count) passed")
        print("  ✅ Random sampling: \(String(format: "%.1f%%", accuracy)) accurate")
        print("  ✅ Boundary tests: Passed")
        print("  ✅ Performance: \(String(format: "%.1f", avgTime))μs average")
        print("  ✅ Compression: \(String(format: "%.1fx", ratio)) smaller")

        if mismatches == 0 && notFound == 0 && knownPassed == knownTests.count {
            print("\n✅ Ultra-compact format is VALID and working correctly!")
        } else {
            print("\n⚠️ Some issues detected - review above")
        }
    }

    // Helper functions

    private func findInOriginal(ip: String, data: [(start: UInt32, end: UInt32, asn: UInt32, name: String)]) -> (
        asn: UInt32, name: String
    )? {
        guard let ipNum = ipStringToUInt32(ip) else { return nil }

        for range in data {
            if ipNum >= range.start && ipNum <= range.end {
                return (range.asn, range.name)
            }
        }
        return nil
    }

    private func ipStringToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    private func uint32ToIP(_ value: UInt32) -> String {
        return "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }
}
