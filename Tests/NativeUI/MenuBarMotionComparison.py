"""Opt-in staging overlay; never edits the source motion diagnostic.

All comparison modes receive identical staged Swift. Compiler definitions
change target lifetime at known boundaries. Normal builds receive no overlay.
"""
import re


EXPECTED_CASES = (
    "native_window_visible", "active_compositor_advances", "repeated_updates_keep_one_clock",
    "self_hide_and_restore", "ancestor_hide_and_restore", "window_order_out_and_restore",
    "opaque_cover_occlusion_and_restore", "detach_and_restore", "same_window_close_and_reopen",
    "rapid_same_window_close_and_reopen", "native_stationary_true_false_true",
    "inactive_evidence_stops_immediately", "dismantle_retained_view",
    "parent_stationary_activity_bridge", "parent_reading_updates_preserve_native_identity",
)

ALIASES = """        let view = fixture.view
        let window = fixture.window
        let arc = fixture.arc
"""

PAYLOAD = '        let payload: [String: Any] = ["proof": "native-menu-bar-motion", "synthetic": true,\n'
SERIALIZE = "        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])\n"
METADATA = '''        payload["diagnosticComparisonOnly"] = true
        payload["replacesNormalNativeGate"] = false
        #if FIXTURE_FRESH_MOTION_TARGETS
        payload["targetLifetime"] = "fresh"
        #elseif FIXTURE_RESET_BEFORE_DETACH
        payload["targetLifetime"] = "reset-before-detach"
        #else
        payload["targetLifetime"] = "reused"
        #endif
'''

COMPARISON = r'''        var view: MenuBarActivityArc.ActivityArcView { fixture.view }
        var window: NSWindow { fixture.window }
        var arc: CAShapeLayer { fixture.arc }
        var comparisonGeneration = 0

        func comparisonCheck(_ name: String, body: () async throws -> [String: Any]) async {
            if name.hasPrefix("parent_") {
                await report.check(name, body: body)
                return
            }
            await report.check(name) {
                var phase = "preparation"
                do {
                    #if FIXTURE_FRESH_MOTION_TARGETS
                    let replaceTarget = name != "native_window_visible"
                    #elseif FIXTURE_RESET_BEFORE_DETACH
                    let replaceTarget = name == "detach_and_restore"
                    #else
                    let replaceTarget = false
                    #endif
                    if replaceTarget {
                        phase = "close previous target"
                        fixture.window.close()
                        phase = "create fresh target"
                        fixture = try MotionArcFixture()
                        comparisonGeneration += 1
                    }
                    // Match ordering/visibility preflight in both modes, so
                    // it cannot explain a difference attributed to lifetime.
                    phase = "visible starting state"
                    showOwnedProofWindow(window)
                    try await waitForVisible(window)
                    let identity: [String: Any] = ["generation": comparisonGeneration,
                        "windowNumber": window.windowNumber,
                        "view": String(describing: ObjectIdentifier(view)),
                        "arc": String(describing: ObjectIdentifier(arc))]
                    phase = "case body"
                    var evidence = try await body()
                    evidence["targetComparison"] = identity
                    return evidence
                } catch {
                    let identity: [String: Any] = ["generation": comparisonGeneration,
                        "windowNumber": window.windowNumber,
                        "view": String(describing: ObjectIdentifier(view)),
                        "arc": String(describing: ObjectIdentifier(arc))]
                    throw MotionProofFailure("\(error.localizedDescription); comparisonPhase=\(phase); targetComparison=\(identity); "
                        + "finalWindow=\(diagnostics(window)); finalNative=\(nativeDiagnostics(view: view, arc: arc, window: window))")
                }
            }
        }
'''


def stage_comparison(source: str) -> str:
    cases = tuple(re.findall(r'await report\.check\("([^"\n]+)"\)', source))
    if cases != EXPECTED_CASES:
        raise ValueError("Motion comparison requires the unchanged fifteen ordered cases")
    declaration = "        let fixture: MotionArcFixture\n"
    if source.count(declaration) != 1 or source.count(ALIASES) != 1:
        raise ValueError("Motion fixture declaration/alias staging contract drifted")
    if source.count(PAYLOAD) != 1 or source.count(SERIALIZE) != 1:
        raise ValueError("Motion report metadata staging contract drifted")
    # Replace only call sites, declaration and aliases. Every original case
    # body, eligibility predicate, angle observation and cleanup stays intact.
    staged = source.replace("await report.check(", "await comparisonCheck(")
    staged = staged.replace(declaration, "        var fixture: MotionArcFixture\n")
    staged = staged.replace(ALIASES, COMPARISON)
    staged = staged.replace(PAYLOAD, PAYLOAD.replace("let payload", "var payload"))
    return staged.replace(SERIALIZE, METADATA + SERIALIZE)
