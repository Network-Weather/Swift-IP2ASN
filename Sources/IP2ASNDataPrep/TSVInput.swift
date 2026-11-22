import Foundation

struct TSVInputError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// Split bytes before decoding so a read boundary can fall inside a UTF-8 scalar or CRLF.
func forEachTSVLine(path: String, _ body: (String, Int) throws -> Void) throws {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    var number = 1
    var pending = Data()

    func emit(_ bytes: Data) throws {
        let content = bytes.last == 13 ? bytes.dropLast() : bytes
        guard let line = String(data: content, encoding: .utf8) else {
            throw TSVInputError("\(path):\(number): invalid UTF-8")
        }
        try body(line, number)
        number += 1
    }

    while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
        var remaining = chunk[...]
        while !remaining.isEmpty {
            let end = remaining.firstIndex(of: 10) ?? remaining.endIndex
            let segment = remaining[..<end]
            guard pending.count + segment.count <= 1024 * 1024 else {
                throw TSVInputError("\(path):\(number): TSV row exceeds 1 MiB")
            }
            if end == remaining.endIndex {
                pending.append(segment)
                break
            }
            if pending.isEmpty {
                try emit(segment)
            } else {
                pending.append(segment)
                try emit(pending)
                pending.removeAll(keepingCapacity: true)
            }
            remaining = remaining[(end + 1)...]
        }
    }
    if !pending.isEmpty { try emit(pending) }
}
