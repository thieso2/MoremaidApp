# Moremaid for Linux — implementation handoff

A complete specification for building **Moremaid**, a markdown reader with first-class Mermaid
diagram support, as a native GTK4 application for **Omarchy/Hyprland**.

This document carries every **decision**. It does not carry the **assets** — roughly 90 KB of CSS
and JavaScript plus the app icon, listed file by file in §4, fetched from a public GitHub repository
at a pinned commit. So the box needs network access once, and that is the only external dependency.

Everything else — stack, dependencies, module map, UI spec, packaging, build plan — is here.

**Every decision here has already been made and argued.** Where a choice looks arbitrary, §11 says
what it cost and what would reopen it. Where something is unverified, §12 says so — nothing in this
document was ever compiled, so treat §12 as your first day's work, not as trivia.

---

## 1. What Moremaid is

A **markdown reader**. You point it at a file or a directory and read. It is not an editor, not a
note-taking app, and not a wiki.

The macOS original exists and ships; this is a reimplementation, not a port of a codebase. The two
projects share a name, an icon and a purpose, and nothing else — separate repos, separate lineages,
free to diverge. You are not maintaining compatibility with anything.

### v1 feature inventory

Stated as observable behaviour, because you have never seen the macOS app and don't need to.

**Reading**
- Renders CommonMark markdown with GitHub-flavoured extensions (tables, task lists, strikethrough).
- Renders **Mermaid diagrams** in fenced ` ```mermaid ` blocks — flowcharts, sequence, class, state,
  ER, Gantt, pie, and the rest of Mermaid's grammar.
- Syntax-highlights fenced code blocks in 20+ languages.
- Any Mermaid diagram can be opened **full-size in its own window**.
- Renders non-markdown text files as syntax-highlighted code documents.
- **Live reload:** an open file that changes on disk re-renders automatically.

**Browsing**
- Open a directory and browse every markdown file in it, recursively, respecting `.gitignore` and
  skipping `.git`/`node_modules`.
- **Navigator** — a left sidebar listing folders, files, and the headings *inside* each file.
  Clicking a heading scrolls to it.
- Internal `.md` links navigate in-app. External links open the system browser.
- Breadcrumb showing where you are.

**Finding**
- **Quick Open** (`Ctrl+P`) — fuzzy filename finder over the whole tree, ranked, filtering as you
  type.
- **Find in Files** (`Ctrl+Shift+F`) — full-text search across every file, with context snippets and
  highlighted matches.

**Fitting in**
- Follows the active Omarchy theme — colours, live, without restarting.
- Opens from a terminal (`moremaid README.md`), from a file manager, or from stdin.
- Zoom, drag-and-drop, recent files.

---

## 2. Target environment

**Arch Linux + Hyprland + Omarchy. Nothing else.**

This is not a hedge — it licenses the whole document to be concrete. You may assume:

- **Wayland only.** No X11 fallback, no XWayland accommodation.
- **A tiling compositor owns window management.** The app does not tile, position, resize, restore,
  or raise itself, and must not try.
- **Omarchy's theme system exists** at the paths given in §6.3.
- **Rolling release.** Current versions at time of writing: GTK 4.22.4, libadwaita 1.9.3,
  webkitgtk-6.0 2.52.5.
- **Packaging is a `PKGBUILD`.** Not Flatpak, not deb, not AppImage.

GNOME and KDE polish are explicitly out of scope. "Feels native" here means *feels native on a
tiling Wayland compositor*, which is a materially different target from feeling native on GNOME —
most notably, it means **less** chrome, not more.

---

## 3. Stack

**Rust + gtk4-rs + libadwaita-rs + webkit6-rs.**

Rendering is a WebKitGTK view displaying HTML the app generates. This is how the macOS version works
and it is why the port is tractable: the entire rendering layer is web technology already and
crosses over untouched (§4).

### Why Rust

Cold start is non-negotiable for something invoked from a shell dozens of times a day, and a single
binary is the cleanest thing to hand a `PKGBUILD`. The cost is real: there is a build step, and the
app's own source is not user-editable. That is deliberately bought back in §4 — the web assets ship
as **data files on disk**, so a user can restyle their markdown rendering without a toolchain.

### Runtime dependencies

```bash
pacman -S gtk4 libadwaita webkitgtk-6.0 xdg-desktop-portal-gtk ttf-ia-writer
# build only:
pacman -S rust
```

Every one of those is load-bearing and none is decorative:

- **`xdg-desktop-portal-gtk`** — `xdg-desktop-portal-hyprland` does **not** implement a file
  chooser. Without this, "open a folder" silently fails.
- **`ttf-ia-writer`** — not a preference. See the Mermaid font trap in §6.4.
- **`webkitgtk-6.0`** is 130.8 MB installed with 71 dependencies, and is **not** in Omarchy's base
  package set. It is most of your install footprint. `webkit2gtk-4.1` is GTK **3** and is not an
  option.

### `Cargo.toml`

```toml
[dependencies]
gtk4           = { version = "0.11", features = ["v4_20"] }
libadwaita     = { version = "0.9",  features = ["v1_8"] }
webkit6        = "0.6"

ignore         = "0.4"    # ripgrep's walker: directory scan + gitignore
grep-searcher  = "0.1"    # in-process content search
grep-regex     = "0.1"
grep-matcher   = "0.1"    # match spans, for highlighting
nucleo-matcher = "0.3"    # fuzzy matching for Quick Open

