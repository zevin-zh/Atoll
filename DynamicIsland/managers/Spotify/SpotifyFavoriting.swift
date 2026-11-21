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

import Foundation

/// Saving the playing track to Spotify's Liked Songs.
///
/// Lives apart from ``SpotifyController`` because the Now Playing source needs
/// it too: that controller fronts whatever app is playing, and when that app is
/// Spotify this is the answer. Keeping it here rather than in `MusicManager` --
/// where it used to live, spelled out inline -- is what lets both reach it.
enum SpotifyFavoriting {
    static let bundleIdentifier = "com.spotify.client"

    /// This goes through the Web API, so it needs the account the user has
    /// already connected in settings. Without that there is nothing to
    /// favourite into, and the control stays hidden.
    @MainActor
    static var isAvailable: Bool { SpotifyLibraryManager.shared.isAuthenticated }

    static func isFavorited(contentIdentifier: String?, contentURL: String?) async -> Bool? {
        guard await isAvailable,
              let trackID = trackID(contentIdentifier: contentIdentifier, contentURL: contentURL)
        else { return nil }
        return await SpotifyLibraryManager.shared.isTrackSaved(trackID: trackID)
    }

    @discardableResult
    static func setFavorited(
        _ favorited: Bool,
        contentIdentifier: String?,
        contentURL: String?
    ) async -> Bool {
        guard await isAvailable,
              let trackID = trackID(contentIdentifier: contentIdentifier, contentURL: contentURL)
        else { return false }
        return await SpotifyLibraryManager.shared.setTrackSaved(favorited, trackID: trackID)
    }

    static func trackID(contentIdentifier: String?, contentURL: String?) -> String? {
        trackID(from: contentIdentifier) ?? trackID(from: contentURL)
    }

    /// Spotify hands out ids as `spotify:track:<id>` or as a share URL with
    /// `/track/<id>` in its path.
    private static func trackID(from rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("spotify:track:") {
            return validTrackID(String(trimmed.dropFirst("spotify:track:".count)))
        }

        if let url = URL(string: trimmed) {
            let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if let index = components.firstIndex(of: "track"), index + 1 < components.count {
                return validTrackID(components[index + 1])
            }
        }

        return nil
    }

    /// Spotify ids are 22 base62 characters. Anything else is a local file or a
    /// podcast episode, neither of which can be saved to Liked Songs.
    private static func validTrackID(_ candidate: String) -> String? {
        guard candidate.count == 22,
              candidate.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        return candidate
    }
}
