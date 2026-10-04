import AppKit
import DarkbloomTelemetry
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor

private let layoutNow = Date()

@Suite("Monitor popover layout")
@MainActor
struct MonitorPopoverLayoutTests {
    @Test("graphical popup earnings fit without truncating the compact layout", arguments: [false, true])
    func earningsGraphic(dark: Bool) async throws {
        let start = Calendar.current.startOfDay(for: layoutNow)
        let summary = ObservedEarningsWindow(microUSD: 6_420_000, observedSeconds: 10_800,
            calendarDayStart: start, capturedAt: start.addingTimeInterval(21_600))
        let view = PopupEarningsGraphic(metrics: PopupEarningsMetrics.make(from: summary),
            week: PopupWeekEarningsMetric(title: "Observed this week", totalUSD: 42.4))
            .padding(12).frame(width: 528)
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingController(rootView: view)
        let fitted = host.sizeThatFits(in: NSSize(width: 528, height: 0))
        #expect(fitted.width == 528)
        #expect(fitted.height < 130)
    }

    @Test("post-switch feedback fits the popup and distinguishes success from missing key")
    func postSwitchFeedback() async throws {
        let view = VStack(alignment: .leading, spacing: 8) {
            SwitchWarmupFeedback(status: .result(
                modelID: "gemma-4-26b-qat-4bit", .sent,
                at: Date(timeIntervalSince1970: 1_800_000_000)
            ))
            SwitchWarmupFeedback(status: .result(
                modelID: "gemma-4-26b-qat-4bit", .missingKey,
                at: Date(timeIntervalSince1970: 1_800_000_000)
            ))
        }
        .padding(16)
        .frame(width: 560, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingController(rootView: view)
        let fitted = host.sizeThatFits(in: NSSize(width: 560, height: 0))
        #expect(fitted.width == 560)
        #expect(fitted.height < 90)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(fitted)
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutSubtreeIfNeeded()
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/darkbloom-switch-warmup-feedback.png"))
    }

    @Test("three-column popup cards fit populated readings and long names", arguments: [false, true])
    func populatedPopupCards(dark: Bool) async throws {
        let ids = ["EigenLabs/Qwen3.8-27B-4bit-mtp", "gemma-4-26b-qat-4bit",
                   "qwen3-vl-30b-a3b-instruct", "qwen3.5-35b-a3b",
                   "qwen3.6-35b-a3b-vl-mtp-mxfp8", "nvidia-nemotron-3.5-lightning",
                   "ternary-bonsai-2-27b", "qwen3.5-9b"]
        let view = LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(ids, id: \.self) { id in
                CompactModelCard(modelID: id, status: "Loaded · idle", tint: .orange,
                    metrics: [
                        ModelCardMetric(id: "speed", symbol: "speedometer", value: "124.7", caption: "avg tok/s today"),
                        ModelCardMetric(id: "earnings", symbol: "dollarsign.circle", value: "$0.0124", caption: "est. net / active h")
                    ], compact: true)
            }
        }.padding(16).frame(width: 560)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingController(rootView: view)
        let fitted = host.sizeThatFits(in: NSSize(width: 560, height: 0))
        #expect(fitted.width == 560)
        #expect(fitted.height < 500)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(fitted)
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutSubtreeIfNeeded()
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/darkbloom-popup-cards-\(dark ? "dark" : "light").png"))
    }

