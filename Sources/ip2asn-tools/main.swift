import Foundation
import IP2ASNDataPrep
import SwiftIP2ASN

enum Command: String {
    case lookup
    case inspect
    case validate
    case buildCompressed = "build-compressed"
    case lookupCompressed = "lookup-compressed"
    case benchCompressed = "bench-compressed"
    case buildUltra = "build-ultra"
    case lookupUltra = "lookup-ultra"
    case benchUltra = "bench-ultra"
}

func usage(exitCode: Int32 = 2) -> Never {
    let msg = """
        ip2asn

        Commands:
          ip2asn <ip>
          ip2asn lookup <ip> [--database <db.ultra>]
          ip2asn inspect [<db.ultra> | --database <db.ultra>]
          ip2asn validate [<db.ultra> [manifest.json]]
                          [--database <db.ultra>] [--manifest <manifest.json>]

        Database development commands:
          build-compressed <input.tsv> <output.cdb>
          lookup-compressed <db.cdb> <ip>
          bench-compressed <db.cdb> [iterations]

          build-ultra [provenance options] <v4.tsv> [v6.tsv] <output.ultra>
            --source <id> --generated-at <ISO-8601>
            --manifest <output.json> --builder-version <version>
            --input-source <url> <downloaded-file>  (repeat in input order)
          lookup-ultra <db.ultra> <ip>
          bench-ultra <db.ultra> [iterations]
        """
    print(msg)
    exit(exitCode)
}

var suppliedArguments = Array(CommandLine.arguments.dropFirst())
if suppliedArguments == ["help"] || suppliedArguments == ["--help"]
    || suppliedArguments == ["-h"]
{
    usage(exitCode: 0)
}
if let first = suppliedArguments.first, IPAddress(string: first) != nil {
    suppliedArguments.insert(Command.lookup.rawValue, at: 0)
}
let args = suppliedArguments[...]
guard let cmdRaw = args.first, let cmd = Command(rawValue: cmdRaw) else { usage() }

