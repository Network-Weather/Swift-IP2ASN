import Foundation

public enum RIR: String, CaseIterable, Sendable {
    case arin = "arin"
    case ripe = "ripencc"
    case apnic = "apnic"
    case lacnic = "lacnic"
    case afrinic = "afrinic"

    public var delegatedURL: String {
        switch self {
        case .arin:
            return "https://ftp.arin.net/pub/stats/arin/delegated-arin-extended-latest"
        case .ripe:
            return "https://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-extended-latest"
        case .apnic:
            return "https://ftp.apnic.net/stats/apnic/delegated-apnic-extended-latest"
        case .lacnic:
            return "https://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-extended-latest"
        case .afrinic:
            return "https://ftp.afrinic.net/stats/afrinic/delegated-afrinic-extended-latest"
        }
    }
}

public struct RIRDataFetcher: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchData(from rir: RIR) async throws -> String {
        guard let url = URL(string: rir.delegatedURL) else {
            throw RIRError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw RIRError.httpError
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw RIRError.invalidData
        }

        return content
    }

    public func fetchAllRIRData() async throws -> [RIR: String] {
        try await withThrowingTaskGroup(of: (RIR, String).self) { group in
            for rir in RIR.allCases {
                group.addTask {
                    let data = try await self.fetchData(from: rir)
                    return (rir, data)
                }
            }

            var results: [RIR: String] = [:]
            for try await (rir, data) in group {
                results[rir] = data
            }

            return results
        }
    }
}

public struct RIRDataParser: Sendable {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public init() {}

    public func parse(_ data: String, registry: String) -> [IPAllocation] {
        var allocations: [IPAllocation] = []
        let lines = data.split(separator: "\n")

        for line in lines {
            if let allocation = parseLine(String(line), registry: registry) {
                allocations.append(allocation)
            }
        }

        return allocations
    }

    private func parseLine(_ line: String, registry: String) -> IPAllocation? {
        if line.hasPrefix("#") || line.isEmpty {
            return nil
        }

        let fields = line.split(separator: "|").map { String($0) }

        if fields.count < 7 {
            return nil
        }

        let recordType = fields[2]

        if recordType == "asn" || (recordType != "ipv4" && recordType != "ipv6") {
            return nil
        }

        let status = fields[6]
        if status != "allocated" && status != "assigned" {
            return nil
        }

        let countryCode = fields[1] == "*" ? nil : fields[1]
        let startIP = fields[3]
        let value = fields[4]
        let dateString = fields[5]

        var asnNumber: UInt32 = 0
        if fields.count > 7, let asn = UInt32(fields[7]) {
            asnNumber = asn
        }

        let allocatedDate = Self.dateFormatter.date(from: dateString)

        if recordType == "ipv4" {
            return parseIPv4Allocation(
                startIP: startIP,
                value: value,
                asn: asnNumber,
                countryCode: countryCode,
                registry: registry,
                allocatedDate: allocatedDate
            )
        } else {
            return parseIPv6Allocation(
                startIP: startIP,
                value: value,
                asn: asnNumber,
                countryCode: countryCode,
                registry: registry,
                allocatedDate: allocatedDate
            )
        }
    }

    private func parseIPv4Allocation(
        startIP: String,
        value: String,
        asn: UInt32,
        countryCode: String?,
        registry: String,
        allocatedDate: Date?
    ) -> IPAllocation? {
        guard let address = IPAddress(string: startIP),
            let count = UInt32(value)
        else {
            return nil
        }

        let prefixLength = 32 - Int(log2(Double(count)))
        let range = IPRange(start: address, prefixLength: prefixLength)

        return IPAllocation(
            range: range,
            asn: asn,
            countryCode: countryCode,
            registry: registry,
            allocatedDate: allocatedDate
        )
    }

    private func parseIPv6Allocation(
        startIP: String,
        value: String,
        asn: UInt32,
        countryCode: String?,
        registry: String,
        allocatedDate: Date?
    ) -> IPAllocation? {
        guard let address = IPAddress(string: startIP),
            let prefixLength = Int(value)
        else {
            return nil
        }

        let range = IPRange(start: address, prefixLength: prefixLength)

        return IPAllocation(
            range: range,
            asn: asn,
            countryCode: countryCode,
            registry: registry,
            allocatedDate: allocatedDate
        )
    }

    public func parseAll(_ data: [RIR: String]) -> [IPAllocation] {
        var allAllocations: [IPAllocation] = []

        for (rir, content) in data {
            let allocations = parse(content, registry: rir.rawValue)
            allAllocations.append(contentsOf: allocations)
        }

        return allAllocations
    }
}

public enum RIRError: Error {
    case invalidURL
    case httpError
    case invalidData
}
