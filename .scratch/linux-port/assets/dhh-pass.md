# Proposed answers to the eight grilling tickets — Omarchy idiom

> **Superseded in part, 2026-08-13.** All eight proposals were subsequently ruled on and the
> tickets resolved. Seven were accepted as written. **The language proposal below — Ruby — was
> overruled in favour of Rust** (`gtk4-rs` + `webkit6-rs`), which also changed the port map: the
> ripgrep libraries are usable in-process, so `FileScanner`, `GitignoreParser` and `ContentSearch`
> collapse into the `ignore` and `grep` crates rather than shelling out to a subprocess.
> **Where this document and a ticket's `## Answer` disagree, the ticket wins.** Kept as the record
> of how the positions were arrived at.

**Status: proposals, not resolutions.** No ticket is closed on the strength of this document.
Written 2026-08-13 as a first pass over tickets 04–11, answering each the way the Omarchy design
philosophy would push — plain text over ceremony, delete the knob rather than add the setting,
the system owns what the system owns, no build step, fast start. This is a reading of that
philosophy applied to Moremaid; it is not sourced from statements by its author.

Three of the eight rest on research tickets that have not run
([binding survey](../issues/01-binding-survey.md),
[Hyprland conventions](../issues/02-hyprland-conventions.md),
[WebKitGTK audit](../issues/03-webkitgtk-audit.md)). Those are flagged inline.

The through-line of the whole pass: **the Linux Moremaid is a smaller program than the macOS
one.** Not because features were cut for time, but because on this desktop the compositor, the
system theme, the package manager and the user's existing tools already do a third of what the
macOS app had to do itself. Every deletion below is that, not a compromise.

---

## 04 — Choose the implementation language

**Proposal: Ruby, with `ruby-gtk4`.** Hold this one loosely; it is the least defensible answer in
the document and the one most exposed to the binding survey.

The case for it is the Omarchy case: the whole app stays readable text on the user's disk, with no
build step between reading it and changing it. Omarchy itself is bash and config files for exactly
this reason. A user who wants Moremaid to render one thing differently opens the file and changes
it. That is a real feature on this desktop and it is worth a lot.

The case against is honest and serious:

- `ruby-gtk4` is a backwater compared to PyGObject or gtk4-rs. If the
  [binding survey](../issues/01-binding-survey.md) finds it can't register WebKitGTK 6 script
  message handlers or a custom URI scheme handler, the answer is dead on the spot — those two
  APIs are the entire JS↔native bridge.
- Ruby's cold start plus GTK plus WebKitGTK may not clear the "feels instant" bar. A markdown
  viewer that takes 1.5s to show a file has already failed.
- ~9k lines of a thinly-bound toolkit is a rough assignment for an agent working solo with no
  hardware to test on.

**Fallback order, stated now so the decision doesn't stall:** if `ruby-gtk4` fails the binding
audit → **Python + PyGObject** (same hackability, same no-build-step property, vastly better-trodden
GTK4/WebKitGTK bindings, and GNOME ships real apps on it). If cold start fails the feel test in
either → **Rust + gtk4-rs**, accepting the build step and losing the hackability, because instant
is non-negotiable and slow is not fixable later.

Swift-on-Linux: rule it in only if the survey says the GTK4 bindings are real. It would salvage
`FuzzyMatcher`, `ContentSearch`, `GitignoreParser`, `HeadingParser` and `MermaidValidator`
mechanically, which is the single largest code saving available — but a dead binding layer is not
worth 2k lines.

---

## 05 — How the Linux app obtains the rendering layer

**Proposal: reuse it verbatim, vendored, with no build step anywhere in the pipeline.**

- **(a) Reuse, don't reimplement.** The CSS and JS in `BaseCSS.swift`, `ThemeCSS.swift`,
  `TypographyCSS.swift`, `PageScripts.swift`, `MermaidConfig.swift` and `LanguageMaps.swift` is
  ~3k lines of working, debugged web code wearing a Swift costume. Extract it to plain
  `.css` / `.js` / `.html` files. The Linux app's rendering layer is then a template that
  interpolates a handful of values into a shipped HTML file — a few dozen lines, not a port.
