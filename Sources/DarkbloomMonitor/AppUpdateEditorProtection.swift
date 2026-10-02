import Foundation
import SwiftUI

/// Tracks only whether a mounted editor has unfinished input. Credential text
/// stays in its view; independent windows and sheets never clear each other.
@MainActor
final class AppUpdateEditorProtection: ObservableObject {
    @Published private(set) var blockingOwners: Set<UUID> = []

    var hasBlockingEditors: Bool { !blockingOwners.isEmpty }

    func setBlocked(_ blocked: Bool, owner: UUID) {
        if blocked {
            guard !blockingOwners.contains(owner) else { return }
            blockingOwners.insert(owner)
        } else {
            guard blockingOwners.contains(owner) else { return }
            blockingOwners.remove(owner)
        }
    }

    func endEditing(owner: UUID) { setBlocked(false, owner: owner) }
}
