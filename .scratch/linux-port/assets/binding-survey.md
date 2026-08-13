# Language binding survey: GTK4 + libadwaita + WebKitGTK 6.0 on Arch

Research asset for [issues/01-binding-survey.md](../issues/01-binding-survey.md).
Date: 2026-08-13. **Paper research only — no Linux box was available, nothing here was compiled
or measured.** Every claim is tagged **[confirmed]** (with a link) or **[inferred]**.

This is a *comparison*, not a recommendation. The choice is
[issues/04-choose-language.md](../issues/04-choose-language.md).

---

## 0. The Arch baseline (all findings are measured against these versions)

| Package | Version | Installed size | Source |
|---|---|---|---|
| `webkitgtk-6.0` | 2.52.5-2 | **130.8 MB**, 71 deps | [archlinux.org][arch-wk] |
| `gtk4` | 1:4.22.4-1 | — | [archlinux.org][arch-gtk4] |
| `libadwaita` | 1:1.9.3-1 | 5.2 MB, 16 deps | [archlinux.org][arch-adw] |
| `vala` | 0.56.19-1 | — | [archlinux.org][arch-vala] |
| `python-gobject` | 3.56.3-1 | 1.5 MB | [archlinux.org][arch-pygobject] |
| Swift | **not in any official repo** — AUR `swift-bin` (6.3.x) only | — | [AUR][aur-swift-bin] |

All **[confirmed]**. Arch does not split `-dev` packages, so headers, `.pc` files, `.gir` and
`.typelib` all ship in the runtime package — one `pacman -S` gets you a build environment for
every candidate except Swift. **[inferred from Arch packaging convention; the file lists below
confirm the `.gir`/`.typelib`/`.vapi` half directly]**

**The six WebKit APIs the port needs all exist in the WebKitGTK 6.0 C API** —
`webkit_web_view_load_html`, `webkit_web_view_set_zoom_level`, `webkit_web_view_get_settings`,
`webkit_web_view_get_user_content_manager`, `webkit_web_view_evaluate_javascript`, and the
`decide-policy` signal are all documented on the 6.0 `WebKitWebView` class page
([webkitgtk.org][wk-webview]) **[confirmed]**. `webkit_web_context_register_uri_scheme` /
`WebKitURISchemeRequest` likewise. So the question is never "does the API exist" — it is
"does *this language's* binding reach it".

---

## 1. Summary comparison

| | **Rust** (gtk4-rs + webkit6-rs) | **Vala** | **Python** (PyGObject) | **C** | **Swift** |
|---|---|---|---|---|---|
| **WebKit 6 API coverage** | Complete, typed, all 6 APIs verified | Complete (GIR-generated vapi) | Complete (GIR at runtime) | Reference impl — by definition complete | **Effectively none.** One 3rd-party 150-line wrapper; 5 of 6 APIs missing |
| **libadwaita coverage** | crate 0.9.2 supports up to **1.10** > Arch's 1.9.3 | vapi ships *with* libadwaita — always in lockstep | typelib ships with libadwaita — always in lockstep | native | ~74 auto-generated Adw widgets in an 8-star project; or hand-rolled |
| **Binding freshness vs Arch** | **Ahead** | **Exact** | **Exact** | **Exact** | Behind / partial |
| **Extra runtime deps beyond the GTK/WebKit stack** | none (static Rust binary) | none (compiles to C) | `python`, `python-gobject` (~1.5 MB + interpreter) | none | Swift runtime libs, **not packaged in Arch repos** |
| **Concurrency** | `gio::spawn_blocking` + `async-channel` + `glib::spawn_future_local`; borrow checker enforces the main-thread rule | GLib threads + `Idle.add`; `async` keyword over the GLib main loop | Python threads + `GLib.idle_add`; PyGObject **releases the GIL** on C calls | GLib threads + `g_idle_add` / `GTask` | Swift concurrency exists on Linux; bridging it to the GLib main loop is unsolved work |
| **Non-UI ecosystem** | Best in class (`ignore`, `nucleo`, `notify`, `walkdir`, `zip`, `tantivy`) | Thin — mostly GLib + hand-rolled | Good (`pathspec`, `rapidfuzz`, `watchdog`, `os.scandir`, `zipfile`) | GLib only — hand-rolled | Foundation only; would reuse the existing Moremaid code |
| **Agent-implementability @ ~8–10k lines** | High: strong errors, large public corpus, official book | Medium-low: small corpus, errors can surface as C errors in generated code | High to write, **low to verify** — no compile step; errors are runtime `AttributeError` | Medium: verbose (~2–3× lines), memory bugs are silent | Low: the agent would be writing the binding layer as well as the app |
| **Real apps on Arch shipping this exact stack** | `newsflash`, `read-it-later` | `tuba`, `capnet-assist` | **`apostrophe`** (a markdown editor with a WebKit preview), `iotas`, `gfeeds`, `wike`, `komikku`, `setzer` | `epiphany`, `gnome-builder`, `bazaar` | **none found** |

---