    @Test("network demand rows include enabled models only and rank urgent work first")
    func networkDemandRows() throws {
        let capacity = try NetworkCapacityParser.parse(
            Data(#"{"models":[{"id":"low","ready":true,"can_accept":true,"routable_providers":10,"warm_providers":10,"running_providers":0,"cold_providers":0,"active_requests":0,"queued_requests":0,"queue_limit":8,"aggregate_tps":10,"estimated_ttft_ms":1,"token_budget_remaining":1,"token_budget_total":1},{"id":"urgent","ready":true,"can_accept":true,"routable_providers":10,"warm_providers":4,"running_providers":2,"cold_providers":6,"active_requests":5,"queued_requests":1,"queue_limit":8,"aggregate_tps":120.5,"estimated_ttft_ms":300,"token_budget_remaining":900,"token_budget_total":1000},{"id":"disabled","ready":true,"can_accept":true,"routable_providers":1,"warm_providers":0,"running_providers":0,"cold_providers":1,"active_requests":3,"queued_requests":0,"queue_limit":8,"aggregate_tps":0,"estimated_ttft_ms":1,"token_budget_remaining":1,"token_budget_total":1}]}"#.utf8),
            capturedAt: layoutNow
        )

        let rows = PopupNetworkDemandPresentation.rows(
            capacity: capacity,
            enabledModelIDs: ["low", "urgent"]
        )

        #expect(rows.map(\.id) == ["urgent", "low"])
        #expect(rows.first?.band == .urgent)
        #expect(rows.first?.activeRequests == 5)
        #expect(rows.first?.queuedRequests == 1)
        #expect(rows.first?.warmProviders == 4)

        #expect(PopupNetworkDemandPresentation.row(for: "urgent", in: capacity) == rows.first)
        #expect(PopupNetworkDemandPresentation.row(for: "disabled", in: capacity)?.band == .urgent)
        #expect(PopupNetworkDemandPresentation.row(for: "missing", in: capacity) == nil)
    }

    @Test("network demand presentation ages an available sample without a refresh")
    func networkDemandFreshnessAgesWithTime() {
        let capturedAt = Date(timeIntervalSince1970: 2_000_000)
        let capacity = NetworkCapacitySnapshot(models: [], capturedAt: capturedAt)
        let available = SourceAvailability<NetworkCapacitySnapshot>.available(
            value: capacity,
            capturedAt: capturedAt
        )

        #expect(
            PopupNetworkDemandPresentation.freshness(
                of: available,
                at: capturedAt.addingTimeInterval(NetworkCapacitySnapshot.maximumAge)
            ) == .current
        )
        #expect(
            PopupNetworkDemandPresentation.freshness(
                of: available,
                at: capturedAt.addingTimeInterval(NetworkCapacitySnapshot.maximumAge + 1)
            ) == .stale
        )
    }

    @Test("network demand refresh failures remain visibly stale")
    func networkDemandRefreshFailureIsStale() {
        let capturedAt = Date(timeIntervalSince1970: 2_000_000)
        let capacity = NetworkCapacitySnapshot(models: [], capturedAt: capturedAt)
        let stale = SourceAvailability<NetworkCapacitySnapshot>.stale(
            value: capacity,
            capturedAt: capturedAt,
            reason: "Network demand refresh failed"
        )

        #expect(
            PopupNetworkDemandPresentation.freshness(
                of: stale,
                at: capturedAt
            ) == .stale
        )
    }

    @Test("popup earnings metrics share the same calendar-day observation")
    func popupEarningsMetrics() {
        let metrics = PopupEarningsMetrics.make(from: ObservedEarningsWindow(
            microUSD: 600_000,
            observedSeconds: 10_800
        ))

        #expect(metrics?.totalUSD == 0.6)
        #expect(abs((metrics?.perHourUSD ?? 0) - 0.2) < 0.000_001)
        #expect(PopupEarningsMetrics.make(from: nil) == nil)
    }

    @Test("weekly earnings label distinguishes complete and partial calendar coverage")
    func popupWeeklyEarningsMetric() {
        #expect(PopupWeekEarningsMetric.make(from: CalendarWeekEarningsSummary(
            microUSD: 4_250_000,
            isComplete: true
        )) == PopupWeekEarningsMetric(title: "This week", totalUSD: 4.25))
        #expect(PopupWeekEarningsMetric.make(from: CalendarWeekEarningsSummary(
            microUSD: 3_125_000,
            isComplete: false
        )) == PopupWeekEarningsMetric(title: "Observed this week", totalUSD: 3.125))
        #expect(PopupWeekEarningsMetric.make(from: nil) == nil)
    }

    @Test("each downloaded-model label stays visually grouped with its own switch")
    func modelOptionToggleGrouping() {
        #expect(ModelOptionToggle.order == .switchThenLabel)
        #expect(ModelOptionToggle.groupSpacing > ModelOptionToggle.labelSpacing * 3)
    }

    @Test("popup excludes catalog-only models from the provider filter")
    func popupShowsAllEnabledModels() throws {
        let modelIDs = ["qwen-new-a", "qwen-new-b", "model-c", "model-d", "model-e", "model-f"]
        let selection = ProviderModelSelection(enabled: modelIDs, preloaded: Array(modelIDs.prefix(2)))
        let catalog = modelIDs.map {
            CatalogModel(
                id: $0,
                displayName: $0,
                family: $0,
                modelType: "llm",
                capabilities: ["text"],
                sizeGB: 1,
                minimumRAMGB: 4,
                active: true
            )
        }
        let inventory = ModelInventoryBuilder.build(
            catalog: catalog,
            local: modelIDs.prefix(5).map {
                LocalModel(id: $0, modelType: "llm", sizeBytes: 1, estimatedMemoryGB: 1)
            },
            selection: selection,
            daemon: nil,
            loadedModels: Array(modelIDs.prefix(2))
        )
        let draft = ProviderConfigDraft(
            sourceRevision: "six-enabled-two-warm",
            original: selection,
            selection: selection,
            originalMaxModelSlots: 2,
            maxModelSlots: 2
        )
        let control = ProviderControlSnapshot(
            inventory: inventory,
            draft: draft,
            residentModelIDs: Set(modelIDs.prefix(2)),
            capturedAt: layoutNow,
            sources: .allFresh
        )

        let presentation = PopupModelPresentation.make(
            input: PopupModelSourceInput(
                daemonState: .unavailable(reason: "unused"),
                loadedModels: .unavailable(reason: "unused"),
                status: .unavailable(reason: "unused"),
                controlSnapshot: control
            ),
            currentTime: layoutNow
        )
        guard case .models(let models) = presentation else {
            Issue.record("Expected popup model badges")
            return
        }

        #expect(Set(models.map(\.name)) == Set(modelIDs.prefix(5)))
        #expect(models.filter { $0.state == .loadedIdle }.map(\.name) == Array(modelIDs.prefix(2)))
        #expect(models.filter { $0.state == .availableUnloaded }.count == 3)
    }

    @Test("popup labels fresh auto-select status as automatic")
    func popupAutomaticModelMode() {
        var automatic = StatusSnapshot()
        automatic.configuredModel = "auto-select"
        var pinned = StatusSnapshot()
        pinned.configuredModel = "gemma-4-26b-qat-4bit"

        #expect(PopupModelModePresentation.make(
            status: .available(value: automatic, capturedAt: layoutNow),
            currentTime: layoutNow
        ) == .automatic)
        #expect(PopupModelModePresentation.make(
            status: .available(value: automatic, capturedAt: layoutNow),
            currentTime: layoutNow.addingTimeInterval(60)
        ) == .automatic)
        #expect(PopupModelModePresentation.make(
            status: .available(value: automatic, capturedAt: layoutNow),
            currentTime: layoutNow.addingTimeInterval(60.001)
        ) == .unavailable)
        #expect(PopupModelModePresentation.make(
            status: .available(value: pinned, capturedAt: layoutNow),
            currentTime: layoutNow
        ) == .unavailable)
        #expect(PopupModelModePresentation.make(
            status: .stale(value: automatic, capturedAt: layoutNow, reason: "Status refresh required"),
            currentTime: layoutNow
        ) == .unavailable)
    }

    @Test("unloaded enabled models explain that they load on demand")
    func popupOnDemandModelStatus() {
        #expect(PopupModelStatusPresentation.make(for: .availableUnloaded) == .init(
            statusName: "on demand",
            supplementaryLabel: "On demand",
            systemImage: "arrow.triangle.2.circlepath"
        ))
        #expect(PopupModelStatusPresentation.make(for: .loadedIdle) == .init(
            statusName: "loaded but idle",
            supplementaryLabel: nil,
            systemImage: nil
        ))
        #expect(PopupModelStatusPresentation.make(for: .active) == .init(
            statusName: "active",
            supplementaryLabel: nil,
            systemImage: nil
        ))
    }

    @Test("Bloomy mascot loads as a tintable vector asset")
    func bloomyLogoAsset() throws {
        let sourceImage = try #require(DarkbloomLogoAsset.sourceImage)
        let greenImage = try #require(DarkbloomLogoAsset.menuBarImage(tint: .systemGreen))
        let redImage = try #require(DarkbloomLogoAsset.menuBarImage(tint: .systemRed))
        let green = try #require(sampledMarkColor(in: greenImage))
        let red = try #require(sampledMarkColor(in: redImage))

        #expect(sourceImage.size == NSSize(width: 18, height: 18))
        #expect(!greenImage.isTemplate)
        #expect(greenImage.size == NSSize(width: 18, height: 18))
        #expect(green.greenComponent > green.redComponent)
        #expect(green.greenComponent > green.blueComponent)
        #expect(red.redComponent > red.greenComponent)
        #expect(red.redComponent > red.blueComponent)
    }

    @Test("model-family vectors render distinctly at menu-bar size")
    func modelFamilyAssets() throws {
        var rendered: [Data] = []
        let strip = NSImage(size: NSSize(width: 192, height: 24))
        strip.lockFocus()
        for (index, family) in [ModelFamilyIcon.darkbloom, .qwen, .openai, .google, .nvidia, .prismml].enumerated() {
            let image = try #require(DarkbloomLogoAsset.menuBarImage(tint: .systemGreen, family: family))
            #expect(image.size.width > 0 && image.size.height > 0)
            let color = try #require(sampledMarkColor(in: image))
            #expect(color.greenComponent > color.redComponent)
            rendered.append(try #require(image.tiffRepresentation))
            image.draw(in: NSRect(x: index * 32 + 8, y: 3, width: 16, height: 18))
        }
        strip.unlockFocus()
        #expect(Set(rendered).count == 6)
        if ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" {
            let data = try #require(strip.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/darkbloom-model-icons.png"))
        }
    }

    @Test("menu bar label keeps the official logo within status-item bounds")
    func menuBarLogoSize() {
        let hostingController = NSHostingController(
            rootView: DarkbloomLogo(
                image: DarkbloomLogoAsset.menuBarImage(tint: .systemGreen),
                tint: .green
            )
            .frame(width: 12.25, height: 14)
        )
        let size = hostingController.sizeThatFits(in: NSSize(width: 500, height: 500))

        #expect(size.width <= 13)
        #expect(size.height <= 15)
    }

    @Test("single-line menu metric remains readable and stable across modes")
    func stableReadableMetric() {
        let throughput = NSHostingController(rootView: MenuBarMetric(text: "41.9 tok/s"))
        let earnings = NSHostingController(rootView: MenuBarMetric(text: "$2.90/24h"))
        let unavailable = NSHostingController(rootView: MenuBarMetric(text: nil))
        let proposed = NSSize(width: 500, height: 100)
        let expected = throughput.sizeThatFits(in: proposed)

        #expect(earnings.sizeThatFits(in: proposed) == expected)
        #expect(unavailable.sizeThatFits(in: proposed) == expected)
        #expect(expected.width == 72)
        #expect(expected.height <= 19)
    }

    @Test("calendar earnings keep the compact menu dimensions")
    func calendarMetricSize() async throws {
        let presentation = MenuBarPresentation.make(snapshot: .unavailable(now: layoutNow), thermal: .nominal,
            earnings: .day(microUSD: 2_640_000, complete: false), mode: .earnings)
        let host = NSHostingController(rootView: MenuBarLabel(presentation: presentation,
            uptime: .available(percent: 100, observedSeconds: 600)))
        #expect(host.sizeThatFits(in: NSSize(width: 500, height: 100)) == NSSize(width: 72, height: 18))
        #expect(presentation.metricText == "$2.64/d*")
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 72, height: 18))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutSubtreeIfNeeded()
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-calendar-menu.png"]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }

    @Test("menu bar label scales icon spacing and metric as one readable unit")
    func readableLabelScale() {
        let presentation = MenuBarPresentation.make(
            snapshot: .unavailable(now: Date(timeIntervalSince1970: 1_750_000_000)),
            thermal: .nominal,
            earnings: .available(microUSD: 2_640_000),
            mode: .automatic
        )
        let hostingController = NSHostingController(rootView: MenuBarLabel(
            presentation: presentation,
            uptime: .available(percent: 100, observedSeconds: 600)
        ))

        let size = hostingController.sizeThatFits(in: NSSize(width: 500, height: 100))

        #expect(size.width == 72)
        #expect(size.height == 18)
    }

    @Test("native status item owns one fixed width")
    func nativeStatusItemWidth() {
        let suite = "StatusNavigationTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = TelemetryService(source: UnusedTelemetrySource())
        let store = MonitorStore(
            service: service,
            initial: .unavailable(now: Date(timeIntervalSince1970: 1_750_000_000))
        )
        let controller = StatusItemController(store: store, defaults: defaults)

        #expect(controller.statusItemLength == 80)
        #expect(controller.dashboardWindowController == nil)
        controller.showDashboard(activate: false)
        let firstWindow = controller.dashboardWindowController?.window
        controller.showSettings(activate: false)
        #expect(controller.dashboardWindowController?.window === firstWindow)
        #expect(controller.dashboardWindowController?.navigation.selected == .settings)
        controller.invalidate()
        #expect(controller.popoverContentSize.width == 560)
        #expect(controller.popoverContentSize.height > 0)
    }

    @Test("popover placement uses its complete content height after content changes")
    func fittingPopoverPlacementSize() {
        let popover = NSPopover()
        let host = FittingPopoverHostingController(
            rootView: Color.clear.frame(width: 560, height: 605), popover: popover
        )
        popover.contentViewController = host
        host.prepareForPresentation()
        #expect(popover.contentSize == NSSize(width: 560, height: 605))
        #expect(host.sizingOptions == .preferredContentSize)

        host.content = Color.clear.frame(width: 560, height: 781.25)
        host.prepareForPresentation()
        #expect(popover.contentSize == NSSize(width: 560, height: 782))
        host.content = Color.clear.frame(width: 560, height: 605)
        host.prepareForPresentation()
        #expect(popover.contentSize == NSSize(width: 560, height: 605))
    }

    @Test("popup screen budget respects the actual anchor and excludes placement space")
    func popupScreenBudget() {
        let screen = NSRect(x: -1_000, y: 50, width: 1_000, height: 600)
        let menuAnchor = NSRect(x: -100, y: 650, width: 80, height: 24)
        #expect(PopupPresentationBudget.maximumContentHeight(visibleFrame: screen, anchorFrame: menuAnchor) == 580)
        let middleAnchor = NSRect(x: -100, y: 330, width: 80, height: 24)
        #expect(PopupPresentationBudget.maximumContentHeight(visibleFrame: screen, anchorFrame: middleAnchor) == 276)
        #expect(PopupPresentationBudget.maximumContentHeight(visibleFrame: screen, anchorFrame: nil) == 580)
        #expect(PopupPresentationBudget.maximumContentHeight(visibleFrame: nil, anchorFrame: menuAnchor) == nil)
        #expect(PopupPresentationBudget.maximumContentHeight(visibleFrame: .zero, anchorFrame: menuAnchor) == nil)
        #expect(PopupPresentationBudget.maximumContentHeight(
            visibleFrame: NSRect(x: 0, y: 0, width: 560, height: 40), anchorFrame: nil) == 20)
        #expect(PopupPresentationBudget.maximumContentHeight(
            visibleFrame: NSRect(x: 0, y: 0, width: 560, height: CGFloat.infinity), anchorFrame: nil) == nil)
    }

    @Test("popup body yields to chrome and retains a useful scroller for the tiny-screen fallback")
    func popupBodyBudget() {
        #expect(PopupContentLayout.fittedBodyHeight(requested: 470, chromeHeight: 226, maximumHeight: nil) == 470)
        #expect(PopupContentLayout.fittedBodyHeight(requested: 470, chromeHeight: 226, maximumHeight: 800) == 470)
        #expect(PopupContentLayout.fittedBodyHeight(requested: 470, chromeHeight: 226, maximumHeight: 500) == 262)
        #expect(PopupContentLayout.fittedBodyHeight(requested: 366, chromeHeight: 226, maximumHeight: 500) == 262)
        // The outer viewport scrolls everything at this size; the nested body
        // remains usable when it comes into view, rather than collapsing to 0.
        #expect(PopupContentLayout.fittedBodyHeight(requested: 470, chromeHeight: 226, maximumHeight: 200) == 470)
        #expect(PopupContentLayout.fittedBodyHeight(requested: .nan, chromeHeight: 226, maximumHeight: 500) == 0)
        #expect(PopupContentLayout.fittedBodyHeight(requested: 366, chromeHeight: 226, maximumHeight: .infinity) == 366)
    }

    @Test("the real popup fits small viewports with collapsed and expanded content", arguments: [20.0, 80.0, 360.0, 580.0, 1_400.0])
    func popupFitsScreenBudget(height: Double) async throws {
        let suite = "Darkbloom.PopupHeight.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "popover.availableExpanded")
        let now = Date()
        let modelIDs = ["model-a", "model-b", "model-c", "model-d", "model-e", "model-f"]
        let selectedIDs = Array(modelIDs.prefix(3))
        let store = MonitorStore(service: TelemetryService(
            source: AutoModeTelemetrySource(now: now, modelIDs: selectedIDs, warmCount: 1), now: { now }),
            initial: .unavailable(now: now), now: { now })
        await store.refreshTelemetryImmediately()
        let controlStore = ProviderControlStore(controller: InertSettingsController(
            sources: .unknown, savedIDs: selectedIDs, slots: 1, downloadedIDs: modelIDs))
        await controlStore.refresh()
        // Rendering uses the real clock. A busy full test run can age the frozen
        // telemetry, so the saved fallback must retain the same selected rows.
        let savedIDs = try #require(controlStore.snapshot?.inventory.myCatalog.filter(\.isEnabled).map(\.catalogID).sorted())
        #expect(PopupModelGroups.advertised(snapshot: store.snapshot, control: controlStore.snapshot, now: now) == selectedIDs)
        #expect(PopupModelGroups.advertised(snapshot: store.snapshot, control: controlStore.snapshot, now: now.addingTimeInterval(11)) == nil)
        for renderTime in [now, now.addingTimeInterval(11)] {
            let selected = PopupModelGroups.advertised(snapshot: store.snapshot, control: controlStore.snapshot, now: renderTime) ?? savedIDs
            #expect(selected == selectedIDs)
            #expect(Set(modelIDs).subtracting(selected).count == 3)
        }
        let popover = NSPopover()
        let host = FittingPopoverHostingController(rootView: MonitorPopover(store: store, isVisible: false)
            .environmentObject(controlStore).defaultAppStorage(defaults).id(false), popover: popover)
        popover.contentViewController = host
        var collapsedHeight: CGFloat?
        for expanded in [false, true, false] {
            defaults.set(expanded, forKey: "popover.availableExpanded")
            host.content = MonitorPopover(store: store, isVisible: false)
                .environmentObject(controlStore).defaultAppStorage(defaults).id(expanded)
            host.prepareForPresentation(maximumContentHeight: height)
            let fitted = host.sizeThatFits(in: NSSize(width: 560, height: 0))
            #expect(fitted.width == 560)
            #expect(fitted.height > 0)
            #expect(fitted.height <= height)
            #expect(popover.contentSize.width == 560)
            #expect(popover.contentSize.height <= height)
            if height == 80 {
                host.view.frame = NSRect(origin: .zero, size: fitted)
                host.view.layoutSubtreeIfNeeded()
                await Task.yield()
                host.view.layoutSubtreeIfNeeded()
                let scrollViews = nativeScrollViews(in: host.view)
                let outer = try #require(scrollViews.first(where: { $0.accessibilityIdentifier() == "popover.outerScroll" }))
                let document = try #require(outer.documentView)
                #expect(document.frame.height > outer.contentView.bounds.height)
                #expect(outer.hasVerticalScroller)
                #expect(outer.scrollerStyle == .overlay)
                #expect(outer.contentView.bounds.width == 528)
                #expect(document.frame.width == outer.contentView.bounds.width)
                let original = outer.documentVisibleRect.origin
                let destination = original.y > 0 ? 0 : min(80, document.frame.height - outer.contentView.bounds.height)
                outer.contentView.scroll(to: NSPoint(x: original.x, y: destination))
                outer.reflectScrolledClipView(outer.contentView)
                #expect(outer.documentVisibleRect.origin.y != original.y)
            }
            if height == 1_400 {
                if expanded { #expect(fitted.height > (collapsedHeight ?? 0)) }
                else if let collapsedHeight { #expect(fitted.height == collapsedHeight) }
                else { collapsedHeight = fitted.height }
            }
        }
    }

    @Test("fresh and stale model settings fit without horizontal growth")
    func modelSettingsFitMinimumSize() async {
        let states: [(ProviderControlSourceStates, Bool, Bool, String)] = [
            (.allFresh, true, true, "Shows a confirmation before removing the downloaded files for Downloaded Model."),
            (ProviderControlSourceStates(
                catalog: .stale("Catalog refresh required"),
                localModels: .fresh(evidenceAt: layoutNow),
                daemon: .fresh(evidenceAt: layoutNow),
                loadedModels: .fresh(evidenceAt: layoutNow)
            ), false, false,
             "Catalog refresh required; Reload the model catalog before deleting this model."),
            (ProviderControlSourceStates(
                catalog: .fresh(evidenceAt: layoutNow),
                localModels: .stale("Local model refresh required"),
                daemon: .fresh(evidenceAt: layoutNow),
                loadedModels: .fresh(evidenceAt: layoutNow)
            ), false, false,
             "Local model refresh required; Reload local models before deleting this model."),
            (ProviderControlSourceStates(
                catalog: .fresh(evidenceAt: layoutNow),
                localModels: .fresh(evidenceAt: layoutNow),
                daemon: .stale("Provider activity refresh required"),
                loadedModels: .fresh(evidenceAt: layoutNow)
            ), true, false,
             "Provider activity refresh required; Refresh provider activity before deleting this model."),
            (ProviderControlSourceStates(
                catalog: .fresh(evidenceAt: layoutNow),
                localModels: .fresh(evidenceAt: layoutNow),
                daemon: .fresh(evidenceAt: layoutNow),
                loadedModels: .unavailable("Loaded model state unavailable")
            ), true, false,
             "Loaded model state unavailable; Refresh loaded model state before deleting this model."),
        ]
        let proposed = NSSize(width: 680, height: 560)

        for (sources, expectedCanDownload, expectedCanDelete, expectedDeleteHelp) in states {
            let controlStore = ProviderControlStore(
                controller: InertSettingsController(sources: sources)
            )
            await controlStore.refresh()
            let hostingController = NSHostingController(
                rootView: MonitorSettingsView()
                    .environmentObject(controlStore)
            )
            let fitted = hostingController.sizeThatFits(in: proposed)
            let availableItem = controlStore.snapshot?.inventory.available.first
            let row = availableItem.map {
                ModelManagerPresentation.availableRow(item: $0, store: controlStore)
            }
            let downloadedItem = controlStore.snapshot?.inventory.myCatalog.first
            let downloadedRow = downloadedItem.map {
                ModelRowPresentation.make(
                    item: $0,
                    draft: controlStore.draft,
                    operation: controlStore.operation,
                    sources: sources,
                    currentTime: layoutNow,
                    canDownload: false,
                    downloadUnavailableReason: nil,
                    sanitize: controlStore.sanitizedDiagnostic
                )
            }

            #expect(controlStore.canDownload("available-model") == expectedCanDownload)
            #expect(row?.downloadAction?.isEnabled == expectedCanDownload)
            #expect(row?.downloadAction?.accessibilityLabel == "Download Available Model")
            #expect(downloadedRow?.deleteAction?.isEnabled == expectedCanDelete)
            #expect(downloadedRow?.deleteAction?.accessibilityHint == expectedDeleteHelp)
            #expect(fitted.width == proposed.width)
            #expect(fitted.height == proposed.height)
        }
    }

    @Test("machine and model popover has a bounded scrollable viewport")
    func hasCompactViewport() async throws {
        let service = TelemetryService(source: UnusedTelemetrySource())
        let store = MonitorStore(
            service: service,
            initial: .unavailable(now: Date(timeIntervalSince1970: 1_750_000_000))
        )
        let controlStore = ProviderControlStore(controller: InertSettingsController())
        await controlStore.refresh()
        let hostingController = NSHostingController(
            rootView: MonitorPopover(store: store)
                .environmentObject(controlStore)
        )
        let proposedSize = hostingController.sizeThatFits(
            in: NSSize(width: 400, height: 0)
        )

        #expect(proposedSize.width == 560)
        #expect(proposedSize.height < 650)
        if ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" {
            let window = NSWindow(contentViewController: hostingController)
            window.isReleasedWhenClosed = false
            window.setContentSize(proposedSize)
            window.orderBack(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(200))
            let view = hostingController.view
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/darkbloom-compact-popup.png"))
        }
    }

    @Test("automatic mode and offline selections fit the production popup width", arguments: [false, true])
    func automaticModePopupLayout(offline: Bool) async throws {
        let modelIDs = [
            "EigenLabs/Qwen3.8-27B-4bit-mtp",
            "gemma-4-26b-qat-4bit",
            "qwen3.6-35b-a3b-vl-mtp-mxfp8",
        ]
        let now = Date()
        let service = TelemetryService(
            source: AutoModeTelemetrySource(now: now, modelIDs: modelIDs, offline: offline, warmCount: 1),
            now: { now }
        )
        let store = MonitorStore(
            service: service,
            initial: .unavailable(now: now),
            now: { now }
        )
        await store.refreshTelemetryImmediately()
        let controlStore = ProviderControlStore(
            controller: InertSettingsController(sources: offline ? .allFresh : .unknown,
                                               savedIDs: offline ? modelIDs : [], slots: 1)
        )
        await controlStore.refresh()
        let hostingController = NSHostingController(
            rootView: MonitorPopover(store: store)
                .environmentObject(controlStore)
        )
        let fitted = hostingController.sizeThatFits(in: NSSize(width: 560, height: 0))

        #expect(fitted.width == 560)
        #expect(fitted.height <= 700)
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let window = NSWindow(contentViewController: hostingController)
        window.isReleasedWhenClosed = false
        window.setContentSize(fitted)
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        let view = hostingController.view
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/darkbloom-\(offline ? "offline" : "auto")-model-popup.png"))
    }

    @Test("lifecycle controls bind to an inert shared store and remain compact")
    func lifecycleControlsFit() async {
        let controlStore = ProviderControlStore(controller: InertSettingsController())
        await controlStore.refresh()
        let hostingController = NSHostingController(
            rootView: ProviderLifecycleControls(
                store: controlStore,
                snapshot: .unavailable(now: Date(timeIntervalSince1970: 1_750_000_000))
            )
        )

        let fitted = hostingController.sizeThatFits(in: NSSize(width: 220, height: 40))

        #expect(fitted.width <= 220)
        #expect(fitted.height <= 64)
    }

    @Test("disabled lifecycle controls keep their inline reason in a compact layout")
    func lifecycleControlsShowInlineReason() async {
        let controlStore = ProviderControlStore(
            controller: InertSettingsController(sources: .unknown)
        )
        await controlStore.refresh()
        let hostingController = NSHostingController(
            rootView: ProviderLifecycleControls(
                store: controlStore,
                snapshot: .unavailable(now: Date(timeIntervalSince1970: 1_750_000_000)),
                currentTime: Date(timeIntervalSince1970: 1_750_000_000)
            )
        )

        let fitted = hostingController.sizeThatFits(in: NSSize(width: 220, height: 64))

        #expect(
            ProviderLifecycleUnavailableReasonPresentation.make(
                from: .init(
                    canStart: false,
                    canStop: false,
                    canRestart: false,
                    unavailableReason: "Provider state is unavailable"
                )
            )?.message == "Provider state is unavailable"
        )
        #expect(fitted.width <= 220)
        #expect(fitted.height <= 64)
    }
}

