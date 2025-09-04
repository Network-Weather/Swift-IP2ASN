#!/bin/bash

echo "Setting up SwiftIP2ASN development environment..."

# Configure git hooks
echo "Configuring Git hooks..."
git config core.hooksPath .githooks

# Build the project
echo "Building project..."
swift build
if [ $? -ne 0 ]; then
    echo "❌ Initial build failed. Please check for errors."
    exit 1
fi

# Run tests
echo "Running tests..."
swift test
if [ $? -ne 0 ]; then
    echo "⚠️  Some tests failed. Please review and fix."
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Git hooks have been configured to run:"
echo "  • Swift formatting on pre-commit"
echo "  • Tests on pre-commit and pre-push"
echo "  • Build verification on pre-push"
echo ""
echo "To run tests: swift test"
echo "To format code: swift format -i -r Sources/ Tests/"
echo "To lint code: swift format lint -r Sources/ Tests/"