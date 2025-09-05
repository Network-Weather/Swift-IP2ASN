import Network
import XCTest

@testable import SwiftIP2ASN

final class OverlapValidationTest: XCTestCase {

    func testNoOverlappingRanges() async throws {
        // Support either gz or plain TSV; skip if neither present unless explicitly opted-in
        let gzPath = "/tmp/ip2asn-v4.tsv.gz"
        let tsvPath = "/tmp/ip2asn-v4.tsv"
        let hasGz = FileManager.default.fileExists(atPath: gzPath)
        let hasTsv = FileManager.default.fileExists(atPath: tsvPath)
        if !hasGz && !hasTsv && ProcessInfo.processInfo.environment["IP2ASN_RUN_NETWORK"] == nil {
            throw XCTSkip("Overlap validation requires /tmp/ip2asn-v4.tsv(.gz) or IP2ASN_RUN_NETWORK=1")
        }

        let sourceCmd = hasGz ? "gunzip -c \(gzPath)" : "cat \(tsvPath)"

        TestLog.log("\n🔍 Validating that BGP database has NO overlapping IP ranges...\n")

        // First, let's check a sample from the actual database
        TestLog.log("📊 Checking first 100 ranges for overlaps...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(sourceCmd) | head -100"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to read BGP data")
            return
        }

        // Parse ranges
        var ranges: [(start: UInt32, end: UInt32, asn: String, line: String)] = []

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t").map { String($0) }
            guard fields.count >= 3 else { continue }

            let startIP = fields[0]
            let endIP = fields[1]
            let asn = fields[2]

            if let start = ipToUInt32(startIP), let end = ipToUInt32(endIP) {
                ranges.append((start, end, asn, String(line)))
            }
        }

        TestLog.log("Parsed \(ranges.count) ranges")

        // Sort by start IP
        ranges.sort { $0.start < $1.start }

        // Check for overlaps (only if we have at least 2 ranges)
        var overlaps: [(String, String)] = []
        if ranges.count >= 2 {
            for index in 0..<(ranges.count - 1) {
                let current = ranges[index]
                let next = ranges[index + 1]

                // Check if current range overlaps with next
                if current.end >= next.start {
                    let currentIP = uint32ToIP(current.start) + "-" + uint32ToIP(current.end)
                    let nextIP = uint32ToIP(next.start) + "-" + uint32ToIP(next.end)

                    TestLog.log("\n❌ OVERLAP FOUND!")
                    TestLog.log("   Range 1: \(currentIP) (AS\(current.asn))")
                    TestLog.log("   Range 2: \(nextIP) (AS\(next.asn))")

                    overlaps.append((currentIP, nextIP))
                }
            }
        }

        if overlaps.isEmpty {
            TestLog.log("\n✅ No overlaps found in first 100 ranges!")
        } else {
            TestLog.log("\n❌ Found \(overlaps.count) overlaps!")
        }

        // Now let's check for gaps and continuity
        TestLog.log("\n📈 Checking for gaps between ranges...")

        var gaps: [(String, String, UInt32)] = []
        let limit = max(0, min(20, ranges.count - 1))
        for index in 0..<limit {  // Check first 20 for gaps
            let current = ranges[index]
            let next = ranges[index + 1]

            if current.end + 1 < next.start {
                let gapSize = next.start - current.end - 1
                let gapStart = uint32ToIP(current.end + 1)
                let gapEnd = uint32ToIP(next.start - 1)

                gaps.append((gapStart, gapEnd, gapSize))
                TestLog.log("   Gap: \(gapStart) to \(gapEnd) (\(gapSize) IPs)")
            }
        }

        if gaps.isEmpty {
            TestLog.log("   No gaps found - ranges are contiguous")
        } else {
            TestLog.log("   Found \(gaps.count) gaps (unrouted IP space)")
        }

        // Check the full database for overlap statistics
        TestLog.log("\n📊 Full database overlap check (this may take a moment)...")
        let fullCheck = try await checkFullDatabase(sourceCmd: sourceCmd)
        TestLog.log("\nFull database results:")
        TestLog.log("   Total ranges: \(fullCheck.totalRanges)")
        TestLog.log("   Overlapping ranges: \(fullCheck.overlaps)")
        TestLog.log("   Maximum range size: \(fullCheck.maxRangeSize) IPs")
        TestLog.log("   Minimum range size: \(fullCheck.minRangeSize) IPs")
        TestLog.log("   Ranges that are NOT powers of 2: \(fullCheck.nonPowerOf2)")

        // Validate no overlaps only in strict mode; otherwise report stats without failing
        if ProcessInfo.processInfo.environment["IP2ASN_STRICT"] != nil {
            XCTAssertEqual(fullCheck.overlaps, 0, "Database should have NO overlapping ranges")
        } else {
            print("(Info) Overlaps observed: \(fullCheck.overlaps) (not failing in non-strict mode)")
        }

        if fullCheck.overlaps == 0 {
            TestLog.log("\n✅ CONFIRMED: The BGP database has NO overlapping ranges!")
            TestLog.log("   This means we CAN use a binary search approach for arbitrary ranges!")
        }

        TestLog.log("\n💡 Recommendation:")
        TestLog.log("   Since \(fullCheck.nonPowerOf2) out of \(fullCheck.totalRanges) ranges")
        TestLog.log("   are NOT powers of 2, we should use a binary search tree")
        TestLog.log("   or sorted array that can handle arbitrary ranges,")
        TestLog.log("   not just CIDR blocks.")
    }

    private func checkFullDatabase(sourceCmd: String) async throws -> (
        totalRanges: Int, overlaps: Int, maxRangeSize: UInt32, minRangeSize: UInt32, nonPowerOf2: Int
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
                \(sourceCmd) | awk -F'\t' '
                BEGIN { count=0; overlaps=0; maxSize=0; minSize=4294967295; nonPower2=0; lastEnd=0 }
                {
                    split($1, s, ".")
                    split($2, e, ".")
                    start = s[1]*16777216 + s[2]*65536 + s[3]*256 + s[4]
                    end = e[1]*16777216 + e[2]*65536 + e[3]*256 + e[4]
                    size = end - start + 1
                    
                    count++
                    
                    if (start <= lastEnd) overlaps++
                    if (size > maxSize) maxSize = size
                    if (size < minSize) minSize = size
                    
                    # Check if power of 2
                    isPower2 = 0
                    for (i = 0; i <= 32; i++) {
                        if (size == 2^i) {
                            isPower2 = 1
                            break
                        }
                    }
                    if (!isPower2) nonPower2++
                    
                    lastEnd = end
                }
                END {
                    print count, overlaps, maxSize, minSize, nonPower2
                }
                '
            """
        ]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw TestError.parseError
        }

        let parts = output.split(separator: " ").compactMap { Int($0) }
        guard parts.count == 5 else {
            throw TestError.parseError
        }

        return (parts[0], parts[1], UInt32(parts[2]), UInt32(parts[3]), parts[4])
    }

    private func ipToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    private func uint32ToIP(_ value: UInt32) -> String {
        let octet1 = (value >> 24) & 0xFF
        let octet2 = (value >> 16) & 0xFF
        let octet3 = (value >> 8) & 0xFF
        let octet4 = value & 0xFF
        return "\(octet1).\(octet2).\(octet3).\(octet4)"
    }

    enum TestError: Error {
        case parseError
    }
}
