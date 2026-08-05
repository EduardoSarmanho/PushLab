import UserNotifications
import OneSignalExtension

// ─────────────────────────────────────────────────────────────────────────
// STEP 6 · Rich images
// A separate target: File → New → Target → Notification Service Extension,
// plus the "OneSignalExtension" SDK product added to it. Without this
// extension, image pushes still arrive — just without the image.
// ─────────────────────────────────────────────────────────────────────────

/// A Notification Service Extension gets the chance to MODIFY a push before
/// iOS displays it — but only when the payload contains `"mutable-content": 1`.
///
/// How it works: iOS launches this extension in its own tiny, short-lived
/// process, calls `didReceive`, and gives it roughly 30 seconds. Whatever
/// content is passed to `contentHandler` is what gets displayed.
///
/// The OneSignal extension helper does the heavy lifting here: it reads the
/// attachment URL from OneSignal's payload, downloads it, attaches it, and
/// calls the content handler. It also powers OneSignal's Confirmed
/// Deliveries analytics on plans that include it.
final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var receivedRequest: UNNotificationRequest?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.receivedRequest = request
        self.contentHandler = contentHandler
        self.bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }
        // Hand everything to OneSignal — it downloads/attaches media and
        // then calls our contentHandler with the final content.
        OneSignalExtension.didReceiveNotificationExtensionRequest(
            request,
            with: bestAttemptContent,
            withContentHandler: contentHandler
        )
    }

    override func serviceExtensionTimeWillExpire() {
        // The system is about to cut us off (slow network?). Let OneSignal
        // deliver the best content it has so far instead of losing the push.
        if let receivedRequest, let bestAttemptContent, let contentHandler {
            OneSignalExtension.serviceExtensionTimeWillExpireRequest(receivedRequest, with: bestAttemptContent)
            contentHandler(bestAttemptContent)
        }
    }
}
