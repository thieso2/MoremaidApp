# Research Hyprland/Omarchy application conventions

Type: research
Status: resolved
Blocked by: —

> **Re-pointed 2026-08-13.** Three decisions that were meant to rest on this research were taken
> ahead of it: [window model](06-window-model.md), [theming](07-theming-strategy.md) and
> [keyboard map](08-keyboard-map.md). This ticket now **confirms or reopens** them rather than
> feeding them. Concretely, the findings that matter most are: (a) exactly what Omarchy sets when
> it switches theme and what an app must watch to follow it; (b) whether a bare window or an
> `AdwHeaderBar` is right under Hyprland; (c) whether any proposed `Ctrl` binding collides with
> Omarchy's defaults. Contradict any of the three and say so plainly — a resolved ticket reopening
> on evidence is the map working, not the map failing.

## Question

What does a well-behaved GTK4 application look like on **Omarchy/Hyprland** specifically — not
on GNOME? This is the ticket that defines "feels native" for this effort, so it needs concrete
findings, not vibes.

Cover:

- **Decorations.** Client-side vs server-side. Hyprland tiles and draws its own borders; many
  users disable CSD. Does a libadwaita `AdwHeaderBar` help or fight the compositor? What do
  respected GTK apps do under Hyprland, and what window rules do Omarchy users typically apply?
- **Theming.** How Omarchy applies a theme across apps — GTK theme, `gsettings` `color-scheme`,
  its theme-switching mechanism, config file locations. What must an app do to follow the
  active Omarchy theme, and what happens when the user switches theme while the app is running?
- **Portals.** Which XDG desktop portals are present under Hyprland (`xdg-desktop-portal-hyprland`
  + the GTK backend): file chooser, settings, opening URIs. How a GTK4 app should open a folder
  picker and hand external links to the browser.
- **Wayland realities.** Fractional scaling, the inability of clients to position or raise their
  own windows, clipboard/drag-and-drop behaviour, and what that breaks in a design that assumes
  macOS window management.
