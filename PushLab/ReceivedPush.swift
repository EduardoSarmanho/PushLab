import Foundation
import UserNotifications

/// One push notification the app knows it received, for the on-screen list.
struct ReceivedPush: Identifiable {

    /// The three flavors the app demonstrates, sent from OneSignal's
    /// composer. The kind is derived from the payload — compare with what
    /// you configured in the dashboard.
    enum Kind: String, CaseIterable {
        /// Plain alert: just `aps.alert` (+ sound + badge).
        case basic = "Basic"
        /// The composer's "Image" field: OneSignal sets `mutable-content: 1`
        /// and puts the URL in its payload; the Notification Service
        /// Extension (via OneSignalExtension) downloads and attaches it.
        case image = "Image"
        /// The composer's "Action Buttons": OneSignal registers a category
        /// dynamically at delivery time — the app doesn't pre-register
        /// anything.
        case actions = "Actions"
    }

    /// Mirrors `UNNotificationRequest.identifier`, so a later tap can be
    /// matched to a banner we already listed.
    let id: String
    let receivedAt: Date
    let title: String
    let body: String
    let kind: Kind
    /// `true` when the push arrived while the app was open on screen —
    /// those are the only deliveries iOS tells the app about immediately.
    let deliveredInForeground: Bool
    /// How the user interacted with it ("Button: accept", "Tapped — opened the app", …).
    var interaction: String?

    init(request: UNNotificationRequest, deliveredInForeground: Bool, interaction: String? = nil) {
        let content = request.content
        self.id = request.identifier
        self.receivedAt = Date()
        self.title = content.title
        self.body = content.body
        self.kind = Self.kind(of: content)
        self.deliveredInForeground = deliveredInForeground
        self.interaction = interaction
    }

    private static func kind(of content: UNNotificationContent) -> Kind {
        // Buttons ⇒ OneSignal attached a (dynamically registered) category.
        if !content.categoryIdentifier.isEmpty {
            return .actions
        }
        // Image ⇒ the service extension attached it before display…
        if !content.attachments.isEmpty {
            return .image
        }
        // …or, as a fallback, the OneSignal payload carries an "att"
        // (attachment) entry inside its "custom" envelope.
        if let custom = content.userInfo["custom"] as? [String: Any], custom["att"] != nil {
            return .image
        }
        return .basic
    }
}
