# macOS App - Claude Code Instructions

## Build & Run

**Always use `mise` tasks** for building and running. Never use bare `tuist xcodebuild` or `xcodebuild` directly.

```bash
# Build the app
mise build

# Build and run (background, checks port)
mise run

# Build and run in foreground (for debugging output)
mise debug

# Clean build (wipe DerivedData + rebuild)
mise clean-build

# Run unit tests
mise test

# Generate Xcode project (after changing Project.swift)
mise generate

# Check what's on the server port
mise check-port

# Copy built .app to .build/
mise dist
```

## Architecture

- SwiftUI app, Swift 6 strict concurrency, macOS 14.0+
- Tuist for project generation, FlyingFox HTTP server, ZIPFoundation
- App sandbox disabled via entitlements for filesystem access
- Bundle ID: `de.tmp8.moremaid`
