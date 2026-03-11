//
//  UpdateCheckerService.swift
//  OrangeNote
//
//  Service responsible for checking GitHub releases and comparing versions.
//

import Foundation

/// Service responsible for checking GitHub releases and comparing versions.
actor UpdateCheckerService {
    // MARK: - Constants

    private static let releasesURL = URL(string: "https://api.github.com/repos/rodnoy/orangenoteGUI/releases/latest")!

    // MARK: - Public API

    /// Fetches the latest release from GitHub and compares with current version.
    func checkForUpdates() async throws -> UpdateStatus {
        let currentVersion = Self.currentAppVersion
        let release = try await fetchLatestRelease()

        // Skip prereleases and drafts
        guard !release.prerelease && !release.draft else {
            return .upToDate(currentVersion: currentVersion)
        }

        if isNewerVersion(release.version, than: currentVersion) {
            return .updateAvailable(
                currentVersion: currentVersion,
                latestVersion: release.version,
                releaseURL: release.htmlUrl,
                releaseNotes: release.body,
                releaseName: release.name
            )
        } else {
            return .upToDate(currentVersion: currentVersion)
        }
    }

    // MARK: - Private Methods

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OrangeNote-macOS", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(GitHubRelease.self, from: data)
        case 404:
            throw UpdateError.noReleasesFound
        case 403:
            throw UpdateError.rateLimited
        default:
            throw UpdateError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    /// Compares two semantic version strings.
    /// Returns true if `version` is newer than `currentVersion`.
    private func isNewerVersion(_ version: String, than currentVersion: String) -> Bool {
        let v1Components = version.split(separator: ".").compactMap { Int($0) }
        let v2Components = currentVersion.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(v1Components.count, v2Components.count)

        for i in 0..<maxLength {
            let v1Part = i < v1Components.count ? v1Components[i] : 0
            let v2Part = i < v2Components.count ? v2Components[i] : 0

            if v1Part > v2Part { return true }
            if v1Part < v2Part { return false }
        }

        return false
    }

    /// Retrieves the current app version from Info.plist.
    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidResponse
    case noReleasesFound
    case rateLimited
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .noReleasesFound:
            return "No releases found"
        case .rateLimited:
            return "GitHub API rate limit exceeded. Please try again later."
        case .httpError(let code):
            return "Server error (HTTP \(code))"
        }
    }
}