## 2. The constant nobody escapes: WebKitGTK dominates the footprint

`webkitgtk-6.0` is **130.8 MB installed with 71 dependencies**
([Arch package page][arch-wk]) **[confirmed]**. Every candidate language pulls exactly that.
The delta between the heaviest realistic choice (Python: interpreter + `python-gobject`, roughly
tens of MB) and the lightest (C/Vala: zero extra) is **single-digit percent of the total install**
**[inferred from the package sizes above]**.

The same logic probably applies to cold start. A datapoint: a Rust crate on crates.io named
`hwatud` describes itself as a *"Daemon for hwatu: warm WebKitGTK engine with prewarmed WebViews
for ~13ms window spawn"* ([crates.io reverse-deps of `webkit6`][crates-rdeps]) **[confirmed the
crate says this; the 13ms figure is the author's claim, unverified]**. Somebody built a
prewarming daemon, which is strong circumstantial evidence that **WebView construction, not
language runtime startup, is the thing that costs time** **[inferred]**.

**Consequence for the ticket's "1.5s to show a file has failed at feels-native" bar:** the
language choice is probably second-order to the rendering strategy (does the app spawn a fresh
`WebKitWebView` per window/tab? does it reuse one? does it prewarm one at startup?). That is a
[rendering-layer ticket](../issues/) question more than a language question. **[inferred —
this is the single most load-bearing inference in this document and it is unmeasured.]**

Python is the only candidate where the language runtime plausibly adds a *visible* fixed cost
(interpreter boot + `import gi` + typelib load). I could **not** find a published measurement
**[not confirmed]**. What would settle it: `hyperfine` on an Arch box comparing a
hello-world GTK4 window in each language.

---

## 3. Rust — gtk4-rs + webkit6-rs

### WebKit 6 binding completeness — **complete, and verified method-by-method**

`webkit6` **0.6.1**, released 2026-03-11, maintained by Bilal Elmoussaoui (a GNOME
Foundation-adjacent maintainer), feature flags up to **`v2_52`** — matching Arch's 2.52.5
([lib.rs][librs-webkit6]) **[confirmed]**. ~35k downloads/month.

Every API the ticket names, checked against docs.rs:

| Needed API | Rust binding | Source |
|---|---|---|
| `webkit_web_view_load_html` | `fn load_html(&self, content: &str, base_uri: Option<&str>)` | [WebViewExt][rs-webviewext] **[confirmed]** |
| script message handlers | `UserContentManager::register_script_message_handler(&self, name, world_name) -> bool` + `connect_script_message_received<F: Fn(&Self, &Value)>(...)` | [UserContentManager][rs-ucm] **[confirmed]** |
| URI scheme handler | `WebContext::register_uri_scheme<P: Fn(&URISchemeRequest)>(&self, scheme, callback)`; `URISchemeRequest` and `URISchemeResponse` both exported | [WebContext][rs-webcontext], [all items][rs-all] **[confirmed]** |
| `decide-policy` | `connect_decide_policy<F: Fn(&Self, &PolicyDecision, PolicyDecisionType) -> bool>` ; `NavigationPolicyDecision`, `ResponsePolicyDecision`, `NavigationAction` all exported | [WebViewExt][rs-webviewext], [all items][rs-all] **[confirmed]** |
| zoom | `set_zoom_level(f64)` / `zoom_level() -> f64` | [WebViewExt][rs-webviewext] **[confirmed]** |
| settings | `settings() -> Option<Settings>` / `set_settings(&Settings)`; `Settings` struct exported | [WebViewExt][rs-webviewext] **[confirmed]** |
| bonus (Moremaid uses it heavily) | `evaluate_javascript(script, world_name, source_uri, cancellable, callback)`; `FindController` also exported | **[confirmed]** |

Nothing on Moremaid's list is missing. The one caveat: docs.rs reports **"15.83% of the crate is
documented"** **[confirmed]** — the *bindings* are complete (they are GIR-generated), the *prose*
is not. An agent will be reading the C docs on webkitgtk.org and translating naming conventions.
**[inferred that this is a manageable friction, not a blocker — the GIR naming convention is
mechanical: `webkit_web_view_load_html` → `WebViewExt::load_html`.]**

### libadwaita coverage

`libadwaita` crate **0.9.2** (2026-07-07) with feature flags `v1_1` … **`v1_10`**
([lib.rs][librs-adw]) **[confirmed]**. Arch ships **1.9.3**. The binding is *ahead* of the
distro, which is the comfortable direction. `gtk4` crate **0.11.4** (2026-06-29), feature flags
to **`v4_22`**, MSRV 1.83 ([lib.rs][librs-gtk4]) **[confirmed]** — again matching Arch's 4.22.4
exactly.

### Runtime footprint

Zero extra runtime deps beyond the C stack; a Rust binary links `libgtk-4.so`, `libadwaita-1.so`,
`libwebkitgtk-6.0.so` dynamically and statically links its own crates. **[inferred from standard
Rust/gtk-rs linkage; not measured.]** Binary size for an 8–10k-line GTK4 app: unmeasured, but
NewsFlash is a comparable real-world reference point. **[not confirmed]**

