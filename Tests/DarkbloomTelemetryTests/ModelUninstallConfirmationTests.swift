import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Model uninstall confirmation")
struct ModelUninstallConfirmationTests {
    @Test("confirmation uses observed local bytes and warns about delayed space")
    func observedSize() {
        let confirmation = ModelUninstallConfirmation(localID: "org/model", displayName: "Model",
            downloadedSizeBytes: 1_000_000_000, cacheDirectory: "/Users/review/.cache/huggingface")
        #expect(confirmation.id == "org/model")
        #expect(confirmation.downloadedSizeDescription == ByteCountFormatter.string(fromByteCount: 1_000_000_000, countStyle: .file))
        #expect(confirmation.message.contains("Downloaded model size:"))
        #expect(confirmation.message.contains("cached revisions"))
        #expect(confirmation.message.contains("You can download it again"))
        #expect(confirmation.message.contains("Backups may delay"))
        #expect(confirmation.cacheDirectory == "/Users/review/.cache/huggingface")
        #expect(confirmation.message.contains(confirmation.cacheDirectory))
    }

    @Test("missing or invalid local sizes do not invent reclaimable space", arguments: [nil, Int64(0), Int64(-1)])
    func unknownSize(bytes: Int64?) {
        let confirmation = ModelUninstallConfirmation(localID: "org/model", displayName: "Model",
            downloadedSizeBytes: bytes, cacheDirectory: "/Volumes/Models/huggingface")
        #expect(confirmation.downloadedSizeDescription == nil)
        #expect(!confirmation.message.contains("Downloaded model size:"))
        #expect(confirmation.message.contains("downloaded files and cached revisions"))
    }
}
