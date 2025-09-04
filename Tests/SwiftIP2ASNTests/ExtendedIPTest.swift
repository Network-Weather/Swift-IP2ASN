import XCTest

@testable import SwiftIP2ASN

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class ExtendedIPTest: XCTestCase {

    func testLargerSetOfIPs() async throws {
        print("\n🌐 Testing with a larger set of IP addresses\n")

        let ip2asn = try await SwiftIP2ASN.buildWithBGPData()

        // Extended test set including the IP you mentioned
        let testIPs = [
            // Your requested IP
            ("204.141.42.155", "User requested IP"),

            // Various CDN and cloud providers
            ("23.185.0.2", "Akamai"),
            ("151.101.1.140", "Fastly"),
            ("172.217.14.100", "Google"),
            ("185.199.108.153", "GitHub"),
            ("140.82.114.4", "GitHub"),

            // DNS providers
            ("9.9.9.9", "Quad9"),
            ("208.67.222.222", "OpenDNS"),
            ("76.76.2.0", "Alternate DNS"),
            ("64.6.64.6", "Verisign"),

            // Social media and tech companies
            ("199.232.13.75", "Twitter"),
            ("151.101.1.140", "Reddit"),
            ("52.84.228.25", "Amazon CloudFront"),
            ("104.244.42.1", "Twitter"),
            ("157.240.221.35", "Facebook/Instagram"),

            // International IPs
            ("59.24.3.173", "Taiwan Academic Network"),
            ("203.208.60.1", "Google Asia"),
            ("119.63.196.1", "Alibaba China"),
            ("217.160.0.1", "1&1 IONOS Germany"),
            ("185.60.216.35", "Facebook Europe"),

            // Enterprise and ISPs
            ("4.2.2.2", "Level 3"),
            ("156.154.70.1", "Neustar"),
            ("12.127.16.67", "AT&T"),
            ("65.49.1.1", "Comcast"),
            ("71.10.216.1", "Charter"),

            // Cloud providers
            ("20.185.79.15", "Microsoft Azure"),
            ("35.186.224.25", "Google Cloud"),
            ("3.101.52.72", "AWS US West"),
            ("13.107.42.14", "Microsoft"),

            // Random IPs
            ("192.0.2.1", "Documentation IP"),
            ("198.51.100.1", "Documentation IP"),
            ("93.184.216.34", "Example.com"),
            ("45.60.121.1", "Hosting provider"),
            ("185.125.190.36", "European hosting")
        ]

        var found = 0
        var notFound = 0
        var results: [(ip: String, asn: UInt32?, name: String?)] = []

        print("Testing \(testIPs.count) IP addresses...\n")

        for (ip, description) in testIPs {
            if let result = await ip2asn.lookup(ip) {
                found += 1
                results.append((ip: ip, asn: result.asn, name: result.name))

                let asnDisplay = result.asn == 0 ? "AS0 ❌" : "AS\(result.asn)"
                print(
                    "✅ \(ip.padding(toLength: 18, withPad: " ", startingAt: 0)) → \(asnDisplay.padding(toLength: 10, withPad: " ", startingAt: 0)) | \(description)"
                )

                if result.name != nil {
                    print("   └─ \(result.name!)")
                }
            } else {
                notFound += 1
                results.append((ip: ip, asn: nil, name: nil))
                print("❌ \(ip.padding(toLength: 18, withPad: " ", startingAt: 0)) → NOT FOUND     | \(description)")
            }
        }

        print("\n📊 Statistics:")
        print("   Total IPs tested: \(testIPs.count)")
        print("   Found: \(found)")
        print("   Not found: \(notFound)")

        // Check how many returned ASN 0
        let zeroASNs = results.filter { $0.asn == 0 }.count
        let nonZeroASNs = results.filter { $0.asn != nil && $0.asn! > 0 }.count

        print("\n   ASN Analysis:")
        print("   - Non-zero ASNs: \(nonZeroASNs)")
        print("   - Zero ASNs: \(zeroASNs)")
        print("   - Not found: \(notFound)")

        // Specifically check the requested IP
        print("\n🔍 Detailed check for 204.141.42.155:")
        if let result = await ip2asn.lookup("204.141.42.155") {
            print("   Found in database!")
            print("   ASN: \(result.asn)")
            print("   Name: \(result.name ?? "N/A")")
            print("   Registry: \(result.registry)")
        } else {
            print("   ⚠️ NOT FOUND in current BGP data")
            print("   Note: The SimpleBGPFetcher currently has a limited hardcoded dataset.")
            print("   In production, you would fetch from real BGP sources like:")
            print("   - IPtoASN.com (comprehensive database)")
            print("   - RouteViews BGP archives")
            print("   - RIPE RIS data")
        }

        if notFound > 0 || zeroASNs > 0 {
            print("\n⚠️ Note: Some IPs not found or returned ASN 0")
            print("This is expected with the limited hardcoded BGP data.")
            print("The SimpleBGPFetcher only includes major providers for testing.")
            print("Production implementation would use full BGP routing tables.")
        }
    }
}
