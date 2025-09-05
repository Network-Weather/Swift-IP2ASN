import XCTest

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

final class DatabaseFormatTest: XCTestCase {

    func testDatabaseFormats() async throws {
        // Skip unless explicitly enabled (avoids using external tools and large files by default)
        if ProcessInfo.processInfo.environment["IP2ASN_RUN_FORMAT_TESTS"] == nil {
            throw XCTSkip("Format/size comparison disabled by default; set IP2ASN_RUN_FORMAT_TESTS=1 to enable")
        }
        print("\n📊 Comparing Database Formats for Embedding\n")

        // First, get the BGP data
        print("📥 Preparing test data...")

        let tsvPath = "/tmp/ip2asn-v4.tsv"

        // Ensure we have uncompressed TSV; skip if not present to keep tests fast/offline
        guard
            FileManager.default.fileExists(atPath: tsvPath)
                || FileManager.default.fileExists(atPath: "/tmp/ip2asn-v4.tsv.gz")
        else {
            throw XCTSkip(
                "No TSV present in /tmp; provide test data or set IP2ASN_RUN_FORMAT_TESTS=1 with files present")
        }
        if !FileManager.default.fileExists(atPath: tsvPath),
            FileManager.default.fileExists(atPath: "/tmp/ip2asn-v4.tsv.gz")
        {
            print("   Decompressing BGP data...")
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

        // Get file size
        guard let tsvSize = try FileManager.default.attributesOfItem(atPath: tsvPath)[.size] as? Int else {
            XCTFail("Could not get TSV file size")
            return
        }
        print("   Original TSV: \(tsvSize / 1024 / 1024)MB")

        // Parse a subset for testing
        print("\n🔧 Testing with first 10,000 entries...")

        let fullData = try String(contentsOfFile: tsvPath)
        let lines = fullData.split(separator: "\n").prefix(10000)

        var entries: [(startIP: String, endIP: String, asn: UInt32, name: String?)] = []
        for line in lines {
            let fields = line.split(separator: "\t").map { String($0) }
            if fields.count >= 5,
                let asn = UInt32(fields[2])
            {
                entries.append((fields[0], fields[1], asn, fields[4]))
            }
        }

        print("   Parsed \(entries.count) entries")

        // Test 1: Binary format
        print("\n1️⃣ Binary Format (memory-mapped):")
        let binaryPath = URL(fileURLWithPath: "/tmp/ip2asn.bin")

        let binaryStart = Date()
        try BinaryDatabaseFormat.serialize(ranges: entries, to: binaryPath)
        let binaryWriteTime = Date().timeIntervalSince(binaryStart)

        guard let binarySize = try FileManager.default.attributesOfItem(atPath: binaryPath.path)[.size] as? Int else {
            XCTFail("Could not get binary file size")
            return
        }
        print("   File size: \(binarySize / 1024)KB")
        print("   Write time: \(String(format: "%.3f", binaryWriteTime))s")

        // Test loading
        let loadStart = Date()
        let mmapDB = try BinaryDatabaseFormat.deserialize(from: binaryPath)
        let loadTime = Date().timeIntervalSince(loadStart)
        print("   Load time: \(String(format: "%.3f", loadTime))s")

        // Test lookups
        let testIPs = ["8.8.8.8", "1.1.1.1", "140.82.121.3"]
        var lookupTimes: [Double] = []
        for ip in testIPs {
            let start = Date()
            _ = mmapDB.lookup(ip)
            lookupTimes.append(Date().timeIntervalSince(start) * 1_000_000)
        }
        print("   Avg lookup: \(String(format: "%.1f", lookupTimes.reduce(0, +) / Double(lookupTimes.count)))μs")

        // Test 2: Compressed format
        print("\n2️⃣ Compressed Format (zlib + delta encoding):")
        let compressedPath = "/tmp/ip2asn.cdb"

        // Create a temp TSV with our subset
        let tempTSV = "/tmp/test_subset.tsv"
        let subsetData = lines.joined(separator: "\n")
        try subsetData.write(toFile: tempTSV, atomically: true, encoding: .utf8)

        let compressStart = Date()
        try CompressedDatabaseBuilder.createCompressed(from: tempTSV, to: compressedPath)
        let compressTime = Date().timeIntervalSince(compressStart)

        guard let compressedSize = try FileManager.default.attributesOfItem(atPath: compressedPath)[.size] as? Int
        else {
            XCTFail("Could not get compressed file size")
            return
        }
        print("   Write time: \(String(format: "%.3f", compressTime))s")

        // Test loading
        let cLoadStart = Date()
        let compactDB = try CompressedDatabaseFormat.loadCompressed(from: compressedPath)
        let cLoadTime = Date().timeIntervalSince(cLoadStart)
        print("   Load time: \(String(format: "%.3f", cLoadTime))s")
        print("   Entries loaded: \(compactDB.entryCount)")

        // Test lookups
        var cLookupTimes: [Double] = []
        for ip in testIPs {
            let start = Date()
            _ = compactDB.lookup(ip)
            cLookupTimes.append(Date().timeIntervalSince(start) * 1_000_000)
        }
        print("   Avg lookup: \(String(format: "%.1f", cLookupTimes.reduce(0, +) / Double(cLookupTimes.count)))μs")

        // Test 3: Estimate full database sizes
        print("\n📈 Estimated Full Database Sizes (500k entries):")
        let scaleFactor = 504984.0 / Double(entries.count)

        print("   Binary format: ~\(Int(Double(binarySize) * scaleFactor / 1024 / 1024))MB")
        print("   Compressed format: ~\(Int(Double(compressedSize) * scaleFactor / 1024 / 1024))MB")
        print("   Original gzip TSV: 6.2MB")

        // Recommendations
        print("\n🎯 Recommendations for App Embedding:")
        print(String(repeating: "─", count: 60))
        print("For iOS/macOS apps, use Compressed Format because:")
        print("  ✅ Smallest file size (~\(Int(Double(compressedSize) * scaleFactor / 1024 / 1024))MB)")
        print("  ✅ Fast load time (decompression is fast)")
        print("  ✅ Good lookup performance (<10μs)")
        print("  ✅ Can be embedded as app resource")
        print("\nFor server applications, use Memory-Mapped Binary:")
        print("  ✅ Zero-copy loading (instant)")
        print("  ✅ Minimal memory usage (OS manages paging)")
        print("  ✅ Best lookup performance")
        print("  ⚠️  Larger file size (~\(Int(Double(binarySize) * scaleFactor / 1024 / 1024))MB)")

        // Clean up
        try? FileManager.default.removeItem(atPath: tempTSV)
    }

    func testFullDatabaseCompression() async throws {
        print("\n🗜️ Testing Full Database Compression\n")

        guard FileManager.default.fileExists(atPath: "/tmp/ip2asn-v4.tsv.gz") else {
            print("⚠️  Skipping - BGP data not available")
            return
        }

        // Create compressed database from full data
        print("Creating compressed database from 500k entries...")

        // First decompress if needed
        let tsvPath = "/tmp/ip2asn-v4.tsv"
        if !FileManager.default.fileExists(atPath: tsvPath) {
            print("  Decompressing TSV...")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
            process.arguments = ["-kc", "/tmp/ip2asn-v4.tsv.gz"]

            let pipe = Pipe()
            process.standardOutput = pipe

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            try data.write(to: URL(fileURLWithPath: tsvPath))
        }

        let compressedPath = "/tmp/ip2asn-full.cdb"

        let start = Date()
        try CompressedDatabaseBuilder.createCompressed(from: tsvPath, to: compressedPath)
        let elapsed = Date().timeIntervalSince(start)

        guard let size = try FileManager.default.attributesOfItem(atPath: compressedPath)[.size] as? Int else {
            XCTFail("Could not get compressed file size")
            return
        }

        print("\n📊 Full Database Results:")
        print("   Original TSV.gz: 6.2MB")
        print("   Compressed DB: \(size / 1024 / 1024)MB")
        print("   Creation time: \(String(format: "%.1f", elapsed))s")

        // Test loading and lookup
        print("\n⚡ Performance Test:")
        let loadStart = Date()
        let db = try CompressedDatabaseFormat.loadCompressed(from: compressedPath)
        print("   Load time: \(String(format: "%.3f", Date().timeIntervalSince(loadStart)))s")
        print("   Entries: \(db.entryCount)")

        // Test some lookups
        let testCases = [
            ("8.8.8.8", UInt32(15169)),  // Google
            ("1.1.1.1", UInt32(13335)),  // Cloudflare
            ("140.82.121.3", UInt32(36459)),  // GitHub
            ("157.240.22.35", UInt32(32934))  // Facebook
        ]

        print("\n🎯 Lookup Tests:")
        for (ip, expectedASN) in testCases {
            let start = Date()
            let asn = db.lookup(ip)
            let elapsed = Date().timeIntervalSince(start) * 1_000_000

            let status = asn == expectedASN ? "✅" : "❌"
            print("   \(status) \(ip) → AS\(asn ?? 0) in \(String(format: "%.1f", elapsed))μs")
        }
    }
}
