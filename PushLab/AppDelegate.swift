import UIKit
import OneSignalFramework

/// The app delegate exists for two reasons:
///  1. OneSignal must be initialized in `didFinishLaunching` (STEP 2).
///  2. Apple delivers the raw device token through these callbacks — and
///     they still fire even though OneSignal handles registration, because
///     the SDK swizzles them and forwards to our implementations. Handy for
///     seeing the real APNs token this device was assigned (STEP 4).
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Verbose logging: open Xcode's console and watch the SDK do the
        // permission → token → register dance by itself.
        OneSignal.Debug.setLogLevel(.LL_VERBOSE)

        // ─────────────────────────────────────────────────────────────────
        // STEP 2 · Initialize the SDK at launch
        // ─────────────────────────────────────────────────────────────────
        OneSignal.initialize(OneSignalConfig.appID, withLaunchOptions: launchOptions)

        // Wire up our own listeners (delegate + observers) — see STEP 2b.
        NotificationManager.shared.configureOnLaunch()
        return true
    }

    // ─────────────────────────────────────────────────────────────────────
    // STEP 4 · Apple returns this device's push address (automatic)
    // The "device token" is where APNs can reach this install.
    // The SDK requested it and already uploaded it to OneSignal.
    // ─────────────────────────────────────────────────────────────────────
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationManager.shared.deviceTokenReceived(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationManager.shared.registrationFailed(error)
    }
}
