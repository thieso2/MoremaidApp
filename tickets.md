# Tickets: Show Hidden Files toggle (⇧⌘.)

Vertical slices implementing the app-wide "Show Hidden Files" feature. Source spec:
[.scratch/show-hidden-dirs/PRD.md](.scratch/show-hidden-dirs/PRD.md). The `"showHiddenFiles"`
preference (default off) and its Preferences → General checkbox already exist and build green — the
tickets below make that checkbox actually do something, then add the ⇧⌘. shortcut.

Work the **frontier**: any ticket whose blockers are all done. Here that means Ticket 1, then Ticket 2.

## Reveal hidden files everywhere the browser lists them

**What to build:** With "Show hidden files" ticked in Preferences → General, every file-listing
surface reveals hidden (dot-prefixed) files and directories — and unticking hides them again, live,
in every open window without reopening. Because `FileScanner` is the single chokepoint that the
directory view, Navigator/Sidebar tree, Quick Open, Find in Files, archive browsing, and Mermaid
validation all funnel through, threading the flag through it covers all of those at once; the two
sites that filter dot-entries independently — the file-watcher and the auto-index directory-listing
page — are updated to match. Gitignored entries (`.derivedData/`, `.build/`) stay hidden regardless,
and `.git`/`node_modules`/build stay excluded regardless.

**Blocked by:** None — can start immediately.

- [ ] `FileScanner` (both the plain and batched scan paths) takes a `showHidden` flag; when on, hidden dot-entries are returned, when off behavior is unchanged. All existing call sites are reconciled with the new signature (content search, archive handler, Mermaid validation, directory window).
- [ ] The directory window reads the app-wide `showHiddenFiles` preference and passes it into the scan.
- [ ] Flipping the preference re-scans and redraws every open directory window immediately (live), via `@AppStorage` observation or the existing app-wide `settingsChanged` notification — chosen by the implementer, driven consistently from the Preferences toggle.
- [ ] The file-watcher honors the flag so a newly-created hidden file triggers auto-reload when the toggle is on; its always-excluded set matches the scanner's.
- [ ] The auto-index directory-listing page honors the flag while keeping its gitignore check.
- [ ] `.gitignore` filtering is untouched — gitignored dot-entries stay hidden with the toggle on.
- [ ] `.git`, `node_modules`, and build directories are excluded by name at root and any depth, not incidentally via the hidden-entry skip.
- [ ] With the toggle off, the visible file set is identical to today (regression guard).
- [ ] A fixture-based `FileScanner.scan` test (Swift Testing) builds a temp tree — plain file/dir, `.github/x.md`, `.env`, `.git/`, `node_modules/`, a gitignored `.build/` — and asserts: off → only plain entries; on → plain entries plus `.github/x.md` and `.env`, but never `.git`/`node_modules`/`.build`.
- [ ] `mise test` and `mise build` pass.

## Toggle hidden files with ⇧⌘. and a View-menu item

**What to build:** Pressing ⇧⌘. (Finder's hidden-files shortcut) flips the app-wide setting and
visibly reveals/hides dot-entries across all open windows; a checkmarked "Show Hidden Files" item in
the View menu does the same and reflects the current state. Both are just additional drivers of the
same preference the Preferences checkbox already sets.

**Blocked by:** Reveal hidden files everywhere the browser lists them (needs its live-refresh so the
shortcut has a visible effect).

- [ ] ⇧⌘. is bound in the Commands DSL and flips the `showHiddenFiles` preference; confirmed not to collide with an existing Moremaid command.
- [ ] A "Show Hidden Files" checkbox item appears in the View menu (alongside the ⇧⌘T Navigator toggle) with a checkmark reflecting the current state.
- [ ] Triggering either the shortcut or the menu item reveals/hides dot-entries live in every open window, identically to the Preferences checkbox.
- [ ] `mise build` passes.
