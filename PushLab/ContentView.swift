import SwiftUI
import UserNotifications


struct ContentView: View {
    private var manager = NotificationManager.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                statusSection
                receivedSection
            }
            .navigationTitle("PushLab OS 🔔")
            .toolbar {
                Button("Clear list", systemImage: "trash") {
                    manager.clearReceivedPushes()
                }
                .disabled(manager.receivedPushes.isEmpty)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the foreground: reset the app icon's badge, and
            // re-check permission (the user may have changed it in Settings).
            if phase == .active {
                Task {
                    await manager.refreshAuthorizationStatus()
                    manager.refreshSubscriptionInfo()
                    try? await UNUserNotificationCenter.current().setBadgeCount(0)
                }
            }
        }
    }

    // MARK: - Status

    /// The whole setup story fits in one card, because the OneSignal SDK does
    /// the token/registration work: ask permission once, then you're live.
    @ViewBuilder
    private var statusSection: some View {
        Section {
            switch manager.authorizationStatus {
            case .notDetermined:
                Button {
                    Task { await manager.requestAuthorization() }
                } label: {
                    Label("Enable push notifications", systemImage: "bell.badge")
                }
            case .denied:
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("Notifications denied — open Settings", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            default:
                if manager.optedIn {
                    Label("Subscribed — ready for pushes", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Registering with OneSignal…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text("The OneSignal SDK requests the APNs token and registers this device by itself — there is nothing else to set up.")
        }
    }

    // MARK: - Received pushes

    private var receivedSection: some View {
        Section {
            if manager.receivedPushes.isEmpty {
                ContentUnavailableView(
                    "No pushes yet",
                    systemImage: "bell.badge",
                    description: Text("Send one from the OneSignal dashboard (Messages → New Message → Push) and it will appear here.")
                )
            } else {
                ForEach(manager.receivedPushes) { push in
                    ReceivedPushRow(push: push)
                }
            }
        } header: {
            Text("Received pushes (\(manager.receivedPushes.count))")
        } footer: {
            Text("Only pushes that arrived in the foreground — or were tapped — are listed. A background push nobody taps is never reported to the app!")
        }
    }
}

/// One row in the list, designed so the audience can SEE the differences:
/// a colored badge for the push kind, where it was delivered, and what the
/// user did with it.
struct ReceivedPushRow: View {
    let push: ReceivedPush

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(push.kind.rawValue.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(kindColor.opacity(0.2), in: .capsule)
                    .foregroundStyle(kindColor)
                Spacer()
                Text(push.receivedAt, format: .dateTime.hour().minute().second())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(push.title).font(.headline)
            Text(push.body).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(
                    push.deliveredInForeground ? "Arrived in foreground" : "Tapped from banner",
                    systemImage: push.deliveredInForeground ? "iphone" : "hand.tap"
                )
                if let interaction = push.interaction {
                    Label(interaction, systemImage: "arrow.turn.down.right")
                        .fontWeight(.semibold)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var kindColor: Color {
        switch push.kind {
        case .basic: .blue
        case .image: .purple
        case .actions: .orange
        }
    }
}

#Preview {
    ContentView()
}
