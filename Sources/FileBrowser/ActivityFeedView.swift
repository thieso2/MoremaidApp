import SwiftUI

struct ActivityFeedView: View {
    let activityStore: ActivityFeedStore
    @Binding var isPresented: Bool
    let onSelectFile: (FileEntry) -> Void
    let onOpenInNewTab: (FileEntry) -> Void

    @AppStorage("activityPanelWidth") private var panelWidth = Constants.activityPanelDefaultWidth

    var body: some View {
        HStack(spacing: 0) {
            panelDragHandle
            VStack(spacing: 0) {
                header
                summaryBar
                Divider()
                eventsList
                Divider()
                bottomBar
            }
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity)
            .background(.windowBackground)
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
                        panelWidth = min(Constants.activityPanelMaxWidth, max(Constants.activityPanelMinWidth, newWidth))
                    }
            )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .foregroundStyle(.secondary)
            Text("Activity")
                .font(.headline)
            Spacer()
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

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 8) {
            let events = activityStore.filteredEvents
            let newCount = events.filter { $0.changeType == .created }.count
            let updatedCount = events.filter { $0.changeType == .modified }.count
            Text(summaryText(new: newCount, updated: updatedCount))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if activityStore.unseenCount > 0 {
                Button("Mark All Read") {
                    activityStore.markAllSeen()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func summaryText(new: Int, updated: Int) -> String {
        var parts: [String] = []
        if new > 0 { parts.append("\(new) new") }
        if updated > 0 { parts.append("\(updated) updated") }
        if parts.isEmpty { return "No activity" }
        return parts.joined(separator: ", ")
    }

    // MARK: - Events List

    private var eventsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(activityStore.filteredEvents) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: ActivityEvent) -> some View {
        Button {
            activityStore.markSeen(id: event.id)
            onSelectFile(event.fileEntry)
        } label: {
            HStack(spacing: 8) {
                // Unseen indicator
                Circle()
                    .fill(event.isSeen ? Color.clear : Color.blue)
                    .frame(width: 6, height: 6)

                // Change type badge
                changeBadge(event.changeType)

                // File info
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.fileEntry.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if !event.fileEntry.directory.isEmpty {
                            Text(event.fileEntry.directory)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Text("\u{2022}")
                                .font(.caption2)
                                .foregroundStyle(.quaternary)
                        }
                        Text(formatTimeAgo(event.detectedAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if event.updateCount > 1 {
                            Text("\u{00D7}\(event.updateCount)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open in New Tab") {
                activityStore.markSeen(id: event.id)
                onOpenInNewTab(event.fileEntry)
            }
            Button("Mark as Read") {
                activityStore.markSeen(id: event.id)
            }
            Button("Dismiss") {
                activityStore.dismiss(id: event.id)
            }
        }
    }

    private func changeBadge(_ type: ActivityEvent.ChangeType) -> some View {
        Text(type == .created ? "NEW" : "UPD")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(type == .created ? Color.green : Color.blue)
            )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Toggle("Markdown Only", isOn: Binding(
                get: { activityStore.markdownOnly },
                set: { activityStore.markdownOnly = $0 }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            Spacer()
            if !activityStore.events.isEmpty {
                Button("Clear") {
                    activityStore.clear()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
