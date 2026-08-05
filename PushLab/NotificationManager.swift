import UIKit
import UserNotifications
import Observation
import OneSignalFramework

/// The heart of the app: everything push-notification-related lives here.
///
/// The classic remote-push flow has three steps — and the OneSignal SDK
/// performs steps 2 and 3 entirely on its own:
///   1. Ask the *user* for permission        → `OneSignal.Notifications.requestPermission`
///   2. Ask *Apple* for a device token       → the SDK calls `registerForRemoteNotifications()`
///   3. Tell *the provider* about that token → the SDK uploads it to OneSignal
///
/// `@Observable` lets SwiftUI views re-render automatically whenever the
/// published state below changes.
@MainActor
@Observable
final class NotificationManager: NSObject {

    /// Shared instance, because the SwiftUI views, the AppDelegate callbacks
    /// and OneSignal's observers all need to talk to the same object.
    static let shared = NotificationManager()

    // MARK: - State the UI observes

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// This device's push address, hex-encoded — still visible for teaching,
    /// even though OneSignal handles it. Arrives via the AppDelegate.
    private(set) var deviceToken: String?
    private(set) var registrationError: String?
    /// OneSignal's own ID for this installation. THIS is what you target
    /// when sending a test push from the dashboard or the REST API.
    private(set) var subscriptionID: String?
    /// Whether OneSignal considers this device reachable (permission granted
    /// AND token uploaded).
    private(set) var optedIn = false
    /// Newest first. Only contains pushes the app was told about — see
    /// `userNotificationCenter(_:didReceive:)` for why that's not all of them!
    private(set) var receivedPushes: [ReceivedPush] = []

    func configureOnLaunch() {
        // Become the notification-center delegate so we hear about foreground
        // deliveries and taps. OneSignal swizzles this and forwards to us —
        // both the SDK and this app see every callback.
        //
        // Note: the app never calls setNotificationCategories. Action
        // buttons come from OneSignal — the SDK registers a category
        // dynamically for each notification that carries buttons.
        UNUserNotificationCenter.current().delegate = self

        // Live updates whenever OneSignal creates/changes this device's
        // subscription (e.g. right after permission is granted).
        OneSignal.User.pushSubscription.addObserver(self)

        Task {
            await refreshAuthorizationStatus()
            refreshSubscriptionInfo()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // STEP 3 · Ask the user for permission
    // ─────────────────────────────────────────────────────────────────────
    func requestAuthorization() async {
        _ = await withCheckedContinuation { continuation in
            OneSignal.Notifications.requestPermission({ accepted in
                continuation.resume(returning: accepted)
            }, fallbackToSettings: false)
        }
        await refreshAuthorizationStatus()
        refreshSubscriptionInfo()
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Reads OneSignal's current view of this device. Also called when the
    /// app returns to the foreground, in case the observer missed something.
    func refreshSubscriptionInfo() {
        subscriptionID = OneSignal.User.pushSubscription.id
        optedIn = OneSignal.User.pushSubscription.optedIn
    }

    func deviceTokenReceived(_ tokenData: Data) {
        // Apple hands the token over as raw bytes; hex is the canonical form.
        deviceToken = tokenData.map { String(format: "%02x", $0) }.joined()
        registrationError = nil
    }

    func registrationFailed(_ error: Error) {
        registrationError = error.localizedDescription
    }

    // MARK: - The received-pushes list

    func clearReceivedPushes() {
        receivedPushes.removeAll()
    }

    private func record(_ request: UNNotificationRequest, deliveredInForeground: Bool, interaction: String? = nil) {
        // If this notification is already in the list (it was presented while
        // the app was open, and now the user tapped it or one of its buttons),
        // just attach the interaction to the existing entry.
        if let index = receivedPushes.firstIndex(where: { $0.id == request.identifier }) {
            if let interaction {
                receivedPushes[index].interaction = interaction
            }
            return
        }
        receivedPushes.insert(
            ReceivedPush(request: request, deliveredInForeground: deliveredInForeground, interaction: interaction),
            at: 0
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────
// STEP 5 · Let the app know a notification reached the device
// Two delegate methods carry ALL the receiving logic on iOS — understand
// these and you understand notifications:
//   willPresent → the push arrived while the app was in the FOREGROUND
//   didReceive  → the user TAPPED the banner or one of its buttons
// A background push that is never tapped triggers NEITHER of them.
// ─────────────────────────────────────────────────────────────────────────

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Called when a push arrives while the app is in the FOREGROUND.
    ///
    /// By default iOS shows nothing for foreground apps — it assumes the app
    /// will handle the information itself. Returning presentation options here
    /// opts into the banner/sound/badge anyway, which is perfect for a demo.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        record(notification.request, deliveredInForeground: true)
        return [.banner, .list, .sound, .badge]
    }

    /// Called when the user INTERACTS with a notification: taps the banner,
    /// or taps one of its action buttons.
    ///
    /// ⚠️ Teaching point: this is the ONLY signal the app gets for pushes that
    /// arrived while it was backgrounded or closed. A push the user never taps
    /// is never reported to the app — so the on-screen list can't show it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let interaction: String
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            interaction = "Tapped — opened the app"
        default:
            // For OneSignal action buttons this is the button ID you typed
            // in the dashboard's composer (e.g. "accept" / "decline").
            interaction = "Button: \(response.actionIdentifier)"
        }
        record(response.notification.request, deliveredInForeground: false, interaction: interaction)
    }
}

// ─────────────────────────────────────────────────────────────────────────
// STEP 4 (continued) · OneSignal confirms the device is registered
// The subscription is OneSignal's record of "this token on this device".
// When it flips to opted-in, the device is reachable from the dashboard.
// ─────────────────────────────────────────────────────────────────────────

extension NotificationManager: OSPushSubscriptionObserver {

    /// OneSignal calls this whenever the subscription changes — most notably
    /// a moment after permission is granted, when the subscription ID and
    /// token first appear. It may arrive on a background thread, so we hop
    /// to the main actor with plain Sendable values.
    nonisolated func onPushSubscriptionDidChange(state: OSPushSubscriptionChangedState) {
        let id = state.current.id
        let optedIn = state.current.optedIn
        Task { @MainActor in
            let manager = NotificationManager.shared
            manager.subscriptionID = id
            manager.optedIn = optedIn
        }
    }
}
