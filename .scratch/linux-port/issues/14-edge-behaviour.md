# Decide error and edge-case behaviour

Type: grilling
Status: resolved
Blocked by: —

> Graduated from the map's fog 2026-08-13, once [the port map](11-module-port-map.md) made the
> failure surfaces visible.

## Question

The macOS app's behaviour in these cases is undocumented and mostly incidental. The Linux spec
should state it on purpose, because a viewer's whole job is opening files it did not choose.

- **A file that isn't markdown.** `moremaid photo.png`, `moremaid a.rs`, a binary blob mistaken for
  text. Refuse, render as plain text, syntax-highlight it? The macOS app renders code files —
  decide whether that survives and for which extensions.
- **Very large files.** A 50MB markdown file, or one with a thousand Mermaid diagrams. Is there a
  ceiling, a progressive render, or a warning? Mermaid rendering is the likely wall.
- **Paths that misbehave.** Broken symlinks, symlink loops, permission-denied directories mid-scan,
  paths that don't exist, a directory passed where a file was expected.
- **Files that change underneath.** Deleted while open, replaced by a directory, truncated
  mid-read, and the editor atomic-save pattern (write temp, rename) that naive watchers miss —
  this one is not an edge case, it is what every save from neovim looks like.
- **Nothing to show.** An empty directory, a directory with no markdown in it, an empty file.
- **Malformed Mermaid.** The macOS app has a `MermaidValidator`; decide whether errors render
  inline in the document, silently fall back to a code block, or surface some other way.
- **stdin.** `cat x.md | moremaid` — what is the document's base path for resolving relative links
  and images, given there isn't one?

Each answer is one line in HANDOFF.md. The point is that the Linux session makes these choices
deliberately rather than discovering them as bugs.

## Answer

The macOS app has **no size guard anywhere** and **no binary detection** — a 50 MB file or a PNG
goes straight to the webview and whatever happens, happens. The Linux spec closes both, and states
the rest on purpose rather than by accident.

One shared affordance, defined once and reused: **the banner** — a dismissible strip at the top of
the content area, used by the large-file and missing-file cases below. It never blocks the content.

### File types

| input | behaviour |
|---|---|
| `.md`, `.markdown` | markdown |
| any other **text** file | syntax-highlighted code document via Prism; language from the extension, plain text when unknown |
| **binary** | refuse, with a friendly message naming the file and its size — never paint NUL bytes into the webview |

Binary detection is a NUL byte in the first 8 KB, the same heuristic `grep-searcher` uses (and it
can be borrowed from there rather than hand-rolled — the crate is already a dependency).

This keeps macOS's behaviour, which is genuinely useful: every repo has code sitting next to the
docs, and being able to open both is why the app is a viewer rather than a markdown-only tool.

### Large documents — a soft ceiling, never a hang

Above **5 MB** *or* **50 Mermaid diagrams**, render plain: no Mermaid, no Prism, with a banner
saying so and a way to insist (`Ctrl+Shift+R` — free in [the keyboard map](08-keyboard-map.md); this
adds a binding to it).

**The diagram count is the real trigger, not the byte size.** Mermaid's cost scales ~3–5× per
+20 nodes ([the audit](03-webkitgtk-audit.md) confirms this as an engine-independent property), so a
200 KB file with 200 diagrams is far more dangerous than a 20 MB file with none.

Forcing a full render populates the diagram cache normally, so the cost is paid once rather than on
every live-reload tick.

Refusing outright was **rejected** — a viewer that won't show you your file is a poor viewer. No
ceiling at all was **rejected** because its failure mode is the worst one available: a window that
opens, shows nothing, explains nothing, and reads as a crash.

### Malformed Mermaid

The diagram is **replaced in place by a styled error block** carrying `MermaidValidator`'s message
and line number, with the offending source shown beneath it.

The reasoning is about who is reading: you are usually the author of the file in front of you, and a
silent fallback to a code block tells you a diagram didn't draw while withholding the one piece of
information — *why* — that the app already computed. `MermaidValidator` produces line-numbered
errors today and they are currently thrown away at the UI.

### The file changes underneath you

- **Deleted, or replaced by a directory:** keep the last good render on screen and show the banner.
  If the path comes back, reload and clear it. **The common cause is a branch switch, not a
  deletion**, so destroying what the user was reading would be wrong far more often than it was
  right.
- **Truncated or mid-write:** absorbed by the debounced parent-directory watch from
  [the crate set](01-binding-survey.md) — a short read simply retries on the next debounce window.
- **Atomic save (write temp + rename):** the normal case on this desktop, handled by watching the
  containing directory rather than the file's inode.

### The remaining cases, decided rather than discovered

**Terminal invocation is the primary entry point, so these behave like a Unix tool:**

- **Path doesn't exist** → message on stderr, **exit 1, no window**. Opening an empty window to
  report a typo is wrong when the user is sitting in a shell.
- **Permission denied on the target** → same: stderr, exit 1.
- **Permission denied mid-scan** → skip the unreadable subtree and carry on. A docs tree with one
  root-owned directory in it should still browse.
- **Directory passed where a file is expected, or vice versa** → both are valid targets; open
  whichever it actually is. There is nothing to complain about.
- **Broken symlink** → treated as a missing path (stderr, exit 1). **Symlink loops** cannot arise:
  `ignore` does not follow symlinks by default and that default stands.

**Empty states get a message, never a blank window:**

- **Empty directory, or one with no readable files** → an empty-state message in the content area.
- **Empty file** → renders as an empty document. This is not an error; empty files are ordinary.

**stdin** (`cat notes.md | moremaid`):

- **The base path is the current working directory**, which is the only sane answer — relative links
  and images resolve from where the user ran the command, which is what they meant.
- Titled `(stdin)`.
- **No live reload**, because there is nothing to watch. Say so in the docs rather than leaving the
  user to wonder why this one document doesn't update.

### What this adds elsewhere

- `Ctrl+Shift+R` (force full render) joins [the keyboard map](08-keyboard-map.md).
- The banner is a UI component HANDOFF.md must describe, used by two cases here.
- Binary detection reuses `grep-searcher`; **no new dependency**.
