# Spec: Show Hidden Files toggle (⇧⌘.)

Status: ready-for-agent
Slug: show-hidden-dirs
Wayfinder map: [.scratch/show-hidden-dirs/map.md](map.md)

## Problem Statement

When browsing a directory in Moremaid, hidden (dot-prefixed) files and directories — `.github/`,
`.vscode/`, `.config/`, `.env` — never appear. The scanner unconditionally skips them, so a user who
keeps real, editable content in dot-directories (docs under `.github/`, notes under `.config/`)
cannot see or open it from the file browser, the Navigator, Quick Open, or Find in Files. There is
no way to reveal these entries; the only workaround is to leave Moremaid and use Finder or a terminal.

## Solution

Add an app-wide **"Show Hidden Files"** toggle, bound to **⇧⌘.** (the same shortcut Finder uses),
that makes the file browser reveal hidden dot-prefixed files and directories everywhere they would
otherwise be filtered. The toggle:

- is a single application-wide preference (not per-window), persisted across launches, defaulting
  to **off**;
- flips live — pressing ⇧⌘. or toggling it in Preferences immediately re-scans every open directory
  window, no reopen required;
- is also reachable as a checkbox item in the View menu;
- keeps `.gitignore` filtering in force — turning it on reveals ordinary dot-entries but **not**
  gitignored ones (so `.derivedData/`, `.build/` stay hidden);
- keeps the heavyweight directories `.git`, `node_modules`, and build output always excluded,
  regardless of the toggle.

The net effect: with the toggle on, a user sees `.github/`, `.vscode/`, `.env` and can open them
like any other file; with it off, behavior is exactly as today.

## User Stories

1. As a Moremaid user, I want hidden dot-directories like `.github/` to appear in the file browser when I enable a setting, so that I can read and edit content I keep there without leaving the app.
2. As a Moremaid user, I want a keyboard shortcut (⇧⌘.) to toggle hidden files, so that I can flip visibility instantly the same way I do in Finder.
3. As a Moremaid user, I want the hidden-files setting to persist across launches, so that I don't have to re-enable it every time I open the app.
4. As a Moremaid user, I want the toggle to be a single app-wide setting, so that all my windows behave consistently and I'm not confused by per-window differences.
5. As a Moremaid user, I want every open directory window to update the moment I toggle the setting, so that I see the effect immediately without reopening folders.
6. As a Moremaid user, I want a View-menu checkbox for "Show Hidden Files", so that I can discover and toggle the feature without memorizing the shortcut.
7. As a Moremaid user, I want a matching toggle in Preferences, so that I can set my long-term default in the same place as my other view settings.
8. As a Moremaid user browsing with hidden files on, I want the Navigator sidebar to also show the hidden entries, so that the tree matches the main view.
9. As a Moremaid user, I want Quick Open to find hidden files when the toggle is on, so that I can jump to `.github/CONTRIBUTING.md` by name.
10. As a Moremaid user, I want Find in Files to search inside hidden files when the toggle is on, so that content searches are complete.
11. As a Moremaid user opening a ZIP archive, I want hidden entries inside it to follow the same toggle, so that archive browsing is consistent with folder browsing.
12. As a Moremaid user, I want the rendered directory-listing (auto-index) page to show hidden entries when the toggle is on, so that the listing matches the Navigator.
13. As a Moremaid user with the toggle on, I want newly-created hidden files to trigger the same auto-reload as visible files, so that the view stays current.
14. As a Moremaid user, I do NOT want `.git`, `node_modules`, or build directories to appear even with hidden files on, so that the browser isn't flooded with thousands of irrelevant entries.
15. As a Moremaid user, I want gitignored dot-directories (like `.derivedData/` or `.build/`) to stay hidden even with the toggle on, so that build junk doesn't clutter the browser.
16. As a Moremaid user who has never touched the setting, I want the default to be off, so that my experience is unchanged unless I opt in.
17. As a Moremaid user, I want the toggle to affect both hidden files and hidden directories, so that behavior matches Finder's ⇧⌘. semantics rather than an arbitrary directories-only rule.
18. As a Moremaid user, I want the View-menu checkbox to show a checkmark reflecting the current state, so that I can tell at a glance whether hidden files are shown.
19. As a Moremaid developer, I want the hidden-files behavior covered by an automated test, so that future refactors of the scanner don't silently regress it.

## Implementation Decisions

**Preference (already implemented).**
- A single app-wide preference, key `"showHiddenFiles"`, default `false`, stored via the existing
  decentralized `@AppStorage` boolean pattern (the same one `showBreadcrumb`, `showStatusBar`,
  `autoReload` use — no central settings object, no `Constants` entry). Any component that needs the
  value declares its own `@AppStorage("showHiddenFiles")` or reads
  `UserDefaults.standard.bool(forKey: "showHiddenFiles")`.
- A "Show hidden files" toggle already exists in Preferences → General.

**Scanner is the single chokepoint.** A census of every dot-entry filter site established that
`FileScanner` (`scan` / `scanBatched`) is the one place almost every file-listing surface funnels
through — the directory window, the Navigator/Sidebar tree, Quick Open, Find in Files, archive
browsing, and Mermaid validation all consume `FileScanner` output and carry no dot-filter of their
own. Threading the flag through `FileScanner` therefore lights up all of those surfaces at once.

- Add a `showHidden` boolean parameter to `FileScanner.scan` and `FileScanner.scanBatched`. When it
  is on, the scanner's directory enumeration must stop skipping hidden entries; when off, behavior
  is exactly as today.
