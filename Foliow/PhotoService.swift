import Photos
import UIKit

struct LibraryCollection: Identifiable {
    let id: String
    let title: String
    let collection: PHAssetCollection?
}

enum PhotoService {
    static func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw FoliowError.message("Allow Photos access in Settings → Apps → Foliow → Photos to review and delete photos.")
        }
    }

    static func collections() -> [LibraryCollection] {
        var result = [LibraryCollection(id: "all", title: "All accessible photos", collection: nil)]
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        fetch.enumerateObjects { collection, _, _ in
            result.append(LibraryCollection(id: collection.localIdentifier, title: collection.localizedTitle ?? "Album", collection: collection))
        }
        return result
    }

    static func items(in collection: PHAssetCollection?, prior: [PhotoItem]) -> [PhotoItem] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = collection.map { PHAsset.fetchAssets(in: $0, options: options) } ?? PHAsset.fetchAssets(with: options)
        let saved = Dictionary(prior.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var result: [PhotoItem] = []
        assets.enumerateObjects { asset, _, _ in
            let resource = PHAssetResource.assetResources(for: asset).first { $0.type == .photo } ?? PHAssetResource.assetResources(for: asset).first
            let id = "photos:\(asset.localIdentifier)"
            result.append(PhotoItem(id: id, name: resource?.originalFilename ?? "Photo", origin: .library,
                                    relativePath: nil, assetIdentifier: asset.localIdentifier, fingerprint: nil,
                                    decision: saved[id]?.decision))
        }
        return result
    }

    static func stillAvailable(_ items: [PhotoItem]) -> [PhotoItem] {
        let identifiers = items.compactMap(\.assetIdentifier)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var available = Set<String>()
        assets.enumerateObjects { asset, _, _ in available.insert(asset.localIdentifier) }
        return items.filter { $0.assetIdentifier.map(available.contains) == true }
    }

    static func deletePassed(_ candidates: [PhotoItem]) async throws -> Set<String> {
        guard !candidates.isEmpty, candidates.allSatisfy({ $0.origin == .library && $0.decision == .pass }) else {
            throw FoliowError.message("Only passed photos can be deleted.")
        }
        let identifiers = candidates.compactMap(\.assetIdentifier)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count == candidates.count else {
            throw FoliowError.message("Your Photos access or library changed. Reopen this album and review the deletion list again.")
        }
        var canDelete = true
        assets.enumerateObjects { asset, _, _ in
            if !asset.canPerform(.delete) { canDelete = false }
        }
        guard canDelete else { throw FoliowError.message("Some selected photos cannot be deleted. They may be synced from a computer or belong to a read-only source.") }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
        return Set(candidates.map(\.id))
    }

    static func preview(_ identifier: String, pixels: CGFloat) async throws -> UIImage {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            throw FoliowError.message("This photo is unavailable. Check your limited Photos access or reopen the album.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: pixels, height: pixels), contentMode: .aspectFit, options: options) { image, info in
                guard (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
                if let error = info?[PHImageErrorKey] as? Error { continuation.resume(throwing: error) }
                else if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: FoliowError.message("Preview unavailable. Download this photo from iCloud in Photos and retry.")) }
            }
        }
    }
}
