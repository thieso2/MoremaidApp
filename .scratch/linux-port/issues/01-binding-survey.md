# Choose the Rust crate set

Type: research
Status: resolved
Blocked by: —

> **Re-scoped 2026-08-13.** This ticket was originally a four-way language survey (Rust / Vala /
> Python / C, plus the Swift-on-Linux question). [The language decision](04-choose-language.md) was
> taken ahead of it — **Rust + gtk4-rs + webkit6-rs** — so the survey's original question is dead.
> What remains, and is still needed before HANDOFF.md can be written, is the crate selection below.
>
> **The original survey was nevertheless completed** (in parallel with the re-scope) and is saved
> at [assets/binding-survey.md](../assets/binding-survey.md). It is *not* an answer to the question
> below, but it pre-answers several of its bullets — see "Prior research" at the foot of this
> ticket. Its main standalone value now is that it **closes the Swift-on-Linux question with
> evidence** (ruled out) and independently corroborates the Rust decision.

## Question

Pin the exact crate set the Linux Moremaid is built from, with versions, so HANDOFF.md's reader
starts from a known-good `Cargo.toml` rather than shopping.

The [port map](11-module-port-map.md) already names the intended crates. Confirm each is real,
maintained, and suitable — and correct it where it isn't:

- **`gtk4` / `libadwaita`** — current versions against what Arch ships. Confirm the libadwaita
  bindings expose `StyleManager` colour-scheme and accent state plus a change signal, which the
  [theming decision](07-theming-strategy.md) depends on entirely.
- **`webkit6`** — the binding crate for WebKitGTK 6.0. Its maturity is the single largest risk in
  the project; the [WebKitGTK audit](03-webkitgtk-audit.md) checks the API surface, this ticket
  checks that the *Rust binding* actually exposes it. A capable C API behind an incomplete binding
  is the same as no API.
- **`ignore`** — ripgrep's walker, replacing both `FileScanner` and `GitignoreParser`. Confirm
  parallel walking, gitignore semantics, and that hidden-file and custom-skip behaviour is
  configurable.
- **`grep-searcher` / `grep-regex`** — in-process content search replacing `ContentSearch`.
  Confirm the API supports the context snippets and match offsets the UI needs for highlighting.
- **`nucleo`** vs **`fuzzy-matcher`** — pick one for Quick Open, on match quality and on whether
  the scoring can be driven incrementally as the user types.
- **`notify`** — file watching. Confirm the inotify backend's behaviour on rename/atomic-save
  (editors write a temp file and rename, which naive watchers miss entirely) and what its
  descriptor cost is per watched directory.
- **`serde` / `toml`** — config parsing, with a commented default file.
- **Opening external links** — `open` crate vs invoking `xdg-open` directly.

Also settle: **is there an async runtime at all?** GTK has its own main loop and `glib` provides
spawning onto it. Pulling in tokio for a desktop app that does directory walks and file reads may
be pure ceremony — decide, and say why.

Deliverable: a `Cargo.toml` dependency block with pinned versions plus one line of justification
each, saved under `.scratch/linux-port/assets/` and linked here. Flag anything that turns out to be
unmaintained or missing — that reopens a decision rather than being worked around quietly.

## Prior research

[assets/binding-survey.md](../assets/binding-survey.md) (the original survey) already establishes,
confirmed from docs:

- **`gtk4` 0.11.4** (2026-06-29), features to `v4_22`, MSRV 1.83 — Arch ships gtk4 **4.22.4**. Exact match.
- **`libadwaita` 0.9.2** (2026-07-07), features to `v1_10` — Arch ships libadwaita **1.9.3**. Binding
  is *ahead* of the distro. (`StyleManager` accent/colour-scheme signals **not yet verified** — still
  this ticket's job.)
- **`webkit6` 0.6.1** (2026-03-11), features to `v2_52` — Arch ships webkitgtk-6.0 **2.52.5**. Exact
  match. **All six APIs the rendering path needs were verified present on docs.rs**: `load_html`,
  `UserContentManager::register_script_message_handler` + `connect_script_message_received`,
  `WebContext::register_uri_scheme`, `connect_decide_policy`, `set_zoom_level`/`zoom_level`,
  `settings`/`set_settings` — plus `evaluate_javascript` and `FindController`. The "incomplete
  binding" risk this ticket names is **retired**. (Caveat: docs.rs reports only 15.8% *prose*
  documentation coverage; the bindings themselves are GIR-generated and complete.)
- **`ignore` 0.4.33** (2026-08-04, BurntSushi/ripgrep) — gitignore + `.ignore` + file-type filters +
  `WalkParallel`. Hidden-file/custom-skip configurability **not yet verified**.
- **`nucleo` / `nucleo-matcher`** — Helix's matcher, ~6× faster than skim/`fuzzy-matcher`, and
  explicitly designed to match on a background threadpool while handing the UI a snapshot without
  blocking. That design point argues for `nucleo` over `fuzzy-matcher` on this ticket's second
  criterion.
