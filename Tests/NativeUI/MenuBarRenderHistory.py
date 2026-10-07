"""Matched early-observation experiment; production and ordinary proof untouched."""
import re
from MenuBarMotionComparison import EXPECTED_CASES, PAYLOAD, SERIALIZE

DECLARATION = '''        #if FIXTURE_COMPOSITOR_ONLY_HISTORY
        let earlyRequestDisplay = false
        #else
        let earlyRequestDisplay = true
        #endif
'''
METADATA = '''        payload["diagnosticComparisonOnly"] = true
        payload["replacesNormalNativeGate"] = false
        #if FIXTURE_COMPOSITOR_ONLY_HISTORY
        payload["earlyAngleObservation"] = "compositor-only"
        #else
        payload["earlyAngleObservation"] = "display-flush"
        #endif
'''


def stage_render_history(source: str) -> str:
    cases = tuple(re.findall(r'await report\.check\("([^"\n]+)"\)', source))
    if cases != EXPECTED_CASES:
        raise ValueError('Render comparison requires the unchanged fifteen ordered cases')
    boundary = '        await report.check("self_hide_and_restore")'
    anchor = '        let arc = fixture.arc\n'
    if source.count(boundary) != 1 or source.count(anchor) != 1:
        raise ValueError('Render comparison fixture anchors drifted')
    if source.count(PAYLOAD) != 1 or source.count(SERIALIZE) != 1:
        raise ValueError('Render comparison report anchors drifted')
    early, later = source.split(boundary, 1)
    calls = ('presentationAngle(arc, in: window)',
             'presentationAngle(arc, in: window, differingFrom: first)')
    if early.count('try await presentationAngle(') != 4 or any(early.count(call) != 2 for call in calls):
        raise ValueError('Render comparison requires exactly four unchanged early observations')
    for call in calls:
        early = early.replace(call, call[:-1] + ', requestDisplay: earlyRequestDisplay)')
    early = early.replace(anchor, anchor + DECLARATION)
    staged = early + boundary + later
    staged = staged.replace(PAYLOAD, PAYLOAD.replace('let payload', 'var payload'))
    return staged.replace(SERIALIZE, METADATA + SERIALIZE)
