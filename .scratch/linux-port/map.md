# Map: Moremaid for Linux (Omarchy/Hyprland)

Label: `wayfinder:map`

## Destination

A **HANDOFF.md** — a complete, self-contained implementation spec that a fresh Claude Code
session, running on an Omarchy/Hyprland box in an **empty repo**, can build the Linux Moremaid
from without access to this repository. No Linux code is written in this repo or this effort.
When the last ticket resolves, the document exists and every decision it needs has been made:
language, rendering strategy, UI model, theming, keyboard map, config, packaging, and a
milestone-ordered build plan.

## Notes

- **Domain:** porting a ~9.9k-line macOS SwiftUI/WebKit app to a GTK4 desktop app. The macOS
  source is this repo (`Sources/`, 8 modules); `SPEC.md` is the spec the macOS app itself was
  built from and is a useful model for what HANDOFF.md should look like.
- **Execution is in-scope for the final ticket only.** Writing HANDOFF.md is the destination, so
  [Write HANDOFF.md](issues/12-write-handoff.md) produces the artifact rather than a decision.
  (Overrides wayfinder's plan-only default.) Every other ticket decides.
- **Scoping decisions already fixed** (charting conversation, 2026-08-13):
  - **Destination shape** — a spec for a *fresh repo*, not a scaffolded skeleton and not a
    cross-platform refactor of this codebase. The two codebases will be separate and will drift.
  - **Stack is decided, language is not** — GTK4 + libadwaita shell, WebKitGTK 6.0 for rendering,
    reusing the existing HTML/markdown-it/Prism/Mermaid pipeline. The implementation language is
    open ([Choose the implementation language](issues/04-choose-language.md)).
  - **Target is Omarchy/Hyprland only** — Arch, Wayland-only, no X11 fallback, no GNOME/KDE
    accommodation, packaging via PKGBUILD/AUR. The spec may be concrete and opinionated
    everywhere; "feels native" means *feels native on a tiling Wayland compositor*, which is not
    the same thing as feeling native on GNOME.
  - **v1 scope = the reading core** — markdown + Mermaid + code highlighting, themes and
    typography, directory browsing, Navigator sidebar, multi-window/tabs, Quick Open, Find in
    Files, live reload, drag & drop, recents. Everything else is out of scope (below).
  - **No Linux hardware during this effort** — the whole map is paper. There are **no prototype
    tickets**; research must mark findings as confirmed-from-docs vs inferred, and HANDOFF.md
    carries a known-unknowns section because nothing here will have been compiled.
- **Skills to consult when resolving:** `/grilling` + `/domain-modeling` for the decision tickets;
  `/research` for the three research tickets; `/handoff` is worth a look for the final ticket
  though its format may not fit.
- **Research assets** live in `.scratch/linux-port/assets/`, linked from their ticket.
- **The eight decision tickets were resolved in one session (2026-08-13)**, at the user's explicit
  direction, overriding wayfinder's one-ticket-per-session rule. They were answered as a single
  pass in the Omarchy design idiom — see [the pass](assets/dhh-pass.md) — and then ruled on. The
  language answer was **overruled from Ruby to Rust** by the user; the pass document is kept as
  the working record, but where it and a ticket's `## Answer` disagree, **the ticket wins**.
- **The three research tickets now confirm rather than decide.** They were charted as inputs to
  decisions that have since been taken ahead of them, so their job changed:
  [the crate set](issues/01-binding-survey.md) was re-scoped from a language survey to pinning
  `Cargo.toml`; [Hyprland conventions](issues/02-hyprland-conventions.md) and
  [the WebKitGTK audit](issues/03-webkitgtk-audit.md) now verify the mechanisms the resolved
  decisions assume. **A resolved ticket reopening on their evidence is the map working, not
  failing** — say so plainly rather than working around it quietly.

- **Concurrent sessions are in play on this map.** Tickets 02 and 03 were resolved by parallel
  sessions while another was mid-flight. One consequence worth knowing: a session mistook those
  concurrent `Status: resolved` writes for a linter and **reverted them twice**. If a ticket's
  status contradicts this map's Decisions-so-far, **the map is right** — re-check before
  "correcting" anything. Ticket 02 was also researched twice; the duplicate asset was discarded and
  its two non-overlapping findings appended to 02 as an addendum.

## Decisions so far

<!-- one line per closed ticket: gist of the answer + link -->

- [Choose the Rust crate set](issues/01-binding-survey.md) — pinned set in
  [crate-set.md](assets/crate-set.md) (canonical; `cargo-toml.md` is the first pass, now a stub —
  two sessions researched this concurrently and were reconciled). **The JS↔native bridge is
  confirmed present in the `webkit6` Rust binding**, not merely in the C API — the map's largest
  risk, retired. `libadwaita` is built with `v1_6`, but *not* because theming needs it: ticket 02
  found Omarchy publishes no accent colour at all, so the accent API compiles and reports nothing.
  The binding is complete; the desktop doesn't feed it. **No async runtime** —
  GTK's main loop plus `gio::spawn_blocking` and `async-channel`, no tokio. Three flags for
  HANDOFF.md: watch the parent *directory* and debounce or the watcher goes deaf after the first
  atomic save; `nucleo-matcher` is quiet but has a free exit (port the existing Swift matcher —
  unaffected by the `fuzzy-matcher` crate being archived, which kills only
  [11](issues/11-module-port-map.md)'s "or `fuzzy-matcher`" alternative);
  `webkit6` is the thinnest crate in the set and 15.8% documented. Four corrections landed on
  reconciliation: add `grep-matcher` (match spans), set `ignore`'s `require_git(false)`, `toml`
  can't emit the *commented* default config asked for, and the script-message payload is a
  JavaScriptCore `Value` — say so, though no extra crate is needed.
- [Research Hyprland/Omarchy conventions](issues/02-hyprland-conventions.md) — findings in
  [hyprland-conventions.md](assets/hyprland-conventions.md). **"Feels native" here means going
  bare:** a plain `GtkApplicationWindow` with no header bar. Hyprland answers *server-side* to both
  decoration protocols and GTK4 honours that by suppressing its fallback titlebar, so a bare window
  is already correct with zero code — while `AdwApplicationWindow` forces a `.csd` class that
  brings rounded corners into a square-bordered desktop. **The compositor's own window grouping is
  the tab feature**, so 06's deletion of `AdwTabView` is a gain, not a sacrifice. 08's Ctrl map
  collides with nothing — but `Ctrl+C/V/X` are hard-reserved, since Omarchy's `Super+C/V/X`
  synthesise them into the focused window. **Reopens 07's theming mechanism** (see that line).
- [Audit WebKitGTK 6 against the rendering pipeline](issues/03-webkitgtk-audit.md) — audit in
  [webkitgtk-audit.md](assets/webkitgtk-audit.md). **The stack holds; nothing fundamental is
  missing**, and every needed API is confirmed present in the `webkit6` crate itself rather than
  only in the C API — zero inferred entries. The JS bridge is byte-identical, so `PageScripts.swift`
  is ~95% portable verbatim. Biggest move: **replace the `file://` base URI with a custom URI
  scheme** — absolute paths outside `base_uri` terminate the web process, and the same change fixes
  offline assets and the secure-context clipboard gate at once.
- [Choose the implementation language](issues/04-choose-language.md) — **Rust + gtk4-rs +
  libadwaita-rs + webkit6-rs**, decided ahead of the research on the grounds that instant cold
  start is non-negotiable and a single binary is the cleanest AUR package. Costs the
  "edit the app on your disk" property, deliberately bought back by shipping the web assets as
  editable data files. No Swift reuse — but three of the five reusable files vanish into crates.
- [Decide how the Linux app obtains the rendering layer](issues/05-rendering-layer-strategy.md) —
  **reuse verbatim**: extract the CSS/JS from the Swift string constants, vendor markdown-it /
  Prism / Mermaid as pinned committed files, no CDN, no npm, no build step. Assets install to
  `/usr/share/moremaid/web/` (overridable via `$XDG_DATA_HOME`), *not* `include_str!`. One-time
  copy; the repos drift on purpose. HANDOFF.md must cite a pinned commit SHA.
- [Decide the window, tab and session model](issues/06-window-model.md) — **the compositor owns
  windows**. One process per invocation, no in-app tabs, no session restore, no self-raising, and
  the Mermaid diagram opens as a new toplevel. Cost: one WebKitGTK per window; accepted and to be
  measured, with single-instance as the contained retreat.
  _Confirmed by [02](issues/02-hyprland-conventions.md), with two notes: one process per invocation
  only happens if the app sets `gio::ApplicationFlags::NON_UNIQUE` — `GApplication` is
  single-instance by default and forwards silently otherwise; and the Mermaid toplevel will tile
  rather than go full-screen, so it needs a distinct app-id and a documented float rule._
- [Decide theming](issues/07-theming-strategy.md) — **follow Omarchy, ship zero themes**. Content
  palette derives from `StyleManager` + GTK settings and is injected as CSS custom properties;
  live re-theming is mandatory; one typography, not six; Prism follows the same source. Deletes
  `ThemeCSS`, `TypographyCSS` and the entire preferences window.
  _Mechanism reopened by [02](issues/02-hyprland-conventions.md): on Omarchy `StyleManager` yields
  only a light/dark bit — no accent colour is published to the Settings portal at all — so the
  palette must be read from `~/.local/state/omarchy/current/theme/colors.toml`, and live switching
  needs an inotify watch on that parent directory plus the `theme-set.d` hook, since a same-mode
  theme change fires no style-manager signal. The decision to follow Omarchy is untouched and
  strengthened; the replacement mechanism is now its own ticket,
  [Decide how the app reads the Omarchy palette](issues/15-omarchy-palette-source.md), **resolved**._
- [Decide how the app reads the Omarchy palette](issues/15-omarchy-palette-source.md) — **parse
  `~/.local/state/omarchy/current/theme/colors.toml` directly, synchronously, before first paint**
  (legacy `~/.config` path tried as fallback). No `.tpl`, no hook, nothing written to `$HOME`, no
  new crates. Changes are caught by an inotify watch on the **parent** `current/` directory —
  the theme dir is replaced by `rm -rf` + `mv`, so a watch on the file goes stale, and a same-mode
  switch signals nothing at all. On change, re-derive and push via `evaluate_javascript` updating
  `:root` in place plus a Mermaid re-init — **never reload**, that would lose scroll position.
  Missing keys fall back per-key to one built-in light/dark palette, which is also the whole
  fallback off Omarchy. Ships the semantic role→key contract HANDOFF.md carries. Rejected: the
  `.tpl` route (needs a `$HOME` write), a config override key, and deriving from Adwaita (produces
  exactly the foreign look 07 exists to avoid). _Note for HANDOFF.md's opening: since stock
  libadwaita apps get only a light/dark bit, an app that reads `colors.toml` looks more at home on
  Omarchy than most GTK apps do — the one place the Linux version beats the macOS original._
- [Decide the keyboard and interaction map](issues/08-keyboard-map.md) — **Ctrl for the app, Super
  never bound, vim keys throughout, no menu of any kind**, with `?` as the shortcuts overlay and
  therefore as the documentation — which makes it a first-milestone item, not a last one.
- [Decide config and state persistence](issues/09-config-persistence.md) — **one hand-editable
  `$XDG_CONFIG_HOME/moremaid/config.toml`**, no GSettings. Config is a stable user-facing
  interface (now the main one, post-Rust); state is separate under `$XDG_STATE_HOME`; sessions
  deleted; folder-expansion ephemeral; `showBreadcrumb`/`showStatusBar` deleted rather than made
  configurable.
- [Decide packaging and desktop integration](issues/10-packaging.md) — **AUR (`moremaid` +
  `moremaid-git`), pacman is the updater.** `depends`: gtk4, libadwaita, webkitgtk-6.0;
  `cargo build --release`. Terminal invocation (`moremaid file.md`, `.`, bare, stdin) is the
  primary entry point and gets designed first; `.desktop` + MIME association secondary.
- [Build the module-by-module port map](issues/11-module-port-map.md) — roughly **a third deleted
  rather than ported**. `FileScanner` + `GitignoreParser` → the `ignore` crate; `ContentSearch` →
  `grep-searcher`/`grep-regex` in-process; `FuzzyMatcher` → `nucleo`; `FileWatcher` → `notify`,
  polling dropped. Genuinely new work is the GTK shell, the WebKitGTK bridge, and the lazy sidebar.
  `HeadingParser` needs a shared heading→slug fixture on both sides or the anchor coupling rots.

- [Set the performance targets and test strategy](issues/13-definition-of-done.md) — **cold start
  ≤300 ms**, the number the language choice was justified against and nobody had set; measured in
  milestone 1 and written back into the spec. If WebKitGTK's process spawn makes it structurally
  unreachable that **reopens [06](issues/06-window-model.md)** rather than relaxing quietly.
  Memory per window: measure, with **>400 MB the red line** on one-process-per-window. **The Mermaid
  pathology is fixed in the port, not inherited** — hash each diagram's source and re-render only
  what changed, turning a prose-only edit from "re-render every diagram" into "re-render none".
  Tests: pure logic + **golden HTML snapshots**; the Rust↔JS slug coupling is held by **one shared
  fixture run on both sides** (node is test-only, so no build step). **No CI** — so the README names
  both commands and the release checklist runs them, since the JS half is the half that gets
  forgotten. Ships the five-milestone build plan HANDOFF.md carries, M1 being something that runs.
  _Note: the `?` overlay lands in M3 with the first shortcuts — which is what
  [08](issues/08-keyboard-map.md) meant by "first-milestone item": with it, never after it._

- [Decide error and edge-case behaviour](issues/14-edge-behaviour.md) — the macOS app has **no size
  guard and no binary detection**; both are closed here. Non-markdown text still renders as a Prism
  code document (that's why it's a viewer, not a markdown-only tool), binaries are refused via
  `grep-searcher`'s NUL heuristic — no new dependency. **Soft ceiling at 5 MB *or* 50 diagrams** →
  plain render plus a banner, `Ctrl+Shift+R` to insist; **the diagram count is the real trigger**,
  since a 200 KB file with 200 diagrams is far more dangerous than a 20 MB file with none. Malformed
  Mermaid surfaces `MermaidValidator`'s line-numbered error **inline** instead of throwing it away,
  as it does today. A deleted file **keeps its content on screen** behind a banner — the usual cause
  is a branch switch, not a deletion. Terminal-first everywhere else: a bad path is stderr + exit 1
  with **no window**; stdin's base path is the CWD and has no live reload. _Adds `Ctrl+Shift+R` to
  [08](issues/08-keyboard-map.md) and a banner component HANDOFF.md must describe._

- [Decide the font stack](issues/16-font-stack.md) — body and headings
  `"iA Writer Quattro S", "Noto Sans", sans-serif`; code is **bare unquoted `monospace`**, which
  fontconfig resolves to the user's `omarchy font` choice for free. **But Mermaid must name an
  explicit family** — the audit found WebKitGTK's SVG renderer can fail to resolve generics and
  **silently blank every diagram label** ([warp#9402](https://github.com/warpdotdev/warp/issues/9402)),
  which is why `ttf-ia-writer` is a hard `depends`, not `optdepends`. Content zoom = app zoom ×
  `text-scaling-factor`, watched live, so sidebar and document stay in proportion. Three
  `config.toml` keys. **Requires a sweep of the extracted assets** — `TypographyCSS`, `BaseCSS:86`
  and the easily-missed inline stack at `HTMLGenerator:80` are all macOS-shaped and won't fix
  themselves. _Debatable call flagged for hardware: GTK chrome uses the body face too (defensible
  only because Omarchy never sets a UI font). Known unknown: WebKitGTK reportedly renders ~100
  weight units heavy — verify in M1._

- [Write HANDOFF.md](issues/12-write-handoff.md) — **the destination. Written to `HANDOFF.md` at the
  repo root**, 821 lines, 13 sections. Assembly was reconciliation rather than transcription: the
  eight decision tickets were resolved before the research landed, so the `libadwaita` feature
  rationale, the packaging dependency list, the keyboard map, the theming mechanism and the `?`
  overlay's milestone all had to be merged rather than copied. Project identity decided in passing
  (same name and icon, separate repos, free to diverge), clearing the map's last fog patch.
  **This map is complete.**

## Not yet specified

<!-- in-scope fog; graduates as the frontier advances -->

<!-- Graduated 2026-08-13: "which actual font faces" → [16 — Decide the font
     stack](issues/16-font-stack.md), once [02](issues/02-hyprland-conventions.md) §2.5 established
     that Omarchy sets only the fontconfig `monospace` alias and expresses no opinion on body text
     at all. -->
**The fog is clear.** Every patch has graduated into a ticket or been decided.

<!-- Cleared 2026-08-13: "project identity" — decided in passing by
     [12](issues/12-write-handoff.md): same name, same icon, separate repos, free to diverge.
     Stated in HANDOFF.md §1. -->

<!-- Graduated 2026-08-13: "testing and CI" + "startup and performance targets" merged into
     [13 — Set the performance targets and test strategy](issues/13-definition-of-done.md);
     "error and edge behaviour" into
     [14 — Decide error and edge-case behaviour](issues/14-edge-behaviour.md). -->

<!-- Cleared 2026-08-13: "how macOS-side changes reach the Linux app" — answered by
     [05](issues/05-rendering-layer-strategy.md): nobody owns divergence, the repos drift by
     design, and the same answer covers the non-rendering half. Not fog, a decision. -->>

## Out of scope

<!-- ruled beyond the destination; never graduates -->

- **`.moremaid` archives** — ZIP virtual filesystem, AES-256 encryption, in-memory browsing of
  encrypted archives, pack/unpack. (`Sources/Archive/`)
- **The `mm` CLI** — beyond the app binary accepting a path argument, which is in scope.
- **File-manager preview integration** — the QuickLook extension has no v1 equivalent (no Nautilus
  thumbnailer, no GNOME Sushi integration).
- **Activity Feed** — real-time file-change tracking UI. (`ActivityFeedView`/`ActivityFeedStore`)
- **PDF export and batch PDF export.** (`PDFBatchExporter`)
- **Source editor view.** (`SourceEditorView`)
- **In-app auto-update** — Sparkle's role on macOS; on Arch this is the package manager's job.
- **GNOME, KDE, XFCE polish; X11 support; Flatpak, deb, or AppImage packaging.** Ruled out by the
  Omarchy-only target.
- **A shared or cross-platform codebase with the macOS app** — rejected at charting in favour of a
  separate repo.