- **Async runtime:** the gtk4-rs book's own guidance is `gio::spawn_blocking()` +
  `async-channel` + `glib::spawn_future_local()`, with tokio reserved for crates that demand it
  (`reqwest` etc.). Moremaid has no such crate. Evidence favours **no tokio**.

Still untouched by that asset: `grep-searcher`/`grep-regex`, `notify` rename/atomic-save behaviour
and fd cost, `serde`/`toml`, and the `open`-vs-`xdg-open` question.

## Answer

Full crate set with pinned versions, feature flags and justification:
**[crate-set.md](../assets/crate-set.md)** — the canonical asset.
([cargo-toml.md](../assets/cargo-toml.md) was the first pass; it is now a stub pointing there, its
unique findings merged in and credited. Two passes ran concurrently on 2026-08-13; see
*Reconciliation* below for the four corrections and two open choices.)
Everything below was checked against crates.io and docs.rs on 2026-08-13 rather than recalled.

**Headline: the JS↔native bridge is confirmed at the Rust binding level, not just the C level.**
This was the largest single risk on the map. `webkit6` 0.6.x exposes
`UserContentManager::register_script_message_handler` + `connect_script_message_received`
(the `WKScriptMessageHandler` equivalent), `WebContext::register_uri_scheme` (offline assets), and
on the `WebViewExt` trait: `load_html`, `evaluate_javascript`,
`call_async_javascript_function`, `set_zoom_level`, `connect_decide_policy`, `connect_load_changed`,
`settings`/`set_settings`. [The language decision](04-choose-language.md) and
[the rendering-layer decision](05-rendering-layer-strategy.md) both stand.

**The set:** `gtk4` 0.11 (`v4_20`), `libadwaita` 0.9 (`v1_6`), `webkit6` 0.6, `ignore` 0.4,
`grep-searcher` 0.1 + `grep-regex` 0.1, `nucleo-matcher` 0.3, `notify` 8 +
`notify-debouncer-full` 0.7, `serde` 1 + `toml` 1, `open` 5, `async-channel` 2.

**`libadwaita`'s `v1_6` feature is load-bearing.** `accent_color()`, `accent_color_rgba()` and
`connect_accent_color_notify()` are gated behind it, and [the theming
decision](07-theming-strategy.md) — derive the palette from the system theme, follow it live — rests
entirely on them. Arch's 1.9.3 satisfies it.

**No async runtime.** GTK owns the main loop; a second runtime beside it is ceremony with a
synchronisation hazard attached. `glib::spawn_future_local` for widget-touching work,
`gio::spawn_blocking` for the walk and the search, `async-channel` to stream results back — which
also gives Quick Open and Find in Files their incremental "results appear as found" behaviour for
free. No tokio.

**Three things flagged for HANDOFF.md:**

1. **Watch the parent directory, not the file — and debounce.** Editors save atomically (write
   temp, rename over target); inotify watches the *inode*, so a watch on the file goes permanently
   deaf after the first save. Every neovim save looks like this, so on this desktop it is the
   normal path, not an edge case. One save emits 3–5 events, which is why
   `notify-debouncer-full` is a required dependency. This confirms dropping the macOS 1-second
   content-hash polling, but note *why* that polling worked: it was immune to this problem.
2. **`nucleo-matcher` is quiet** (0.3.1, February 2024) though in daily use as Helix's matcher;
   `fuzzy-matcher` is genuinely stale (2020). If it's dead by implementation time the exit is free:
   `Sources/Search/FuzzyMatcher.swift` is short, self-contained, and porting it would make Linux
   ranking match macOS exactly.
3. **`webkit6` is the thinnest crate in the set** — 143k downloads against `ignore`'s 157M, and
   docs.rs reports it 15.8% documented. Signatures are GIR-generated and reliable; behavioural prose
   isn't there, so expect to read the C docs for semantics. An unfixed upstream bug here would have
   no easy workaround.

**Also recorded:** `webkitgtk-6.0` on Arch is **130.8 MB installed with 71 dependencies** — most of
the app's install footprint, and worth stating plainly in HANDOFF.md. And there is no dedicated
print-to-PDF method on `WebViewExt` (only `connect_print`), which doesn't matter while PDF export is
out of scope but shouldn't be silently assumed.

---

### Correction (2026-08-13, after [02](02-hyprland-conventions.md) resolved)

The answer above calls `libadwaita`'s `v1_6` feature **load-bearing**, on the grounds that
`accent_color()` / `accent_color_rgba()` / `connect_accent_color_notify()` carry the theming
decision. That reasoning is **wrong for this desktop**: the Hyprland/Omarchy research found that
Omarchy publishes **no accent colour to the Settings portal at all** — `StyleManager` yields only a
light/dark bit, and the palette has to come from `colors.toml` instead.

What survives: `v1_6` is still the right floor and costs nothing (Arch ships 1.9.3), and
`connect_dark_notify` / `color_scheme` are still used. But the accent API is **not** what the
theming decision stands on, and HANDOFF.md must not imply that it is. The mechanism now belongs to
[Decide how the app reads the Omarchy palette](15-omarchy-palette-source.md).

Unaffected: every other crate, the version pins, the no-async-runtime decision, and the three
flagged risks (parent-directory watching, `nucleo-matcher` staleness, `webkit6` thinness).

