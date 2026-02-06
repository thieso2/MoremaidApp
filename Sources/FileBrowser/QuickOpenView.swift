import SwiftUI

struct QuickOpenView: View {
    let files: [FileEntry]
    let isScanning: Bool
    let onSelect: (FileEntry) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var sortMethod: SortMethod = .dateDesc
    @State private var markdownOnly = true
    @FocusState private var isSearchFocused: Bool

    private var filteredFiles: [FileEntry] {
        var result = markdownOnly ? files.filter { $0.isMarkdown } : files
        if !query.isEmpty {
            let q = query.lowercased()
            result = result.filter {
                fuzzyMatch($0.relativePath.lowercased(), query: q) ||
                fuzzyMatch($0.name.lowercased(), query: q)
            }
        }
        return sortMethod.sort(result)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Open file...", text: $query)
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

            Divider()

            // Results
            QuickOpenResultsList(
                files: filteredFiles,
                query: query.lowercased(),
                selectedIndex: $selectedIndex,
                isScanning: isScanning,
                onSelect: onSelect
            )

            Divider()

            // Bottom bar: sort, filter, count
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

                Toggle(isOn: $markdownOnly) {
                    Text("MD")
                        .font(.caption.bold())
                }
                .toggleStyle(.button)
                .controlSize(.small)

                Spacer()

                Text("\(filteredFiles.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .frame(width: 520)
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            let count = min(filteredFiles.count, 30)
            if selectedIndex < count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
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

    private func selectCurrent() {
        let results = Array(filteredFiles.prefix(30))
        if selectedIndex < results.count {
            onSelect(results[selectedIndex])
        }
    }

    /// Fuzzy match: all characters of query appear in order in the string.
    private func fuzzyMatch(_ string: String, query: String) -> Bool {
        var idx = string.startIndex
        for char in query {
            guard let found = string[idx...].firstIndex(of: char) else { return false }
            idx = string.index(after: found)
        }
        return true
    }
}

// MARK: - Results list (extracted for proper SwiftUI identity)

private struct QuickOpenResultsList: View {
    let files: [FileEntry]
    let query: String
    @Binding var selectedIndex: Int
    let isScanning: Bool
    let onSelect: (FileEntry) -> Void

    private var results: [FileEntry] { Array(files.prefix(30)) }

    var body: some View {
        if results.isEmpty {
            Text(isScanning ? "Scanning..." : "No files found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { file in
                            let index = results.firstIndex(of: file) ?? 0
                            QuickOpenRow(
                                file: file,
                                query: query,
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
                    if let file = results[safe: selectedIndex] {
                        proxy.scrollTo(file.id, anchor: .center)
                    }
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Row with highlighting

private struct QuickOpenRow: View {
    let file: FileEntry
    let query: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.isMarkdown ? "doc.richtext" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                highlightedText(file.name, query: query)
                    .lineLimit(1)
                if !file.directory.isEmpty {
                    highlightedText(file.directory, query: query)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
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
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear)
        .contentShape(Rectangle())
    }

    private func highlightedText(_ text: String, query: String) -> Text {
        guard !query.isEmpty else { return Text(text) }

        let matched = fuzzyMatchIndices(text.lowercased(), query: query)
        var result = Text("")
        for (i, char) in text.enumerated() {
            if matched.contains(i) {
                result = result + Text(String(char)).bold().foregroundColor(.accentColor)
            } else {
                result = result + Text(String(char))
            }
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
}
