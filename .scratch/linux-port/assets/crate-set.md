# The Rust crate set

Research asset for [issues/01-binding-survey.md](../issues/01-binding-survey.md) (re-scoped to
"Choose the Rust crate set"). Companion to [assets/binding-survey.md](binding-survey.md), which
established the language choice and the three GNOME binding crates.

Date: 2026-08-13. **Paper research only — nothing here was compiled.** Every claim is tagged
**[confirmed]** (with a link) or **[inferred]**. Versions come from the crates.io API, read
2026-08-13.

> **📌 This file is the canonical crate-set asset.** It supersedes `cargo-toml.md`, whose unique
> content has been merged in here (credited inline) and which is now a stub pointing at this file.
> The two were written concurrently on 2026-08-13 and agreed on the headline; this one carries the
> corrections.

**Headlines:** everything the [port map](../issues/11-module-port-map.md) named is real, maintained
and suitable. The corrections are:

1. **`fuzzy-matcher` is formally archived** — the port map's "or `fuzzy-matcher`" alternative is
   dead (§7). *(This does **not** touch the "free exit" that map.md and cargo-toml.md cite for
   `nucleo` being quiet — that exit is porting `FuzzyMatcher.swift`, and it is intact.)*
2. **`grep-matcher` is missing** from every list — match spans for highlighting come from it, not
   from `SinkMatch` (§6).
3. **`ignore`'s `require_git` defaults to `true`**, so `.gitignore` is silently ignored outside a
   git repo (§5).
4. **`toml` cannot emit a commented default config**, which this ticket explicitly asked for (§9).

Two disagreements with `cargo-toml.md` are recorded rather than resolved: **`nucleo` over
`nucleo-matcher`** (§7) and **`gtk4::UriLauncher` over the `open` crate** (§9 — since corroborated
by ticket 02 from GTK source).

**Withdrawn on re-check:** an earlier draft claimed `javascriptcore6` was a *required* dependency.
It is not — `webkit6` re-exports it. What remains is a documentation gap worth closing (§3).

**On the theming dependency:** the *binding* is complete; the *desktop* does not feed it. Those
are different claims and §4 now separates them explicitly.

---

## 1. `[dependencies]` — copy-paste block

```toml
[dependencies]
# ── GNOME stack ─────────────────────────────────────────────────────────────
# All four unify on gtk4 ^0.11 / glib ^0.22 / gio ^0.22 / gdk4 ^0.11 — verified, §2.
gtk4            = { version = "0.11.4", features = ["v4_18"], package = "gtk4" }
libadwaita      = { version = "0.9.2",  features = ["v1_6"] }
webkit6         = "0.6.1"
# javascriptcore6 — NOT a required dependency line: webkit6 re-exports it as
# `webkit6::javascriptcore`. Listed here only if you want the version visible. See §3.

# glib / gio / gdk4 / gtk are re-exported (webkit6::gio, gtk4::gio, …) — do NOT add
# separate dependency lines for them. Credit: assets/cargo-toml.md got this right.

# ── Async plumbing. No tokio — see §10. ─────────────────────────────────────
async-channel   = "2.5.0"   # worker thread → GTK main loop; the gtk4-rs book's own pattern

# ── File discovery & search (ripgrep's libraries, in-process) ───────────────
ignore          = "0.4.33"  # replaces FileScanner + GitignoreParser outright
grep-searcher   = "0.1.17"  # line-oriented search w/ before/after context
grep-regex      = "0.1.14"  # the Matcher implementation grep-searcher drives
grep-matcher    = "0.1.9"   # Match{start,end} — the byte offsets the UI highlights with

# ── Quick Open ──────────────────────────────────────────────────────────────
nucleo          = "0.5.0"   # NOT fuzzy-matcher, which is archived — see §7

# ── File watching ───────────────────────────────────────────────────────────
notify                = "8.2.0"  # stay on stable 8; 9.0.0-rc.4 is in flight, don't take the rc
notify-debouncer-full = "0.7.0"  # not optional: this is what makes atomic saves work — §8

# ── Config ──────────────────────────────────────────────────────────────────
serde           = { version = "1.0.229", features = ["derive"] }
toml            = "1.1.4"
dirs            = "6.0.0"   # XDG config dir

# ── Errors ──────────────────────────────────────────────────────────────────
anyhow          = "1.0.104"
```

**Deliberately absent:** `tokio` (§10), `walkdir` (`ignore` supersedes it), the `open` crate
(§9), `zip` (Archive is out of v1 scope per [map.md](../map.md)), any markdown crate
(markdown-it runs in the WebView — `Rendering/` crosses over verbatim per the port map).

Version/date/download figures for every crate above are **[confirmed]** from the crates.io API
(`/api/v1/crates/<name>`), read 2026-08-13.

---

## 2. The compatibility check that actually matters

Four crates in this set bind the same C stack and must agree on their glib-family versions, or
the build fails with two incompatible `glib::Object` types. Read from the crates.io dependency
API for the exact pinned versions **[confirmed]**:

