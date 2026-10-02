import DarkbloomTelemetry
import Testing
@testable import DarkbloomMonitor

/// SwiftPM checks the pure names; actual native roles, duplicate nodes, presses,
/// switch states and retained drafts run under NSApplication.run() in
/// Tests/NativeUI/ModelManagerAccessibilityProof.swift.
@Suite("Model manager accessibility presentation")
@MainActor
struct ModelManagerAccessibilityTests {
    @Test("compact actions name the model while preserving their visible captions", arguments: [false, true])
    func contextualActionLabels(downloaded: Bool) throws {
        let catalog = [
            CatalogModel(id: "google/gemma-fixture", displayName: "Gemma fixture", family: "gemma", modelType: "llm",
                capabilities: ["chat"], sizeGB: 4, minimumRAMGB: 8, active: true),
            CatalogModel(id: "qwen/qwen-fixture", displayName: "Qwen fixture", family: "qwen", modelType: "llm",
                capabilities: ["chat"], sizeGB: 4, minimumRAMGB: 8, active: true)
        ]
        let local = downloaded ? catalog.map {
            LocalModel(id: $0.id, modelType: "llm", sizeBytes: 4_000_000_000, estimatedMemoryGB: nil)
        } : []
        let inventory = ModelInventoryBuilder.build(catalog: catalog, local: local,
            selection: ProviderModelSelection(enabled: [], preloaded: []), daemon: nil, loadedModels: [])
        let items = inventory.myCatalog + inventory.available
        let gemma = try #require(items.first { $0.catalogID == "google/gemma-fixture" })
        let qwen = try #require(items.first { $0.catalogID == "qwen/qwen-fixture" })
        #expect(ModelManagerPresentation.compactEntryActionLabel(for: gemma) == (downloaded ? "Manage" : "Details"))
        #expect(ModelManagerPresentation.compactEntryAccessibilityLabel(for: gemma) == (downloaded ? "Manage Gemma fixture" : "Details for Gemma fixture"))
        #expect(ModelManagerPresentation.compactEntryAccessibilityLabel(for: qwen) == (downloaded ? "Manage Qwen fixture" : "Details for Qwen fixture"))
        #expect(ModelManagerPresentation.compactEntryAccessibilityLabel(for: gemma) != ModelManagerPresentation.compactEntryAccessibilityLabel(for: qwen))
    }
}
