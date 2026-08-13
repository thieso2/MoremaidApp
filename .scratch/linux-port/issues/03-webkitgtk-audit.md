# Audit WebKitGTK 6 against the rendering pipeline

Type: research
Status: resolved
Blocked by: —

> **Re-pointed 2026-08-13.** The language is now fixed as **Rust**, so every finding here must be
> checked twice: once against the WebKitGTK 6.0 C API, and once against whether the `webkit6` Rust
> binding actually exposes it. A capable C API behind an incomplete binding is the same as no API.
> Crate-level coverage is tracked in [the crate set ticket](01-binding-survey.md); this ticket owns
> the capability question itself.
>
> **Narrowed 2026-08-13** by [the crate set](01-binding-survey.md), which confirmed the binding
> surface directly on docs.rs: `register_script_message_handler` / `connect_script_message_received`,
> `WebContext::register_uri_scheme`, and `WebViewExt::{load_html, evaluate_javascript,
> call_async_javascript_function, set_zoom_level, connect_decide_policy, connect_load_changed,
> settings}` all exist. **The "does the bridge exist" half of this ticket is answered — skip it.**
> What remains is *behaviour*, which the Rust docs don't cover (the crate is 15.8% documented, so
> semantics have to come from the WebKitGTK C documentation):
>
> - the size ceiling, if any, on `load_html`, and what `base_uri` must be set to for the custom
>   scheme to resolve relative asset paths
> - CSP and sandbox constraints on a custom URI scheme serving the vendored JS — the one place the
>   offline-assets decision could still fail
> - `prefers-color-scheme` propagation into the page, which the theming decision assumes
> - Mermaid render performance on large diagrams under WebKitGTK
> - whether find-in-page exists and is worth using
>
> Already recorded, don't re-derive: `webkitgtk-6.0` is 130.8 MB installed with 71 deps on Arch, and
> there is no dedicated print-to-PDF method (only `connect_print`).

## Narrowed scope: where these are already answered

The narrowing landed after [assets/webkitgtk-audit.md](../assets/webkitgtk-audit.md) was completed,
so four of the five bullets were already covered. Re-checking them skeptically turned up **one real
gap and one error in the audit** — both now fixed in the asset's new §13. Findings stated inline so
this is a one-read decision. **`Status:` deliberately left as-is for the narrowing session to close.**

| Narrowed bullet | Where | Verdict |
|---|---|---|
| `load_html` size ceiling | §2 | **Answered.** No documented ceiling. Payload is ~35–45 KB CSS/JS per page *plus* the whole markdown re-embedded as a JS string literal (so a 1 MB doc ships >1 MB of HTML, twice). |
| What `base_uri` must be for a custom scheme | **§13.2 (new)** | **Was a genuine gap — now filled.** See below. |
| CSP / sandbox on the custom scheme | §4.2, §4.4, sharpened by §13.2 | **Answered.** Binding CSP constraint is the generator's own inline `<script>`/`<style>` (would need `'unsafe-inline'` if a CSP tag were added), not WebKit policy. Sandbox is sidestepped: the *UI* process reads files and hands bytes to the web process. |
| `prefers-color-scheme` propagation | **§13.1 (new)** — supersedes §6.2 | **The audit was WRONG. Corrected.** See below. |
| Mermaid perf on large diagrams | §8 | **Answered** as far as paper allows. Two real Linux gotchas: generic font-families may silently blank all labels; a WebKitGTK bug renders fonts ~100 weight units heavy. |
| Find-in-page — exists, worth using? | §6.3 | **Answered, definitive: exists, not worth using.** `WebKitFindController` gives totals but **no current-match index**, so it cannot drive the existing "3 of 17" UI. Keep the JS implementation — it is pure DOM with no WebKit dependency. |

