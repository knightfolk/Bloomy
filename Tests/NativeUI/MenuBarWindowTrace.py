"""Bounded, opt-in native callback instrumentation for staged review copies."""

TRACE_FIELDS = r'''
        #if FIXTURE_MOTION_WINDOW_TRACE
        private var fixtureEvents: [[String: Any]] = []
        private var fixtureDroppedEvents = 0
        private weak var fixtureObserverWindow: NSWindow?

        func fixtureLifecycleTrace() -> [String: Any] {
            ["events": fixtureEvents, "droppedEvents": fixtureDroppedEvents,
             "capacity": 512, "diagnosticOnly": true]
        }

        private func fixtureTrace(_ event: String, nextWindow: NSWindow? = nil) {
            guard fixtureEvents.count < 512 else { fixtureDroppedEvents += 1; return }
            fixtureEvents.append(["event": event, "time": CACurrentMediaTime(),
                "view": String(describing: ObjectIdentifier(self)),
                "arc": String(describing: ObjectIdentifier(arc)),
                "window": window?.windowNumber ?? -1,
                "nextWindow": nextWindow?.windowNumber ?? -1,
                "observerWindow": fixtureObserverWindow?.windowNumber ?? -1,
                "windowVisible": window?.isVisible ?? false,
                "compositorVisible": window?.occlusionState.contains(.visible) ?? false,
                "active": active, "dismantled": dismantled, "reduceMotion": reduceMotion,
                "hidden": isHiddenOrHasHiddenAncestor,
                "animationKeys": arc.animationKeys() ?? [],
                "backingLayer": layer.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                "arcParent": arc.superlayer.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                "closeReevaluationScheduled": closeReevaluationScheduled])
        }
        #endif
'''


def trace_call(event: str, *, next_window: bool = False) -> str:
    argument = ', nextWindow: newWindow' if next_window else ''
    return f'''            #if FIXTURE_MOTION_WINDOW_TRACE
            fixtureTrace("{event}"{argument})
            #endif
'''


LABEL_PATCHES = [
    ("        private weak var closedWindowAwaitingReevaluation: NSWindow?\n", TRACE_FIELDS),
    ("        override func viewWillMove(toWindow newWindow: NSWindow?) {\n",
     trace_call("willMoveWindow", next_window=True)),
    ("            NotificationCenter.default.removeObserver(self)\n            super.viewWillMove(toWindow: newWindow)\n",
     '''            #if FIXTURE_MOTION_WINDOW_TRACE
            fixtureObserverWindow = nil
            fixtureTrace("windowObserversRemoved")
            #endif
'''),
    ("        override func viewDidMoveToWindow() {\n", trace_call("didMoveWindow")),
    ("                                   name: NSWindow.willCloseNotification, object: window)\n",
     '''                #if FIXTURE_MOTION_WINDOW_TRACE
                fixtureObserverWindow = window
                fixtureTrace("windowObserversAdded")
                #endif
'''),
    ("        override func viewDidMoveToSuperview() {\n", trace_call("didMoveSuperview")),
    ("        override func viewDidHide() {\n", trace_call("didHide")),
    ("        override func viewDidUnhide() {\n", trace_call("didUnhide")),
    ("        func stopObserving() {\n", trace_call("dismantle") +
     '''            #if FIXTURE_MOTION_WINDOW_TRACE
            defer {
                fixtureObserverWindow = nil
                fixtureTrace("dismantleObserversRemoved")
            }
            #endif
'''),
    ("        func configure(active: Bool, tint: NSColor, reduceMotion: Bool = false) {\n",
     trace_call("configure")),
    ("        @objc private func windowWillClose() {\n", trace_call("willCloseNotification")),
    ("                self.closedWindowAwaitingReevaluation = nil\n",
     '''                #if FIXTURE_MOTION_WINDOW_TRACE
                self.fixtureTrace("deferredCloseReevaluation")
                #endif
'''),
    ("        private func synchronizeAnimation() {\n",
     '''            #if FIXTURE_MOTION_WINDOW_TRACE
            fixtureTrace("synchronizeEnter")
            defer { fixtureTrace("synchronizeExit") }
            #endif
'''),
]

VISIBILITY_BEFORE = "        @objc private func windowVisibilityChanged() { synchronizeAnimation() }\n"
VISIBILITY_AFTER = '''        @objc private func windowVisibilityChanged() {
''' + trace_call("visibilityNotification") + '''            synchronizeAnimation()
        }
'''

# One anchor has insertion-before semantics; it must still retain the original
# removal and super call exactly. All remaining patches insert after anchors.
BEFORE_ANCHOR = LABEL_PATCHES[2][0]


def stage_window_trace(source: str) -> str:
    for anchor, _ in LABEL_PATCHES:
        if source.count(anchor) != 1:
            raise ValueError(f"Window trace source anchor drifted: {anchor.strip()}")
    if source.count(VISIBILITY_BEFORE) != 1:
        raise ValueError("Window trace visibility callback anchor drifted")
    for anchor, addition in LABEL_PATCHES:
        if anchor == BEFORE_ANCHOR:
            # Record removal after it happened, before the original super call.
            first, second = anchor.split('            super.', 1)
            source = source.replace(anchor, first + addition + '            super.' + second)
        else:
            source = source.replace(anchor, anchor + addition)
    return source.replace(VISIBILITY_BEFORE, VISIBILITY_AFTER)


TRACE_REPORT_FIELDS = '''    #if FIXTURE_MOTION_WINDOW_TRACE
    var windowTraceCases: [[String: Any]] = []
    #endif
'''
TRACE_CASE = '''                #if FIXTURE_MOTION_WINDOW_TRACE
                defer {
                    report.windowTraceCases.append(["case": name, "generation": comparisonGeneration,
                        "windowNumber": window.windowNumber, "trace": view.fixtureLifecycleTrace()])
                }
                #endif
'''
TRACE_METADATA = '''        #if FIXTURE_MOTION_WINDOW_TRACE
        payload["nativeWindowTrace"] = windowTraceCases
        #endif
'''


def stage_trace_report(source: str) -> str:
    anchors = [
        ("    var failures: [String] = []\n", TRACE_REPORT_FIELDS),
        ('                var phase = "preparation"\n', TRACE_CASE),
        ('        payload["replacesNormalNativeGate"] = false\n', TRACE_METADATA),
    ]
    for anchor, _ in anchors:
        if source.count(anchor) != 1:
            raise ValueError(f"Window trace report anchor drifted: {anchor.strip()}")
    for anchor, addition in anchors:
        source = source.replace(anchor, anchor + addition)
    return source
