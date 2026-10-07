"""Opt-in detach-to-close cadence experiment; never edits the ordinary proof."""
import re
from MenuBarMotionComparison import EXPECTED_CASES, PAYLOAD, SERIALIZE

ANCHOR = '''            fixture.container.addSubview(view)
            try await waitForClock(arc)
            return ["restoredIntoSameWindow": view.window === window]
'''
TREATMENT = '''            fixture.container.addSubview(view)
            try await waitForClock(arc)
            let cadenceStarted = CACurrentMediaTime()
            let cadenceBefore: [String: Any] = ["window": diagnostics(window),
                "native": nativeDiagnostics(view: view, arc: arc, window: window)]
            var cadenceAngles = [Double]()
            #if FIXTURE_OBSERVED_DETACH_CADENCE || FIXTURE_DELAY_ONLY_DETACH_CADENCE
            do {
                #if FIXTURE_OBSERVED_DETACH_CADENCE
                cadenceAngles = try await observeDetachedCompositor(view: view, arc: arc,
                    window: window, container: fixture.container)
                #else
                try await waitDetachedCadence(view: view, arc: arc,
                    window: window, container: fixture.container)
                #endif
            } catch {
                throw MotionProofFailure("\\(error.localizedDescription); detachCadenceBefore=\\(cadenceBefore); "
                    + "detachCadenceSeconds=\\(CACurrentMediaTime() - cadenceStarted); "
                    + "detachCadenceAfter=\\(nativeDiagnostics(view: view, arc: arc, window: window))")
            }
            #endif
            return ["restoredIntoSameWindow": view.window === window,
                    "detachCadence": ["before": cadenceBefore, "seconds": CACurrentMediaTime() - cadenceStarted,
                        "angles": cadenceAngles, "forcedDisplay": false,
                        "after": ["window": diagnostics(window),
                                  "native": nativeDiagnostics(view: view, arc: arc, window: window)]]]
'''
OBSERVER_ANCHOR = '    private static func recoveredClockEvidence('
OBSERVER = '''    /// Diagnostic only: observe advancing presentation motion before close.
    /// No display, flush, configure, hold or lifecycle recovery is requested.
    private static func observeDetachedCompositor(view: MenuBarActivityArc.ActivityArcView,
                                                  arc: CAShapeLayer, window: NSWindow,
                                                  container: NSView) async throws -> [Double] {
        let backing = view.layer
        func geometry() -> [String] {
            [NSStringFromRect(view.frame), NSStringFromRect(view.bounds), NSStringFromRect(arc.frame),
             arc.path.map { NSStringFromRect($0.boundingBoxOfPath) } ?? "nil",
             String(Double(arc.lineWidth)), String(Double(arc.strokeStart)), String(Double(arc.strokeEnd))]
        }
        let initialGeometry = geometry()
        var angles = [Double]()
        let deadline = CACurrentMediaTime() + 4
        repeat {
            try Task.checkCancellation()
            try require(window.contentView === container && view.superview === container
                        && view.window === window && view.layer === backing && arc.superlayer === backing
                        && backing?.sublayers?.first === arc && geometry() == initialGeometry,
                        "Detach observation lost native identity or geometry")
            try require(window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
                        && !view.isHiddenOrHasHiddenAncestor && view.visibleRect.intersects(view.bounds)
                        && !arc.isHidden && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                        "Detach observation lost native eligibility")
            let clock = arc.animation(forKey: "inferenceRotation") as? CABasicAnimation
            try require(arc.animationKeys() == ["inferenceRotation"] && clock?.keyPath == "transform.rotation.z"
                        && clock?.duration == 1.4 && clock?.repeatCount == .infinity,
                        "Detach observation lost the single production clock")
            if let presentation = arc.presentation() {
                let angle = atan2(presentation.transform.m12, presentation.transform.m11)
                if angle.isFinite, angles.first.map({ angularDistance($0, angle) > 0.1 }) ?? true {
                    angles.append(angle)
                    if angles.count == 2 { return angles }
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        } while CACurrentMediaTime() < deadline
        throw MotionProofFailure("Detached compositor did not supply two advancing eligible angles")
    }

'''
DELAY = '''    /// Diagnostic only: one settling interval with no presentation reads.
    private static func waitDetachedCadence(view: MenuBarActivityArc.ActivityArcView,
                                            arc: CAShapeLayer, window: NSWindow,
                                            container: NSView) async throws {
        let backing = view.layer
        func geometry() -> [String] {
            [NSStringFromRect(view.frame), NSStringFromRect(view.bounds), NSStringFromRect(arc.frame),
             arc.path.map { NSStringFromRect($0.boundingBoxOfPath) } ?? "nil",
             String(Double(arc.lineWidth)), String(Double(arc.strokeStart)), String(Double(arc.strokeEnd))]
        }
        let initialGeometry = geometry()
        try await Task.sleep(for: .milliseconds(50))
        try Task.checkCancellation()
        try require(window.contentView === container && view.superview === container
                    && view.window === window && view.layer === backing && arc.superlayer === backing
                    && backing?.sublayers?.first === arc && geometry() == initialGeometry,
                    "Detach delay lost native identity or geometry")
        try require(window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
                    && !view.isHiddenOrHasHiddenAncestor && view.visibleRect.intersects(view.bounds)
                    && !arc.isHidden && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    "Detach delay lost native eligibility")
        let clock = arc.animation(forKey: "inferenceRotation") as? CABasicAnimation
        try require(arc.animationKeys() == ["inferenceRotation"] && clock?.keyPath == "transform.rotation.z"
                    && clock?.duration == 1.4 && clock?.repeatCount == .infinity,
                    "Detach delay lost the single production clock")
    }

'''
METADATA = '''        payload["diagnosticComparisonOnly"] = true
        payload["replacesNormalNativeGate"] = false
        #if FIXTURE_OBSERVED_DETACH_CADENCE
        payload["detachCadence"] = "compositor-observed"
        #elseif FIXTURE_DELAY_ONLY_DETACH_CADENCE
        payload["detachCadence"] = "delay-only"
        payload["detachCadenceRequestedDelayMilliseconds"] = 50
        #else
        payload["detachCadence"] = "immediate"
        #endif
'''


def stage_detach_cadence(source: str) -> str:
    cases = tuple(re.findall(r'await report\.check\("([^"\n]+)"\)', source))
    if cases != EXPECTED_CASES:
        raise ValueError('Detach cadence requires the unchanged fifteen ordered cases')
    if source.count(ANCHOR) != 1 or source.count(OBSERVER_ANCHOR) != 1:
        raise ValueError('Detach cadence observation anchors drifted')
    if source.count(PAYLOAD) != 1 or source.count(SERIALIZE) != 1:
        raise ValueError('Detach cadence report anchors drifted')
    start = source.index('        await report.check("detach_and_restore")')
    end = source.index('        await report.check("same_window_close_and_reopen")')
    if ANCHOR not in source[start:end]:
        raise ValueError('Detach cadence anchor moved outside the detach case')
    staged = source.replace(ANCHOR, TREATMENT).replace(OBSERVER_ANCHOR, OBSERVER + DELAY + OBSERVER_ANCHOR)
    staged = staged.replace(PAYLOAD, PAYLOAD.replace('let payload', 'var payload'))
    return staged.replace(SERIALIZE, METADATA + SERIALIZE)
