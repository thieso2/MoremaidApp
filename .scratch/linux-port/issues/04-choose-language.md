# Choose the implementation language

Type: grilling
Status: resolved
Blocked by: 01, 03

## Question

Given the binding survey and the WebKitGTK audit, which language does the Linux Moremaid get
written in?

The answer must state:

- The choice and the two or three findings that decided it.
- The **runtime dependency footprint** it implies on Arch, and expected cold-start time.
- The **build system** it drags along (cargo / meson / setuptools / …) — this feeds the packaging
  ticket.
- The two or three things this choice makes *harder* than the runner-up would have, so the
  HANDOFF.md reader knows where the friction will be rather than discovering it.
- Whether any of the platform-independent Swift logic (`FuzzyMatcher`, `ContentSearch`,
  `GitignoreParser`, `HeadingParser`, `MermaidValidator`) can be carried over mechanically or must
  be rewritten from behaviour.

Record it in a form HANDOFF.md can quote more or less directly — this is the sentence the Linux
session reads first.

## Answer

**Rust, with `gtk4-rs` + `libadwaita-rs` + `webkit6-rs`.**

Chosen over the Ruby/Python hackability case, decided ahead of the binding survey.

**What decided it.** Cold start is non-negotiable for a viewer that is invoked from a terminal
dozens of times a day — an interpreted runtime plus GTK plus WebKitGTK is a gamble on the one
property that most determines whether the app feels native. A single binary is also the cleanest
thing to hand a `PKGBUILD`, and `gtk4-rs` / `webkit6-rs` are the best-maintained GTK4 bindings
outside C, which matters enormously for an agent implementing solo with no hardware to test on.

**Runtime footprint on Arch:** `gtk4`, `libadwaita`, `webkitgtk-6.0`. Build-time only: `rust`
(`cargo`). No interpreter, no runtime dependency tree beyond the toolkit itself.

**Build system:** cargo. The `PKGBUILD` runs `cargo build --release` and installs one binary plus
a data directory.

**What this makes harder than Ruby or Python would have:**

1. **A build step now exists, so the app's own source is no longer user-editable** — the single
   strongest argument for an interpreted language on this desktop, and it is genuinely lost.
   Partially compensated by a deliberate choice in the rendering-layer ticket: the web assets ship
   as **data files** under `/usr/share/moremaid/web/` with an `$XDG_DATA_HOME` override, *not*
   baked in with `include_str!`. A user who wants to change how markdown renders still can, without
   a compiler. That is the hackability that survives, and it is preserved on purpose.
2. **GTK's C-flavoured object model through Rust ownership is verbose.** Expect more lines than the
   SwiftUI original for the same UI, and expect the sidebar's lazy list model to be the fiddliest
   part.
3. **Slower iteration for an agent with no hardware.** Compile errors are the only feedback loop.
   They are the good kind of error, but the cycle is minutes rather than seconds.

**Swift reuse: none.** All five platform-independent files are rewritten — but three of them
(`FuzzyMatcher`, `ContentSearch`, `GitignoreParser`) disappear into crates rather than being
rewritten at all, so choosing Rust deletes more code than it forces to be retyped. See the
[port map](11-module-port-map.md).

**Consequence for the map:** this supersedes the Ruby proposal in
[the Omarchy-idiom pass](../assets/dhh-pass.md). The
[binding survey](01-binding-survey.md) is re-scoped from "which language" to "which crates, and
confirm `webkit6-rs` covers the bridge".
