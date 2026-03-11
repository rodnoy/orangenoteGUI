//
//  UpdateStatus.swift
//  OrangeNote
//
//  Result of checking for updates.
//

import Foundation

/// Result of checking for updates.
enum UpdateStatus: Equatable {
    case upToDate(currentVersion: String)
    case updateAvailable(currentVersion: String, latestVersion: String, releaseURL: URL, releaseNotes: String, releaseName: String)
    case error(message: String)
    case checking
    case idle

    static func == (lhs: UpdateStatus, rhs: UpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking):
            return true
        case (.upToDate(let a), .upToDate(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        case (.updateAvailable(let c1, let l1, let u1, _, _), .updateAvailable(let c2, let l2, let u2, _, _)):
            return c1 == c2 && l1 == l2 && u1 == u2
        default:
            return false
        }
    }
}
