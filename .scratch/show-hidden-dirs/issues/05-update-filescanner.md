# Update FileScanner to honor the toggle

Type: task
Status: retired
Blocked by: 01, 02, 03

> **Retired — superseded by `tickets.md` (repo root).** The implementation was re-sliced into
> vertical tracer-bullet tickets via `/to-tickets`. This scanner work is folded into the first
> ticket, "Reveal hidden files everywhere the browser lists them". Do not work this ticket; work
> `tickets.md`.

## Question

Thread the `showHiddenFiles` flag into `FileScanner` so that, when ON, the three enumerators drop
`.skipsHiddenFiles` (FileScanner.swift:17, :79, :130) and hidden dot-entries are returned — while
`.git`, `node_modules`, and build dirs stay excluded at **every** level.

Because removing `.skipsHiddenFiles` now exposes `.git` (and other always-excluded dirs) at the
root and in subtrees, harden the exclusion:
- Strengthen `shouldSkipComponent` (:195) and the `scanBatched` root loop (:83) so the
  always-excluded set is skipped by name at any depth, not incidentally via `.skipsHiddenFiles`.
- Apply the gitignore ordering decided in the gitignore-interaction ticket: **gitignore still
  wins** — do NOT touch any `gitignore.isIgnored(...)` check. The *only* change is making the three
  `.skipsHiddenFiles` options (`:17`, `:79`, `:130`) conditional on `showHiddenFiles`. Ignored
  dot-dirs (`.derivedData`, `.build`, `.DS_Store`) stay hidden even with the toggle on.

Pass the flag through `FileScanner.scan` / `scanBatched` signatures (and `FileFilter` if that's the
cleaner seam — decide here). Uses the census (#01) as the authority on which call sites exist.

**Per the census (#01):** `FileScanner` is the single chokepoint, so this one change also makes the
Navigator/Sidebar tree, QuickOpen, Find-in-Files, and archive browsing honor the toggle for free —
no separate work for those surfaces. Update the **4 call sites** a new `showHidden` param touches:
- `Search/ContentSearch.swift:32`
- `Archive/ArchiveHandler.swift:17`
- `FileBrowser/DirectoryWindowView.swift:1018` (the batched scan — this is where the app-wide
  preference is actually read and passed in)
- `Validation/MermaidValidator.swift:202` (markdown-only; a default of "off" is fine here)