notify                = "8"
notify-debouncer-full = "0.7"

serde = { version = "1", features = ["derive"] }
toml  = "1"

open          = "5"
async-channel = "2"
```

`gio` and `glib` arrive re-exported through `gtk4::gio` / `gtk4::glib` — do not add them as
dependencies.

**`libadwaita` needs `v1_8`** for `AdwShortcutsDialog` (§6.5); `GtkShortcutsWindow` is deprecated
since GTK 4.18. It also carries `v1_6`'s `accent_color()` API — which **compiles and returns
nothing useful on this desktop**, because Omarchy publishes no accent colour. Keep the feature, do
not build theming on it (§6.3).

### No async runtime

GTK owns the main loop. Do not add tokio.

- `glib::spawn_future_local` for anything touching widgets.
- `gio::spawn_blocking` for the directory walk and the content search.
- `async-channel` to stream results back — which also gives Quick Open and Find in Files their
  incremental "results appear as they're found" behaviour for free.

---

## 4. The rendering layer — reuse it verbatim

**This is the single largest asset available to you, and you should not write it.**

The macOS app's rendering layer is ~3,000 lines of working, debugged CSS and JavaScript that happens
to live inside Swift string constants. Extract it to plain files and use it as-is. Your Rust
rendering code is then: read a template, substitute a handful of values, call `load_html`. A few
dozen lines, not a port.

### Where to get it

Repository: **`https://github.com/thieso2/MoremaidApp`**
Pinned commit: **`a3ab7fd86262c14fb621f7409c961ab816d4c527`**

Do not use `main` — it will have moved.

| file | bytes | what it holds |
|---|---|---|
| `Sources/Rendering/BaseCSS.swift` | 12,679 | the document stylesheet |
| `Sources/Rendering/PageScripts.swift` | 27,869 | all client-side JS — heading extraction, copy buttons, link handling, Mermaid init, live re-render |
| `Sources/Rendering/HTMLGenerator.swift` | 14,464 | the HTML skeleton and assembly |
| `Sources/Rendering/LanguageMaps.swift` | 7,688 | extension → Prism language, pure data |
| `Sources/Rendering/MermaidConfig.swift` | 4,900 | Mermaid initialisation config |
| `Sources/Rendering/ThemeCSS.swift` | 6,165 | 10 colour themes — **mostly deleted**, see §6.3 |
| `Sources/Rendering/TypographyCSS.swift` | 4,615 | 6 typography styles — **deleted**, see §6.4 |
| `Sources/FileBrowser/HeadingParser.swift` | 11,035 | reference implementation for §7's slug rules |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png` | — | **the app icon.** Also 512/256/128/64/32/16 px variants in the same directory. Convert to the hicolor layout (§10); there is no other source for it |

Each is a Swift file wrapping raw CSS/JS in `"""` string literals. Strip the Swift and keep the
contents.

### Vendored web dependencies

markdown-it, Prism.js and Mermaid.js are currently loaded **from a CDN**. Do not carry that over — a
local markdown viewer that needs the network to render a heading is broken.

Commit all of it into `vendor/` as plain files, served over the custom URI scheme (§5). **No npm, no
bundler, no `package.json`.** The files are distributable as shipped and there is nothing to build.

What the macOS app currently pulls, and what to pin it to:

| library | macOS uses | pin to |
|---|---|---|
| Prism.js | `1.29.0` | `1.29.0` — a real pin, carry it over |
| Mermaid | `@10` — a **floating major**, resolves to latest 10.x | choose an exact `10.x.y` and record it. Mermaid 11 exists; do **not** silently jump — the config schema changed |
| markdown-it | **completely unpinned** (`npm/markdown-it`, no version at all) | pick the current release, pin it exactly, write the number down |

Two of the three are not actually pinned today. That is a latent bug on macOS — a CDN roll can
change rendering without a commit — and vendoring is what fixes it. **Whatever versions you choose,
record them in this file**, because nothing else will remember.

> **The Prism autoloader is a runtime network dependency, not just a build-time one.**
> `HTMLGenerator.swift:36` sets
> `Prism.plugins.autoloader.languages_path = 'https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/'`
> — Prism fetches each language grammar **lazily, at render time**, the first time it meets that
> language. Vendoring `prism.min.js` alone leaves an app that silently fails to highlight anything
> unusual when offline.
>
> Vendor **`components/` in full** (~200 small files, a few hundred KB total) alongside the core,
> and repoint `languages_path` at the custom scheme. Also vendor the theme CSS the app references
> (`themes/prism-tomorrow.min.css` and any other named in `HTMLGenerator`) — though §6.3 replaces
> most theme colour with derived custom properties, so check what is still actually needed before
> copying all of them.

### Where the assets live at runtime

```
/usr/share/moremaid/web/          # installed by the package
$XDG_DATA_HOME/moremaid/web/      # takes precedence if present
```

**Not `include_str!`.** This is the deliberate counterweight to choosing a compiled language: a user
can restyle their rendering, swap the Mermaid config, or add a Prism language without a toolchain.
It costs nothing and it is the difference between a Rust binary and a Rust black box.

### Required edits to the extracted assets

These will not happen by themselves:

