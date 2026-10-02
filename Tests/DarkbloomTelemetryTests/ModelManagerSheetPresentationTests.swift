import AppKit
import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Model manager sheet presentation")
@MainActor
struct ModelManagerSheetPresentationTests {
    @Test("sheet budgets subtract chrome, keep width, and never impose an overflowing minimum",
          arguments: [CGFloat(80), 240, 560, 900])
    func boundedHeight(available: CGFloat) throws {
        let budget = try #require(ModelManagerSheetHeightPolicy.screenBudget(
            visibleHeight: available, windowChromeHeight: 28))
        let height = ModelManagerSheetHeightPolicy.height(screenBudget: budget, hostMaximum: nil)
        #expect(height > 0)
        #expect(height <= budget)
        #expect(height <= ModelManagerSheetHeightPolicy.preferredHeight)
        #expect(budget == max(1, available - 48))
        #expect(ModelManagerSheetHeightPolicy.width == 620)
        // Expanded content cannot raise a host's explicit viewport limit.
        #expect(ModelManagerSheetHeightPolicy.height(screenBudget: budget, hostMaximum: 40) <= 40)
        #expect(ModelManagerSheetHeightPolicy.height(screenBudget: budget, hostMaximum: 2_000) == height)
    }

    @Test("unknown and malformed screen evidence have a finite conservative fallback")
    func missingScreen() {
        for value: CGFloat? in [nil, .nan, .infinity, -.infinity, 0, -1] {
            #expect(ModelManagerSheetHeightPolicy.screenBudget(visibleHeight: value, windowChromeHeight: 0) == nil)
            #expect(ModelManagerSheetHeightPolicy.height(screenBudget: value, hostMaximum: value)
                == ModelManagerSheetHeightPolicy.unknownScreenHeight)
        }
        #expect(ModelManagerSheetHeightPolicy.screenBudget(visibleHeight: 560, windowChromeHeight: .nan) == nil)
        #expect(ModelManagerSheetHeightPolicy.screenBudget(visibleHeight: 20, windowChromeHeight: 100) == 1)
        #expect(ModelManagerSheetHeightPolicy.height(screenBudget: nil, hostMaximum: 80) == 80)
        #expect(ModelManagerSheetHeightPolicy.height(screenBudget: 1, hostMaximum: 80) == 1)
    }

    @Test("current canonical inventory replaces old facts and missing or ambiguous IDs cannot fall back")
    func currentIdentity() {
        let current = item("vendor/original", downloaded: true, state: .active)
        let unrelated = item("vendor/unrelated", downloaded: true)
        #expect(ModelManagerSheetPresentation.make(catalogID: current.catalogID,
            inventory: inventory([current, unrelated])) == .current(current))
        #expect(ModelManagerSheetPresentation.make(catalogID: current.catalogID,
            inventory: inventory([unrelated])) == .unavailable)
        #expect(ModelManagerSheetPresentation.make(catalogID: current.catalogID, inventory: nil) == .unavailable)
        #expect(ModelManagerSheetPresentation.make(catalogID: current.catalogID,
            inventory: inventory([current, current])) == .unavailable)
        let available = item(current.catalogID, downloaded: false)
        #expect(ModelManagerSheetPresentation.make(catalogID: current.catalogID,
            inventory: inventory([], available: [available])) == .current(available))
    }

    @Test("late removed-model callbacks cannot change retained drafts and restoration permits an explicit edit")
    func retainedDraft() async throws {
        let original = item("vendor/original", downloaded: true)
        let unrelated = item("vendor/unrelated", downloaded: true)
        let originalSelection = ProviderModelSelection(enabled: [], preloaded: [])
        let draft = ProviderConfigDraft(sourceRevision: "inert-sheet", original: originalSelection,
            selection: originalSelection, originalMaxModelSlots: 1, maxModelSlots: 1)
        let controller = SheetFixtureController(snapshot: .init(inventory: inventory([original]),
            draft: draft, capturedAt: Date()))
        let store = ProviderControlStore(controller: controller)
        await store.refresh()
        store.setMaxModelSlots(2)
        let retained = try #require(store.draft)
        let lateEnabled = {
            ModelManagerSheetPresentation.editDownloaded(catalogID: original.catalogID, selector: original.catalogID,
                inventory: store.snapshot?.inventory) { store.setEnabled(true, modelID: original.catalogID) }
        }
        let latePreload = {
            ModelManagerSheetPresentation.editDownloaded(catalogID: original.catalogID, selector: original.catalogID,
                inventory: store.snapshot?.inventory) { store.setPreloaded(true, modelID: original.catalogID) }
        }
        for replacement in [inventory([unrelated]), inventory([], available: [item(original.catalogID, downloaded: false)]),
                            inventory([original, original])] {
            await controller.replaceInventory(replacement)
            await store.refreshPreservingDraft()
            #expect(!lateEnabled())
            #expect(!latePreload())
            #expect(store.draft == retained)
        }
        await controller.replaceInventory(inventory([original, unrelated]))
        await store.refreshPreservingDraft()
        #expect(lateEnabled())
        #expect(latePreload())
        #expect(store.draft?.selection == .init(enabled: [original.catalogID], preloaded: [original.catalogID]))
        #expect(store.draft?.sourceRevision == retained.sourceRevision)
        #expect(store.draft?.maxModelSlots == 2)
        #expect(store.draft?.original == retained.original)
        #expect(await controller.mutationCount == 0)
    }

    @Test("a refreshed exact ID cannot hijack an old row's alias", arguments: ["enabled", "preloaded"])
    func aliasHijackAfterRefresh(kind: String) async throws {
        let originalID = "gpt-oss-20b"
        let alias = "gpt-oss"
        let firstCatalog = [catalog(originalID, family: alias)]
        let selection = ProviderModelSelection(enabled: [alias], preloaded: [alias])
        let originalInventory = builtInventory(firstCatalog, selection: selection)
        let originalItem = try #require(originalInventory.myCatalog.first)
        #expect(originalItem.enabledSelector == alias)
        #expect(originalItem.preloadSelector == alias)
        let fixture = fixtureStore(inventory: originalInventory, selection: selection)
        let store = fixture.store
        await store.refresh()
        // Capture the old row's canonical ID and selector, but read current
        // inventory and draft at the moment the queued callback is delivered.
        let lateToggle = {
            self.stage(false, kind: kind, catalogID: originalID, selector: alias, store: store)
        }
        let replacement = builtInventory(firstCatalog + [catalog(alias, family: "another-family")], selection: selection)
        #expect(replacement.myCatalog.first(where: { $0.catalogID == originalID })?.issue == nil)
        #expect(replacement.myCatalog.first(where: { $0.catalogID == alias })?.enabledSelector == alias)
        await fixture.controller.replaceInventory(replacement)
        await store.refreshPreservingDraft()
        let refreshedDraft = try #require(store.draft)
        #expect(store.draftValidationMessage == nil)
        #expect(!lateToggle())
        #expect(store.draft == refreshedDraft)
        #expect(store.draft?.selection == selection)
        #expect(store.draft?.hasChanges == false)
        // The same raw selector is legitimate only for the new exact model.
        #expect(stage(false, kind: kind, catalogID: alias, selector: alias, store: store))
        if kind == "enabled" {
            #expect(store.draft?.selection.enabled.isEmpty == true)
            #expect(store.draft?.selection.preloaded == [alias])
        } else {
            #expect(store.draft?.selection.preloaded.isEmpty == true)
            #expect(store.draft?.selection.enabled == [alias])
        }
        #expect(await fixture.controller.mutationCount == 0)
    }

    @Test("valid independent aliases stage only the requested toggle without normalizing selectors",
          arguments: ["enabled", "preloaded"])
    func validAliases(kind: String) async throws {
        let id = "gpt-oss-20b"
        let alias = "gpt-oss"
        // Each selection array can use a different spelling for the same model.
        let selection = kind == "enabled"
            ? ProviderModelSelection(enabled: [alias], preloaded: [id])
            : ProviderModelSelection(enabled: [id], preloaded: [alias])
        let fixture = fixtureStore(inventory: builtInventory([catalog(id, family: alias)], selection: selection),
            selection: selection)
        let store = fixture.store
        await store.refresh()
        let original = try #require(store.draft)
        let selector = alias
        #expect(!stage(false, kind: kind, catalogID: id, selector: "unresolved-old-alias", store: store))
        #expect(store.draft == original)
        #expect(stage(false, kind: kind, catalogID: id, selector: selector, store: store))
        if kind == "enabled" {
            #expect(store.draft?.selection.enabled.isEmpty == true)
            #expect(store.draft?.selection.preloaded == original.selection.preloaded)
        } else {
            #expect(store.draft?.selection.preloaded.isEmpty == true)
            #expect(store.draft?.selection.enabled == original.selection.enabled)
        }
        #expect(stage(true, kind: kind, catalogID: id, selector: selector, store: store))
        #expect(store.draft == original)
        #expect(await fixture.controller.mutationCount == 0)
    }

    private func stage(_ value: Bool, kind: String, catalogID: String, selector: String, store: ProviderControlStore) -> Bool {
        ModelManagerSheetPresentation.editDownloaded(catalogID: catalogID, selector: selector,
            inventory: store.snapshot?.inventory) {
                if kind == "enabled" { store.setEnabled(value, modelID: selector) }
                else { store.setPreloaded(value, modelID: selector) }
            }
    }
    private func catalog(_ id: String, family: String) -> CatalogModel {
        .init(id: id, displayName: id, family: family, modelType: "llm", capabilities: [],
            sizeGB: 1, minimumRAMGB: 4, active: true)
    }
    private func builtInventory(_ catalog: [CatalogModel], selection: ProviderModelSelection) -> ModelInventory {
        ModelInventoryBuilder.build(catalog: catalog, local: catalog.map {
            .init(id: $0.id, modelType: "llm", sizeBytes: 1024, estimatedMemoryGB: 4)
        }, selection: selection, daemon: nil, loadedModels: [])
    }
    private func fixtureStore(inventory: ModelInventory, selection: ProviderModelSelection)
        -> (store: ProviderControlStore, controller: SheetFixtureController) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = ProviderConfigDraft(sourceRevision: "inert-selector", original: selection, selection: selection)
        let controller = SheetFixtureController(snapshot: .init(inventory: inventory, draft: draft, capturedAt: now,
            sources: .init(catalog: .fresh(evidenceAt: now), localModels: .fresh(evidenceAt: now),
                daemon: .fresh(evidenceAt: now), loadedModels: .fresh(evidenceAt: now))))
        return (ProviderControlStore(controller: controller, now: { now }), controller)
    }

    private func item(_ id: String, downloaded: Bool, state: InventoryLiveState = .unloaded) -> ModelInventoryItem {
        .init(catalogID: id, localID: downloaded ? id : nil, displayName: id, modelType: "llm",
            capabilities: [], sizeGB: 1, minimumRAMGB: 4, isDownloaded: downloaded,
            isEnabled: false, isPreloaded: false, liveState: state, issue: nil)
    }
    private func inventory(_ downloaded: [ModelInventoryItem], available: [ModelInventoryItem] = []) -> ModelInventory {
        .init(myCatalog: downloaded, available: available, issues: [])
    }
}

private actor SheetFixtureController: ProviderControlling {
    var snapshot: ProviderControlSnapshot
    private(set) var mutationCount = 0
    init(snapshot: ProviderControlSnapshot) { self.snapshot = snapshot }
    func replaceInventory(_ inventory: ModelInventory) {
        snapshot = .init(inventory: inventory, draft: snapshot.draft, capturedAt: snapshot.capturedAt,
            sources: snapshot.sources)
    }
    func refresh() async throws -> ProviderControlSnapshot { snapshot }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult { mutationCount += 1; throw CancellationError() }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws { mutationCount += 1; throw CancellationError() }
    func delete(_ localModelID: String) async throws { mutationCount += 1; throw CancellationError() }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws { mutationCount += 1; throw CancellationError() }
}
