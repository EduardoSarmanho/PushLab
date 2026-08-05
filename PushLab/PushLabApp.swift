import SwiftUI

@main
struct PushLabApp: App {
    /// Remote-notification callbacks — most importantly the device token —
    /// still arrive through `UIApplicationDelegate`, so we bridge one into
    /// the SwiftUI life cycle. See `AppDelegate.swift`.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
