//
//  NotificationService.swift
//  OrangeNote
//
//  Handles local notifications via macOS Notification Center.
//

import UserNotifications

/// Provides local notification capabilities for the application.
enum NotificationService {
    // MARK: - Permission

    /// Requests notification authorization from the user.
    ///
    /// Call this once at app launch. Subsequent calls are no-ops if permission
    /// has already been granted or denied.
    static func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            } else {
                print("Notification permission granted: \(granted)")
            }
        }
    }

    // MARK: - Notifications

    /// Posts a local notification indicating that transcription has completed.
    ///
    /// - Parameters:
    ///   - fileName: The name of the transcribed audio file.
    ///   - segmentCount: The number of segments produced by the transcription.
    ///   - duration: The audio duration in seconds.
    static func sendTranscriptionComplete(
        fileName: String,
        segmentCount: Int,
        duration: TimeInterval
    ) {
        let content = UNMutableNotificationContent()
        content.title = L10n.localizedString("notification.transcriptionComplete.title")
        let pluralSuffix = segmentCount == 1
            ? ""
            : L10n.localizedString("notification.transcriptionComplete.pluralSuffix")
        let bodyFormat = L10n.localizedString("notification.transcriptionComplete.body")
        content.body = String(
            format: bodyFormat,
            fileName,
            segmentCount,
            pluralSuffix,
            formattedDuration(duration)
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "transcription-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    /// Posts a local notification indicating that translation has completed.
    ///
    /// - Parameters:
    ///   - targetLanguage: The language code the text was translated to.
    ///   - segmentCount: The number of segments that were translated.
    static func sendTranslationComplete(
        targetLanguage: String,
        segmentCount: Int
    ) {
        let content = UNMutableNotificationContent()
        content.title = L10n.localizedString("notification.translationComplete.title")
        content.body = String(
            format: L10n.localizedString("notification.translationComplete.body"),
            segmentCount,
            L10n.localizedString("lang.\(targetLanguage)")
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "translation-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private Helpers

    /// Formats a duration in seconds into a human-readable string (e.g. "5m 23s").
    private static func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        let h = L10n.localizedString("time.hours.short")
        let m = L10n.localizedString("time.minutes.short")
        let s = L10n.localizedString("time.seconds.short")

        if hours > 0 {
            return "\(hours)\(h) \(minutes)\(m) \(secs)\(s)"
        } else if minutes > 0 {
            return "\(minutes)\(m) \(secs)\(s)"
        }
        return "\(secs)\(s)"
    }
}
