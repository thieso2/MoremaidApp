# Build the module-by-module port map

Type: grilling
Status: resolved
Blocked by: 04, 05

## Question

Walk all eight macOS modules and fix each one's Linux counterpart. This produces the central table
of HANDOFF.md, so every row needs a verdict — **port verbatim / reimplement / replace with a
library / drop** — and a named library where one replaces hand-written code.

| module | what's in it |
|---|---|
| `App/` | lifecycle, `AppState`, preferences, state persistence, file picker, quick-open commands |
| `FileBrowser/` | `DirectoryWindowView`, `SingleFileView`, `WebView` wrapper, Navigator (`SidebarView`, `SidebarTree`, `HeadingParser`), `QuickOpenView`, `SearchInFilesView`, `FileScanner`, `GitignoreParser`, `DiagramWindowController` |
| `Rendering/` | `HTMLGenerator`, `BaseCSS`, `ThemeCSS`, `TypographyCSS`, `PageScripts`, `MermaidConfig`, `LanguageMaps` |
| `Search/` | `FuzzyMatcher`, `ContentSearch` |
| `FileWatcher/` | FSEvents-based watching + 1s content-hash polling for live reload |
| `Shared/` | `Models` (`OpenTarget`, `FileEntry`, `RecentTarget`), `Constants`, `SearchHistory`, utilities |
| `Validation/` | `MermaidValidator` |
| `Archive/` | ZIP virtual FS, LRU cache — **out of scope for v1**, but record where the seam is |

Points that need real decisions rather than transcription:

- **`FileWatcher`** — FSEvents has no direct equivalent. `GFileMonitor` / raw `inotify` /
  a polling fallback: which, and what are the descriptor limits on a large tree?
- **`FileScanner`** — respects `.gitignore` and skips `node_modules`/`.git`; is there a library
  for gitignore semantics in the chosen language, or does `GitignoreParser` get ported?
- **`HeadingParser`** — deliberately mirrors the JS slugify in `PageScripts.swift` so anchor IDs
  match. Whatever the port, that coupling must survive; say how it's kept honest.
- **The Navigator** — a flat row list backed by a `LazyVStack` for laziness. What's the GTK4
  equivalent that stays lazy over a large tree (`GtkListView` + a model), and does the
  folder-expansion persistence survive?
- **Anything with no counterpart** — list it explicitly rather than letting it go missing.

## Answer

**The recurring verdict is *delete* or *use a crate*, and both are the point.** Choosing Rust made
this table shorter rather than longer: the ripgrep libraries are available in-process, so three
hand-written Swift components vanish into dependencies instead of being retyped.

| macOS | verdict | notes |
|---|---|---|
| `App/` lifecycle, `AppState` | **reimplement, much smaller** | `GtkApplication`, one window per process. Most of `AppState` evaporates with session restore. |
| `App/PreferencesView` | **delete** | Replaced by `config.toml`. Nothing left to put in a window once themes and typography are gone. |
| `App/PDFBatchExporter`, `CLIInstaller`, `CheckForUpdatesView` | **delete** | Out of scope; pacman updates. |
| `App/FilePicker` | **replace** | XDG file-chooser portal via GTK's `FileDialog`. |
| `App/QuickOpenCommands` | **fold in** | Becomes plain accelerator registration. |
| `FileBrowser/DirectoryWindowView`, `SingleFileView` | **reimplement** | One window, two modes. |
| `FileBrowser/WebView` | **reimplement, small** | `webkit6-rs` wrapper. The script-message bridge is the single highest-risk piece; see the [audit](03-webkitgtk-audit.md). |
| Navigator: `SidebarView`, `SidebarTree` | **reimplement** | `GtkListView` + a list model, to stay lazy over a large tree as the `LazyVStack` does. Expect this to be the fiddliest UI code in the project. |
| `FileBrowser/HeadingParser` | **port by hand, with a shared fixture** | Deliberately mirrors the JS slugify in `PageScripts.swift` so anchor IDs match. **Ship a fixture list of heading→slug pairs as a test on both the Rust and JS sides** — without it this coupling rots silently and links break for headings nobody tested. |
| `FileBrowser/QuickOpenView`, `SearchInFilesView` | **reimplement** | Overlay over the window. |
| `FileBrowser/FileScanner` | **delete → `ignore` crate** | ripgrep's directory walker: parallel, gitignore-aware, with the `.git`/`node_modules` skips configurable. Replaces the hand-written scanner outright. |
| `FileBrowser/GitignoreParser` | **delete → `ignore` crate** | Same crate. Gitignore semantics are fiddlier than they look; this is the reference implementation. |
| `Search/ContentSearch` | **delete → `grep` crates** | `grep-searcher` + `grep-regex`, in-process. Same engine as ripgrep, no subprocess, no JSON parsing, no runtime dependency on `rg` being installed. |
| `Search/FuzzyMatcher` | **delete → `nucleo` (or `fuzzy-matcher`)** | In-process matching, built for exactly this live-filtering case. |
| `FileWatcher/` | **reimplement → `notify` crate** | inotify underneath. **Drop the 1s content-hash polling** — it was a macOS-era workaround and inotify is reliable here. Watch open files and the visible tree only; a recursive watch over a large tree will exhaust inotify descriptors, which is a real failure mode on `node_modules`-shaped trees. |
| `FileBrowser/DiagramWindowController` | **reimplement as a toplevel** | Per the [window model](06-window-model.md). |
| `Rendering/*` | **reuse verbatim** | Vendored assets + string substitution. `ThemeCSS` collapses to a generated palette, `TypographyCSS` to one style, `MermaidConfig` derives from the palette. `LanguageMaps` crosses as data. |
| `Shared/Models` | **simplify hard** | `OpenTarget` mostly collapses: no window de-duplication, no session restore, no `.empty` case. `RecentTarget` survives. |
| `Shared/SearchHistory`, `Constants`, utilities | **port** | Trivial. |
| `Validation/MermaidValidator` | **port by hand** | Self-contained, no crate equivalent. |
| `Archive/*` | **out of scope — and build no seam for it** | Read from the filesystem directly. When archives arrive, refactor then; a virtual-filesystem abstraction built now, for a feature not in v1, is speculative cost with no payer. |

**Net effect.** Roughly a third of the macOS codebase is deleted rather than ported; four more
components (`FileScanner`, `GitignoreParser`, `ContentSearch`, `FuzzyMatcher`) are replaced by two
crates; the largest single asset — the rendering layer — crosses over untouched. What is genuinely
new work is the GTK shell, the WebKitGTK bridge, and the lazy sidebar.