The compile-time cost is real and unmeasured: gtk4-rs + webkit6-rs is a large dependency tree.
An agent iterating on a Linux box will feel this. **[inferred]**

### Concurrency

The gtk4-rs book's main-event-loop chapter is explicit **[confirmed]**:
- GTK GObjects are **not** `Send`/`Sync` — touching a widget from another thread is a *compile
  error* about `NonNull<GObject>` not being `Sync`, not a runtime crash.
- Recommended: `gio::spawn_blocking()` for CPU/IO-heavy work on a thread pool,
  `async-channel` to report results back, `glib::spawn_future_local()` to run futures on the
  main loop. Tokio integration via a `OnceLock<Runtime>` + channels is documented for crates
  that demand it.

This maps cleanly onto Moremaid's model (`FileScanner` on a background `DispatchQueue` →
`gio::spawn_blocking`; `AsyncStream<FileChangeEvent>` from `FileWatcher` → `async-channel`
consumed by `spawn_future_local`). **[inferred mapping — the primitives are confirmed, the
mapping is my analysis.]**

### Non-UI ecosystem

Strongest of any candidate, and several crates are *better* than what Moremaid hand-rolls today:

| Need | Crate | Status |
|---|---|---|
| gitignore + recursive walk | **`ignore`** 0.4.33 (2026-08-04, BurntSushi / ripgrep) — handles `.gitignore`, `.ignore`, file-type filters, and `WalkParallel` for parallel walking | [docs.rs][rs-ignore] **[confirmed]**. Replaces both `GitignoreParser.swift` (98 lines) and much of `FileScanner.swift` (214 lines). |
| fuzzy matching | **`nucleo` / `nucleo-matcher`** — the matcher behind Helix; "~6× faster than skim/fuzzy-matcher"; designed to match on a background threadpool and hand the UI a snapshot without blocking | [docs.rs][rs-nucleo] **[confirmed]**. Replaces `FuzzyMatcher.swift` (112 lines) and is architecturally a better fit for QuickOpen than a synchronous matcher. |
| file watching | `notify` (inotify) | **[inferred — widely used, not verified this session]** |
| dir walking (plain) | `walkdir` | **[inferred]** |
| ZIP (out of v1 scope) | `zip` crate | **[inferred]** — noted per the ticket; not needed for v1. |
| full-text search | `tantivy` if an index is ever wanted; for Moremaid's actual Find-in-Files (grep-style, no index) `grep-searcher`/`memchr` or plain iteration suffice | **[inferred]** |

### Agent-implementability

**High. [inferred, with confirmed supporting signals.]**
- Official book with a dedicated main-event-loop/concurrency chapter ([gtk-rs.org][rs-book])
  **[confirmed it exists]**.
- Compile-time enforcement of the main-thread rule turns the single most likely class of GTK bug
  (touching widgets off-thread) into a compile error.
- The known friction: GObject subclassing in Rust (`glib::wrapper!`, `ObjectSubclass`,
  `#[properties]`) is heavy boilerplate that an agent will get wrong repeatedly before getting
  it right. **[inferred]** Moremaid needs custom widgets for the Navigator, so this is unavoidable.
- Real shipping references to read: `newsflash` (Rust + GTK4 + libadwaita + webkitgtk-6.0, Tokio
  backend, in Arch's `webkitgtk-6.0` reverse-deps as a makedepend) and `read-it-later`
  ([Arch required-by list][arch-wk], [OMG Ubuntu on the GTK4 port][omg-newsflash]) **[confirmed
  they exist and use this stack; I did not read their source]**.

---

## 4. Vala

### WebKit 6 binding completeness — **complete, via a vapi that ships in the `vala` package**

Important detail: `webkitgtk-6.0` **does not ship its own `.vapi`** — its file list contains
`WebKit-6.0.gir` and `WebKit-6.0.typelib` but no vapi ([Arch file list][arch-wk-files])
**[confirmed]**. The vapi lives in the **`vala` package itself**:
`webkitgtk-6.0.vapi`, `webkitgtk-web-extension-6.0.vapi`,
`webkitgtk-web-process-extension-6.0.vapi`, plus `gtk4.vapi`, `gtk4-wayland.vapi`
([Arch `vala` file list][arch-vala-files]) **[confirmed]**.

Because the vapi is GIR-derived, coverage is the C API's coverage. `WebKit.WebView` is documented
on valadoc ([valadoc webkitgtk-6.0][valadoc-wk]) **[confirmed]**. I did **not** individually
verify all six APIs in the vapi the way I did for Rust — **[not confirmed]** — but the mechanism
(GIR → vapi) makes gaps unlikely, and any gap is fixable in-project by hand-writing a vapi
fragment.

⚠️ **The version-skew risk is real and specific to Vala's packaging shape.** The webkit vapi is
versioned with `vala` (0.56.19), not with `webkitgtk-6.0` (2.52.5). If Arch bumps WebKit ahead of
a Vala release, new APIs are missing until Vala catches up. **[inferred from the packaging
layout confirmed above.]** By contrast `libadwaita-1.vapi` **does** ship inside the `libadwaita`
package ([Arch file list][arch-adw-files]) **[confirmed]**, so libadwaita coverage is always in
exact lockstep with the installed version — no skew there.

### Runtime footprint

Vala compiles to C and links the same libraries — **identical to C, zero language runtime**
**[confirmed by construction: Vala is a C code generator]**.

### Concurrency

GLib threads + `Idle.add` to return to the main loop, plus Vala's `async`/`yield` keywords which
compile down to GLib's callback-based async model. **[inferred — standard GLib/Vala practice;
I did not verify against a specific doc page this session.]** No compile-time protection against
touching widgets off-thread.