- **Desktop integration on Arch.** `.desktop` entry conventions, MIME association for markdown,
  icon theme placement, and whether tray/background-app patterns are viable (they mostly aren't).
- **The keybinding space.** Which modifiers and chords Hyprland/Omarchy already claim (Super is
  used heavily), so the app's shortcuts can be chosen without collisions.

Deliverable: a markdown findings doc under `.scratch/linux-port/assets/`, linked here. Flag every
place where a macOS assumption in the current app simply does not survive contact with a tiler —
those become input to the window-model and keyboard tickets.

## Answer

Full findings, every claim tagged confirmed-from-source **[C]** or inferred **[I]**, with links:
**[assets/hyprland-conventions.md](../assets/hyprland-conventions.md)**. Read from Omarchy's
`quattro` branch — `master` is the stale pre-Lua generation; third-party write-ups (DeepWiki et al)
describe paths that no longer exist.

### [08 keyboard map](08-keyboard-map.md) — **confirmed, one addition**

Every row of the decided map was checked against Omarchy's actual binding source
(`default/hypr/bindings/{tiling,utilities,clipboard,media,applications}.lua`). **Zero collisions.**
The *entire* `Ctrl` and `Ctrl+Shift` space is unclaimed — Omarchy binds no plain-Ctrl chord at all,
only `Ctrl+Alt+Delete` and `Ctrl+Alt+Tab`. Bare `/ ? j k g Enter Escape Tab` are free too.

One thing the map is missing and **must** add: **`Ctrl+C`/`Ctrl+V`/`Ctrl+X` are hard-reserved for
clipboard.** Omarchy's `Super+C/V/X` "universal clipboard" *synthesises* `Ctrl+C/V/X` into the
focused window. Bind `Ctrl+C` to anything else and a desktop-wide gesture breaks inside Moremaid.
Second addition: `Alt+Tab` is the compositor's, so nothing in-app may use it. Third: the `?`
overlay now has a native widget — **`AdwShortcutsDialog`** (libadwaita 1.8+, Arch ships 1.9.3);
`GtkShortcutsWindow` is deprecated since GTK 4.18.

### [07 theming](07-theming-strategy.md) — **decision confirmed, mechanism reopened**

"Follow Omarchy, ship zero themes" is right and the research strengthens it. But the *stated
mechanism* — "read the light/dark state and accent from libadwaita's `StyleManager`" — **does not
work on Omarchy** and must be replaced:

- Omarchy's entire GTK theming is three `gsettings` calls: `color-scheme` prefer-light/dark,
  `gtk-theme` Adwaita/Adwaita-dark, `icon-theme`. **There is no `gtk.css` in any shipped theme**
  and no GTK template in `default/themed/`.
- There is **no accent colour**: `xdg-desktop-portal-gtk` publishes only `color-scheme` and
  `contrast` under `org.freedesktop.appearance`. `AdwStyleManager` therefore yields exactly **one
  bit** on this desktop — Tokyo Night, Gruvbox and Nord are indistinguishable through it.
  **Not a contradiction of [01](01-binding-survey.md), which calls libadwaita's `v1_6` feature
  load-bearing because `accent_color()` exists — both are true.** The API is real and the feature
  flag is still needed; Omarchy simply never feeds it, so the call returns the Adwaita default on
  every theme. Keep `v1_6`, but do not let it carry the palette. HANDOFF.md should say this in one
  sentence so the reader does not "fix" one finding with the other.
- The real palette is **`~/.local/state/omarchy/current/theme/colors.toml`** (note: `.local/state`,
  not `.config` — it moved in `quattro`). Flat TOML, `mode` + 26 semantically-named colours,
  present in every theme, backfilled from `alacritty.toml` for user themes. Parse this, or the app
  follows nothing.
- **Live switching is worse than assumed.** The `StyleManager` signal fires only on a light↔dark
  flip; Tokyo Night → Nord changes no gsetting and the app is told *nothing*. Two real signals:
  an inotify watch on `~/.local/state/omarchy/current/` (the theme dir is atomically `mv`-swapped,
  so watch the parent), and Omarchy's sanctioned `~/.config/omarchy/hooks/theme-set.d/` hook.
  Ship both — file watch for zero-install correctness, hook for latency.
- Typography rows partly confirmed: "the user's configured monospace for code" is a free win —
  Omarchy's font setting is a fontconfig `prepend_first` on the **`monospace`** alias, so unquoted
  `font-family: monospace` in the page resolves to it automatically. But "the system UI font" is
  Cantarell, *not* JetBrains Mono — Omarchy never touches `font-name`. And `text-scaling-factor`
  **is** a live user-facing Omarchy setting (`omarchy display text size`) that GTK honours and
  WebKit content does not; the app must fold it into content zoom or the sidebar and the document
  disagree.

### [06 window model](06-window-model.md) — **confirmed; two corrections and the decoration answer**

One-window-per-invocation, no in-app tabs, no session restore, multi-process — all confirmed, and
better supported than the ticket knew: Hyprland has **native window grouping** (`Super+G`, a themed
groupbar, `Super+Alt+Tab` to cycle, `Super+Alt+1..5` to jump). That *is* the tab feature, already
built and already themed. Session restore is not merely unwanted but impossible — a Wayland client
cannot set its position, and Omarchy ships `suppress_event = "maximize"` so it cannot set its size
either.

Two corrections:

1. **`xdg-activation` is less awkward than stated.** Omarchy sets `misc.focus_on_activate = true`,
   and GTK ≥ 4.14.6 handles the receiving side automatically. The decision to just open another
   window still stands (multi-process means there is no sibling to activate), but the *reasoning*
   should be "we chose multi-process", not "activation doesn't work".
2. **The Mermaid diagram toplevel will tile, not go full-screen.** A second toplevel splits the
   reading window in half — the opposite of the macOS behaviour — and the app cannot maximize
   itself. Keep the toplevel, but give it a distinct title/app-id and ship a documented
   `o.window(...) { float = true }` rule in the README, the way Omarchy floats its own dialogs.

**The decoration question this ticket owed 06: go bare.** Use a plain `GtkApplicationWindow` with
no header bar. Hyprland answers *server-side* to both decoration protocols
(`"Screw Gnome and GTK"` — its own source comment), GTK4 honours that via
`gdk_wayland_display_prefers_ssd()` and suppresses its fallback titlebar, so a bare window is
already correct with no code. `AdwHeaderBar` would add ~47px of chrome for content that no longer
exists — 07 deleted preferences, 08 deleted the menu. Caveat: `AdwApplicationWindow` forces the
`.csd` class regardless of compositor preference (it installs an invisible titlebar gizmo), which
brings Adwaita rounded corners and a shadow margin into a `rounding = 0`, square-2px-border
desktop. Prefer `GtkApplicationWindow`; if libadwaita dialogs force `AdwApplicationWindow`,
override the `.csd` styling. **This is the #1 thing to verify on real hardware.**

### [04 language](04-choose-language.md) — **not contradicted; one silent trap**

Rust + `gtk4-rs` + `libadwaita-rs` + `webkit6-rs` survives this research intact, and two findings
get *cheaper* under it: parsing `colors.toml` reuses the `toml` crate ticket 09 already needs, and
watching `~/.local/state/omarchy/current/` reuses the `notify` crate live-reload already needs. So
the theming mechanism this ticket reopens costs **zero new dependencies**. `AdwShortcutsDialog` is
reachable — the `libadwaita` crate is at 0.9.2 with feature flags through `v1_10`.

**The trap:** `GApplication` is single-instance **by default**. Ticket 06's "multi-process, each
invocation its own process" only happens if the app is constructed with
`gio::ApplicationFlags::NON_UNIQUE`. Without it a second `moremaid b.md` forwards its arguments to
the first process over D-Bus and exits — the exact behaviour 06 rejected, with no error message.
HANDOFF.md must name the flag.

### Also new, and nobody's ticket yet

Every Omarchy window is `opacity 0.985 0.96` by default — a reader should ship a documented
opt-out rule (`tag = "-default-opacity"`), as `imv`/`mpv` do. `webkitgtk-6.0` is **not** in
Omarchy's base package set (~100 MB new dependency). Omarchy already ships **Omawrite** (its own
markdown app, `Super+Shift+W`) and Obsidian, so the `.desktop` entry should *offer* `text/markdown`
without grabbing the default. And GTK4 has **no tray API at all** — no tray, no background
residency, no autostart.