private func sampledMarkColor(in image: NSImage) -> NSColor? {
    let scale = 10
    let width = Int(image.size.width * CGFloat(scale))
    let height = Int(image.size.height * CGFloat(scale))
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }
    bitmap.size = image.size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()

    return bitmap.colorAt(x: width / 10, y: height / 2)?.usingColorSpace(.deviceRGB)
}

@MainActor
private func nativeScrollViews(in view: NSView) -> [NSScrollView] {
    ((view as? NSScrollView).map { [$0] } ?? [])
        + view.subviews.flatMap { nativeScrollViews(in: $0) }
}

private struct UnusedTelemetrySource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw UnusedError() }
    func readLoadedModels() async throws -> LoadedModelsState { throw UnusedError() }
    func readStatus() async throws -> StatusSnapshot { throw UnusedError() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw UnusedError() }
}

private actor AutoModeTelemetrySource: TelemetrySource {
    let now: Date
    let modelIDs: [String]
    let offline: Bool
    let warmCount: Int

    init(now: Date, modelIDs: [String], offline: Bool = false, warmCount: Int = 2) {
        self.now = now
        self.modelIDs = modelIDs
        self.offline = offline
        self.warmCount = warmCount
    }

    func readDaemonState() async throws -> DaemonState {
        if offline { throw UnusedError() }
        let timestamp = now.timeIntervalSince1970
        return DaemonState(
            schema: 1,
            version: "0.9.11",
            currentModel: modelIDs[0],
            warmModels: Array(modelIDs.prefix(warmCount)),
            stats: ProviderStats(tokensGenerated: 11_092, requestsServed: 124, usageGaps: 0),
            trust: TrustState(
                level: "hardware",
                status: "online",
                reason: "same_binary",
                receivedAt: timestamp
            ),
            capacity: MemoryCapacity(totalMemoryGB: 192, gpuMemoryActiveGB: 54, gpuMemoryCacheGB: 8),
            slots: [],
            inferenceActive: false,
            startedAt: timestamp - 3_600,
            writtenAt: timestamp,
            pid: 42,
            processIdentity: ProcessIdentity(pid: 42, startTimeMicros: 42_000_000),
            advertisedModels: modelIDs
        )
    }

    func readLoadedModels() async throws -> LoadedModelsState {
        LoadedModelsState(
            schema: 1,
            models: Array(modelIDs.prefix(warmCount)),
            updatedAt: now.timeIntervalSince1970
        )
    }

    func readStatus() async throws -> StatusSnapshot {
        var status = StatusSnapshot()
        status.daemon = offline ? "stopped" : "running"
        status.configuredModel = "auto-select"
        status.enabledModelFilter = modelIDs.joined(separator: ",")
        return status
    }

    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { [] }
}

