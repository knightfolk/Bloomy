import Foundation

/// Local inventory size describes model payloads, not guaranteed reclaimable
/// space: other cached revisions and local backup snapshots can differ.
struct ModelUninstallConfirmation: Identifiable, Equatable {
    let localID: String
    let displayName: String
    let downloadedSizeBytes: Int64?
    let cacheDirectory: String

    var id: String { localID }

    var downloadedSizeDescription: String? {
        guard let downloadedSizeBytes, downloadedSizeBytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: downloadedSizeBytes, countStyle: .file)
    }

    var message: String {
        let size = downloadedSizeDescription.map { "Downloaded model size: \($0).\n\n" } ?? ""
        return size + "This removes this model’s downloaded files and cached revisions from:\n\(cacheDirectory)\n\nYou can download it again. Backups may delay when the space becomes available."
    }
}
