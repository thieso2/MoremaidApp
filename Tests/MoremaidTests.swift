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
