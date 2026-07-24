# Decide gitignore interaction when hidden files are shown

Type: grilling
Status: resolved
Blocked by: —

## Question

When "Show Hidden Files" is ON, does `.gitignore` filtering still apply? A hidden dir like `.build`
or `.cache` is often gitignored — should turning on "show hidden" reveal it, or does gitignore
still win? Two coherent positions:

- **Gitignore still wins** — "show hidden" only lifts the dot-prefix filter; gitignored entries
  stay hidden. Predictable, keeps ignored noise out.
- **Show hidden overrides gitignore** — the toggle means "show me everything hidden," including
  gitignored dot-dirs. Closer to a raw filesystem view.

Note the always-excluded set (`.git`/`node_modules`/build) is settled separately — those stay out
regardless. This ticket is only about the gitignore layer. Resolve with the user; the answer sets
the ordering in `FileScanner` (blocks the scanner ticket).

## Answer

**Gitignore still wins.** (User decision, 2026-07-24.)

"Show Hidden Files" lifts **only** the dot-prefix filter (`.skipsHiddenFiles`); the gitignore layer
stays independent and unchanged. So with the toggle ON you see `.github/`, `.vscode/`, `.env` — but
gitignored dot-dirs like `.derivedData/`, `.build/`, `.DS_Store` stay hidden.

Rationale: the scan already runs two independent filters — `.skipsHiddenFiles` and
`gitignore.isIgnored(relativePath)` (`FileScanner.swift`; `GitignoreParser.isIgnored`). The toggle
only removes the first. Concrete stakes that settled it: overriding gitignore would flood *this*
repo's browser with `.derivedData/` (huge), `.build/`, `Tuist/.build/`, `.DS_Store`. Matches how
VS Code separates "show hidden" from gitignore filtering. Predictable, and the smallest change.

**Implication for the scanner ticket:** do NOT touch the `gitignore.isIgnored(...)` checks. The only
change is making the three `.skipsHiddenFiles` options conditional on `showHiddenFiles`. The
gitignore call in `generateAutoIndex` (`:1170`) likewise stays.
