# Census the hidden-file filter sites

Type: research
Status: resolved
Blocked by: —

## Question

Enumerate **every** code path in the app that filters, skips, or excludes hidden (dot-prefixed)
entries, so the toggle can be applied consistently and nothing is missed. For each site, record:
file:line, what it filters (dot-prefix? `.skipsHiddenFiles`? named `.git`/`node_modules`?), and
whether it feeds directory display, the Navigator tree, search, file-watching, or archives.

Known starting points (from charting; confirm + extend):
- `FileScanner.scan` — `.skipsHiddenFiles` (FileScanner.swift:17)
- `FileScanner.scanBatched` — `.skipsHiddenFiles` (FileScanner.swift:79, :130); root loop skips
  `.git`/`node_modules` by name (:83); `shouldSkipComponent` (:195)
- `FileWatcher` — `hasPrefix(".")` filter (FileWatcher.swift:50–55)
- `DirectoryWindowView` — Navigator/index tree builder `guard !item.hasPrefix(".")` (:1167)
- Check also: `SidebarTree`/`SidebarView`, `QuickOpenView`, `FuzzyMatcher`, `Search/`,
  `ZipVirtualFS`.

Deliverable: a short markdown census (linked as an asset) listing each site + its role. This is
the reference every implementation ticket works against.

## Answer

Full census: [assets/census-filter-sites.md](../assets/census-filter-sites.md).

**Headline: `FileScanner` is the single chokepoint.** Threading the toggle through `FileScanner`
covers directory display, the Navigator/Sidebar tree, QuickOpen, Find-in-Files, archives, and
Mermaid validation — they all funnel through `FileScanner.scan`/`scanBatched` and carry no
dot-filter of their own.

Only **two** sites filter dot-entries independently (outside `FileScanner`):
- **`FileWatcher.swift:50–55`** — `hasPrefix(".")` + `node_modules`/`Derived`/`build`; gates live
  auto-reload.
- **`generateAutoIndex` (`DirectoryWindowView.swift:1167`)** — the auto-index HTML directory page.
  (This corrects the "Navigator tree builder" guess from charting — the Navigator actually
  inherits `FileScanner`; the independent site is the rendered directory-listing page.)

Inside `FileScanner`, the relevant lines are `:17`, `:79`, `:130` (`.skipsHiddenFiles`), plus the
always-exclude at `:83` and `shouldSkipComponent` `:195`. The scanner has **4 call sites**
(`ContentSearch:32`, `ArchiveHandler:17`, `DirectoryWindowView:1018`, `MermaidValidator:202`) a new
`showHidden` param must account for.

Two fog patches are cleared by this census (search-surface consistency, ZIP archives) — both
inherit `FileScanner`, so they're absorbed into the scanner ticket rather than becoming tickets.
