import Foundation

public actor CompressedTrie {
    private final class TrieNode {
        var asnInfo: ASNInfo?
        var children: [Bool: TrieNode] = [:]
        var compressedPath: [Bool] = []

        init(asnInfo: ASNInfo? = nil) {
            self.asnInfo = asnInfo
        }
    }

    private var ipv4Root = TrieNode()
    private var ipv6Root = TrieNode()
    private var totalNodes = 0

    public init() {}

    public func insert(range: IPRange, asnInfo: ASNInfo) {
        let root =
            switch range.start {
            case .v4: ipv4Root
            case .v6: ipv6Root
            }

        var current = root

        for bitIndex in 0..<range.prefixLength {
            let bit = range.start.getBit(at: bitIndex)

            if let child = current.children[bit] {
                current = child
            } else {
                let newNode = TrieNode()
                current.children[bit] = newNode
                current = newNode
                totalNodes += 1
            }
        }

        current.asnInfo = asnInfo
    }

    public func lookup(_ address: IPAddress) -> ASNInfo? {
        let root =
            switch address {
            case .v4: ipv4Root
            case .v6: ipv6Root
            }

        var current = root
        var lastMatch: ASNInfo?
        let bitCount = address.bitCount

        for bitIndex in 0..<bitCount {
            if let info = current.asnInfo {
                lastMatch = info
            }

            let bit = address.getBit(at: bitIndex)

            guard let child = current.children[bit] else {
                break
            }

            current = child
        }

        if let info = current.asnInfo {
            lastMatch = info
        }

        return lastMatch
    }

    public func compress() {
        compressNode(ipv4Root)
        compressNode(ipv6Root)
    }

    private func compressNode(_ node: TrieNode) {
        if node.children.count == 1 && node.asnInfo == nil {
            guard let (bit, child) = node.children.first else { return }

            var path = [bit]
            var current = child

            while current.children.count == 1 && current.asnInfo == nil {
                guard let (nextBit, nextChild) = current.children.first else { break }
                path.append(nextBit)
                current = nextChild
            }

            if path.count > 1 {
                node.compressedPath = path
                node.children = current.children
                node.asnInfo = current.asnInfo
                totalNodes -= path.count - 1
            }
        }

        for child in node.children.values {
            compressNode(child)
        }
    }

    public func getStatistics() -> TrieStatistics {
        let ipv4Stats = gatherStatistics(from: ipv4Root, depth: 0, maxDepth: 32)
        let ipv6Stats = gatherStatistics(from: ipv6Root, depth: 0, maxDepth: 128)

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

    private func gatherStatistics(from node: TrieNode, depth: Int, maxDepth: Int) 
        -> (nodeCount: Int, maxDepth: Int, entries: Int) {
        var nodeCount = 1
        var currentMaxDepth = depth
        var entries = node.asnInfo != nil ? 1 : 0

        for child in node.children.values {
            let childStats = gatherStatistics(from: child, depth: depth + 1, maxDepth: maxDepth)
            nodeCount += childStats.nodeCount
            currentMaxDepth = max(currentMaxDepth, childStats.maxDepth)
            entries += childStats.entries
        }

        return (nodeCount, currentMaxDepth, entries)
    }
}

public struct TrieStatistics: Sendable {
    public let totalNodes: Int
    public let ipv4Nodes: Int
    public let ipv6Nodes: Int
    public let ipv4Depth: Int
    public let ipv6Depth: Int
    public let ipv4Entries: Int
    public let ipv6Entries: Int
}

