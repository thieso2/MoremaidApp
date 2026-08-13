# Decide how the Linux app obtains the rendering layer

Type: grilling
Status: resolved
Blocked by: 03

## Question

The macOS rendering layer is a set of Swift string constants — `BaseCSS.swift`, `ThemeCSS.swift`
(10 themes), `TypographyCSS.swift` (6 styles), `PageScripts.swift`, `MermaidConfig.swift`,
`LanguageMaps.swift` — assembled by `HTMLGenerator.swift` into one inline HTML document, with
markdown-it, Prism.js and Mermaid.js pulled from a CDN.

That is ~3k lines of CSS/JS wearing a Swift costume, and it is the single largest reusable asset
in the project. Decide:

- **(a) Reimplement or reuse?** Does the Linux app regenerate this HTML in its own language, or
  consume the CSS/JS extracted verbatim into plain `.css`/`.js` files with a thin templating step?
- **(b) How do the web dependencies ship?** A CDN is unacceptable for a local markdown viewer that
  must work offline — vendor the three libraries into the repo, use Arch packages, or something
  else. Pin versions.
- **(c) One-time copy or ongoing link?** Does the new repo take a snapshot, or is there a
  mechanism (submodule, extraction script, manual sync) keeping it in step with this repo?
- **(d) Who owns divergence?** When the macOS side adds a theme or fixes a rendering bug, what is
  supposed to happen on Linux? "Nothing, they drift" is a legitimate answer if stated on purpose.

Note the constraint the destination imposes: HANDOFF.md must be usable by a session with no access
to this repo, so if the answer is "copy the assets", the handoff has to carry them or say precisely
where to get them.

## Answer

**Reuse it verbatim, vendored, with no build step anywhere in the pipeline.**

- **(a) Reuse, don't reimplement.** The CSS and JS inside `BaseCSS.swift`, `ThemeCSS.swift`,
  `TypographyCSS.swift`, `PageScripts.swift`, `MermaidConfig.swift` and `LanguageMaps.swift` is
  ~3k lines of working, debugged web code wearing a Swift costume. It is extracted to plain
  `.css` / `.js` / `.html` files and crosses over untouched. The Rust side's entire rendering
  layer is then: read the template, substitute a handful of values, hand the string to
  `webkit_web_view_load_html`. A few dozen lines, not a port. No template-engine crate — plain
  string substitution is enough and adds nothing to audit.

- **(b) Web dependencies are vendored, pinned, and committed.** markdown-it, Prism.js and
  Mermaid.js go into the repo as plain `.js` files served over a custom URI scheme. **No CDN** — a
  local markdown viewer that needs the network to render a heading is broken, and this app's whole
  premise is reading files on your own disk. No npm, no bundler, no `package.json`; the files are
  distributable as shipped and there is nothing to build. HANDOFF.md pins exact versions.

- **Assets ship as data files, not `include_str!`.** They install to `/usr/share/moremaid/web/`,
  with `$XDG_DATA_HOME/moremaid/web/` taking precedence if present. This is the deliberate
  counterweight to choosing a compiled language: the user can still change how their markdown
  renders — restyle it, swap the Mermaid config, add a Prism language — without a toolchain. It
  costs nothing and it is the difference between a Rust binary and a Rust black box.

- **(c) One-time copy.** No submodule, no sync script, no extraction tooling. The new repo takes a
  snapshot and owns it.

- **(d) Divergence is owned by nobody, deliberately.** The two apps drift. This follows from the
  separate-repo shape fixed at charting; building sync machinery for a two-codebase, one-person
  problem is cost without a payer. If the macOS side fixes a rendering bug worth having, someone
  copies the file across by hand, and that is the whole process.

**Binding constraint on the destination:** HANDOFF.md's reader has no access to this repo, so the
document must name the public GitHub repo, a **pinned commit SHA**, and the exact file paths to lift
— or carry the assets inline. Pointing at `main` is not good enough; it will have moved by the time
anyone reads it.
