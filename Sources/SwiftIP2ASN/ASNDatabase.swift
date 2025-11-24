import Foundation

// MARK: - ASNDatabase

/// Actor-based ASN database using a compressed trie for lookups.
///
/// Thread Safety:
/// - All public methods are actor-isolated.
/// - Build phase: Call `build()` or `buildWithBGPData()` once.
/// - Lookup phase: Call `lookup()` after building.
///
/// Usage:
/// ```swift
/// let db = ASNDatabase()
/// await db.build(from: allocations)
/// let info = await db.lookup("8.8.8.8")
/// ```
public actor ASNDatabase {
    private let trie: CompressedTrie
    private var isBuilt = false

    public init() {
        self.trie = CompressedTrie()
    }

    // MARK: - Build Phase

    /// Build database from IP allocations.
    public func build(from allocations: [IPAllocation]) async {
        precondition(!isBuilt, "Database already built")

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

        await trie.finalize()
        isBuilt = true
    }

    /// Build database with BGP data that includes AS names.
    public func buildWithBGPData(bgpEntries: [(range: IPRange, asn: UInt32, name: String?)]) async {
        precondition(!isBuilt, "Database already built")

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

        await trie.finalize()
        isBuilt = true
    }

    // MARK: - Lookup Phase

    /// Look up ASN info for an IP address.
    public func lookup(_ address: IPAddress) async -> ASNInfo? {
        guard isBuilt else { return nil }
        return await trie.lookup(address)
    }

    /// Look up ASN info for an IP address string.
    public func lookup(_ addressString: String) async -> ASNInfo? {
        guard let address = IPAddress(string: addressString) else {
            return nil
        }
        return await lookup(address)
    }

    // MARK: - Statistics

    public func getStatistics() async -> TrieStatistics {
        return await trie.getStatistics()
    }

    // MARK: - Persistence

    public func save(to url: URL) async throws {
        guard isBuilt else {
            throw DatabaseError.notBuilt
        }
        // Serialization would go here
        throw DatabaseError.serializationError
    }

    public func load(from url: URL) async throws {
        // Deserialization would go here
        throw DatabaseError.serializationError
    }
}

// MARK: - DatabaseError

public enum DatabaseError: Error, Sendable {
    case notBuilt
    case invalidData
    case serializationError
}
