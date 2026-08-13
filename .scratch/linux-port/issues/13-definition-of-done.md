# Set the performance targets and test strategy

Type: grilling
Status: resolved
Blocked by: —

> Graduated from the map's fog 2026-08-13, once [the language decision](04-choose-language.md)
> made both halves specifiable.

## Question

Rust was chosen over the more hackable alternatives **specifically because cold start is
non-negotiable** — and nothing on this map has yet said what that means in numbers. An unquantified
non-negotiable is a preference. Fix it.

- **Performance targets.** Cold start to a rendered document. Time to first paint for a 50-line
  README vs a 5000-line document. Directory scan time for a tree with 10k files. Mermaid render
  time for a large diagram. Memory per window, given the multi-process model puts a WebKitGTK
  behind every one. Each target needs a number and a way to measure it, or the Linux session will
  ship something that feels slow and have no basis to call it a regression.
- **What "feels native" is measured by**, beyond raw speed: does the window appear before content
  is ready or after? Is there a flash of unstyled content on load? What happens on a theme switch —
  does the page visibly relayout?
- **Test strategy.** What is worth testing in a GTK app with no hardware in the loop: the pure
  logic (heading slugs, fuzzy ranking, config parsing, Mermaid validation) is straightforwardly
  unit-testable; the shell largely isn't. Decide what is covered, what is explicitly not, and
  whether anything runs in CI on Arch.
- **The `HeadingParser` fixture specifically.** The port map flags that the Rust slugify and the JS
  slugify in `PageScripts.swift` must agree or anchor links silently break. Decide the mechanism:
  a shared fixture file of heading→slug pairs, tested on both sides. Where does it live, and what
  makes anyone re-run it?

Output: the "definition of done" section HANDOFF.md carries per milestone.

## Answer

### Performance targets

Every number below is a **target to verify, not a measured fact** — nothing on this map was ever
compiled. Milestone 1's definition of done includes measuring the first one and writing the real
figure back into the spec.

| what | target | how it's checked |
|---|---|---|
| **Cold start → painted document** | **≤300 ms** | `moremaid README.md` from a shell, wall clock |
| Small doc (50 lines) vs large (5000) | delta **≤100 ms** | document size must not dominate; markdown-it is fast and the parse is not the cost |
| Directory scan, 10k-file tree | **first rows ≤100 ms**, complete **≤1 s** | `ignore`'s parallel walker, streamed over `async-channel` — the user sees rows immediately, not after |
| Quick Open keystroke → filtered list | **≤16 ms** (one frame) at 10k entries | what `nucleo-matcher` exists for |
| Find in Files, 10k files | **first match ≤200 ms**, streamed | `grep-searcher` in-process, results as found |
| Mermaid, 100-node diagram | **≤1 s** | the audit confirms cost scales ~3–5× per +20 nodes; this is Mermaid's own property, engine-independent |
| Memory per window | **measure and record**; **>400 MB is a red line** | one WebKitGTK per window is the accepted cost of [the window model](06-window-model.md). Crossing the red line is the signal to reconsider it in favour of single-instance, which that ticket already names as the contained retreat |

**≤300 ms is the load-bearing one.** [Rust was chosen over more hackable
languages](04-choose-language.md) specifically because cold start is non-negotiable, and until now
nothing had put a number on it — an unquantified non-negotiable is a preference. Missing it is a
bug to fix before release, not a release blocker; but if WebKitGTK's process spawn turns out to
make it structurally unreachable, that is a finding that reopens [the window
model](06-window-model.md), not a number to quietly relax.

### The Mermaid pathology — fix it in the port, don't inherit it

The macOS app renders diagrams in a sequential `await` loop and **re-renders every diagram on every
live-reload tick**. The [WebKitGTK audit](03-webkitgtk-audit.md) flags this as already the app's
worst performance characteristic on macOS, and expects WebKitGTK to be *slower* here, not faster.
Porting it faithfully would ship a known regression.

**Hash each diagram's source; on reload, re-render only diagrams whose source changed and reuse
cached SVG for the rest.** This turns the common case — editing prose in a document full of
diagrams — from "re-render all of them" into "re-render none of them".

Viewport-lazy rendering (IntersectionObserver) was **considered and not taken**: it helps first
paint on a 30-diagram document but adds pop-in and meaningfully complicates the JS being ported.
Revisit only if the ≤1 s target fails on real documents.

### What "feels native" means beyond speed

Four binary properties, each either true or false, no measurement needed:

