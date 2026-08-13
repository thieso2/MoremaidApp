# Decide how the app reads the Omarchy palette

Type: grilling
Status: resolved
Blocked by: —

> Surfaced 2026-08-13 by [Research Hyprland/Omarchy conventions](02-hyprland-conventions.md),
> which reopened the *mechanism* half of [Decide theming](07-theming-strategy.md). The decision to
> follow Omarchy rather than ship themes is untouched and strengthened; what needs deciding is how
> the palette physically reaches the rendered page.

## Question

[Theming](07-theming-strategy.md) assumed the palette would come from libadwaita's `StyleManager`.
The research killed that: **Omarchy publishes no accent colour to the Settings portal**, so
`StyleManager` yields a light/dark bit and nothing else. The colours live in
`~/.local/state/omarchy/current/theme/colors.toml`, and a **same-mode theme change fires no
style-manager signal at all** — switch from one dark theme to another and the app is never told.

Decide the mechanism, end to end:

- **Read `colors.toml` directly, or participate in the `.tpl` template system?** Omarchy's
  `omarchy-theme-set-templates` renders `.tpl` files from `~/.config/omarchy/themed/` into the
  current-theme directory on every switch (this is how Obsidian is themed). Shipping a
  `moremaid.css.tpl` would hand the app ready-made CSS; reading `colors.toml` directly keeps
  everything inside the app and installs nothing into `$HOME`. **A package must not write to a
  user's home directory**, which cuts against the template route — but the template route survives
  if the app writes its own template on first run, or if the user opts in with a documented
  one-liner. Weigh it.
- **How is a change detected?** The research names an inotify watch on the *parent* directory plus
  the `theme-set.d` hook. Decide which, or both, and what the fallback is when neither fires. The
  app already has a file watcher — this should reuse it, not grow a second mechanism.
- **What is the colour contract?** `colors.toml` gives a palette with Omarchy's key names; the page
  needs CSS custom properties, and Prism needs a code-highlighting palette. Define the mapping —
  including what happens when a theme omits a key the page needs, which is the case that will
  actually break in the wild.
- **What happens off Omarchy?** A plain Arch + Hyprland box has no `colors.toml`. The app must
  still render something reasonable. Decide the fallback: derive from the GTK light/dark bit, or
  ship one built-in palette as the floor.
- **First paint.** The palette must be known *before* the page renders, or every launch flashes the
  wrong colours. Decide whether the read is synchronous on startup and what it costs against
  [the performance targets](13-definition-of-done.md).

