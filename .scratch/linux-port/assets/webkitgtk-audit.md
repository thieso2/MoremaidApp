# WebKitGTK 6.0 audit against the Moremaid rendering pipeline

Research asset for [issues/03-webkitgtk-audit.md](../issues/03-webkitgtk-audit.md).
Date: 2026-08-13. **No Linux hardware was available**; every claim below is either
**confirmed-from-docs** (with a link) or **inferred** (reasoning stated). Nothing here was compiled
or run.

Audited against WebKitGTK **2.52.5** (API version `webkitgtk-6.0`), the version currently in Arch
`extra`, and — per the ticket's re-pointing to Rust — against the **`webkit6` 0.6.1** crate (§10a).

---

## 0. Verdict up front

**The stack decision holds.** Every load-bearing mechanism in `WebView.swift` /
`HTMLGenerator.swift` has a documented WebKitGTK 6.0 counterpart, **and every one of those APIs is
exposed by the `webkit6` Rust crate** (§10a — 31 rows, all confirmed on docs.rs, no inferred
entries). There is **no missing capability that reopens the stack decision**, and no place where a
capable C API sits behind a missing binding.

Three things change shape rather than disappear, and one macOS behaviour genuinely has no
counterpart:

1. **The `file://` base-URI strategy should be replaced with a custom URI scheme.** It is the single
   highest-leverage change: it fixes offline assets, the clipboard secure-context problem, and the
   "absolute local paths outside base_uri kill the web process" hazard in one move.
2. **`PageScripts` needs ~4 small edits**, not a rewrite — the JS bridge API is byte-for-byte the
   same (`window.webkit.messageHandlers.<name>.postMessage(...)`).
3. **Cmd+click has no Linux meaning** — it becomes Ctrl+click / middle-click, read from
   `webkit_navigation_action_get_modifiers()` / `get_mouse_button()`.
4. **Nothing on Linux corresponds to macOS window tabbing** (`NSWindow.tabbingMode`) — see
   "No WebKitGTK equivalent" below. That is a *window-manager* gap, not a WebKitGTK gap, and it is
   really ticket 06's problem, but it is the only genuinely absent thing this audit found.

---

## 1. Capability table

| # | macOS mechanism (file:line) | WebKitGTK 6.0 equivalent | Status | Notes |
|---|---|---|---|---|
| 1 | `webView.loadHTMLString(html, baseURL:)` — one inline doc (`WebView.swift:132`) | `webkit_web_view_load_html(view, content, base_uri)` | **confirmed** | No documented size ceiling. `base_uri` semantics differ dangerously — see §2. |
| 2 | CDN `<script src="https://cdn.jsdelivr.net/…">` (`HTMLGenerator.swift:32-37`) | `webkit_web_context_register_uri_scheme()` + `webkit_uri_scheme_request_finish()` | **confirmed** | Serves from disk or memory via `GInputStream`. See §4. |
| 3 | `config.userContentController.add(handler, name:)` (`WebView.swift:474-476`) | `webkit_user_content_manager_register_script_message_handler(ucm, name, world_name)` | **confirmed** | 6.0 **added the `world_name` parameter**; pass `NULL` for the default world. See §3. |
| 4 | JS side: `window.webkit.messageHandlers.X.postMessage(…)` | **Identical string.** | **confirmed** | Docs state scripts call `window.webkit.messageHandlers.<name>.postMessage(value)`. `PageScripts.swift:116` works unmodified. |
| 5 | `WKScriptMessage.body` as `[String: Any]` / `String` | `script-message-received` signal delivers a `JSCValue` directly | **confirmed** | `WebKitJavascriptResult` was **removed** in 6.0. Host-side unwrapping code differs; the JS side does not. |
| 6 | `WKUserScript(source:injectionTime:forMainFrameOnly:)` (`WebView.swift:477-601`) | `webkit_user_script_new(source, injected_frames, injection_time, allow, block)` + `webkit_user_content_manager_add_script()` | **confirmed** | Same two injection times (document-start / document-end), same main-frame-only option. |
| 7 | `webView.evaluateJavaScript(js)` / `try await …` (11 call sites) | `webkit_web_view_evaluate_javascript(view, script, length, world_name, source_uri, cancellable, cb, data)` + `…_finish()` → `JSCValue` | **confirmed** | Since 2.40. Async-only (so is the macOS API). Replaces the older `run_javascript`. |
| 8 | Structured JS→host return values (JSON strings from `findInPage`, `moremaidGetHeadingList`) | `JSCValue` — read as string, or use `webkit_web_view_call_async_javascript_function()` | **confirmed** | The existing "return a JSON string, decode host-side" pattern ports verbatim. |
| 9 | `decidePolicyFor navigationAction` (`WebView.swift:666`) | `WebKitWebView::decide-policy` → `WebKitNavigationPolicyDecision` → `webkit_policy_decision_use()` / `_ignore()` | **confirmed** | Emitted "when WebKit is requesting the client to decide a policy decision, such as whether to navigate to a page, open a new window…". |
| 10 | `navigationAction.navigationType == .linkActivated` | `webkit_navigation_action_get_navigation_type()` → `WEBKIT_NAVIGATION_TYPE_LINK_CLICKED` | **confirmed** (method) / **inferred** (exact enum constant name) | Method listed on `NavigationAction` in the 6.0 reference; the enum member name was not visible on that page. |
| 11 | `navigationAction.modifierFlags.contains(.command)` | `webkit_navigation_action_get_modifiers()` → `GdkModifierType` bitmask | **confirmed** | "Return the modifier keys". Also `get_mouse_button()` — "GTK+ button values are 1, 2 and 3 for left, middle and right". |
| 12 | External link → `NSWorkspace.shared.open(url)` | `gtk_uri_launcher_new(uri)` + `gtk_uri_launcher_launch()` (GTK 4.10+), or `g_app_info_launch_default_for_uri()` | **inferred** (standard GTK4 API, not verified against a WebKitGTK doc — it is a GTK concern, not a WebKit one) | Under a Flatpak/portal setup this routes through `xdg-open`. Omarchy is not sandboxed, so either works. |
| 13 | `willOpenMenu` + hovered-link hack (`WebView.swift:417`) | `WebKitWebView::context-menu` signal, which carries a `WebKitHitTestResult`; build items with `webkit_context_menu_item_new_from_gaction()`, mutate with `prepend/append/insert/remove` | **confirmed** | **Strictly better than macOS.** The hit-test result gives `webkit_hit_test_result_get_link_uri()` directly — the `linkHover` user script + `currentHoveredLink` hack is unnecessary. Note: in 6.0 the signal **no longer has a `GdkEvent` parameter**. |
| 14 | `linkHover` message → status bar (`WebView.swift:517-533`) | `WebKitWebView::mouse-target-changed` signal `(hit_test_result, modifiers)` | **confirmed** | "emitted when the mouse cursor moves over an element such as a link, image or a media element". **Delete the `linkHover` user script entirely.** |
| 15 | `webView.pageZoom = zoom/100` (`WebView.swift:206`) | `webkit_web_view_set_zoom_level(view, factor)` with `WebKitSettings:zoom-text-only = FALSE` (the default) | **confirmed** | `zoom-text-only=FALSE` scales all view contents, matching `pageZoom`. |
| 16 | `didFinish navigation` → restore scroll (`WebView.swift:648`) | `WebKitWebView::load-changed` with `WEBKIT_LOAD_FINISHED` | **confirmed** | States are STARTED / REDIRECTED / COMMITTED / FINISHED. |
| 17 | `nativeLog` console bridge (`WebView.swift:477-515`) | `WebKitSettings:enable-write-console-messages-to-stdout` (one boolean, since 2.2) | **confirmed** | **Much simpler than macOS.** The ~40-line console-monkeypatch user script can be deleted. If structured capture is needed instead, it requires a web-process extension (`WebKitWebPage::console-message-sent`) — see §8 caveat. |
| 18 | Custom in-page find (`PageScripts.swift:425-540`, JS marks) | Keep the JS as-is; **or** `webkit_web_view_get_find_controller()` → `WebKitFindController` | **confirmed** | Native controller gives `search`/`search_next`/`search_previous`/`count_matches` and `found-text`/`counted-matches`, but **no current-match index**. The app's UI shows "3 of 17", so **keep the JS implementation**. See §7. |
| 19 | `navigator.clipboard.writeText` in copy buttons (`PageScripts.swift:140`) | Same API, **but it is secure-context-gated**. Fix: `webkit_security_manager_register_uri_scheme_as_secure()` on the custom scheme | **confirmed** (secure-context gating; `register_uri_scheme_as_secure` exists) / **inferred** (that registering-as-secure makes it a secure context, hence `navigator.clipboard` defined) | This is the concrete reason to abandon `file://`. See §4.3. Belt-and-braces fallback: post the text over a `copyText` message handler and use `gdk_clipboard_set_text()`. |
| 20 | `preferences.setValue(true, forKey:"allowFileAccessFromFileURLs")` (`WebView.swift:470`) | `webkit_settings_set_allow_file_access_from_file_urls()` (and `…_universal_access_…`) | **confirmed** | Only relevant if you stay on `file://`. Moot under a custom scheme. |
| 21 | `preferences.isElementFullscreenEnabled = true` | `WebKitSettings:enable-fullscreen` | **inferred** (property exists across WebKitSettings versions; not re-verified on the 6.0 page) | Low risk, low importance. |
| 22 | `makeFirstResponder(webView)` (`WebView.swift:209`) | `gtk_widget_grab_focus()` | **inferred** (plain GTK4) | — |
| 23 | `NSPasteboard` copy-markdown (`WebView.swift:376`) | `gdk_clipboard_set_text()` on `gdk_display_get_clipboard()` | **inferred** (plain GTK4) | — |
| 24 | 1 s `Timer` file-hash poll → `reRenderMarkdown(json)` (`WebView.swift:172`) | `GFileMonitor` (inotify) or `g_timeout_add_seconds`, then `evaluate_javascript("reRenderMarkdown(…)")` | **inferred** (plain GLib) | The *JS entry point* is unchanged. Ticket 05 territory. |
| 25 | `openDiagram` → separate `NSWindow` with `diagramPage` HTML (`WebView.swift:627`) | Same message handler → new `GtkWindow` + second `WebKitWebView` loading the diagram HTML | **confirmed** (mechanism) | The diagram page's own `⌘+`/`⌘−` keybindings become `Ctrl+`/`Ctrl−` — page-local JS, trivial. |
| 26 | `prefers-color-scheme` / dark mode | See §6 — **not automatic, and deliberately so.** | **confirmed** | The app forces its own theme via `data-theme`, so this is nearly a non-issue. |
| 27 | `webView.pdf(configuration:)` (`WebView.swift:386`) | `WebKitPrintOperation` printing to a PDF file | **inferred** | **Out of scope for v1** per map.md. Noted only so it isn't mistaken for a hole. |
| 28 | Mermaid rendering of large diagrams | Same JS, same engine family (JavaScriptCore) | **inferred** — see §9 | Two real Linux-specific gotchas found (font resolution, font weight), neither fatal. |