- **(b) Vendor the web dependencies.** markdown-it, Prism.js and Mermaid.js get committed into
  `vendor/` as plain pinned `.js` files, served over a custom URI scheme. No CDN — a local
  markdown viewer that needs the network to render a heading is broken. No npm, no bundler, no
  `package.json`; the files are already distributable as-is and there is nothing to build.
  Pin exact versions in HANDOFF.md.
- **(c) One-time copy.** No submodule, no sync script. The new repo takes a snapshot and owns it.
- **(d) Divergence: nobody owns it, and that's deliberate.** The two apps drift. This was already
  fixed at charting when the separate-repo shape was chosen; pretending otherwise means building
  sync machinery for a two-person problem that doesn't exist.

**Constraint the destination imposes:** HANDOFF.md's reader has no access to this repo, so the
document must point at the public GitHub repo at a **pinned commit** and name the exact files to
lift, or carry them inline. Pointing at `main` is not good enough — it will have moved.

---

## 06 — Window, tab and session model

**Proposal: the compositor owns windows. The app owns none of it.**

- **One window per invocation. No in-app tabs.** `AdwTabView` would be reimplementing, badly, the
  thing Hyprland already does well — and doing it inside a single tile, where the user then has
  two competing systems for arranging documents. `moremaid a.md` and `moremaid b.md` gives two
  windows; Hyprland tiles them, groups them, moves them across workspaces. That is the feature.
- **No session restore.** `savedWindowSessions` is deleted, not ported. Restoring windows is the
  compositor's and the session manager's job on this desktop, and a tiling user's layout is not
  something an application should be guessing at on launch.
- **No "focus the existing window".** Wayland forbids self-raising, `xdg-activation` is a partial
  and awkward answer, and the honest behaviour is simply to open another window. If the user asked
  for the file again, give them the file.
- **Multi-process, not single-instance.** Each invocation is its own process. Simplest possible
  model, no IPC, no shared state, crashes are isolated. **The cost is real and should be stated in
  HANDOFF.md:** every window carries its own WebKitGTK, so ten open documents is ten web processes
  and a few hundred MB. If that proves intolerable in practice, single-instance with multiple
  toplevels is the retreat — but start simple and measure.
- **The Mermaid diagram window is a new toplevel**, not an in-app overlay. Same reasoning: hand it
  to the compositor and it tiles, floats, or goes fullscreen according to the user's own rules.

Rests on [Hyprland conventions](../issues/02-hyprland-conventions.md) for the decoration question —
whether the app draws a header bar at all, or goes bare and lets Hyprland draw the border.

---

## 07 — Theming

**Proposal: follow Omarchy. Ship zero themes. Delete the picker.**

This is the largest deletion in the port and the most important one for "feels native". Omarchy
rethemes the entire desktop at once — terminal, editor, bar, browser. An app that ignores that and
offers its own competing list of ten palettes is instantly, obviously foreign, no matter how good
the palettes are.

- **Derive the content palette from the system/GTK theme** rather than picking from a list. The
  rendered markdown takes its background, foreground, accent and surface colors from the active
  theme, so the WebKitGTK content and the GTK chrome are the same colors because they came from
  the same source — not because someone matched them by eye.
- **Live switching is mandatory, not a nicety.** The user rethemes their whole desktop in one
  command and every open Moremaid window must follow within the same second. Watch the theme
  signal, push the new palette into the page, re-render Mermaid with the new config.
- **Typography: one style, not six.** The six macOS styles assume SF and New York. Pick one good
  default — system UI font for chrome, a solid body face for prose, the user's monospace for code —
  and delete the picker. Anyone who wants Tufte-style margin notes can have the config file.
