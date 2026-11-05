import SwiftUI
import TrueCloudKit

/// The account's payment history, loaded from TrueCloud. Kept in HomeView so the list survives switching panes.
@MainActor
final class PaymentsModel: ObservableObject {
    @Published private(set) var records: [PaymentRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoaded = false

    func load(auth: AuthStore) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            records = try await auth.payments()
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    /// Sample data for screenshots, without network.
    func preview(_ records: [PaymentRecord]) {
        self.records = records
        hasLoaded = true
    }
    #endif
}

struct PaymentsPane: View {
    @ObservedObject var model: PaymentsModel
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.openURL) private var openURL

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
                } else if model.records.isEmpty {
                    empty.reveal(0.06)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.records.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { Divider().padding(.horizontal, 14) }
                            row(record)
                        }
                    }
                    .padding(.vertical, 4)
                    .glassSurface(cornerRadius: 16)
                    .reveal(0.06)
                }

                footer
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Payments")
        .task { if !model.hasLoaded { await model.load(auth: auth) } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Payments").font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                if model.hasLoaded && !model.records.isEmpty {
                    Text("\(model.records.count) \(model.records.count == 1 ? "payment" : "payments")")
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
            Text("Your plan purchases and upgrades, as TrueCloud recorded them.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Rows

    private func row(_ record: PaymentRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(record.createdAt.map { Self.dateFormatter.string(from: $0) } ?? "Unknown date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(record.planName.isEmpty ? "Plan" : record.planName).font(.callout.weight(.semibold))
                    chip(record.typeText, color: .gray)
                    statusChip(record.status)
                }
                if record.status == .failure, let reason = record.failureReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(record.amountText)
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color == .gray ? Color.secondary : color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .glassCapsule(tint: color.opacity(0.15))
    }

    @ViewBuilder
    private func statusChip(_ status: PaymentRecord.Status) -> some View {
        switch status {
        case .success: chip("Success", color: .green)
        case .failure: chip("Failed", color: .red)
        case .pending: chip("Pending", color: .orange)
        case .other(let text): chip(text.capitalized, color: .gray)
        }
    }

    // MARK: States

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "creditcard")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No payments yet").font(.headline)
            Text("Plan purchases and upgrades show up here.")
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
            Text("Couldn't load payments").font(.headline)
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

    private var footer: some View {
        HStack(spacing: 4) {
            Text("Plans and billing are managed on truecloud.in.")
                .foregroundStyle(.secondary)
            Button("Open Plans") { openURL(Config.dashboardURL.appendingPathComponent("plans")) }
                .textLinkStyle()
        }
        .font(.callout)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()
}
