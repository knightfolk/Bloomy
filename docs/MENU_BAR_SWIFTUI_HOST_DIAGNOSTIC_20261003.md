# Actual SwiftUI menu host comparison

The separate native fixture hosts the production `MenuBarLabel` in an
`NSHostingController` with fixed synthetic active-model, GPU and fan values.
It makes no provider/API request and changes no preferences.

All four finite cases reached terminal success on October 3:

1. Active rotation advances in the actual compositor.
2. Closing/reopening the same window retains the native view and arc, and
   rotation still advances after a 1.6-second hold.
3. Rapid close/reopen retains the same objects and sustained motion.
4. SwiftUI root removal drives actual dismantle. The retained view is then
   reattached to an eligible visible window and stressed with configuration,
   hiding and reopening; its animation does not resurrect.

The observations retain real visibility/occlusion and Reduce Motion
prerequisites. No forced redraw or transaction flush establishes motion.
The first build caught a Swift 6 observer isolation error; copying the
notification name into a Sendable String before the main-actor closure fixed
compilation. The second builder completed, and actual native Run-button clicks
produced the terminal report.

This narrows the earlier standalone AppKit-host problem. It does not replace
or declare the separate 15-case check passing: Native186 still reports 12/15,
including an unestablished genuine-cover prerequisite and two standalone-host
reopen failures. Layer-backing its parent alone did not change those outcomes.
The failed checks and dirty layer-graph diagnostics remain preserved.

The ring production source is byte-identical to published 1.9.18. The focused
1.9.19 Uninstall release keeps that published menu-bar implementation and
excludes the later unfinished Settings preview. The development preview and
broader native matrix are still open.

Reproduce with
`python3 Tests/NativeUI/build-menu-host-lifecycle-fixture.py` after current Debug
products are available, then click **Run lifecycle diagnostic** in the emitted
isolated app. The retained second build is
`.build/menu-host-lifecycle-fixture-20261003-002`; its manifest records source,
dependency and binary hashes. Its report is
`BloomyMenuHostLifecycle-63933-49338C45-DC32-49A8-BBD1-DE6C4B642099/host-lifecycle-proof.json`
under this Mac's temporary directory. Review signing is not distribution proof.
