import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("One-slot startup picker aliases")
@MainActor
struct ModelStartupPickerPresentationTests {
    @Test("both independent alias directions select the enabled tag without rewriting the draft",
          arguments: [false, true])
    func preservesIndependentAliases(enabledUsesAlias: Bool) async throws {
        let enabled = enabledUsesAlias ? "gpt-oss" : "gpt-oss-20b"
        let preloaded = enabledUsesAlias ? "gpt-oss-20b" : "gpt-oss"
        let selection = ProviderModelSelection(enabled: [enabled, "other-model"], preloaded: [preloaded])
        let inventory = ModelInventory(myCatalog: [
            item("gpt-oss-20b", enabled: enabled, preloaded: preloaded),
            item("other-model", enabled: "other-model")
        ], available: [], issues: [])
        let store = fixtureStore(selection: selection, inventory: inventory)
        await store.refresh()
        let original = try #require(store.draft)
        let mounted = ModelStartupPickerPresentation.make(selection: original.selection, inventory: inventory)
        #expect(mounted.selectedTag == enabled)
        #expect(store.draft == original)
        mounted.select(enabled, using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        #expect(store.draft?.hasChanges == false)

        await store.refreshPreservingDraft()
        let refreshed = try #require(store.draft)
        let picker = ModelStartupPickerPresentation.make(selection: refreshed.selection, inventory: store.snapshot?.inventory)
        #expect(picker.selectedTag == enabled)
        picker.select(enabled, using: store.setPreferredStartupModel)
        #expect(store.draft == original)

        picker.select("other-model", using: store.setPreferredStartupModel)
        let changed = try #require(store.draft)
        #expect(changed.selection.preloaded == ["other-model"])
        #expect(changed.selection.enabled == original.selection.enabled)
        #expect(changed.original == original.original)
        #expect(changed.sourceRevision == original.sourceRevision)
        #expect(changed.hasChanges)
    }

    @Test("unresolved preferences stay unchanged until an explicit clear",
          arguments: ["unknown", "missing-inventory", "ambiguous"])
    func unresolvedPreferenceIsPreserved(kind: String) async throws {
        let selection: ProviderModelSelection
        let inventory: ModelInventory
        switch kind {
        case "ambiguous":
            selection = .init(enabled: ["first", "second"], preloaded: ["shared"])
            inventory = .init(myCatalog: [item("first", enabled: "first", preloaded: "shared"),
                item("second", enabled: "second", preloaded: "shared")], available: [], issues: [])
        default:
            selection = .init(enabled: ["first"], preloaded: [kind == "unknown" ? "missing" : "first"])
            inventory = .init(myCatalog: [item("first", enabled: "first")], available: [], issues: [])
        }
        let store = fixtureStore(selection: selection, inventory: inventory)
        await store.refresh()
        let original = try #require(store.draft)
        let picker = ModelStartupPickerPresentation.make(selection: original.selection,
            inventory: kind == "missing-inventory" ? nil : inventory)
        #expect(picker.selectedTag == nil)
        picker.select(selection.enabled[0], using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        #expect(store.draft?.hasChanges == false)
        picker.select("", using: store.setPreferredStartupModel)
        #expect(store.draft?.selection.preloaded.isEmpty == true)
        #expect(store.draft?.selection.enabled == original.selection.enabled)
        #expect(store.draft?.original == original.original)
        #expect(store.draft?.hasChanges == true)
    }

    @Test("no preference stays clean and an explicit choice or clear stages only preload")
    func explicitChoiceAndClear() async throws {
        let selection = ProviderModelSelection(enabled: ["first", "second"], preloaded: [])
        let inventory = ModelInventory(myCatalog: [item("first", enabled: "first"), item("second", enabled: "second")], available: [], issues: [])
        let store = fixtureStore(selection: selection, inventory: inventory)
        await store.refresh()
        let original = try #require(store.draft)
        let initial = ModelStartupPickerPresentation.make(selection: original.selection, inventory: inventory)
        #expect(initial.selectedTag == "")
        initial.select("", using: store.setPreferredStartupModel)
        initial.select("unlisted", using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        initial.select("first", using: store.setPreferredStartupModel)
        #expect(store.draft?.selection.preloaded == ["first"])
        let chosen = ModelStartupPickerPresentation.make(selection: try #require(store.draft).selection, inventory: inventory)
        chosen.select("", using: store.setPreferredStartupModel)
        #expect(store.draft == original)
    }

    @Test("multiple preloads retain the warning path and permit explicit clearing")
    func multiplePreferenceCanBeCleared() async throws {
        let selection = ProviderModelSelection(enabled: ["first", "second"], preloaded: ["first", "second"])
        let inventory = ModelInventory(myCatalog: [item("first", enabled: "first", preloaded: "first"),
            item("second", enabled: "second", preloaded: "second")], available: [], issues: [])
        let store = fixtureStore(selection: selection, inventory: inventory)
        await store.refresh()
        let original = try #require(store.draft)
        let picker = ModelStartupPickerPresentation.make(selection: original.selection, inventory: inventory)
        #expect(picker.selectedTag == "")
        #expect(store.draft == original)
        picker.select("", using: store.setPreferredStartupModel)
        #expect(store.draft?.selection.preloaded.isEmpty == true)
        #expect(store.draft?.selection.enabled == selection.enabled)
        #expect(store.draft?.hasChanges == true)
    }

    @Test("duplicate enabled aliases offer one stable canonical model for every preload state",
          arguments: ["none", "single", "multiple"])
    func duplicateAliasesAreUsable(preloadState: String) async throws {
        let preloaded: [String] = switch preloadState {
        case "single": ["gpt-oss-20b"]
        case "multiple": ["gpt-oss-20b", "other-model"]
        default: []
        }
        let selection = ProviderModelSelection(enabled: ["gpt-oss", "gpt-oss-20b", "other-model"], preloaded: preloaded)
        let inventory = ModelInventory(myCatalog: [
            item("gpt-oss-20b", enabled: "gpt-oss", preloaded: "gpt-oss-20b"),
            item("other-model", enabled: "other-model")
        ], available: [], issues: [])
        let store = fixtureStore(selection: selection, inventory: inventory)
        await store.refresh()
        let original = try #require(store.draft)
        let picker = ModelStartupPickerPresentation.make(selection: original.selection, inventory: inventory)
        #expect(picker.options.map(\.catalogID) == ["gpt-oss-20b", "other-model"])
        #expect(picker.options.map(\.selector) == ["gpt-oss", "other-model"])
        #expect(picker.selectedTag == (preloadState == "single" ? "gpt-oss" : ""))
        #expect(store.draft == original)
        // A duplicate raw spelling is not a second menu option.
        picker.select("gpt-oss-20b", using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        picker.select("gpt-oss", using: store.setPreferredStartupModel)
        if preloadState == "single" {
            #expect(store.draft == original)
            #expect(store.draft?.hasChanges == false)
        } else {
            #expect(store.draft?.selection.preloaded == ["gpt-oss"])
            #expect(store.draft?.hasChanges == true)
        }
        let next = ModelStartupPickerPresentation.make(selection: try #require(store.draft).selection, inventory: inventory)
        #expect(next.selectedTag == "gpt-oss")
        #expect(next.options == picker.options)
        #expect(store.draft?.selection.enabled == selection.enabled)
    }

    @Test("unknown enabled options cannot invalidate an otherwise resolved preference")
    func unknownOptionCannotBeStaged() async throws {
        let selection = ProviderModelSelection(enabled: ["first", "missing", "second"], preloaded: ["first"])
        let inventory = ModelInventory(myCatalog: [item("first", enabled: "first"),
            item("second", enabled: "second")], available: [], issues: [])
        let store = fixtureStore(selection: selection, inventory: inventory)
        await store.refresh()
        let original = try #require(store.draft)
        let picker = ModelStartupPickerPresentation.make(selection: original.selection, inventory: inventory)
        #expect(picker.options.map(\.selector) == ["first", "second"])
        #expect(picker.selectedTag == "first")
        picker.select("missing", using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        picker.select("second", using: store.setPreferredStartupModel)
        #expect(store.draft?.selection.preloaded == ["second"])
    }

    @Test("missing inventory supplies no guessed model options for zero or multiple preloads", arguments: [0, 2])
    func missingInventoryHasNoOptions(preloadCount: Int) async throws {
        let enabled = ["first", "second"]
        let selection = ProviderModelSelection(enabled: enabled, preloaded: Array(enabled.prefix(preloadCount)))
        let inventory = ModelInventory(myCatalog: [item("first", enabled: "first"), item("second", enabled: "second")], available: [], issues: [])
        let store = fixtureStore(selection: selection, inventory: inventory)
        await store.refresh()
        let original = try #require(store.draft)
        let picker = ModelStartupPickerPresentation.make(selection: original.selection, inventory: nil)
        #expect(picker.options.isEmpty)
        #expect(picker.selectedTag == "")
        picker.select("first", using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        picker.select("", using: store.setPreferredStartupModel)
        #expect(store.draft?.selection.preloaded.isEmpty == true)
        #expect(store.draft?.selection.enabled == enabled)
        #expect(store.draft?.hasChanges == (preloadCount > 0))
    }

    private func item(_ id: String, enabled: String?, preloaded: String? = nil) -> ModelInventoryItem {
        .init(catalogID: id, localID: id, displayName: id, modelType: "llm", capabilities: [],
            sizeGB: 1, minimumRAMGB: 4, isDownloaded: true, isEnabled: enabled != nil,
            isPreloaded: preloaded != nil, liveState: .unloaded, issue: nil,
            enabledSelector: enabled, preloadSelector: preloaded)
    }

    private func fixtureStore(selection: ProviderModelSelection, inventory: ModelInventory) -> ProviderControlStore {
        let now = Date()
        let draft = ProviderConfigDraft(sourceRevision: "startup-picker-fixture", original: selection,
            selection: selection, originalMaxModelSlots: 1, maxModelSlots: 1)
        let source = ProviderControlSourceState.fresh(evidenceAt: now)
        let snapshot = ProviderControlSnapshot(inventory: inventory, draft: draft, capturedAt: now,
            sources: .init(catalog: source, localModels: source, daemon: source, loadedModels: source))
        return ProviderControlStore(controller: StartupPickerFixtureController(snapshot: snapshot))
    }
}

private struct StartupPickerFixtureController: ProviderControlling {
    let snapshot: ProviderControlSnapshot
    func refresh() async throws -> ProviderControlSnapshot { snapshot }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult { throw CancellationError() }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws { throw CancellationError() }
    func delete(_ localModelID: String) async throws { throw CancellationError() }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws { throw CancellationError() }
}
