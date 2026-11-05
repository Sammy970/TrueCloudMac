import SwiftUI

/// Shown at the top of the Cloud PC screen when TrueCloud changed something this app depends on.
/// Nothing is shown while everything matches, or when a check simply couldn't run (offline).
struct SiteHealthBanner: View {
    @ObservedObject var health: SiteHealth
    @Environment(\.openURL) private var openURL
    @State private var expanded = false

    private var changed: [(area: SiteHealth.Area, details: [String])] {
        SiteHealth.Area.allCases.compactMap { area in
            if case .changed(let details) = health.results[area] { return (area, details) }
            return nil
        }
    }

    var body: some View {
        if !changed.isEmpty {
            let blocking = changed.contains { $0.area == .controls || $0.area == .account }
            let tint: Color = blocking ? .red : .orange
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: blocking ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(blocking ? "Update needed" : "Some details can't load")
                            .font(.headline)
                        Text(blocking
                             ? "TrueCloud changed its website. Start, Shut Down and pairing are off so nothing goes wrong. Update the app, or use truecloud.in for now."
                             : "TrueCloud changed how it stores \(changed.map { $0.area.rawValue }.joined(separator: " and ")). Your cloud PC still works.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(changed, id: \.area) { item in
                            ForEach(item.details, id: \.self) { line in
                                Text("\(item.area.rawValue): \(line)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button("Update the App") { openURL(Config.releasesURL) }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                    Button(expanded ? "Hide Details" : "What Changed?") {
                        withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
                    }
                    .buttonStyle(.borderless)
                    Spacer(minLength: 0)
                }
                .controlSize(.small)
            }
            .padding(14)
            .frame(maxWidth: 520, alignment: .leading)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.35)))
        }
    }
}
