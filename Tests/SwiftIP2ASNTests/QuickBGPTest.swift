import XCTest

@testable import SwiftIP2ASN

final class QuickBGPTest: XCTestCase {

    func testQuickBGPParse() async throws {
        print("\n🧪 Quick test of BGP data parsing...")

        // Use test data instead of decompressing large file
        // For a real test, we should use a small test fixture
        let testData = """
            1.0.0.0\t1.0.0.255\t13335\tUS\tCLOUDFLARENET
            8.8.8.0\t8.8.8.255\t15169\tUS\tGOOGLE
            140.82.112.0\t140.82.127.255\t36459\tUS\tGITHUB
            157.240.0.0\t157.240.255.255\t32934\tUS\tFACEBOOK
            """
        let content = testData

        print("Decompressed data: \(content.count) characters")

        let lines = content.split(separator: "\n")
        print("Total lines: \(lines.count)")

        // Show first 10 lines
        print("\nFirst 10 lines:")
        for (index, line) in lines.prefix(10).enumerated() {
            print("\(index+1): \(line)")
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
