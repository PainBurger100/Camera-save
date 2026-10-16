import Foundation
import UniformTypeIdentifiers

struct FileDeletionResult {
    var deletedIDs: Set<String> = []
    var errors: [String] = []
}

enum FileService {
    static let extensions: Set<String> = Set("jpg jpeg jpe jfif png heic heif webp avif gif bmp tif tiff cr2 cr3 nef nrw arw srf sr2 dng raf orf rw2 pef srw raw rwl 3fr iiq erf kdc mos mrw x3f".split(separator: " ").map(String.init))
    static let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .nameKey]

    static func fingerprint(_ url: URL) throws -> FileFingerprint {
        let values = try url.resourceValues(forKeys: resourceKeys)
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, let date = values.contentModificationDate else {
            throw FoliowError.message("Not a regular, accessible photo file.")
        }
        return FileFingerprint(bytes: Int64(bytes), modified: date)
    }

    static func scan(_ root: URL, prior: [PhotoItem]) throws -> [PhotoItem] {
        let saved = Dictionary(prior.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(resourceKeys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in
            enumerationError = error
            return true
        }) else { throw FoliowError.message("This folder could not be opened. Download it locally in Files and try again.") }
        let base = root.standardizedFileURL.path
        var items: [PhotoItem] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: resourceKeys)
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                  extensions.contains(url.pathExtension.lowercased()), DeletionRules.isDescendant(url, of: root),
                  let stamp = try? fingerprint(url) else { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            let id = "file:\(relative)"
            let old = saved[id]
            let decision = old?.fingerprint?.matches(stamp) == true ? old?.decision : nil
            items.append(PhotoItem(id: id, name: url.lastPathComponent, origin: .files, relativePath: relative,
                                   assetIdentifier: nil, fingerprint: stamp, decision: decision))
        }
        if items.isEmpty, let error = enumerationError { throw error }
        if let error = enumerationError {
            throw FoliowError.message("Some folders could not be read: \(error.localizedDescription). Make the folder available offline, then try again.")
        }
        return items.sorted { ($0.relativePath ?? $0.name).localizedStandardCompare($1.relativePath ?? $1.name) == .orderedAscending }
    }

    static func url(for item: PhotoItem, root: URL) throws -> URL {
        guard item.origin == .files, let relative = item.relativePath,
              !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else {
            throw FoliowError.message("Invalid photo path.")
        }
        let url = root.appendingPathComponent(relative)
        guard DeletionRules.isDescendant(url, of: root) else {
            throw FoliowError.message("The photo is outside the selected folder.")
        }
        return url
    }

    /// Called only with the snapshot shown in the final deletion sheet.
    static func deletePassed(_ candidates: [PhotoItem], root: URL) -> FileDeletionResult {
        var result = FileDeletionResult()
        for item in candidates {
            guard item.decision == .pass, item.origin == .files, let expected = item.fingerprint else {
                result.errors.append("\(item.name): not an eligible passed file.")
                continue
            }
            do {
                let url = try FileService.url(for: item, root: root)
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinationError: NSError?
                var operationError: Error?
                var removed = false
                coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
                    do {
                        guard DeletionRules.isDescendant(coordinatedURL, of: root),
                              expected.matches(try fingerprint(coordinatedURL)) else {
                            throw FoliowError.message("The original changed since review. Review it again before deleting.")
                        }
                        try FileManager.default.removeItem(at: coordinatedURL)
                        removed = true
                    } catch { operationError = error }
                }
                if let error = coordinationError { throw error }
                if let error = operationError { throw error }
                guard removed else { throw FoliowError.message("The file provider did not complete deletion.") }
                result.deletedIDs.insert(item.id)
            } catch { result.errors.append("\(item.name): \(error.localizedDescription)") }
        }
        return result
    }
}