private struct UnusedError: Error {}

private actor InertSettingsController: ProviderControlling {
    private let value: ProviderControlSnapshot

    init(sources: ProviderControlSourceStates = .allFresh, savedIDs: [String] = [], slots: Int? = nil,
         downloadedIDs: [String]? = nil) {
        let catalogIDs = downloadedIDs ?? savedIDs
        let selection = ProviderModelSelection(enabled: savedIDs, preloaded: [])
        let draft = ProviderConfigDraft(
            sourceRevision: "layout-fixture",
            original: selection,
            selection: selection,
            originalMaxModelSlots: slots,
            maxModelSlots: slots
        )
        let catalog = [
            CatalogModel(
                id: "downloaded-model",
                displayName: "Downloaded Model",
                family: "downloaded",
                modelType: "llm",
                capabilities: ["text", "code"],
                sizeGB: 8.5,
                minimumRAMGB: 16,
                active: true
            ),
            CatalogModel(
                id: "available-model",
                displayName: "Available Model",
                family: "available",
                modelType: "vision-language",
                capabilities: ["vision", "text"],
                sizeGB: 4,
                minimumRAMGB: 8,
                active: true
            ),
        ]
        let inventory = ModelInventoryBuilder.build(
            catalog: catalog + catalogIDs.map { CatalogModel(id: $0, displayName: $0, family: "model", modelType: "llm", capabilities: [], sizeGB: 8, minimumRAMGB: 16, active: true) },
            local: (downloadedIDs == nil ? [LocalModel(
                id: "downloaded-model",
                modelType: "llm",
                sizeBytes: 8_500_000_000,
                estimatedMemoryGB: nil
            )] : []) + catalogIDs.map { LocalModel(id: $0, modelType: "llm", sizeBytes: 8_000_000_000, estimatedMemoryGB: nil) },
            selection: selection,
            daemon: nil,
            loadedModels: []
        )
        value = ProviderControlSnapshot(
            inventory: inventory,
            draft: draft,
            capturedAt: layoutNow,
            sources: sources
        )
    }

    func refresh() async throws -> ProviderControlSnapshot { value }

    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        ProviderConfigSaveResult(draft: draft, restartRequired: draft.hasChanges)
    }

    func download(
        _ modelID: String,
        onOutput: (@Sendable (ProcessOutputChunk) -> Void)?
    ) async throws {
        throw UnusedError()
    }

    func delete(_ localModelID: String) async throws { throw UnusedError() }
    func activityRisk() async -> ProviderActivityRisk { .idle }

    func execute(
        _ action: ProviderLifecycleAction,
        enabledModels: [String]
    ) async throws {
        throw UnusedError()
    }
}

private extension ProviderControlSourceStates {
    static let allFresh = ProviderControlSourceStates(
        catalog: .fresh(evidenceAt: layoutNow),
        localModels: .fresh(evidenceAt: layoutNow),
        daemon: .fresh(evidenceAt: layoutNow),
        loadedModels: .fresh(evidenceAt: layoutNow)
    )
}
