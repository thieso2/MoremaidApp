# Apply the toggle to sibling filters and refresh open windows

Type: task
Status: retired
Blocked by: 01, 02

> **Retired — superseded by `tickets.md` (repo root).** The implementation was re-sliced into
> vertical tracer-bullet tickets via `/to-tickets`. The refresh half is folded into the first
> ticket, "Reveal hidden files everywhere the browser lists them"; the sibling-site work lives there
> too. Do not work this ticket; work `tickets.md`.

## Question

Two things the scanner ticket doesn't cover:

1. **Sibling filters** — the census (#01) found exactly **two** sites that filter dot-entries
   independently of `FileScanner`; both must honor `showHiddenFiles` so display stays consistent:
   - **`FileWatcher.swift:50–55`** — `hasPrefix(".")` + `node_modules`/`Derived`/`build`. Else
     newly-added hidden files won't trigger auto-reload, and its always-excluded set must match the
     scanner's.
   - **`generateAutoIndex` (`DirectoryWindowView.swift:1167`)** — the auto-index HTML
     directory-listing page (`guard !item.hasPrefix(".")`, plus its own gitignore check at :1170).
   - **NOT** the Navigator/Sidebar tree — the census confirmed it inherits `FileScanner`, so it's
     already handled by the scanner ticket (#05). No `SidebarTree` change needed.

2. **Re-scan / refresh propagation** — since the toggle is app-wide, flipping it must make **all
   open directory windows** re-scan and redraw live (not just on next open). Decide the mechanism
   (observe the `@AppStorage` value → re-run the scan; or a notification the windows subscribe to)
   and wire it. This is the part that turns "preference changed" into "windows update."

Resolve the mechanism as part of this ticket. Depends on the preference (#02) existing and the
census (#01) being complete.
