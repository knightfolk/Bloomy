"""Expose the existing owned cover only in the staged Settings diagnostic."""
import re
from MenuBarMotionComparison import EXPECTED_CASES

ACCESS_EXTENSION = '''
#if FIXTURE_SETTINGS_PREVIEW_PROOF
extension MenuBarMotionProof {
    /// Own startup, observation and joined teardown even after cancellation.
    @MainActor
    static func settingsCoverProbe(frame: NSRect,
        observe: @MainActor (Int, Process, [String: Any]) async throws -> [String: Any]
    ) async -> [String: Any] {
        let cover = OwnedMotionCover(frame: frame)
        var result: [String: Any] = ["passed": false, "cancelled": false]
        do {
            try Task.checkCancellation()
            try await cover.start()
            result["observation"] = try await observe(cover.windowNumber, cover.process, cover.readyEvidence ?? [:])
            try Task.checkCancellation()
            result["passed"] = true
        } catch is CancellationError {
            result["cancelled"] = true
            result["failure"] = "cancelled"
        } catch {
            result["failure"] = error.localizedDescription
        }
        result["ready"] = cover.readyEvidence ?? [:]
        result["cleanup"] = await cover.stop()
        if Task.isCancelled {
            result["cancelled"] = true
            result["passed"] = false
            result["failure"] = "cancelled"
        }
        return result
    }
}
#endif
'''


def stage_settings_cover_access(source: str) -> str:
    if 'static func settingsCoverProbe(' in source:
        raise ValueError('Settings cover access already present')
    cases = tuple(re.findall(r'await report\.check\("([^"\n]+)"\)', source))
    if cases != EXPECTED_CASES:
        raise ValueError('Settings cover access requires the unchanged fifteen cases')
    for anchor in ['    private final class OwnedMotionCover {\n',
                   '        func start() async throws {\n',
                   '        func stop() async -> [String: Any] {\n',
                   'process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL',
                   'process.arguments = ["--motion-cover",']:
        if source.count(anchor) != 1:
            raise ValueError('Owned cover safety anchor drifted')
    return source + ACCESS_EXTENSION