### The three things to verify first on real hardware

1. Does `AdwApplicationWindow`'s forced `.csd` class actually show rounded corners and a shadow
   margin against Hyprland's square 2 px border? (§1.3 — decides bare vs Adw window.)
2. Does WebKitGTK content re-render crisply when the user cycles monitor scale with `Super + /`?
3. Which identifier lands in `xdg_toplevel.set_app_id` — the `GApplication` id or `prgname`?
   Everything in desktop integration hangs off it. `WAYLAND_DEBUG=1 moremaid |& grep set_app_id`.

---

### Addendum (separate session, 2026-08-13)

A second session researched this ticket concurrently before noticing it was already resolved. Its
findings overlapped almost entirely and its asset was discarded as redundant — **and in one place
wrong**: it treated the `Super+C`/`Super+V` synthesis as a bad source and dismissed it. The
resolution above is correct on that point; the duplicate was not.

Two findings from that pass are **not** in the asset above and are worth keeping:

1. **GTK3/GTK4 apps do not re-theme live on Omarchy today.**
   [basecamp/omarchy#2789](https://github.com/basecamp/omarchy/issues/2789) requested dynamic GTK
   theming and is **closed without implementation** — the proposed fix (rewriting
   `~/.config/gtk-{3,4}.0/settings.ini` on theme switch) was never merged. This is confirmation
   from the other direction that reading the palette out of `colors.toml` is not merely the
   *better* route but the *only* one that gets a live full-palette follow: the GTK chrome
   physically cannot follow a same-mode theme change without a restart. It also means any
   chrome/content mismatch after a theme switch is an **Omarchy gap, not a bug in this app** — and
   it is a second, independent argument for drawing as little chrome as possible.

2. **A theme declares itself light by containing an empty `light.mode` file** in its root —
   presence alone is the signal, contents irrelevant. Useful if the app ever needs to determine
   light/dark from the theme directory rather than from the style manager.
