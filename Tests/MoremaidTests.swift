import Foundation
import Testing
@testable import Moremaid

@Test func formatSizeTest() {
    #expect(formatSize(0) == "0 B")
    #expect(formatSize(512) == "512 B")
    #expect(formatSize(1024) == "1.0 KB")
    #expect(formatSize(1536) == "1.5 KB")
    #expect(formatSize(1048576) == "1.0 MB")
}

@Test func formatTimeAgoTest() {
    #expect(formatTimeAgo(Date()) == "just now")
    #expect(formatTimeAgo(Date(timeIntervalSinceNow: -120)) == "2 mins ago")
    #expect(formatTimeAgo(Date(timeIntervalSinceNow: -7200)) == "2 hours ago")
}

@Test func htmlEscapingTest() {
    #expect("<script>".htmlEscaped == "&lt;script&gt;")
    #expect("\"hello\"".htmlEscaped == "&quot;hello&quot;")
}

@Test func isMarkdownFileTest() {
    #expect(isMarkdownFile("README.md") == true)
    #expect(isMarkdownFile("notes.markdown") == true)
    #expect(isMarkdownFile("code.swift") == false)
    #expect(isMarkdownFile("GUIDE.MD") == true)
}

@Test func isHTMLFileTest() {
    #expect(isHTMLFile("index.html") == true)
    #expect(isHTMLFile("legacy.htm") == true)
    #expect(isHTMLFile("INDEX.HTML") == true)
    #expect(isHTMLFile("README.md") == false)
}

@Test func defaultFilterIncludesMarkdownAndHTMLTest() {
    let html = FileEntry(
        id: "index.html",
        name: "index.html",
        relativePath: "index.html",
        absolutePath: "/tmp/index.html",
        size: 0,
        modifiedDate: Date(),
        isMarkdown: false
    )
    let markdown = FileEntry(
        id: "README.md",
        name: "README.md",
        relativePath: "README.md",
        absolutePath: "/tmp/README.md",
        size: 0,
        modifiedDate: Date(),
        isMarkdown: true
    )
    let swift = FileEntry(
        id: "main.swift",
        name: "main.swift",
        relativePath: "main.swift",
        absolutePath: "/tmp/main.swift",
        size: 0,
        modifiedDate: Date(),
        isMarkdown: false
    )

    #expect(FileFilter.defaultFiles.matches(html) == true)
    #expect(FileFilter.defaultFiles.matches(markdown) == true)
    #expect(FileFilter.defaultFiles.matches(swift) == false)
    #expect(FileFilter.markdownOnly.matches(html) == false)
    #expect(FileFilter.markdownOnly.matches(markdown) == true)
}

@Test func htmlPageReturnsRawContentTest() {
    let source = "<h1>Hello</h1>"
    #expect(HTMLGenerator.htmlPage(content: source) == source)
}

@Test func sameDocumentAnchorNavigationMatchesDocumentDirectoryTest() {
    #expect(isSameDocumentAnchorNavigation(
        linkPath: "/tmp/docs/api/",
        currentFilePath: "/tmp/docs/api/index.html",
        currentDocumentDirectory: "/tmp/docs/api"
    ))
}

@Test func sameDocumentAnchorNavigationMatchesCurrentFileTest() {
    #expect(isSameDocumentAnchorNavigation(
        linkPath: "/tmp/docs/api/index.html",
        currentFilePath: "/tmp/docs/api/index.html",
        currentDocumentDirectory: "/tmp/docs/api"
    ))
}

@Test func sameDocumentAnchorNavigationDoesNotMatchProjectRootForNestedDocumentTest() {
    #expect(!isSameDocumentAnchorNavigation(
        linkPath: "/tmp/docs",
        currentFilePath: "/tmp/docs/api/index.html",
        currentDocumentDirectory: "/tmp/docs/api"
    ))
}

// MARK: - Sidebar heading tree (document structure)

private func he(_ level: Int, _ id: String) -> WebViewStore.HeadingEntry {
    .init(level: level, text: id.capitalized, id: id)
}

@Test func headingTreeNestsByLevel() {
    let tree = SidebarHeadingNode.tree(from: [
        he(1, "title"),
        he(2, "install"),
        he(3, "macos"),
        he(3, "linux"),
        he(2, "usage"),
        he(3, "cli"),
        he(4, "flags"),
    ])
    #expect(tree.map(\.id) == ["title"])
    let title = tree[0]
    #expect(title.children.map(\.id) == ["install", "usage"])
    #expect(title.children[0].children.map(\.id) == ["macos", "linux"])
    let usage = title.children[1]
    #expect(usage.children.map(\.id) == ["cli"])
    #expect(usage.children[0].children.map(\.id) == ["flags"])
}

/// A section that jumps straight from H1 to H3 (no H2) still nests the H3
/// under the H1 — it must not become a sibling root.
@Test func headingTreeHandlesSkippedLevels() {
    let tree = SidebarHeadingNode.tree(from: [
        he(1, "a"),
        he(3, "b"),
        he(2, "c"),
    ])
    #expect(tree.map(\.id) == ["a"])
    #expect(tree[0].children.map(\.id) == ["b", "c"])
}

