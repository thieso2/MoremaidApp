# Decide config and state persistence

Type: grilling
Status: resolved
Blocked by: 04

## Question

macOS persists everything in UserDefaults: `savedWindowSessions`, `recentTargets` (last 10),
`defaultTheme` / `defaultTypography` / `defaultZoom`, `showBreadcrumb` / `showStatusBar` /
`restoreWindows`, and per-directory Navigator folder-expansion state.

Decide the Linux equivalent:

- **GSettings schema, a plain XDG config file, or both?** GSettings is the GNOME-idiomatic answer
  and brings schema compilation into the packaging step; a TOML/JSON/INI file under
  `$XDG_CONFIG_HOME/moremaid/` is hand-editable — which the Omarchy audience will want, since
  that's how the rest of their system is configured.
- **Which state goes where.** Preferences vs ephemeral UI state vs recents vs sessions. Cache-like
  state (folder expansion) may belong under `$XDG_CACHE_HOME` or `$XDG_STATE_HOME` rather than
  config.
- **Exact paths**, respecting XDG base directory spec including the fallbacks.
- **What is dropped** given the window-model decision — if session restore is gone, so is
  `savedWindowSessions`.
- **Whether the config is documented as a user-facing interface** (Omarchy users will dotfile it)
  and therefore whether it needs stability guarantees and a documented default file.

## Answer

**One hand-editable file. No GSettings.**

- **`$XDG_CONFIG_HOME/moremaid/config.toml`**, honouring the XDG fallback to `~/.config`. Parsed
  with `serde` + `toml`. GSettings would mean a schema, schema compilation in the package, and a
  configuration the user cannot read with `cat` or keep in a dotfiles repo — three kinds of
  ceremony for zero benefit to this audience.

- **The config file is a user-facing interface**, and after the language decision it is the *main*
  one: choosing Rust removed the option of editing the app itself, so this file and the web assets
  under `/usr/share/moremaid/web/` are the entire surface a user can shape without a toolchain.
  Ship a fully commented default, document every key in the README, and treat key names as stable.
  People will symlink this on day one.

- **Keep it tiny.** After the theming decision there is very little left to configure: font family
  and size overrides, the monospace face, and a theme override for the person who genuinely wants
  to fight their system theme. `showBreadcrumb` and `showStatusBar` are **deleted rather than made
  configurable** — pick the right default and stand behind it. A config file that mirrors a
  preferences window nobody wanted is the same mistake in plain text.

- **State is not config.** Recents go to `$XDG_STATE_HOME/moremaid/recents`.
  `savedWindowSessions` is deleted outright, following from the window model. Per-directory
  Navigator folder-expansion becomes **ephemeral** — in-session only, persisted nowhere. It is not
  worth a file, and getting it wrong across sessions is more annoying than not having it.
