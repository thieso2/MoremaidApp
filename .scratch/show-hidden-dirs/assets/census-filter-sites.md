# Census: hidden-file / dot-entry filter sites

Asset for ticket **Census the hidden-file filter sites**. Sweep date: 2026-07-24.
Method: `grep` across `Sources/**/*.swift` for `.skipsHiddenFiles`, `hasPrefix(".")`, named
excludes (`.git`/`node_modules`/`Derived`/`build`), and every `enumerator` / `contentsOfDirectory`
call, then traced each file-consuming surface to its source.

## Headline

**`FileScanner` is the single chokepoint.** Almost every surface that lists files funnels through
`FileScanner.scan` / `FileScanner.scanBatched`, so threading the toggle through `FileScanner`
covers them all at once. Only **two** places filter dot-entries independently and need separate
changes: **`FileWatcher`** and the **auto-index HTML page** (`generateAutoIndex`).

## A. Independent filter sites — must each honor the toggle

| # | Site | File:line | What it filters | Role |
|---|------|-----------|-----------------|------|
| 1 | `FileScanner.scan` | `FileScanner.swift:17` | `.skipsHiddenFiles` enumerator option | Non-batched scan (used by ContentSearch, ArchiveHandler, MermaidValidator) |
| 2 | `FileScanner.scanBatched` | `FileScanner.swift:79, :130` | `.skipsHiddenFiles` (root `contentsOfDirectory` + per-subtree enumerators) | Batched scan feeding the directory window |
| 3 | `FileScanner` root name-skip | `FileScanner.swift:83` | `name == "node_modules" \|\| name == ".git"` | Always-exclude at root of batched scan |
| 4 | `FileScanner.shouldSkipComponent` | `FileScanner.swift:195–202` | path contains `node_modules` / `.git` component | Always-exclude at any depth (both scan paths) |
| 5 | `FileWatcher` change filter | `FileWatcher.swift:50–55` | `c.hasPrefix(".") \|\| c == "node_modules" \|\| c == "Derived" \|\| c == "build"` | Drops hidden/noise paths from live FSEvents → gates auto-reload + `updateProjectFilesFromEvent` |
| 6 | `generateAutoIndex` | `DirectoryWindowView.swift:1167` | `guard !item.hasPrefix(".")` (+ gitignore :1170) | Builds the **auto-index HTML directory-listing page** shown when opening a folder / clicking a subdir |

Sites 1–4 are all inside `FileScanner` → covered by the scanner ticket.
Sites 5–6 are outside `FileScanner` → covered by the sibling-filters ticket.

## B. Surfaces that INHERIT FileScanner — no separate change needed

These consume `FileScanner` output (or an already-filtered list), so they follow the toggle for
free once `FileScanner` honors it:

| Surface | File:line | How it sources files |
|---|---|---|
| Directory window / `projectFiles` | `DirectoryWindowView.swift:1018` | `FileScanner.scanBatched(...)` |
| Navigator / Sidebar tree | `SidebarView.swift` / `SidebarTree.swift` | Renders `projectFiles`; **no** dot-filter of its own |
| QuickOpen (fuzzy open) | `QuickOpenView.swift:73,92,104` | Filters the existing `projectFiles` list by path prefix; no dot-filter |
| Find in Files (content search) | `ContentSearch.swift:32` | `FileScanner.scan(directory:filter:)` |
| Archive browsing | `ArchiveHandler.swift:17` | `FileScanner.scan(...)` |
| Mermaid validation | `MermaidValidator.swift:202` | `FileScanner.scan(directory:filter: .markdownOnly)` |

## C. Not a filter — no change needed

- `DirectoryWindowView.tryLoadInitialFile` (`:1033`) — lists the dir to find a README/index; only
  matches known non-dot default names (`readme.md`, `index.md`, `claude.md`…). No dot-filter.
- `ZipVirtualFS.swift` — path normalization only (`hasPrefix("./")` at :20); no dot-entry filter.
  Archives are filtered via `ArchiveHandler` → `FileScanner` (row in B).

## D. Call-site impact for the scanner ticket

`FileScanner.scan` / `scanBatched` have **4 call sites** that a new `showHidden` parameter must
account for (add the arg, or default it): `ContentSearch.swift:32`, `ArchiveHandler.swift:17`,
`DirectoryWindowView.swift:1018`, `MermaidValidator.swift:202`.

## E. Consequences for the map

- **Fog "Search surfaces (QuickOpen / Find in Files) consistency"** → resolved: both inherit
  `FileScanner`, so no separate decision or ticket — absorbed by the scanner ticket.
- **Fog "ZIP virtual filesystem"** → resolved: archives inherit `FileScanner` via `ArchiveHandler`;
  `ZipVirtualFS` has no dot-filter. Absorbed by the scanner ticket.
- **Sibling-filters ticket** correction: the second independent site is the **auto-index page**
  (`generateAutoIndex`), *not* the Navigator tree (the Navigator inherits `FileScanner`).
