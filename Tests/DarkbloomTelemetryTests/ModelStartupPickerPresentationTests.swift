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
        #expect(mounted.selectedChoice == .model(enabled))
        #expect(store.draft == original)
        mounted.select(enabled, selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        #expect(store.draft?.hasChanges == false)

        await store.refreshPreservingDraft()
        let refreshed = try #require(store.draft)
        let picker = ModelStartupPickerPresentation.make(selection: refreshed.selection, inventory: store.snapshot?.inventory)
        #expect(picker.selectedTag == enabled)
        picker.select(enabled, selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft == original)

        picker.select("other-model", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
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
        #expect(picker.selectedChoice == nil)
        picker.select(selection.enabled[0], selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        #expect(store.draft?.hasChanges == false)
        picker.select("", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
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
        #expect(initial.selectedChoice == .noPreference)
        initial.select("", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        initial.select("unlisted", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        initial.select("first", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft?.selection.preloaded == ["first"])
        let chosen = ModelStartupPickerPresentation.make(selection: try #require(store.draft).selection, inventory: inventory)
        chosen.select("", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft == original)
    }

    @Test("multiple preloads have their own picker state without rewriting or clearing the draft")
    func multiplePreferenceCanBeCleared() async throws {
        let selection = ProviderModelSelection(enabled: ["first", "second"], preloaded: ["first", "second"])
        let inventory = ModelInventory(myCatalog: [item("first", enabled: "first", preloaded: "first"),
            item("second", enabled: "second", preloaded: "second")], available: [], issues: [])
        let store = fixtureStore(selection: selection, inventory: inventory)
        await store.refresh()
        let original = try #require(store.draft)
        let picker = ModelStartupPickerPresentation.make(selection: original.selection, inventory: inventory)
        #expect(picker.selectedTag == "")
        #expect(picker.selectedChoice == .multiple)
        #expect(store.draft == original)
        #expect(!picker.select(.multiple, selection: store.draft?.selection,
            inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel))
        #expect(store.draft == original)
        #expect(picker.select(.model("second"), selection: store.draft?.selection,
            inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel))
        #expect(store.draft?.selection.preloaded == ["second"])
        #expect(store.draft?.selection.enabled == selection.enabled)
        let single = ModelStartupPickerPresentation.make(selection: try #require(store.draft).selection,
            inventory: inventory)
        #expect(single.selectedChoice == .model("second"))
        picker.select("", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft?.selection.preloaded.isEmpty == true)
        #expect(store.draft?.selection.enabled == selection.enabled)
        #expect(store.draft?.hasChanges == true)
    }

    @Test("startup menus offer only downloaded models with unambiguous controls",
          arguments: [false, true])
    func invalidOptionsAreNotOffered(preloadMissingModel: Bool) async throws {
        let selection = ProviderModelSelection(enabled: ["ready", "missing", "issue"],
            preloaded: preloadMissingModel ? ["missing"] : [])
        let inventory = ModelInventory(myCatalog: [item("ready", enabled: "ready"),
            item("issue", enabled: "issue", issue: "Ambiguous selector")],
            available: [item("missing", enabled: "missing", downloaded: false)], issues: ["Ambiguous selector"])
        let store = fixtureStore(selection: selection, inventory: inventory)
        await store.refresh()
        let original = try #require(store.draft)
        let picker = ModelStartupPickerPresentation.make(selection: selection, inventory: inventory)
        #expect(picker.options.map(\.catalogID) == ["ready"])
        #expect(picker.selectedChoice == (preloadMissingModel ? nil : .noPreference))
        #expect(!picker.select(.model("missing"), selection: selection, inventory: inventory,
            using: store.setPreferredStartupModel))
        #expect(!picker.select(.model("issue"), selection: selection, inventory: inventory,
            using: store.setPreferredStartupModel))
        #expect(store.draft == original)
        if preloadMissingModel {
            #expect(picker.select(.noPreference, selection: store.draft?.selection,
                inventory: inventory, using: store.setPreferredStartupModel))
        }
        let current = ModelStartupPickerPresentation.make(selection: try #require(store.draft).selection,
            inventory: inventory)
        #expect(current.select(.model("ready"), selection: store.draft?.selection,
            inventory: inventory, using: store.setPreferredStartupModel))
        #expect(store.draft?.selection.preloaded == ["ready"])
        #expect(store.draft?.selection.enabled == selection.enabled)
        #expect(store.draft?.original == original.original)
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
        picker.select("gpt-oss-20b", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        picker.select("gpt-oss", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
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
        picker.select("missing", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        picker.select("second", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
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
        picker.select("first", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft == original)
        picker.select("", selection: store.draft?.selection, inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel)
        #expect(store.draft?.selection.preloaded.isEmpty == true)
        #expect(store.draft?.selection.enabled == enabled)
        #expect(store.draft?.hasChanges == (preloadCount > 0))
    }

    @Test("captured options reject refreshed identity changes without staging",
          arguments: ["exact-shadow", "ambiguous", "removed", "disabled"])
    func staleOptionCannotStageDifferentIdentity(change: String) async throws {
        let selection = ProviderModelSelection(enabled: ["gpt-oss", "gpt-oss-20b", "other-model"], preloaded: [])
        let model = item("gpt-oss-20b", enabled: "gpt-oss")
        let other = item("other-model", enabled: "other-model")
        let inventory = ModelInventory(myCatalog: [model, other], available: [], issues: [])
        let currentSelection: ProviderModelSelection
        let currentInventory: ModelInventory
        let freshSelector: String
        let freshCatalogID: String
        switch change {
        case "exact-shadow":
            currentSelection = selection
            currentInventory = .init(myCatalog: [model, item("gpt-oss", enabled: "gpt-oss"), other], available: [], issues: [])
            freshSelector = "gpt-oss"
            freshCatalogID = "gpt-oss"
        case "ambiguous":
            currentSelection = selection
            currentInventory = .init(myCatalog: [model, item("gpt-oss-120b", enabled: "gpt-oss"), other], available: [], issues: [])
            freshSelector = "gpt-oss-20b"
            freshCatalogID = "gpt-oss-20b"
        case "removed":
            currentSelection = selection
            currentInventory = .init(myCatalog: [other], available: [], issues: [])
            freshSelector = "other-model"
            freshCatalogID = "other-model"
        default:
            currentSelection = .init(enabled: ["gpt-oss-20b", "other-model"], preloaded: [])
            currentInventory = inventory
            freshSelector = "gpt-oss-20b"
            freshCatalogID = "gpt-oss-20b"
        }
        let controller = StartupPickerRefreshingFixtureController(snapshots: [
            fixtureSnapshot(selection: selection, inventory: inventory),
            fixtureSnapshot(selection: currentSelection, inventory: currentInventory)
        ])
        let store = ProviderControlStore(controller: controller)
        await store.refresh()
        let captured = ModelStartupPickerPresentation.make(selection: try #require(store.draft).selection,
            inventory: store.snapshot?.inventory)
        #expect(captured.options.first?.selector == "gpt-oss")
        #expect(captured.options.first?.catalogID == "gpt-oss-20b")
        await store.refresh()
        let beforeCallback = try #require(store.draft)
        var stagedCount = 0
        let accepted = captured.select("gpt-oss", selection: store.draft?.selection,
            inventory: store.snapshot?.inventory) { selector in
                stagedCount += 1
                store.setPreferredStartupModel(selector)
            }
        #expect(!accepted)
        #expect(stagedCount == 0)
        #expect(store.draft == beforeCallback)
        #expect(store.draft?.hasChanges == false)

        let fresh = ModelStartupPickerPresentation.make(selection: beforeCallback.selection,
            inventory: store.snapshot?.inventory)
        #expect(fresh.options.first { $0.selector == freshSelector }?.catalogID == freshCatalogID)
        #expect(fresh.select(freshSelector, selection: store.draft?.selection,
            inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel))
        #expect(store.draft?.selection.preloaded == [freshSelector])
        #expect(store.draft?.selection.enabled == beforeCallback.selection.enabled)
        #expect(store.draft?.original == beforeCallback.original)
        #expect(store.draft?.sourceRevision == beforeCallback.sourceRevision)
    }

    @Test("captured callbacks compare against later edits and preserve a current raw alias no-op")
    func capturedCallbackUsesCurrentPreference() async throws {
        let selection = ProviderModelSelection(enabled: ["gpt-oss", "gpt-oss-20b", "other-model"], preloaded: [])
        let inventory = ModelInventory(myCatalog: [item("gpt-oss-20b", enabled: "gpt-oss"),
            item("other-model", enabled: "other-model")], available: [], issues: [])
        let store = fixtureStore(selection: selection, inventory: inventory)
        await store.refresh()
        let captured = ModelStartupPickerPresentation.make(selection: selection, inventory: inventory)
        store.setPreferredStartupModel("gpt-oss-20b")
        let laterAlias = try #require(store.draft)
        var stagedCount = 0
        #expect(!captured.select("gpt-oss", selection: store.draft?.selection,
            inventory: store.snapshot?.inventory) { selector in
                stagedCount += 1
                store.setPreferredStartupModel(selector)
            })
        #expect(stagedCount == 0)
        #expect(store.draft == laterAlias)
        #expect(store.draft?.selection.preloaded == ["gpt-oss-20b"])

        // Clear uses the current preload even though the captured menu had none.
        #expect(captured.select("", selection: store.draft?.selection,
            inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel))
        #expect(store.draft?.selection == selection)

        store.setPreferredStartupModel("gpt-oss-20b")
        let selected = ModelStartupPickerPresentation.make(selection: try #require(store.draft).selection,
            inventory: inventory)
        store.setPreferredStartupModel("other-model")
        // A formerly selected option is now an explicit change back to that model.
        #expect(selected.select("gpt-oss", selection: store.draft?.selection,
            inventory: store.snapshot?.inventory, using: store.setPreferredStartupModel))
        #expect(store.draft?.selection.preloaded == ["gpt-oss"])
    }

    private func item(_ id: String, enabled: String?, preloaded: String? = nil,
                      downloaded: Bool = true, issue: String? = nil) -> ModelInventoryItem {
        .init(catalogID: id, localID: downloaded ? id : nil, displayName: id, modelType: "llm", capabilities: [],
            sizeGB: 1, minimumRAMGB: 4, isDownloaded: downloaded, isEnabled: enabled != nil,
            isPreloaded: preloaded != nil, liveState: .unloaded, issue: issue,
            enabledSelector: enabled, preloadSelector: preloaded)
    }

    private func fixtureStore(selection: ProviderModelSelection, inventory: ModelInventory) -> ProviderControlStore {
        ProviderControlStore(controller: StartupPickerFixtureController(
            snapshot: fixtureSnapshot(selection: selection, inventory: inventory)))
    }

    private func fixtureSnapshot(selection: ProviderModelSelection, inventory: ModelInventory) -> ProviderControlSnapshot {
        let now = Date()
        let draft = ProviderConfigDraft(sourceRevision: "startup-picker-fixture", original: selection,
            selection: selection, originalMaxModelSlots: 1, maxModelSlots: 1)
        let source = ProviderControlSourceState.fresh(evidenceAt: now)
        return ProviderControlSnapshot(inventory: inventory, draft: draft, capturedAt: now,
            sources: .init(catalog: source, localModels: source, daemon: source, loadedModels: source))
    }
}

private actor StartupPickerRefreshingFixtureController: ProviderControlling {
    let snapshots: [ProviderControlSnapshot]
    private var refreshCount = 0
    init(snapshots: [ProviderControlSnapshot]) { self.snapshots = snapshots }
    func refresh() async throws -> ProviderControlSnapshot {
        let snapshot = snapshots[min(refreshCount, snapshots.count - 1)]
        refreshCount += 1
        return snapshot
    }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult { throw CancellationError() }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws { throw CancellationError() }
    func delete(_ localModelID: String) async throws { throw CancellationError() }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws { throw CancellationError() }
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
