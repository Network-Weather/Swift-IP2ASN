import Foundation

public actor ASNDatabase {
    private let trie: CompressedTrie
    private var isBuilt = false

    public init() {
        self.trie = CompressedTrie()
    }

    public func build(from allocations: [IPAllocation]) async {
        for allocation in allocations {
            let asnInfo = ASNInfo(
                asn: allocation.asn,
                countryCode: allocation.countryCode,
                registry: allocation.registry,
                allocatedDate: allocation.allocatedDate,
                name: nil
            )

            await trie.insert(range: allocation.range, asnInfo: asnInfo)
        }

        // await trie.compress() // Will be implemented later
        isBuilt = true
    }

    /// Build database with BGP data that includes AS names
    public func buildWithBGPData(bgpEntries: [(range: IPRange, asn: UInt32, name: String?)]) async {
        for (range, asn, name) in bgpEntries {
            let asnInfo = ASNInfo(
                asn: asn,
                countryCode: nil,
                registry: "bgp",
                allocatedDate: nil,
                name: name
            )
            await trie.insert(range: range, asnInfo: asnInfo)
        }
        isBuilt = true
    }

    public func buildFromRIRData() async throws {
        let fetcher = RIRDataFetcher()
        let parser = RIRDataParser()

        let rirData = try await fetcher.fetchAllRIRData()
        let allocations = parser.parseAll(rirData)

        await build(from: allocations)
    }

    public func lookup(_ address: IPAddress) async -> ASNInfo? {
        guard isBuilt else { return nil }
        return await trie.lookup(address)
    }

    public func lookup(_ addressString: String) async -> ASNInfo? {
        guard let address = IPAddress(string: addressString) else {
            return nil
        }
        return await lookup(address)
    }

    public func getStatistics() async -> TrieStatistics {
        return await trie.getStatistics()
    }

    public func save(to url: URL) async throws {
        guard isBuilt else {
            throw DatabaseError.notBuilt
        }

        let data = try await serialize()
        try data.write(to: url)
    }

    public func load(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        try await deserialize(data)
        isBuilt = true
    }

    private func serialize() async throws -> Data {
        fatalError("Serialization not yet implemented")
    }

    private func deserialize(_ data: Data) async throws {
        fatalError("Deserialization not yet implemented")
    }
}

public struct ASNDatabaseBuilder: Sendable {
    public init() {}

    public func buildAndSave(to url: URL) async throws {
        let database = ASNDatabase()
        try await database.buildFromRIRData()
        try await database.save(to: url)
    }

    public func buildFromLocalFiles(_ files: [URL]) async throws -> ASNDatabase {
        let parser = RIRDataParser()
        var allAllocations: [IPAllocation] = []

        for file in files {
            let data = try String(contentsOf: file)
            let registry = file.deletingPathExtension().lastPathComponent
            let allocations = parser.parse(data, registry: registry)
            allAllocations.append(contentsOf: allocations)
        }

        let database = ASNDatabase()
        await database.build(from: allAllocations)
        return database
    }
}

public enum DatabaseError: Error {
    case notBuilt
    case invalidData
    case serializationError
}