| | `gtk4` | `glib` | `gio` | `gdk4` | other |
|---|---|---|---|---|---|
| `libadwaita` 0.9.2 | `^0.11` | `^0.22` | `^0.22` | `^0.11` | `pango ^0.22` |
| `webkit6` 0.6.1 | `^0.11` | `^0.22` | `^0.22` | `^0.11` | `javascriptcore6 ^0.6`, `soup3 ^0.9` |
| `javascriptcore6` 0.6.0 | — | `^0.22` | — | — | |
| (pinned above) | 0.11.4 | 0.22.8 | 0.22.8 | 0.11.x | |

**They unify cleanly.** No conflict, no `[patch]` section, no version pinning gymnastics. This is
the single highest-value thing to have verified before writing a `Cargo.toml`, and it checks out.

### Feature-flag floors

| crate | flag | why | Arch ships |
|---|---|---|---|
| `gtk4` | `v4_18` | **Floor is `v4_10`** — the highest-versioned API confirmed needed is `UriLauncher`/`FileDialog` (§9). `v4_18` is a judgment call: comfortably under Arch's 4.22.4 so a brief distro lag can't break the build, comfortably over the real floor. **[floor confirmed; `v4_18` is inferred/judgment]** | 4.22.4 |
| `libadwaita` | `v1_6` | **Required, not optional** — `StyleManager::accent_color()` and `connect_accent_color_notify` are gated behind `v1_6` (§4). Setting this lower silently removes the API the theming decision rests on. **[confirmed]** | 1.9.3 |
| `webkit6` | *(none)* | None of the six required APIs carried an "Available on crate feature" annotation on docs.rs. See the methodology note below. **[confirmed by absence]** | 2.52.5 |

**Methodology note on "confirmed by absence":** docs.rs builds with all features enabled and
annotates gated items with *"Available on crate feature `vX_Y` only"*. That annotation **did**
surface on `libadwaita::StyleManager::accent_color` in the same reading pass, which proves the
annotation is visible to this method. Its absence on the `webkit6` items is therefore evidence,
not merely a null result.

---

## 3. `webkit6` — the bridge, and what `Value` actually is

The six-API audit was completed in [binding-survey.md §3](binding-survey.md) and the ticket's
"incomplete binding" risk is **retired**. Not repeated here.

**Also present** beyond the six (merged from [cargo-toml.md](cargo-toml.md)):
`call_async_javascript_function`, `connect_load_changed`, `add_script`, `add_style_sheet`,
`register_script_message_handler_with_reply`, `connect_context_menu`.

**Not found: a dedicated print-to-PDF method.** `connect_print` exists, so printing routes
through the general GTK print operation. PDF export is out of v1 scope, so this matters only if
that changes — recorded rather than silently assumed.

**Residual risk — `webkit6` is the thinnest crate in the set.** 143k downloads against `ignore`'s
157M, and docs.rs reports it **15.8% documented**. Signatures are GIR-generated and reliable;
behavioural prose largely isn't there, so read the C docs for semantics and the Rust docs only
for shapes. It is the dependency with the least community pressure behind it and the one where an
unfixed upstream bug would have no easy workaround — worth one line in HANDOFF.md's
known-unknowns so a weird WebKit behaviour is treated as plausibly a binding issue rather than
the implementer's own code.

### ⚠️ The script-message payload is a JavaScriptCore value — corrected on re-check

> **Correction (re-verified 2026-08-13).** An earlier draft of this section claimed the bridge
> *"cannot be written with `webkit6` alone"* and that a direct `javascriptcore6` dependency was
> **required**. **That was wrong, and it is withdrawn.** Reading the docs.rs HTML for `webkit6`
> 0.6.1 directly, the crate's re-export list is:
> ```rust
> pub use ffi;  pub use gdk;  pub use gio;  pub use glib;
> pub use gtk;  pub use javascriptcore;  pub use soup;
> ```
> **[confirmed]** — so `webkit6::javascriptcore::Value` is reachable with no extra dependency
> line. And `Value`'s accessors are **inherent methods** on the struct (they appear under
> docs.rs's `implementations` section, not `trait-implementations`) **[confirmed]**, so there is
> no prelude trait to import either. The re-export genuinely suffices.
>
> **What survives is a documentation gap, not a dependency gap** — and it is still worth fixing,
> because it is the kind of thing that costs an implementer an hour of confusion:

