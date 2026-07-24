# Add the app-wide Show Hidden Files preference

Type: task
Status: resolved
Blocked by: —

## Question

Add a single app-wide `showHiddenFiles` (final name TBD in this ticket) preference, following the
exact pattern of the existing UI toggles (`showBreadcrumb`, `showStatusBar`, `restoreWindows` in
`Sources/App/`): a UserDefaults key, a default value (**default: off**), and read/write access
from wherever preferences are surfaced. Include it in the Preferences UI if the sibling toggles
appear there.

Resolve: the property name, the UserDefaults key string, the default value, and where the state is
owned (which `@AppStorage` / preferences object). This is the foundation the shortcut, scanner,
and sibling-filter tickets all read from — no re-scan wiring here (that lives in the sibling ticket).

## Answer

Added the preference following the existing decentralized `@AppStorage` boolean pattern (the same
one `showBreadcrumb` / `showStatusBar` / `autoReload` use — no `Constants` entry needed).

- **Property / key string:** `showHiddenFiles` — one string, read via `@AppStorage("showHiddenFiles")`
  wherever needed (like `showBreadcrumb`). Downstream tickets read the same key.
- **Default:** `false` (off), as specified.
- **State ownership:** decentralized `@AppStorage`, not a central object — matches the codebase.
  The UI toggle lives in `PreferencesView.swift`; the scanner/watcher/auto-index tickets will each
  declare their own `@AppStorage("showHiddenFiles")` (or read `UserDefaults.standard.bool(forKey:)`).
- **Preferences UI:** added `Toggle("Show hidden files", isOn: $showHiddenFiles)` to the **General**
  tab, right after "Auto-reload on file change" (`PreferencesView.swift`).

**Deliberately NOT wired:** no `onChange`/`.settingsChanged` emission on the toggle. Whether the
propagation mechanism is `.settingsChanged` or direct `@AppStorage` observation is an open decision
owned by the sibling-filters-and-refresh ticket — wiring it here would pre-decide that. Flipping the
toggle currently persists the value (and updates any live `@AppStorage` reader) but does not yet
re-scan open windows; that is expected until the sibling ticket lands.

Build: `mise build` → **Build Succeeded**.

**Fact for downstream tickets:** the key is exactly `"showHiddenFiles"`, default `false`. There is a
ready-made app-wide change signal — `Notification.Name.settingsChanged`, posted by
`PreferencesView.notifySettingsChanged()` — that the sibling ticket may reuse for re-scan propagation.
