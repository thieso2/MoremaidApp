# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

**Always use `mise` tasks.** Never use bare `tuist xcodebuild` or `xcodebuild` directly.

```bash
mise build          # Build the app
mise run            # Build and run in background (checks port 13277)
mise debug          # Build and run in foreground (see stdout)
mise clean-build    # Wipe .derivedData and rebuild from scratch
mise test           # Run unit tests
mise generate       # Regenerate Xcode project (after changing Project.swift)
mise check-port     # Check what's using port 13277
mise dist           # Copy built .app to .build/
```

After changing `Project.swift` or `Tuist.swift`, run `mise generate` before `mise build`.

## Project Configuration

- **Bundle ID:** `de.tmp8.moremaid` (team `6629AD7A87`, automatic signing)
- **Targets:** Moremaid (app), MoremaidCLI (command-line `mm`), MoremaidQuickLook (extension), MoremaidTests
- **Swift 6** with strict concurrency, macOS 14.0+ deployment target
- **Dependencies:** ZIPFoundation (ZIP handling); marked.js, Prism.js, Mermaid.js loaded via CDN
- **App sandbox disabled** via `Moremaid.entitlements` for filesystem access
- **Tuist** for project generation, DerivedData in local `.derivedData/`

## Architecture

### Module Layout (`Sources/`)

| Module | Purpose |
|---|---|
| `App/` | App lifecycle, window management, state persistence, preferences |
| `FileBrowser/` | Directory browsing, single-file view, WebView wrapper, TOC, tabs, search UI |
| `Rendering/` | HTML generation, CSS themes/typography, JavaScript page scripts |
| `Search/` | Fuzzy matcher (QuickOpen), content search (Find in Files) |
| `Archive/` | ZIP virtual filesystem, LRU cache, pack/unpack operations |
| `FileWatcher/` | FSEvents-based file change monitoring |
| `Shared/` | Models (`OpenTarget`, `FileEntry`), constants, utilities |
| `Validation/` | Mermaid diagram syntax checking |

### Window Lifecycle

SwiftUI `WindowGroup(id: "main")` creates windows. Each `WindowRootView` instance claims a target from a queue:

1. `AppState` loads saved sessions on init → populates `pendingSessions`
2. First window's `.task` calls `claimPendingSession()` and opens remaining via `openWindow(id: "main")`
3. New windows from Cmd+O or drag-drop go through `pendingTargets` queue
4. Windows with no target to claim call `dismiss()`
5. `WindowFrameTracker` (NSViewRepresentable) saves window position every 2s

**Flicker prevention:** `WindowTrackerView` (custom NSView) sets `window.alphaValue = 0` in `viewDidMoveToWindow()` before the window renders. The window is revealed (`alphaValue = 1`) only after content is claimed.

### Rendering Pipeline

`HTMLGenerator` → inline HTML with marked.js + Prism.js + Mermaid.js → loaded into `WKWebView`

- All CSS/JS inlined in the HTML string (no local file serving for single pages)
- 10 color themes, 6 typography styles (configured via `Constants`)
- `PageScripts.swift` contains all client-side JavaScript (heading extraction, copy buttons, link handling)

### WebView Bridge (JS ↔ Swift)

`WebView.swift` wraps WKWebView with a message handler bridge:
- **JS → Swift:** `window.webkit.messageHandlers.swift.postMessage({type, ...})`
- Message types: `linkClick`, `headings`, `loadComplete`, `externalLink`
- **Link interception:** Internal `.md` links navigate in-app; external links open browser; Cmd+click opens new tab/window
- **Auto-reload:** Polls file content hash every 1s, reloads WebView on change

### File Discovery

`FileScanner` recursively scans directories on a background DispatchQueue, respects `.gitignore` via `GitignoreParser`, skips `node_modules`/`.git`. Returns `[FileEntry]` used identically by directory view and ZIP virtual filesystem.

### State Persistence (UserDefaults)

- `savedWindowSessions` — window positions and open files (restored on launch)
- `recentTargets` — last 10 opened files/folders
- `defaultTheme`, `defaultTypography`, `defaultZoom` — appearance preferences
- `showBreadcrumb`, `showStatusBar`, `restoreWindows` — UI toggle states

## Gotchas

- **Port 13277 conflict:** The Node.js `mm` CLI (parent project) uses the same port. Always `mise check-port` or `lsof -i :13277` before testing.
- **macOS Tahoe toolbar placements:** Only `.navigation` renders by default. Use `.toolbarRole(.editor)` on the view for `.primaryAction`/`.secondaryAction` items to appear.
- **SwiftUI MenuBarExtra:** `.task` on MenuBarExtra content only triggers when the menu is opened, not at app launch.
- **Do NOT use `open` command** to launch the built app — macOS LaunchServices caches old binaries. Use `mise run` or `mise debug` instead.
