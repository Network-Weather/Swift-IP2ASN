# Contributing to SwiftIP2ASN

We welcome contributions to SwiftIP2ASN! This document outlines the process for contributing to the project.

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/swift-ip2asn.git
   cd swift-ip2asn
   ```
3. Create a new branch for your feature or bug fix:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Setup

### Prerequisites

- Xcode 15+ (for Swift 6 support)
- macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+
- Swift 6.0+

### Building

```bash
# Build the package
swift build

# Build in release mode
swift build -c release
```

### Testing

```bash
# Run all tests
swift test

# Run tests with coverage
swift test --enable-code-coverage

# Run specific test
swift test --filter TestName
```

### Documentation

The project uses DocC for documentation generation:

```bash
# Generate documentation locally (requires Xcode 15+)
swift package --allow-writing-to-directory docs-out \
  generate-documentation --target SwiftIP2ASN \
  --output-path docs-out \
  --transform-for-static-hosting
```

## Code Style

- Follow Swift's [API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use SwiftFormat for consistent code formatting
- Write clear, self-documenting code with appropriate comments
- Use meaningful variable and function names
- Follow the existing code style in the project

### Swift 6 Concurrency

This project uses Swift 6 with strict concurrency checking:
- Use `actor` for thread-safe data structures
- Prefer `async/await` over completion handlers
- Mark types as `Sendable` when appropriate
- Use `@MainActor` for UI-related code when needed

## Testing Guidelines

- Write comprehensive unit tests for new functionality
- Test both IPv4 and IPv6 address scenarios
- Include edge cases and error conditions
- Use descriptive test names that explain what is being tested
- Mock external dependencies where appropriate

### Performance Tests

For performance-critical changes:
- Include benchmarks showing before/after performance
- Test with realistic data sizes
- Document any performance characteristics

## Documentation

- Add DocC documentation comments for public APIs
- Include usage examples in documentation
- Update the README.md if adding new features
- Write clear commit messages

### DocC Documentation Style

```swift
/// Brief description of the function or type.
///
/// Longer description if needed, explaining the purpose and behavior.
///
/// - Parameters:
///   - parameter1: Description of parameter1
///   - parameter2: Description of parameter2
/// - Returns: Description of return value
/// - Throws: Description of errors that can be thrown
public func example(parameter1: String, parameter2: Int) throws -> String {
    // Implementation
}
```

## Submitting Changes

1. **Create a Pull Request**: Push your branch to your fork and create a pull request against the `main` branch

2. **PR Description**: Include:
   - Clear description of what the change does
   - Why the change is needed
   - Any breaking changes
   - Screenshots for UI changes (if applicable)
   - Test plan

3. **Tests**: Ensure all tests pass and add new tests for your changes

4. **Documentation**: Update documentation as needed

5. **Review Process**: 
   - Address feedback from reviewers
   - Keep the PR up to date with `main`
   - Be responsive to review comments

## Types of Contributions

### Bug Fixes
- Include a clear description of the bug
- Add a test that reproduces the bug (if possible)
- Verify the fix resolves the issue

### New Features
- Discuss the feature in an issue first
- Ensure it fits with the project's goals
- Include comprehensive tests
- Update documentation

### Performance Improvements
- Include benchmarks showing improvement
- Test with realistic data sets
- Document any trade-offs

### Documentation
- Fix typos and improve clarity
- Add examples and usage patterns
- Update API documentation

## Code Review

All submissions require code review. We use GitHub pull requests for this purpose. Reviews will check for:

- Code quality and style
- Test coverage
- Documentation completeness
- Performance impact
- Security considerations
- API design consistency

## Issues

When filing issues:

- Use the issue templates when available
- Provide a clear, concise title
- Include steps to reproduce (for bugs)
- Specify your environment (Swift version, platform, etc.)
- Include relevant code snippets or logs

## Community

- Be respectful and inclusive
- Help others learn and grow
- Follow the [Swift Community Guidelines](https://swift.org/community/)
- Ask questions in discussions or issues

## Security

If you find a security vulnerability, please do not open a public issue. Instead, email the maintainers directly or use GitHub's security advisory feature.

## License

By contributing to SwiftIP2ASN, you agree that your contributions will be licensed under the MIT License.

## Questions?

If you have questions about contributing, feel free to:
- Open an issue for discussion
- Start a discussion on GitHub
- Check existing issues and discussions

Thank you for contributing to SwiftIP2ASN! 🎉