/// Multiple top-level (H1) headings become sibling roots, each keeping its
/// own subtree — collapsing one must not affect the other.
@Test func headingTreeSupportsMultipleRoots() {
    let tree = SidebarHeadingNode.tree(from: [
        he(1, "first"),
        he(2, "first-sub"),
        he(1, "second"),
        he(2, "second-sub"),
    ])
    #expect(tree.map(\.id) == ["first", "second"])
    #expect(tree[0].children.map(\.id) == ["first-sub"])
    #expect(tree[1].children.map(\.id) == ["second-sub"])
}

/// Deep chains (H1→H2→H3→H4→H5→H6) nest one level per heading so every
/// level is independently collapsible.
@Test func headingTreeNestsDeepChain() {
    let tree = SidebarHeadingNode.tree(from: (1...6).map { he($0, "h\($0)") })
    var node = tree
    for level in 1...6 {
        #expect(node.map(\.id) == ["h\(level)"])
        node = node[0].children
    }
    #expect(node.isEmpty)
}

// MARK: - FileScanner hidden files

/// Builds a temp directory tree exercising the hidden-files decision matrix:
/// plain file/dir, a hidden dir + file, a hidden file, the always-excluded
/// `.git` and `node_modules`, and a gitignored dot-dir (`.build/`).
/// Returns the root; caller must remove it.
private func makeHiddenFilesFixture() throws -> URL {
    let fm = FileManager.default
    // Resolve the /var -> /private/var symlink up front so relative paths computed
    // by the scanner (which resolves it) line up with this base path.
    let root = fm.temporaryDirectory
        .appendingPathComponent("moremaid-scan-\(UUID().uuidString)")
        .resolvingSymlinksInPath()

    func write(_ text: String, _ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    try write("v", "visible.md")           // plain file
    try write("i", "sub/inner.md")         // plain dir + file
    try write("g", ".github/gh.md")        // hidden dir + file
    try write("e", ".env")                 // hidden file
    try write("c", ".git/config")          // always excluded
    try write("p", "node_modules/pkg.md")  // always excluded
    try write("b", ".build/ignored.md")    // gitignored dot-dir
    try write(".build/\n", ".gitignore")   // gitignore rule for .build
    return root
}

// Asserted on file basenames rather than relativePath: on macOS the scanner
// canonicalises the temp dir (stripping /private) so relativePath strings carry a
// harmless prefix mismatch under a symlinked temp root. Each fixture basename maps to
// exactly one decision case, so basenames fully identify which entries were returned.
// visible.md/inner.md = plain, gh.md = hidden dir, .env = hidden file,
// config = .git, pkg.md = node_modules, ignored.md = gitignored .build.

@Test func fileScannerHidesDotEntriesByDefaultTest() throws {
    let root = try makeHiddenFilesFixture()
    defer { try? FileManager.default.removeItem(at: root) }

    let names = Set(FileScanner.scan(directory: root.path, filter: .allFiles, showHidden: false)
        .map(\.name))

    // Regression guard: with the toggle off, only non-hidden entries appear.
    #expect(names.contains("visible.md"))
    #expect(names.contains("inner.md"))
    #expect(!names.contains(".env"))
    #expect(!names.contains("gh.md"))
    #expect(!names.contains("config"))
    #expect(!names.contains("pkg.md"))
    #expect(!names.contains("ignored.md"))
}

@Test func fileScannerRevealsDotEntriesWhenShowHiddenTest() throws {
    let root = try makeHiddenFilesFixture()
    defer { try? FileManager.default.removeItem(at: root) }

    let names = Set(FileScanner.scan(directory: root.path, filter: .allFiles, showHidden: true)
        .map(\.name))

    // Hidden files and directories are revealed (gh.md proves .github/ was traversed)...
    #expect(names.contains("visible.md"))
    #expect(names.contains("inner.md"))
    #expect(names.contains("gh.md"))
    #expect(names.contains(".env"))
    // ...but the heavy dirs stay excluded by name...
    #expect(!names.contains("config"))   // .git/config
    #expect(!names.contains("pkg.md"))   // node_modules/pkg.md
    // ...and gitignore still wins.
    #expect(!names.contains("ignored.md"))   // .build/ignored.md
}

@Test func htmlHeadingParserIgnoresNavigationAndUsesMainHeadingsTest() {
    let html = """
    <html>
    <body>
      <aside class="sidebar"><h2>Navigation</h2><nav><a href="#intro">Intro link</a></nav></aside>
      <main>
        <h1>API Guide</h1>
        <h2 id="intro">Intro &amp; Setup</h2>
        <h3><code>Query.new</code></h3>
      </main>
    </body>
    </html>
    """

    let headings = HeadingParser.extractHeadings(fromHTML: html)
    #expect(headings.map(\.text) == ["API Guide", "Intro & Setup", "Query.new"])
    #expect(headings.map(\.id) == ["api-guide", "intro", "querynew"])
    #expect(headings.map(\.level) == [1, 2, 3])
}
