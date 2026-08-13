# Decide theming: ship the 10 themes, or follow Omarchy?

Type: grilling
Status: resolved
Blocked by: 02, 05

## Question

Moremaid ships **10 color themes** (Light, Dark, GitHub, GitHub Dark, Dracula, Nord, Solarized
Light/Dark, Monokai, One Dark) and **6 typography styles** as its own CSS, selectable in
Preferences. Omarchy has a **system-wide theme** that users expect every app to follow — an app
that ignores it is the single most obvious way to look foreign on that desktop.

Decide:

- **Follow the system theme, keep the app's own list, or both?** The obvious shape is
  "follow Omarchy by default, manual override available" — but that needs the mapping question
  answered: Omarchy themes are not the same set as these 10, so does following mean *deriving*
  content colors from the GTK/system palette rather than picking from a list?
- **Chrome ↔ content consistency.** The GTK shell and the WebKitGTK content are styled by two
  completely different systems. How do they stay visually one app, especially at the seam?
- **Live theme switching.** The user changes the Omarchy theme while the app is open. What happens?
- **Typography on Linux.** The 6 typography styles assume macOS system fonts (SF, New York, etc.).
  Decide the substitute stack, and whether any style is dropped rather than badly approximated.
- **Code highlighting.** Prism themes are a third palette — do they follow too?

## Answer

**Follow Omarchy. Ship zero themes. Delete the picker.**

This is the largest deletion in the port and the most consequential single decision for "feels
native". Omarchy rethemes an entire desktop at once — terminal, editor, bar, browser. An app that
ignores that and offers its own competing list of ten palettes is instantly, obviously foreign, no
matter how good those palettes are on their own.

- **Derive the content palette from the active system theme**, don't pick from a list. Read the
  light/dark state and accent from libadwaita's `StyleManager` plus GTK settings, and inject the
  result into the page as CSS custom properties on `:root`. The GTK chrome and the WebKitGTK
  content then share a palette because they share a *source*, not because someone matched them by
  eye once and let them rot.

- **Live switching is mandatory, not a nicety.** The user rethemes their whole desktop with one
  command and every open Moremaid window must follow within the same second: handle the
  style-manager change signal, re-inject the custom properties via `evaluate_javascript`, and
  re-initialise Mermaid with the new config so existing diagrams recolour rather than sitting there
  in the old palette.

- **One typography, not six.** The macOS styles assume SF and New York, which aren't there. Ship
  one good default — the system UI font for chrome, a solid body face for prose, the user's
  configured monospace for code — and delete the picker. `TypographyCSS` does not cross over.

- **Prism follows too.** Generate the code-highlighting palette from the same source, or ship
  light/dark variants keyed to the system colour-scheme. A third independent palette is how an app
  ends up looking like a ransom note.

**The trade, stated plainly:** the ten themes and six typographies are the app's two most-marketed
features on macOS, and this deletes both. On GNOME or KDE that would be a loss. On a desktop built
around system-wide theming it is the entire point — and it also deletes the preferences window,
since after this there is nothing left to put in one.

Rests on [Hyprland conventions](02-hyprland-conventions.md) for the mechanism: exactly what Omarchy
sets when it switches theme, and what an app must read and watch to follow it. That research
**confirms the mechanism**; the decision to follow rather than ship a list stands regardless.
