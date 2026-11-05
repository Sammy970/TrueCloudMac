import AppKit
import SwiftUI

/// One row of the Logs pane: a log line, or a run of identical lines collapsed together.
struct LogEntry: Identifiable, Equatable {
    let id: Int
    let first: Date
    var last: Date
    let category: String     // "session", "auth", "pair", … (from "[session] …"), or "app"
    let message: String
    var count: Int

    var isProblem: Bool {
        let m = message.lowercased()
        return ["fail", "error", "couldn't", "refus", "not accepted", "blocked", "expired", "congested", "timed out"]
            .contains { m.contains($0) }
    }

    private static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Parses "2026-11-05 22:55:47.978 [session] status failed: …" lines, oldest first, and collapses
    /// consecutive repeats of the same message (status polls write the same line every few seconds).
    static func parse(_ lines: [String]) -> [LogEntry] {
        var result: [LogEntry] = []
        for line in lines {
            guard line.count > 24, let date = stampFormat.date(from: String(line.prefix(23))) else {
                // A wrapped continuation or a malformed line: attach to the previous entry's text is overkill; show as-is.
                result.append(LogEntry(id: result.count, first: .distantPast, last: .distantPast, category: "app",
                                       message: line, count: 1))
                continue
            }
            var rest = line.dropFirst(24)
            var category = "app"
            if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                category = String(rest[rest.index(after: rest.startIndex)..<close])
                rest = rest[rest.index(after: close)...].drop(while: { $0 == " " })
            }
            let message = String(rest)
            if let lastIndex = result.indices.last,
               result[lastIndex].category == category, result[lastIndex].message == message {
                result[lastIndex].count += 1
                result[lastIndex].last = date
            } else {
                result.append(LogEntry(id: result.count, first: date, last: date, category: category,
                                       message: message, count: 1))
            }
        }
        return result
    }

    /// The line as it is in the file (with a repeat count), for copying.
    var plainText: String {
        let stamp = first == .distantPast ? "" : Self.stampFormat.string(from: last) + " "
        let repeats = count > 1 ? " (×\(count) since \(Self.stampFormat.string(from: first)))" : ""
        return "\(stamp)[\(category)] \(message)\(repeats)"
    }
}

/// What the app has been doing, from its log file (~/Library/Logs/TrueCloud/truecloud.log): every start,
/// stop, pairing step and the exact error TrueCloud sent back. Newest first, repeats collapsed.
struct LogsPane: View {
    @State private var entries: [LogEntry] = []
    @State private var search = ""
    @State private var category = "All"
    @State private var problemsOnly = false
    @State private var selection = Set<LogEntry.ID>()
    @State private var copied = false
    @State private var confirmClear = false

    private var categories: [String] {
        ["All"] + Set(entries.map(\.category)).sorted()
    }

    private var shown: [LogEntry] {
        entries.reversed().filter { e in
            (category == "All" || e.category == category) &&
            (!problemsOnly || e.isProblem) &&
            (search.isEmpty || e.message.localizedCaseInsensitiveContains(search) ||
             e.category.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        content
            .navigationTitle("Logs")
            .navigationSubtitle(subtitle)
            .searchable(text: $search, placement: .toolbar, prompt: "Search logs")
            .toolbar { toolbar }
            .task {
                // Live while the pane is open.
                while !Task.isCancelled {
                    let fresh = LogEntry.parse(Log.recentLines(3000))
                    if fresh != entries { entries = fresh }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            .confirmationDialog("Clear the log?", isPresented: $confirmClear) {
                Button("Clear", role: .destructive) {
                    Log.clear()
                    entries = []
                    selection = []
                }
            } message: {
                Text("This empties truecloud.log. It can't be undone.")
            }
    }

    private var subtitle: String {
        let total = entries.reduce(0) { $0 + $1.count }
        return shown.count == entries.count ? "\(total) lines" : "\(shown.count) of \(entries.count) shown"
    }

    @ViewBuilder
    private var content: some View {
        if shown.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text(entries.isEmpty ? "Nothing logged yet" : "No matches")
                    .font(.title3.weight(.semibold))
                Text(entries.isEmpty
                     ? "Starts, stops, pairing and errors show up here as they happen."
                     : "Try another search, category, or turn off Problems only.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(shown, selection: $selection) { entry in
                LogRow(entry: entry)
                    .contextMenu {
                        Button("Copy") { copy(selection.contains(entry.id) ? selected : [entry]) }
                    }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onCopyCommand { [NSItemProvider(object: selected.map(\.plainText).joined(separator: "\n") as NSString)] }
        }
    }

    private var selected: [LogEntry] { shown.filter { selection.contains($0.id) } }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Category", selection: $category) {
                ForEach(categories, id: \.self) { Text($0 == "All" ? "All categories" : $0.capitalized).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Show one part of the app")

            Toggle(isOn: $problemsOnly) {
                Label("Problems only", systemImage: "exclamationmark.triangle")
            }
            .help("Show only failures and errors")

            Button {
                copy(selected.isEmpty ? shown : selected)
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .help(selected.isEmpty ? "Copy everything shown" : "Copy the selected rows")

            Menu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL]) }
                Button("Open in Console") { NSWorkspace.shared.open(Log.fileURL) }
                Divider()
                Button("Clear Log…", role: .destructive) { confirmClear = true }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private func copy(_ rows: [LogEntry]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rows.map(\.plainText).joined(separator: "\n"), forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.isProblem ? "exclamationmark.triangle.fill" : "circle.fill")
                .font(entry.isProblem ? .caption : .system(size: 5))
                .foregroundStyle(entry.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                .frame(width: 14)

            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.first == .distantPast ? "" : Self.time.string(from: entry.last))
                    .font(.system(.callout, design: .monospaced))
                if entry.first != .distantPast && !Calendar.current.isDateInToday(entry.last) {
                    Text(Self.day.string(from: entry.last)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, alignment: .trailing)

            Text(entry.category)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .frame(width: 90, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.count > 1 {
                    Text("Repeated \(entry.count)× since \(Self.time.string(from: entry.first))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}
