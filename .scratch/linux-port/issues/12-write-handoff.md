# Write HANDOFF.md

Type: task
Status: resolved
Blocked by: —  (01-11, 13-16 all resolved 2026-08-13)

## Question

Assemble every decision on this map into a single **self-contained HANDOFF.md** that a fresh
Claude Code session, on an Omarchy box, in an empty repo, can implement the Linux Moremaid from —
without access to this repository beyond what the document itself carries.

Required sections:

1. **What Moremaid is** — and the v1 feature inventory, stated as observable behaviour rather than
   as a diff against the macOS app (the reader has never seen it).
2. **Target environment** — Arch + Hyprland + Omarchy, Wayland-only, and the assumptions that
   licenses.
3. **Stack and language** with the rationale, plus the exact `pacman` dependency list.
4. **Rendering-layer strategy** — including how the reader obtains the CSS/JS assets, and the
   pinned versions of markdown-it, Prism.js and Mermaid.js.
5. **Module-by-module port map** — the table from the port-map ticket.
6. **UI spec** — window/tab model, Navigator, theming, keyboard map, discoverability.
7. **Config, persistence and packaging.**
8. **Explicit out-of-scope list**, so the reader doesn't helpfully build the archive format.
9. **Milestone-ordered build plan**, each milestone with a definition of done — the first one
   being something that runs, not something that's architecturally complete.
10. **Known unknowns** — every finding this map marked "inferred, not verified", since nothing
    was ever prototyped on real hardware. The reader hits these first and should be warned.

Also decide here: where the document lands (this repo's root, `.scratch/linux-port/`, or handed
over as a standalone file), and whether the `/handoff` skill's format is worth following or
whether this is its own thing.

## Answer

**Written to `HANDOFF.md` at the repository root** (~600 lines, 13 sections plus a provenance
appendix). Root rather than `.scratch/` — it is a deliverable to hand over, not working material,
and the user asked for a `HANDOFF.md`.

The `/handoff` skill's format was **not** followed: it is built for compacting a conversation so
another agent can resume *this* work, and writes to a temp directory. This is a specification for a
different project in a different repository, so it needed its own shape.

### Project identity — decided in passing, per the map's last fog patch

**Same name, same icon, separate repos, free to diverge.** Stated in §1 so the reader knows they
are not maintaining compatibility with anything.

### What assembly actually required

The eight decision tickets were resolved before the research landed, so several had been amended
after the fact. Transcribing them would have produced a document that contradicted itself.
Reconciled:

- **`libadwaita` features** — [01](01-binding-survey.md) said `v1_6` was load-bearing for theming;
  [02](02-hyprland-conventions.md) proved Omarchy publishes no accent colour. Both are true. The
  spec asks for `v1_8` (needed for `AdwShortcutsDialog` anyway), keeps `v1_6`'s API, and says in one
  sentence why it must not carry the palette — so the reader doesn't "fix" one finding with the
  other.
- **Packaging deps** — [10](10-packaging.md) resolved with three; `xdg-desktop-portal-gtk` (02) and
  `ttf-ia-writer` (16) were added later. All five are in §3, each with its reason attached, because
  a dependency without a reason gets pruned.
- **Keyboard map** — [08](08-keyboard-map.md) gained `Ctrl+Shift+R` from [14](14-edge-behaviour.md),
  the `Ctrl+C/V/X` and `Alt+Tab` reservations from 02, and `AdwShortcutsDialog` for the `?` overlay.
- **Theming mechanism** — 07's stated `StyleManager` route was replaced wholesale by
  [15](15-omarchy-palette-source.md). §6.3 documents the replacement, not the original.
- **`?` overlay timing** — 08 called it "first-milestone"; §13 lands it in M3 with the first
  shortcuts, which is what that meant.
- **`AdwTabView`** — 03 lists it as the one place the port can't be a translation; 06 deleted it
  and 02 showed Hyprland's native grouping already *is* the feature. §6.1 states the resolution.

### Deliberate omissions

- **No code.** Signatures where an API is easy to get wrong (§5's `modifiers()` returning a bare
  `u32`), not implementations.
- **The 51k/47k/37k research assets are not inlined** — §4 pins the commit SHA and the appendix
  points at `.scratch/linux-port/`. The document stands alone for building; the assets are there for
  arguing.
- **No timeline or effort estimates.** Nothing here was compiled, so any number would be fiction.

### The three things most likely to be got wrong

Foregrounded rather than buried, since a spec's reader skims:

1. **`GApplication` is single-instance by default** — without `NON_UNIQUE` the multi-process window
   model silently doesn't happen. Called out in a block quote in §6.1.
2. **`file://` base URI terminates the web process** on absolute local image paths. §5 leads with
   the custom-scheme replacement.
3. **inotify watches the inode**, so a watch on a file goes deaf after the first atomic save — which
   is what every neovim save is. §9.4, and again in §6.3 for the theme directory.
