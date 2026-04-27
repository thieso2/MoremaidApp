import SwiftUI
import AppKit

// MARK: - Heading Tree

/// Hierarchical heading node. Built from the flat `[HeadingEntry]` list by grouping
/// each heading under the most recent heading of a lower level.
struct SidebarHeadingNode: Identifiable, Hashable {
    let id: String
    let text: String
    let level: Int
    let children: [SidebarHeadingNode]
}

extension SidebarHeadingNode {
    static func tree(from headings: [WebViewStore.HeadingEntry]) -> [SidebarHeadingNode] {
        struct Frame {
            var level: Int
            var text: String
            var id: String
            var children: [SidebarHeadingNode]
        }
        var stack: [Frame] = []
        var roots: [SidebarHeadingNode] = []

        for h in headings {
            while let top = stack.last, top.level >= h.level {
                stack.removeLast()
                let node = SidebarHeadingNode(id: top.id, text: top.text, level: top.level, children: top.children)
                if stack.isEmpty {
                    roots.append(node)
                } else {
                    stack[stack.count - 1].children.append(node)
                }
            }
            stack.append(Frame(level: h.level, text: h.text, id: h.id, children: []))
        }
        while !stack.isEmpty {
            let top = stack.removeLast()
            let node = SidebarHeadingNode(id: top.id, text: top.text, level: top.level, children: top.children)
            if stack.isEmpty {
                roots.append(node)
            } else {
                stack[stack.count - 1].children.append(node)
            }
        }
        return roots
    }
}

// MARK: - Flat Row Model

/// Single visible row. Building one flat list (instead of recursive nested
/// VStacks) lets `LazyVStack` actually be lazy.
enum SidebarRow: Identifiable, Hashable {
    case folder(path: String, name: String, depth: Int, isOpen: Bool)
    case file(entry: FileEntry, depth: Int, isOpen: Bool, hasChildren: Bool, isSelected: Bool)
    case heading(node: SidebarHeadingNode, depth: Int, fileRelPath: String, isCurrentFile: Bool, isActive: Bool, isCollapsed: Bool)