Neither the [port map](../issues/11-module-port-map.md) (WebView row: *"reimplement, small —
`webkit6-rs` wrapper"*) nor [cargo-toml.md](cargo-toml.md) says **what `Value` is**. Both print
the signature with a bare `&Value` in it. A reader will reasonably guess `glib::Variant`, or a
string, and go looking for a `to_string()` that does what they expect. It is neither:

```rust
UserContentManager::connect_script_message_received<F: Fn(&Self, &Value) + 'static>(
    &self, detail: Option<&str>, f: F) -> SignalHandlerId
```

That `Value` is **`javascriptcore6::Value`**, a re-export from `webkit6`'s own dependency
`javascriptcore6 ^0.6` **[confirmed]**. To turn Moremaid's `{type: "linkClick", href: "..."}`
message payloads into Rust data you need that crate's accessors — all **[confirmed]** present on
`javascriptcore6` 0.6.0:

- `is_object()`, `is_string()`, `is_array()`, `is_number()`, `is_boolean()`
- `object_get_property(&self, name: &str) -> Option<Value>`, `object_has_property(&self, name: &str) -> bool`
- `object_get_property_at_index(&self, index: u32) -> Option<Value>`
- `to_str() -> GString`, `to_int32() -> i32`, `to_double() -> f64`, `to_boolean() -> bool`

So the four message types the macOS app uses (`linkClick`, `headings`, `loadComplete`,
`externalLink` — `Sources/FileBrowser/WebView.swift:626`) are readable field-by-field.
**[the accessors are confirmed; that they suffice for Moremaid's payloads is inferred]**

**Recommendation (downgraded from "required" to "optional, and say what `Value` is").** Either:
- write `webkit6::javascriptcore::Value` and add no dependency line — **this works**; or
- list `javascriptcore6 = "0.6.0"` explicitly if you prefer the version visible in `Cargo.toml`.

Either way, **HANDOFF.md must state that the script-message payload is a JavaScriptCore value**
and point at the accessors above. That sentence is the actual deliverable here; the dependency
line is a matter of taste.

*Simpler alternative worth flagging to the [WebKitGTK audit](../issues/03-webkitgtk-audit.md):*
have the JS side `postMessage(JSON.stringify(obj))` and the Rust side do
`value.to_str()` → `serde_json::from_str()`. That trades one crate (`serde_json`) for avoiding
JSC's object-graph API entirely, and makes the bridge payloads trivially testable as strings.
**[inferred — a design suggestion, not a finding. Belongs to ticket 03, not this one.]**

---

## 4. `libadwaita` `StyleManager` — the *binding* is complete; the *desktop* is not

**Read this heading precisely, because the distinction is the whole point of this section.**

There are two separate claims, and only the first is this ticket's business:

| claim | verdict | whose question |
|---|---|---|
| **(a)** The Rust binding exposes colour-scheme state, accent state, and change signals. | ✅ **Confirmed.** Verified method-by-method on docs.rs, below. | This ticket. |
| **(b)** On Omarchy, the desktop actually *supplies* an accent colour for that API to report. | ❌ **No.** | [Ticket 02](../issues/02-hyprland-conventions.md), answered. |

**"Green" in this section means (a) and only (a).** It is **not** an endorsement of accent-following
as a theming mechanism. Ticket 02 invalidated that mechanism, and this section does not reopen it.

> **What ticket 02 found** ([assets/hyprland-conventions.md](hyprland-conventions.md) §2.3):
> `AdwStyleManager:accent-color` reads `org.freedesktop.appearance/accent-color` from the Settings
> portal, but `xdg-desktop-portal-gtk`'s Settings backend publishes **only** `color-scheme` and
> `contrast` — a search of `settings.c` for "accent" returns nothing **[confirmed against
> GTK/portal source by ticket 02]**. Omarchy never sets an accent GSetting either. So on Omarchy
> **`AdwStyleManager` yields exactly one bit: light or dark.** Tokyo Night, Gruvbox, Nord and
> Kanagawa are indistinguishable through it. The real palette lives in
> `~/.local/state/omarchy/current/theme/colors.toml`, which is
> [ticket 15](../issues/15-omarchy-palette-source.md)'s subject.

**Consequences for what this ticket pins:**

- `accent_color()` / `accent_color_rgba()` / `connect_accent_color_notify()` exist and compile,
  but on Omarchy they will return the libadwaita default forever. **Do not build the palette on
  them.**
- **`v1_6` is still the right feature floor** — but the *reason* has changed. It is no longer
  "load-bearing for theming"; it is simply free (Arch ships 1.9.3) and harmless. Nothing in v1
  breaks if it is absent.
- **The part of `StyleManager` that is genuinely load-bearing is the light/dark bit** —
  `is_dark()` and `connect_dark_notify`. Those are ungated and work on Omarchy.

With that framing fixed, here is claim (a) verified. All present on `libadwaita` 0.9.2's
`StyleManager`, read from docs.rs **[all confirmed]**:

| need | method | gate |
|---|---|---|
| colour-scheme **state** | `color_scheme() -> ColorScheme`, `set_color_scheme(ColorScheme)` | ungated |
| resolved dark/light | `is_dark() -> bool` | ungated |
| does the system even express a preference | `system_supports_color_schemes() -> bool` | ungated |
| accent **state** | `accent_color() -> AccentColor` | **`v1_6`** |
| accent as a usable colour | `accent_color_rgba() -> RGBA` | **`v1_6`** |
| **change signal** (colour scheme) | `connect_color_scheme_notify<F: Fn(&Self) + 'static>(f: F) -> SignalHandlerId` | ungated |
| **change signal** (resolved dark) | `connect_dark_notify<F: Fn(&Self) + 'static>(f: F) -> SignalHandlerId` | ungated |
| **change signal** (accent) | `connect_accent_color_notify<F>`, `connect_accent_color_rgba_notify<F>` | **`v1_6`** |
| bonus | `connect_high_contrast_notify<F>` | ungated |

Two notes for ticket 07:

1. **The `v1_6` gate is a trap only if you go looking for accent.** Omit `features = ["v1_6"]`
   and `accent_color()` plus its notify signal simply do not exist — a failure that reads as
   "the binding is incomplete" rather than "you under-specified a feature flag." Keep the flag
   (Arch ships 1.9.3, it is free), but per the framing above, **nothing in v1 should depend on
   what it unlocks.** **[confirmed]**
2. **`connect_dark_notify` is the one to actually wire.** `color_scheme()` is the *preference*
   (`Default`/`ForceLight`/`ForceDark`/…); `is_dark()` is the *resolved* value after the system
   setting is applied. A markdown viewer wants the resolved value. **[inferred from the two
   methods' confirmed descriptions.]**

~~Unverified: whether `AccentColor` exposes a conversion to a hex string for injecting into
`ThemeCSS`.~~ **Moot** — per ticket 02 the accent value is never populated on Omarchy, so nothing
injects it. The hex-formatting question moves to `colors.toml` parsing
([ticket 15](../issues/15-omarchy-palette-source.md)).

---

## 5. `ignore` — hidden files and custom skips ARE configurable ✅

`ignore` 0.4.33 (published 2026-08-04, BurntSushi, in the ripgrep repo). All builder methods
below read from docs.rs `WalkBuilder` **[all confirmed]**, with their documented defaults:

| `WalkBuilder` method | default | what it does for Moremaid |
|---|---|---|
| `hidden(&mut self, yes: bool)` | **`true`** (hidden **are** ignored) | The whole `showHidden` preference is this one boolean. Note the polarity: `hidden(true)` means *do* ignore them. |
| `git_ignore(bool)` | `true` | `.gitignore` semantics — replaces `GitignoreParser.swift` |
| `git_global(bool)` | `true` | honours `core.excludesFile`; macOS Moremaid does **not** do this — a small behaviour *upgrade* |
| `git_exclude(bool)` | `true` | `.git/info/exclude` |
| `ignore(bool)` | `true` | `.ignore` files (gitignore syntax, VCS-agnostic) |
| `parents(bool)` | `true` | ignore files from parent dirs — matters when opening a subdirectory of a repo |
| `require_git(bool)` | **`true`** | ⚠️ gitignore rules are **only applied inside a git repo** by default. Moremaid opens arbitrary folders; if `.gitignore` should be honoured in a non-repo directory, set this `false`. **Easy to miss.** |
| `filter_entry<P: Fn(&DirEntry) -> bool + Send + Sync + 'static>(P)` | none | **the `node_modules` / `.git` skip.** Skips descending into non-matching dirs, not just filtering them out — the behaviour `FileScanner.shouldSkipComponent` has. **Only one filter can be active at a time** — compose all skips into a single closure. |
| `add_custom_ignore_filename<S: AsRef<OsStr>>(S)` | none | a future `.moremaidignore` if ever wanted; higher precedence than standard ignore files |
| `overrides(Override)` / `types(Types)` | none | include/exclude globs; markdown-extension filtering |
| `max_depth(Option<usize>)` | `None` | — |
| `follow_links(bool)` | **`false`** | matches the macOS app's effective behaviour |
| `standard_filters(bool)` | `true` | master switch for hidden+parents+ignore+git_ignore+git_global+git_exclude |
| `threads(usize)` | `0` (auto) | — |
| `build() -> Walk` / `build_parallel() -> WalkParallel` | — | see below |

**Parallel walking semantics.** `build_parallel()` returns `WalkParallel`, which *"must be
executed with a closure rather than standard iteration"* **[confirmed]** — i.e. you hand it a
visitor closure per thread rather than getting an `Iterator`. Two consequences for the port
**[inferred]**:

- Results arrive **out of order and concurrently**, unlike `FileScanner`'s ordered batches. The
  Navigator will need to sort after collection, or collect into an order-independent structure.
- The visitor runs on `ignore`'s own threads, which are **not** the GTK main thread. Results must
  cross back via `async-channel` → `glib::spawn_future_local`. `WalkParallel`'s closure is
  `Send`-bounded, which enforces this at compile time.

**Verdict: keep.** The port map's "delete `FileScanner` + `GitignoreParser` → `ignore`" verdict
holds, and `require_git(false)` is the one line that must not be forgotten.

---

## 6. `grep-searcher` / `grep-regex` — context snippets AND match offsets ✅

The ticket asked whether the API yields "the context snippets and match offsets the UI needs for
highlighting". **Both, from two different places** — this is the part that is easy to get wrong,
so the split matters.

### Context snippets — `SearcherBuilder` **[confirmed]** (`grep-searcher` 0.1.17, 2026-07-15)

| method | default | note |
|---|---|---|
| `before_context(usize)` | `0` | lines before each match |
| `after_context(usize)` | `0` | lines after each match |
| `line_number(bool)` | **enabled** | "small performance cost"; Find-in-Files needs it |
| `binary_detection(BinaryDetection)` | disabled | ⚠️ **set this.** Moremaid scans arbitrary directories; without it, binaries get searched and emit garbage. Directly addresses the map's "binary files mistaken for text" fog. |
| `memory_map(MmapChoice)` | never | opt-in; unmeasured whether it helps here |
| `multi_line(bool)` | disabled | leave off — requires the file in memory |
| `passthru(bool)` | disabled | — |
| `heap_limit(Option<usize>)` | unlimited | worth setting as a guard against huge files |
| `invert_match`, `encoding`, `bom_sniffing` | —/none/enabled | — |

### Where results arrive — the `Sink` trait **[confirmed]**

`Sink` has `matched()` (required, returns `bool` to continue or stop), plus optional `context()`,
`context_break()`, `binary_data()`, `begin()`, `finish()`. So *matches* and *context lines* are
delivered through **separate callbacks** — `SinkMatch` vs `SinkContext` — which is exactly the
distinction a highlighted snippet UI wants.

### Per-match data — `SinkMatch` **[confirmed]**

```rust
pub fn bytes(&self) -> &'b [u8]                    // the matching line(s), incl. terminator
pub fn lines(&self) -> LineIter<'b>
pub fn absolute_byte_offset(&self) -> u64          // offset into the whole file
pub fn line_number(&self) -> Option<u64>           // Some(..) iff line_number(true)
pub fn buffer(&self) -> &'b [u8]
pub fn bytes_range_in_buffer(&self) -> Range<usize>
```

### ⚠️ The gap, and how it closes

`SinkMatch` gives you the **line** and its **file offset** — but *not the span of the match
within the line*, which is what you actually need to paint a highlight. That comes from
`grep-matcher`, by running the matcher again over `SinkMatch::bytes()` **[confirmed]**:

```rust
fn find_iter<F>(&self, haystack: &[u8], matched: F) -> Result<(), Self::Error>
  where F: FnMut(Match) -> bool
fn find_at(&self, haystack: &[u8], at: usize) -> Result<Option<Match>, Self::Error>
```

`Match` carries *"the start and end byte range"*, *"relative to the start of `haystack`"*
**[confirmed]** — i.e. relative to the line. That is the highlight span, and it handles multiple
matches per line, which `SinkMatch` alone cannot express.

**This means `grep-matcher` is a direct dependency, not just a transitive one.** The port map
names only `grep-searcher` + `grep-regex`; add `grep-matcher`. **[correction to the port map.]**

**Also confirmed: no subprocess.** All three are libraries; the port map's "no runtime dependency
on `rg` being installed" claim holds.

**Unverified:** whether byte offsets need mapping to *character* offsets before reaching the
WebView / GTK label for highlighting. Rust `&[u8]` offsets over UTF-8 are byte offsets; JS string
indices are UTF-16 code units. For non-ASCII matches these differ. **[inferred that this is a
real conversion the implementer must handle — flagged, not solved.]**

---

## 7. `nucleo` vs `fuzzy-matcher` — 🚩 `fuzzy-matcher` is ARCHIVED

**Pick `nucleo` 0.5.0. This is not a close call.**

| | `nucleo` | `fuzzy-matcher` |
|---|---|---|
| repo | `helix-editor/nucleo` — **1,483 stars, pushed 2026-06-24, not archived**, 29 open issues | `skim-rs/fuzzy-matcher` — 297 stars, **`archived: true`**, last push **2024-06-29** |
| last crates.io release | 0.5.0, **2024-04-02** | 0.3.7, **2020-10-04** — *nearly six years* |
| recent downloads | 566k (`nucleo`), 1.31M (`nucleo-matcher`) | 8.2M |
| speed | *"often around six times faster"* than skim/`fuzzy-matcher` (author's claim) | baseline |

All figures **[confirmed]** from the crates.io and GitHub APIs, read 2026-08-13.

**The port map says "delete → `nucleo` (or `fuzzy-matcher`)". Strike the parenthetical.** Its
GitHub repository is archived — read-only, no future fixes. Per the ticket's instruction to flag
unmaintained crates loudly: this one is not merely unmaintained, it is formally closed.

### On `nucleo`'s own release staleness — read it correctly

`nucleo` 0.5.0 dates to April 2024, which looks alarming next to the archived alternative. It
isn't the same thing **[confirmed evidence, inferred conclusion]**:
- the **repo was pushed 2026-06-24** — development continues; releases just haven't been cut;
- the author states *"The `nucleo-matcher` crate is finished and ready for widespread use, with
  breaking changes expected to be very rare"* **[confirmed quote]** — the gap is declared
  completion, not abandonment;
- it is the matcher inside **Helix**, a widely-used editor, so it gets continuous real-world
  exercise.

Still worth naming as a residual risk: a single-maintainer crate with a two-year release gap.

### Incremental scoring as the user types — ✅ **confirmed, and it is explicit**

This was the ticket's second criterion, and `nucleo` addresses it by name:

```rust
pub fn reparse(&mut self, column: usize, new_text: &str,
               case_matching: CaseMatching, normalization: Normalization,
               append: bool)
```

> *"By specifying `append` the caller promises that text passed to the previous `reparse`
> invocation is a prefix of `new_text`. This enables additional optimizations but can lead to
> missing matches if an incorrect value is passed."* **[confirmed]**

So: pass `append: true` on a keystroke, `false` on backspace/paste. Getting it backwards silently
drops matches rather than erroring — worth a comment in HANDOFF.md.

### The rest of the high-level API — fits GTK's main loop cleanly **[confirmed]**

```rust
Nucleo::new(config: Config, notify: Arc<dyn Fn() + Sync + Send>,
            num_threads: Option<usize>, columns: u32) -> Self
fn injector(&self) -> Injector<T>
fn tick(&mut self, timeout: u64) -> Status
fn snapshot(&self) -> &Snapshot<T>
fn restart(&mut self, clear_snapshot: bool)
```

`new()` takes a **notify callback** — *"notify is called everytime new information is available
and tick should be called"* **[confirmed]**. Matching runs on nucleo's own threadpool; the
callback fires; the GTK side calls `tick(timeout)` and reads `snapshot()`. That is a clean fit
for `glib::idle_add_local` or an `async-channel` wakeup, with no blocking on the main loop.
**[the API is confirmed; the GTK wiring is inferred.]**

Take `nucleo` (the worker) rather than bare `nucleo-matcher` — Quick Open wants exactly the
background-threadpool-plus-snapshot behaviour the high-level crate provides.

> **Disagreement on record.** [cargo-toml.md](cargo-toml.md) picks bare `nucleo-matcher` 0.3,
> reasoning that the worker/tick model is *"unnecessary when `async-channel` is already carrying
> results back"*. That is a coherent position — but it gives up `reparse(…, append)`, which is
> the one API that answers this ticket's *"can the scoring be driven incrementally as the user
> types"* criterion by name. Whoever writes HANDOFF.md should pick deliberately; both crates come
> from the same repo and switching later is a small change.
>
> **Both documents agree on the important half:** the "free exit" if `nucleo` goes properly dead
> is **porting `Sources/Search/FuzzyMatcher.swift`** — short, self-contained, an afternoon's work,
> and it would make Linux ranking match macOS exactly. That exit does **not** depend on the
> `fuzzy-matcher` crate and is therefore unaffected by its archival.

---

## 8. `notify` — 🚩 alone it does **not** solve atomic saves

`notify` 8.2.0 (2026-05-02, 35M recent downloads). Linux backend is **inotify**, via
`INotifyWatcher`; `recommended_watcher()` selects it automatically. **[confirmed]**

### 🔑 The mechanism — watch the **directory**, not the file

*(Merged from [cargo-toml.md](cargo-toml.md), which stated this more sharply than my own draft
did. It is the single most actionable line in this document.)*

**inotify watches the *inode*, not the path.** An editor's atomic save writes a temp file and
renames it over the target — a *new inode*. So a watch registered on the file itself sees the
rename and then **nothing, ever again**: the app goes silently deaf after the user's first save.
Neovim saves exactly this way, so on this desktop it is the **normal path, not an edge case**.

- **Watch the containing directory and filter events by filename.** This is the fix, and it is
  not optional.
- A single save emits **3–5 inotify events**, which is the second reason
  `notify-debouncer-full` is a required dependency rather than a nicety.
- Note *why* the macOS 1 s content-hash poll worked: **polling is immune to this entirely.**
  Dropping it (per the port map) is only a win if the rename case is handled deliberately.

**[the inode/rename mechanism is inferred-but-near-certain from how inotify works; the
"3–5 events" figure is from cargo-toml.md's sources and is not independently verified here.]**

### `notify` documents editor behaviour as a *known problem*

From `notify`'s own "Known Problems → Editor Behaviour" section **[confirmed]**:

> *"If you rely on precise events (Write/Delete/Create..), you will notice that the actual events
> can differ a lot between file editors."*

— because some editors truncate in place while others write a temp file and rename over the
original. `notify` reports the raw inotify truth; it does not paper over it. Its `RenameMode`
enum has `Any`, `To`, `From`, `Both`, `Other` **[confirmed]**, and the docs **do not** state which
of these the inotify backend actually emits **[explicitly not confirmed]**. Inotify's native
`IN_MOVED_FROM`/`IN_MOVED_TO` are separate events correlated by a cookie, so `From` + `To` as a
pair is the likely shape and `Both` is likely never emitted on Linux — **[inferred, and this is
exactly the kind of guess that should be tested before HANDOFF.md relies on it]**.

### The fix: `notify-debouncer-full` 0.7.0 — add it, don't hand-roll

Wraps `notify ^8.2.0` **[confirmed]**. Its documented behaviour is a point-for-point answer to
this bullet **[confirmed]**:

- *"Combines matching rename From/To pairs into single events"*
- *"consolidates multiple rename occurrences"* and *"adjusts pre-rename event paths accordingly"*
- *"prevents duplicate create events"*
- *"suppresses modify events following creates"* ← **this is the temp-file-plus-rename case**
- *"emits one remove event for directory deletions"*
- merges events over a configurable timeout (e.g. `Duration::from_secs(2)`)

Caveat, stated plainly: its **file-ID stitching is documented as "(macOS FS Events, Windows)"**
**[confirmed]** — the ID-cache mechanism is not advertised for Linux. The rename-pairing and
event-consolidation behaviours are described generally and are not Linux-excluded
**[confirmed by the doc's own phrasing]**, but *how well* debouncing alone handles Vim's
`4913`-temp-file dance on inotify specifically is **[not confirmed]**.

**Recommendation:** take the debouncer, set a short timeout (~100–300 ms — long enough to
coalesce a save, short enough that live reload still feels instant **[inferred, unmeasured]**),
and treat "any event touching this path" as "re-read the file" rather than trusting the event
kind. Moremaid's live reload only needs *"something changed, reload"*, so it can be robust to
event-kind ambiguity by design.

This also **retires the port map's residual worry** about dropping the 1 s content-hash polling:
the debouncer plus a path-level "just reload" policy covers what the poll was papering over.
**[inferred.]**

### Descriptor cost — the port map's concern is confirmed, with numbers

`notify`'s docs state **[confirmed]**:

- hitting the limit surfaces as *"Bad File Descriptor / No space left on device"*;
- *"recursive directory watching counts each file and folder toward the limit"*;
- the suggested remedy is `sysctl fs.inotify.max_user_instances=8192` and
  `fs.inotify.max_user_watches=524288`;
- `PollWatcher` *"bypasses these restrictions if users cannot increase system limits"*.

Also documented **[confirmed]**: network filesystems may emit nothing, `/proc` and `/sys` are
unreliable, deleting a parent requires watching the parent, and *"large directories may result in
missed events on some platforms"*.

**Consequence: the port map's "watch open files and the visible tree only, never recurse" rule is
correct and is now evidence-backed, not precautionary.** An app cannot ship expecting users to
have run `sysctl`. **[the limits are confirmed; the design conclusion is inferred.]**
`PollWatcher` is the documented escape hatch if a fallback is ever wanted.

---

## 9. Config, and external links

### `serde` + `toml` — with one wrinkle about comments

- `serde` **1.0.229** (2026-07-18), `features = ["derive"]`. Uncontroversial. **[confirmed version]**
- `toml` **1.1.4+spec-1.1.0** (2026-07-28). Note this is now **1.x** — the long 0.8.x era is
  over, so any 0.8-era snippet an implementer copies will be subtly wrong. **[confirmed version;
  the "snippets will be stale" point is inferred.]**
- `dirs` **6.0.0** for `config_dir()` → `~/.config/moremaid/config.toml`. **[confirmed version]**

⚠️ **The ticket asks for "a commented default config file." `toml` cannot produce that.**
Serializing a Rust struct emits values, not comments. **[inferred — but this is well-established
behaviour of serde-based emitters, and `toml_edit` exists precisely because of it.]** Two options:

1. **Ship a static default** — `include_str!("../resources/default-config.toml")`, hand-written
   with comments, written to disk on first run if absent. Read-only config thereafter. **Simplest,
   and the right fit** for an app whose config is edited by hand in a text editor. Recommended.
2. **`toml_edit` 0.25.13** (2026-07-14) — *"format-preserving TOML parser"* **[confirmed]** — only
   needed if the app ever *writes back* to the config while preserving the user's comments. Nothing
   in v1 scope does. **Skip it.**

### External links — 🚩 both options in the ticket are second-best

The ticket framed this as `open` crate vs invoking `xdg-open`. There is a third answer already in
the dependency tree:

```rust
gtk4::UriLauncher::new(uri: &str) -> UriLauncher       // Available on crate feature v4_10
fn launch<P: FnOnce(Result<(), Error>) + 'static>(
    &self, parent: Option<&impl IsA<Window>>,
    cancellable: Option<&impl IsA<Cancellable>>, callback: P)
fn set_uri(&self, uri: Option<&str>)
```

All **[confirmed]** on `gtk4` 0.11.4. Why it beats both offered options **[inferred]**:

- **Zero new dependencies** — `gtk4` is already there. The `open` crate (5.4.1, 2026-08-05,
  13.7M recent downloads — perfectly healthy **[confirmed]**) would be a dependency added for one
  call site.
- **Takes a `parent` window.** On Wayland this is what lets the compositor route focus/activation
  correctly instead of the browser stealing focus from nowhere. On Hyprland this is the difference
  between polite and rude. **[inferred — this is the standard rationale for GTK's parent
  parameter; not verified against Hyprland behaviour.]**
- **Async with a `Result` callback**, so a failure is reportable instead of silent. Shelling out
  to `xdg-open` gives an exit code at best, and adds a process spawn.
- **Portal-aware** — the GTK-blessed path, whatever the desktop does. **[inferred — the docs did
  not state the implementation.]**

Fallback if the `v4_10` floor is ever unwanted: `gio::AppInfo::launch_default_for_uri`, also
already in the tree. **Do not** shell out to `xdg-open`; **do not** add the `open` crate.

> ✅ **Independently corroborated by [ticket 02](../issues/02-hyprland-conventions.md)**, which
> reached the same conclusion from a different direction — reading GTK's own source
> ([gtkurilauncher.c](https://github.com/GNOME/gtk/blob/main/gtk/gtkurilauncher.c)):
> `GtkUriLauncher` takes the portal path when one is available
> (`if (gdk_display_should_use_portal (display, PORTAL_OPENURI_INTERFACE, 3))
> gtk_openuri_portal_open_uri_async (...)`) and falls back to `gtk_show_uri_full()` otherwise.
> Ticket 02's verdict: *"**Use `GtkUriLauncher`; do not shell out to `xdg-open`.**"*
> That also settles the "is it portal-aware?" item I had marked **[inferred]** above — it is,
> **[confirmed from GTK source]**. Two independent passes, same answer.

---

## 10. Async runtime — **no tokio**. Settled.

**Decision: no async runtime beyond glib's own main loop.**

The gtk4-rs book's main-event-loop chapter prescribes **[confirmed]**:

| need | tool |
|---|---|
| CPU/IO-heavy work off the main thread | `gio::spawn_blocking()` — glib's own thread pool |
| worker → UI messaging | `async-channel` 2.5.0 |
| running a future on the GTK main loop | `glib::spawn_future_local()` |
| tokio | *only* for crates that demand it (`reqwest` et al.) |

**Moremaid has no crate that demands tokio.** Checking this set: `ignore` is threads-not-async;
`grep-searcher` is synchronous; `nucleo` runs its own threadpool and signals via a callback;
`notify` uses its own thread and a channel; `serde`/`toml`/`dirs` are synchronous. **[confirmed
per-crate from their documented designs.]** Nothing in v1 does networking.

Supporting the decision structurally: **GTK GObjects are not `Send`/`Sync`** — touching a widget
off-thread is a *compile error* about `NonNull<GObject>` not being `Sync`, not a runtime crash
**[confirmed]**. A second runtime would add a scheduler that cannot own any UI state, purchasing
nothing. Pulling tokio in "just in case" is the ceremony the ticket suspected it was.

**Every background producer in this app lands on the same shape:** work on a non-GTK thread →
`async-channel::Sender` → `glib::spawn_future_local` on the main loop → mutate widgets. Directory
scan, content search, fuzzy match, and file watching all fit it. Worth stating once in HANDOFF.md
as *the* concurrency pattern rather than four times. **[inferred design guidance.]**

---

## 11. Corrections to the port map ([ticket 11](../issues/11-module-port-map.md))

Ticket 11 is resolved; these are amendments HANDOFF.md should carry, not a reopening.

| row | correction | severity |
|---|---|---|
| `Search/FuzzyMatcher` → *"`nucleo` (or `fuzzy-matcher`)"* | **Strike "or `fuzzy-matcher`"** — that repo is archived (§7). | 🚩 the alternative is dead |
| `FileBrowser/WebView` → *"`webkit6-rs` wrapper"* | **Say that the script-message payload is a JavaScriptCore `Value`**, reachable as `webkit6::javascriptcore::Value`, and point at `object_get_property`/`to_str` (§3). *No dependency line needed — `webkit6` re-exports it. An earlier draft claimed otherwise; withdrawn.* | ℹ️ documentation gap (downgraded from 🚩) |
| `Search/ContentSearch` → *"`grep-searcher` + `grep-regex`"* | **Add `grep-matcher`.** Match spans for highlighting come from `Matcher::find_iter`, not from `SinkMatch` (§6). | ⚠️ incomplete |
| `FileWatcher/` → *"`notify` crate"* | **Add `notify-debouncer-full`.** Raw `notify` reports editors' temp-file-plus-rename dance verbatim; the debouncer is what merges it (§8). | ⚠️ incomplete |
| `FileBrowser/FileScanner` → *"`ignore` crate"* | Correct — but `require_git(false)` must be set or `.gitignore` is ignored outside a git repo (§5). | ℹ️ footnote |
| `App/FilePicker` → *"`FileDialog`"* / external links | Correct; both `FileDialog` and `UriLauncher` need the `v4_10` feature floor (§2, §9). | ℹ️ footnote |

Everything else in the port map's crate column is **confirmed real, maintained, and suitable**.

---

## 12. Known unknowns

Nothing here was compiled. Ordered by how much each could change the plan.

1. **Does the whole set actually resolve and link?** Version *requirements* were verified to unify
   (§2), which is the strongest paper check available — but `cargo build` is the only real proof.
   *Would confirm:* `cargo generate-lockfile` on an Arch box.
2. **`notify` + debouncer against a real atomic save on inotify.** Which `RenameMode` variants the
   inotify backend emits is **undocumented** (§8), and the debouncer's file-ID stitching is
   advertised for macOS/Windows. The mitigation ("any event → reload") should make this moot, but
   it is untested. *Would confirm:* watch a file, save it from Vim and from VS Code, log events.
3. **Debounce timeout.** 100–300 ms is a guess. Too short → double reloads; too long → sluggish
   live reload.
4. **`AccentColor` → CSS string.** `accent_color_rgba()` returns `RGBA`; whether a hex helper
   exists or formatting is manual is unverified (§4). Minor, but ticket 07 touches it.
5. **UTF-8 byte offsets → JS/GTK string indices** for match highlighting (§6). Real for non-ASCII
   content; unsolved here.
6. **`ignore`'s `WalkParallel` ordering** and how much reordering work the Navigator needs.
   Inferred from the API shape, not tested.
7. **`nucleo`'s two-year release gap.** Judged benign on repo activity + Helix usage, but it is a
   single-maintainer crate. *Would confirm:* skim the commits since 0.5.0 for unreleased fixes.
8. **`v4_18` vs `v4_22` for the `gtk4` feature.** A judgment call (§2); only the `v4_10` floor is
   confirmed.
9. **`webkit6` feature flags.** Concluded ungated by absence of docs.rs annotations (§2) — strong,
   but not the same as reading the source.
10. **Compile time and binary size** for this dependency set. Unmeasured; gtk4 + webkit6 is a
    large tree and an agent iterating on a Linux box will feel it.