**§13.2 — the gap.** §2 analysed `base_uri` only in its `file://` form; §4 described the scheme
handler without ever saying what to *pass* as `base_uri`. The answer, and a non-obvious trap:
use **one scheme with one host**, with every distinction in the path —
`base_uri = moremaid://app/doc/<dir>/`, assets at `moremaid://app/vendor/…`. A custom-scheme URI
**without** a host component gets an **opaque origin** (never same-origin with anything, no Storage
APIs), and `moremaid://doc/…` vs `moremaid://vendor/…` are *different hosts → different origins →
cross-origin*, which drags in CORS — where WebKit "does not allow cross-origin requests to custom
URI schemes" by default and **does not even send preflight `OPTIONS`** to handlers. One host makes
all of that disappear. Bonus: this *dissolves* rather than dodges §2.1's web-process-termination
hazard — that rule is about local paths, so once the origin is `moremaid://app`, a stray
`![](/abs/path.png)` is a 404 the handler controls, not a crash. Flagged **inferred**: the reference
documents `base_uri` for local paths but never for custom schemes, so verify in hour one on hardware.

**§13.1 — the error.** §6.2 claimed WebKitGTK "deliberately does not follow the desktop" and
"forces light". That overstated a 2020 commit and is **wrong**. `prefers-color-scheme` has been
supported on GTK since **2.25.1** (r244766, 2019); detection checks
**`gtk-application-prefer-dark-theme` first**. The 2020 fix (r255342) only strips `-dark` from the
*theme name* so UA form controls stay light — its own commit message says *"The web process is still
notified when a dark theme is in use, so that if website prefers a dark color scheme it will be
used."* And **libadwaita sets `gtk-application-prefer-dark-theme` specifically because "libraries
like WebKit need a non-libadwaita-specific way to detect if the app is currently dark."** So the
chain closes automatically. **Consequence for ticket 07:** an "Auto" theme is available *for free*
via the media query. The explicit `AdwStyleManager` → `switchTheme()` path is still primary (ten
named themes, not a light/dark pair), but §6.2 was wrong to say the media query is unavailable.
Caveat that survives: to get dark *form controls/scrollbars* the document must declare
`color-scheme` — a one-line `HTMLGenerator` addition.

§6.2 now carries a SUPERSEDED banner pointing at §13.1 so nobody lands on the stale claim.

## Question

The whole stack decision rests on WebKitGTK 6.0 being able to do what `WKWebView` does here.
With no Linux box to prototype on, this audit is the only thing standing between the spec and a
wrong assumption. Verify against **documentation and real-world usage**, and mark each finding as
confirmed-from-docs or inferred.

The macOS pipeline (`Sources/Rendering/HTMLGenerator.swift`, `Sources/FileBrowser/WebView.swift`)
does the following — check each against WebKitGTK 6:

- **Loads one large inline HTML string** with all CSS and JS embedded, no local file server.
  Is there a size ceiling? What base URI is needed for relative resources?
- **JS → native bridge.** macOS uses `window.webkit.messageHandlers.swift.postMessage({type, ...})`
  with message types `linkClick`, `headings`, `loadComplete`, `externalLink`. What is the
  WebKitGTK equivalent (`webkit_user_content_manager_register_script_message_handler`), and does
  the JS-side API differ enough to require changes to `PageScripts.swift`?
- **Native → JS.** Evaluating JS from the host to trigger re-render, theme change, scroll-to-anchor.
- **Link interception.** Routing internal `.md` links in-app while external links go to the
  browser — the `decide-policy` signal. Also: what replaces Cmd+click for "open in new window"?
- **Offline assets.** markdown-it, Prism.js and Mermaid.js currently come from a CDN. Confirm the
  custom URI scheme handler (`webkit_web_context_register_uri_scheme`) can serve them from disk
  or memory, and note any CSP/sandbox constraints that bite.
- **Zoom**, **`prefers-color-scheme` / dark mode**, and **find-in-page** if it exists.
- **Mermaid performance** — any known issues rendering large diagrams in WebKitGTK.
- **Arch packaging** — which package provides WebKitGTK 6.0, its size, and its stability.

Deliverable: a markdown audit under `.scratch/linux-port/assets/`, linked here, with an explicit
list of **anything the macOS version does that has no WebKitGTK equivalent**. If something
fundamental is missing, say so loudly — it reopens the stack decision.

## Answer

