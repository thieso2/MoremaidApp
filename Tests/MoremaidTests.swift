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
