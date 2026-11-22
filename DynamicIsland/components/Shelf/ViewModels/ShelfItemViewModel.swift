/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import AppKit
import SwiftUI

@MainActor
final class ShelfItemViewModel: ObservableObject {
    @Published private(set) var item: ShelfItem
    @Published var thumbnail: NSImage?
    @Published var displayName: String = ""
    @Published var icon: NSImage?
    @Published var isDropTargeted: Bool = false

    init(item: ShelfItem) {
        self.item = item
        self.displayName = ""
        self.icon = nil
        Task { await loadMetadata() }
    }

    // Single coordinated load: resolves bookmark once, populates all metadata
    func loadMetadata() async {
        guard case .file(let bookmarkData) = item.kind else { return }
        let bookmark = Bookmark(data: bookmarkData)
        let (url, _) = await bookmark.resolveAsync()
        guard let resolvedURL = url else { return }

        // Self-healing: refresh the cached path in case the file moved since it
        // was dropped. No-op when unchanged, so it won't churn persistence.
        let itemID = item.id
        let resolvedPath = resolvedURL.standardizedFileURL.path
        await MainActor.run {
            ShelfStateViewModel.shared.applyCachedPath(resolvedPath, for: itemID, resolvedFrom: bookmarkData)
        }

        // Load display name
        let name = await loadDisplayNameFromURL(resolvedURL)
        await MainActor.run { self.displayName = name }
        
        // Load icon
        let image = await loadIconFromURL(resolvedURL)
        await MainActor.run { self.icon = image }
        
        // Load thumbnail
        if let thumbnailImage = await ThumbnailService.shared.thumbnail(for: resolvedURL, size: CGSize(width: 56, height: 56)) {
            await MainActor.run { self.thumbnail = thumbnailImage }
        }
    }

    func loadDisplayName() async {
        guard case .file(let bookmarkData) = item.kind else { return }
        let bookmark = Bookmark(data: bookmarkData)
        let (url, _) = await bookmark.resolveAsync()
        guard let resolvedURL = url else { return }
        let name = await loadDisplayNameFromURL(resolvedURL)
        await MainActor.run { self.displayName = name }
    }

    private func loadDisplayNameFromURL(_ url: URL) async -> String {
        if url.pathExtension.lowercased() == "json" && url.path.contains("TextBlocks") {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                struct TextBlockData: Codable {
                    let content: String
                    let title: String?
                    var displayTitle: String {
                        if let title = title, !title.isEmpty { return title }
                        let firstLine = content.components(separatedBy: .newlines).first ?? content
                        if firstLine.count > 50 { return String(firstLine.prefix(47)) + "..." }
                        return firstLine
                    }
                }
                if let textData = try? decoder.decode(TextBlockData.self, from: data) {
                    return textData.displayTitle
                }
            } catch { /* fall through */ }
        } else if url.pathExtension.lowercased() == "webloc" && url.path.contains("WebLocs") {
            do {
                let data = try Data(contentsOf: url)
                if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let urlString = plist["URL"] as? String {
                    let title = plist["Title"] as? String
                    return title ?? urlString
                }
            } catch { /* fall through */ }
        }
        return (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }

    func loadIcon() async {
        guard case .file(let bookmarkData) = item.kind else { return }
        let bookmark = Bookmark(data: bookmarkData)
        let (url, _) = await bookmark.resolveAsync()
        guard let resolvedURL = url else { return }
        let image = await loadIconFromURL(resolvedURL)
        await MainActor.run { self.icon = image }
    }

    private func loadIconFromURL(_ url: URL) async -> NSImage {
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // Async version to resolve file URL without blocking main thread
    func resolveFileURL() async -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let (url, _) = await bookmark.resolveAsync()
        return url
    }

    // MARK: - Actions
    func handleClick(event: NSEvent) {
        if event.clickCount == 2 { handleDoubleClick() }
    }

    func handleDoubleClick() {
        ShelfActionService.open(item)
    }
}