- **Prism follows too.** Generate the code-highlighting palette from the same source, or ship
  light/dark variants selected by the system's color-scheme. A third independent palette is how
  apps end up looking like a ransom note.

Consequence worth naming: **the ten themes and six typographies are the app's most-marketed
feature on macOS, and this deletes both.** That is the trade — on GNOME or KDE it would be a loss;
on a desktop built around system-wide theming it is the entire point.

Rests on [Hyprland conventions](../issues/02-hyprland-conventions.md) for the mechanism — exactly
how Omarchy signals a theme change and what an app reads to follow it.

---

## 08 — Keyboard and interaction map

**Proposal: Ctrl for the app, Super stays Hyprland's, vim keys throughout, no menu.**

| binding | action |
|---|---|
| `Ctrl+P` | Quick Open (fuzzy file finder) |
| `Ctrl+Shift+F` | Find in Files |
| `Ctrl+B` | toggle the Navigator sidebar (editor convention, not macOS's ⇧⌘T) |
| `Ctrl+N` | new window (new process, new tile) |
| `/` | focus search |
| `Tab` | switch search mode (filename ↔ content) |
| `j` / `k`, `gg` / `G`, `Ctrl+D` / `Ctrl+U` | navigate results and scroll the document |
| `Enter` | open · `Escape` | close overlay / clear search |
| `Ctrl+click` | open link in a new window |
| `Ctrl` `+` / `-` / `0` | zoom |
| `?` | shortcuts overlay |

- **Super is never bound.** It belongs to the compositor on this desktop and an app that takes it
  is broken by definition.
- **No menu bar and no hamburger menu.** There are perhaps eight things this app does. A menu is
  chrome for a program that has more surface than this one does.
- **Discoverability is `?`** — one overlay listing every binding, which is also the entire
  documentation. This is the thing that replaces the menu, so it has to be genuinely complete.
- **Vim keys are not optional here.** The audience lives in neovim; `j`/`k` scrolling a document is
  the baseline expectation, not a power-user affordance.

Rests on [Hyprland conventions](../issues/02-hyprland-conventions.md) to confirm no collisions with
Omarchy's shipped bindings.

---

## 09 — Config and state persistence

**Proposal: one hand-editable file. No GSettings.**

- **`$XDG_CONFIG_HOME/moremaid/config.toml`**, honouring the XDG fallback to `~/.config`. GSettings
  means a schema, schema compilation in the package, and a config the user cannot read with `cat` or
  keep in their dotfiles — three kinds of ceremony for zero benefit to this audience.
- **The config is a user-facing interface.** Ship a fully commented default file, document every key
  in the README, and treat key names as stable. Omarchy users will symlink this into a dotfiles repo
  on day one.
- **Keep it tiny.** After the theming decision there is almost nothing left to configure: font
  family and size overrides, maybe the monospace face, maybe a theme override for the person who
  genuinely wants to fight the system theme. `showBreadcrumb` and `showStatusBar` get deleted rather
  than made configurable — pick the right default and stand behind it.
- **State is not config.** Recents go to `$XDG_STATE_HOME/moremaid/recents`. `savedWindowSessions` is
  deleted outright (no session restore). Per-directory Navigator folder-expansion becomes ephemeral —
  in-session only, persisted nowhere. It is not worth a file.

Rests on [the language choice](../issues/04-choose-language.md) only for which TOML library; the
shape of the answer doesn't change either way.

---

## 10 — Packaging, distribution and desktop integration

**Proposal: AUR, and let pacman be the updater.**

- **`PKGBUILD` in the AUR**, two packages the usual way: `moremaid` from tagged releases and
  `moremaid-git` from `HEAD`. This is how software arrives on an Arch box; anything else is
  swimming upstream.
- **Terminal invocation is the primary entry point, not an afterthought.** `moremaid README.md`,
  `moremaid .` for a directory, `moremaid` with no argument for the current directory, and
  `cat notes.md | moremaid` for stdin. This audience opens files from a terminal far more often
  than from a file manager, so this path gets designed first and tested most.
- **Desktop integration is secondary but present:** `.desktop` entry, an icon in the hicolor theme,
  and a `text/markdown` MIME association so a file manager can hand files over.
- **Versioning:** git tags, AUR bumped on release. **Updates are `pacman`'s job** — no in-app update
  check, no version pinging, no notification. Sparkle's role on macOS simply has no counterpart here
  and shouldn't be invented.
- **HANDOFF.md must carry the exact `pacman` dependency list**, because that is literally the
  reader's first command and nothing works until it's right.

---

## 11 — Module-by-module port map

**Proposal.** The recurring verdict is *delete* or *shell out*, and both are the point.

| macOS | verdict | notes |
|---|---|---|
| `App/` lifecycle, `AppState` | **reimplement, much smaller** | `GtkApplication`, one window per process. Most of `AppState` evaporates with session restore. |
| `App/PreferencesView` | **delete** | Replaced by the config file. Nothing left to put in a preferences window once themes and typography are gone. |
| `App/PDFBatchExporter`, `CLIInstaller`, `CheckForUpdatesView` | **delete** | Out of scope; pacman handles updates. |
| `App/FilePicker` | **replace** | XDG file-chooser portal. |
| `FileBrowser/DirectoryWindowView`, `SingleFileView` | **reimplement** | The main window, two modes. |
| `FileBrowser/WebView` | **reimplement, small** | WebKitGTK wrapper. Message-handler bridge is the risk; see the audit. |
| Navigator: `SidebarView`, `SidebarTree` | **reimplement** | `GtkListView` + a list model to stay lazy over a large tree, mirroring the `LazyVStack` intent. |
| `FileBrowser/HeadingParser` | **port carefully** | Deliberately mirrors the JS slugify in `PageScripts.swift` so anchor IDs match. **Ship a shared fixture list of heading→slug pairs as a test in both places**, or this silently rots. |
| `FileBrowser/QuickOpenView`, `SearchInFilesView` | **reimplement** | Overlay/popover. |
| `FileBrowser/FileScanner` | **reimplement** | Background directory walk. Keep the `.git`/`node_modules` skips. |
| `FileBrowser/GitignoreParser` | **library if one exists, else port** | Gitignore semantics are fiddlier than they look; don't hand-roll if the language has a real one. |
| `FileBrowser/DiagramWindowController` | **reimplement as a toplevel** | Per the window-model decision. |
| `Rendering/*` | **reuse verbatim** | Vendored assets + a thin template. `ThemeCSS` collapses to a generated palette, `TypographyCSS` to one style, `MermaidConfig` derives from the palette. `LanguageMaps` ports as data. |
| `Search/ContentSearch` | **shell out to `ripgrep`** | It's on every Omarchy box, it's faster than anything hand-rolled, and it deletes a file. Parse `rg --json`. |
| `Search/FuzzyMatcher` | **port verbatim** | Pure logic, and in-process matching beats shelling out to `fzf` for a live-updating GUI list. |
| `FileWatcher/` | **reimplement** | `GFileMonitor` / inotify. **Drop the 1s content-hash polling** — inotify is reliable, polling was a macOS-era workaround. Watch open files and the visible tree only; a recursive watch on a large tree will exhaust inotify descriptors. |
| `Shared/Models` | **simplify** | `OpenTarget` largely collapses: no window de-duplication, no session restore, no `.empty` case. |
| `Shared/SearchHistory`, `Constants`, utilities | **port** | Trivial. |
| `Validation/MermaidValidator` | **port verbatim** | Self-contained. |
| `Archive/*` | **out of scope — and build no seam for it** | Read from the filesystem directly. When archives arrive, refactor then; a virtual-filesystem abstraction built now for a feature that isn't in v1 is pure speculative cost. |

**Net effect:** roughly a third of the macOS codebase is deleted rather than ported, another chunk
is replaced by `ripgrep` and the system theme, and the largest single asset — the rendering layer —
crosses over untouched.
