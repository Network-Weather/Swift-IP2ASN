import Network
import XCTest

@testable import SwiftIP2ASN

final class OverlapValidationTest: XCTestCase {

    func testNoOverlappingRanges() async throws {
        print("\n🔍 Validating that BGP database has NO overlapping IP ranges...\n")

        // First, let's check a sample from the actual database
        print("📊 Checking first 100 ranges for overlaps...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "gunzip -c /tmp/ip2asn-v4.tsv.gz | head -100"]

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

        print("Parsed \(ranges.count) ranges")

        // Sort by start IP
        ranges.sort { $0.start < $1.start }

        // Check for overlaps
        var overlaps: [(String, String)] = []
        for i in 0..<ranges.count - 1 {
            let current = ranges[i]
            let next = ranges[i + 1]

            // Check if current range overlaps with next
            if current.end >= next.start {
                let currentIP = uint32ToIP(current.start) + "-" + uint32ToIP(current.end)
                let nextIP = uint32ToIP(next.start) + "-" + uint32ToIP(next.end)

                print("\n❌ OVERLAP FOUND!")
                print("   Range 1: \(currentIP) (AS\(current.asn))")
                print("   Range 2: \(nextIP) (AS\(next.asn))")

                overlaps.append((currentIP, nextIP))
            }
        }

        if overlaps.isEmpty {
            print("\n✅ No overlaps found in first 100 ranges!")
        } else {
            print("\n❌ Found \(overlaps.count) overlaps!")
        }

        // Now let's check for gaps and continuity
        print("\n📈 Checking for gaps between ranges...")

        var gaps: [(String, String, UInt32)] = []
        for i in 0..<min(20, ranges.count - 1) {  // Check first 20 for gaps
            let current = ranges[i]
            let next = ranges[i + 1]

            if current.end + 1 < next.start {
                let gapSize = next.start - current.end - 1
                let gapStart = uint32ToIP(current.end + 1)
                let gapEnd = uint32ToIP(next.start - 1)

                gaps.append((gapStart, gapEnd, gapSize))
                print("   Gap: \(gapStart) to \(gapEnd) (\(gapSize) IPs)")
            }
        }

        if gaps.isEmpty {
            print("   No gaps found - ranges are contiguous")
        } else {
            print("   Found \(gaps.count) gaps (unrouted IP space)")
        }

        // Check the full database for overlap statistics
        print("\n📊 Full database overlap check (this may take a moment)...")

        let fullCheck = try await checkFullDatabase()
        print("\nFull database results:")
        print("   Total ranges: \(fullCheck.totalRanges)")
        print("   Overlapping ranges: \(fullCheck.overlaps)")
        print("   Maximum range size: \(fullCheck.maxRangeSize) IPs")
        print("   Minimum range size: \(fullCheck.minRangeSize) IPs")
        print("   Ranges that are NOT powers of 2: \(fullCheck.nonPowerOf2)")

        // Validate no overlaps
        XCTAssertEqual(fullCheck.overlaps, 0, "Database should have NO overlapping ranges")

        if fullCheck.overlaps == 0 {
            print("\n✅ CONFIRMED: The BGP database has NO overlapping ranges!")
            print("   This means we CAN use a binary search approach for arbitrary ranges!")
        }

        print("\n💡 Recommendation:")
        print("   Since \(fullCheck.nonPowerOf2) out of \(fullCheck.totalRanges) ranges")
        print("   are NOT powers of 2, we should use a binary search tree")
        print("   or sorted array that can handle arbitrary ranges,")
        print("   not just CIDR blocks.")
    }

    private func checkFullDatabase() async throws -> (
        totalRanges: Int, overlaps: Int, maxRangeSize: UInt32, minRangeSize: UInt32, nonPowerOf2: Int
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
                gunzip -c /tmp/ip2asn-v4.tsv.gz | awk -F'\t' '
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
            """,
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
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }

    enum TestError: Error {
        case parseError
    }
}
