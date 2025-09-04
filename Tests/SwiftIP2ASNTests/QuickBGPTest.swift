import XCTest

@testable import SwiftIP2ASN

final class QuickBGPTest: XCTestCase {

    func testQuickBGPParse() async throws {
        print("\n🧪 Quick test of BGP data parsing...")

        // Use the already downloaded file
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", "/tmp/ip2asn-v4.tsv.gz"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to decompress")
            return
        }

        print("Decompressed data: \(content.count) characters")

        let lines = content.split(separator: "\n")
        print("Total lines: \(lines.count)")

        // Show first 10 lines
        print("\nFirst 10 lines:")
        for (i, line) in lines.prefix(10).enumerated() {
            print("\(i+1): \(line)")
        }

        // Look for our test IPs
        print("\n🔍 Looking for specific IPs...")

        let testIPs = ["204.141.42", "180.222.119", "57.144.220"]

        for testIP in testIPs {
            let matching = lines.filter { line in
                line.starts(with: testIP)
            }

            if !matching.isEmpty {
                print("\n✅ Found entries for \(testIP):")
                for match in matching.prefix(5) {
                    let fields = match.split(separator: "\t").map { String($0) }
                    if fields.count >= 5 {
                        print("   Range: \(fields[0])-\(fields[1])")
                        print("   ASN: \(fields[2])")
                        print("   Country: \(fields[3])")
                        print("   Name: \(fields[4])")
                    }
                }
            } else {
                print("\n❌ No exact match for \(testIP)")

                // Try to find which range contains it
                for line in lines {
                    let fields = line.split(separator: "\t").map { String($0) }
                    if fields.count >= 2 {
                        let startIP = fields[0]
                        let endIP = fields[1]

                        // Simple string comparison (not perfect but quick)
                        if startIP <= testIP + ".0" && endIP >= testIP + ".255" {
                            print("   Might be in range: \(startIP)-\(endIP)")
                            if fields.count >= 5 {
                                print("   ASN: \(fields[2]), Name: \(fields[4])")
                            }
                            break
                        }
                    }
                }
            }
        }
    }
}
