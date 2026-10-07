"""Read-only fixture access to the real status-item button; no host changes."""

ACCESS_EXTENSION = '''
// Opt-in inert native diagnostic. This extension is staged, never shipped.
#if FIXTURE_PRODUCTION_STATUS_ITEM_PROOF
extension StatusItemController {
    var fixtureProofButton: NSStatusBarButton? { statusItem.button }
}
#endif
'''


def stage_status_item_access(source: str) -> str:
    for anchor in ("final class StatusItemController: NSObject, NSPopoverDelegate {",
                   "    private let statusItem: NSStatusItem\n"):
        if source.count(anchor) != 1:
            raise ValueError(f"Status-item diagnostic access anchor drifted: {anchor.strip()}")
    if "fixtureProofButton" in source or "FIXTURE_PRODUCTION_STATUS_ITEM_PROOF" in source:
        raise ValueError("Status-item diagnostic access is already present")
    return source + ACCESS_EXTENSION