---

## 2. Loading one large inline HTML string

**Size ceiling: none documented.** `webkit_web_view_load_html()` takes a NUL-terminated
`const gchar *content`; the reference gives no length limit
([load_html](https://webkitgtk.org/reference/webkitgtk/stable/method.WebView.load_html.html)).
*(inferred:* the practical ceiling is IPC/memory, far above anything Moremaid produces.*)*

Scale of the payload, measured in this repo (`wc -c` on `Sources/Rendering/`):

| Piece | Bytes |
|---|---|
| `BaseCSS.swift` | 12,679 |
| `ThemeCSS.swift` (10 themes) | 6,165 |
| `TypographyCSS.swift` (6 styles) | 4,615 |
| `PageScripts.swift` | 27,869 |
| `MermaidConfig.swift` | 4,900 |
| `LanguageMaps.swift` | 7,688 |

So ≈ **35–45 KB of inlined CSS+JS per page**, *plus the entire markdown source re-embedded as a JS
string literal* (`var rawMarkdown = …`, `HTMLGenerator.swift:21`). A 1 MB markdown file therefore
produces a >1 MB HTML string, twice (once inline, once again on every `reRenderMarkdown()` call).
That is already true on macOS and works; nothing suggests WebKitGTK is worse. **inferred.**

### 2.1 The `base_uri` trap — read this twice

Verbatim from the docs:

> "Load the given `content` string with the specified `base_uri`. If `base_uri` is not `NULL`,
> relative URLs in the `content` will be resolved against `base_uri` and **absolute local paths must
> be children of the `base_uri`. For security reasons absolute local paths that are not children of
> `base_uri` will cause the web process to terminate.** If you need to include URLs in `content` that
> are local paths in a different directory than `base_uri` you can build a data URI for them. When
> `base_uri` is `NULL`, it defaults to `about:blank`. The mime type of the document will be
> `text/html`."
> — [WebKit.WebView.load_html](https://webkitgtk.org/reference/webkitgtk/stable/method.WebView.load_html.html)
> **confirmed**

Consequences for Moremaid, which sets `baseURL` to the *document's own directory*
(`WebView.swift:131`) so that `![](./img.png)` resolves:

- A markdown file containing `![](/home/user/pictures/x.png)` or `![](../sibling/x.png)` — both
  ordinary in real documents — resolves to an absolute local path **outside** `base_uri` and
  **kills the web process**. On macOS this merely fails to load the image. This is a hard behavioural
  difference and a crash-class bug waiting to happen. **confirmed from the quoted doc**; *inferred*
  that Moremaid's `../` case triggers it.
- Fix: **do not use a `file://` base URI.** Use a custom scheme (§4) whose handler resolves paths
  itself and can 404 politely instead of terminating the process.

---

## 3. JS → native bridge

**Host side (changed in 6.0):**

> "`webkit_user_content_manager_register_script_message_handler_in_world()` and
> `unregister_script_message_handler_in_world()` have been removed" — replace with
> `register_script_message_handler`, which "**have gained parameters to specify the script world to
> use**."
> — [migrating-to-webkitgtk-6.0.md](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/gtk/migrating-to-webkitgtk-6.0.md)
> **confirmed**

Signature (GI/PyGObject rendering):

```
register_script_message_handler(name: str, world_name: str | None = None) → bool
```
— [PyGObject WebKit-6.0 UserContentManager](https://api.pygobject.gnome.org/WebKit-6.0/class-UserContentManager.html) **confirmed**

Also new in 6.0: `register_script_message_handler_with_reply()`, whose signal is
`script-message-with-reply-received` and which hands the host a `WebKitScriptMessageReply` so JS
`postMessage` can `await` a value. **confirmed.** Moremaid does not need it today, but it is the
clean replacement for the current "host evaluates JS that returns a JSON string" round-trips
(`getHeadings`, `findInPage`) if ticket 05 wants to tidy them.

**Second 6.0 change:** `WebKitJavascriptResult` was removed; `script-message-received` "now directly
returns a `JavaScriptCore.Value`". **confirmed** (same migration doc). Host-side unwrapping is
different code; the JS side is unaffected.

### 3.1 Does `PageScripts.swift` need to change for the bridge?

**No — the JS API string is identical.** Docs for WebKit-6.0 state scripts call
`"window.webkit.messageHandlers.<name>.postMessage(value)"`. **confirmed.** So
`PageScripts.swift:116`:

```js
window.webkit.messageHandlers.openDiagram.postMessage({ definition: graphDefinition, theme: ct });
```

is portable verbatim. Same for the `nativeLog` and `linkHover` calls in the `WKUserScript`s — though
both of those user scripts should be *deleted* on Linux (rows 14 and 17) rather than ported.

### 3.2 Known binding wart (matters for ticket 04 — language choice)

In WebKit 6.0 the GJS and Python bindings originally **could not pass `null`/`None` as `world_name`**
("Argument world_name may not be null"); passing `''` silently registered the handler in a *different*
world. Fixed by Michael Catanzaro in
[WebKit PR #11802](https://github.com/WebKit/WebKit/pull/11802), shipped in **2.40.1** (Mar 2023).
— [GNOME Discourse thread](https://discourse.gnome.org/t/registering-message-handler-in-default-world-in-webkit-6-0/14595)
**confirmed.** Arch ships 2.52.5, so this is history — but it is a good illustration that the
introspection-based bindings (Python/GJS/Vala) hit rough edges the C/Rust path does not.

---

## 4. Offline assets — the custom URI scheme

### 4.1 It works

`webkit_web_context_register_uri_scheme(context, scheme, callback, user_data, destroy)`:

> "Register `scheme` in `context`, so that when an URI request with `scheme` is made in the
> `WebKitWebContext`, the `WebKitURISchemeRequestCallback` registered will be called with a
> `WebKitURISchemeRequest`." … "It is possible to handle URI scheme requests asynchronously, by
> calling `g_object_ref()` on the `WebKitURISchemeRequest` and calling
> `webkit_uri_scheme_request_finish()` later."
> — [WebContext.register_uri_scheme](https://webkitgtk.org/reference/webkitgtk/stable/method.WebContext.register_uri_scheme.html)
> **confirmed**

The handler returns a `GInputStream` + length + MIME type. A `GMemoryInputStream` over an embedded
byte array (Rust `include_bytes!`, GResource, Vala/C `GResource`) or a `GFileInputStream` over
`/usr/share/moremaid/vendor/` both work. **confirmed** that the API accepts either; **inferred**
that GResource-embedded assets are the right packaging choice.

`webkit_uri_scheme_request_finish_error()` handles the missing-file case — which is exactly the
graceful failure the `file://` base URI cannot give you (§2.1).

**`register_uri_scheme` is still on `WebKitWebContext` in 6.0** — it did **not** move to
`WebKitNetworkSession`. Confirmed by its presence on the
[6.0 WebContext page](https://webkitgtk.org/reference/webkitgtk/stable/class.WebContext.html).
What moved to `NetworkSession` was cookies/cache/downloads/website-data:

> "WebKit now uses a single global network process for all web contexts, and different network
> sessions can be created and used in the same network process" … "`WebsiteDataManager` now
> auto-created by `NetworkSession`" … "`WebKitWebContext::download-started` signal has been removed."
> — [migration doc](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/gtk/migrating-to-webkitgtk-6.0.md)
> **confirmed**

None of that touches Moremaid, which makes zero network requests once the CDN goes away.

### 4.2 CSP / CORS constraints that bite

- Custom schemes are **subject to CORS**, and "WebKit by default does not allow sending cross-origin
  requests to custom URI schemes by design". Remedy:
  `webkit_security_manager_register_uri_scheme_as_cors_enabled()`. **confirmed** that the method
  exists on the 6.0
  [SecurityManager](https://webkitgtk.org/reference/webkitgtk/stable/class.SecurityManager.html);
  **inferred** that Moremaid needs it (it probably does *not*, because everything is same-origin
  under one scheme — but the Prism autoloader's dynamic `<script>` injection is the one thing worth
  testing).
- **The page emits no CSP header of its own**, and the app controls the whole document. The
  practical CSP risk is not WebKit's default policy but the *inline* `<script>`/`<style>` blocks the
  generator emits — if ticket 05 ever adds a CSP meta tag, `'unsafe-inline'` would be mandatory.
  **inferred.**
- Prism's **autoloader** (`HTMLGenerator.swift:35-36`) sets
  `languages_path = 'https://cdn.jsdelivr.net/…/components/'` and lazy-fetches grammars at runtime.
  Under a custom scheme this becomes `moremaid://prism/components/`, and the handler must serve
  ~290 `prism-*.min.js` files. **inferred** that this is the fiddliest part of de-CDN-ing;
  the alternative is the `codePage` approach already used at `HTMLGenerator.swift:286`
  (`LanguageMaps.prismScriptTags`), i.e. emit explicit `<script>` tags for the languages actually
  present. Flag for ticket 05.

### 4.3 Why the custom scheme is *required*, not merely nicer

`navigator.clipboard.writeText` — used by every code-block Copy button
(`PageScripts.swift:140`) — is **restricted to secure contexts**: "navigator.clipboard is not
present for http:// websites", and `file://` is not a secure context in WebKit.
— [WebKit blog: Async Clipboard API](https://webkit.org/blog/10855/async-clipboard-api/) **confirmed**
(that the API is secure-context-gated); **inferred** (that WebKitGTK treats `file://` as
non-secure — this follows from the spec's potentially-trustworthy-origin definition, but was not
verified against a WebKitGTK-specific source).

`webkit_security_manager_register_uri_scheme_as_secure(sm, "moremaid")` — "Register `scheme` as a
secure scheme" — is the documented lever. **confirmed** that the method exists;
**inferred** that it makes `navigator.clipboard` available.

> **Must verify on hardware.** If registering-as-secure does *not* light up `navigator.clipboard`,
> the fallback is a `copyText` script message handler → `gdk_clipboard_set_text()`. That fallback is
> ~15 lines and is arguably better anyway (no user-gesture requirement, no promise). Ticket 05
> should probably just specify the native path unconditionally and stop depending on
> `navigator.clipboard` at all.

### 4.4 The sandbox

In 6.0 the web-process sandbox is **mandatory**: "`webkit_web_context_set_sandbox_enabled()`
removed"; use `webkit_web_context_add_path_to_sandbox()` for extra directory access. **confirmed**
([migration doc](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/gtk/migrating-to-webkitgtk-6.0.md),
[Catanzaro on sandboxing](https://blogs.gnome.org/mcatanzaro/2020/03/31/sandboxing-webkitgtk-apps/)).

**inferred:** a custom-scheme design sidesteps this almost entirely, because the *UI process*
(unsandboxed) does the file reading in the scheme handler and hands bytes to the web process. If the
Linux port instead served images via `file://`, it would have to `add_path_to_sandbox()` every
directory the user browses — an unbounded, ugly requirement. **This is the second independent reason
to choose the custom scheme.** No source was found stating exactly which paths the default sandbox
blocks; treat the details as unverified.

---

## 5. Link interception, and what replaces Cmd+click

`decide-policy` + `WebKitNavigationPolicyDecision` maps 1:1 onto
`decidePolicyFor navigationAction`. The decision object exposes
`webkit_navigation_policy_decision_get_navigation_action()`, and on the action:

| macOS | WebKitGTK 6.0 | Status |
|---|---|---|
| `navigationAction.navigationType == .linkActivated` | `get_navigation_type() == LINK_CLICKED` | **confirmed** (method) / **inferred** (constant spelling) |
| `navigationAction.request.url` | `get_request()` → `webkit_uri_request_get_uri()` | **confirmed** |
| `.cancel` / `.allow` | `webkit_policy_decision_ignore()` / `_use()` | **confirmed** |
| `modifierFlags.contains(.command)` | `get_modifiers()` → `GdkModifierType` bitmask | **confirmed** |
| — (macOS has no middle-click convention) | `get_mouse_button()` — "GTK+ button values are 1, 2 and 3 for left, middle and right buttons" | **confirmed** |

**Cmd+click has no Linux equivalent and should not be emulated.** The native conventions are:

- **Ctrl+click** (`GDK_CONTROL_MASK`) → open in new tab. This is what every Linux browser does.
- **Middle-click** (`get_mouse_button() == 2`) → open in new tab. Also universal, and Moremaid gets
  it for free from `get_mouse_button()`; the macOS app has no equivalent.
- **Shift+click** (`GDK_SHIFT_MASK`) → open in new window.
- **Context menu → "Open Link in New Tab/Window"** — the `context-menu` signal path (row 13), which
  is *better* on Linux than on macOS because `WebKitHitTestResult` supplies the link URI directly
  and the whole `linkHover` / `currentHoveredLink` / `willOpenMenu` apparatus
  (`WebView.swift:411-458, 517-533`) can be deleted.

Note the 6.0 signature change: "`WebView::context-menu` and `WebView::show-option-menu` no longer
have a `Gdk.Event` parameter". **confirmed.**

One more relevant 6.0 change: **"Process swapping mandatory on cross-site navigation."**
**confirmed.** *inferred:* irrelevant here, because Moremaid `ignore()`s every navigation and
re-loads content itself — it never actually navigates.

---

## 6. Zoom, dark mode, find-in-page

### 6.1 Zoom — clean equivalent
`webkit_web_view_set_zoom_level(view, factor)` with `WebKitSettings:zoom-text-only = FALSE`
(the default) scales all view contents, exactly like `WKWebView.pageZoom`. **confirmed.**
Moremaid's `applyZoom(zoom)` (`WebView.swift:205`) is a one-line port.

### 6.2 `prefers-color-scheme` — deliberately *not* wired to the GTK theme

> **⚠️ SUPERSEDED — see [§13.1](#131--correction-to-62--prefers-color-scheme-does-propagate).**
> This subsection overstates a 2020 commit and is **wrong** in its headline claim.
> `prefers-color-scheme: dark` **does** propagate to the page (supported since 2.25.1); only
> UA-rendered form controls stay light unless the page declares `color-scheme`. Read §13.1 instead.

This is the finding most likely to surprise. WebKit
[bug 197947](https://bugs.webkit.org/show_bug.cgi?id=197947) (RESOLVED FIXED, r255342, Jan 2020)
made **WebKitGTK use a light theme by default regardless of system settings**: it detects a dark GTK
theme by a `-dark` / `:dark` suffix on the theme name and *strips it*, so page content renders
light. Rationale quoted in the bug: "dark themes will never be web-compatible except for websites
that opt-in." **confirmed.**

Implication for Moremaid: **almost none, and that is good news.** The app never relies on
`prefers-color-scheme` — it forces `document.documentElement.setAttribute('data-theme', theme)`
from a persisted preference (`PageScripts.swift:61-75`) and switches at runtime via
`switchTheme(name)` over `evaluate_javascript`. That whole mechanism ports unchanged.

The *shell* is a different question: libadwaita apps should use
`AdwStyleManager:color-scheme` rather than `GtkSettings:gtk-application-prefer-dark-theme`
([libadwaita styles docs](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/styles-and-appearance.html),
[Alice Mikhaylenko on dark style preference](https://blogs.gnome.org/alicem/2021/10/04/dark-style-preference/)) —
**confirmed**. If the Linux app wants "follow system light/dark", it must read
`AdwStyleManager:dark` on the host side and call `switchTheme()` itself. **inferred**, but it is the
obvious design and it is *more* reliable than depending on WebKit's media query. Hand this to
ticket 07 (theming).

### 6.3 Find-in-page — native controller exists but is the wrong tool
`webkit_web_view_get_find_controller()` → `WebKitFindController` with `search()`, `search_next()`,
`search_previous()`, `search_finish()`, `count_matches()`, and signals `found-text`,
`failed-to-find-text`, `counted-matches`. **confirmed**
([FindController](https://webkitgtk.org/reference/webkitgtk/stable/class.FindController.html)).

**But there is no API reporting the *index* of the current match** — only the total. **confirmed**
(nothing on the class page provides it). Moremaid's find UI reports `(current, total)`
(`WebView.swift:333-360`) and supports `findJumpToIndex(i)` for a results list — neither is
expressible with `WebKitFindController`.

**Recommendation: keep `PageScripts.findInPageScript` verbatim.** It is pure DOM code with no WebKit
dependency, it already returns `{current, total}` JSON, and it is the *only* way to keep the existing
UI. The native controller is worth nothing here. → feeds ticket 05.

---

## 7. `PageScripts.swift`: exactly what must change

Reviewed line by line. The client-side JS is **~95% portable verbatim**.

**Unchanged (no edits needed):**
- `themeScript` / `switchTheme` — pure DOM.
- `mermaidInitScript`, `themeVariables` — pure Mermaid config.
- `codeCopyButtonsScript` — *the DOM part*. See below for the clipboard call.
- `markedRenderScript` (markdown-it wiring, slugify, heading IDs, fence aliases, mermaid extraction).
- `liveRerenderScript` (`reRenderMarkdown`, `reRenderCode`) — the host calls these by name over
  `evaluate_javascript`; the names and signatures are unchanged.
- `autoIndexSortScript`, `headingListScript`, `findInPageScript`, `searchHighlightScript`.

**Must change (4 items):**

1. **`openMermaidInNewWindow` — no change to the API string, but keep the try/catch.**
   `window.webkit.messageHandlers.openDiagram.postMessage({...})` is valid on WebKitGTK. **confirmed.**
   *Caveat:* the host must register the handler with the new `(name, world_name)` signature, and the
   JS object passed becomes a `JSCValue` dictionary rather than an `NSDictionary`.
2. **Clipboard (`codeCopyButtonsScript`, line 140).** `navigator.clipboard.writeText` is
   secure-context-gated. Either register the custom scheme as secure (§4.3), or — better —
   replace the call with `window.webkit.messageHandlers.copyText.postMessage(code)` and do it
   natively with `gdk_clipboard_set_text()`.
3. **CDN references in `HTMLGenerator` (not `PageScripts` proper)** — the four
   `https://cdn.jsdelivr.net/...` tags and the `Prism.plugins.autoloader.languages_path` assignment
   become custom-scheme URLs.
4. **Keyboard hints in `diagramPage`** — `title="Zoom In (⌘+)"` and the `e.metaKey` branch in the
   wheel handler (`HTMLGenerator.swift:127, 217`) must become Ctrl. Cosmetic but user-visible.

**Should be deleted rather than ported (the two `WKUserScript`s in `WebView.swift`):**
- The **console monkeypatch** (`WebView.swift:477-515`) → replaced by one boolean,
  `WebKitSettings:enable-write-console-messages-to-stdout`. **confirmed.**
- The **`linkHover` script** (`WebView.swift:517-533`) → replaced by
  `WebKitWebView::mouse-target-changed` + `WebKitHitTestResult`. **confirmed.**

The **heading user script** (`WebView.swift:535-601`, `moremaidGetHeadingList` /
`moremaidGetCurrentHeadingId`) ports verbatim via `webkit_user_script_new(...,
WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END, ...)` + `webkit_user_content_manager_add_script()`.
**confirmed** that the API and both injection times exist.

---

## 8. Mermaid on WebKitGTK

No WebKitGTK-specific Mermaid performance report was found. What *was* found (all from
Tauri/Wails/Warp-class apps that embed WebKitGTK, i.e. real-world usage, not WebKit docs):

- **Generic font families may not resolve, silently blanking all diagram labels.** Reported in
  [warp#9402](https://github.com/warpdotdev/warp/issues/9402): "The SVG renderer fails to resolve
  generic CSS font families (sans-serif, monospace, etc.) used by mermaid when the expected system
  fonts are not installed. Since mermaid defaults to these generic families for all text elements,
  every label disappears silently." **confirmed** (that the report exists); **inferred** (that it
  will bite Moremaid). Mitigation: set explicit `fontFamily` in `mermaid.initialize()` and depend on
  a concrete Arch font package. → ticket 07 (fonts) and ticket 11 (packaging).
- **WebKitGTK renders fonts ~100 weight units heavier than specified** — an open bug affecting
  Tauri/Wails on Linux
  ([writeup](https://medium.com/@dasunnimantha777/fonts-render-too-bold-in-rust-tauri-wails-on-linux-a-webkitgtk-bug-and-how-to-fix-it-8b6a0b27b613)).
  **confirmed** (that this is reported) / **inferred** (that it still applies to 2.52.5 — *not*
  verified; the source is undated relative to current releases). Affects the 6 typography styles
  more than Mermaid. **Must verify on hardware.**
- **Mermaid's own scaling** is the dominant cost and is engine-independent: rendering cost scales
  with nodes and edges, ~3–5× slower per +20 nodes
  ([mermaidcreator](https://www.mermaidcreator.com/blog/mermaid-large-diagram-optimization-performance)).
  **confirmed** as a general Mermaid property.
- Moremaid renders diagrams **sequentially in an `await` loop** (`PageScripts.swift:226-251`) and
  **re-renders every diagram on every 1-second live-reload tick** (`liveRerenderScript`). On a
  document with many diagrams this is already the app's worst performance characteristic on macOS.
  **inferred:** WebKitGTK, especially with `WEBKIT_DISABLE_DMABUF_RENDERER=1` forcing shared-memory
  buffers (§10), will be *slower*, not faster. Worth a diagram-cache note in HANDOFF.md.

JavaScriptCore is the same engine family as macOS WebKit, so raw JS execution should be comparable.
**inferred.**

---

## 9. Arch packaging

| | `webkitgtk-6.0` | `webkit2gtk-4.1` |
|---|---|---|
| Version | **2.52.5-2** | 2.52.5-2 |
| Repo | `extra` (official) | `extra` (official) |
| Download size | **36.2 MB** | 36.08 MB |
| Installed size | **130.8 MB** | 133.52 MB |
| Last updated | **2026-07-14** | — |
| Provides | `libwebkitgtk-6.0.so`, `libjavascriptcoregtk-6.0.so` | `libwebkit2gtk-4.1.so` |
| Deps | 71 | — |
| Reverse deps | 31 packages incl. **epiphany, gnome-builder, gnome-shell, foliate, yelp, font-manager** | — |

Sources: [archlinux.org/packages/extra/x86_64/webkitgtk-6.0](https://archlinux.org/packages/extra/x86_64/webkitgtk-6.0/),
[…/webkit2gtk-4.1](https://archlinux.org/packages/extra/x86_64/webkit2gtk-4.1/). **confirmed.**

**Pick `webkitgtk-6.0`. It is unambiguously the right one:**
> "**webkitgtk-6.0**: This is WebKitGTK for GTK 4 (and libsoup 3), introduced in WebKitGTK 2.40." …
> "**webkit2gtk-4.1**: This is WebKitGTK for GTK 3 and libsoup 3." …
> "All deprecated APIs were removed [in 6.0]."
> — [Catanzaro, *WebKitGTK API Versions Demystified*](https://blogs.gnome.org/mcatanzaro/2025/04/28/webkitgtk-api-versions/)
> **confirmed**

`webkit2gtk-4.1` is GTK **3** and is therefore simply not an option for a GTK4/libadwaita app.
There is no choice to agonise over. PKGBUILD `depends=('gtk4' 'libadwaita' 'webkitgtk-6.0')`.

**Stability:** one stable release every 6 months, aligned with GNOME; 2.52.0 shipped March 2026,
2.54.0 due September 2026
([2.52.0 release note](https://webkitgtk.org/2026/03/18/webkitgtk2.52.0-released.html),
[Catanzaro](https://blogs.gnome.org/mcatanzaro/2025/04/28/webkitgtk-api-versions/)). **confirmed.**
Point releases are frequent (2.52.3 in April 2026). Igalia maintains it; GNOME Web (Epiphany) is
built on the same API, which is the strongest possible signal that everything Moremaid needs is
exercised daily by a shipping browser. **inferred** from the reverse-dependency list.

**Note the ~131 MB installed footprint.** That is 130 MB of dependency for a markdown viewer, but
it is almost certainly *already installed* on an Omarchy box (gnome-shell, yelp, epiphany all pull
it). Worth one sentence in HANDOFF.md, not a reconsideration.

---

## 10. Wayland / Hyprland runtime hazard

Not an API gap, but the single most likely "it builds and shows a blank window" failure:

WebKitGTK's GPU path (hardware compositing + the DMA-BUF renderer) is reported to misbehave across
Wayland compositors — **including Hyprland** — and especially with the NVIDIA proprietary driver,
producing blank/white windows. The ecosystem-standard workaround is to set
`WEBKIT_DISABLE_DMABUF_RENDERER=1` (and sometimes `WEBKIT_DISABLE_COMPOSITING_MODE=1`) before the
WebView initialises, forcing shared-memory buffers.
Sources: [meetily#435](https://github.com/Zackriya-Solutions/meetily/issues/435),
[fluster#11](https://github.com/flusterIO/fluster/issues/11),
[tauri#9394](https://github.com/tauri-apps/tauri/issues/9394),
[wry#1727](https://github.com/tauri-apps/wry/issues/1727) — **confirmed** that these reports exist
and converge on the same workaround; **inferred** whether 2.52.5 on current Mesa still needs it
(the reports span 2024–2025 and many predate current releases).

HANDOFF.md should mention this as a documented first-thing-to-try, not bake the env var in
unconditionally — disabling DMA-BUF costs real rendering performance, which §8 says Moremaid can
least afford. **Must verify on hardware.**

Also relevant: 6.0 removed `WEBKIT_HARDWARE_ACCELERATION_POLICY_ON_DEMAND` from the enum, and
"it is no longer possible to draw scrollbars that match arbitrary GTK themes — WebKit will draw
scrollbars that match the Adwaita GTK theme". **confirmed** (migration doc). The latter is a small
visual-fidelity note for ticket 07: the WebView's scrollbars are Adwaita, full stop.

---

## 10a. Rust binding coverage (`webkit6` crate) — second pass, complete

The ticket was re-pointed mid-audit: the implementation language is now fixed as **Rust**, so a
capable C API behind an incomplete binding is worth nothing. Full crate coverage belongs to
[01-binding-survey.md](../issues/01-binding-survey.md); what follows verifies **every** API this
audit depends on, against **`webkit6` 0.6.1** on docs.rs.

A first pass left five API groups unverified; a second pass closed all five. **There are now no
inferred entries in this section** — every row below was read off a docs.rs page.

| C API this audit relies on | `webkit6` crate | Status |
|---|---|---|
| `webkit_web_view_load_html` | `WebViewExt::load_html` | **confirmed** |
| `webkit_web_view_evaluate_javascript` | `WebViewExt::evaluate_javascript` | **confirmed** |
| `webkit_web_view_set_zoom_level` | `WebViewExt::set_zoom_level` | **confirmed** |
| `webkit_web_view_get_find_controller` | `WebViewExt::find_controller` | **confirmed** |
| `decide-policy` | `WebViewExt::connect_decide_policy` | **confirmed** |
| `load-changed` | `WebViewExt::connect_load_changed` | **confirmed** |
| `context-menu` | `WebViewExt::connect_context_menu` | **confirmed** |
| `mouse-target-changed` | `WebViewExt::connect_mouse_target_changed` | **confirmed** |
| `register_script_message_handler` | `UserContentManager::register_script_message_handler(&self, name: &str, world_name: Option<&str>) -> bool` | **confirmed** |
| `…_with_reply` | `register_script_message_handler_with_reply(&self, name: &str, world_name: Option<&str>) -> bool` | **confirmed** |
| `script-message-received` → `JSCValue` | `connect_script_message_received<F: Fn(&Self, &Value)>(&self, detail: Option<&str>, f: F)` | **confirmed** |
| `webkit_user_content_manager_add_script` | `add_script(&self, script: &UserScript)` | **confirmed** |
| `webkit_web_context_register_uri_scheme` | `WebContext::register_uri_scheme<P: Fn(&URISchemeRequest) + 'static>(&self, scheme: &str, callback: P)` | **confirmed** |
| `webkit_web_context_get_security_manager` | `WebContext::security_manager(&self) -> Option<SecurityManager>` | **confirmed** |
| `webkit_web_context_add_path_to_sandbox` | `WebContext::add_path_to_sandbox(&self, path: impl AsRef<Path>, read_only: bool)` | **confirmed** |
| `webkit_security_manager_register_uri_scheme_as_secure` (§4.3) | `SecurityManager::register_uri_scheme_as_secure(&self, scheme: &str)` | **confirmed** |
| `…_as_cors_enabled` (§4.2) | `SecurityManager::register_uri_scheme_as_cors_enabled(&self, scheme: &str)` | **confirmed** |
| `webkit_uri_scheme_request_finish` (§4.1) | `URISchemeRequest::finish(&self, stream: &impl IsA<InputStream>, stream_length: i64, content_type: Option<&str>)` | **confirmed** |
| `webkit_uri_scheme_request_finish_error` | `URISchemeRequest::finish_error(&self, error: &mut Error)` | **confirmed** |
| — (richer response w/ headers) | `URISchemeRequest::finish_with_response(&self, response: &URISchemeResponse)` | **confirmed** |
| `webkit_navigation_action_get_modifiers` (§5) | `NavigationAction::modifiers(&self) -> u32` | **confirmed** |
| `webkit_navigation_action_get_mouse_button` (§5) | `NavigationAction::mouse_button(&self) -> u32` | **confirmed** |
| `webkit_navigation_action_get_navigation_type` | `NavigationAction::navigation_type(&self) -> NavigationType` | **confirmed** |
| `webkit_hit_test_result_get_link_uri` (§5, row 13/14) | `HitTestResult::link_uri(&self) -> Option<GString>`, `context_is_link(&self) -> bool` | **confirmed** |
| `webkit_context_menu_item_new_from_gaction` (row 13) | `ContextMenuItem::from_gaction(action: &impl IsA<Action>, label: &str, target: Option<&Variant>) -> ContextMenuItem` | **confirmed** |
| `enable-write-console-messages-to-stdout` (row 17) | `Settings::set_enable_write_console_messages_to_stdout(&self, enabled: bool)` | **confirmed** |
| `zoom-text-only` (§6.1) | `Settings::set_zoom_text_only(&self, zoom_text_only: bool)` | **confirmed** |
| `allow-file-access-from-file-urls` (row 20) | `Settings::set_allow_file_access_from_file_urls(&self, allowed: bool)` | **confirmed** |
| `enable-fullscreen` (row 21) | `Settings::set_enable_fullscreen(&self, enabled: bool)` | **confirmed** |
| Web Inspector (dev aid) | `Settings::set_enable_developer_extras(&self, enabled: bool)` | **confirmed** |

Sources: [WebViewExt](https://docs.rs/webkit6/latest/webkit6/prelude/trait.WebViewExt.html),
[UserContentManager](https://docs.rs/webkit6/latest/webkit6/struct.UserContentManager.html),
[WebContext](https://docs.rs/webkit6/latest/webkit6/struct.WebContext.html),
[SecurityManager](https://docs.rs/webkit6/latest/webkit6/struct.SecurityManager.html),
[URISchemeRequest](https://docs.rs/webkit6/latest/webkit6/struct.URISchemeRequest.html),
[NavigationAction](https://docs.rs/webkit6/latest/webkit6/struct.NavigationAction.html),
[HitTestResult](https://docs.rs/webkit6/latest/webkit6/struct.HitTestResult.html),
[ContextMenuItem](https://docs.rs/webkit6/latest/webkit6/struct.ContextMenuItem.html),
[Settings](https://docs.rs/webkit6/latest/webkit6/struct.Settings.html).

**Every API this audit leans on is present in the Rust binding.** The Rust half of the re-pointed
scope is therefore closed: there is no place where a capable C API sits behind a missing binding.
Four ergonomic notes for HANDOFF.md:

- `world_name` is `Option<&str>`, so the GJS/Python "cannot pass null" wart (§3.2) **does not apply
  to Rust** — `None` is expressible. A concrete argument for Rust over the introspection bindings.
- **`NavigationAction::modifiers()` returns a bare `u32`, not a typed `gdk::ModifierType`.** The
  Ctrl/Shift-click test in §5 must compare against `gdk::ModifierType::CONTROL_MASK.bits()` rather
  than using `.contains()`. Small, but exactly the kind of thing that silently compiles and
  misbehaves.
- `URISchemeRequest::finish()` takes any `IsA<gio::InputStream>`, so `gio::MemoryInputStream` over
  `include_bytes!`-embedded vendored assets is a direct fit (§4.1) — no temp files, no GResource
  required.
- `finish_with_response(&URISchemeResponse)` exists as well, which is the route to setting response
  headers if the Prism-autoloader CORS question (§4.2 / §12 item 3) turns out to need them.

**Still owned by ticket 01, not here:** whether `webkit6` 0.6.1 is the version that pairs with the
chosen `gtk4`/`libadwaita`/`glib` crate generation, and the overall crate-set coherence. This
section establishes only that the *capabilities* exist in the binding.

---

## 11. ⚠️ No WebKitGTK equivalent

Read this list as the answer to "what does the macOS version do that cannot be done". It is short,
and **nothing on it is fundamental.**

1. **`NSWindow` native window tabbing** (`NSWindow.tabbingMode = .preferred`, per CLAUDE.md's Window
   Lifecycle section). There is **no GTK4/Wayland equivalent** — no toolkit-level or
   compositor-level window tabbing exists on Hyprland. Tabs must be implemented *inside* the app
   with `AdwTabView`/`AdwTabBar`, which changes the window/tab model materially (one `GtkWindow`
   holding N WebViews, rather than N windows the OS groups). **confirmed** as an absence in the sense
   that no such API was found; **inferred** that `AdwTabView` is the substitute. **This is ticket
   06's problem, and this audit flags it as the one place the port cannot be a translation.**
2. **`WKWebView.pdf(configuration:)` → in-memory PDF data.** WebKitGTK offers
   `WebKitPrintOperation` (print-to-PDF-file via the GTK print dialog), not a one-call
   "give me `Data`". **inferred.** *Out of scope for v1 anyway* (map.md rules out PDF export).
3. **A current-match index from the native find controller.** `WebKitFindController` gives totals,
   never "3 of 17". **confirmed.** Fully worked around by keeping the existing JS find (§6.3), so
   this costs nothing.
4. **`prefers-color-scheme` automatically following the desktop's dark preference.** WebKitGTK
   deliberately forces light. **confirmed.** Costs nothing here because Moremaid forces its own
   theme, but it *would* bite any design that leaned on the media query.
5. **Structured console-message capture in the UI process.** `enable-write-console-messages-to-stdout`
   gives you the text on stdout, which is all `WebView.swift:643-645` actually does with it. Getting
   *structured* messages (level, line, source) requires a **web-process extension**, and the
   migration doc warns: "**the entire web process API may unfortunately be removed in the future**."
   **confirmed.** Recommendation: use the stdout boolean, never write a web-process extension.
6. **`Cmd`-click.** Not a missing API — a missing *platform convention*. Replaced by Ctrl+click /
   middle-click / Shift+click (§5).

Everything else in `WebView.swift`, `HTMLGenerator.swift` and `PageScripts.swift` has a documented
counterpart.

---

## 12. Known unknowns / must verify on hardware

Ordered by how much damage a wrong assumption would do.

1. **Does `register_uri_scheme_as_secure()` actually make `navigator.clipboard` available?**
   (§4.3, *inferred*.) If not, the copy buttons silently fail. Cheap mitigation exists (native
   clipboard over a message handler) — ticket 05 should probably just specify that and remove the
   dependency, making this unknown moot.
2. **Does WebKitGTK 2.52.5 render correctly on Hyprland without `WEBKIT_DISABLE_DMABUF_RENDERER=1`?**
   (§10.) Blank-window class failure. First thing to test on real hardware.
3. **Prism autoloader under a custom scheme** — does dynamic `<script>` injection from
   `moremaid://prism/components/prism-rust.min.js` pass WebKit's checks without
   `register_uri_scheme_as_cors_enabled()`? (§4.2, *inferred*.) Fallback: emit explicit script tags
   for detected languages, as `codePage` already does.
4. **The font-weight-too-bold bug** — still present in 2.52.5? (§8, *inferred*, source undated.)
   Directly affects the 6 typography styles' fidelity → ticket 07.
5. **Mermaid generic-font-family resolution** — do `sans-serif`/`monospace` resolve on a bare
   Omarchy install, or do labels vanish? (§8.) Determines whether HANDOFF.md must name explicit font
   packages as hard dependencies.
6. **Exact `NavigationType` enum variant spelling** for a clicked link (§5, row 10). The Rust type
   `NavigationType` is confirmed to exist (§10a); only the variant name (presumably
   `NavigationType::LinkClicked`) is unverified. Trivial to fix at compile time; noted only for
   honesty. Related and *not* a compile-time catch: `NavigationAction::modifiers()` returns a bare
   `u32`, so a Ctrl-click test written as if it were a typed `gdk::ModifierType` will compile and
   silently misbehave — compare against `gdk::ModifierType::CONTROL_MASK.bits()` (§10a).
7. **`WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END` timing vs. macOS `.atDocumentEnd`** — the heading
   script must run before the host first calls `moremaidGetHeadingList()`. Assumed equivalent;
   **not verified.**
8. **Behaviour of a >1 MB inline HTML string** through the load_html IPC path (§2). No documented
   ceiling, but no evidence anyone has pushed it either. Test with a large markdown file early.
9. **What the mandatory bubblewrap sandbox blocks by default** (§4.4). No authoritative list found.
   Should be irrelevant under the custom-scheme design; would be central under a `file://` design.
10. **Perceived Mermaid render latency** on a 100-node diagram, with and without the DMA-BUF
    renderer (§8). Feeds the still-unset performance targets in map.md's "Not yet specified".

---

## 13. Addendum — third pass, prompted by the 2026-08-13 narrowing

The ticket was narrowed to five *behavioural* questions. Re-reading §§2/4/6/8 against them found
three already answered at depth, **one genuine thin spot**, and **one material error in this
document**. Both are fixed here rather than by rewriting the sections above, so the record of what
changed stays visible.

### 13.1 ⚠️ Correction to §6.2 — `prefers-color-scheme` *does* propagate

**§6.2 above is wrong** where it says WebKitGTK "deliberately does not follow the desktop" and
"forces light". That overstated a 2020 commit. The accurate picture, and it matters for ticket 07:

- **The `prefers-color-scheme` media query has been supported on GTK since WebKitGTK 2.25.1**
  (r244766, April 2019) — [bug 196685](https://bugs.webkit.org/show_bug.cgi?id=196685).
  **confirmed.**
- Detection is `PageClientImpl::effectiveAppearanceIsDark()`, quoted by Carlos Garcia Campos in that
  bug: it checks **`gtk-application-prefer-dark-theme` first**, then `gtk-theme-name` ending in
  `-dark`, then `GTK_THEME` containing `:dark`. **confirmed.**
- What [r255342](https://trac.webkit.org/changeset/255342/webkit) (the bug 197947 fix this document
  leaned on) actually did is narrower than §6.2 claims: it strips `-dark` from the **theme name sent
  to the web process**, so *UA-rendered form controls* stay light. Its own commit message says
  **"The web process is still notified when a dark theme is in use, so that if website prefers a
  dark color scheme it will be used."** **confirmed.**
- The chain therefore closes automatically under libadwaita: **AdwStyleManager sets
  `gtk-application-prefer-dark-theme` when dark is active precisely because "libraries like WebKit
  need a non-libadwaita-specific way to detect if the app is currently dark"**
  ([libadwaita commit discussion](https://mail.gnome.org/archives/commits-list/2021-November/msg10192.html),
  [dialect#217](https://github.com/dialect-app/dialect/issues/217)). **confirmed** that this is the
  stated rationale; **inferred** that the GTK4/`webkitgtk-6.0` port still uses the same
  `effectiveAppearanceIsDark()` heuristic (the quoted code is from the GTK3 era).

**Net effect for Moremaid:** "follow the system light/dark preference" is available **for free** via
the media query — the app does *not* have to plumb `AdwStyleManager` → `switchTheme()` by hand, as
§6.2 asserted. That plumbing remains the right choice anyway, because Moremaid has *ten* named
themes rather than a light/dark pair and must pick a specific one; but the media query is a valid
and simpler fallback for an "Auto" theme option, and ticket 07 should know it exists.

Two caveats that survive the correction:
- **UA-rendered widgets stay light unless the page opts in.** To get dark form controls and
  scrollbars the document must declare `color-scheme: dark` (CSS) or `<meta name="color-scheme">`.
  Worth adding to the generated `<head>` per theme — a one-line change in `HTMLGenerator`.
- The `-dark`-suffix heuristic is **fragile for third-party themes**: a theme named
  `WhiteSur-dark-purple` *contains* but does not *end with* `-dark` and will not be detected. On
  Omarchy with Adwaita this is a non-issue, but it is why the explicit `switchTheme()` path is still
  the primary mechanism. **confirmed** (reported in bug 196685's later comments).

### 13.2 Genuine gap now filled — what `base_uri` must actually be, and the origin trap

§2 analysed `base_uri` only in its `file://` form, and §4 described the scheme handler without ever
saying **what to pass as `base_uri` once you are on a custom scheme**. That is precisely the
narrowed question, and it was not answered. It is now.

**Use one scheme with one host, and put every distinction in the path:**

```
base_uri:  moremaid://app/doc/<percent-encoded-document-dir>/
assets:    moremaid://app/vendor/mermaid.min.js
images:    ./diagram.png  →  moremaid://app/doc/<dir>/diagram.png
```

Why the single host matters — this is the trap:

- A custom-scheme URI **with** a host component gets a normal tuple origin
  (`scheme://host`); a custom-scheme URI **without** one gets an **opaque origin**. The WebKitGTK
  docs state a security origin's host "will be `NULL` if the origin is opaque **or if its protocol
  does not require a host component**"
  ([WebKitSecurityOrigin](https://webkitgtk.org/reference/webkit2gtk/2.30.2/WebKitSecurityOrigin.html)).
  **confirmed.** An opaque origin "is never same-origin with any other origin, including another
  opaque origin", and per spec must not reach the Storage APIs. **confirmed** (MDN / spec).
- Therefore `moremaid:///vendor/x.js` (no host) or `moremaid:/x.js` risks an opaque origin, and
  `moremaid://doc/…` vs `moremaid://vendor/…` are **two different hosts → two different origins →
  cross-origin**, which drags in CORS for what should be a same-document asset load.
- And CORS on custom schemes is deliberately hostile: "WebKit by default does *not* allow sending
  cross-origin requests to custom URI schemes", and **"handlers will *not* receive preflight
  `OPTIONS` requests"** — you would need
  `register_uri_scheme_as_cors_enabled()` *plus* hand-written `Access-Control-Allow-*` headers via
  `finish_with_response()`
  ([Igalia, *Integrating WPE*](https://wpewebkit.org/blog/06-integrating-wpe.html)). **confirmed.**
  All of that vanishes if everything shares one host.

**Status of the base_uri claim itself:** the reference documents `base_uri` behaviour for local
paths but not for custom schemes, so "relative URLs resolve against a `moremaid://app/doc/…/`
base_uri and re-enter the scheme handler" is **inferred** — from ordinary RFC 3986 relative
resolution plus the handler's documented remit ("any load: pages, subresources, the Fetch API,
XmlHttpRequest"). It is the standard pattern for WebKit-family embedders, but it was **not** found
stated verbatim for WebKitGTK. → added as known-unknown #11 in spirit; verify in the first hour on
hardware, because the whole offline-asset design rests on it.

Note also that this dissolves §2.1's web-process-termination hazard rather than merely avoiding it:
the "absolute local paths must be children of `base_uri` … will cause the web process to terminate"
rule is about **local paths**. Once the document's origin is `moremaid://app`, a stray
`![](/home/user/x.png)` is just a failed subresource load the handler can 404 — not a crash.
**inferred**, same confidence as above, and the single strongest argument for the custom scheme.

### 13.3 The other three narrowed bullets — already answered, no change

- **`load_html` size ceiling** → §2. No documented ceiling; payload measured at ~35–45 KB of
  CSS/JS per page plus the full markdown re-embedded as a JS string literal. Unchanged.
- **CSP/sandbox on the custom scheme** → §4.2 / §4.4, now sharpened by §13.2's origin rule. The
  binding CSP constraint is not WebKit policy but the generator's own inline `<script>`/`<style>`
  blocks (`'unsafe-inline'` would be mandatory if a CSP meta tag were ever added). Sandbox is
  sidestepped because the *UI* process reads the files. Unchanged.
- **Mermaid performance** → §8. Nothing further is findable without hardware; the two real Linux
  gotchas (generic font-family resolution, the font-weight bug) are already recorded there.
- **Find-in-page** → §6.3. Exists (`WebKitFindController`), but reports no current-match index, so
  it cannot drive the "3 of 17" UI — keep the JS implementation. Unchanged and definitive.