### Non-UI ecosystem

**Thin.** There is no Vala equivalent of `ignore` or `nucleo`. Everything non-UI is either GLib
(`GLib.Dir`, `GLib.Regex`, `GLib.FileMonitor`) or hand-rolled, or a C library bound through a
vapi. **[inferred — no Vala package registry of consequence exists; Vala's model is "bind the C
library".]**

Mitigating: Moremaid already hand-rolls the pieces that matter. `FuzzyMatcher.swift` is 112
lines, `GitignoreParser.swift` is 98 lines. Re-implementing them in Vala is a day's work, not a
blocker. **[confirmed line counts from this repo.]** ZIP would come from `libarchive` or
`gsf` via vapi — out of v1 scope anyway.

### Agent-implementability

**Medium-low. [inferred, with one confirmed hazard.]**

The confirmed hazard: **Vala errors can surface as C compiler errors against generated code.**
Community reports describe *"awful compiler errors about the C code"* that are hard to relate
back to Vala source, and note that generated C is poorly debuggable — *"similar to trying to
debug C but only being able to see the assembly output"* ([GNOME Discourse][vala-discourse],
[Vala debugging docs][vala-debug]) **[confirmed that these reports exist; I have not
independently assessed severity on current 0.56.19]**.

For an agent working solo this is the specific worry: an agent's main feedback loop is compiler
output. A language whose errors sometimes point at machine-generated intermediate code degrades
that loop badly.

Secondary concern: **training-corpus size.** Vala's public code corpus is far smaller than
Rust's, Python's, or C's. **[inferred]**

Maintenance signal: Vala has sat on the **0.56.x LTS line** for years (0.56.19 current on Arch,
Debian accepted 0.56.19-1 in March 2026) ([vala.dev][vala-site], [Debian tracker][vala-debian])
**[confirmed the version; "sat for years" is inferred from 0.56 being described as the current
LTS across multiple 2026-dated sources]**. Steady, not dying — but not moving.

Real shipping references: `tuba` (Mastodon client) and `capnet-assist`, both in Arch's
`webkitgtk-6.0` required-by list ([Arch][arch-wk]) **[confirmed they depend on it; that they are
Vala is **[inferred]** from project reputation, not verified this session]**.

---

## 5. Python — PyGObject

### WebKit 6 binding completeness — **complete, at runtime, untyped**

PyGObject reads `WebKit-6.0.typelib` at runtime via GIRepository + libffi
([pygobject.gnome.org][pygobject-overview]) **[confirmed]**. `webkitgtk-6.0` ships that typelib
([Arch file list][arch-wk-files]) **[confirmed]**. GNOME publishes a rendered WebKit-6.0 Python
API reference including `UserContentManager` ([api.pygobject.gnome.org][pygobject-ucm])
**[confirmed]**.

```python
import gi
gi.require_version("WebKit", "6.0")
from gi.repository import WebKit
```

Because it is typelib-driven, **binding coverage is exactly the installed library's coverage,
always, with zero lag** — the single strongest structural argument for PyGObject. **[confirmed
by mechanism.]** Same for libadwaita: `Adw-1.typelib` ships with `libadwaita`
([Arch file list][arch-adw-files]) **[confirmed]**, so Adw coverage is always exactly 1.9.3.

The cost of the same mechanism: **nothing is checked until it runs.** A misspelled method or a
wrong-arity call is an `AttributeError`/`TypeError` at the moment that code path executes, not
at build time.

### Runtime footprint

`python-gobject` 3.56.3-1, 1.5 MB installed, depends on `gobject-introspection-runtime`, `glib2`,
`libffi`, `python` ([Arch][arch-pygobject]) **[confirmed]**. Plus CPython itself. Against
WebKit's 130.8 MB this is small on disk; the concern is **startup latency**, which I could not
find any published measurement for **[not confirmed]**. Interpreter boot + `import gi` +
typelib load is the one place a language runtime plausibly adds visible fixed cost to Moremaid's
"open a file, see it rendered" path. **[inferred]**

### Concurrency

Documented and unambiguous ([PyGObject threading guide][pygobject-threads]) **[confirmed]**:
- *"GTK isn't thread safe; only one thread, the main thread, is allowed to call GTK code at all
  times."*
