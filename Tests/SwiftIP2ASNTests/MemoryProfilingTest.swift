import XCTest

@testable import SwiftIP2ASN

final class MemoryProfilingTest: XCTestCase {

    func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        return String(format: "%.2f MB", mb)
    }

    func formatKB(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        return String(format: "%.1f KB", kb)
    }

    func testMemoryUsageOfEmbeddedDatabase() throws {
        print("\n" + String(repeating: "=", count: 70))
        print("MEMORY PROFILING: Embedded UltraCompact Database")
        print(String(repeating: "=", count: 70))

        let baseMemory = getMemoryUsage()
        print("\nBase memory: \(formatBytes(baseMemory))")

        // Load embedded database
        print("\n📦 Loading embedded UltraCompact database...")
        let db = try EmbeddedDatabase.loadUltraCompact()

        let afterLoad = getMemoryUsage()
        let delta = afterLoad > baseMemory ? afterLoad - baseMemory : 0

        print("   Entries: \(db.entryCount)")
        print("   Unique ASNs: \(db.uniqueASNCount)")
        print("   Memory after load: \(formatBytes(afterLoad))")
        print("   Memory delta: \(formatBytes(delta))")

        // Calculate theoretical minimum
        // Each range: startIP (4) + endIP (4) + asn (4) = 12 bytes per entry
        let rangeBytes = db.entryCount * 12
        // ASN names: assume ~30 bytes average per name
        let asnNameBytes = db.uniqueASNCount * 30
        let theoreticalMin = rangeBytes + asnNameBytes

        print("\n📊 Theoretical Analysis:")
        print("   Range arrays (3 × \(db.entryCount) × 4 bytes): \(formatKB(UInt64(rangeBytes)))")
        print("   ASN names (~\(db.uniqueASNCount) × 30 bytes): \(formatKB(UInt64(asnNameBytes)))")
        print("   Theoretical minimum: \(formatKB(UInt64(theoreticalMin)))")
        print("   Actual delta: \(formatKB(delta))")

        if delta > 0 {
            let overhead = Double(delta) / Double(theoreticalMin)
            print("   Overhead ratio: \(String(format: "%.2fx", overhead))")
        }

        // Verify lookups work
        print("\n🔍 Verifying lookups work:")
        let testIPs = ["8.8.8.8", "1.1.1.1", "140.82.121.3"]
        for ip in testIPs {
            if let result = db.lookup(ip) {
                print("   ✅ \(ip) → AS\(result.asn)")
            } else {
                print("   ❌ \(ip) → NOT FOUND")
            }
        }

        print("\n" + String(repeating: "=", count: 70))
    }

    func testLookupPerformance() throws {
        print("\n" + String(repeating: "=", count: 70))
        print("PERFORMANCE: Lookup Speed")
        print(String(repeating: "=", count: 70))

        let db = try EmbeddedDatabase.loadUltraCompact()
        print("\nDatabase loaded: \(db.entryCount) entries")

        // Warmup
        for _ in 0..<1000 {
            _ = db.lookup(ip: UInt32.random(in: 0x0100_0000...0xDF00_0000))
        }

        // Benchmark
        let iterations = 100_000
        print("\n⚡ Running \(iterations) random lookups...")

        let start = Date()
        var found = 0
        for _ in 0..<iterations {
            let randomIP = UInt32.random(in: 0x0100_0000...0xDF00_0000)
            if db.lookup(ip: randomIP) != nil {
                found += 1
            }
        }
        let elapsed = Date().timeIntervalSince(start)

        let lookupsPerSec = Double(iterations) / elapsed
        let nsPerLookup = (elapsed * 1_000_000_000) / Double(iterations)

        print("   Time: \(String(format: "%.3f", elapsed))s")
        print(
            "   Found: \(found)/\(iterations) (\(String(format: "%.1f%%", Double(found) / Double(iterations) * 100)))")
        print("   Lookups/sec: \(String(format: "%.0f", lookupsPerSec))")
        print("   Nanoseconds/lookup: \(String(format: "%.0f", nsPerLookup))")

        // Also test string parsing overhead
        print("\n⚡ Running \(iterations) string lookups (includes parsing)...")
        let testIPs = (0..<1000).map { _ -> String in
            let a = UInt8.random(in: 1...223)
            let b = UInt8.random(in: 0...255)
            let c = UInt8.random(in: 0...255)
            let d = UInt8.random(in: 0...255)
            return "\(a).\(b).\(c).\(d)"
        }

        let start2 = Date()
        var found2 = 0
        for i in 0..<iterations {
            let ip = testIPs[i % testIPs.count]
            if db.lookup(ip) != nil {
                found2 += 1
            }
        }
        let elapsed2 = Date().timeIntervalSince(start2)

        let lookupsPerSec2 = Double(iterations) / elapsed2
        let nsPerLookup2 = (elapsed2 * 1_000_000_000) / Double(iterations)

        print("   Time: \(String(format: "%.3f", elapsed2))s")
        print("   Lookups/sec: \(String(format: "%.0f", lookupsPerSec2))")
        print("   Nanoseconds/lookup: \(String(format: "%.0f", nsPerLookup2))")
        print("   String parsing overhead: \(String(format: "%.0f", nsPerLookup2 - nsPerLookup))ns")

        print("\n" + String(repeating: "=", count: 70))

        // Assert reasonable performance (debug builds are slower)
        XCTAssertLessThan(nsPerLookup, 5000, "Lookup should be under 5 microseconds in debug")
    }
}
