# Decide the font stack

Type: grilling
Status: resolved
Blocked by: —

> Graduated from the map's fog 2026-08-13, once
> [the Hyprland/Omarchy research](02-hyprland-conventions.md) §2.5 established what a stock Omarchy
> box actually sets and installs.

## Question

[Theming](07-theming-strategy.md) settled that there is **one** typography rather than six, and
that it follows system settings. The research then established that on Omarchy there is barely a
system setting to follow:

- `omarchy-font-set` writes `~/.config/fontconfig/fonts.conf` with a `prepend_first` rule on the
  **`monospace`** alias, and rewrites each terminal's own config.
- It **never** touches `org.gnome.desktop.interface font-name`, `document-font-name` or
  `monospace-font-name`.
- So the GTK UI font is whatever Adwaita defaults to — **Cantarell** — and **body text has no
  system opinion at all**.
- What is actually installed on a stock box includes `ttf-ia-writer` and the `noto-*` families.

Decide:

- **The body/prose face.** There is no system preference to inherit, so this is a real choice, and
  it is the single most visible typographic decision in a markdown reader. Pick one, and decide
  whether it is *depended upon* (a `PKGBUILD` dependency on a font package) or *preferred with
  fallbacks* (a CSS stack that degrades). `ttf-ia-writer` being pre-installed makes it a strong
  candidate that costs nothing.
- **The code face.** Unquoted `font-family: monospace` inherits the user's fontconfig choice for
  free — the one place Omarchy *does* express a preference, and honouring it is a cheap, very
  visible win. Confirm that's the answer and that nothing overrides it.
- **The UI/chrome face.** Cantarell by default. Given the app draws almost no chrome, does this
  matter enough to override?
- **Sizing and `text-scaling-factor`.** `org.gnome.desktop.interface text-scaling-factor` is a live
  Omarchy setting (`omarchy display text size`). GTK chrome follows it automatically; **WebKit
  content does not unless the app multiplies it in.** Decide whether it does — and how that
  composes with the app's own `Ctrl +/-/0` zoom, so the two don't fight.
- **What `config.toml` exposes.** [Config](09-config-persistence.md) reserved font family and size
  overrides. Name the exact keys.

Every named macOS family in `TypographyCSS.swift` (SF, New York, SF Mono) is a dead reference and
must not survive into the spec.

## Answer

### The faces

| role | value | why |
|---|---|---|
| **body + headings** | `"iA Writer Quattro S", "Noto Sans", sans-serif` | `ttf-ia-writer` is already on a stock Omarchy box and Quattro is a genuine reading typeface — the closest thing that desktop has to one. Headings use the same face; there is one typography, not six. |
| **code** | `monospace` — **bare, unquoted, no named families** | The free win: fontconfig resolves the generic to whatever the user picked with `omarchy font`, the one place Omarchy *does* express a preference. Honouring it costs nothing and is invisible when it works, which is what native feels like. |
| **Mermaid** | **explicit named families — never a generic** | See the trap below. This is the exception to the rule above. |
| **GTK chrome** | the body face, via a CSS provider | See the debatable call below. |

`ttf-ia-writer` becomes a **hard `depends`** in the `PKGBUILD`, not an `optdepends` — the Mermaid
trap makes a concrete installed font package load-bearing rather than a nicety.

### The Mermaid font trap — the reason "just use generics" is wrong

[The audit](03-webkitgtk-audit.md) found a reported WebKitGTK behaviour that would be very hard to
diagnose from symptoms: **the SVG renderer can fail to resolve generic CSS font families
(`sans-serif`, `monospace`) when the expected system fonts aren't installed, and since Mermaid
defaults to generics for all text elements, every label in every diagram silently disappears**
([warp#9402](https://github.com/warpdotdev/warp/issues/9402)). Boxes render, labels don't. Nothing
errors.

So: **set an explicit `fontFamily` in `mermaid.initialize()`** naming a concrete family, and depend
on the package that provides it. The CSS text of the document can keep using generics — this
applies to the SVG renderer specifically — but Mermaid must be pinned by name.

This is *why* the font package is a hard dependency, and it should be written into HANDOFF.md with
the reasoning attached, or someone will later "tidy" it back to `optdepends` and blank every
diagram on a minimal install.

### Text scaling

**Effective content zoom = app zoom × `text-scaling-factor`.**

`omarchy display text size` drives `org.gnome.desktop.interface text-scaling-factor` (9–20 px,
anchored at 12 px = 1.0). GTK chrome honours it automatically; **WebKit content does not** — content
size is purely the app's own zoom. Multiplying keeps the sidebar and the document in proportion at
every setting, and `Ctrl+0` resets the app's own factor to 1.0 while still respecting the system
scale.

Watch the gsettings key so a change made while the app is open applies live, the same way the
palette does.

### Config

`config.toml` exposes exactly three keys, per the reservation in
[config and state persistence](09-config-persistence.md):

```toml
[font]
body = "iA Writer Quattro S"   # prose and headings
mono = "monospace"             # bare generic = follow the Omarchy font
size = 16                      # base px, before text-scaling-factor
```

### The sweep — every macOS font reference must die

Three places carry font stacks, and all three are macOS-shaped:

- **`TypographyCSS.swift`** — all six styles, each leading with `-apple-system`,
  `BlinkMacSystemFont`, `'Segoe UI'`. Five of the six are deleted outright by
  [the theming decision](07-theming-strategy.md); the survivor is rewritten.
- **`BaseCSS.swift:86`** — `'Monaco', 'Menlo', 'Ubuntu Mono', 'Courier New', monospace` → bare
  `monospace`.
- **`HTMLGenerator.swift:80`** — an inline `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
  sans-serif` stack on the auto-index page, easy to miss because it isn't in `TypographyCSS` at all.

Dead on Linux and not to survive into the spec in any form: `-apple-system`, `BlinkMacSystemFont`,
`Segoe UI`, `SFMono-Regular`, `Monaco`, `Menlo`, `et-book`, `charter`, `Latin Modern`, `Palatino`,
`Lucida Grande`. Since [the rendering layer crosses over verbatim](05-rendering-layer-strategy.md),
this sweep is a **required edit to the extracted assets** — it will not happen by itself.

### One debatable call, flagged as such

**GTK chrome uses the body face too**, applied via a CSS provider, so the Navigator sidebar and the
Quick Open overlay match the document instead of sitting in Cantarell beside it. The seam between a
GTK sidebar listing headings and a WebKit document rendering those same headings in a different face
is visible, and this is a document viewer — the text *is* the product.

The counter-argument is real: overriding fonts in a GTK app is normally rude. It is defensible here
only because **Omarchy never sets a UI font at all** — Cantarell is Adwaita's default, not the
user's choice — so nothing is being overridden. **Revisit on hardware.** If it looks wrong, dropping
back to Cantarell for chrome is a one-line change.

### Known unknown, for HANDOFF.md

**WebKitGTK is reported to render fonts ~100 weight units heavier than specified**, an open bug
affecting Tauri/Wails apps on Linux. The audit marks it *confirmed as reported* but **not verified
against 2.52.5** — the source is undated relative to current releases.

If it holds, prose will look bolder than intended and the mitigation is to specify weights 100
lighter than wanted. **Verify in milestone 1**, which is already measuring cold start, and correct
the spec with the real behaviour.