- Pattern: Python `threading` for blocking work (file IO, scanning), `GLib.idle_add()` to hand
  results back to the main thread.
- **Crucially: *"all PyGObject calls release the GIL during their execution and other Python
  threads can be executed during that time."*** So the GIL does **not** serialize the GTK/WebKit
  calls — but it *does* serialize pure-Python work, which is what a directory scanner and a
  fuzzy matcher mostly are. **[the GIL-release quote is confirmed; the consequence for
  CPU-bound Python scanning is inferred.]**
- `Gdk.threads_init()`/`enter()`/`leave()` are obsolete and should not appear. **[confirmed]**

Mitigation if scanning proves too slow in pure Python: push the hot loop into a C-accelerated
library (`os.scandir` is already C; `rapidfuzz` is C++). **[inferred]**

### Non-UI ecosystem

Good, all mature, all `pacman`- or `pip`-installable **[inferred — I did not verify Arch package
availability for each]**:

| Need | Library |
|---|---|
| gitignore | `pathspec` (the library `black`/`pre-commit` use for gitignore semantics) |
| fuzzy matching | `rapidfuzz` (C++ backed) or `thefuzz` |
| dir walking | stdlib `os.scandir` / `os.walk` / `pathlib` |
| file watching | `watchdog` (inotify) |
| ZIP (out of v1 scope) | stdlib `zipfile`, including AES via `pyzipper` |
| full-text search | stdlib `re` over `mmap` is likely enough for Moremaid's grep-style Find-in-Files; `whoosh`/`tantivy-py` if an index is ever wanted |

⚠️ Non-stdlib Python deps complicate the **PKGBUILD**: each becomes an Arch dependency (available
in `extra`/AUR or not) or gets vendored. This is a packaging-ticket problem, not a language
problem, but it is real and it is unique to Python among the candidates. **[inferred]**

### Agent-implementability

**Easiest to write; hardest to be confident in. [inferred.]**

- Python + GTK4 has the largest and most tutorial-rich corpus of the four. PyGObject publishes a
  full GTK4 tutorial ([pygobject.gnome.org][pygobject-gtk4]) **[confirmed]**.
- No compile step means no compiler feedback. For ~8–10k lines written largely unattended, an
  agent's confidence that "it builds" is worth nothing here; correctness has to come from
  actually running every path. **[inferred — this is the central tradeoff.]**
- Mitigations exist (`mypy` + `PyGObject-stubs`, `ruff`) but coverage of dynamically-generated
  gi bindings by stubs is partial. **[inferred, not verified.]**

**Strongest real-world reference of any candidate:** **Apostrophe** — a GNOME markdown editor,
written in Python/PyGObject, using WebKitGTK for its preview pane, hosted in GNOME World,
packaged in Arch, and in `webkitgtk-6.0`'s required-by list ([GNOME GitLab][apostrophe],
[Arch][arch-wk]) **[confirmed it exists and matches this description]**. It is close to
Moremaid's exact shape. Also on the list: `iotas`, `gfeeds`, `wike`, `komikku`, `setzer` —
Python is by count the **most common** language among Arch packages depending on
`webkitgtk-6.0`. **[the required-by list is confirmed; the per-package language attribution is
inferred from project reputation.]**

---

## 6. C

### WebKit 6 binding completeness

Not a binding — the reference implementation. Coverage is 100% by definition, documentation is
first-class ([webkitgtk.org API reference][wk-webview]) **[confirmed]**, and every other
language's docs are a translation of these.

Same for libadwaita and GTK4: C is what the Arch package *is*.

### Runtime footprint

Minimal — no language runtime. **[confirmed by construction.]**

### Concurrency

`GThread`/`GTask`/`GThreadPool` + `g_idle_add()` to return to the main loop; `GFileMonitor` for
watching. No safety net whatsoever for the main-thread rule. **[inferred — standard GLib
practice.]**

### Non-UI ecosystem

GLib and nothing else, realistically. `GRegex`, `GDir`, `GHashTable`, `GFileMonitor` cover the
primitives; gitignore semantics, fuzzy matching, and content search are all hand-written.
**[inferred]** Same mitigating point as Vala: Moremaid's versions of these are 98 and 112 lines.

### Agent-implementability

**Medium, and the risks are asymmetric. [inferred.]**
- Upside: enormous corpus, the best documentation of any candidate, and every GTK/WebKit example
  on the internet is already in C — an agent never has to translate an idiom.
- Downside 1: **line count.** ~8–10k lines in Rust/Vala is plausibly 2–3× that in C once
  GObject boilerplate, manual string handling, and manual memory management are counted.
  A 20–30k-line C codebase is a materially different project.
- Downside 2: **silent failure modes.** Use-after-free, refcount leaks, and off-thread widget
  access all compile cleanly and fail at runtime, sometimes intermittently. An agent working
  solo has no signal until something crashes — and possibly not then.

Real shipping references: `epiphany` 50.5 (GNOME Web) depends on `webkitgtk-6.0`, `gtk4`, and
`libadwaita` ([Arch][arch-epiphany]) **[confirmed]**, as do `gnome-builder` and `bazaar`.
This is the most-exercised path on the planet.

