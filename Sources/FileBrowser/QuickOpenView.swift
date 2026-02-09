import SwiftUI

// MARK: - Browse mode

private enum BrowseMode {
    case directory
    case flat
}

// MARK: - Directory entry model

enum DirEntry: Identifiable {
    case folder(name: String, path: String)
    case file(FileEntry)

    var id: String {
        switch self {
        case .folder(_, let path): "dir:\(path)"
        case .file(let entry): "file:\(entry.id)"
        }
    }

    var name: String {
        switch self {
        case .folder(let name, _): name
        case .file(let entry): entry.name
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}

// MARK: - QuickOpenView

struct QuickOpenView: View {
    let files: [FileEntry]
    let isScanning: Bool
    let onSelect: (FileEntry) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var currentDir = ""
    @State private var selectedIndex = 0
    @AppStorage("quickOpenSort") private var sortMethodRaw = SortMethod.dateDesc.rawValue
    @AppStorage("quickOpenMarkdownOnly") private var markdownOnly = true
    @AppStorage("quickOpenBrowseMode") private var browseModeRaw = "directory"
    @FocusState private var isSearchFocused: Bool

    private var sortMethod: SortMethod {
        get { SortMethod(rawValue: sortMethodRaw) ?? .dateDesc }
        nonmutating set { sortMethodRaw = newValue.rawValue }
    }

    private var browseMode: BrowseMode {
        get { browseModeRaw == "flat" ? .flat : .directory }
        nonmutating set { browseModeRaw = newValue == .flat ? "flat" : "directory" }
    }

    /// Filtered files for the current settings.
    private var baseFiles: [FileEntry] {
        markdownOnly ? files.filter { $0.isMarkdown } : files
    }

    /// Flat mode results — all files, filtered by query.
    private var flatResults: [FileEntry] {
        var results = baseFiles
        if !query.isEmpty {
            let q = query.lowercased()
            results = results.filter { fuzzyMatch($0.name.lowercased(), query: q) }
        }
        return sortMethod.sort(results)
    }

    /// Directory browse entries (folders + files in current directory), filtered by query within current dir and below.
    private var directoryEntries: [DirEntry] {
        let allFiles = baseFiles
        let prefix = currentDir.isEmpty ? "" : currentDir + "/"

        if !query.isEmpty {
            // Filter files in currentDir and below, matching by name
            let q = query.lowercased()
            let scopedFiles = allFiles.filter { file in
                let rel = file.relativePath
                let inScope = currentDir.isEmpty || rel.hasPrefix(prefix)
                return inScope && fuzzyMatch(file.name.lowercased(), query: q)
            }
            return sortMethod.sort(scopedFiles).map { .file($0) }
        }

        // No query: show folders + files in current directory
        let dirFiles = allFiles.filter { $0.directory == currentDir }

        var subdirNames = Set<String>()
        for file in allFiles {
            let rel = file.relativePath
            guard rel.hasPrefix(prefix) || currentDir.isEmpty else { continue }
            let remainder = currentDir.isEmpty ? rel : String(rel.dropFirst(prefix.count))
            if let slash = remainder.firstIndex(of: "/") {
                subdirNames.insert(String(remainder[..<slash]))
            }
        }

        var result: [DirEntry] = subdirNames.sorted().map { name in
            .folder(name: name, path: currentDir.isEmpty ? name : "\(currentDir)/\(name)")
        }
        result += sortMethod.sort(dirFiles).map { .file($0) }
        return result
    }

    /// Breadcrumb path components.
    private var breadcrumbs: [BreadcrumbItem] {
        var items = [BreadcrumbItem(name: "~", path: "")]
        if !currentDir.isEmpty {
            let parts = currentDir.split(separator: "/").map(String.init)
            var path = ""
            for part in parts {
                path = path.isEmpty ? part : "\(path)/\(part)"
                items.append(BreadcrumbItem(name: part, path: path))
            }
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(browseMode == .directory ? "Filter in directory..." : "Search all files...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit { selectCurrent() }
                    .onChange(of: query) { selectedIndex = 0 }
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)

            // Breadcrumb navigation (always present to keep stable height)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(breadcrumbs) { crumb in
                        if crumb.path != "" || breadcrumbs.count > 1 {
                            if crumb.path != breadcrumbs.first?.path {
                                Text("/")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                        }
                        Button(crumb.name) {
                            navigateTo(crumb.path)
                        }
                        .buttonStyle(.plain)
                        .font(.caption.bold())
                        .foregroundStyle(crumb.path == currentDir ? .primary : .secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .opacity(browseMode == .directory ? 1 : 0)
            .allowsHitTesting(browseMode == .directory)

            Divider()

            // Results
            if browseMode == .flat {
                if flatResults.isEmpty {
                    emptyState
                } else {
                    flatResultsList
                }
            } else {
                if directoryEntries.isEmpty {
                    emptyState
                } else {
                    directoryList
                }
            }

            Divider()

            // Bottom bar
            bottomBar
        }
        .modifier(GlassEffectModifier())
        .frame(width: 520)
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            let count: Int
            if browseMode == .flat {
                count = min(flatResults.count, 50)
            } else {
                count = min(directoryEntries.count, 50)
            }
            if selectedIndex < count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            if !query.isEmpty {
                query = ""
            } else if browseMode == .directory && !currentDir.isEmpty {
                goUp()
            } else {
                onDismiss()
            }
            return .handled
        }
        .onKeyPress(.tab, phases: .down) { press in
            if press.modifiers == .option {
                markdownOnly.toggle()
                selectedIndex = 0
                return .handled
            }
            return .ignored
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleBrowseMode)) { _ in
            browseMode = browseMode == .directory ? .flat : .directory
            selectedIndex = 0
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleQuickOpen)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Text(isScanning ? "Scanning..." : "No matches")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }

    // MARK: - Flat results list

    private var flatResultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(flatResults.prefix(50).enumerated()), id: \.element.id) { index, file in
                        FileSearchRow(
                            file: file,
                            query: query.lowercased(),
                            isSelected: index == selectedIndex
                        )
                        .id(file.id)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(file) }
                    }
                }
            }
            .frame(maxHeight: 350)
            .onChange(of: selectedIndex) {
                if let file = flatResults.prefix(50)[safe: selectedIndex] {
                    proxy.scrollTo(file.id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Directory browse list

    private var directoryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(directoryEntries.prefix(50).enumerated()), id: \.element.id) { index, entry in
                        DirEntryRow(
                            entry: entry,
                            query: query.lowercased(),
                            isSelected: index == selectedIndex
                        )
                        .id(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture { activate(entry) }
                    }
                }
            }
            .frame(maxHeight: 350)
            .onChange(of: selectedIndex) {
                if let entry = directoryEntries.prefix(50)[safe: selectedIndex] {
                    proxy.scrollTo(entry.id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(SortMethod.allCases, id: \.self) { method in
                    Button {
                        sortMethod = method
                    } label: {
                        HStack {
                            Text(method.label)
                            if sortMethod == method {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(sortMethod.label, systemImage: "arrow.up.arrow.down")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Mode indicators (clickable)
            Button {
                browseMode = browseMode == .directory ? .flat : .directory
                selectedIndex = 0
            } label: {
                Text(browseMode == .directory ? "Dir" : "Flat")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Shift+Tab to toggle")

            Button {
                markdownOnly.toggle()
                selectedIndex = 0
            } label: {
                Text(markdownOnly ? "MD" : "All")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(markdownOnly ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Option+Tab to toggle")

            Spacer()

            if browseMode == .flat {
                let count = flatResults.count
                Text("\(count) file\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let fileCount = directoryEntries.filter { !$0.isFolder }.count
                let dirCount = directoryEntries.filter { $0.isFolder }.count
                Text("\(fileCount) files\(dirCount > 0 ? ", \(dirCount) dirs" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func selectCurrent() {
        if browseMode == .flat {
            let visible = Array(flatResults.prefix(50))
            if selectedIndex < visible.count {
                onSelect(visible[selectedIndex])
            }
        } else {
            let visible = Array(directoryEntries.prefix(50))
            if selectedIndex < visible.count {
                activate(visible[selectedIndex])
            }
        }
    }

    private func activate(_ entry: DirEntry) {
        switch entry {
        case .folder(_, let path):
            navigateTo(path)
        case .file(let fileEntry):
            onSelect(fileEntry)
        }
    }

    private func navigateTo(_ path: String) {
        currentDir = path
        query = ""
        selectedIndex = 0
    }

    private func goUp() {
        if let slash = currentDir.lastIndex(of: "/") {
            currentDir = String(currentDir[..<slash])
        } else {
            currentDir = ""
        }
        selectedIndex = 0
    }

    private func fuzzyMatch(_ string: String, query: String) -> Bool {
        var idx = string.startIndex
        for char in query {
            guard let found = string[idx...].firstIndex(of: char) else { return false }
            idx = string.index(after: found)
        }
        return true
    }
}

// MARK: - Breadcrumb item

private struct BreadcrumbItem: Identifiable {
    let name: String
    let path: String
    var id: String { path.isEmpty ? "~" : path }
}

// MARK: - Safe subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - File search row (flat mode)

private struct FileSearchRow: View {
    let file: FileEntry
    let query: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.isMarkdown ? "doc.richtext" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(highlightedAttributed(file.name, query: query))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !file.directory.isEmpty {
                        Text(file.directory)
                            .lineLimit(1)
                    }
                    Text(formatTimeAgo(file.modifiedDate))
                        .help(formatFullDate(file.modifiedDate))
                    Text(formatSize(file.size))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Directory entry row (browse mode)

private struct DirEntryRow: View {
    let entry: DirEntry
    let query: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(entry.isFolder ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(highlightedAttributed(entry.name, query: query))
                        .lineLimit(1)
                    if entry.isFolder {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if case .file(let file) = entry {
                    HStack(spacing: 8) {
                        Text(formatTimeAgo(file.modifiedDate))
                            .help(formatFullDate(file.modifiedDate))
                        Text(formatSize(file.size))
                        if !query.isEmpty {
                            Text(file.directory)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch entry {
        case .folder: "folder.fill"
        case .file(let f): f.isMarkdown ? "doc.richtext" : "doc"
        }
    }
}

// MARK: - Shared highlight helpers (AttributedString — no deprecated Text+)

private func highlightedAttributed(_ text: String, query: String) -> AttributedString {
    guard !query.isEmpty else { return AttributedString(text) }
    let matched = fuzzyMatchIndices(text.lowercased(), query: query)
    var result = AttributedString()
    for (i, char) in text.enumerated() {
        var part = AttributedString(String(char))
        if matched.contains(i) {
            part.inlinePresentationIntent = .stronglyEmphasized
            part.foregroundColor = .accentColor
        }
        result.append(part)
    }
    return result
}

private func fuzzyMatchIndices(_ string: String, query: String) -> Set<Int> {
    var indices = Set<Int>()
    let chars = Array(string)
    var qIter = query.makeIterator()
    guard var nextQ = qIter.next() else { return indices }
    for (i, c) in chars.enumerated() {
        if c == nextQ {
            indices.insert(i)
            if let nq = qIter.next() {
                nextQ = nq
            } else {
                break
            }
        }
    }
    return indices
}

// MARK: - Glass effect (macOS 26+)

struct GlassEffectModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
