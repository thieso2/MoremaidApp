# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

**Always use `mise` tasks.** Never use bare `tuist xcodebuild` or `xcodebuild` directly.

```bash
mise build          # Build the app
mise run            # Build and run in background
mise debug          # Build and run in foreground (see stdout)
mise clean-build    # Wipe .derivedData and rebuild from scratch
mise test           # Run unit tests
mise generate       # Regenerate Xcode project (after changing Project.swift)
mise dist           # Copy built .app to .build/
```

After changing `Project.swift` or `Tuist.swift`, run `mise generate` before `mise build`.

## Project Configuration

- **Bundle ID:** `de.tmp8.moremaid` (team `6629AD7A87`, automatic signing)
- **Targets:** Moremaid (app), MoremaidCLI (command-line `mm`), MoremaidQuickLook (extension), MoremaidTests
- **Swift 6** with strict concurrency, macOS 15.0+ deployment target
- **Dependencies:** ZIPFoundation (ZIP handling); markdown-it, Prism.js, Mermaid.js loaded via CDN
- **App sandbox disabled** via `Moremaid.entitlements` for filesystem access
- **Tuist** for project generation, DerivedData in local `.derivedData/`

## Architecture

### Module Layout (`Sources/`)

| Module | Purpose |
|---|---|
| `App/` | App lifecycle, window management, state persistence, preferences |
| `FileBrowser/` | Directory browsing, single-file view, WebView wrapper, **Navigator** (left sidebar — `SidebarView.swift` / `SidebarTree.swift` / `HeadingParser.swift`), tabs, search UI |
| `Rendering/` | HTML generation, CSS themes/typography, JavaScript page scripts |
| `Search/` | Fuzzy matcher (QuickOpen), content search (Find in Files) |
| `Archive/` | ZIP virtual filesystem, LRU cache, pack/unpack operations |
| `FileWatcher/` | FSEvents-based file change monitoring |
| `Shared/` | Models (`OpenTarget`, `FileEntry`), constants, utilities |
| `Validation/` | Mermaid diagram syntax checking |

### Window Lifecycle

SwiftUI `WindowGroup(for: OpenTarget.self)` — each window holds an `OpenTarget?` value. SwiftUI handles lifecycle, "focus existing window with same value", and would handle restoration except we opt out:

- `.restorationBehavior(.disabled)` — no window restoration across launches
- `.defaultLaunchBehavior(.suppressed)` — no empty window at launch
- `application(_:open:)` (AppDelegate) → `appState.openTarget(target)` → handler bridge (registered by `WindowRootView.task`) → `openWindow(value: target)`
- File → Open / Open Recent / ⌘N call `openWindow(value:)` directly from the Commands DSL.
- New tab uses `NSWindow.tabbingMode = .preferred` + a fresh `OpenTarget.empty(UUID())` so each tab is a unique value.

`OpenTarget` cases: `.file(path)`, `.directory(path, initialFile)`, `.empty(UUID)`. `RecentTarget` is a separate Codable type used for UserDefaults persistence (decoupled from `OpenTarget` so adding cases doesn't break old data).

### Navigator

Left sidebar = "Navigator". Toggle with ⇧⌘T. Source: `SidebarView.swift`. Renders a flat row list (`SidebarRow` enum: folder / file / heading) so `LazyVStack` is actually lazy. Headings are parsed on-demand via `HeadingParser` (mirrors the JS slugify in `PageScripts.swift` so anchor IDs match). Folder expansion persists per directory in UserDefaults; file expansion is ephemeral per session.

### Rendering Pipeline

`HTMLGenerator` → inline HTML with markdown-it + Prism.js + Mermaid.js → loaded into `WKWebView`

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

## Releasing

To release a new version:

1. Bump **both** `CFBundleShortVersionString` **and** `CFBundleVersion` (integer build number) in `Project.swift` (both Moremaid and MoremaidQuickLook targets). **`CFBundleVersion` MUST be incremented** — Sparkle uses `sparkle:version` (derived from `CFBundleVersion`) to detect updates; if the build number stays the same, Sparkle will not offer the update.
2. Commit the version bump
3. Create a GitHub Release with a `v`-prefixed tag (this triggers the CI workflow):
   ```bash
   gh release create v0.X.Y --generate-notes --title "v0.X.Y"
   ```
   **Do NOT just push a tag** — the release workflow triggers on tag push, but creating the release via `gh release create` ensures the tag and release are created atomically.
4. CI handles: build, sign, notarize, attach ZIP to release, update Sparkle appcast, update Homebrew tap

## Gotchas

- **macOS Tahoe toolbar placements:** Only `.navigation` renders by default. Use `.toolbarRole(.editor)` on the view for `.primaryAction`/`.secondaryAction` items to appear.
- **SwiftUI MenuBarExtra:** `.task` on MenuBarExtra content only triggers when the menu is opened, not at app launch.
- **Do NOT use `open` command** to launch the built app — macOS LaunchServices caches old binaries. Use `mise run` or `mise debug` instead.
