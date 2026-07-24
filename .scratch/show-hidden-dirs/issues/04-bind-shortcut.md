# Bind ⇧⌘. to toggle Show Hidden Files

Type: task
Status: retired
Blocked by: 02

> **Retired — superseded by `tickets.md` (repo root).** The implementation was re-sliced into
> vertical tracer-bullet tickets via `/to-tickets`. This shortcut work is now the second ticket,
> "Toggle hidden files with ⇧⌘. and a View-menu item". Do not work this ticket; work `tickets.md`.

## Question

Wire **⇧⌘.** to flip the `showHiddenFiles` preference, and add a checkbox menu item (label e.g.
"Show Hidden Files") in the View menu alongside the Navigator toggle (⇧⌘T), following the
Commands DSL pattern in `Sources/App/`.

Resolve as part of this ticket:
- Confirm ⇧⌘. doesn't collide with an existing Moremaid command or a standard macOS binding in
  this app's context.
- Where the command lives in the Commands DSL and how it reads/writes the preference from #02.
- Menu item wording + checkmark state binding.

Toggling here only flips the stored preference; making open windows react to the flip is the
sibling-filters-and-refresh ticket.
