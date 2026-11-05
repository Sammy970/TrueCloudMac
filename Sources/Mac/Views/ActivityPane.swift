import SwiftUI
import TrueCloudKit

/// The cloud PC's power events (starts, shutdowns, force stops), loaded from TrueCloud's activity log.
/// Kept in HomeView so the list survives switching panes.
@MainActor
final class ActivityModel: ObservableObject {
    @Published private(set) var entries: [ActivityEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoaded = false

    func load(auth: AuthStore) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            entries = Array(try await auth.activityLog().prefix(200))
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    /// Sample data for screenshots, without network.
    func preview(_ entries: [ActivityEntry]) {
        self.entries = entries
        hasLoaded = true
    }
    #endif
}

struct ActivityPane: View {
    @ObservedObject var model: ActivityModel
    @EnvironmentObject private var auth: AuthStore

    /// Entries grouped by calendar day, newest day first.
    private var days: [(day: Date, entries: [ActivityEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: model.entries) { calendar.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day, default: []].sorted { $0.timestamp > $1.timestamp })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header.reveal(0)

                if let message = model.errorMessage {
                    errorCard(message).reveal(0.06)
                } else if !model.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if model.entries.isEmpty {
                    empty.reveal(0.06)
                } else {
                    ForEach(days, id: \.day) { group in
                        daySection(group.day, group.entries)
                    }
                    .reveal(0.06)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Activity")
        .task { if !model.hasLoaded { await model.load(auth: auth) } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                if model.hasLoaded && !model.entries.isEmpty {
                    Text("\(model.entries.count) \(model.entries.count == 1 ? "event" : "events")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await model.load(auth: auth) }
                } label: {
                    HStack(spacing: 6) {
                        if model.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh")
                    }
                }
                .secondaryGlassButton()
                .disabled(model.isLoading)
            }
            Text("Starts, shutdowns and force stops of your cloud PC, as TrueCloud recorded them.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: List

    private func daySection(_ day: Date, _ entries: [ActivityEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.dayTitle(day))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 52) }
                    row(entry)
                }
            }
            .padding(.vertical, 4)
            .glassSurface(cornerRadius: 16)
        }
    }

    private func row(_ entry: ActivityEntry) -> some View {
        let tint = Self.tint(entry)
        return HStack(spacing: 12) {
            Image(systemName: Self.symbol(entry.type))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.callout.weight(.medium))
                Text(entry.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Circle().fill(tint).frame(width: 7, height: 7)
                .help(entry.isSuccess ? "Succeeded" : entry.isFailure ? "Failed" : "Recorded")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: States

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No activity yet").font(.headline)
            Text("Starting or shutting down your cloud PC shows up here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 20)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text("Couldn't load activity").font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { Task { await model.load(auth: auth) } }
                .secondaryGlassButton()
                .disabled(model.isLoading)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 20)
    }

    // MARK: Helpers

    private static func symbol(_ type: String) -> String {
        switch type.lowercased() {
        case "start": return "power"
        case "shutdown", "stop": return "stop.circle"
        default: return "gearshape"
        }
    }

    private static func tint(_ entry: ActivityEntry) -> Color {
        entry.isFailure ? .red : entry.isSuccess ? .green : .gray
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return dayFormatter.string(from: day)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()
}
