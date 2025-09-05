SwiftIP2ASN – Release Checklist

Scope: Library for offline IP → ASN lookup plus scripts to prepare and compress data.

Pre-release validation
- Build: Run `swift build -c release` for all supported platforms and Swift versions.
- Tests: Run `swift test` locally; ensure only offline unit tests run by default.
- API audit: Confirm public API surface is stable and documented; no breaking changes.
- SemVer: Bump version in tags and changelog according to SemVer.

Quality and compliance
- Documentation: README reflects current capabilities and limitations (no in-actor persistence yet).
- Examples: Include snippet for loading a compressed database and performing lookups.
- Licensing: LICENSE present and up to date.
- Formatting: Run `swift-format` locally (tooling not shipped as dependency).

Artifacts and data
- Data builder scripts: Provide a simple script to create compressed DB from TSV.
- Verify compressed DB: Load with `CompressedDatabaseFormat.loadCompressed` and sample lookups.
- Do not ship data: The package should not embed large data files.

CI/CD
- Add a CI workflow (GitHub Actions) to run `swift build` and offline tests on macOS and Linux.
- Cache SPM to speed up builds; skip network-dependent tests.

Post-release
- Create a GitHub release with notes: highlights, performance, and format stability.
- Tag commit (e.g., v1.0.0).
- Monitor issue tracker; triage bug reports and requests.

Notes
- Some integration tests are intentionally skipped; they rely on network access and external tools.
- Persistence of the actor-based `ASNDatabase` is not finalized; use provided on-disk formats instead.
