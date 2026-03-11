//
//  GitHubRelease.swift
//  OrangeNote
//
//  Represents a GitHub release from the API response.
//

import Foundation

/// Represents a GitHub release from the API response.
struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let htmlUrl: URL
    let publishedAt: Date
    let prerelease: Bool
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
    }

    /// Extracts semantic version from tag_name (removes 'v' prefix if present).
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}
