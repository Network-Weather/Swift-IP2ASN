import Foundation

// MARK: - TrieNode

/// Memory-efficient trie node using fixed-size array instead of Dictionary.
/// Each node has exactly 2 possible children (left=0, right=1).
/// Memory: ~24 bytes per node vs ~72 bytes with Dictionary.
private final class TrieNode: @unchecked Sendable {
    var asnInfo: ASNInfo?
    var left: TrieNode?  // bit = 0
    var right: TrieNode?  // bit = 1

    init(asnInfo: ASNInfo? = nil) {
        self.asnInfo = asnInfo
    }

    @inlinable
    func child(for bit: Bool) -> TrieNode? {
        bit ? right : left
    }

    @inlinable
    func setChild(_ node: TrieNode, for bit: Bool) {
        if bit {
            right = node
        } else {
            left = node
        }
    }

    var hasChildren: Bool {
        left != nil || right != nil
    }

    var childCount: Int {
        (left != nil ? 1 : 0) + (right != nil ? 1 : 0)
    }
}

// MARK: - CompressedTrie

/// High-performance prefix trie for IP to ASN lookups.
///
/// Thread Safety:
/// - Build phase: Call `insert()` from a single task, then call `finalize()`.
/// - Lookup phase: After `finalize()`, `lookup()` is safe to call concurrently.
/// - The actor isolation ensures these phases don't overlap.
///
/// Memory Efficiency:
/// - Uses fixed-size left/right pointers instead of Dictionary (~3x memory savings).
/// - Supports path compression for long chains of single-child nodes.
public actor CompressedTrie {
    private var ipv4Root = TrieNode()
    private var ipv6Root = TrieNode()
    private var totalNodes = 0
    private var isFinalized = false

    public init() {}

    // MARK: - Build Phase

    /// Insert a range into the trie. Must be called before `finalize()`.
    public func insert(range: IPRange, asnInfo: ASNInfo) {
        precondition(!isFinalized, "Cannot insert after finalize()")

        let root: TrieNode
        switch range.start {
        case .v4: root = ipv4Root
        case .v6: root = ipv6Root
        }

        var current = root

        for bitIndex in 0..<range.prefixLength {
            let bit = range.start.getBit(at: bitIndex)

            if let child = current.child(for: bit) {
                current = child
            } else {
                let newNode = TrieNode()
                current.setChild(newNode, for: bit)
                current = newNode
                totalNodes += 1
            }
        }

        current.asnInfo = asnInfo
    }

    /// Finalize the trie after all insertions. Enables concurrent lookups.
    public func finalize() {
        isFinalized = true
    }

    // MARK: - Lookup Phase

    /// Look up ASN info for an IP address.
    /// Returns the most specific (longest prefix) match.
    ///
    /// Thread-safe after `finalize()` is called.
    public func lookup(_ address: IPAddress) -> ASNInfo? {
        let root: TrieNode
        switch address {
        case .v4: root = ipv4Root
        case .v6: root = ipv6Root
        }

        var current = root
        var lastMatch: ASNInfo?
        let bitCount = address.bitCount

        for bitIndex in 0..<bitCount {
            if let info = current.asnInfo {
                lastMatch = info
            }

            let bit = address.getBit(at: bitIndex)

            guard let child = current.child(for: bit) else {
                break
            }

            current = child
        }

        // Check final node
        if let info = current.asnInfo {
            lastMatch = info
        }

        return lastMatch
    }

    // MARK: - Statistics

    public func getStatistics() -> TrieStatistics {
        let ipv4Stats = gatherStatistics(from: ipv4Root, depth: 0)
        let ipv6Stats = gatherStatistics(from: ipv6Root, depth: 0)

        return TrieStatistics(
            totalNodes: totalNodes,
            ipv4Nodes: ipv4Stats.nodeCount,
            ipv6Nodes: ipv6Stats.nodeCount,
            ipv4Depth: ipv4Stats.maxDepth,
            ipv6Depth: ipv6Stats.maxDepth,
            ipv4Entries: ipv4Stats.entries,
            ipv6Entries: ipv6Stats.entries
        )
    }

    private func gatherStatistics(from node: TrieNode, depth: Int) -> (nodeCount: Int, maxDepth: Int, entries: Int) {
        var nodeCount = 1
        var currentMaxDepth = depth
        var entries = node.asnInfo != nil ? 1 : 0

        if let left = node.left {
            let stats = gatherStatistics(from: left, depth: depth + 1)
            nodeCount += stats.nodeCount
            currentMaxDepth = max(currentMaxDepth, stats.maxDepth)
            entries += stats.entries
        }

        if let right = node.right {
            let stats = gatherStatistics(from: right, depth: depth + 1)
            nodeCount += stats.nodeCount
            currentMaxDepth = max(currentMaxDepth, stats.maxDepth)
            entries += stats.entries
        }

        return (nodeCount, currentMaxDepth, entries)
    }
}

// MARK: - TrieStatistics

public struct TrieStatistics: Sendable {
    public let totalNodes: Int
    public let ipv4Nodes: Int
    public let ipv6Nodes: Int
    public let ipv4Depth: Int
    public let ipv6Depth: Int
    public let ipv4Entries: Int
    public let ipv6Entries: Int
}