1. **Delete `TypographyCSS` entirely** and all six styles' font stacks (§6.4).
2. **Strip every macOS font reference.** `-apple-system`, `BlinkMacSystemFont`, `Segoe UI`,
   `SFMono-Regular`, `Monaco`, `Menlo`, `et-book`, `charter`, `Latin Modern`, `Palatino`,
   `Lucida Grande` are all dead on Linux. Note `BaseCSS.swift:86` **and** an easily-missed inline
   stack at `HTMLGenerator.swift:80` on the auto-index page.
3. **Replace `ThemeCSS`'s 10 themes** with CSS custom properties fed from §6.3.
4. **Point every asset URL at the custom scheme** rather than a CDN or `file://`.
5. **Fix the Mermaid diagram cache** (§9.2) — it currently re-renders every diagram on every
   live-reload tick.

### Divergence

Nobody owns it. The two codebases drift, by design. If the macOS side later fixes a rendering bug
worth having, someone copies the file across by hand. That is the entire process.

---

## 5. The WebKitGTK bridge

### Use a custom URI scheme, not `file://`

**The highest-leverage decision in the port.** `load_html`'s documentation is explicit: absolute
local paths outside `base_uri` **terminate the web process**. So an `![](/abs/path.png)` or
`![](../sibling/x.png)` in someone's markdown is a *crash*, not a broken image.

Register a scheme via `WebContext::register_uri_scheme` and serve documents, images and vendored
assets through it. This fixes three problems at once:

1. Local image references stop killing the web process.
2. Vendored JS/CSS load offline.
3. `navigator.clipboard` is **secure-context gated** and `file://` is not secure — the copy buttons
   would silently fail. Mark the scheme secure with
   `SecurityManager::register_uri_scheme_as_secure`, or copy natively over a message handler
   instead.

It also sidesteps the now-mandatory bubblewrap sandbox.

### JS ↔ Rust

The JS side is **byte-identical** to macOS —
`window.webkit.messageHandlers.<name>.postMessage({type, …})` is the documented WebKit 6.0 API, so
`PageScripts` is ~95% portable verbatim. Message types: `linkClick`, `headings`, `loadComplete`,
`externalLink`.

Host side:

```rust
UserContentManager::register_script_message_handler(name, world_name)  // note: world_name is new
UserContentManager::connect_script_message_received(detail, |_, value| …)  // hands you a JSCValue
WebViewExt::evaluate_javascript(…)          // Rust → JS
WebViewExt::call_async_javascript_function(…)
WebViewExt::connect_decide_policy(…)        // link interception
WebViewExt::set_zoom_level(f64)
```

`WebKitJavascriptResult` no longer exists; the signal delivers a `JSCValue` directly.

### Link handling

Read `NavigationAction::modifiers()` and `mouse_button()` in `decide-policy`.

- Internal `.md` → navigate in-app.
- External → hand to the system browser.
- **`Ctrl+click`, middle-click and `Shift+click`** open a new window. Middle-click is a *gain* over
  macOS, which has no equivalent.

**Rust wart that compiles and silently misbehaves:** `modifiers()` returns a bare `u32`, not a typed
`gdk::ModifierType`. Compare against `CONTROL_MASK.bits()`.

### Two macOS hacks to delete rather than port

- The `linkHover` user script and `currentHoveredLink` state — replaced by `mouse-target-changed`
  plus `HitTestResult::link_uri()`, which gives it directly.
- A 40-line console monkeypatch — replaced by the `enable-write-console-messages-to-stdout` setting.

### Keep the JS find-in-page

`WebKitFindController` reports match totals but never a current-match index, so it cannot drive the
existing "3 of 17" UI. Keep the JavaScript implementation.

### Do not use `prefers-color-scheme`

WebKitGTK deliberately forces light (WebKit bug 197947). Costs nothing — the app sets its own
`data-theme` — but drive dark mode from `AdwStyleManager`, never the media query.

---

## 6. UI specification

### 6.1 Windows: the compositor owns everything

- **One window per invocation. No in-app tabs.** Hyprland has native window grouping (`Super+G`, a
  themed groupbar, `Super+Alt+Tab` to cycle). That *is* the tab feature, already built and already
  themed to match the user's desktop.
- **No session restore.** Not merely unwanted — impossible. A Wayland client cannot set its
  position, and Omarchy ships `suppress_event = "maximize"` so it cannot set its size either.
- **Multi-process.** Each invocation is its own process: no IPC, no shared state, crashes isolated.

> **The trap that will bite you first.** `GApplication` is **single-instance by default**. Without
> `gio::ApplicationFlags::NON_UNIQUE`, a second `moremaid b.md` forwards its arguments to the first
> process over D-Bus and exits — silently, with no error. Set the flag.

Cost: one WebKitGTK per window, so ten documents is ten web processes and a few hundred MB. This is
accepted, and §9.1 gives you the number at which to reconsider.

**The Mermaid diagram window** is a second toplevel. Under a tiler it will *tile* — splitting your
reading window in half, the opposite of the macOS full-screen behaviour — and the app cannot
maximize itself. Give it a distinct app-id and ship a documented float rule in the README, the way
Omarchy floats its own dialogs.

### 6.2 Chrome: go bare

**A plain `GtkApplicationWindow` with no header bar.**

Hyprland answers *server-side* to both decoration protocols, and GTK4 honours that via
`gdk_wayland_display_prefers_ssd()`, suppressing its fallback titlebar. A bare window is already
correct with zero code.