The chrome half needs no decision: GTK cannot follow a same-mode theme change live
(basecamp/omarchy#2789, closed unimplemented), so any chrome/content mismatch is an Omarchy gap.
That is a third independent argument for drawing almost no chrome, and worth stating as such rather
than re-litigating.

## Answer

**Read `colors.toml` directly, synchronously, at startup; watch the parent directory for changes;
fall back to one built-in palette.** No template, no hook, no `$HOME` footprint, no new crates —
`toml` and `notify` are already in the tree for `config.toml` and live reload.

### The read

Source of truth: **`~/.local/state/omarchy/current/theme/colors.toml`**, with
`~/.config/omarchy/current/theme/colors.toml` tried as a legacy fallback — the path moved in
`quattro` and it costs one `stat` to survive that having happened before.

Read and parse it **on the startup path, before the first `load_html`**, and interpolate the derived
custom properties into the initial HTML. The file is ~1 KB of flat TOML; the parse is far below a
millisecond, on a path that is already doing blocking file I/O to read the markdown. **There is
never a flash of the wrong palette** — which matters more here than elsewhere, because with one
process per window the user sees first paint every single time they open a file.

The `.tpl` template route was **rejected**: it is the sanctioned extension point and it is how
Obsidian is themed, but it requires a file written into `$HOME`, and a package must not do that.
First-run self-install or an opt-in one-liner would buy back the capability at the cost of a setup
step that can silently not happen — for a palette the app can derive itself in a few dozen lines.

A `config.toml` key naming an explicit palette file was **considered and rejected** — the built-in
fallback already covers the non-Omarchy case, and this would be a config knob existing only for a
schema change that hasn't happened yet.

### Change detection

**inotify on `~/.local/state/omarchy/current/` — the parent directory, not the file** — re-stat
`theme/colors.toml` on any event. `omarchy-theme-set` replaces the theme directory with `rm -rf` +
`mv`, so a watch on the file's inode goes stale immediately. This is the same trap as the
editor atomic-save case in [the crate set](01-binding-survey.md), and it has the same fix.

Debounce through `notify-debouncer-full`, already a dependency.

- **Light↔dark arrives free**, via the Settings portal → `StyleManager::connect_dark_notify`, with
  zero app code. Handle it, but it is not the interesting case.
- **Same-mode switches (Tokyo Night → Nord) signal nothing at all** — the watch is the only thing
  that catches them, and they are the common case among 22 shipped themes.

The `theme-set.d` hook is **documented in the README as an optional lower-latency path**, not
shipped. The watch works from first launch and survives a user who never installs anything, which
is the property worth optimising for.

**On change: re-derive and push via `evaluate_javascript`, updating the `:root` custom properties
in place, then re-initialise Mermaid so existing diagrams recolour. Do not reload the page** — a
reload would throw away scroll position, and rethemeing while reading is exactly when the user is
looking at the document.

With one process per window, each window reads and watches independently. N windows means N inotify
watches on one directory, which is free.

### The colour contract

The app derives semantic roles from the palette; it never reads GTK theme colours. `StyleManager`
is consulted only for the light/dark bit — which built-in palette to fall back to, and what the
chrome does.

| role | source key | notes |
|---|---|---|
| page background | `background` | |
| raised surface (code blocks, tables) | `lighter_background` in dark mode, `darker_background` in light | the one genuinely mode-dependent pick |
| body text | `foreground` | |
| headings | `bright_foreground` | |
| muted text, rules, borders | `muted`, `dark_foreground` | |
| links, focus ring, active state | `accent` | |
| selection | `selection` | |
| blockquote / callout edge | `accent` at reduced alpha | |

Prism tokens map onto the ANSI set — `comment` → `dark_foreground`, `keyword` → `magenta`,
`string` → `green`, `number` → `orange`, `function` → `blue`, `class-name` → `yellow`,
`constant`/`builtin` → `cyan`, `operator`/`punctuation` → `foreground`, `deleted` → `red`,
`inserted` → `green`, with `bright_*` for emphasis variants. Mermaid's config derives from the same
roles so diagrams, prose and code are one palette rather than three.

Exact aesthetic tuning (alphas, contrast checks against every shipped theme) is implementation
work, not a decision — but the **role list above is the contract**, and it is what HANDOFF.md
carries.

### Robustness

- **Per-key fallback.** Every key is present in all 22 shipped themes and user themes are backfilled
  from `alacritty.toml`, but this is an internal file with no compatibility promise. Any missing or
  unparseable key falls back to the built-in palette's value for that role. A malformed file falls
  back wholesale. **Never fail to render over a colour.**
- **One built-in palette, light and dark**, is the floor: used when no `colors.toml` exists at all
  (plain Arch + Hyprland), chosen by the `StyleManager` light/dark bit. The app then looks good and
  simply ignores themes, rather than looking broken.
- Deriving from Adwaita instead was **rejected** — on Omarchy that produces the blue-grey look
  [the theming decision](07-theming-strategy.md) exists to avoid. It would make the fallback
  consistent with the chrome by making it foreign.

### The chrome half needs no decision

GTK cannot follow a same-mode theme change live —
[basecamp/omarchy#2789](https://github.com/basecamp/omarchy/issues/2789) is closed unimplemented, and
Omarchy's entire GTK theming is `gtk-theme` = `Adwaita`/`Adwaita-dark` plus `color-scheme`. So the
chrome tracks light/dark and nothing more, and any chrome/content mismatch is an Omarchy gap rather
than a bug here. **This is a third independent argument for drawing almost no chrome** — the less
of it there is, the less there is to be visibly out of step. State it in HANDOFF.md as a reason,
not as a caveat.

**The upshot worth putting in HANDOFF.md's opening:** because stock libadwaita apps get only a
light/dark bit, an app that reads `colors.toml` and tints itself will look *more* at home on
Omarchy than most GTK applications on that desktop. This is not parity work — it is the one place
the Linux version can be better than the macOS original.
