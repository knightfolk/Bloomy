"""Single-factor manual-host layer-backing comparison; never edits product source."""
import re
from MenuBarMotionComparison import EXPECTED_CASES, PAYLOAD, SERIALIZE

ANCHOR = '            container = MotionOpaqueTargetView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))\n'
FIXTURE_PREFIX = '''    private struct MotionArcFixture {
        let container: NSView
        let view: MenuBarActivityArc.ActivityArcView
        let window: NSWindow
        let arc: CAShapeLayer

        init() throws {
'''
TREATMENT = ANCHOR + '''            #if FIXTURE_EXPLICIT_MOTION_ROOT_LAYER
            container.wantsLayer = true
            #endif
'''
METADATA = '''        payload["diagnosticComparisonOnly"] = true
        payload["replacesNormalNativeGate"] = false
        #if FIXTURE_EXPLICIT_MOTION_ROOT_LAYER
        payload["manualRootLayer"] = "explicit"
        #else
        payload["manualRootLayer"] = "ordinary"
        #endif
'''


def stage_root_layer(source: str) -> str:
    cases = tuple(re.findall(r'await report\.check\("([^"\n]+)"\)', source))
    if cases != EXPECTED_CASES:
        raise ValueError('Root-layer comparison requires the unchanged fifteen ordered cases')
    for anchor in (ANCHOR, PAYLOAD, SERIALIZE):
        if source.count(anchor) != 1:
            raise ValueError('Root-layer comparison anchor drifted')
    if source.count(FIXTURE_PREFIX + ANCHOR) != 1:
        raise ValueError('Root-layer anchor moved outside the manual fixture initializer')
    staged = source.replace(ANCHOR, TREATMENT)
    staged = staged.replace(PAYLOAD, PAYLOAD.replace('let payload', 'var payload'))
    return staged.replace(SERIALIZE, METADATA + SERIALIZE)