---

## 7. Swift on Linux — verdict

**Not a real option for this app. The blocker is WebKitGTK, and it is specific and confirmed.**

### The GTK4/libadwaita half: thin but not zero

| Project | State |
|---|---|
| [`rhx/SwiftGtk`][swiftgtk] | Auto-generated from GObject introspection via `gir2swift`. `gtk4` branch tested against GTK 4.0–4.22 (so, current). Requires Swift 5.7+. Generates ~300k lines of Swift interface — long build times. **No WebKit, no libadwaita.** **[confirmed from the repo README]** |
| [`AparokshaUI/Adwaita`][adwaita-swift] ("Adwaita for Swift", SwiftUI-like) | **The GitHub repo was archived 2024-10-17** and moved to a self-hosted forge (`git.aparoksha.dev`). **No WebView/WebKitGTK support.** **[confirmed]** |
| [`makoni/swift-adwaita`][swift-adwaita] (imperative Swift 6 wrapper) | Active — created 2026-03-23, last push 2026-07-08, MIT, **8 stars**, single maintainer, 0 open issues. 178 widget wrappers (74 auto-generated Adw + 104 hand-written GTK). Targets libadwaita 1.5+. **Ships an `AdwaitaWebKit` product with a WebView for WebKitGTK 6.0 — Linux-only.** **[all confirmed from the repo and the GitHub API]** |

So there *is* exactly one Swift WebKitGTK wrapper. It is ~150 lines. Here is what it exposes,
read from source **[confirmed from `Sources/AdwaitaWebKit/WebView.swift`][swift-adwaita-webview]**:

| Moremaid needs | `AdwaitaWebKit.WebView` |
|---|---|
| `load_html` | ✅ `loadHTML(_:baseURI:)` |
| `UserContentManager` script message handlers | ❌ not exposed |
| `URISchemeHandler` | ❌ not exposed |
| `decide-policy` | ❌ not exposed |
| zoom | ❌ not exposed |
| settings | ❌ not exposed |

It offers `loadURI`, `reload`, `goBack`/`goForward`, `canGoBack`, `uri`, `title`, `isLoading`,
`estimatedLoadProgress`, and an `onLoadChanged` load-event callback. **Five of the six APIs the
ticket names are missing.** The ticket's own rule — *"partial bindings here are disqualifying"* —
disposes of this directly.

And the missing five are not incidental to Moremaid; they are the app's spine:
- script message handlers ← the entire JS↔Swift bridge (`linkClick`, `headings`, `loadComplete`,
  `externalLink` — `WebView.swift:619–668` in this repo)
- `decide-policy` ← internal-`.md`-link interception, external-link-to-browser, Cmd-click
- zoom ← the zoom preference (`webView.pageZoom`, `WebView.swift:206`)
- settings ← `allowFileAccessFromFileURLs` and friends (`WebView.swift:470`)

**Broader search finding:** I searched specifically for a Swift WebKitGTK binding
(gir2swift-generated or otherwise) and found **none beyond this one**. `rhx` has SwiftGtk and
SwiftGdk but no SwiftWebKitGtk. **[confirmed to the extent a negative can be — two targeted
searches returned nothing.]**

### The escape hatch, and why it doesn't rescue the case

Swift can call C directly through a module map. `swift-adwaita`'s own docs acknowledge this:
advanced features *"require accessing the raw pointer via `castedPointer()` and calling the
upstream WebKitGTK C API directly"* **[confirmed]**. So a Swift port is *possible*: hand-write a
module map over `webkit2gtk-6.0.h`, and drive `webkit_web_view_*` through raw C interop — GObject
signal connection, `GVariant`/`JSCValue` marshalling, refcount management, and `GClosure`
lifetime all by hand.

That is **writing the binding layer as well as the app**, with no prior art to copy, on a
platform the agent cannot test against locally, in a language with almost no GTK training corpus.
It converts a porting job into a bindings-engineering job.

### Packaging: a second, independent problem

**Swift is not in any official Arch repository.** It exists only in the AUR:
`swift-bin` (repackages the official Swift.org **RHEL 9** toolchain, currently 6.3.x),
`swift-language` (source build, stuck at 5.10 — the last version that bootstraps without an
existing Swift compiler), and `swift-language-git` ([AUR][aur-swift-bin],
[AUR][aur-swift-language]) **[confirmed]**.

Consequences for the Omarchy/AUR packaging story **[inferred from the above]**:
- The PKGBUILD's `makedepends` would include an AUR package, which `pacman` cannot resolve — every
  user needs an AUR helper and a from-AUR toolchain.
- The build toolchain is a repackaged *RHEL 9* binary running on Arch — a glibc-version drift
  hazard that Arch's rolling release makes worse, and that nobody upstream is testing.
