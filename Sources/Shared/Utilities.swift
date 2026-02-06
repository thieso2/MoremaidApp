import Foundation

// MARK: - File Size Formatting

func formatSize(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return "\(String(format: "%.1f", Double(bytes) / 1024)) KB" }
    if bytes < 1024 * 1024 * 1024 { return "\(String(format: "%.1f", Double(bytes) / (1024 * 1024))) MB" }
    return "\(String(format: "%.1f", Double(bytes) / (1024 * 1024 * 1024))) GB"
}

// MARK: - Time Ago Formatting

func formatTimeAgo(_ date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))

    if seconds < 60 { return "just now" }
    let minutes = seconds / 60
    if minutes < 60 { return minutes == 1 ? "1 min ago" : "\(minutes) mins ago" }
    let hours = minutes / 60
    if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
    let days = hours / 24
    if days < 7 { return days == 1 ? "yesterday" : "\(days) days ago" }
    let weeks = days / 7
    if weeks < 4 { return weeks == 1 ? "last week" : "\(weeks) weeks ago" }
    let months = days / 30
    if months < 12 { return months == 1 ? "last month" : "\(months) months ago" }
    let years = days / 365
    return years == 1 ? "last year" : "\(years) years ago"
}

// MARK: - Full Date Formatting

func formatFullDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.dateFormat = "MMM d, yyyy, h:mm a"
    return formatter.string(from: date)
}

// MARK: - Markdown Extension Check

func isMarkdownFile(_ path: String) -> Bool {
    let ext = (path as NSString).pathExtension.lowercased()
    return Constants.markdownExtensions.contains(ext)
}
