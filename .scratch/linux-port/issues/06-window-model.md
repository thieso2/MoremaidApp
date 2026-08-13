# Decide the window, tab and session model under a tiling compositor

Type: grilling
Status: resolved
Blocked by: 02

## Question

macOS Moremaid is multi-window with native macOS tabs, session restore, ⌘N / new tab, and a
`WindowGroup(for: OpenTarget.self)` that focuses an existing window when the same target is
opened again. Under Hyprland the **compositor owns tiling, workspaces and grouping** — in-app
tabs may be redundant, and a Wayland client cannot raise or position its own windows.

Decide:

- **One window per target, or a tabbed shell?** If tabs, `AdwTabView` or the compositor's own
  grouping — pick one and justify it against how Omarchy users actually work.
- **Does session restore exist at all?** macOS persists `savedWindowSessions` and reopens windows
  on launch. Under a tiler where the compositor may itself restore layouts, is this wanted?
- **What replaces "focus the existing window for this file"?** Wayland forbids self-raising;
  `xdg-activation` is the partial answer. Decide the behaviour when `moremaid README.md` is run
  for a file already open.
- **Single-instance or multi-process?** Does a second launch talk to the running instance
  (GApplication single-instance) or spawn its own process? This interacts with everything above.
- **The Mermaid diagram window.** macOS opens a full-screen diagram in its own native window
  (`DiagramWindowController`). In a tiler, is that a new toplevel, an in-app overlay, or dropped?

The answer sets the shape of the app shell, so state it concretely enough to build from.

## Answer

**The compositor owns windows. The app owns none of it.**

- **One window per invocation. No in-app tabs.** `AdwTabView` would reimplement, worse, the thing
  Hyprland already does well — and it would put two competing systems for arranging documents in
  front of the user at once. `moremaid a.md` and `moremaid b.md` produce two windows; Hyprland
  tiles them, groups them, and moves them across workspaces. That *is* the tab feature, and it is
  already written.

- **No session restore.** `savedWindowSessions` is deleted rather than ported. Reopening windows
  at launch is the compositor's and session manager's business on this desktop, and guessing at a
  tiling user's layout is a good way to be wrong loudly, every morning.

- **No "focus the existing window for this target".** Wayland forbids clients from raising
  themselves, `xdg-activation` is a partial and awkward workaround, and the honest behaviour is to
  open another window. The user asked for the file; give them the file.

- **Multi-process, not single-instance.** Each invocation is its own process: no IPC, no shared
  mutable state, crashes isolated to one document. **The cost is real and HANDOFF.md must state
  it** — every window carries its own WebKitGTK, so ten open documents means ten web processes and
  a few hundred MB. The retreat, if that proves intolerable in practice, is a single `GtkApplication`
  owning several toplevels; that is a contained refactor, not a rewrite. Start simple and measure.
  Rust's fast start is part of why the simple option is affordable here.

- **The Mermaid diagram window is a new toplevel**, not an in-app overlay. Same reasoning: hand it
  to the compositor and it tiles, floats or goes fullscreen according to rules the user already
  wrote for themselves.

**What this deletes from the port:** `AdwTabView` (never built), `savedWindowSessions`, window
de-duplication, and most of `OpenTarget` — the `.empty(UUID)` case exists only to give each new tab
a unique value, and there are no tabs.

Rests on [Hyprland conventions](02-hyprland-conventions.md) for the decoration question — whether
the window draws an `AdwHeaderBar` at all or goes bare and lets Hyprland draw the border. That
research now **confirms or reopens** this decision rather than feeding it.
