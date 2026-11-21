/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import ApplicationServices
import Foundation
import UserNotifications

/// Asks macOS for the runtime permissions the app needs, one pass from the menu.
///
/// Each kind is guarded by its own preflight check, so running this on an
/// install that already has a grant simply moves on to the next one instead of
/// nudging the user again.
///
/// Notably absent: Automation (Apple Events). Nothing in the app drives another
/// application any more, so there is no sixth permission to request — which is
/// the point, since that was the one macOS kept asking about.
enum PermissionsRequester {
    private enum Pane: String {
        case accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case screenRecording = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case notifications = "x-apple.systempreferences:com.apple.preference.notifications"
    }

    @MainActor
    static func accessibilityGranted() -> Bool {
        if AppRuntimeEnvironment.isUITesting { return true }
        return AXIsProcessTrusted()
    }

    static func screenRecordingGranted() -> Bool {
        if AppRuntimeEnvironment.isUITesting { return true }
        return CGPreflightScreenCaptureAccess()
    }

    /// Requests everything that is still missing.
    ///
    /// Accessibility and Screen Recording can only ever be *added* by the user
    /// in System Settings: the in-app call raises the system's own prompt, and
    /// macOS shows that prompt once per app — afterwards the same call quietly
    /// returns false. So the matching pane is opened as well, which is the only
    /// way the request stays actionable on a second press.
    @MainActor
    static func grantAll() {
        let needsAccessibility = !accessibilityGranted()
        let needsScreenRecording = !screenRecordingGranted()

        if needsAccessibility {
            AccessibilityPermissionStore.shared.requestAuthorizationPrompt()
        }
        if needsScreenRecording {
            _ = CGRequestScreenCaptureAccess()
        }

        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            var needsNotificationPane = false

            switch status {
            case .notDetermined:
                _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            case .denied:
                needsNotificationPane = true
            default:
                break
            }

            // System Settings shows one pane at a time, so pick the single most
            // useful one rather than opening several and letting them fight.
            if needsNotificationPane {
                open(.notifications)
            } else if needsScreenRecording {
                open(.screenRecording)
            } else if needsAccessibility {
                open(.accessibility)
            }

            AccessibilityPermissionStore.shared.refreshStatus()
        }
    }

    private static func open(_ pane: Pane) {
        guard let url = URL(string: pane.rawValue) else { return }
        NSWorkspace.shared.open(url)
    }
}
