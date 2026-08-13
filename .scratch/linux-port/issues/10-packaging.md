# Decide packaging, distribution and desktop integration

Type: grilling
Status: resolved
Blocked by: 02, 04

## Question

How does a user get this onto an Omarchy machine and run it?

Decide:

- **Packaging route** — a `PKGBUILD` published to the AUR, a personal repo, or source build only.
  Include what the `PKGBUILD` depends on and what it builds with, given the language choice.
- **Desktop integration** — `.desktop` entry, icon (and where in the icon theme), MIME association
  for `text/markdown` so a file manager opens it, and whether it registers as a handler for
  anything else.
- **Terminal invocation** — `moremaid README.md`, `moremaid .`, reading from stdin (`… | moremaid`)?
  Tiling users live in terminals, so this is a primary entry point, not an afterthought. Note that
  the full `mm` CLI is out of scope; this is just argument handling on the app binary.
- **Versioning and release flow** — how a release is cut and how the package updates, given
  in-app auto-update (Sparkle's role on macOS) is explicitly out of scope.
- **Build-from-source instructions** — exact `pacman` dependency list, since HANDOFF.md's reader
  needs it on day one before anything else works.

## Answer

**AUR, and let pacman be the updater.**

- **`PKGBUILD` in the AUR**, in the two conventional flavours: `moremaid` from tagged releases and
  `moremaid-git` from `HEAD`. This is how software arrives on an Arch box; anything else is
  swimming upstream for no one's benefit.
  - `depends`: `gtk4`, `libadwaita`, `webkitgtk-6.0`
  - `makedepends`: `rust` (or `rustup`)
  - build: `cargo build --release`
  - install: the binary to `/usr/bin/moremaid`, the web assets to `/usr/share/moremaid/web/`, the
    `.desktop` file, and the icon into the hicolor theme

- **Terminal invocation is the primary entry point and gets designed first.** `moremaid README.md`,
  `moremaid .` for a directory, bare `moremaid` for the current directory, and
  `cat notes.md | moremaid` for stdin. This audience opens files from a shell far more often than
  from a file manager, so this path is tested most and documented first. (The full `mm` CLI stays
  out of scope — this is argument handling on the app binary, nothing more.)

- **Desktop integration is secondary but present:** `.desktop` entry, an icon in hicolor, and a
  `text/markdown` MIME association so a file manager can hand files over.

- **Versioning:** git tags; the AUR package is bumped on release. **Updates are pacman's job** — no
  in-app update check, no version ping, no notification. Sparkle's role on macOS has no counterpart
  here and inventing one would be actively unwelcome on this distribution.

- **HANDOFF.md must carry the exact `pacman` dependency list verbatim**, because that is literally
  the reader's first command and nothing else works until it is right.