- The Static Linux SDK (musl) would sidestep glibc drift, but it has an active tail of reported
  Foundation/module issues (`URLRequest` not found, `_FoundationCollections` missing,
  SIL-verification crashes with musl) across swift-corelibs-foundation, swift-nio, and
  swift-configuration issue trackers **[confirmed those issues exist; current status per-issue
  not assessed]**. And a musl-static Swift binary still has to dynamically link the glibc-built
  `libgtk-4.so` / `libwebkitgtk-6.0.so`, which is the part that doesn't work.

### What reuse would Swift actually unlock? — less than it looks

Measured against this repo **[confirmed by `wc -l` and `grep '^import'`]**:

- Total: **9,892** lines of Swift.
- **Foundation-only, zero AppKit/SwiftUI/WebKit: 3,685 lines** — `Rendering/` (2,111),
  `Search/` (322: `ContentSearch` 210 + `FuzzyMatcher` 112), `Validation/MermaidValidator` (219),
  `FileScanner` (214), `HeadingParser` (275), `SidebarTree` (116), `GitignoreParser` (98),
  `Shared/` subset (330).
- Everything else — `DirectoryWindowView` (1,348), `WebView` (749), `SidebarView` (601),
  `QuickOpenView` (598), `MoremaidApp` (491), `SearchInFilesView` (437), `SingleFileView` (353) —
  is SwiftUI/AppKit/WebKit and **must be rewritten regardless of language**.

Now discount the 3,685:

- **`Rendering/` (2,111 lines, 57% of the "portable" total) is not really Swift.** `BaseCSS.swift`
  is `static let all = """ * { margin: 0; ... """` — a Swift multiline string literal holding
  CSS. `PageScripts.swift` (618) is the same for JavaScript. `LanguageMaps.swift` (271) is a
  dictionary literal. `ThemeCSS`, `TypographyCSS`, `MermaidConfig` likewise. **[confirmed by
  inspection.]** This content ports to *any* language — or better, out of the source entirely
  into `.css`/`.js` files. Swift buys nothing here.
- **`FuzzyMatcher` (112) and `GitignoreParser` (98) have superior off-the-shelf replacements in
  Rust (`nucleo`, `ignore`) and adequate ones in Python (`rapidfuzz`, `pathspec`).** Porting them
  is a *downgrade* relative to adopting the library.
- `FileWatcher` (136) is FSEvents-based and must be rewritten for inotify/`GFileMonitor` in every
  language including Swift. **[confirmed — it uses `FSEventStreamRef`.]**
- `Archive/` (287) is explicitly out of v1 scope per [map.md](../map.md).

**Net genuinely-Swift-specific reuse: roughly 1,000–1,300 lines** — `HeadingParser` (275),
`MermaidValidator` (219), `ContentSearch` (210), `FileScanner` (214), `SidebarTree` (116), and the
`Shared` models. **[inferred from the confirmed line counts above.]** That is ~10–13% of the
codebase, and it is the *easiest* 10–13% to reimplement (pure string/path logic that an agent
can port from the Swift source mechanically into any target language, using the existing file as
the spec).

### Verdict

**Rule Swift out.** Not because Swift-on-Linux is unhealthy in general — Swift 6.3 works on Linux
and Foundation is in reasonable shape — but because of three independent findings, any one of
which would be enough:

1. **[confirmed]** The only Swift WebKitGTK 6.0 wrapper in existence exposes 1 of the 6 APIs
   Moremaid's rendering path needs, in an 8-star, four-month-old, single-maintainer project.
   The ticket's stated rule makes partial bindings disqualifying.
2. **[confirmed]** Swift is absent from Arch's official repositories; the AUR packaging story is
   a repackaged RHEL 9 toolchain, which is a poor foundation for a PKGBUILD-distributed app.
3. **[inferred from confirmed measurements]** The reuse prize is ~1,000–1,300 lines of easily
   re-portable logic, not the ~9.9k the ticket's framing implies — and the largest "portable"
   chunk is CSS/JS embedded in string literals, which ports to any language equally well.

The port map does **not** change enormously. HANDOFF.md can close this question.

---

## 8. Known unknowns

Nothing here was compiled or measured. The items below are the ones where I could not reach a
confirmed answer, ordered by how much they could change the picture.

1. **Cold start, per language, on Arch.** No published measurement found for any candidate.
   Specifically unknown: how much fixed cost CPython + `import gi` + typelib load adds, and
   whether it is visible next to WebView construction. *Would confirm:* `hyperfine` on an Arch
   box comparing a hello-world GTK4 window across Rust / Vala / Python / C.
2. **Time to first render of a `WebKitWebView`.** The `hwatud` prewarming crate implies it is
   large enough to engineer around, but the number is unverified. This may matter more than the
   entire language choice. *Would confirm:* a timing harness around `webkit_web_view_load_html`
   → `load-changed(finished)` for a representative Moremaid page.
3. **Vala vapi coverage of the six specific WebKit APIs.** Confirmed the vapi exists and is
   GIR-derived; did not verify each symbol. *Would confirm:* `grep` the six symbols in
   `/usr/share/vala/vapi/webkitgtk-6.0.vapi`.
