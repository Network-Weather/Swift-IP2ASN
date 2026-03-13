import Foundation

/// Safe alternative to SwiftPM's auto-generated `Bundle.module` accessor.
///
/// The auto-generated `resource_bundle_accessor.swift` calls `fatalError()` when the
/// resource bundle `SwiftIP2ASN_SwiftIP2ASN` can't be found at runtime — an unrecoverable
/// crash with no opportunity to handle it. This property performs the same candidate-path
/// search but returns `nil` instead of trapping, allowing callers to throw a recoverable
/// error (`.resourceNotFound`).
///
/// See: https://github.com/Network-Weather/Swift-IP2ASN/issues/1

private class BundleFinder {}

extension Foundation.Bundle {
    /// Returns the SwiftIP2ASN resource bundle, or `nil` if it can't be located.
    ///
    /// This searches the same candidate paths as SPM's generated `Bundle.module`
    /// but avoids the `fatalError` when none match.
    public static var safeModule: Bundle? {
        let bundleName = "SwiftIP2ASN_SwiftIP2ASN"

        // Standard SPM candidate paths
        let candidates = [
            Bundle.main.resourceURL,
            Bundle(for: BundleFinder.self).resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: BundleFinder.self).resourceURL?
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent(),
            Bundle(for: BundleFinder.self).resourceURL?
                .deletingLastPathComponent()
                .deletingLastPathComponent(),
            // Additional paths for non-standard layouts (.pkg installs, Sparkle updates)
            Bundle.main.privateFrameworksURL,
            Bundle.main.sharedFrameworksURL,
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }

        // Last resort: ask the main bundle directly (handles nested/relocated bundles)
        if let url = Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }

        return nil
    }
}
