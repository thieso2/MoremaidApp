import Foundation

/// All 10 typography CSS variable blocks, ported from ../lib/styles.js
enum TypographyCSS {
    static let all = """
    [data-typography="default"] {
        --font-body: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
        --font-heading: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
        --font-code: 'Monaco', 'Menlo', 'Ubuntu Mono', 'Courier New', monospace;
        --font-size-base: 16px;
        --line-height: 1.6;
        --paragraph-spacing: 1em;
        --max-width: 800px;
        --text-align: left;
    }

    [data-typography="github"] {
        --font-body: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
        --font-heading: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
        --font-code: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
        --font-size-base: 16px;
        --line-height: 1.5;
        --paragraph-spacing: 1em;
        --max-width: 1012px;
        --text-align: left;
    }

    [data-typography="latex"] {
        --font-body: 'Latin Modern Roman', 'Computer Modern', 'Georgia', serif;
        --font-heading: 'Latin Modern Roman', 'Computer Modern', 'Georgia', serif;
        --font-code: 'Latin Modern Mono', 'Computer Modern Typewriter', 'Courier New', monospace;
        --font-size-base: 12pt;
        --line-height: 1.4;
        --paragraph-spacing: 0.5em;
        --max-width: 6.5in;
        --text-align: justify;
    }

    [data-typography="tufte"] {
        --font-body: et-book, Palatino, 'Palatino Linotype', 'Palatino LT STD', 'Book Antiqua', Georgia, serif;
        --font-heading: et-book, Palatino, 'Palatino Linotype', 'Palatino LT STD', 'Book Antiqua', Georgia, serif;
        --font-code: Consolas, 'Liberation Mono', Menlo, Courier, monospace;
        --font-size-base: 15px;
        --line-height: 1.5;
        --paragraph-spacing: 1.4em;
        --max-width: 960px;
        --text-align: left;
    }

    [data-typography="medium"] {
        --font-body: charter, Georgia, Cambria, 'Times New Roman', Times, serif;
        --font-heading: 'Lucida Grande', 'Lucida Sans Unicode', 'Lucida Sans', Geneva, Arial, sans-serif;
        --font-code: 'Menlo', 'Monaco', 'Courier New', Courier, monospace;
        --font-size-base: 21px;
        --line-height: 1.58;
        --paragraph-spacing: 1.58em;
        --max-width: 680px;
        --text-align: left;
    }

    [data-typography="compact"] {
        --font-body: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        --font-heading: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        --font-code: 'Monaco', 'Menlo', monospace;
        --font-size-base: 14px;
        --line-height: 1.4;
        --paragraph-spacing: 0.5em;
        --max-width: 100%;
        --text-align: left;
    }

    [data-typography="wide"] {
        --font-body: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        --font-heading: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        --font-code: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
        --font-size-base: 16px;
        --line-height: 1.7;
        --paragraph-spacing: 1.2em;
        --max-width: 100%;
        --text-align: left;
    }

    [data-typography="newspaper"] {
        --font-body: 'Times New Roman', Times, serif;
        --font-heading: 'Georgia', 'Times New Roman', serif;
        --font-code: 'Courier New', Courier, monospace;
        --font-size-base: 16px;
        --line-height: 1.5;
        --paragraph-spacing: 0.8em;
        --max-width: 100%;
        --text-align: justify;
    }

    [data-typography="terminal"] {
        --font-body: 'Fira Code', 'Source Code Pro', 'Monaco', 'Menlo', monospace;
        --font-heading: 'Fira Code', 'Source Code Pro', 'Monaco', 'Menlo', monospace;
        --font-code: 'Fira Code', 'Source Code Pro', 'Monaco', 'Menlo', monospace;
        --font-size-base: 14px;
        --line-height: 1.5;
        --paragraph-spacing: 1em;
        --max-width: 900px;
        --text-align: left;
    }

    [data-typography="book"] {
        --font-body: 'Crimson Text', 'Baskerville', 'Georgia', serif;
        --font-heading: 'Crimson Text', 'Baskerville', 'Georgia', serif;
        --font-code: 'Courier New', Courier, monospace;
        --font-size-base: 18px;
        --line-height: 1.7;
        --paragraph-spacing: 1.5em;
        --max-width: 650px;
        --text-align: justify;
    }
    """
}
