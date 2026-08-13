# The crate set — superseded

> **➡️ Canonical asset: [crate-set.md](crate-set.md).** Use that file. This one is a stub.

This document was the first crate-set deliverable for
[Choose the Rust crate set](../issues/01-binding-survey.md), written 2026-08-13. A second pass ran
concurrently the same day, reached the same headline by the same method (crates.io + docs.rs), and
went further. The two were reconciled into `crate-set.md`, which is now the single source of truth.

**Nothing here was lost.** Everything this document had that the other lacked was merged in and
credited inline, in particular:

- **The atomic-save mechanism** — inotify watches the *inode*, so a watch on the file itself goes
  permanently deaf after the first rename-over save; watch the containing **directory** and filter
  by filename. This was stated more sharply here than in the second pass and is now
  `crate-set.md` §8's lead.
- **`gio`/`glib` arrive re-exported** via `gtk4::gio` and are not separate dependency lines. The
  second pass had listed them redundantly; corrected there on the strength of this file.
- **No dedicated print-to-PDF method** on `WebViewExt` (only `connect_print`) — recorded for
  whenever PDF export comes back into scope.
- **`webkit6` is the thinnest crate in the set** (143k downloads vs `ignore`'s 157M, 15.8%
  documented) — the residual-risk note for HANDOFF.md.
- **`notify` 9.0.0-rc.4 is in flight**; stay on stable 8.
- The Arch package table and the WebKitGTK footprint framing (130.8 MB, 71 deps, pulls the
  GStreamer stack — shared on a machine that already runs a GTK browser, not on a minimal box).
- The additional `webkit6` surface: `call_async_javascript_function`, `connect_load_changed`,
  `add_script`, `add_style_sheet`, `register_script_message_handler_with_reply`,
  `connect_context_menu`.

**Where the two differed**, `crate-set.md` records the disagreement rather than overwriting this
file's position — see its §7 (`nucleo` vs `nucleo-matcher`) and §9 (`gtk4::UriLauncher` vs the
`open` crate). Both are live choices for whoever writes HANDOFF.md.

**Corrections `crate-set.md` carries that this file did not:** `fuzzy-matcher` is formally
*archived* (not merely stale); `grep-matcher` is a required direct dependency for match-span
highlighting; `ignore`'s `require_git` defaults to `true` and must be set `false`; and `toml`
cannot emit the *commented* default config this ticket asked for.

**One claim in this file is now superseded by ticket 02**, not by the second pass: the
"`libadwaita` requires `v1_6` and this is load-bearing" framing. Omarchy publishes no accent colour
to the Settings portal at all, so the accent API has nothing to report there. `v1_6` remains the
right floor (free, harmless), but the theming decision does not stand on it. See
[hyprland-conventions.md](hyprland-conventions.md) §2.3,
[ticket 15](../issues/15-omarchy-palette-source.md), and `crate-set.md` §4.