    var id: String {
        switch self {
        case .folder(let path, _, _, _): "f:\(path)"
        case .file(let entry, _, _, _, _): "F:\(entry.relativePath)"
        case .heading(let node, _, let fileRelPath, _, _, _): "h:\(fileRelPath):\(node.id)"
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    let directoryPath: String
    let projectFiles: [FileEntry]
    @Binding var selectedFile: FileEntry?
    @Binding var headingsCache: [String: [WebViewStore.HeadingEntry]]
    let currentHeadingID: String
    let onScrollToAnchor: (String) -> Void
    let onNavigateToFileAnchor: (String, String) -> Void

    @AppStorage("sidebarWidth") private var width: Double = 240
    @AppStorage("sidebarSort") private var sortRaw: String = SidebarSort.foldersFirst.rawValue
    @AppStorage("sidebarFilter") private var filterRaw: String = FileFilter.markdownOnly.rawValue
    @AppStorage("sidebarFontSize") private var fontSize: Double = 13
    @State private var search: String = ""
    @State private var expandedFolders: Set<String> = []
    @State private var expandedFiles: Set<String> = []
    @State private var collapsedHeadings: Set<String> = []
    @State private var didLoadExpanded = false

    private var sort: SidebarSort {
        SidebarSort(rawValue: sortRaw) ?? .foldersFirst
    }

    private var filter: FileFilter {
        FileFilter(rawValue: filterRaw) ?? .markdownOnly
    }

    /// Files passing the type filter and the search query. Search matches
    /// filename, path, *or* any cached heading's text.
    private var filteredFiles: [FileEntry] {
        let base = projectFiles.filter { filter.matches($0) }
        if search.isEmpty { return base }
        let q = search.lowercased()
        return base.filter { file in
            if file.relativePath.lowercased().contains(q) { return true }
            if file.name.lowercased().contains(q) { return true }
            if let cached = headingsCache[file.relativePath],
               cached.contains(where: { $0.text.lowercased().contains(q) }) {
                return true
            }
            return false
        }
    }

    private var nodes: [SidebarNode] {
        SidebarTreeBuilder.build(files: filteredFiles, sort: sort)
    }

    /// While filtering, force-expand the tree so every match is visible —
    /// without touching the user's persisted expansion state. When filter
    /// clears, the tree snaps back to whatever the user had open.
    private var effectiveExpansion: (folders: Set<String>, files: Set<String>, ignoreCollapsedHeadings: Bool) {
        guard !search.isEmpty else {
            return (expandedFolders, expandedFiles, false)
        }
        var folders = expandedFolders
        var files = expandedFiles
        let q = search.lowercased()
        for file in filteredFiles {
            // Expand every ancestor folder so the matching file row is visible.
            let parts = file.relativePath.split(separator: "/").map(String.init)
            if parts.count > 1 {
                for i in 0..<(parts.count - 1) {
                    folders.insert(parts[0...i].joined(separator: "/"))
                }
            }
            // If the match is on a heading text, expand the file itself too.
            if let cached = headingsCache[file.relativePath],
               cached.contains(where: { $0.text.lowercased().contains(q) }) {
                files.insert(file.relativePath)
            }
        }
        return (folders, files, true)
    }

    /// Pre-compute the visible row list. Re-runs when state changes; cheap
    /// because we only enumerate expanded subtrees.
    private var flatRows: [SidebarRow] {
        var rows: [SidebarRow] = []
        let exp = effectiveExpansion

        func walkHeading(_ heading: SidebarHeadingNode, depth: Int, fileRelPath: String, isCurrentFile: Bool) {
            let key = headingKey(file: fileRelPath, id: heading.id)
            // While filtering, ignore explicit heading collapses so all sub-
            // sections are visible (matches may be nested under a collapsed one).
            let collapsed = !exp.ignoreCollapsedHeadings && collapsedHeadings.contains(key)
            let isActive = isCurrentFile && heading.id == currentHeadingID
            rows.append(.heading(
                node: heading,
                depth: depth,
                fileRelPath: fileRelPath,
                isCurrentFile: isCurrentFile,
                isActive: isActive,
                isCollapsed: collapsed
            ))
            if !heading.children.isEmpty && !collapsed {
                for child in heading.children {
                    walkHeading(child, depth: depth + 1, fileRelPath: fileRelPath, isCurrentFile: isCurrentFile)
                }
            }
        }

        func walk(_ node: SidebarNode, depth: Int) {
            switch node {
            case .folder(let path, let name, let children):
                let isOpen = exp.folders.contains(path)
                rows.append(.folder(path: path, name: name, depth: depth, isOpen: isOpen))
                if isOpen {
                    for child in children { walk(child, depth: depth + 1) }
                }
            case .file(let entry):
                let cached = headingsCache[entry.relativePath]
                let hasChildren = entry.isMarkdown // markdown rows always show a chevron
                let isOpen = exp.files.contains(entry.relativePath) && hasChildren
                let isSelected = selectedFile?.relativePath == entry.relativePath
                rows.append(.file(
                    entry: entry,
                    depth: depth,
                    isOpen: isOpen,
                    hasChildren: hasChildren,
                    isSelected: isSelected
                ))
                if isOpen, let headings = cached, !headings.isEmpty {
                    let tree = SidebarHeadingNode.tree(from: headings)
                    for h in tree {
                        walkHeading(h, depth: depth + 1, fileRelPath: entry.relativePath, isCurrentFile: isSelected)
                    }
                }
            }
        }

        for n in nodes { walk(n, depth: 0) }
        return rows
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider()
                outline
            }
            .frame(width: max(180, width))
            .background(.windowBackground)

            resizeHandle
        }
        .onAppear { loadExpandedState() }
        .onChange(of: selectedFile) { autoExpandForSelection() }
        .onChange(of: directoryPath) {
            didLoadExpanded = false
            loadExpandedState()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("Filter…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Menu {
                Picker("Show", selection: $filterRaw) {
                    Text("Markdown Only").tag(FileFilter.markdownOnly.rawValue)
                    Text("All Files").tag(FileFilter.allFiles.rawValue)
                }
                Divider()
                Picker("Sort", selection: $sortRaw) {
                    Text("Folders First").tag(SidebarSort.foldersFirst.rawValue)
                    Text("Interleaved").tag(SidebarSort.interleaved.rawValue)
                }
                Divider()
                Section("Font Size") {
                    Button("Smaller") { fontSize = max(9, fontSize - 1) }
                    Button("Larger") { fontSize = min(20, fontSize + 1) }
                    Button("Reset") { fontSize = 13 }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Outline

    private var outline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if flatRows.isEmpty {
                        Text(search.isEmpty ? "No files" : "No matches")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: fontSize))
                            .padding(16)
                    } else {
                        ForEach(flatRows) { row in
                            rowView(row)
                                .id(row.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: currentHeadingID) {
                guard !currentHeadingID.isEmpty,
                      let file = selectedFile else { return }
                let key = headingKey(file: file.relativePath, id: currentHeadingID)
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(key, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: SidebarRow) -> some View {
        switch row {
        case .folder(let path, let name, let depth, let isOpen):
            SidebarFolderRow(
                name: name,
                depth: depth,
                isOpen: isOpen,
                fontSize: fontSize,
                onToggle: { toggleFolder(path: path) }
            )
        case .file(let entry, let depth, let isOpen, let hasChildren, let isSelected):
            SidebarFileRow(
                entry: entry,
                depth: depth,
                isSelected: isSelected,
                isOpen: isOpen,
                hasChildren: hasChildren,
                fontSize: fontSize,
                onSelect: { selectedFile = entry },
                onToggle: { toggleFile(entry: entry) }
            )
        case .heading(let node, let depth, let fileRelPath, let isCurrentFile, let isActive, let isCollapsed):
            SidebarHeadingRow(
                heading: node,
                depth: depth,
                isActive: isActive,
                isCollapsed: isCollapsed,
                hasChildren: !node.children.isEmpty,
                fontSize: fontSize,
                onSelect: {
                    if isCurrentFile {
                        onScrollToAnchor(node.id)
                    } else {
                        onNavigateToFileAnchor(fileRelPath, node.id)
                    }
                },
                onToggle: { toggleHeading(key: headingKey(file: fileRelPath, id: node.id)) }
            )
        }
    }

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let new = width + value.translation.width
                        width = min(500, max(180, new))
                    }
            )
            .overlay(alignment: .leading) {
                Divider()
            }
    }

    // MARK: - Toggle helpers

    private func toggleFolder(path: String) {
        if expandedFolders.contains(path) {
            expandedFolders.remove(path)
        } else {
            expandedFolders.insert(path)
        }
        saveExpandedState()
    }

    private func toggleFile(entry: FileEntry) {
        if expandedFiles.contains(entry.relativePath) {
            expandedFiles.remove(entry.relativePath)
        } else {
            // Populate cache from disk if we don't already have headings for
            // this file (cheap for typical markdown files).
            if entry.isMarkdown && headingsCache[entry.relativePath] == nil {
                headingsCache[entry.relativePath] = HeadingParser.extractHeadings(fromFileAtPath: entry.absolutePath)
            }
            expandedFiles.insert(entry.relativePath)
        }
        saveExpandedState()
    }

    private func toggleHeading(key: String) {
        if collapsedHeadings.contains(key) {
            collapsedHeadings.remove(key)
        } else {
            collapsedHeadings.insert(key)
        }
    }

    private func headingKey(file: String, id: String) -> String {
        "h:\(file):\(id)"
    }

    // MARK: - Auto-expand

    private func autoExpandForSelection() {
        guard let file = selectedFile else { return }
        let ancestors = SidebarTreeBuilder.ancestorFolderPaths(for: file)
        var changed = false
        for path in ancestors where !expandedFolders.contains(path) {
            expandedFolders.insert(path)
            changed = true
        }
        if !expandedFiles.contains(file.relativePath) {
            expandedFiles.insert(file.relativePath)
            changed = true
        }
        if changed { saveExpandedState() }
    }

    // MARK: - Persistence

    /// Only folder expansion persists. File expansion is ephemeral so the
    /// navigator opens fresh each session — otherwise files appear "open"
    /// at launch even though their heading cache was lost when the app quit.
    private var expandedFoldersKey: String { "sidebarExpandedFolders:\(directoryPath)" }

    private func loadExpandedState() {
        guard !didLoadExpanded else { return }
        let folders = UserDefaults.standard.stringArray(forKey: expandedFoldersKey) ?? []
        expandedFolders = Set(folders)
        didLoadExpanded = true
        autoExpandForSelection()
    }

    private func saveExpandedState() {
        UserDefaults.standard.set(Array(expandedFolders), forKey: expandedFoldersKey)
    }
}

// MARK: - Row Views

private let sidebarRowIndent: CGFloat = 14

struct SidebarFolderRow: View {
    let name: String
    let depth: Int
    let isOpen: Bool
    let fontSize: Double
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 10)
                Image(systemName: isOpen ? "folder" : "folder.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: fontSize))
                Text(name)
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * sidebarRowIndent + 8)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SidebarFileRow: View {
    let entry: FileEntry
    let depth: Int
    let isSelected: Bool
    let isOpen: Bool
    let hasChildren: Bool
    let fontSize: Double
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if hasChildren {
                    Button(action: onToggle) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                }
            }
            .frame(width: 10)

            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .font(.system(size: fontSize))
            Text(entry.name)
                .font(.system(size: fontSize))
                .fontWeight(isSelected ? .medium : .regular)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * sidebarRowIndent + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 5).fill(.selection.opacity(0.35))
                : nil
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var iconName: String {
        entry.isMarkdown ? "doc.text" : "doc"
    }
}

struct SidebarHeadingRow: View {
    let heading: SidebarHeadingNode
    let depth: Int
    let isActive: Bool
    let isCollapsed: Bool
    let hasChildren: Bool
    let fontSize: Double
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if hasChildren {
                    Button(action: onToggle) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                }
            }
            .frame(width: 10)

            Image(systemName: "number")
                .foregroundStyle(.tertiary)
                .font(.system(size: max(9, fontSize - 2)))
                .frame(width: 12)

            Text(heading.text)
                .font(.system(size: max(9, fontSize - 1)))
                .fontWeight(heading.level <= 2 ? .medium : .regular)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * sidebarRowIndent + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(
            isActive
                ? RoundedRectangle(cornerRadius: 5).fill(.selection.opacity(0.35))
                : nil
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}
