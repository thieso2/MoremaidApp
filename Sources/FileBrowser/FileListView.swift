import SwiftUI

struct FileListView: View {
    let project: Project
    @Binding var selectedFile: FileEntry?
    @State private var searchText = ""
    @State private var sortMethod: SortMethod = .dateDesc
    @State private var fileFilter: FileFilter = .markdownOnly
    @State private var files: [FileEntry] = []
    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with project name and controls
            HStack {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
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
                    Divider()
                    Button {
                        fileFilter = fileFilter == .markdownOnly ? .allFiles : .markdownOnly
                    } label: {
                        Text(fileFilter == .markdownOnly ? "Show All Files" : "Markdown Only")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Search field
            TextField("Search files...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            // File list
            List(filteredAndSortedFiles, selection: $selectedFile) { file in
                FileRowView(file: file)
                    .tag(file)
            }
            .listStyle(.plain)
        }
        .task {
            startScan()
        }
        .onChange(of: fileFilter) {
            startScan()
        }
    }

    private func startScan() {
        files = []
        isScanning = true
        let filter = fileFilter
        let path = project.path
        print("[ui] startScan for \(path)")
        let uiStart = CFAbsoluteTimeGetCurrent()

        FileScanner.scanBatched(directory: path, filter: filter, batchSize: 20) { batch, done in
            DispatchQueue.main.async {
                if files.isEmpty {
                    print("[ui] first batch of \(batch.count) files after \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - uiStart) * 1000))ms")
                }
                files.append(contentsOf: batch)
                if done {
                    isScanning = false
                    print("[ui] scan complete: \(files.count) files after \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - uiStart) * 1000))ms")
                }
            }
        }
    }

    private var filteredAndSortedFiles: [FileEntry] {
        var result = files.filter { fileFilter.matches($0) }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.relativePath.lowercased().contains(query) ||
                $0.name.lowercased().contains(query)
            }
        }
        return sortMethod.sort(result)
    }
}
