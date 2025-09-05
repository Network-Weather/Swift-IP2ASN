import Foundation

enum TestLog {
    static let verbose: Bool = ProcessInfo.processInfo.environment["IP2ASN_VERBOSE"] != nil
    static func log(_ message: @autoclosure () -> String) {
        if verbose { print(message()) }
    }
}