An `AdwHeaderBar` would add ~47 px of chrome for content that no longer exists — §6.3 deleted
preferences and §6.5 deleted the menu.

**Caveat:** `AdwApplicationWindow` forces a `.csd` class regardless of compositor preference,
bringing Adwaita rounded corners and a shadow margin into a `rounding = 0`, square-2px-border
desktop. Prefer `GtkApplicationWindow`. If a libadwaita dialog forces `AdwApplicationWindow`,
override the `.csd` styling. **This is the number one thing to check on hardware.**

### 6.3 Theming: follow Omarchy, ship zero themes

The macOS app ships 10 colour themes and a picker. **Delete both.** Omarchy rethemes an entire
desktop at once, and an app offering its own competing palette list is the single most obvious way
to look foreign there.

**Do not use `AdwStyleManager` for the palette.** On Omarchy it yields exactly one bit — light or
dark. Tokyo Night, Gruvbox and Nord are indistinguishable through it, because
`xdg-desktop-portal-gtk` publishes only `color-scheme` and `contrast`, and Omarchy sets no accent.

**The palette is a file:**

```
~/.local/state/omarchy/current/theme/colors.toml     # note: .local/state, not .config
~/.config/omarchy/current/theme/colors.toml          # legacy path, try as fallback
```

Flat TOML, present in all 22 shipped themes and backfilled from `alacritty.toml` for user themes:

```toml
mode = "dark"
accent = "#7aa2f7"      selection = "#292e42"     muted = "#414868"
background = "#1a1b26"  dark_background = "#13141c"
darker_background = "#0e0e14"  lighter_background = "#24283b"
foreground = "#a9b1d6"  dark_foreground = "#565f89"
light_foreground = "#b4bee6"   bright_foreground = "#c0caf5"
red = "#f7768e"  yellow = "#e0af68"  orange = "#eb927b"  green = "#9ece6a"
cyan = "#449dab" blue = "#7aa2f7"    magenta = "#ad8ee6" brown = "#75493d"
bright_red = "#ff7a93"  bright_yellow = "#ff9e64"  bright_green = "#b9f27c"
bright_cyan = "#0db9d7" bright_blue = "#7da6ff"    bright_magenta = "#bb9af7"
```

**Read it synchronously, before the first `load_html`**, and interpolate the derived custom
properties into the initial HTML. It is ~1 KB; the parse is well under a millisecond, on a path
already doing blocking file I/O. There is then **never** a flash of the wrong colours — which
matters more here than usual, because one process per window means the user sees first paint every
single time.

**Role contract:**

| role | source key |
|---|---|
| page background | `background` |
| raised surface (code blocks, tables) | `lighter_background` in dark mode, `darker_background` in light |
| body text | `foreground` |
| headings | `bright_foreground` |
| muted text, rules, borders | `muted`, `dark_foreground` |
| links, focus ring, active state | `accent` |
| selection | `selection` |
| blockquote edge | `accent` at reduced alpha |

Prism maps onto the ANSI set — `comment` → `dark_foreground`, `keyword` → `magenta`, `string` →
`green`, `number` → `orange`, `function` → `blue`, `class-name` → `yellow`, `constant`/`builtin` →
`cyan`, `operator` → `foreground`, `deleted` → `red`, `inserted` → `green`, `bright_*` for emphasis.
Mermaid's config derives from the same roles, so prose, code and diagrams are one palette rather
than three.

**Detecting a change.** Light↔dark arrives free via `StyleManager::connect_dark_notify`. **A
same-mode switch — Tokyo Night → Nord — signals nothing at all**, and most of the 22 themes share a
mode, so this is the common case. Catch it with an inotify watch on
`~/.local/state/omarchy/current/` — **the parent directory**, because the theme dir is replaced by
`rm -rf` + `mv` and a watch on the file's inode goes stale immediately. Debounce it.

**On change: re-derive and push through `evaluate_javascript`, updating `:root` custom properties
in place, then re-init Mermaid so diagrams recolour. Never reload the page** — that would throw away
scroll position, and rethemeing is exactly when the user is mid-document.

Omarchy's sanctioned `~/.config/omarchy/hooks/theme-set.d/` hook is a lower-latency alternative;
**document it in the README, do not ship it** — a package must not write to `$HOME`, and the watch
works from first launch with no setup.

**Off Omarchy** (plain Arch + Hyprland, no `colors.toml`): fall back to one built-in palette, light
and dark, chosen by the `StyleManager` bit. Missing individual keys fall back per-key. **Never fail
to render over a colour.**

