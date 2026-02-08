import SwiftUI

struct SearchInFilesView: View {
    let files: [FileEntry]
    @Binding var searchQuery: String
    @Binding var isPresented: Bool
    @Binding var searchResults: [SearchResult]
    @Binding var activeFileIndex: Int
    @Binding var activeMatchIndex: Int
    let onSelectResult: (FileEntry, String, Int, Int) -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onFirst: () -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var totalMatchCount = 0
    @State private var expandedPaths: Set<String> = []
    @AppStorage("searchPanelWidth") private var panelWidth = Constants.searchPanelDefaultWidth

    var body: some View {
        HStack(spacing: 0) {
            panelDragHandle
            VStack(spacing: 0) {
                searchHeader
                if !searchResults.isEmpty {
                    navigationBar
                }
                Divider()
                resultsList
            }
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity)
            .background(.windowBackground)
        }
        .onAppear {
            isSearchFocused = true
            if !searchQuery.isEmpty {
                triggerSearch()
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    // MARK: - Drag Handle

    private var panelDragHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newWidth = panelWidth - value.translation.width
                        panelWidth = min(Constants.searchPanelMaxWidth, max(Constants.searchPanelMinWidth, newWidth))
                    }
            )
    }

    // MARK: - Header

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search in files...", text: $searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit { triggerSearch() }
                .onChange(of: searchQuery) { debouncedSearch() }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                    totalMatchCount = 0
                    activeFileIndex = -1
                    activeMatchIndex = -1
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isPresented = false }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(10)
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack(spacing: 6) {
            Spacer()

            Text(positionLabel)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Previous Match (\u{21E7}\u{2318}G)")

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Next Match (\u{2318}G)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var positionLabel: String {
        if isSearching {
            return "Searching..."
        }
        guard activeFileIndex >= 0, activeMatchIndex >= 0 else {
            return "\(totalMatchCount) matches in \(searchResults.count) files"
        }
        var pos = 0
        for i in 0..<activeFileIndex {
            pos += searchResults[i].matches?.count ?? 0
        }
        pos += activeMatchIndex + 1
        return "\(pos) of \(totalMatchCount)"
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(searchResults.enumerated()), id: \.element.path) { fileIndex, result in
                        resultFileGroup(result, fileIndex: fileIndex)
                    }
                }
            }
            .onChange(of: activeFileIndex) { scrollToActive(proxy: proxy) }
            .onChange(of: activeMatchIndex) { scrollToActive(proxy: proxy) }
        }
    }

    private func scrollToActive(proxy: ScrollViewProxy) {
        guard activeFileIndex >= 0, activeMatchIndex >= 0 else { return }
        let scrollID = "\(activeFileIndex)-\(activeMatchIndex)"
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(scrollID, anchor: .center)
        }
    }

    private func resultFileGroup(_ result: SearchResult, fileIndex: Int) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedPaths.contains(result.path) },
            set: { newValue in
                if newValue { expandedPaths.insert(result.path) }
                else { expandedPaths.remove(result.path) }
            }
        )) {
            if let matches = result.matches {
                ForEach(Array(matches.enumerated()), id: \.offset) { matchIndex, match in
                    let isActive = fileIndex == activeFileIndex && matchIndex == activeMatchIndex
                    matchRow(match, matchIndex: matchIndex, filePath: result.path, isActive: isActive)
                        .id("\(fileIndex)-\(matchIndex)")
                        .padding(.leading, 8)
                }
            }
        } label: {
            fileHeader(result, isActiveFile: fileIndex == activeFileIndex)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    private func fileHeader(_ result: SearchResult, isActiveFile: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: fileIcon(for: result.fileName))
                .foregroundStyle(isActiveFile ? .primary : .secondary)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.fileName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(isActiveFile ? .primary : .secondary)
                    .lineLimit(1)
                if !result.directory.isEmpty {
                    Text(result.directory)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text("\(result.matches?.count ?? 0)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
    }

    private func matchRow(_ match: SearchMatch, matchIndex: Int, filePath: String, isActive: Bool) -> some View {
        Button {
            if let file = files.first(where: { $0.relativePath == filePath }) {
                onSelectResult(file, searchQuery, match.lineNumber, matchIndex)
            }
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Text("\(match.lineNumber)")
                    .font(.caption.monospaced())
                    .foregroundStyle(isActive ? .primary : .tertiary)
                    .frame(minWidth: 30, alignment: .trailing)
                Text(highlightedText(match.text, query: searchQuery))
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: 4).fill(.selection.opacity(0.3))
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func highlightedText(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        let lowText = text.lowercased()
        let lowQuery = query.lowercased()
        var searchStart = lowText.startIndex

        while let range = lowText.range(of: lowQuery, range: searchStart..<lowText.endIndex) {
            let attrStart = AttributedString.Index(range.lowerBound, within: attributed)
            let attrEnd = AttributedString.Index(range.upperBound, within: attributed)
            if let attrStart, let attrEnd {
                attributed[attrStart..<attrEnd].backgroundColor = .yellow.opacity(0.3)
                attributed[attrStart..<attrEnd].font = .caption.bold()
            }
            searchStart = range.upperBound
        }

        return attributed
    }

    private func fileIcon(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if Constants.markdownExtensions.contains(ext) {
            return "doc.text"
        }
        return "doc"
    }

    // MARK: - Search Logic

    private func debouncedSearch() {
        searchTask?.cancel()
        guard !searchQuery.isEmpty, searchQuery.count >= Constants.searchMinTerm else {
            searchResults = []
            totalMatchCount = 0
            activeFileIndex = -1
            activeMatchIndex = -1
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .seconds(Constants.searchInFilesDebounce))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    private func triggerSearch() {
        searchTask?.cancel()
        guard !searchQuery.isEmpty, searchQuery.count >= Constants.searchMinTerm else { return }
        isSearching = true
        searchTask = Task {
            await performSearch()
        }
    }

    private func performSearch() async {
        let query = searchQuery
        let results = await ContentSearch.searchContent(query: query, in: files)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            searchResults = results
            totalMatchCount = results.reduce(0) { $0 + ($1.matches?.count ?? 0) }
            expandedPaths = Set(results.map(\.path))
            activeFileIndex = -1
            activeMatchIndex = -1
            isSearching = false
        }
    }
}
