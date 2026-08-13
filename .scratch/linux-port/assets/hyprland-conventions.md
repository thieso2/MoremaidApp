# Hyprland / Omarchy application conventions

Research asset for [issue 02](../issues/02-hyprland-conventions.md). Feeds tickets
[06 window model](../issues/06-window-model.md), [07 theming](../issues/07-theming-strategy.md),
[08 keyboard map](../issues/08-keyboard-map.md), and the packaging tickets.

**No Linux hardware was available.** Every finding below is tagged:

- **[C]** = *confirmed-from-source-or-docs* — read out of the actual Omarchy / Hyprland / GTK /
  libadwaita / xdg-desktop-portal source tree or official docs, link given.
- **[I]** = *inferred* — a conclusion drawn by composing confirmed facts, never observed running.
  Treat every **[I]** as a hypothesis that HANDOFF.md must carry into its known-unknowns list.

Research date: 2026-08-13. Omarchy default branch at that date: **`quattro`** (not `master` —
`master` is the older, pre-Lua generation and its `config/hypr/*.conf` files are stale; do not
read them). All Omarchy citations below are from `quattro`.

---

## 0. The concrete environment we are targeting

| Thing | Value | Tag |
|---|---|---|
| Compositor | Hyprland `0.56.2` (Arch `extra`) | **[C]** [archlinux.org](https://archlinux.org/packages/extra/x86_64/hyprland/) |
| GTK4 | `4.22.4` (Arch `extra`); `4.23.3` in `gnome-unstable` | **[C]** |
| libadwaita | `1.9.3` (Arch `extra`); `1.10beta.1` in `gnome-unstable` | **[C]** |
| WebKitGTK | `webkitgtk-6.0` `2.52.5` (Arch `extra`) — the GTK4 API series | **[C]** |
| Portals installed by Omarchy | `xdg-desktop-portal-gtk` **and** `xdg-desktop-portal-hyprland` | **[C]** [`install/omarchy-base.packages`](https://github.com/basecamp/omarchy/blob/quattro/install/omarchy-base.packages) |
| File manager | `nautilus` (+ `nautilus-python`, `sushi`, `gnome-disk-utility`) | **[C]** same file |
| Session | `uwsm` + `sddm`, `XDG_CURRENT_DESKTOP=Hyprland` | **[C]** [`default/hypr/envs.lua`](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/envs.lua) |
| Fonts shipped | `noto-fonts{,-cjk,-emoji}`, `ttf-jetbrains-mono-nerd-basic`, **`ttf-ia-writer`**, `woff2-font-awesome`, `cantarell-fonts` (transitive via GTK) | **[C]** |
| Shell / bar | `quickshell-git` — "the Omarchy shell" (bar, menu, notifications, OSD, lock, tray) | **[C]** |

**`webkitgtk-6.0` is NOT in Omarchy's base package set.** **[C]** It is in Arch `extra`, so it is a
one-line `depends=()` entry in the PKGBUILD, but it is a ~100 MB dependency the user does not
already have. Packaging ticket input.

Also note: `gtk4` and `libadwaita` are *not* explicitly in the base set either; they arrive
transitively via `nautilus` / `evince` / `pinta`. **[C]** They will be present on every Omarchy box
in practice. **[I]**

---

## 1. Decorations — CSD vs SSD

### 1.1 Hyprland flatly refuses CSD

Hyprland implements **both** decoration-negotiation protocols and answers **server-side to
everything, always**:

- `zxdg_decoration_manager_v1`: `xdgDefaultModeCSD()` returns `MODE_SERVER_SIDE`;
  `xdgModeOnRequestCSD()` ignores what the client asked for and returns the same.
  **[C]** [`src/protocols/XDGDecoration.cpp`](https://github.com/hyprwm/Hyprland/blob/main/src/protocols/XDGDecoration.cpp)
- `org_kde_kwin_server_decoration_manager`: on bind it immediately sends
  `default_mode = MODE_SERVER`, with the source comment
  *"send default mode of SSD, as Hyprland will never ask for CSD. Screw Gnome and GTK."*
  **[C]** [`src/protocols/ServerDecorationKDE.cpp`](https://github.com/hyprwm/Hyprland/blob/main/src/protocols/ServerDecorationKDE.cpp)

Hyprland's "server-side decoration" is **a border and nothing else** — no titlebar, no buttons.
Omarchy's defaults: `border_size = 2`, `gaps_in = 5`, `gaps_out = 10`, `rounding = 0`, no shadow,
no blur, layout `dwindle`. **[C]** [`default/hypr/looknfeel.lua`](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/looknfeel.lua)

### 1.2 What GTK4 actually does with that

GTK4 has **no `xdg-decoration` support at all** — a repo-wide search of `GNOME/gtk` for
`xdg_decoration` returns nothing; only the deprecated KDE `server-decoration.xml` is vendored.
**[C]** [`gdk/wayland/protocol/server-decoration.xml`](https://github.com/GNOME/gtk/blob/main/gdk/wayland/protocol/server-decoration.xml)

But GTK4 *does* honour the KDE protocol's default mode, and this is the crux:

```c
/* gtk/gtkwindow.c */
static gboolean
gtk_window_should_use_csd (GtkWindow *window)
{
  if (!priv->decorated) return FALSE;
  ...
  if (GDK_IS_WAYLAND_DISPLAY (...))
    return !gdk_wayland_display_prefers_ssd (gdk_display);
  ...
}

/* gdk/wayland/gdkdisplay-wayland.c */
gboolean
gdk_wayland_display_prefers_ssd (GdkDisplay *display)
{
  if (display_wayland->server_decoration_manager)
    return display_wayland->server_decoration_mode == ORG_KDE_KWIN_SERVER_DECORATION_MANAGER_MODE_SERVER;
  return FALSE;
}
```
**[C]** [gtkwindow.c](https://github.com/GNOME/gtk/blob/main/gtk/gtkwindow.c),
[gdkdisplay-wayland.c](https://github.com/GNOME/gtk/blob/main/gdk/wayland/gdkdisplay-wayland.c)

Hyprland announces `MODE_SERVER` → `prefers_ssd() == TRUE` → `gtk_window_should_use_csd() == FALSE`
→ **a plain `GtkApplicationWindow` under Hyprland gets no GTK titlebar, no client shadow, no
rounded CSD corners.** It is a bare rectangle inside Hyprland's 2px border. **[I]** (the chain is
confirmed line-by-line; the visual result is not observed)

### 1.3 …unless you set a titlebar, which libadwaita always does

`gtk_window_set_titlebar()` unconditionally calls `gtk_window_enable_csd()`, sets
`client_decorated = TRUE`, and adds the `.csd` CSS class — *regardless of what the compositor
prefers*. Only GTK's implicit fallback titlebar is suppressed by `prefers_ssd`. **[C]** gtkwindow.c

And `AdwWindow` / `AdwApplicationWindow` install an invisible gizmo as the titlebar in `_init`,
and `g_error()` if you try to replace it:

```c
priv->titlebar = adw_gizmo_new_with_role ("nothing", GTK_ACCESSIBLE_ROLE_PRESENTATION, ...);
gtk_widget_set_visible (priv->titlebar, FALSE);
gtk_window_set_titlebar (GTK_WINDOW (self), priv->titlebar);
...
g_error ("gtk_window_set_titlebar() is not supported for AdwWindow");
```
**[C]** [`src/adw-window.c`](https://github.com/GNOME/libadwaita/blob/main/src/adw-window.c)

So:

| Window class | Titlebar under Hyprland | `.csd` class (→ Adwaita rounded corners + shadow margin) |
|---|---|---|
| `GtkApplicationWindow`, no explicit titlebar | none | no |
| `GtkApplicationWindow` + `gtk_window_set_titlebar(AdwHeaderBar)` | headerbar drawn | **yes** |
| `AdwApplicationWindow` (any content) | none from GTK; whatever `AdwToolbarView` holds | **yes** (invisible gizmo still enables CSD) |

**Consequence [I]:** there is never a *double* titlebar under Hyprland (Hyprland draws none), so
`AdwHeaderBar` does not "fight" the compositor in the crude sense. What it does is (a) spend
~47 px of vertical chrome per window in an environment where the compositor already provides the
window's identity via border colour and the bar, and (b) drag in the `.csd` styling — Adwaita
paints rounded corners and reserves a shadow margin — while Omarchy runs `rounding = 0` and a
square 2 px border. The likely artefact is a square compositor border cutting across rounded app
corners, plus dead transparent margin inside the tile. **This is the single most likely "looks
foreign" defect and needs verifying on hardware first thing.**

### 1.4 Escape hatches

- `gtk_window_set_decorated(window, FALSE)` hides the title box entirely
  (`update_csd_visibility`: `visible = !fullscreen && decorated`). **[C]** gtkwindow.c
- Users can turn borders and gaps off globally with `Super + Shift + Backspace`, or permanently in
  `~/.config/hypr/looknfeel.lua`. Rounded corners are opt-in (`rounding = 8`). **[C]**
  [`manual/41-common-tweaks.md`](https://github.com/basecamp/omarchy/blob/quattro/manual/41-common-tweaks.md)

### 1.5 Window rules Omarchy actually ships

From [`default/hypr/windows.lua`](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/windows.lua)
and [`default/hypr/apps/system.lua`](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/apps/system.lua) — **[C]** all of it:

```lua
o.window(".*", { suppress_event = "maximize" })          -- client maximize requests are swallowed
o.window(".*", { tag = "+default-opacity" })
o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })   -- EVERY window is translucent
o.window("xdg-desktop-portal-gtk", { tag = "+floating-window" })    -- portal dialogs float, centred, 875x600
o.window({ class = "(sublime_text|DesktopEditors|org.gnome.Nautilus)",
           title = "^(Open.*Files?|Open [F|f]older.*|Save.*|...)" }, { tag = "+floating-window" })
o.window("^(zoom|vlc|mpv|...|org.gnome.NautilusPreviewer)$", { tag = "-default-opacity", opacity = "1 1" })
```

Three things fall out:

1. **Every window is 98.5% / 96% opaque by default.** A document *reader* almost certainly wants
   to opt out, exactly as `imv`/`mpv`/`Pinta` do. The app cannot do this itself — it is a user
   config line, so it belongs in the README:
   `o.window("<app-id>", { tag = "-default-opacity", opacity = "1 1" })`. **[I]**
2. **Rules are matched on app-id**, with reverse-DNS the house style (`org.omarchy.about`,
   `org.gnome.Nautilus`, `com.mitchellh.ghostty`). Pick a stable reverse-DNS app-id and never
   change it. **[C]** (convention) / **[I]** (that ours should match)
3. **The compositor already floats and centres portal file dialogs.** The app does not need — and
   must not attempt — any dialog placement. **[C]**

---

## 2. Theming — how Omarchy actually themes things

### 2.1 The mechanism

`omarchy-theme-set <name>` **[C]**
([`bin/omarchy-theme-set`](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-theme-set)):

1. Stages into `~/.local/state/omarchy/current/next-theme/`, copying the official theme from
   `$OMARCHY_PATH/themes/<name>/` (`/usr/share/omarchy/themes/`) then overlaying user themes from
   `~/.config/omarchy/themes/<name>/`.
   > **Path change in `quattro`:** the live theme is at **`~/.local/state/omarchy/current/theme`**,
   > not `~/.config/omarchy/current/theme` as older write-ups (and DeepWiki) say. Third-party docs
   > are stale on this. **[C]**
2. Renders templates via `omarchy-theme-set-templates` from
   [`default/themed/*.tpl`](https://github.com/basecamp/omarchy/tree/quattro/default/themed).
3. Atomically `mv`s `next-theme` → `theme`; writes the name to `current/theme.name`.
4. Runs, in parallel: `omarchy-restart-{terminal,hyprctl,btop,opencode,helix}`,
   `omarchy-theme-set-{foot,tmux,gnome,pi,claude,browser,vscode,obsidian,keyboard}`.
5. Fires **`omarchy-hook theme-set "$THEME_NAME"`**.

### 2.2 The palette is a flat TOML file — and it is genuinely good

`~/.local/state/omarchy/current/theme/colors.toml`, e.g. Tokyo Night **[C]**
([`themes/tokyo-night/colors.toml`](https://github.com/basecamp/omarchy/blob/quattro/themes/tokyo-night/colors.toml)):

```toml
mode = "dark"
accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"
background = "#1a1b26"      dark_background = "#13141c"
darker_background = "#0e0e14"  lighter_background = "#24283b"
foreground = "#a9b1d6"      dark_foreground = "#565f89"
light_foreground = "#b4bee6"   bright_foreground = "#c0caf5"
red = "#f7768e"  yellow = "#e0af68"  orange = "#eb927b"  green = "#9ece6a"
cyan = "#449dab" blue = "#7aa2f7"    magenta = "#ad8ee6" brown = "#75493d"
bright_red = "#ff7a93"  bright_yellow = "#ff9e64"  bright_green = "#b9f27c"
bright_cyan = "#0db9d7" bright_blue = "#7da6ff"    bright_magenta = "#bb9af7"
```

Every key is present in every shipped theme, and user themes without one are generated from
`alacritty.toml` (`omarchy-theme-colors-from-alacritty`). `mode` is resolved by
`omarchy-theme-color --file <colors.toml> mode`, falling back to background luminance. **[C]**

This is a complete, stable, semantically-named palette — enough to *derive* a full markdown reading
theme and a full Prism theme, which is what "follow Omarchy" has to mean. **Direct input to
ticket 07.**

Shipped themes (22): catppuccin, catppuccin-latte, ethereal, everforest, flexoki-light, gruvbox,
hackerman, kanagawa, last-horizon, lumon, matte-black, miasma, nord, osaka-jade, retro-82,
ristretto, rose-pine, solitude, tokyo-night, vantablack, white. **[C]**

### 2.3 What GTK apps get: **light/dark, and nothing else**

The entirety of Omarchy's GTK theming is
[`bin/omarchy-theme-set-gnome`](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-theme-set-gnome) — **[C]**:

```bash
mode=$(omarchy-theme-color --file "$COLORS_FILE" mode)
if [[ $mode == "light" ]]; then
  gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
  gsettings set org.gnome.desktop.interface gtk-theme    "Adwaita"
else
  gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
  gsettings set org.gnome.desktop.interface gtk-theme    "Adwaita-dark"
fi
gsettings set org.gnome.desktop.interface icon-theme "$(<icons.theme)"   # default Yaru-blue
```

**There is no `gtk.css` template and no theme file named `gtk.*` in any shipped theme.**
`default/themed/` contains templates for alacritty, btop, chromium, claude, foot, ghostty,
gum, helix, hyprland-preview-share-picker, hyprland, keyboard, kitty, neovim, obsidian, pi,
shell, vscode — **and no GTK.** **[C]** (Third-party summaries claiming a `gtk.css` are wrong;
I checked the tree.)

The manual states this plainly: themes style "the desktop, terminal, neovim, activity screen
(btop), Chromium, and the entire Omarchy shell". GTK apps are not on the list. **[C]**
[`manual/05-themes.md`](https://github.com/basecamp/omarchy/blob/quattro/manual/05-themes.md)

**And there is no accent colour either.** `AdwStyleManager:accent-color` (libadwaita ≥ 1.6) reads
`org.freedesktop.appearance/accent-color` from the Settings portal. `xdg-desktop-portal-gtk`'s
Settings backend publishes **only** `color-scheme` and `contrast` under that namespace — a search
of `settings.c` for "accent" returns nothing: **[C]**
[`src/settings.c`](https://github.com/flatpak/xdg-desktop-portal-gtk/blob/main/src/settings.c)

```c
g_variant_dict_insert_value (&dict, "color-scheme", get_color_scheme ());
g_variant_dict_insert_value (&dict, "contrast",     get_contrast_value ());
g_variant_builder_add (builder, "{s@a{sv}}", "org.freedesktop.appearance", ...);
```

Omarchy also never sets any accent GSetting. So on Omarchy `AdwStyleManager` yields exactly
**one bit** — light or dark. Tokyo Night, Gruvbox, Nord and Kanagawa are indistinguishable
through it. **[I]**

**Therefore [I]:** a stock libadwaita app on Omarchy is *Adwaita blue-grey with a Tokyo Night
wallpaper behind it*. It follows the light/dark bit and nothing else. An app that reads
`colors.toml` and tints itself will look **more** native than the average GTK app on that desktop —
including more native than Nautilus. This is the whole opportunity for ticket 07, and it means
"follow the system theme" **cannot** be implemented through `AdwStyleManager` alone.

### 2.4 Live theme switching — what the app actually receives

Two independent channels:

**(a) The Settings portal, automatic, no code.** `xdg-desktop-portal-gtk`'s Settings backend maps
GSettings `org.gnome.desktop.interface color-scheme` → `org.freedesktop.appearance/color-scheme`
and emits `SettingChanged` on every change:

```c
if (strcmp (user_data->namespace, "org.gnome.desktop.interface") == 0 &&
    strcmp (key, "color-scheme") == 0)
  ...emit_setting_changed ("org.freedesktop.appearance", key, ...);
```
**[C]** [`src/settings.c`](https://github.com/flatpak/xdg-desktop-portal-gtk/blob/main/src/settings.c)

libadwaita's `AdwStyleManager` consumes exactly this. **[C]**
([docs](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.7/class.StyleManager.html))
→ **light↔dark switches propagate live, with zero app code.** **[I]** (chain confirmed end to end)

**(b) Everything else — silent.** Tokyo Night → Nord are *both* `mode = "dark"`. No gsettings key
changes. **The app is told nothing.** **[I]**

Two mechanisms exist to catch (b), both **[C]**:

- **`omarchy-hook theme-set`** — `omarchy-theme-set` runs `omarchy-hook theme-set "$THEME_NAME"`,
  which executes `~/.config/omarchy/hooks/theme-set` and every file in
  `~/.config/omarchy/hooks/theme-set.d/`. The `theme-set.d` directory already exists in Omarchy's
  shipped config skeleton. This is the sanctioned extension point: ship a
  `theme-set.d/moremaid` one-liner that pokes the running app (D-Bus method, `SIGUSR1`, …).
  ([`bin/omarchy-hook`](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-hook))
- **Watch the file.** `~/.local/state/omarchy/current/theme` is replaced by an atomic
  `rm -rf` + `mv` of a directory; `theme.name` is rewritten. An inotify watch on the parent
  directory sees it. Note the `mv`-over-directory pattern breaks a naive watch on
  `theme/colors.toml` itself — watch `current/` and re-stat. **[I]**

Recommendation for ticket 07 **[I]**: watch the file (works with zero install steps, survives the
user never running the hook installer) *and* document the hook as the low-latency path.

### 2.5 Fonts

`omarchy-font-set` writes **`~/.config/fontconfig/fonts.conf`** with a `prepend_first` rule on the
`monospace` family, and rewrites each terminal's own config. **It never touches
`org.gnome.desktop.interface font-name`, `document-font-name`, or `monospace-font-name`.** **[C]**
([`bin/omarchy-font-set`](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-font-set))

Consequences **[I]**, all for ticket 07:

- The GTK UI font is whatever Adwaita defaults to — **Cantarell**, not JetBrains Mono. Omarchy's
  "system font" claim in [`manual/37-fonts.md`](https://github.com/basecamp/omarchy/blob/quattro/manual/37-fonts.md)
  means *monospace* everywhere, via fontconfig.
- **CSS `font-family: monospace` (unquoted generic) in the WebView resolves through fontconfig to
  the user's chosen Omarchy font, for free.** Code blocks and Mermaid monospace should use the bare
  generic and not name a family. This is a genuine "feels native" win for ~0 effort.
- Body text has no Omarchy opinion at all. `ttf-ia-writer` **is** installed (iA Writer Duo/Mono/
  Quattro), which is the closest thing Omarchy has to a reading typeface, and is a strong candidate
  substitute for the macOS New York / SF Serif typography styles.

`org.gnome.desktop.interface text-scaling-factor` **is** driven by
`omarchy display text size` (9–20 px, anchored 12 px = 1.0, quantised so the GTK font lands on a
whole point size). **[C]**
([`bin/omarchy-display-text-size`](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-display-text-size))
GTK honours it automatically; the **WebView content does not** — WebKit content size is the app's
own zoom setting. If the app does not multiply its content zoom by `text-scaling-factor`, a user
who set `omarchy display text size 16` gets a large sidebar and small document text. **[I]**
Direct input to ticket 07 and the zoom keybindings.

---

## 3. Portals

### 3.1 Which backend answers what

`xdg-desktop-portal-hyprland` declares exactly four interfaces — this is its whole
`hyprland.portal`: **[C]**
([hyprland.portal](https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/main/hyprland.portal))

```ini
[portal]
DBusName=org.freedesktop.impl.portal.desktop.hyprland
Interfaces=org.freedesktop.impl.portal.Screenshot;org.freedesktop.impl.portal.ScreenCast;org.freedesktop.impl.portal.GlobalShortcuts;org.freedesktop.impl.portal.InputCapture;
UseIn=wlroots;Hyprland;sway;Wayfire;river;
```

Omarchy ships **no `portals.conf`** override. **[C]** (searched the tree)

So with `XDG_CURRENT_DESKTOP=Hyprland` **[C]**, the routing is:

| Interface | Backend | Tag |
|---|---|---|
| Screenshot, ScreenCast, GlobalShortcuts, InputCapture | **hyprland** | **[C]** |
| **FileChooser** | **gtk** | **[C]** (xdph has no file picker; GTK is the documented fallback) |
| **Settings** (`org.freedesktop.appearance`) | **gtk** | **[C]** |
| **OpenURI**, Print, Notification, Inhibit, Access, Email | **gtk** | **[I]** (by elimination — xdph declares none of them) |
| **Secret** | *nobody* — Omarchy has a migration note that the Secret portal "has no provider" on Hyprland | **[C]** [`migrations/1784508556.sh`](https://github.com/basecamp/omarchy/blob/quattro/migrations/1784508556.sh) |

### 3.2 GTK4 uses portals automatically here — no `GTK_USE_PORTAL` needed

```c
gboolean gdk_display_should_use_portal (...)
{
  ...
  if (gdk_running_in_sandbox ()) return TRUE;
  if (!environment_has_portals ()) return FALSE;   /* == org.freedesktop.portal.Desktop is
                                                      DBus-activatable */
  ...
  return check_portal_interface (portal_interface, min_version);
}
```
**[C]** [`gdk/gdk.c`](https://github.com/GNOME/gtk/blob/main/gdk/gdk.c)

Since xdg-desktop-portal is installed and activatable on Omarchy, modern GTK4 routes through the
portal even outside a sandbox. **[I]**

Practical API guidance, all **[C]** from the GTK tree:

- **Folder / file picker:** `GtkFileDialog` (`select_folder`, `open`) → `GtkFileChooserNative` →
  `gtk_file_chooser_native_portal_show()`. You get the GTK portal chooser, and Hyprland floats
  and centres it for you.
  ([gtkfiledialog.c](https://github.com/GNOME/gtk/blob/main/gtk/gtkfiledialog.c),
  [gtkfilechoosernative.c](https://github.com/GNOME/gtk/blob/main/gtk/gtkfilechoosernative.c))
- **External links → browser:** `GtkUriLauncher` — it takes the portal path when available:
  `if (gdk_display_should_use_portal (display, PORTAL_OPENURI_INTERFACE, 3)) gtk_openuri_portal_open_uri_async (...)`,
  else `gtk_show_uri_full()`.
  ([gtkurilauncher.c](https://github.com/GNOME/gtk/blob/main/gtk/gtkurilauncher.c))
  **Use `GtkUriLauncher`; do not shell out to `xdg-open`.** **[I]**
- **Do not use the GlobalShortcuts portal.** It is the one thing xdph *does* implement, and it is
  exactly the wrong tool: it would put Moremaid's shortcuts into the compositor's global namespace
  and collide with Omarchy's already-dense Super map. In-window `GtkShortcutController` only. **[I]**

---

## 4. Wayland realities

All **[C]** unless noted.

- **A client cannot position, move, raise, or focus its own toplevel.** There is no
  `xdg_toplevel.set_position`. The compositor tiles; the app gets whatever geometry the tile has.
  ([xdg-shell](https://wayland.app/protocols/xdg-shell))
- **Self-raising goes through `xdg-activation-v1`, and Omarchy has it enabled.** Omarchy sets
  `misc.focus_on_activate = true` in
  [`default/hypr/looknfeel.lua`](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/looknfeel.lua).
  → an activation request from a *correctly-tokened* second launch really does focus the existing
  window. **This is the answer to ticket 06's "what replaces focus-the-existing-window".** **[I]**
  (config confirmed; behaviour not observed)
  - Receiving side is automatic in GTK ≥ 4.14.6 / 4.15.1; sending side needs GLib ≥ 2.75.1,
    GTK ≥ 4.10. The launcher must pass a `GdkAppLaunchContext` to `g_app_info_launch_uris()`, or
    forward `g_app_launch_context_get_startup_notify_id()` in the **`XDG_ACTIVATION_TOKEN`** env
    var. `StartupNotify=true` in the `.desktop` file is required.
    ([palant.info, 2026-02](https://palant.info/2026/02/03/supporting-waylands-xdg-activation-protocol-with-gtk/glib/))
- **`misc.initial_workspace_tracking = 0`** — new windows open on the *current* workspace, not the
  one the launching process lived on. A `moremaid` run from a terminal on workspace 3 opens where
  the user is now. Fine, but it means "open next to my terminal" is not a thing you can promise.
- **`o.window(".*", { suppress_event = "maximize" })`** — the app's own maximize requests are
  discarded. `gtk_window_maximize()` is a no-op. So is any saved-window-size restore.
- **Fractional scaling.** GTK4 speaks `wp_fractional_scale_v1` + `wp_viewporter` (since 4.11.1,
  pointer sizing fixed in 4.18); Arch ships 4.22. Omarchy binds `Super + /` and `Super + Alt + /`
  to *cycle monitor scaling* (`omarchy-hyprland-monitor-scaling up|down`), so users change scale
  interactively and expect apps to follow live.
  ([GTK 4.11.1 blog](https://blog.gtk.org/2023/04/05/gtk-4-11-1/),
  [`default/hypr/bindings/tiling.lua`](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/bindings/tiling.lua))
  Whether **WebKitGTK content** re-renders crisply on a live scale change is **unverified** and is
  the highest-risk rendering unknown. **[I]** — see known-unknowns.
  `xwayland.force_zero_scaling = true` is set, but we are Wayland-native so it is irrelevant.
- **Clipboard.** `wl-clipboard` is installed; Omarchy enables middle-click primary paste
  (`gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true`).
  ([`install/user/first-run/gtk-primary-paste.sh`](https://github.com/basecamp/omarchy/blob/quattro/install/user/first-run/gtk-primary-paste.sh))
  Text selection in the WebView should therefore populate PRIMARY as well as CLIPBOARD, since users
  will middle-click-paste out of it. **[I]**
  **Omarchy's `Super + C/V/X` synthesise `Ctrl + C/V/X` into the focused window** — see §6.1; this
  hard-reserves `Ctrl+C/V/X`.
- **Drag & drop.** Wayland DnD is `wl_data_device`; GTK4 `GtkDropTarget` on `GDK_TYPE_FILE_LIST` /
  `text/uri-list` is the normal path and Nautilus is the normal source. **[I]** Two caveats:
  (a) the drop must be handled by a **GTK** widget — a `WebKitWebView` filling the window will
  swallow drops into WebKit's own DnD handling, so an overlay/`GtkDropTarget` on a container above
  it is needed; (b) drag *out* of the app (macOS-style dragging a file to another app) is not part
  of v1 scope and should stay out.

---

## 5. Desktop integration on Arch

All **[C]** unless noted.

- **`.desktop` file:** `/usr/share/applications/<app-id>.desktop`, basename **must equal the
  Wayland `app_id`** or the compositor cannot match icon/rules to the window
  ([desktop-entry spec](https://specifications.freedesktop.org/desktop-entry-spec/latest/),
  [Colors of Noise: GTK and the application id](https://honk.sigxcpu.org/con/GTK__and_the_application_id.html)).
  Verify at runtime with `WAYLAND_DEBUG=1 moremaid |& grep set_app_id`.
  Omarchy's own convention is reverse-DNS: `org.omarchy.about`, `org.omarchy.terminal`.
  Minimum keys, modelled on Omarchy's own
  [`applications/imv.desktop`](https://github.com/basecamp/omarchy/blob/quattro/applications/imv.desktop):
  ```ini
  [Desktop Entry]
  Type=Application
  Name=Moremaid
  Exec=moremaid %U
  Icon=<app-id>
  MimeType=text/markdown;text/x-markdown;inode/directory;
  Terminal=false
  StartupNotify=true          # required for xdg-activation to work — see §4
  Categories=Office;Viewer;TextEditor;
  ```
- **MIME:** `text/markdown` is already in `shared-mime-info` upstream — no XML needs installing:
  ```xml
  <mime-type type="text/markdown">
    <sub-class-of type="text/plain"/>
    <glob pattern="*.md"/> <glob pattern="*.mkd"/> <glob pattern="*.markdown"/>
    <alias type="text/x-markdown"/>
  </mime-type>
  ```
  ([freedesktop.org.xml.in](https://gitlab.freedesktop.org/xdg/shared-mime-info/-/blob/master/data/freedesktop.org.xml.in))
  Note `.mdx`, `.mdown`, `.qmd` are **not** covered — glob them in a package-provided XML if wanted. **[I]**
  Being *listed* in `MimeType=` does not make you default; that is `xdg-mime default` / the user's
  `mimeapps.list` ([ArchWiki: XDG MIME Applications](https://wiki.archlinux.org/title/XDG_MIME_Applications)).
  **A package must not silently steal the default handler.** **[I]**
- **Competition for `.md` on Omarchy is real:** Omarchy ships **Omawrite** (its own markdown app,
  `Super + Shift + W`) and **Obsidian** (`Super + Shift + O`), and the manual says plain text opens
  in Neovim from Nautilus.
  ([`manual/21-guis.md`](https://github.com/basecamp/omarchy/blob/quattro/manual/21-guis.md))
  Moremaid is a *reader* and Omawrite is a *writer*; the honest position is "offer, don't grab". **[I]**
- **Icons:** `/usr/share/icons/hicolor/{16,24,32,48,64,128,256}x*/apps/<app-id>.png` and
  `scalable/apps/<app-id>.svg`. Symbolic variants go in `.../symbolic/apps/<app-id>-symbolic.svg`.
- **Cache refresh is free on Arch** — pacman hooks already exist and fire on any package that
  touches these trees: `update-desktop-database.hook` (desktop-file-utils),
  `gtk-update-icon-cache.hook`, `30-update-mime-database.hook` (shared-mime-info). A PKGBUILD needs
  **no** `post_install` for these. (verified against the Arch package file lists)
- **Tray / background app: don't.**
  - **GTK4 has no tray API at all** — `GtkStatusIcon` was removed in GTK4 and nothing replaced it;
    a tray icon means implementing StatusNotifierItem over D-Bus by hand. **[C]**
  - Omarchy *does* have a working tray in its quickshell bar (with a pin/hide manager,
    [`manual/41-common-tweaks.md`](https://github.com/basecamp/omarchy/blob/quattro/manual/41-common-tweaks.md)),
    but SNI-on-Wayland is widely reported flaky — icons vanish on shell reload and only a session
    restart brings them back
    ([end-4/dots-hyprland#1617](https://github.com/end-4/dots-hyprland/issues/1617),
    [Waybar#3468](https://github.com/Alexays/Waybar/issues/3468)). **[C]** (that the reports exist)
  - A tiler user closes windows with `Super + W` and relaunches from `Super + Space`. A
    resident background process with a tray icon is an alien pattern here. **[I]**
    **Recommendation: no tray, no "close to background", no autostart.**

---

## 6. The keybinding space

### 6.1 The one hard constraint: `Ctrl + C/V/X` are reserved

Omarchy binds `Super + C/V/X` to a "universal clipboard" that **synthesises `Ctrl+C/V/X` into the
focused surface** (or `Ctrl/Shift+Insert` if the window is tagged `terminal`): **[C]**
([`default/hypr/bindings/clipboard.lua`](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/bindings/clipboard.lua))

```lua
o.bind("SUPER + C", "Universal copy",  universal_clipboard_shortcut("CTRL","C","CTRL","Insert"))
o.bind("SUPER + V", "Universal paste", universal_clipboard_shortcut("CTRL","V","SHIFT","Insert"))
o.bind("SUPER + X", "Universal cut",   send_shortcut_once("CTRL","X"))
```

If Moremaid binds `Ctrl+C` to anything but copy, `Super+C` will fire that instead — a
desktop-wide behaviour breaking inside one app. **Non-negotiable for ticket 08.** **[I]**

### 6.2 What Omarchy claims — complete, from source

Read from
[`default/hypr/bindings/{tiling,utilities,clipboard,media,applications}.lua`](https://github.com/basecamp/omarchy/tree/quattro/default/hypr/bindings)
(the user-facing `~/.config/hypr/bindings.lua` is an empty override stub — the real bindings live
in `/usr/share/omarchy/default/`). Cross-checked against
[`manual/06-hotkeys.md`](https://github.com/basecamp/omarchy/blob/quattro/manual/06-hotkeys.md). **[C]**

| Modifier space | Claimed by Hyprland/Omarchy? | Detail |
|---|---|---|
| `Super + <letter>` | **fully claimed** | W close · J split · P pseudo · T float · F fullscreen · O pop · L layout · K keybindings · S scratchpad · G group · C/V/X clipboard · Home width |
| `Super + Shift + <letter>` | **fully claimed** | Return/B browser · F files · N editor · M music · D docker · G signal · O obsidian · **W omawrite** · A chatgpt · C/E hey · Y youtube · P photos · S maps · X twitter · `/` 1password |
| `Super + Ctrl + <letter>` | **fully claimed** | A audio · B bluetooth · D display · E emoji · F tiled-fs · H hardware · I idle · K herdr · L lock · N nightlight · O toggles · P power · Q calc · R reminder · S share · T activity · V clipboard mgr · W network · Z zoom |
| `Super + Alt + <letter>` | **largely claimed** | F full-width · G ungroup · K tmux keys · S scratchpad-move · `/` scaling · Home save-width · Space apps menu |
| `Super + <digit>` and every Shift/Alt/Ctrl variant | **fully claimed** | workspaces, move-to-workspace, group members, bar panels |
| `Super + Arrows / Tab / Space / Escape / Backspace / comma / - / = / / / Print / mouse` | **fully claimed** | focus, swap, groups, workspaces, menus, transparency, gaps, notifications, resize, screenshots, drag/resize |
| **`Alt + Tab`**, `Alt + Shift + Tab` | **claimed** | cycle windows on the workspace |
| `Ctrl + Alt + Delete`, `Ctrl + Alt + Tab`, `Ctrl + Alt + Shift + Tab` | **claimed** | close-all, monitor focus |
| `Print`, `Alt + Print`, `Shift + XF86*`, `Alt + XF86*` | **claimed** | capture, media, brightness |
| **`Ctrl + <letter>`** | **FREE** — zero plain-Ctrl bindings exist | except `Ctrl+C/V/X` semantics per §6.1 |
| **`Ctrl + Shift + <letter>`** | **FREE** | no Omarchy binding uses it |
| **`Ctrl + <digit>`, `Ctrl + Shift + <digit>`** | **FREE** | |
| **`Alt + <letter>`** (not Tab) | **FREE** | but conventionally menu mnemonics |
| **`Ctrl + Tab` / `Ctrl + Shift + Tab`** | **FREE** globally | *(transiently rebound only while a `slurp` screenshot-selection layer is on screen)* |
| **`F1`–`F12`** unmodified | **FREE** | |
| **bare `/`, `j`, `k`, `g`, `n`, `?`** | **FREE** | no compositor claim on unmodified letters |

**Headline for ticket 08:** the *entire* `Ctrl` and `Ctrl+Shift` space is free. A conventional
GTK/GNOME `Ctrl`-based keymap — `Ctrl+P`, `Ctrl+Shift+F`, `Ctrl+Shift+T`, `Ctrl+N`, `Ctrl+W`,
`Ctrl+±/0`, `Ctrl+?` — collides with **nothing**, and is a literal transliteration of the macOS
map. It also does not fight terminal muscle memory, because Omarchy users' terminals are launched
with `Super+Return` and their copy/paste is `Super+C/V`. **Do not reach for `Super`.** **[I]**

Two secondary constraints **[I]**:

- `Super + W` closes the window. Any in-app `Ctrl+W` ("close tab") lives next to a much more
  reflexive `Super+W` that kills the whole toplevel. If there are tabs, this is a real hazard.
- `Alt + Tab` is the compositor's. In-app tab cycling must use `Ctrl+Tab` / `Ctrl+PageUp/Down`.

### 6.3 Discoverability

- `Super + K` opens `omarchy-menu-keybindings`, which enumerates **Hyprland** bindings only —
  an app's internal shortcuts will never appear there. **[C]**
- GNOME's answer is a shortcuts window on `Ctrl+?`. `GtkShortcutsWindow` is **deprecated since
  GTK 4.18**; the replacement is **`AdwShortcutsDialog`** (+ `AdwShortcutLabel`), new in
  **libadwaita 1.8**, adaptive, with built-in search. Arch has libadwaita 1.9.3, so it is
  available. **[C]**
  ([libadwaita NEWS](https://github.com/GNOME/libadwaita/blob/main/NEWS),
  [GNOME 49 release notes](https://release.gnome.org/49/developers/))
- There is no menu bar under Hyprland and no global menu. A hamburger `GtkMenuButton` is the
  GNOME convention; whether tiling users want even that is ticket 08's call. **[I]**

---

## 7. Consequences for the chosen stack (Rust + `gtk4-rs` + `webkit6-rs`)

[Ticket 04](../issues/04-choose-language.md) fixed the language after this research began. Four
findings above land differently in Rust, and one is load-bearing.

- **`gio::ApplicationFlags::NON_UNIQUE` is mandatory, and its absence is silent.** **[C]**
  ([gio-rs `flags.rs`](https://github.com/gtk-rs/gtk-rs-core/blob/master/gio/src/auto/flags.rs))
  `GApplication` is single-instance **by default** — `gtk::Application::new(Some(id), Default::default())`
  means a second `moremaid b.md` forwards its arguments to the first process over D-Bus and exits.
  [Ticket 06](../issues/06-window-model.md) decided *multi-process, one process per invocation*;
  that decision only happens if the flag is set explicitly. Getting this wrong produces the
  single-instance behaviour the ticket rejected, with no error. **[I]**
- **Parsing `colors.toml` costs zero new dependencies.** [Ticket 09](../issues/09-config-and-state.md)
  already commits to `$XDG_CONFIG_HOME/moremaid/config.toml`, so the `toml` crate is in the tree
  regardless. §2.2's palette file is the same format. **[I]**
- **The theme file-watch costs zero new dependencies either.** The live-reload feature (the macOS
  app's 1 s content-hash poll) needs a file watcher anyway; the `notify` crate covers both the
  document and `~/.local/state/omarchy/current/`. §2.4's "watch the directory, not the file"
  caveat applies — the theme dir is replaced by `mv`, so an inode watch on `colors.toml` goes
  stale. **[I]**
- **`AdwShortcutsDialog` is reachable.** The `libadwaita` crate is at **0.9.2** with feature flags
  through `v1_10`, so `features = ["v1_8"]` gets the widget; `gtk4` has `gtk_v4_22`, matching
  Arch's 4.22.4. **[C]** ([crates.io](https://crates.io/crates/libadwaita)) Note the tension with
  §1.3: `AdwDialog` is happiest inside an `AdwApplicationWindow`, which is exactly the window class
  that forces the `.csd` class. Verify it presents standalone from a plain `GtkApplicationWindow`
  before committing to bare windows. **[I]**
- **App-id plumbing.** The Wayland `app_id` must equal the `.desktop` basename (§5). In gtk4-rs,
  set the `GtkApplication` application-id *and* `glib::set_prgname()`, then verify with
  `WAYLAND_DEBUG=1 moremaid |& grep set_app_id`. Which of the two GTK actually uses on the
  toplevel is **unverified**. **[I]**

---

## 8. macOS assumptions that do not survive contact with a tiler

Each row: what Moremaid does today (from `CLAUDE.md` / `SPEC.md`), and what actually happens.

| # | macOS Moremaid assumption | Reality on Omarchy/Hyprland | Tag | Feeds |
|---|---|---|---|---|
| 1 | **`savedWindowSessions` restores window positions on launch.** | A Wayland client cannot set its position, and cannot even reliably set its size (`suppress_event = "maximize"` swallows maximize; the tile dictates geometry). Restoring *positions* is impossible; restoring *which documents were open* is still possible but the compositor may also be restoring its own layout. | **[C]** protocol + Omarchy rule | 06 |
| 2 | **`WindowGroup(for:)` focuses the existing window when the same target reopens.** | Self-raising is forbidden. The only route is `xdg-activation-v1`, which needs a token from the *launching* process (`GdkAppLaunchContext` / `XDG_ACTIVATION_TOKEN`) and `StartupNotify=true`. Omarchy sets `focus_on_activate = true`, so it *should* work — from a launcher/`.desktop`. From a bare `moremaid README.md` typed in a terminal, the token comes from the terminal's context and is far less certain. | **[C]** config, **[I]** behaviour | 06 |
| 3 | **Native macOS window tabs (`NSWindow.tabbingMode = .preferred`).** | Nothing like it exists. Hyprland has its own window **grouping** (`Super+G`, groupbar, `Super+Alt+Tab` to cycle, `Super+Alt+1..5` to jump) which is the compositor-native equivalent — with its own tab bar, already themed by the active Omarchy theme. In-app `AdwTabView` duplicates it, and puts `Ctrl+W` next to a reflexive `Super+W`. | **[C]** grouping exists | 06, 08 |
| 4 | **⌘N opens a new window; the app decides where.** | The app can spawn a toplevel; the compositor decides everything about where it lands (dwindle split, current workspace per `initial_workspace_tracking = 0`). Spawning several at once produces a layout the user did not ask for. | **[C]** | 06 |
| 5 | **`DiagramWindowController` opens a full-screen diagram window.** | A second toplevel becomes a *tile*, splitting the reading window in half — the opposite of "full screen". `Super+F` is the user's fullscreen, not the app's. An in-app overlay is the only thing that behaves as intended. | **[I]** | 06 |
| 6 | **10 in-app colour themes chosen in Preferences.** | Omarchy has a system-wide palette (`colors.toml`) users switch with `Super+Ctrl+Shift+Space` and expect *everything* to follow. An app with its own unrelated theme list is exactly the thing that looks foreign. But: GTK apps are given only `Adwaita`/`Adwaita-dark` + `color-scheme`, so "following" means **reading `colors.toml` and deriving**, not picking from a list. | **[C]** | 07 |
| 7 | **Prism code themes and markdown CSS are independent palettes.** | Both must derive from the same `colors.toml` or the seam shows. `colors.toml` has exactly the 16 ANSI-ish colours a syntax theme needs, plus `accent`/`selection`/`muted`. | **[C]** palette shape, **[I]** that it suffices | 07 |
| 8 | **6 typography styles built on SF, New York, SF Mono.** | None of those fonts exist. Omarchy's font knob only rewrites the fontconfig **`monospace`** alias — body text has no system opinion. `ttf-ia-writer` and `noto-*` are what is actually installed. `font-family: monospace` unquoted is the free win; every named macOS family is a dead reference. | **[C]** | 07 |
| 9 | **Zoom is purely the app's business (⌘+ / ⌘− / ⌘0).** | `org.gnome.desktop.interface text-scaling-factor` is a live, user-facing Omarchy setting (`omarchy display text size`). GTK chrome follows it automatically; WebKit content does not unless the app multiplies it in. Also `Super+Ctrl+Z` is a *compositor* screen zoom and `Super+/` cycles monitor scale — three zoom concepts the user can reach. | **[C]** | 07, 08 |
| 10 | **⌘-based shortcuts; Cmd is the app's modifier.** | There is no Cmd. `Super` is the compositor's and is almost exhaustively claimed (see §6.2). `Ctrl` is completely free — but `Ctrl+C/V/X` are hard-reserved because `Super+C/V/X` synthesise them. | **[C]** | 08 |
| 11 | **A menu bar carries discoverability for free.** | No menu bar, no global menu; `Super+K` lists compositor bindings only. Discoverability must be built: `AdwShortcutsDialog` on `Ctrl+?`, and the README. | **[C]** | 08 |
| 12 | **Cmd+click opens a link in a new tab/window.** | Nothing is bound to `Ctrl+click` by the compositor, so `Ctrl+click` is available — but what it *opens into* depends entirely on the ticket-06 window/tab decision. | **[I]** | 06, 08 |
| 13 | **A macOS titlebar/toolbar identifies the window.** | Under Hyprland the identity is the 2 px gradient border and the bar. An `AdwHeaderBar` is ~47 px of chrome the environment already provides, and drags in `.csd` rounded-corner/shadow styling that clashes with `rounding = 0`. | **[C]** mechanism, **[I]** appearance | 06, 07 |
| 14 | **QuickLook extension previews files in Finder.** | Already ruled out of scope — worth noting Omarchy *does* ship **`sushi`**, so Nautilus `Space` preview exists and is somebody else's. | **[C]** | — |
| 15 | **Opaque windows.** | Every Omarchy window is `opacity 0.985 0.96` by default. A reader should ship a documented opt-out rule (`tag = "-default-opacity"`), like `imv`/`mpv` do. The app cannot set this itself. | **[C]** | 07, docs |
| 16 | **Sparkle in-app updates.** | Already out of scope; `pacman`/AUR owns it. `omarchy update` is the user's habit. | **[C]** | packaging |
| 17 | **Drag & drop onto the window, and dragging out.** | Drop-in works (`GtkDropTarget` / `text/uri-list`, Nautilus is the source) **but** a full-bleed `WebKitWebView` will swallow the drop into WebKit's own DnD. Drag-*out* should stay unscoped. | **[I]** | 06 |
| 18 | **Recents, background residency, dock presence.** | No dock, no tray API in GTK4, flaky SNI on Wayland. Recents live in the app's own UI (and optionally `GtkRecentManager`), and the app should exit when its last window closes. | **[C]** GTK4 tray removal | 06 |

---

## 9. Known unknowns

Nothing below was observed on hardware. These are ordered by how badly a wrong guess hurts.

1. **Does `AdwApplicationWindow`'s `.csd` styling actually produce visible rounded corners /
   shadow margin under Hyprland's square 2 px border?** The code path is confirmed
   (`gtk_window_set_titlebar` → `gtk_window_enable_csd` → `.csd` class, independent of
   `prefers_ssd`), the pixels are not. If it does, decide between `AdwApplicationWindow` +
   a CSS override and a plain `GtkApplicationWindow`. *First thing to check on a real box.*
2. **WebKitGTK 6.0 under live fractional-scale changes** (`Super + /`). Does content re-render
   crisply or go blurry until reload? GTK4's own fractional-scale support is solid; WebKit's
   compositing layer under it is untested here.
3. **Does `xdg-activation` actually focus the existing window when `moremaid FILE.md` is typed in
   a terminal?** `focus_on_activate = true` is confirmed set; whether a terminal-launched process
   ends up with a usable token is not. If it doesn't, ticket 06's single-instance story needs a
   fallback (e.g. always open a new toplevel).
4. **Whether Omarchy's `theme-set` hook is reliably present.** `~/.config/omarchy/hooks/theme-set.d/`
   ships in the config skeleton, but a user who has customised or reset configs may not have it.
   The inotify fallback is why it should not be the only mechanism.
5. **`colors.toml` schema stability.** Every shipped theme has the same keys today, and
   user themes are backfilled from `alacritty.toml`. But this is an internal file with no
   compatibility promise, and `quattro` already moved its *path* (`~/.config` →
   `~/.local/state`). Parse defensively; fall back to Adwaita colours on any missing key.
6. **How a WebKitGTK-rendered page looks against 96% window opacity.** Text over a translucent
   background may be unpleasant. Untested.
7. **Whether `text/markdown` is enough**, or Omarchy/Nautilus classify `.md` as `text/plain` in
   practice via content sniffing.
8. **Whether `Ctrl+Tab` is truly free.** It is not in Omarchy's static config, but
   `utilities.lua` *dynamically* binds `TAB` and `CTRL+TAB` while a `slurp` selection layer is on
   screen. That should be transient and only during screenshot selection — verify it does not leak.
9. **libadwaita 1.10 / GTK 4.23** are in `gnome-unstable`. Arch moves fast; anything built against
   1.9/4.22 should be checked against the next cycle before release.
10. **Whether `AdwDialog`-derived widgets (`AdwShortcutsDialog`) present correctly from a plain
    `GtkApplicationWindow`.** If they demand an `AdwApplicationWindow` host, §1.3's `.csd` problem
    and §6.3's discoverability answer collide, and one of them has to give.
11. **Which identifier GTK4 puts in `xdg_toplevel.set_app_id`** — the `GApplication` application-id
    or `g_get_prgname()`. Everything in §5 (icon, `.desktop` match, Hyprland window rules) hangs
    off it being the reverse-DNS app-id.
12. **Whether Omarchy users want the app in the `Super+Shift` app-launch space at all** (i.e.
    whether the README should suggest `o.bind("SUPER + SHIFT + R", "Moremaid", ...)`). Most of that
    space is already taken; `R` and `T`/`U`/`V`/`Z` appear free, but this is a user decision, not
    ours.

---

## Sources

Omarchy (`basecamp/omarchy`, branch `quattro`) —
[bindings](https://github.com/basecamp/omarchy/tree/quattro/default/hypr/bindings) ·
[looknfeel.lua](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/looknfeel.lua) ·
[windows.lua](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/windows.lua) ·
[apps/system.lua](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/apps/system.lua) ·
[envs.lua](https://github.com/basecamp/omarchy/blob/quattro/default/hypr/envs.lua) ·
[omarchy-theme-set](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-theme-set) ·
[omarchy-theme-set-gnome](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-theme-set-gnome) ·
[omarchy-font-set](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-font-set) ·
[omarchy-display-text-size](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-display-text-size) ·
[omarchy-hook](https://github.com/basecamp/omarchy/blob/quattro/bin/omarchy-hook) ·
[themes/tokyo-night/colors.toml](https://github.com/basecamp/omarchy/blob/quattro/themes/tokyo-night/colors.toml) ·
[default/themed/](https://github.com/basecamp/omarchy/tree/quattro/default/themed) ·
[install/omarchy-base.packages](https://github.com/basecamp/omarchy/blob/quattro/install/omarchy-base.packages) ·
manual [05-themes](https://github.com/basecamp/omarchy/blob/quattro/manual/05-themes.md),
[06-hotkeys](https://github.com/basecamp/omarchy/blob/quattro/manual/06-hotkeys.md),
[21-guis](https://github.com/basecamp/omarchy/blob/quattro/manual/21-guis.md),
[37-fonts](https://github.com/basecamp/omarchy/blob/quattro/manual/37-fonts.md),
[41-common-tweaks](https://github.com/basecamp/omarchy/blob/quattro/manual/41-common-tweaks.md) ·
[The Omarchy Manual](https://learn.omacom.io/2/the-omarchy-manual)

Hyprland —
[XDGDecoration.cpp](https://github.com/hyprwm/Hyprland/blob/main/src/protocols/XDGDecoration.cpp) ·
[ServerDecorationKDE.cpp](https://github.com/hyprwm/Hyprland/blob/main/src/protocols/ServerDecorationKDE.cpp) ·
[wiki.hypr.land](https://wiki.hypr.land/)

Portals —
[hyprland.portal](https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/main/hyprland.portal) ·
[xdg-desktop-portal-hyprland README](https://github.com/hyprwm/xdg-desktop-portal-hyprland) ·
[xdg-desktop-portal-gtk src/settings.c](https://github.com/flatpak/xdg-desktop-portal-gtk/blob/main/src/settings.c) ·
[ArchWiki: XDG Desktop Portal](https://wiki.archlinux.org/title/XDG_Desktop_Portal)

GTK / libadwaita —
[gtkwindow.c](https://github.com/GNOME/gtk/blob/main/gtk/gtkwindow.c) ·
[gdkdisplay-wayland.c](https://github.com/GNOME/gtk/blob/main/gdk/wayland/gdkdisplay-wayland.c) ·
[gdk/gdk.c](https://github.com/GNOME/gtk/blob/main/gdk/gdk.c) ·
[gtkurilauncher.c](https://github.com/GNOME/gtk/blob/main/gtk/gtkurilauncher.c) ·
[gtkfilechoosernative.c](https://github.com/GNOME/gtk/blob/main/gtk/gtkfilechoosernative.c) ·
[adw-window.c](https://github.com/GNOME/libadwaita/blob/main/src/adw-window.c) ·
[libadwaita NEWS](https://github.com/GNOME/libadwaita/blob/main/NEWS) ·
[AdwStyleManager](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.7/class.StyleManager.html) ·
[GNOME 49 developer notes](https://release.gnome.org/49/developers/) ·
[GTK 4.11.1 blog](https://blog.gtk.org/2023/04/05/gtk-4-11-1/)

Freedesktop / Arch —
[shared-mime-info freedesktop.org.xml.in](https://gitlab.freedesktop.org/xdg/shared-mime-info/-/blob/master/data/freedesktop.org.xml.in) ·
[Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/) ·
[ArchWiki: XDG MIME Applications](https://wiki.archlinux.org/title/XDG_MIME_Applications) ·
[xdg-activation-v1](https://wayland.app/protocols/xdg-activation-v1) ·
[xdg-shell](https://wayland.app/protocols/xdg-shell)

Other —
[Supporting Wayland's XDG activation protocol with Gtk/Glib (palant.info, 2026-02-03)](https://palant.info/2026/02/03/supporting-waylands-xdg-activation-protocol-with-gtk/glib/) ·
[GTK+ and the application id (Colors of Noise)](https://honk.sigxcpu.org/con/GTK__and_the_application_id.html) ·
[end-4/dots-hyprland#1617 (tray icons disappear)](https://github.com/end-4/dots-hyprland/issues/1617) ·
[Alexays/Waybar#3468 (tray module)](https://github.com/Alexays/Waybar/issues/3468)
