import Foundation
import SwiftUI
import Photos
import UIKit

@MainActor
final class ReviewStore: ObservableObject {
    @Published var session: SavedSession?
    @Published var filter: ReviewFilter = .review
    @Published var currentID: String?
    @Published var busy = false
    @Published var previewLoading = false
    @Published var message: String?
    @Published var needsFolderAccess = false
    private var rootURL: URL?
    private var ownsScopedAccess = false
    private var history: [ReviewHistory] = []
    private var saveFailed = false
    var canUndo: Bool { !history.isEmpty }
    var items: [PhotoItem] { session?.items ?? [] }
    var passed: [PhotoItem] { DeletionRules.candidates(in: items) }
    var keptCount: Int { items.filter { $0.decision == .keep }.count }
    var reviewedCount: Int { items.filter { $0.decision != nil }.count }
    var visible: [PhotoItem] {
        items.filter {
            switch filter {
            case .review: return $0.decision == nil
            case .keep: return $0.decision == .keep
            case .pass: return $0.decision == .pass
            }
        }
    }
    var current: PhotoItem? { visible.first { $0.id == currentID } ?? visible.first }

    private var sessionURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Foliow-session.json")
    }

    init() {
        do {
            let url = sessionURL
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            session = try JSONDecoder().decode(SavedSession.self, from: data)
            if session?.origin == .files, let bookmark = session?.folderBookmark {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                ownsScopedAccess = url.startAccessingSecurityScopedResource()
                rootURL = url
                if !ownsScopedAccess || stale { needsFolderAccess = true }
            }
            currentID = visible.first?.id
        } catch { needsFolderAccess = session?.origin == .files; message = "Could not restore this session. Select the same folder or album to continue. \(error.localizedDescription)" }
    }

    func persist() {
        guard let session else { return }
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: sessionURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            saveFailed = false
        } catch {
            if !saveFailed { message = "Your progress could not be saved. Keep the app open and free up device storage. \(error.localizedDescription)" }
            saveFailed = true
        }
    }

    private func releaseFolder() {
        if ownsScopedAccess { rootURL?.stopAccessingSecurityScopedResource() }
        rootURL = nil
        ownsScopedAccess = false
        needsFolderAccess = false
    }

    func importFolder(_ url: URL) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let granted = url.startAccessingSecurityScopedResource()
        var retainAccess = false
        defer { if granted && !retainAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
            // Only carry decisions over when reopening the exact same folder.
            let sameRoot = rootURL?.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath()
            let previous = sameRoot && session?.origin == .files ? items : []
            let found = try await Task.detached(priority: .userInitiated) { try FileService.scan(url, prior: previous) }.value
            guard !found.isEmpty else { throw FoliowError.message("No supported photo files were found in this folder. Download cloud files locally in Files before reviewing.") }
            releaseFolder()
            rootURL = url
            ownsScopedAccess = granted
            retainAccess = true
            session = SavedSession(title: url.lastPathComponent, origin: .files, folderBookmark: bookmark, items: found)
            history.removeAll()
            filter = .review
            currentID = visible.first?.id
            persist()
        } catch { message = error.localizedDescription }
    }

    func importCollection(_ collection: LibraryCollection) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await PhotoService.authorize()
            let old = session?.origin == .library ? items : []
            let found = PhotoService.items(in: collection.collection, prior: old)
            guard !found.isEmpty else { throw FoliowError.message("No accessible photos found. For limited access, allow more photos in Settings → Apps → Foliow → Photos.") }
            releaseFolder()
            session = SavedSession(title: collection.title, origin: .library, folderBookmark: nil, items: found)
            history.removeAll()
            filter = .review
            currentID = visible.first?.id
            persist()
        } catch { message = error.localizedDescription }
    }

    func setFilter(_ value: ReviewFilter) {
        guard !busy else { return }
        filter = value
        currentID = visible.first?.id
    }

    func decide(_ decision: Decision) {
        guard !busy, let item = current, let index = session?.items.firstIndex(where: { $0.id == item.id }) else { return }
        let before = visible
        let position = before.firstIndex(where: { $0.id == item.id }) ?? 0
        if item.decision != decision { history.append(ReviewHistory(id: item.id, previous: item.decision)) }
        session?.items[index].decision = decision
        let after = visible
        if after.contains(where: { $0.id == item.id }), !after.isEmpty {
            currentID = after[(position + 1) % after.count].id
        } else { currentID = after.isEmpty ? nil : after[min(position, after.count - 1)].id }
        persist()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func undo() {
        guard !busy, let last = history.popLast(), let index = session?.items.firstIndex(where: { $0.id == last.id }) else { return }
        session?.items[index].decision = last.previous
        filter = last.previous == .keep ? .keep : last.previous == .pass ? .pass : .review
        currentID = last.id
        persist()
    }

    func skip() {
        let list = visible
        guard !busy, let item = current, let index = list.firstIndex(where: { $0.id == item.id }), list.count > 1 else { return }
        currentID = list[(index + 1) % list.count].id
    }

    func image(for item: PhotoItem) async throws -> UIImage {
        previewLoading = true
        defer { if current?.id == item.id { previewLoading = false } }
        switch item.origin {
        case .library:
            guard let id = item.assetIdentifier else { throw FoliowError.message("Missing Photos reference.") }
            return try await PhotoService.preview(id, pixels: 1800)
        case .files:
            guard !needsFolderAccess, let rootURL else { throw FoliowError.message("Reselect the original folder to restore access.") }
            return try await PreviewService.filePreview(FileService.url(for: item, root: rootURL))
        }
    }

    /// The immutable candidate snapshot is created when the deletion sheet opens.
    func deleteConfirmed(_ snapshot: [PhotoItem]) async {
        guard !busy, !snapshot.isEmpty, let origin = session?.origin else { return }
        let eligible = Set(passed.map(\.id))
        guard Set(snapshot.map(\.id)).isSubset(of: eligible), snapshot.allSatisfy({ $0.decision == .pass && $0.origin == origin }) else {
            message = "Your decisions changed. Reopen the passed-photo deletion list."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let deleted: Set<String>
            var failures: [String] = []
            if origin == .library {
                try await PhotoService.authorize()
                deleted = try await PhotoService.deletePassed(snapshot)
            } else {
                guard !needsFolderAccess, let rootURL else { throw FoliowError.message("Reselect the original folder before deleting.") }
                let result = await Task.detached(priority: .userInitiated) { FileService.deletePassed(snapshot, root: rootURL) }.value
                deleted = result.deletedIDs
                failures = result.errors
            }
            session?.items.removeAll { deleted.contains($0.id) }
            // Physical deletion cannot be reversed by restoring a decision.
            history.removeAll()
            currentID = visible.first?.id
            persist()
            if failures.isEmpty {
                message = "Deleted \(deleted.count) passed photo\(deleted.count == 1 ? "" : "s"). Keepers and unreviewed photos were left in place."
            } else {
                message = "Deleted \(deleted.count). \(failures.count) could not be deleted and remain in Passed.\n\n" + failures.prefix(8).joined(separator: "\n")
            }
        } catch { message = "Deletion did not complete: \(error.localizedDescription)" }
    }

    func refreshPhotosAccess() {
        guard !busy, session?.origin == .library else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        session?.items = PhotoService.stillAvailable(items)
        if let id = currentID, !visible.contains(where: { $0.id == id }) { currentID = visible.first?.id }
        persist()
    }
}