---

### Reconciliation (2026-08-13) — canonical asset is [crate-set.md](../assets/crate-set.md)

Two crate-set passes ran concurrently, by the same method (crates.io + docs.rs, same day). They
agree on the headline, the set, the `v1_6` floor, the no-async-runtime decision and
`notify-debouncer-full` being required. `cargo-toml.md` is now a stub; its unique findings — the
inode/atomic-save mechanism, `gio` arriving re-exported, no print-to-PDF on `WebViewExt`, the
`webkit6`-thinness note, `notify` 9.0.0-rc in flight — are merged into `crate-set.md` and credited.

**Four corrections to the set above:**

1. **`grep-matcher` 0.1.9 is missing.** `SinkMatch` yields the matching **line** plus
   `line_number()` and `absolute_byte_offset()` — but **not the span of the match within the
   line**, which is what a highlight paints. That comes from `Matcher::find_iter` →
   `Match{start,end}`, relative to the line, and it handles multiple matches per line, which
   `SinkMatch` cannot express. Add it as a direct dependency.
2. **`ignore`'s `require_git` defaults to `true`** — `.gitignore` is honoured **only inside a git
   repo**. Moremaid opens arbitrary folders, so this needs `require_git(false)`. One line, easy to
   miss, silently wrong without it. (Also `hidden(true)` means *ignore* hidden files — the
   polarity reads backwards.)
3. **`toml` cannot emit a *commented* default config**, which this ticket explicitly asked for and
   neither pass had answered. Serde emitters write values, not comments. Ship a hand-written
   `default-config.toml` via `include_str!` and write it on first run; `toml_edit` is needed only
   if the app ever writes config back, which nothing in v1 does.
4. **`fuzzy-matcher` is formally archived** — `skim-rs/fuzzy-matcher`, read-only, last pushed
   2024-06-29 — not merely "stale (2020)". This kills **the port map's** "`nucleo` (or
   `fuzzy-matcher`)" alternative in [11](11-module-port-map.md). ⚠️ It does **not** touch the
   "free exit" cited above and in map.md: that exit is *porting `FuzzyMatcher.swift`*, which is
   intact and unaffected. By contrast `nucleo`'s own quiet release record is benign — repo pushed
   **2026-06-24**, author states the matcher is *"finished… breaking changes expected to be very
   rare"*: declared completion, not abandonment.

**On the script-message payload — a documentation gap, not a missing dependency.** An earlier
draft of the reconciliation claimed `javascriptcore6` was a *required* crate; **that was wrong and
is withdrawn.** `webkit6` re-exports it (`pub use javascriptcore;`, verified in the crate's
docs.rs re-export list), and `Value`'s accessors are inherent methods, so no dependency line and
no prelude import are needed. What *is* worth fixing: neither pass says **what `Value` is**. It is
a JavaScriptCore value, reachable as `webkit6::javascriptcore::Value`, read with
`object_get_property` / `to_str` / `is_object`. A reader seeing a bare `&Value` will guess
`glib::Variant` and lose an hour. HANDOFF.md should say so in one sentence. *(Simpler alternative
for [ticket 03](03-webkitgtk-audit.md): `postMessage(JSON.stringify(…))` + `serde_json`, skipping
the JSC object graph entirely.)*

**Two open choices, recorded rather than resolved:**

- **`nucleo` 0.5 (worker) vs `nucleo-matcher` 0.3 (matcher).** The worker is what answers this
  ticket's *"driven incrementally as the user types"* criterion by name:
  `MultiPattern::reparse(…, append: bool)` — *"the caller promises that text passed to the
  previous reparse invocation is a prefix of new_text… enables additional optimizations"* — plus
  `Nucleo::new(config, notify: Arc<dyn Fn() + Sync + Send>, …)`. Both absent from bare
  `nucleo-matcher`. The counter-argument (worker/tick is redundant when `async-channel` already
  carries results) is coherent. Same repo either way; switching later is small.
- **`gtk4::UriLauncher` vs the `open` crate** for external links. UriLauncher adds zero
  dependencies, is async with a reportable `Result`, and takes a **parent window** so the
  compositor can route activation. ✅ **Ticket 02 independently reached the same conclusion from
  GTK's source** — `GtkUriLauncher` takes the portal path when available, and its verdict was
  *"use `GtkUriLauncher`; do not shell out to `xdg-open`."* On current evidence this one looks
  settled in UriLauncher's favour.

**One structural check neither answer recorded:** `libadwaita` 0.9.2 and `webkit6` 0.6.1 both
require `gtk4 ^0.11`, `glib ^0.22`, `gio ^0.22`, `gdk4 ^0.11` (crates.io dependency API).
**They unify** — no conflict, no `[patch]`. That is the likeliest thing to sink a hand-written
`Cargo.toml`, and it holds.

**On `v1_6` being "load-bearing"** — see the Correction above; `crate-set.md` §4 now separates the
two claims explicitly. The *binding* exposes accent (confirmed); the *desktop* never populates it
(ticket 02). `v1_6` stays as a free, harmless floor, but nothing in v1 depends on what it unlocks.
