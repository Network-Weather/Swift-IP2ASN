import Foundation
import IP2ASNDataPrep
import SwiftIP2ASN

enum Command: String {
    case buildCompressed = "build-compressed"
    case lookupCompressed = "lookup-compressed"
    case benchCompressed = "bench-compressed"
    case buildUltra = "build-ultra"
    case lookupUltra = "lookup-ultra"
    case benchUltra = "bench-ultra"
}

func usage() -> Never {
    let msg = """
        ip2asn-tools

        Commands:
          build-compressed <input.tsv> <output.cdb>
          lookup-compressed <db.cdb> <ip>
          bench-compressed <db.cdb> [iterations]

          build-ultra <input.tsv> <output.ultra>
          lookup-ultra <db.ultra> <ip>
          bench-ultra <db.ultra> [iterations]
        """
    print(msg)
    exit(2)
}

let args = CommandLine.arguments.dropFirst()
guard let cmdRaw = args.first, let cmd = Command(rawValue: cmdRaw) else { usage() }

switch cmd {
case .buildCompressed:
    guard args.count == 3 else { usage() }
    let input = String(args.dropFirst().first!)
    let output = String(args.dropFirst(2).first!)
    do {
        try CompressedDatabaseBuilder.createCompressed(from: input, to: output)
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }

case .lookupCompressed:
    guard args.count == 3 else { usage() }
    let dbPath = String(args.dropFirst().first!)
    let ip = String(args.dropFirst(2).first!)
    do {
        let db = try CompressedDatabaseFormat.loadCompressed(from: dbPath)
        if let asn = db.lookup(ip) {
            print("AS\(asn)")
        } else {
            print("NOT FOUND")
            exit(1)
        }
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }

case .benchCompressed:
    guard args.count >= 2 else { usage() }
    let dbPath = String(args.dropFirst().first!)
    let iters = Int(args.dropFirst(2).first ?? "5") ?? 5
    if iters <= 0 {
        print("iterations must be > 0")
        exit(2)
    }
    _ = try? CompressedDatabaseFormat.loadCompressed(from: dbPath)  // warmup
    var timesC: [Double] = []
    for _ in 0..<iters {
        let start = Date()
        _ = try CompressedDatabaseFormat.loadCompressed(from: dbPath)
        timesC.append(Date().timeIntervalSince(start) * 1000)
    }
    report(times: timesC, label: "Compressed load")

case .buildUltra:
    guard args.count == 3 else { usage() }
    let input = String(args.dropFirst().first!)
    let output = String(args.dropFirst(2).first!)
    do {
        try UltraCompactBuilder.createUltraCompact(from: input, to: output)
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }

case .lookupUltra:
    guard args.count == 3 else { usage() }
    let dbPath = String(args.dropFirst().first!)
    let ip = String(args.dropFirst(2).first!)
    do {
        let db = try UltraCompactDatabase(path: dbPath)
        if let r = db.lookup(ip) {
            print("AS\(r.asn) \(r.name ?? "")")
        } else {
            print("NOT FOUND")
            exit(1)
        }
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }

case .benchUltra:
    guard args.count >= 2 else { usage() }
    let dbPath = String(args.dropFirst().first!)
    let iters = Int(args.dropFirst(2).first ?? "5") ?? 5
    if iters <= 0 {
        print("iterations must be > 0")
        exit(2)
    }
    _ = try? UltraCompactDatabase(path: dbPath)  // warmup
    var timesU: [Double] = []
    for _ in 0..<iters {
        let start = Date()
        _ = try UltraCompactDatabase(path: dbPath)
        timesU.append(Date().timeIntervalSince(start) * 1000)
    }
    report(times: timesU, label: "UltraCompact load")
}

// MARK: - Helpers
func report(times: [Double], label: String) {
    guard !times.isEmpty else { return }
    let avg = times.reduce(0, +) / Double(times.count)
    let minv = times.min() ?? avg
    let maxv = times.max() ?? avg
    print(
        "\(label): avg=\(String(format: "%.2f", avg)) ms, min=\(String(format: "%.2f", minv)) ms, max=\(String(format: "%.2f", maxv)) ms over \(times.count) iters"
    )
}