Full audit: [assets/webkitgtk-audit.md](../assets/webkitgtk-audit.md) — 28-row C-API capability
table (§1) plus a 31-row Rust-binding table (§10a), every finding marked confirmed-from-docs (with
link) or inferred.

**The stack decision holds** — on both halves of the re-pointed scope. Nothing fundamental is
missing. Every load-bearing mechanism in `WebView.swift` / `HTMLGenerator.swift` has a documented
WebKitGTK 6.0 counterpart, **and every one of those APIs is confirmed present in the `webkit6` 0.6.1
crate** (§10a contains no inferred entries — the five groups left unverified on the first pass were
all closed on a second pass: `SecurityManager::register_uri_scheme_as_secure`,
`URISchemeRequest::finish`/`finish_error`/`finish_with_response`, `NavigationAction::modifiers`/
`mouse_button`/`navigation_type`, `HitTestResult::link_uri`, `ContextMenuItem::from_gaction`, and
the four `Settings` accessors). There is no place where a capable C API sits behind a missing
binding.

Headline findings:

- **The JS bridge is byte-identical.** `window.webkit.messageHandlers.<name>.postMessage(…)` is the
  documented WebKit-6.0 JS API. `PageScripts.swift` is ~95% portable verbatim. Host side changed:
  `register_script_message_handler` gained a `world_name` param, and `WebKitJavascriptResult` was
  removed (the signal now hands you a `JSCValue` directly).
- **Replace the `file://` base URI with a custom URI scheme.** Highest-leverage decision in the port.
  `load_html`'s docs are explicit: absolute local paths outside `base_uri` **terminate the web
  process** — so `![](/abs/path.png)` or `![](../sib/x.png)` in a markdown file is a crash, not a
  broken image. A custom scheme also fixes offline assets *and* the clipboard secure-context problem
  *and* sidesteps the now-mandatory bubblewrap sandbox. Three problems, one move.
- **`navigator.clipboard` is secure-context-gated** and `file://` is not secure — the Copy buttons
  would silently fail. Fix via `register_uri_scheme_as_secure`, or better, drop the web API and copy
  natively over a message handler.
- **Cmd+click has no Linux meaning** → Ctrl+click / middle-click / Shift+click, read from
  `NavigationAction::modifiers()` / `mouse_button()`. Middle-click is a *gain* over macOS. Rust
  wart: `modifiers()` returns a bare `u32`, not a typed `gdk::ModifierType` — compare against
  `CONTROL_MASK.bits()` or it compiles and silently misbehaves.
- **Two macOS hacks can be deleted outright**: the `linkHover` user script (→
  `mouse-target-changed` + `HitTestResult`) and the 40-line console monkeypatch (→ one boolean,
  `enable-write-console-messages-to-stdout`).
- **Keep the JS find-in-page.** `WebKitFindController` reports totals but never a current-match
  index, so it cannot drive the existing "3 of 17" UI.
- **`prefers-color-scheme` deliberately does not follow the desktop** (WebKit bug 197947, forces
  light). Costs nothing — the app forces its own `data-theme` — but ticket 07 must drive dark mode
  from `AdwStyleManager`, not the media query.
- **Arch:** `webkitgtk-6.0` 2.52.5, `extra`, 36.2 MB download / 130.8 MB installed, 6-month release
  cadence, 31 reverse deps including Epiphany and gnome-shell. `webkit2gtk-4.1` is GTK **3** and is
  simply not an option. No choice to agonise over.

**No equivalent** (§11): native `NSWindow` tabbing (→ `AdwTabView`, ticket 06 — the one place the
port cannot be a translation); `WKWebView.pdf()` returning in-memory data (out of scope); a
current-match index from the native find controller; automatic `prefers-color-scheme`; structured
console capture in the UI process. None fatal.

**Biggest hardware risks** (§12): does `register_uri_scheme_as_secure` actually enable
`navigator.clipboard`; does WebKitGTK render on Hyprland without `WEBKIT_DISABLE_DMABUF_RENDERER=1`;
does Prism's autoloader work under a custom scheme; do Mermaid's generic font families resolve on a
bare Omarchy install.
