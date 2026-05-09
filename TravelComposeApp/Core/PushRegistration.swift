import SwiftUI
import UIKit
import UserNotifications

// MARK: - Push notification registration
//
// Owns the iOS-side of the APNs handshake:
//   1. Ask UNUserNotificationCenter for permission (alert + badge +
//      sound) on first authenticated launch.
//   2. On grant, call `UIApplication.registerForRemoteNotifications`.
//   3. AppDelegate's `didRegisterForRemoteNotificationsWithDeviceToken`
//      hands the hex token back to AppStore via
//      `submitApnsToken(_:)`.
//   4. AppStore POSTs to `/devices`. Backend stores the token; future
//      send-side dispatch fans out from there.
//
// Real APNs delivery requires an APNs key in the backend's env;
// without it, the backend stores the token and never sends. iOS-side
// behavior is the same either way.

final class VoygoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Shared store reference set in `RootView.onAppear` so the APNs
    /// callbacks (which fire on the main thread but aren't statically
    /// MainActor) can hand the token to `AppStore`.
    nonisolated(unsafe) static weak var store: AppStore?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Called by APNs after `registerForRemoteNotifications()`. We
    /// store the token and forward it to the backend via AppStore.
    nonisolated func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            await VoygoAppDelegate.store?.submitApnsToken(hex)
        }
    }

    nonisolated func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Non-fatal — typically simulator (which can't register).
    }

    // Foreground presentation. Show banner + badge + sound for any
    // notification the app sees while open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                  @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // User tapped a notification — extract `routeId` / `rideId` from
    // userInfo and post a deep-link request that RootView handles.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let info = response.notification.request.content.userInfo
        let routeId = info["routeId"] as? String
        let rideId = info["rideId"] as? String
        Task { @MainActor in
            if let routeId, !routeId.isEmpty {
                NotificationCenter.default.post(
                    name: .voygoOpenRoute,
                    object: nil,
                    userInfo: ["routeId": routeId]
                )
            } else if let rideId, !rideId.isEmpty {
                NotificationCenter.default.post(
                    name: .voygoOpenRide,
                    object: nil,
                    userInfo: ["rideId": rideId]
                )
            }
            completionHandler()
        }
    }
}

extension Notification.Name {
    /// Posted from a notification tap with `userInfo: ["routeId": "…"]`.
    /// MainTabView (or HomeTab) listens and pushes `.routeDetails`.
    static let voygoOpenRoute = Notification.Name("voygo.openRoute")
    /// Posted from a notification tap with `userInfo: ["rideId": "…"]`.
    static let voygoOpenRide  = Notification.Name("voygo.openRide")
}

/// Permission flow: request authorization, then register if granted.
/// Called from `RootView` on `currentUser.id` becoming non-empty so we
/// only ask once the user is authenticated and we have someone to
/// associate the token with on the backend.
@MainActor
func requestPushAuthorizationIfNeeded() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .notDetermined:
        let granted = (try? await center.requestAuthorization(
            options: [.alert, .badge, .sound]
        )) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    case .authorized, .provisional, .ephemeral:
        // Already granted — re-register so the token is fresh in
        // case it rotated (Apple sometimes rotates).
        UIApplication.shared.registerForRemoteNotifications()
    case .denied:
        // User said no. Don't pester. Settings → Notifications is
        // the recovery path.
        break
    @unknown default:
        break
    }
}
