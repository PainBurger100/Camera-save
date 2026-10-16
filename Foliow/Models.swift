import Foundation

enum PhotoOrigin: String, Codable { case files, library }
enum Decision: String, Codable, CaseIterable { case keep, pass }
enum ReviewFilter: String, CaseIterable, Identifiable {
    case review = "Review", keep = "Keepers", pass = "Passed"
    var id: String { rawValue }
}

struct FileFingerprint: Codable, Equatable {
    let bytes: Int64
    let modified: Date
    func matches(_ other: FileFingerprint) -> Bool {
        bytes == other.bytes && abs(modified.timeIntervalSince(other.modified)) < 0.001
    }
}

struct PhotoItem: Identifiable, Codable {
    let id: String
    let name: String
    let origin: PhotoOrigin
    let relativePath: String?
    let assetIdentifier: String?
    let fingerprint: FileFingerprint?
    var decision: Decision?
}

struct SavedSession: Codable {
    var title: String
    var origin: PhotoOrigin
    var folderBookmark: Data?
    var items: [PhotoItem]
}

struct ReviewHistory {
    let id: String
    let previous: Decision?
}

enum FoliowError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum DeletionRules {
    static func candidates(in items: [PhotoItem]) -> [PhotoItem] {
        items.filter { $0.decision == .pass }
    }
    static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let parent = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let child = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return child.count > parent.count && Array(child.prefix(parent.count)) == parent
    }
}
