"""Guard the supported-host diagnostic against settling or manual reattachment."""
import re
import unittest
from pathlib import Path


class SettingsPreviewStagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = Path(__file__).with_name('SettingsPreviewProof.swift').read_text()

    def test_complete_ordered_case_inventory_and_terminal_count(self):
        cases = re.findall(r'await session\.check\("([^"\n]+)"\)', self.source)
        self.assertEqual(cases, [
            'actual_settings_baseline', 'ten_fresh_updates', 'active_idle_active',
            'independent_fan_temperature_updates', 'failed_fan_read_and_recovery',
            'window_appearance_changes_without_reading', 'navigate_away_return',
            'navigate_return_immediate_close_reopen', 'supported_opaque_cover_and_restore', 'minimize_restore',
            'retained_close_reopen', 'rapid_close_reopen'])
        self.assertIn('results.count == 12', self.source)

    def test_immediate_sequence_has_no_interposed_wait_or_presentation_read(self):
        block = self.source.split('let returned = try await session.eligible()\n', 1)[1]
        before_eligibility = block.split('_ = try await session.eligible()', 1)[0]
        statements = '\n'.join(line.strip() for line in before_eligibility.splitlines()
                               if line.strip() and not line.strip().startswith('//'))
        self.assertEqual(statements, '\n'.join([
            'try require(returned.view !== old.view && returned.layer !== old.layer,',
            '"immediate_navigation_reused_dismantled_preview")',
            'let geometry = returned.geometry',
            'let beforeClose = returned.attachment',
            'window.performClose(nil)', 'reopen()']))
        attachment = self.source.split('var attachment: [String: Any] {', 1)[1].split('var geometry:', 1)[0]
        for forbidden in ['presentation()', 'sleep', 'flush', 'display', 'layout', 'configure', 'addSublayer']:
            self.assertNotIn(forbidden, attachment)
        self.assertIn('ancestors.count < 32', attachment)

    def test_three_supported_cycles_and_unchanged_motion_hold(self):
        block = self.source.split('await session.check("navigate_return_immediate_close_reopen")', 1)[1].split('await session.check("supported_opaque_cover_and_restore")', 1)[0]
        self.assertIn('for cycle in 0..<3', block)
        self.assertIn('navigation.sidebarSelection = .settings(.appearance)', block)
        self.assertIn('session.nativeArcs().isEmpty', block)
        self.assertIn('showPreview()', block)
        self.assertIn('session.requireIdentity(returned)', block)
        self.assertIn('returned.geometry == geometry', block)
        self.assertIn('session.motion(returned', block)
        for forbidden in ['removeFromSuperview', 'addSubview', 'wantsLayer =', 'CATransaction', 'Task.sleep']:
            self.assertNotIn(forbidden, block)
        self.assertIn('Task.sleep(for: .milliseconds(1_700))', self.source)
        self.assertIn('"replacesNormalNativeGate": false', self.source)

    def test_cover_requires_real_occlusion_and_joined_graceful_cleanup(self):
        block = self.source.split('await session.check("supported_opaque_cover_and_restore")', 1)[1].split('await session.check("minimize_restore")', 1)[0]
        for required in ['screen.frame.contains(coverFrame)', '(32...1_024).contains(coverFrame.width)',
                         'session.opaqueCoverage', '!window.occlusionState.contains(.visible)',
                         '!store.dashboardVisible', 'animationKeys()', '"parent-request"',
                         'probe["passed"] as? Bool == true', 'session.coverProbes.append(probe)',
                         'throw CancellationError()', 'defer { window.setFrame(originalFrame, display: false) }']:
            self.assertIn(required, block)
        self.assertEqual(block.count('session.wait('), 1)
        for forbidden in ['postNotification', 'synchronizeAnimation', 'configure(', 'CATransaction', 'displayIfNeeded', 'layoutSubtree']:
            self.assertNotIn(forbidden, block)


if __name__ == '__main__':
    unittest.main()