switch cmd {
case .lookup:
    guard let request = parseLookupArguments(Array(args.dropFirst())) else { usage() }
    do {
        let database =
            try request.databasePath.map(UltraCompactDatabase.init(path:))
            ?? IP2ASN.embedded()
        guard let result = database.lookup(request.ip) else {
            print("NOT FOUND")
            exit(1)
        }
        printLookup(result)
    } catch {
        fail(error)
    }

case .inspect:
    guard
        let request = parseDiagnosticArguments(
            Array(args.dropFirst()),
            allowsManifest: false
        )
    else {
        usage()
    }
    do {
        let databaseURL =
            try request.databasePath.map(URL.init(fileURLWithPath:))
            ?? EmbeddedDatabase.ultraCompactURL()
        let report = try DatabaseArtifactDiagnostics.inspect(databaseURL: databaseURL)
        try writeJSON(report)
    } catch {
        fail(error)
    }

case .validate:
    guard
        let request = parseDiagnosticArguments(
            Array(args.dropFirst()),
            allowsManifest: true
        )
    else {
        usage()
    }
    do {
        let usesEmbeddedDatabase = request.databasePath == nil
        let databaseURL =
            try request.databasePath.map(URL.init(fileURLWithPath:))
            ?? EmbeddedDatabase.ultraCompactURL()
        let manifestURL: URL?
        if let manifestPath = request.manifestPath {
            manifestURL = URL(fileURLWithPath: manifestPath)
        } else if usesEmbeddedDatabase {
            manifestURL = try EmbeddedDatabase.manifestURL()
        } else {
            manifestURL = nil
        }
        let report = try DatabaseArtifactDiagnostics.validate(
            databaseURL: databaseURL,
            manifestURL: manifestURL
        )
        try writeJSON(report)
    } catch {
        fail(error)
    }

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
    var positional: [String] = []
    var sourceIdentifier: String?
    var generationTimestamp: Date?
    var manifestPath: String?
    var builderVersion: String?
    var manifestSources: [(url: URL, downloadedPath: String)] = []
    var buildArguments = Array(args)
    buildArguments.removeFirst()
    var argumentIndex = 0
    while argumentIndex < buildArguments.count {
        let argument = buildArguments[argumentIndex]
        switch argument {
        case "--source":
            argumentIndex += 1
            guard argumentIndex < buildArguments.count else { usage() }
            sourceIdentifier = buildArguments[argumentIndex]
        case "--generated-at":
            argumentIndex += 1
            guard argumentIndex < buildArguments.count else { usage() }
            generationTimestamp = ISO8601DateFormatter().date(from: buildArguments[argumentIndex])
            guard generationTimestamp != nil else { usage() }
        case "--manifest":
            argumentIndex += 1
            guard argumentIndex < buildArguments.count else { usage() }
            manifestPath = buildArguments[argumentIndex]
        case "--builder-version":
            argumentIndex += 1
            guard argumentIndex < buildArguments.count else { usage() }
            builderVersion = buildArguments[argumentIndex]
        case "--input-source":
            argumentIndex += 1
            guard argumentIndex < buildArguments.count,
                let url = URL(string: buildArguments[argumentIndex])
            else { usage() }
            argumentIndex += 1
            guard argumentIndex < buildArguments.count else { usage() }
            manifestSources.append((url, buildArguments[argumentIndex]))
        default:
            guard !argument.hasPrefix("--") else { usage() }
            positional.append(argument)
        }
        argumentIndex += 1
    }

    let metadata: UltraCompactBuildMetadata?
    switch (generationTimestamp, sourceIdentifier) {
    case (.none, .none):
        metadata = nil
    case (.some(let timestamp), .some(let source)):
        metadata = UltraCompactBuildMetadata(
            generationTimestamp: timestamp,
            sourceIdentifier: source
        )
    default:
        usage()
    }

    let v4Path: String?
    let v6Path: String?
    let outputPath: String
    switch positional.count {
    case 2:
        v4Path = positional[0]
        v6Path = nil
        outputPath = positional[1]
    case 3:
        v4Path = positional[0]
        v6Path = positional[1]
        outputPath = positional[2]
    default:
        usage()
    }

    let inputPaths = [v4Path, v6Path].compactMap { $0 }
    let requestsManifest = manifestPath != nil || builderVersion != nil || !manifestSources.isEmpty
    let manifestRequest:
        (
            path: String,
            builderVersion: String,
            sourceInputs: [DatabaseBuildManifest.SourceInput]
        )?
    if requestsManifest {
        guard let manifestPath,
            let builderVersion,
            generationTimestamp != nil,
            manifestSources.count == inputPaths.count
        else { usage() }

        manifestRequest = (
            manifestPath,
            builderVersion,
            zip(manifestSources, inputPaths).map { source, inputPath in
                DatabaseBuildManifest.SourceInput(
                    url: source.url,
                    downloadedArtifactURL: URL(fileURLWithPath: source.downloadedPath),
                    builderInputURL: URL(fileURLWithPath: inputPath)
                )
            }
        )
    } else {
        manifestRequest = nil
    }

    do {
        try UltraCompactBuilder.createUltraCompact(
            ipv4TSV: v4Path,
            ipv6TSV: v6Path,
            to: outputPath,
            metadata: metadata
        )

        if let manifestRequest, let generationTimestamp {
            let manifest = try DatabaseBuildManifest.create(
                databaseURL: URL(fileURLWithPath: outputPath),
                sourceInputs: manifestRequest.sourceInputs,
                builderVersion: manifestRequest.builderVersion,
                generatedAt: generationTimestamp
            )
            try manifest.write(to: URL(fileURLWithPath: manifestRequest.path))
        }
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
            printLookup(r)
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
struct LookupRequest {
    let ip: String
    let databasePath: String?
}

struct DiagnosticRequest {
    let databasePath: String?
    let manifestPath: String?
}

func parseLookupArguments(_ arguments: [String]) -> LookupRequest? {
    var positionals: [String] = []
    var databasePath: String?
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--database":
            index += 1
            guard index < arguments.count, databasePath == nil else { return nil }
            databasePath = arguments[index]
        default:
            guard !arguments[index].hasPrefix("--") else { return nil }
            positionals.append(arguments[index])
        }
        index += 1
    }
    guard positionals.count == 1, IPAddress(string: positionals[0]) != nil else { return nil }
    return LookupRequest(ip: positionals[0], databasePath: databasePath)
}

func parseDiagnosticArguments(
    _ arguments: [String],
    allowsManifest: Bool
) -> DiagnosticRequest? {
    var positionals: [String] = []
    var databasePath: String?
    var manifestPath: String?
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--database":
            index += 1
            guard index < arguments.count, databasePath == nil else { return nil }
            databasePath = arguments[index]
        case "--manifest":
            guard allowsManifest else { return nil }
            index += 1
            guard index < arguments.count, manifestPath == nil else { return nil }
            manifestPath = arguments[index]
        default:
            guard !arguments[index].hasPrefix("--") else { return nil }
            positionals.append(arguments[index])
        }
        index += 1
    }

    guard positionals.count <= (allowsManifest ? 2 : 1) else { return nil }
    if let positionalDatabase = positionals.first {
        guard databasePath == nil else { return nil }
        databasePath = positionalDatabase
    }
    if positionals.count == 2 {
        guard allowsManifest, manifestPath == nil else { return nil }
        manifestPath = positionals[1]
    }
    return DiagnosticRequest(databasePath: databasePath, manifestPath: manifestPath)
}

func printLookup(_ result: (asn: UInt32, name: String?)) {
    if let name = result.name, !name.isEmpty {
        print("AS\(result.asn) \(name)")
    } else {
        print("AS\(result.asn)")
    }
}

func writeJSON<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try DatabaseArtifactDiagnostics.encodedJSON(value))
}

func fail(_ error: Error) -> Never {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}

func report(times: [Double], label: String) {
    guard !times.isEmpty else { return }
    let avg = times.reduce(0, +) / Double(times.count)
    let minv = times.min() ?? avg
    let maxv = times.max() ?? avg
    print(
        "\(label): avg=\(String(format: "%.2f", avg)) ms, min=\(String(format: "%.2f", minv)) ms, max=\(String(format: "%.2f", maxv)) ms over \(times.count) iters"
    )
}
