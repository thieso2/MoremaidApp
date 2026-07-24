# Map: Show Hidden Files toggle (⇧⌘.)

Label: `wayfinder:map`

## Destination

Moremaid gains an **app-wide "Show Hidden Files" toggle**, bound to **⇧⌘.**, that makes the
directory scanner traverse and display hidden (dot-prefixed) entries — files and directories —
while `.git`, `node_modules`, and build dirs stay excluded regardless. When the last ticket
resolves, the feature is shipped: the toggle persists across launches, flips every open window
live, and every place that filters dot-entries (scanner, file-watcher, Navigator tree, search)
honors it consistently.

## Notes

- **Domain:** macOS SwiftUI app. Build/run only via `mise` tasks (see CLAUDE.md). Scanner lives in
  `Sources/FileBrowser/FileScanner.swift`; UI toggles persist in UserDefaults (`showBreadcrumb`,
  `showStatusBar`, `restoreWindows` are the existing pattern in `Sources/App/`).
- **Execution is in-scope.** This map carries the feature to shipped, not just to a spec — the
  leaf `task` tickets are the actual implementation. (Overrides wayfinder's plan-only default.)
- **Implementation handed to `tickets.md` (repo root).** A `/to-spec` → `/to-tickets` pass
  synthesized the resolved decisions into [PRD.md](PRD.md) and two vertical tracer-bullet tickets in
  `tickets.md`. The three implementation tickets here (scanner / shortcut / sibling-filters) are
  **retired** — superseded by `tickets.md`. The frontier is now empty; work `tickets.md`, not this
  map. The map remains the record of the decisions that got us here (census, preference, gitignore).
- **Scoping decisions already fixed** (from the charting conversation, 2026-07-24):
  - Tracker = local markdown under `.scratch/show-hidden-dirs/`.
  - Toggle scope = **one app-wide preference** (not per-window). ⇧⌘. flips it everywhere; all open
    directory windows re-scan.
  - `.git` / `node_modules` / build dirs stay **always excluded** even when hidden is on — the
    toggle reveals ordinary dot-entries (`.github`, `.config`, `.vscode`, `.env`…), not the noise.
  - "Hidden" = Finder ⇧⌘. semantics: dot-prefixed **files and directories**, not directories only.
- Skills to consult when resolving: `/grilling` + `/domain-modeling` for the design tickets;
  `swiftui-specialist` for the SwiftUI/Commands wiring.

## Decisions so far

<!-- one line per closed ticket: gist of the answer + link -->

- [Census the hidden-file filter sites](issues/01-census-filter-sites.md) — `FileScanner` is the
  single chokepoint (Navigator, QuickOpen, Find-in-Files, archives, validation all inherit it); only
  `FileWatcher` (`:50–55`) and the auto-index page (`generateAutoIndex`, `:1167`) filter dots
  independently. Full asset: [census-filter-sites.md](assets/census-filter-sites.md).
- [Add the app-wide Show Hidden Files preference](issues/02-add-show-hidden-preference.md) — key
  `"showHiddenFiles"`, default `false`, decentralized `@AppStorage` (like `showBreadcrumb`); toggle
  added to Preferences → General. Propagation left to the sibling ticket. `mise build` green.
- [Decide gitignore interaction when hidden files are shown](issues/03-gitignore-interaction.md) —
  **gitignore still wins**: the toggle lifts only `.skipsHiddenFiles`, leaving `gitignore.isIgnored`
  untouched. So `.github`/`.vscode`/`.env` show, but ignored `.derivedData`/`.build` stay hidden.

## Not yet specified

<!-- in-scope fog; graduates as the frontier advances -->

- **Manual QA pass** — verify on a real directory containing `.github`, `.vscode`, a gitignored
  dot-dir, and `.git`. Can't ticket sharply until the implementation approach (esp. re-scan
  propagation and gitignore interaction) is settled.

<!-- Cleared by the census: "Search surfaces (QuickOpen / Find in Files)" and "ZIP virtual
     filesystem" both inherit FileScanner, so they're absorbed into the scanner ticket — no
     separate tickets. -->>

## Out of scope

<!-- ruled beyond the destination; never graduates -->

_(none yet)_