4. **Vala's vapi-in-the-`vala`-package version skew.** Whether Vala 0.56.19's vapi is generated
   against WebKit 2.52 or something older is unverified, and it is the one place a coverage gap
   could hide. *Would confirm:* diff the vapi against `WebKit-6.0.gir`.
5. **Severity of Vala's generated-C error messages on 0.56.19.** The community reports are real
   but partly historical. *Would confirm:* deliberately introduce type errors in a small Vala
   GTK4 program and read the output.
6. **Binary/install size for an 8–10k-line app in each language.** Not measured for any.
7. **PyGObject stub coverage for WebKit-6.0.** Whether `PyGObject-stubs` + `mypy` gives an agent
   enough static feedback to compensate for the missing compile step is unknown and would
   materially change Python's agent-implementability score. *Would confirm:* run `mypy` over a
   small WebKit-6.0 PyGObject program.
8. **Whether `rapidfuzz` / `pathspec` / `watchdog` are in Arch `extra` or only PyPI**, which
   determines whether a Python PKGBUILD is clean or needs vendoring.
9. **Per-package language attribution** in Arch's `webkitgtk-6.0` required-by list. The list is
   confirmed; which of the 31 packages are Python vs Vala vs C is largely inferred from project
   reputation. The Apostrophe (Python) and NewsFlash (Rust) attributions are the two I am
   confident in.
10. **GObject-subclassing boilerplate cost in Rust for the Navigator's custom widgets.** Flagged
    as the main Rust friction but not quantified.

---

## Links

[arch-wk]: https://archlinux.org/packages/extra/x86_64/webkitgtk-6.0/
[arch-wk-files]: https://archlinux.org/packages/extra/x86_64/webkitgtk-6.0/files/
[arch-gtk4]: https://archlinux.org/packages/?q=gtk4
[arch-adw]: https://archlinux.org/packages/extra/x86_64/libadwaita/
[arch-adw-files]: https://archlinux.org/packages/extra/x86_64/libadwaita/files/
[arch-vala]: https://archlinux.org/packages/extra/x86_64/vala/
[arch-vala-files]: https://archlinux.org/packages/extra/x86_64/vala/files/
[arch-pygobject]: https://archlinux.org/packages/extra/x86_64/python-gobject/
[arch-epiphany]: https://archlinux.org/packages/extra/x86_64/epiphany/
[wk-webview]: https://webkitgtk.org/reference/webkitgtk/stable/class.WebView.html
[rs-webviewext]: https://docs.rs/webkit6/latest/webkit6/prelude/trait.WebViewExt.html
[rs-ucm]: https://docs.rs/webkit6/latest/webkit6/struct.UserContentManager.html
[rs-webcontext]: https://docs.rs/webkit6/latest/webkit6/struct.WebContext.html
[rs-all]: https://docs.rs/webkit6/latest/webkit6/all.html
[librs-webkit6]: https://lib.rs/crates/webkit6
[librs-gtk4]: https://lib.rs/crates/gtk4
[librs-adw]: https://lib.rs/crates/libadwaita
[rs-book]: https://gtk-rs.org/gtk4-rs/stable/latest/book/main_event_loop.html
[rs-ignore]: https://docs.rs/ignore/latest/ignore/
[rs-nucleo]: https://docs.rs/nucleo/latest/nucleo/
[crates-rdeps]: https://crates.io/crates/webkit6/reverse_dependencies
[valadoc-wk]: https://valadoc.org/webkitgtk-6.0/index.htm
[vala-site]: https://vala.dev/
[vala-debian]: https://tracker.debian.org/pkg/vala
[vala-discourse]: https://discourse.gnome.org/t/newbie-vala-app-builds-runs-fine-but-lots-of-c-errors-are-output-0-56-vs-0-48/12769
[vala-debug]: https://docs.vala.dev/tutorials/programming-language/main/08-00-techniques/08-01-debugging.html
[pygobject-overview]: https://pygobject.gnome.org/
[pygobject-threads]: https://pygobject.gnome.org/guide/threading.html
[pygobject-gtk4]: https://pygobject.gnome.org/tutorials/gtk4.html
[pygobject-ucm]: https://api.pygobject.gnome.org/WebKit-6.0/class-UserContentManager.html
[apostrophe]: https://gitlab.gnome.org/World/apostrophe
[omg-newsflash]: https://www.omgubuntu.co.uk/2022/09/newsflash-gtk-feed-reader-ported-to-gtk-4-supports-freshrss-more
[swiftgtk]: https://github.com/rhx/SwiftGtk
[adwaita-swift]: https://github.com/AparokshaUI/Adwaita
[swift-adwaita]: https://github.com/makoni/swift-adwaita
[swift-adwaita-webview]: https://github.com/makoni/swift-adwaita/blob/main/Sources/AdwaitaWebKit/WebView.swift
[aur-swift-bin]: https://aur.archlinux.org/packages/swift-bin
[aur-swift-language]: https://aur.archlinux.org/packages/swift-language
[swift-static-sdk]: https://www.swift.org/documentation/articles/static-linux-getting-started.html
