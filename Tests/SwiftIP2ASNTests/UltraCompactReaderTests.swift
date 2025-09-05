import XCTest

@testable import IP2ASNDataPrep
@testable import SwiftIP2ASN

final class UltraCompactReaderTests: XCTestCase {
    func testLookupFromUltraCompactDB() throws {
        // Prepare a small TSV in memory
        let lines = [
            "1.1.1.0\t1.1.1.255\t13335\tUS\tCLOUDFLARE",
            "8.8.8.0\t8.8.8.255\t15169\tUS\tGOOGLE"
        ].joined(separator: "\n")

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let tsv = tmp.appendingPathComponent("mini.tsv").path
        let out = tmp.appendingPathComponent("mini.ultra").path
        try lines.write(toFile: tsv, atomically: true, encoding: .utf8)

        try UltraCompactBuilder.createUltraCompact(from: tsv, to: out)
        let db = try UltraCompactDatabase(path: out)

        XCTAssertEqual(db.lookup("1.1.1.1")?.asn, 13335)
        XCTAssertEqual(db.lookup("8.8.8.8")?.asn, 15169)
        XCTAssertNil(db.lookup("9.9.9.9"))
    }
}
