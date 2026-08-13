# Decide the keyboard and interaction map

Type: grilling
Status: resolved
Blocked by: 02, 06

## Question

Translate the macOS interaction model to Hyprland without colliding with bindings the compositor
and Omarchy already own (Super is used heavily there), and without a menu bar to lean on for
discoverability.

Map every existing affordance:

| macOS | what it does |
|---|---|
| ⌘P | Quick Open (fuzzy file finder) |
| ⌘⇧F | Search in Files (content search) |
| ⇧⌘T | toggle the Navigator sidebar |
| ⌘N / new tab | new window / new tab |
| `/` | focus search |
| TAB | switch search mode (filename ↔ content) |
| arrows / Enter | browse and open results |
| Cmd+click | open link in new tab/window |
| drag & drop | open dropped files and folders |
| ⌘+ / ⌘- / ⌘0 | zoom |

Decide:

- **The modifier scheme** — Ctrl throughout, or something that acknowledges Omarchy's Super-heavy
  bindings and terminal-adjacent muscle memory.
- **Is there a menu bar at all?** GNOME apps use a hamburger menu; tiling users often want none.
  If there's no menu, **what makes the shortcuts discoverable** — a shortcuts window (Ctrl+?),
  a help overlay, the README?
- **Whether vim-style navigation** (j/k, gg/G, `/` search) is worth offering given the audience.
- What Cmd+click becomes, given the window model decision.

## Answer

**Ctrl for the app, Super stays Hyprland's, vim keys throughout, no menu.**

| binding | action |
|---|---|
| `Ctrl+P` | Quick Open (fuzzy file finder) |
| `Ctrl+Shift+F` | Find in Files (content search) |
| `Ctrl+B` | toggle the Navigator sidebar — editor convention, not macOS's ⇧⌘T |
| `Ctrl+N` | new window (new process, new tile) |
| `/` | focus search |
| `Tab` | switch search mode (filename ↔ content) |
| `j` / `k` | move through results, scroll the document |
| `gg` / `G`, `Ctrl+D` / `Ctrl+U` | top / bottom, half-page scroll |
| `Enter` | open |
| `Escape` | close overlay, clear search |
| `Ctrl+click` | open link in a new window |
| `Ctrl` `+` / `-` / `0` | zoom in / out / reset |
| `?` | shortcuts overlay |

- **Super is never bound.** It belongs to the compositor on this desktop; an app that takes it is
  broken by definition, not by preference.

- **No menu bar and no hamburger menu.** This app does perhaps eight things. A menu is chrome for a
  program with more surface than this one has, and on a tiling desktop it is vertical space spent
  on nothing.

- **`?` is the discoverability story, and therefore the documentation.** One overlay listing every
  binding. Because it replaces the menu entirely, it has to be genuinely complete and it has to be
  the first thing built, not the last — an undiscoverable app with no menu is just a hostile app.

- **Vim keys are baseline, not a power-user affordance.** This audience lives in neovim; `j`/`k`
  scrolling a document is the expectation on arrival.

- **`Ctrl+click` opens a new window** rather than a new tab, following from the window model.

Rests on [Hyprland conventions](02-hyprland-conventions.md) to confirm none of these collide with
bindings Omarchy ships by default. Collisions would adjust individual rows, not the scheme.
