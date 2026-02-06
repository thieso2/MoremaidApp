import SwiftUI

struct FileRowView: View {
    let file: FileEntry

    var body: some View {
        HStack {
            Image(systemName: file.isMarkdown ? "doc.richtext" : "doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.relativePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Text(formatSize(file.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatTimeAgo(file.modifiedDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(formatFullDate(file.modifiedDate))
                }
            }
            Spacer()
        }
    }
}
