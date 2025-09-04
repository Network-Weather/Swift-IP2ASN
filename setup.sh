#!/bin/bash

echo "Setting up SwiftIP2ASN development environment..."

# Configure git hooks
echo "Configuring Git hooks..."
git config core.hooksPath .githooks

# Install SwiftLint if on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! which swiftlint >/dev/null; then
        echo "Installing SwiftLint..."
        if which brew >/dev/null; then
            brew install swiftlint
        else
            echo "⚠️  Homebrew not found. Please install SwiftLint manually:"
            echo "    brew install swiftlint"
        fi
    else
        echo "✅ SwiftLint already installed"
    fi
fi

# Install swift-format
echo "Installing swift-format..."
swift build -c release --product swift-format --package-path .build/checkouts/swift-format
if [ $? -eq 0 ]; then
    echo "✅ swift-format installed"
else
    echo "⚠️  swift-format installation failed. You can install it manually later."
fi

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
echo "To format code: swift-format -i -r Sources/ Tests/"
echo "To lint code: swiftlint"