- The directory window reads the app-wide preference and passes it into `scanBatched`. Other callers
  (content search, archive handler, Mermaid validation) pass the flag or accept a safe default of
  off; the scanner signature change must be reconciled at all existing call sites.

**Gitignore still wins.** "Show Hidden Files" lifts only the hidden-entry filter. The independent
gitignore layer (`GitignoreParser.isIgnored`) stays untouched in both the scanner and the auto-index
page. So with the toggle on, ordinary dot-entries appear but gitignored ones do not.

**Heavy dirs always excluded.** `.git`, `node_modules`, and build directories remain excluded at
every depth regardless of the toggle. Because the current code partly relied on the hidden-entry
skip to keep `.git` out, the explicit name-based exclusion must be robust on its own once the hidden
skip can be disabled — i.e. `.git` must be excluded by name at the root and at any nesting level,
not incidentally.

**Two independent sibling sites** filter dot-entries outside `FileScanner` and must each honor the
same preference so the app stays consistent:
- The **file-watcher** path filter, which gates live auto-reload — otherwise newly-added hidden
  files won't trigger a refresh, and its always-excluded set must match the scanner's.
- The **auto-index page** generator that renders a directory-listing HTML page — its own dot-prefix
  guard must respect the toggle while keeping its gitignore check.
The Navigator/Sidebar tree is explicitly **not** a separate site — it inherits `FileScanner`.

**Live propagation across windows.** Because the toggle is app-wide, flipping it (via ⇧⌘., the View
menu, or Preferences) must cause every open directory window to re-scan and redraw immediately. The
implementer chooses the mechanism — either observing the `@AppStorage` value directly or reusing the
existing app-wide `Notification.Name.settingsChanged` signal (posted by
`PreferencesView.notifySettingsChanged()`), which several windows already subscribe to for
theme/zoom changes. Whichever is chosen, all three toggle entry points must drive the same refresh.

**Shortcut and menu.** Bind **⇧⌘.** in the Commands DSL to flip `showHiddenFiles`, and add a
checkbox View-menu item (e.g. "Show Hidden Files", alongside the ⇧⌘T Navigator toggle) whose
checkmark reflects the current state. Confirm ⇧⌘. does not collide with an existing Moremaid command.

**"Hidden" definition.** Dot-prefixed **files and directories**, matching Finder's ⇧⌘. semantics —
not directories only.

## Testing Decisions

**What a good test looks like here:** assert external behavior — given a directory tree on disk and
a flag, the scanner returns the right set of entries — never internal mechanics like which enumerator
option was passed. Tests use **Swift Testing** (`@Test` / `#expect`, `@testable import Moremaid`),
matching the existing `Tests/MoremaidTests.swift`.

**Single seam: `FileScanner.scan`.** Confirmed with the developer as the one test seam. It is a pure
function of *(directory tree, filter, showHidden) → `[FileEntry]`*, so a test can build a temporary
fixture directory and assert the returned relative-path set.

Fixture should contain, at minimum: a plain file, a plain subdirectory with a file, a hidden dir
with a file (`.github/x.md`), a hidden file (`.env`), a `.git/` dir, a `node_modules/` dir, and a
gitignored dot-dir (`.build/`, with a `.gitignore` listing it). Assert:
- `showHidden == false` → only the plain file/dir appear (today's behavior; a regression guard).
- `showHidden == true` → the plain entries **plus** `.github/x.md` and `.env` appear; `.git/`,
  `node_modules/`, and the gitignored `.build/` do **not**.

**Prior art:** `defaultFilterIncludesMarkdownAndHTMLTest` (behavioral `FileFilter.matches` assertions)
and the `HeadingParser` / `SidebarHeadingNode.tree` tests (pure-function, fixture-in / expectation-out)
are the models to follow. There is no existing filesystem-fixture test, so this introduces a small
temp-directory setup/teardown helper.

**Out of test scope:** the file-watcher path filter and the auto-index page generator are verified by
the manual QA pass, not automated tests — they involve FSEvents timing and HTML-string assertions
with no prior art in the repo, and seaming them would add brittle new test surface for little gain.

## Out of Scope

- Per-window hidden-files state — the toggle is deliberately a single app-wide preference.
- Showing `.git`, `node_modules`, or build directories — permanently excluded regardless of the
  toggle.
- Overriding `.gitignore` — gitignored entries stay hidden even with the toggle on.
- A separate "show/hide `.gitignore`d files" control — not part of this feature.
- Any per-file-type or glob-based hidden rules beyond the dot-prefix convention.
- Automated tests for the file-watcher and auto-index sibling sites (manual QA instead).

## Further Notes

- The preference and its Preferences → General toggle are already implemented and building green;
  what remains is the scanner change, the sibling-site changes + live refresh, and the ⇧⌘. shortcut
  + View menu.
- Build and run only via `mise` tasks (`mise build`, `mise run`, `mise test`) per CLAUDE.md — never
  bare `xcodebuild`. After the shortcut/menu work, verify no Xcode-project regeneration is needed
  (`mise generate` only if `Project.swift` changes).
- Manual QA acceptance: open a folder containing `.github/`, `.vscode/`, a gitignored dot-dir, and
  `.git`; toggle ⇧⌘. and confirm dot-entries appear/disappear live across all open windows, that
  gitignored dirs and `.git`/`node_modules` never appear, and that a newly-created hidden file shows
  up via auto-reload when the toggle is on.
- The wayfinder map ([map.md](map.md)) tracks the remaining implementation tickets and records the
  decisions this spec synthesizes (census, preference, gitignore).
