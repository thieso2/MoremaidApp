import SwiftUI

struct ProjectWindowView: View {
    let project: Project
    @Environment(AppState.self) private var appState
    @State private var selectedFile: FileEntry?
    @StateObject private var webViewStore = WebViewStore()
    @State private var copyFeedback = false
    @State private var showQuickOpen = false
    @State private var projectFiles: [FileEntry] = []
    @State private var isScanning = false

    var body: some View {
        WebView(store: webViewStore)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if selectedFile == nil {
                    Text("Press ⌘K to open a file")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                }
            }
            .overlay {
                if showQuickOpen {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showQuickOpen = false }

                    VStack {
                        QuickOpenView(
                            files: projectFiles,
                            isScanning: isScanning,
                            onSelect: { file in
                                selectedFile = file
                                showQuickOpen = false
                            },
                            onDismiss: { showQuickOpen = false }
                        )
                        .padding(.top, 60)
                        Spacer()
                    }
                }
            }
            .onChange(of: selectedFile) {
                if let file = selectedFile {
                    webViewStore.load(file: file, project: project)
                }
            }
            .navigationTitle(selectedFile?.name ?? project.name)
            .onReceive(NotificationCenter.default.publisher(for: .toggleQuickOpen)) { _ in
                showQuickOpen.toggle()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if selectedFile != nil {
                        Button {
                            webViewStore.copyMarkdown()
                            copyFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copyFeedback = false
                            }
                        } label: {
                            Label(copyFeedback ? "Copied!" : "Copy Markdown", systemImage: "doc.on.doc")
                        }
                        .help("Copy raw markdown to clipboard")

                        Button {
                            webViewStore.printDocument()
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                        .help("Print or save as PDF")
                    }
                }
            }
            .task { scanFiles() }
    }

    private func scanFiles() {
        isScanning = true
        FileScanner.scanBatched(directory: project.path, filter: .allFiles, batchSize: 50) { batch, done in
            DispatchQueue.main.async {
                projectFiles.append(contentsOf: batch)
                if done { isScanning = false }
            }
        }
    }
}