> Note for your own sanity: **GTK chrome cannot follow a same-mode theme change** — Omarchy's entire
> GTK theming is `gtk-theme = Adwaita/Adwaita-dark` plus `color-scheme`, and dynamic GTK theming
> was requested and closed unimplemented (basecamp/omarchy#2789). Any chrome/content mismatch after
> a theme switch is an Omarchy gap, not your bug. It is also a third independent argument for §6.2's
> bare window: the less chrome there is, the less there is to be out of step.

**The opportunity worth understanding:** because stock libadwaita apps get only a light/dark bit, an
app that reads `colors.toml` and tints itself will look *more* at home on Omarchy than most GTK
applications there. This is the one place the Linux version is better than the macOS original.

### 6.4 Fonts

| role | value |
|---|---|
| body + headings | `"iA Writer Quattro S", "Noto Sans", sans-serif` |
| code | `monospace` — **bare, unquoted, no named families** |
| Mermaid | **an explicit named family — never a generic** |
| GTK chrome | the body face, via a CSS provider |

**Code is the free win.** Omarchy's font setting is a fontconfig `prepend_first` on the `monospace`
alias, so bare `font-family: monospace` resolves to whatever the user chose with `omarchy font`. It
is the one place that desktop expresses a preference, and honouring it costs one word.

> **The Mermaid font trap.** WebKitGTK's SVG renderer can fail to resolve generic font families when
> expected system fonts are absent — and since Mermaid defaults to generics for *all* text, **every
> label in every diagram silently disappears**. Boxes render, labels don't, nothing errors
> ([warp#9402](https://github.com/warpdotdev/warp/issues/9402)). Set an explicit `fontFamily` in
> `mermaid.initialize()`. **This is why `ttf-ia-writer` is a hard `depends`, not `optdepends`** —
> do not "tidy" it later.

Omarchy expresses **no opinion on body text at all** (it never touches `font-name` or
`document-font-name`), so the prose face is an unforced choice; iA Writer Quattro is a genuine
reading typeface that ships on a stock box.

**Text scaling:** `omarchy display text size` drives `text-scaling-factor`. GTK chrome honours it
automatically; **WebKit content does not**. Set

```
effective content zoom = app zoom × text-scaling-factor
```

so the sidebar and document stay in proportion, and watch the gsettings key for live changes.
`Ctrl+0` resets the app's own factor to 1.0 while still respecting the system scale.

### 6.5 Keyboard and discoverability

**`Ctrl` for the app. `Super` is the compositor's and must never be bound.**

| binding | action |
|---|---|
| `Ctrl+P` | Quick Open |
| `Ctrl+Shift+F` | Find in Files |
| `Ctrl+B` | toggle Navigator |
| `Ctrl+N` | new window |
| `Ctrl+Shift+R` | force full render of a large document (§8) |
| `/` | focus search |
| `Tab` | switch search mode (filename ↔ content) |
| `j` / `k`, `gg` / `G`, `Ctrl+D` / `Ctrl+U` | navigate and scroll |
| `Enter` / `Escape` | open / dismiss |
| `Ctrl+click`, middle-click | open link in new window |
| `Ctrl` `+` / `-` / `0` | zoom |
| `?` | shortcuts overlay |

The entire plain-`Ctrl` and `Ctrl+Shift` space is unclaimed by Omarchy — it binds no plain-Ctrl
chord at all, only `Ctrl+Alt+Delete` and `Ctrl+Alt+Tab`. Bare `/ ? j k g Enter Escape Tab` are free.

**Three hard reservations:**

- **`Ctrl+C` / `Ctrl+V` / `Ctrl+X` are clipboard, untouchable.** Omarchy's `Super+C/V/X` universal
  clipboard *synthesises* them into the focused window; rebinding `Ctrl+C` breaks a desktop-wide
  gesture inside your app.
- **`Alt+Tab`** is the compositor's.
- **`Super`**, in every combination.

**Vim keys are baseline, not a power-user affordance.** This audience lives in neovim.

**No menu bar and no hamburger menu.** The app does about eight things; a menu is chrome for a
larger program, and on a tiling desktop it is vertical space spent on nothing.

**`?` is therefore the entire discoverability story** — use **`AdwShortcutsDialog`** (libadwaita
1.8+; `GtkShortcutsWindow` is deprecated since GTK 4.18). Because it replaces the menu, it must be
genuinely complete, and it ships in **Milestone 3 alongside the first shortcuts** — never after
them.

### 6.6 The Navigator

A left sidebar showing folders, files, and headings within files. Use `GtkListView` with a list
model so it stays lazy over a large tree — the macOS version uses a flat row list behind a lazy
container for exactly this reason, and this is the fiddliest UI in the project.

Folder expansion state is **ephemeral**, in-session only, persisted nowhere.

---

## 7. Module-by-module port map

The recurring verdict is *delete* or *use a crate*. Choosing Rust made this table shorter, not
longer: the ripgrep libraries are usable in-process, so three hand-written components vanish into
dependencies.

| macOS component | verdict | notes |
|---|---|---|
| App lifecycle, `AppState` | **reimplement, much smaller** | `GtkApplication` with `NON_UNIQUE`. Most of `AppState` evaporates with session restore. |
| `PreferencesView` | **delete** | Replaced by `config.toml`. After §6.3 and §6.4 there is nothing left to put in a preferences window. |
| `PDFBatchExporter`, `CLIInstaller`, `CheckForUpdatesView` | **delete** | Out of scope; pacman updates. |
| `FilePicker` | **replace** | GTK4 `FileDialog` → XDG portal automatically. |
| `DirectoryWindowView`, `SingleFileView` | **reimplement** | One window, two modes. |
| `WebView` wrapper | **reimplement, small** | §5. The highest-risk piece. |
| Navigator (`SidebarView`, `SidebarTree`) | **reimplement** | §6.6. |
| `HeadingParser` | **port by hand, with a shared fixture** | Mirrors the JS slugify so anchor ids match — see §9.3. |
| `QuickOpenView`, `SearchInFilesView` | **reimplement** | Overlays. |
| `FileScanner` | **delete → `ignore` crate** | Parallel, gitignore-aware. **Set `require_git(false)`** — it defaults true and will otherwise ignore `.gitignore` outside a git repo. |
| `GitignoreParser` | **delete → `ignore` crate** | Same crate. Gitignore semantics are fiddlier than they look. |
| `ContentSearch` | **delete → `grep-*` crates** | `grep-searcher` + `grep-regex` + `grep-matcher` (the last for match spans, needed for highlighting). Same engine as ripgrep, in-process, no subprocess. |
| `FuzzyMatcher` | **delete → `nucleo-matcher`** | See §12 for its maintenance caveat and the free exit. |
| `FileWatcher` | **reimplement → `notify`** | **Drop the 1-second content-hash polling.** See §9.4. |
| `DiagramWindowController` | **reimplement as a toplevel** | §6.1. |
| `Rendering/*` | **reuse verbatim** | §4. |
| `Models` (`OpenTarget` etc.) | **simplify hard** | No window de-duplication, no session restore, no `.empty` case. |
| `SearchHistory`, `Constants`, utilities | **port** | Trivial. |
| `MermaidValidator` | **port by hand** | Self-contained; §8 surfaces its output. |
| `Archive/*` (ZIP, AES) | **out of scope — and build no seam for it** | Read from the filesystem directly. A virtual-filesystem abstraction built now for a feature not in v1 is speculative cost with no payer. |

**Net:** roughly a third deleted rather than ported, four components replaced by two crate families,
and the rendering layer crossing over untouched. The genuinely new work is the GTK shell, the
WebKitGTK bridge, and the lazy sidebar.

---

## 8. Behaviour at the edges

The macOS app has **no size guard and no binary detection**. Both are closed here. Decide these on
purpose rather than discovering them as bugs.

**File types**

| input | behaviour |
|---|---|
| `.md`, `.markdown` | markdown |
| any other **text** file | Prism code document; language from extension, plain when unknown |
| **binary** | refuse with a friendly message naming file and size |

Binary detection is a NUL byte in the first 8 KB — the heuristic `grep-searcher` already uses.

**Large documents.** Above **5 MB** *or* **50 Mermaid diagrams**, render plain (no Mermaid, no
Prism) with a banner and `Ctrl+Shift+R` to insist. **The diagram count is the real trigger** —
Mermaid's cost scales ~3–5× per +20 nodes, so a 200 KB file with 200 diagrams is far more dangerous
than a 20 MB file with none. Forcing a render populates the diagram cache normally.

**Malformed Mermaid.** Replace the diagram in place with a styled error block carrying
`MermaidValidator`'s message and line number, source shown beneath. You are usually the author of
the file you are reading, and the app already computes this and currently throws it away.

**The file changes underneath you.** Deleted or replaced by a directory → **keep the last good
render on screen** behind a dismissible banner; reload and clear it if the path returns. The usual
cause is a branch switch, not a deletion. Truncated or mid-write → absorbed by the debounced watch.

**Terminal invocation behaves like a Unix tool**, because that is the primary entry point:

- Path doesn't exist, or permission denied → **stderr, exit 1, no window**. Opening a window to
  report a typo is wrong when the user is in a shell.
- Permission denied mid-scan → skip that subtree, carry on.
- Directory where a file was expected, or vice versa → both are valid; open what it is.
- Broken symlink → treated as missing. Symlink loops cannot arise: `ignore` does not follow symlinks
  by default, and that default stands.

**Empty states get a message, never a blank window.** Empty directory → empty-state text. Empty file
→ renders as an empty document; that is not an error.

**stdin** (`cat notes.md | moremaid`) → base path is the **current working directory**, so relative
links and images resolve from where the command ran. Titled `(stdin)`. **No live reload** — there is
nothing to watch. Say so in the docs.

**A shared banner component** serves the large-file and missing-file cases. It never blocks content.

---

## 9. Performance and correctness targets

### 9.1 Numbers

Targets to verify, not measured facts — nothing in this document was ever compiled.

| what | target |
|---|---|
| **Cold start → painted document** | **≤300 ms** |
| 50-line vs 5000-line document | delta ≤100 ms |
| Directory scan, 10k files | first rows ≤100 ms, complete ≤1 s |
| Quick Open keystroke → filtered list | ≤16 ms at 10k entries |
| Find in Files, 10k files | first match ≤200 ms, streamed |
| Mermaid, 100-node diagram | ≤1 s |
| Memory per window | measure; **>400 MB is the red line** |

**≤300 ms is load-bearing.** Rust was chosen over more hackable languages precisely because cold
start is non-negotiable. If WebKitGTK's process spawn makes it structurally unreachable, that
**reopens §6.1's one-process-per-window model** in favour of single-instance with a pre-warmed web
process — it is not a number to quietly relax. Same for the memory red line.

### 9.2 Fix the Mermaid cache — do not inherit it

The macOS app renders diagrams in a sequential `await` loop and **re-renders every diagram on every
live-reload tick**. This is already its worst performance characteristic, and WebKitGTK is expected
to be slower at it.

**Hash each diagram's source. On reload, re-render only diagrams whose source changed; reuse cached
SVG for the rest.** The common case — editing prose in a document full of diagrams — goes from
"re-render all of them" to "re-render none of them".

This is also a better test than a latency number, because it is binary: **a prose-only edit
re-renders zero diagrams, or the cache is broken.**

### 9.3 The slug coupling

`HeadingParser` (Rust, for the Navigator, which shows headings for files not loaded in any webview)
and the slugify in `PageScripts` (JS, which assigns the actual anchor ids) **must produce identical
slugs** or in-document links break for exactly the headings nobody tested.

**One shared fixture, run by both sides.** `tests/fixtures/slugs.json` holds heading→slug pairs
including the nasty cases — punctuation, emoji, duplicates needing `-1` suffixes, non-ASCII, inline
code, links inside headings. A Rust test runs it; a small JS test runs the same file through the
*shipped* slugify under node.

Node here is a **test-only dependency** — nothing is compiled, bundled or npm-installed, so §4's
no-build-step rule survives intact.

*(Making Rust the sole slugifier was considered and rejected: it removes the duplicated algorithm
but replaces it with a worse, untested coupling — Rust and markdown-it would then have to agree on
which lines are headings at all, and a `#` inside a fenced code block misaligns every anchor after
it.)*

### 9.4 The file-watching trap

**inotify watches the inode.** Editors save atomically — write a temp file, rename over the target —
so **a watch on the file itself goes permanently deaf after the first save**. Every neovim save
looks exactly like this, so on this desktop it is the normal path, not an edge case.

- Watch the **containing directory**; filter events by filename.
- One save emits 3–5 inotify events, so `notify-debouncer-full` is required, not optional.
- Watch open files and the visible tree only. A recursive watch over a `node_modules`-shaped tree
  will exhaust `max_user_watches`.
- The macOS 1-second content-hash poll is dropped — but note *why* it worked: polling was immune to
  this. Switching to inotify is only a win if the rename case is handled deliberately.

The same trap applies to the theme directory in §6.3, for the same reason.

### 9.5 Four binary "feels native" properties

No measurement needed — each is true or false:

1. **No flash of wrong colours, ever.** Structural: §6.3's palette read is synchronous.
2. **No flash of unstyled content.** All CSS is inline in the document handed to `load_html`.
3. **A theme switch does not relayout or jump.** Custom properties update in place; never reload.
4. **No splash screen, no progress window, no empty window waiting for content.** If the document
   isn't ready, the window isn't mapped.

### 9.6 Tests

- **Unit tests on the pure logic** — slugs, fuzzy ranking, config parsing, palette derivation and
  per-key fallback, Mermaid validation, walk/ignore behaviour.
- **Golden snapshots of the generated HTML** against committed `.html` fixtures. Catches a dropped
  CSS variable or a mangled asset path with no GUI and no compositor.
- **No CI.** Tests run locally.

Because nothing forces the suite to run, two things must be written down: the README names **both**
`cargo test` *and* `node tests/slugs.test.js` (the JS half won't run under `cargo test` and is the
half that gets forgotten), and the **release checklist runs both**, since a tag is the last moment
anyone will think about it.

---

## 10. Config, state and packaging

### Config — one hand-editable file

`$XDG_CONFIG_HOME/moremaid/config.toml` (falling back to `~/.config`), parsed with `serde` + `toml`.
**No GSettings** — that means a schema, schema compilation in the package, and a config the user
cannot `cat` or keep in dotfiles.

**This file is a user-facing interface**, and after choosing a compiled language it is the main one.
Ship a fully commented default, document every key, treat key names as stable. People will symlink
it on day one.

```toml
[font]
body = "iA Writer Quattro S"
mono = "monospace"          # bare generic = follow the Omarchy font
size = 16                   # base px, before text-scaling-factor
```

Keep it tiny. `showBreadcrumb`/`showStatusBar` are **deleted rather than made configurable** — pick
the right default and stand behind it. (Note: the `toml` crate cannot *emit* comments, so ship the
commented default as a static file rather than generating it.)

### State is not config

- Recents → `$XDG_STATE_HOME/moremaid/recents`
- Window sessions → **deleted entirely** (§6.1)
- Navigator folder expansion → **ephemeral**, persisted nowhere

### Packaging

**AUR, and pacman is the updater.** Two packages in the usual way: `moremaid` from tagged releases,
`moremaid-git` from `HEAD`.

```bash
depends=('gtk4' 'libadwaita' 'webkitgtk-6.0' 'xdg-desktop-portal-gtk' 'ttf-ia-writer')
makedepends=('rust')
# build:   cargo build --release
# install: /usr/bin/moremaid
#          /usr/share/moremaid/web/
#          the .desktop entry, and the icon into hicolor
```

**Terminal invocation is the primary entry point and gets designed first**: `moremaid README.md`,
`moremaid .`, bare `moremaid` for the current directory, `cat notes.md | moremaid`. This audience
opens files from a shell far more often than from a file manager.

**Desktop integration is secondary but present:** `.desktop` entry, hicolor icon, and a
`text/markdown` association that **offers** itself without grabbing the default — Omarchy already
ships Omawrite (`Super+Shift+W`) and Obsidian, and stealing the association would be rude.

**No in-app updates.** Sparkle's role on macOS has no counterpart here and inventing one would be
unwelcome on this distribution. Cut releases from git tags; bump the AUR package.

**Ship two documented Hyprland rules in the README**, don't apply them yourself:

- a float rule for the Mermaid diagram window (§6.1)
- an opacity opt-out (`tag = "-default-opacity"`) — every Omarchy window is `opacity 0.985 0.96` by
  default, and text over a translucent background is not what a reader wants. `imv` and `mpv` do
  the same.

**There is no tray, no background residency, no autostart.** GTK4 has no tray API at all.

---

## 11. Explicitly out of scope

Do not helpfully build these. Each was ruled out deliberately:

- **`.moremaid` archives** — the ZIP virtual filesystem, AES-256 encryption, in-memory browsing of
  encrypted archives. **And build no seam for it** (§7).
- **The `mm` CLI** — beyond the app binary accepting a path argument, which is in scope.
- **File-manager preview integration** — no Nautilus thumbnailer, no GNOME Sushi equivalent of the
  macOS QuickLook extension.
- **Activity feed** — real-time file-change tracking UI.
- **PDF export**, single or batch.
- **Source editor view.** This is a reader.
- **In-app auto-update.**
- **GNOME, KDE, XFCE polish; X11; Flatpak, deb, AppImage.**
- **Any shared or cross-platform codebase with the macOS app.**

---

## 12. Known unknowns — your first day

Nothing here was ever compiled. These are the things to verify before building on them, roughly in
order of what they would cost you.

1. **Does `AdwApplicationWindow`'s forced `.csd` class show rounded corners and a shadow margin
   against Hyprland's square 2 px border?** Decides bare `GtkApplicationWindow` vs Adw (§6.2).
2. **Cold start.** Measure it in Milestone 1 and write the real number back into this document. If
   ≤300 ms is unreachable per-process, §6.1 reopens.
3. **Does `register_uri_scheme_as_secure` actually enable `navigator.clipboard`?** If not, copy
   natively over a message handler (§5).
4. **Does WebKitGTK render on Hyprland without `WEBKIT_DISABLE_DMABUF_RENDERER=1`?** If the
   workaround is needed it forces shared-memory buffers and everything gets slower.
5. **Does Prism's autoloader work under a custom URI scheme?** It fetches language grammars
   lazily *at render time*, so this is not a startup question — an unhighlighted Rust block three
   documents in is the symptom. Requires `components/` vendored in full and `languages_path`
   repointed (§4).
6. **Do Mermaid's fonts resolve on a bare Omarchy install?** §6.4's explicit `fontFamily` is the
   mitigation; verify it works.
7. **WebKitGTK reportedly renders fonts ~100 weight units heavier than specified** — reported for
   Tauri/Wails on Linux, **not verified against 2.52.5**. If it holds, specify weights 100 lighter.
8. **Which identifier lands in `xdg_toplevel.set_app_id`** — the `GApplication` id or `prgname`? All
   desktop integration and every window rule hangs off it. Check with
   `WAYLAND_DEBUG=1 moremaid |& grep set_app_id`.
9. **Does WebKit content re-render crisply when the user cycles monitor scale** with `Super+/`?
10. **`nucleo-matcher` is quiet** — 0.3.1 dates from February 2024, though it is Helix's matcher and
    in daily use. `fuzzy-matcher` is formally archived and is not an alternative. If nucleo is dead
    by the time you read this, the exit is free: port `Sources/Search/FuzzyMatcher.swift`, which is
    short and self-contained, and Linux ranking then matches macOS exactly.
11. **`colors.toml` has no compatibility promise.** It is internal to Omarchy and its path already
    moved once (`~/.config` → `~/.local/state`). Parse defensively; §6.3's per-key fallback is the
    safety net.
12. **`webkit6` is the thinnest crate in the set** — 143k downloads against `ignore`'s 157M, and
    docs.rs reports it 15.8% documented. Signatures are GIR-generated and reliable; behavioural
    prose is not there, so read the WebKitGTK C documentation for semantics. A weird WebKit
    behaviour is plausibly a binding issue, not your code.

---

## 13. Build plan

**Milestone 1 is something that runs**, not something architecturally complete.

| # | milestone | done when |
|---|---|---|
| **1** | **It opens a file.** Window, WebKitGTK, custom URI scheme serving the vendored assets, one markdown file rendered with Prism and Mermaid, palette read from `colors.toml`. | `moremaid README.md` shows a correctly themed rendered document — **and cold start has been measured and the real number written into §9.1.** |
| **2** | **It browses.** Directory open, Navigator over a lazy list model, heading extraction, internal link navigation, external links via the portal. | A real repo's docs tree is navigable; §9.1's scan targets met on a 10k-file tree. |
| **3** | **It finds things.** Quick Open and Find in Files, both streamed incrementally — **and the `?` shortcuts dialog.** | Keystroke latency met at 10k files. The overlay ships *with* the first shortcuts: with no menu bar it is the only discoverability the app has. |
| **4** | **It's live.** File watching (parent-directory, debounced), live reload with the diagram cache, theme watching. | Two binary invariants hold: a prose-only edit re-renders **zero** diagrams, and a theme switch preserves scroll position. |
| **5** | **It ships.** `config.toml`, `.desktop` + MIME, `PKGBUILD`, README with the two Hyprland rules. | Installs from the AUR on a clean Omarchy box and opens a `.md` file handed over by a file manager. |

---

## Appendix — provenance

Every decision above came from a wayfinder map of 16 tickets, each recording its question, its
answer, what was rejected and why. If something here looks arbitrary, the reasoning is in
`.scratch/linux-port/` in the macOS repository at the pinned commit — along with three research
assets on the Rust crate set, Hyprland/Omarchy conventions, and a 28-row WebKitGTK capability audit.

Where this document and those tickets disagree, **this document wins** — several tickets were
amended by research that landed after they resolved, and those amendments are already folded in
here.
