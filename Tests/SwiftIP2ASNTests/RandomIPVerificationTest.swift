import XCTest

@testable import SwiftIP2ASN

final class RandomIPVerificationTest: XCTestCase {

    func testRandomIPsAgainstRealData() async throws {
        print("\n🎲 Testing random IP addresses with real BGP data\n")

        // First, let's check what the actual BGP database says for various IPs
        // We'll use the downloaded database
        print("📥 Loading real BGP data from IPtoASN...")

        // Random selection of IPs from different parts of the internet
        let testIPs = [
            // Tech companies
            "17.253.144.10",  // Apple
            "157.240.22.35",  // Facebook/Meta
            "52.94.236.248",  // Amazon AWS
            "20.236.44.162",  // Microsoft Azure
            "172.217.16.142",  // Google
            "104.18.33.221",  // Cloudflare

            // ISPs and carriers
            "24.193.64.100",  // Comcast
            "71.192.100.50",  // Charter
            "98.137.246.8",  // Yahoo/Verizon
            "209.85.233.104",  // Google

            // International
            "203.104.103.21",  // Japan
            "59.125.119.200",  // Taiwan
            "110.164.10.5",  // Thailand
            "41.210.140.100",  // Kenya
            "200.147.3.150",  // Brazil
            "89.185.43.100",  // Russia
            "5.101.219.100",  // Iran

            // CDNs
            "151.101.1.140",  // Fastly
            "23.215.100.50",  // Akamai
            "192.229.173.15",  // Amazon CloudFront

            // Random addresses
            "91.198.174.192",  // Wikimedia
            "199.232.64.100",  // Twitter/X
            "140.82.121.3",  // GitHub
            "162.159.200.1",  // Cloudflare
            "185.199.108.153",  // GitHub Pages

            // Your specific requests
            "204.141.42.155",  // ZOHO
            "180.222.119.247"  // Yahoo Singapore
        ]

        // First, let's check these against the real database
        print("\n📊 Checking against real BGP database (from /tmp/ip2asn-v4.tsv.gz):")
        print(String(repeating: "─", count: 70))

        for ip in testIPs {
            // Look up in the real database
            let result = try await lookupInRealDatabase(ip: ip)
            print(result)
        }

        // Now let's verify a few with whois
        print("\n🔍 Verifying sample IPs with WHOIS:")
        print(String(repeating: "─", count: 70))

        let sampleIPs = [
            "17.253.144.10",  // Apple
            "104.18.33.221",  // Cloudflare
            "52.94.236.248",  // Amazon
            "204.141.42.155"  // Your requested IP
        ]

        for ip in sampleIPs {
            print("\n🌐 WHOIS lookup for \(ip):")
            let whoisResult = try await runWhois(ip: ip)

            // Parse key fields
            if let originAS = extractField(from: whoisResult, field: "OriginAS:") {
                print("   OriginAS: \(originAS)")
            }
            if let netName = extractField(from: whoisResult, field: "NetName:") {
                print("   NetName: \(netName)")
            }
            if let orgName = extractField(from: whoisResult, field: "OrgName:") {
                print("   OrgName: \(orgName)")
            }
            if let org = extractField(from: whoisResult, field: "Organization:") {
                print("   Organization: \(org)")
            }

            // Try to extract ASN from various formats
            let asnPattern = #"AS(\d+)"#
            if let asnMatch = whoisResult.range(of: asnPattern, options: .regularExpression) {
                let asn = String(whoisResult[asnMatch])
                print("   Found ASN: \(asn)")
            }
        }

        print("\n" + String(repeating: "─", count: 70))
        print("\n💡 Note: WHOIS and BGP data should generally match, though:")
        print("   - WHOIS shows the allocated organization")
        print("   - BGP shows the actual routing announcement")
        print("   - Some IPs may be announced by different ASNs than their allocation")
    }

    private func lookupInRealDatabase(ip: String) async throws -> String {
        // Use gunzip to decompress and grep to find the IP
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "gunzip -c /tmp/ip2asn-v4.tsv.gz | awk -F'\\t' -v ip='\(ip)' '$1 <= ip && $2 >= ip { print $0; exit }'"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty
        else {
            return "\(ip.padding(toLength: 16, withPad: " ", startingAt: 0)) → NOT FOUND in BGP database"
        }

        let fields = output.split(separator: "\t").map { String($0) }
        if fields.count >= 5 {
            let asn = fields[2]
            let country = fields[3]
            let name = fields[4]
            return
                "\(ip.padding(toLength: 16, withPad: " ", startingAt: 0)) → AS\(asn.padding(toLength: 6, withPad: " ", startingAt: 0)) \(country)  \(name)"
        }

        return "\(ip.padding(toLength: 16, withPad: " ", startingAt: 0)) → \(output)"
    }

    private func runWhois(ip: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/whois")
        process.arguments = [ip]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()  // Suppress errors

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func extractField(from whois: String, field: String) -> String? {
        let lines = whois.split(separator: "\n")
        for line in lines where line.contains(field) {
            let parts = line.split(separator: ":")
            if parts.count >= 2 {
                return parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