1. **No flash of the wrong colours, ever.** Guaranteed structurally: [the palette is read
   synchronously before first paint](15-omarchy-palette-source.md), so the very first pixel is
   already the user's theme.
2. **No flash of unstyled content.** All CSS is inline in the document handed to `load_html`.
3. **A theme switch does not relayout or jump.** Custom properties are updated in place via
   `evaluate_javascript`; the page is never reloaded, so scroll position survives.
4. **No splash screen, no progress window, no empty window waiting for content.** If the document
   isn't ready, the window isn't mapped yet.

### Test strategy

**Unit tests on the pure logic** — heading slugs, fuzzy ranking, config parsing, palette derivation
and per-key fallback, Mermaid validation, walk/ignore behaviour. All of it is plain Rust with no
toolkit involved, which is most of what can go quietly wrong.

**Golden snapshots of the generated HTML.** `HTMLGenerator`'s output is a string; snapshot it
against committed `.html` fixtures. This catches rendering-layer regressions — a dropped CSS
variable, a mangled asset path, a broken template substitution — with no GUI and no compositor.

**A headless smoke test under `cage`/`weston --headless` was considered and rejected**: real
end-to-end signal, but it drags a compositor and a display socket into the loop for a project with
no CI to run them in.

### The `HeadingParser` ↔ JS slugify coupling

`HeadingParser` (Rust, for the Navigator, which shows headings for files not loaded in any webview)
and the slugify in `PageScripts` (JS, which assigns the actual anchor ids) must produce identical
slugs or in-document links break for exactly the headings nobody tested.

**One shared fixture, run by both sides.** `tests/fixtures/slugs.json` holds heading→slug pairs
including the nasty cases (punctuation, emoji, duplicates needing `-1` suffixes, non-ASCII, inline
code, links inside headings). A Rust test runs it; a small JS test runs the same file through the
*shipped* `slugify` under node.

**Node is a test-only dependency and does not violate [the no-build-step
decision](05-rendering-layer-strategy.md)** — nothing is compiled, bundled, or npm-installed; a
script is executed against a fixture.

Making Rust the sole slugifier (passing slugs into the page) was **considered and rejected**: it
removes the duplicated algorithm but replaces it with a worse, *untested* coupling — Rust and
markdown-it must then agree on which lines are headings at all, and a `#` inside a fenced code block
misaligns the zip and breaks every anchor after it.

### CI: none

Tests run locally. Nothing is automated, nothing is maintained, and **nothing forces the suite to
run** — that is the accepted cost of a solo project on a distribution the author already runs.

Two consequences the spec must carry so this doesn't rot silently:

- The README documents `cargo test` **and** `node tests/slugs.test.js` as the two commands, since
  the JS half won't run under `cargo test` and is therefore the half that will be forgotten.
- [Packaging](10-packaging.md) cuts releases from git tags. **The release checklist includes running
  both**, because a tag is the last moment anyone will think about it.

### Definition of done, per milestone

HANDOFF.md carries this as its build plan. **Milestone 1 is something that runs**, not something
that is architecturally complete.

| # | milestone | done when |
|---|---|---|
| **1** | **It opens a file.** Window, WebKitGTK, custom URI scheme serving the vendored assets, one markdown file rendered with Prism and Mermaid, palette read from `colors.toml`. | `moremaid README.md` shows a correctly themed rendered document — **and cold start has been measured and the real number written back into the spec.** |
| **2** | **It browses.** Directory open, Navigator sidebar over a lazy list model, heading extraction, internal `.md` link navigation, external links via the portal. | A real repo's docs tree is navigable; the scan targets are met on a 10k-file tree. |
| **3** | **It finds things.** Quick Open and Find in Files, both streamed incrementally — **and the `?` shortcuts overlay.** | Keystroke latency target met at 10k files. The overlay ships *with* the first shortcuts, never after them, which is what [the keyboard map](08-keyboard-map.md) meant by calling it a first-milestone item: with no menu bar it is the only discoverability the app has. |
| **4** | **It's live.** File watching (parent-directory watch, debounced), live reload with the diagram cache, theme watching. | Two binary invariants hold: a prose-only edit re-renders **zero** diagrams, and a theme switch preserves scroll position. |
| **5** | **It ships.** `config.toml`, `.desktop` + MIME association, `PKGBUILD`, README. | Installs from the AUR on a clean Omarchy box and opens a `.md` file handed over by a file manager. |
