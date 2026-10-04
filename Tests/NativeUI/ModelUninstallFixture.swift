// Local-only native review fixture. The fake controller owns exactly one
// temporary sentinel file and never reads or changes provider files.
import AppKit
import SwiftUI
import DarkbloomTelemetry

private enum UninstallFixtureModel {
    static let eligibleID = "fixture-unloaded-model"
    static let residentID = "fixture-resident-model"
    static let missingID = "fixture-not-downloaded-model"
}

private struct UninstallFixtureStatusDocument: Codable, Equatable, Sendable {
    var deleteCallCount = 0
    var weightsFileExists = false
    var simulatedWriterBusy = false
    var lastDeleteOutcome = "not attempted"
    var fixtureStorageReady = false
}

@MainActor
private final class UninstallFixtureStatus: ObservableObject {
    @Published private(set) var document: UninstallFixtureStatusDocument

    let rootURL: URL
    let cacheURL: URL
    let statusURL: URL
    let weightsURL: URL
    private let ownsRoot: Bool

    init() {
        let processID = ProcessInfo.processInfo.processIdentifier
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BloomyModelUninstallReview-\(processID)-\(UUID().uuidString)",
                isDirectory: true
            )
        cacheURL = rootURL.appendingPathComponent("fixture-cache", isDirectory: true)
        statusURL = rootURL.appendingPathComponent("status.json")
        weightsURL = cacheURL.appendingPathComponent("fixture-only-weights.safetensors")

        var initial = UninstallFixtureStatusDocument()
        var createdRoot = false
        do {
            // A PID-specific directory is fresh for a running process. If a
            // stale directory exists after PID reuse, preserve it and fail
            // closed instead of adopting or overwriting its files.
            guard !FileManager.default.fileExists(atPath: rootURL.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
            createdRoot = true
            try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: false)
            try Data("inert fixture sentinel; not model weights\n".utf8)
                .write(to: weightsURL, options: .withoutOverwriting)
            initial.weightsFileExists = true
            initial.fixtureStorageReady = true
        } catch {
            initial.lastDeleteOutcome = "fixture storage unavailable"
        }
        ownsRoot = createdRoot
        document = initial
        persist(initial)
    }

    var canOfferEligibleModel: Bool { document.fixtureStorageReady }

    func update(
        deleteCallCount: Int,
        weightsFileExists: Bool,
        simulatedWriterBusy: Bool,
        lastDeleteOutcome: String
    ) {
        var next = document
        next.deleteCallCount = deleteCallCount
        next.weightsFileExists = weightsFileExists
        next.simulatedWriterBusy = simulatedWriterBusy
        next.lastDeleteOutcome = lastDeleteOutcome
        document = next
        persist(next)
    }

    private func persist(_ value: UninstallFixtureStatusDocument) {
        guard ownsRoot else { return }
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: statusURL, options: .atomic)
    }
}

private actor UninstallFixtureController: ProviderControlling {
    private let status: UninstallFixtureStatus
    private let cacheDirectory: String
    private let weightsURL: URL
    private let hasFixtureStorage: Bool
    private var selection = ProviderModelSelection(
        enabled: [UninstallFixtureModel.residentID],
        preloaded: []
    )
    private var localModelIDs: Set<String>
    private var simulatedWriterBusy = false
    private var deleteCallCount = 0
    private var lastDeleteOutcome = "not attempted"

    init(
        status: UninstallFixtureStatus,
        cacheDirectory: String,
        weightsURL: URL,
        hasFixtureStorage: Bool
    ) {
        self.status = status
        self.cacheDirectory = cacheDirectory
        self.weightsURL = weightsURL
        self.hasFixtureStorage = hasFixtureStorage
        localModelIDs = [UninstallFixtureModel.residentID]
        if hasFixtureStorage {
            localModelIDs.insert(UninstallFixtureModel.eligibleID)
        }
    }

    func refresh() async throws -> ProviderControlSnapshot {
        let now = Date()
        let daemon = Self.daemonState(at: now)
        let catalog = Self.catalog
        let local = catalog.compactMap { model -> LocalModel? in
            guard localModelIDs.contains(model.id) else { return nil }
            let bytes = model.id == UninstallFixtureModel.eligibleID
                ? Int64(1_250_000_000)
                : Int64(900_000_000)
            return LocalModel(id: model.id, modelType: model.modelType,
                sizeBytes: bytes, estimatedMemoryGB: nil)
        }
        let inventory = ModelInventoryBuilder.build(
            catalog: catalog,
            local: local,
            selection: selection,
            daemon: daemon,
            loadedModels: [UninstallFixtureModel.residentID]
        )
        let draft = ProviderConfigDraft(
            sourceRevision: "synthetic-model-uninstall-fixture-v1",
            original: selection,
            selection: selection,
            originalMaxModelSlots: 2,
            maxModelSlots: 2,
            originalEngineV2MaxConcurrent: 2,
            engineV2MaxConcurrent: 2
        )
        let fresh = ProviderControlSourceState.fresh(evidenceAt: now)
        return ProviderControlSnapshot(
            inventory: inventory,
            draft: draft,
            daemonState: daemon,
            capturedAt: now,
            sources: ProviderControlSourceStates(
                catalog: fresh,
                localModels: fresh,
                daemon: fresh,
                loadedModels: fresh
            ),
            effectiveCacheDirectory: cacheDirectory
        )
    }

    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        selection = draft.selection
        let updated = ProviderConfigDraft(
            sourceRevision: "synthetic-model-uninstall-fixture-v1",
            original: selection,
            selection: selection,
            originalMaxModelSlots: draft.maxModelSlots,
            maxModelSlots: draft.maxModelSlots,
            originalEngineV2MaxConcurrent: draft.engineV2MaxConcurrent,
            engineV2MaxConcurrent: draft.engineV2MaxConcurrent
        )
        return ProviderConfigSaveResult(draft: updated, restartRequired: false)
    }

    func download(
        _ modelID: String,
        onOutput: (@Sendable (ProcessOutputChunk) -> Void)?
    ) async throws {
        // Downloads are outside this review. Leave the fixture catalog inert.
    }

    func delete(_ localModelID: String) async throws {
        deleteCallCount += 1
        lastDeleteOutcome = localModelID == UninstallFixtureModel.eligibleID
            ? "rejected delete without a cache binding"
            : "rejected outside fixture eligibility"
        await publishStatus(weightsFileExists: FileManager.default.fileExists(atPath: weightsURL.path))
        throw ProviderControlError.deleteBlocked("Refresh model controls to confirm the model cache before uninstalling.")
    }

    func performDelete(
        _ localModelID: String,
        expectedCacheDirectory: String,
        onPhase: ProviderMutationPhaseObserver?
    ) async throws -> ProviderMutationCompletion {
        deleteCallCount += 1
        await publishStatus(weightsFileExists: FileManager.default.fileExists(atPath: weightsURL.path))

        let freshSnapshot = try await refresh()
        let item = freshSnapshot.inventory.myCatalog.first { $0.localID == localModelID }
        guard !expectedCacheDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expectedCacheDirectory == cacheDirectory,
              freshSnapshot.effectiveCacheDirectory == expectedCacheDirectory,
              localModelID == UninstallFixtureModel.eligibleID,
              let item,
              item.isDownloaded,
              item.liveState == .unloaded,
              !item.isEnabled,
              !item.isPreloaded,
              freshSnapshot.runtimeDeletionBlockReason(for: localModelID) == nil else {
            lastDeleteOutcome = "rejected fresh fixture eligibility check"
            await publishStatus(weightsFileExists: FileManager.default.fileExists(atPath: weightsURL.path))
            throw ProviderControlError.deleteBlocked("The local model identity is ambiguous")
        }

        try await removeFixtureModel(localModelID)
        await onPhase?(.reconciling)
        return .refreshUncertain
    }

    private func removeFixtureModel(_ localModelID: String) async throws {
        let fileExists = FileManager.default.fileExists(atPath: weightsURL.path)

        guard !simulatedWriterBusy else {
            lastDeleteOutcome = "blocked by simulated writer"
            await publishStatus(weightsFileExists: fileExists)
            throw ProviderControlError.commandAlreadyRunning
        }
        guard localModelID == UninstallFixtureModel.eligibleID,
              hasFixtureStorage,
              localModelIDs.contains(UninstallFixtureModel.eligibleID),
              fileExists else {
            lastDeleteOutcome = "rejected outside fixture eligibility"
            await publishStatus(weightsFileExists: fileExists)
            throw ProviderControlError.deleteBlocked("The local model identity is ambiguous")
        }
        do {
            // This is the only removal performed by the fixture. The path is
            // a unique temporary sentinel created above, never a provider path.
            try FileManager.default.removeItem(at: weightsURL)
            localModelIDs.remove(UninstallFixtureModel.eligibleID)
            lastDeleteOutcome = "removed fixture sentinel"
            await publishStatus(weightsFileExists: false)
        } catch {
            lastDeleteOutcome = "fixture sentinel removal failed"
            await publishStatus(weightsFileExists: FileManager.default.fileExists(atPath: weightsURL.path))
            throw ProviderControlError.invalidOutput("Fixture-owned sentinel removal failed")
        }
    }

    func activityRisk() async -> ProviderActivityRisk { .idle }

    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws {
        // The fixture never starts, stops, or restarts a provider.
    }

    func setWriterBusy(_ busy: Bool) async {
        simulatedWriterBusy = busy
        if busy {
            lastDeleteOutcome = "writer busy simulation enabled"
        } else if lastDeleteOutcome == "writer busy simulation enabled" {
            lastDeleteOutcome = "ready to retry"
        }
        await publishStatus(weightsFileExists: FileManager.default.fileExists(atPath: weightsURL.path))
    }

    private func publishStatus(weightsFileExists: Bool) async {
        await status.update(
            deleteCallCount: deleteCallCount,
            weightsFileExists: weightsFileExists,
            simulatedWriterBusy: simulatedWriterBusy,
            lastDeleteOutcome: lastDeleteOutcome
        )
    }

    private static let catalog = [
        CatalogModel(
            id: UninstallFixtureModel.eligibleID,
            displayName: "Fixture Unloaded 4B",
            family: "fixture-unloaded",
            modelType: "text",
            capabilities: ["chat"],
            sizeGB: 1.25,
            minimumRAMGB: 8,
            active: true
        ),
        CatalogModel(
            id: UninstallFixtureModel.residentID,
            displayName: "Fixture Resident 4B",
            family: "fixture-resident",
            modelType: "text",
            capabilities: ["chat"],
            sizeGB: 0.9,
            minimumRAMGB: 8,
            active: true
        ),
        CatalogModel(
            id: UninstallFixtureModel.missingID,
            displayName: "Fixture Not Downloaded 4B",
            family: "fixture-not-downloaded",
            modelType: "text",
            capabilities: ["chat"],
            sizeGB: 0.8,
            minimumRAMGB: 8,
            active: true
        )
    ]

    private static func daemonState(at now: Date) -> DaemonState {
        let timestamp = now.timeIntervalSince1970
        return DaemonState(
            schema: 1,
            version: "synthetic-review",
            currentModel: UninstallFixtureModel.residentID,
            warmModels: [UninstallFixtureModel.residentID],
            stats: ProviderStats(tokensGenerated: 0, requestsServed: 0, usageGaps: 0),
            trust: nil,
            capacity: nil,
            slots: [ModelSlot(
                model: UninstallFixtureModel.residentID,
                mtpEnabled: false,
                mtpActive: false,
                mtpReason: nil,
                kvBackend: "fixture",
                requestedKVBackend: "fixture"
            )],
            inferenceActive: false,
            startedAt: timestamp - 60,
            writtenAt: timestamp,
            pid: 4242,
            processIdentity: ProcessIdentity(pid: 4242, startTimeMicros: 1_800_000_000),
            advertisedModels: [UninstallFixtureModel.residentID],
            lifecycle: ProviderLifecycleState(outcome: .serving, remainingRequests: 0,
                coordinatorAcknowledged: true),
            startupPreloadPendingModels: []
        )
    }
}

@main
struct ModelUninstallFixture: App {
    private let controller: UninstallFixtureController
    @StateObject private var store: ProviderControlStore
    @StateObject private var reviewStatus: UninstallFixtureStatus
    @State private var compactReview = false
    @State private var thresholdReview = false
    @State private var threeColumnReview = false
    @State private var lightReview = false
    @State private var boundsReview = "Bounds not measured"

    init() {
        let reviewStatus = UninstallFixtureStatus()
        let controller = UninstallFixtureController(
            status: reviewStatus,
            cacheDirectory: reviewStatus.cacheURL.path,
            weightsURL: reviewStatus.weightsURL,
            hasFixtureStorage: reviewStatus.canOfferEligibleModel
        )
        self.controller = controller
        _reviewStatus = StateObject(wrappedValue: reviewStatus)
        _store = StateObject(wrappedValue: ProviderControlStore(controller: controller))
    }

    var body: some Scene {
        WindowGroup("Model Uninstall Review") {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label("Synthetic uninstall review", systemImage: "shippingbox")
                            .font(.headline)
                        Spacer(minLength: 8)
                        Text("No provider connected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Simulate cache writer busy", isOn: Binding(
                        get: { reviewStatus.document.simulatedWriterBusy },
                        set: { value in Task { await controller.setWriterBusy(value) } }
                    ))
                    .toggleStyle(.checkbox)
                    HStack {
                        Toggle("650 pt card layout", isOn: $compactReview)
                        Toggle("Light appearance", isOn: $lightReview)
                    }
                    .toggleStyle(.checkbox)
                    HStack {
                        Toggle("654 pt two-column boundary", isOn: $thresholdReview)
                        Toggle("968 pt three-column boundary", isOn: $threeColumnReview)
                        Button("Measure card controls") {
                            boundsReview = ModelUninstallCardBounds.measure(outputDirectory: reviewStatus.rootURL,
                                allocatedCardWidth: threeColumnReview || thresholdReview ? 300 : 460)
                        }
                        .disabled(!compactReview && !thresholdReview && !threeColumnReview)
                    }.toggleStyle(.checkbox)
                    Text(boundsReview).font(.caption).foregroundStyle(.secondary)
                    Text(reviewStatusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("Status JSON: \(reviewStatus.rootURL.lastPathComponent)/status.json")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)

                Divider()

                ModelManagerView(store: store)
                    .frame(width: threeColumnReview ? 968 : thresholdReview ? 654 : compactReview ? 650 : nil)
                    .frame(maxWidth: .infinity)
            }
            .frame(minWidth: 650, idealWidth: 820, minHeight: 700, idealHeight: 780)
            .preferredColorScheme(lightReview ? .light : .dark)
            .task { await store.refresh() }
        }
    }

    private var reviewStatusLine: String {
        let value = reviewStatus.document
        let file = value.weightsFileExists ? "present" : "removed"
        return "Uninstall calls: \(value.deleteCallCount) · fake weights file: \(file) · \(value.lastDeleteOutcome)"
    }
}

/// A bounded, read-only inspection of the real native accessibility geometry.
/// The production card group exposes its content width; controls must stay
/// horizontally within that content. No control is pressed or focused here.
@MainActor
private enum ModelUninstallCardBounds {
    static func measure(outputDirectory: URL, allocatedCardWidth: CGFloat) -> String {
        let output = outputDirectory.appendingPathComponent("card-controls-bounds.json")
        var measurements: [[String: Any]] = []
        var failures: [String] = []
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.title == "Model Uninstall Review" }),
              let content = window.contentView else { return "No owned review window" }
        var pending: [(NSObject, Int)] = [(content, 0)]
        var seen = Set<ObjectIdentifier>()
        var nodes: [NSObject] = []
        while let (object, depth) = pending.popLast() {
            guard seen.insert(ObjectIdentifier(object)).inserted else { continue }
            guard nodes.count < 2_000, depth <= 128 else {
                failures.append("Native accessibility traversal exceeded its bound")
                break
            }
            nodes.append(object)
            let children = attribute("accessibilityChildren", object) as? [NSObject] ?? []
            pending.append(contentsOf: children.map { ($0, depth + 1) })
            if let view = object as? NSView {
                pending.append(contentsOf: view.subviews.map { ($0, depth + 1) })
                if let accessible = NSAccessibility.unignoredDescendant(of: view) as? NSObject {
                    pending.append((accessible, depth + 1))
                }
            }
        }
        let cases = [(UninstallFixtureModel.residentID, "Fixture Resident 4B"),
                     (UninstallFixtureModel.eligibleID, "Fixture Unloaded 4B")]
        for (id, name) in cases {
            let headers = nodes.filter {
                (attribute("accessibilityRole", $0) as? String) == NSAccessibility.Role.group.rawValue
                    && (attribute("accessibilityLabel", $0) as? String ?? "").hasPrefix(id + ",")
            }
            guard headers.count == 1, let header = headers.first,
                  let rect = (attribute("accessibilityFrame", header) as? NSValue)?.rectValue,
                  rect.width.isFinite && rect.width > 0 else {
                failures.append("\(id): expected one readable card content group; found \(headers.count)")
                continue
            }
            measurements.append(["model": id, "kind": "content", "frame": NSStringFromRect(rect)])
            // Do not accept controls merely fitting an already overgrown
            // content group. The independent grid slot is the width oracle.
            let contentWidth = allocatedCardWidth - 24
            if rect.width > contentWidth + 2 {
                failures.append("\(id): content exceeds its allotted width by \(Double(rect.width - contentWidth)) pt")
            }
            let allocated = NSRect(x: rect.midX - contentWidth / 2, y: rect.minY,
                                   width: contentWidth, height: rect.height)
            for role in ["enable", "preload", "uninstall", "manage"] {
                let matches = nodes.filter { node in
                    let label = attribute("accessibilityLabel", node) as? String ?? ""
                    switch role {
                    case "enable": return label == "Enable \(name)" || label == "Disable \(name)"
                    case "preload": return label == "Preload \(name)"
                    case "uninstall": return label == "Uninstall \(name)"
                    default: return label == "Manage \(name)"
                    }
                }
                guard matches.count == 1, let control = matches.first,
                      let frame = (attribute("accessibilityFrame", control) as? NSValue)?.rectValue,
                      frame.width.isFinite && frame.width > 0 else {
                    failures.append("\(id).\(role): expected one readable control; found \(matches.count)")
                    continue
                }
                let overflow = max(0, allocated.minX - frame.minX, frame.maxX - allocated.maxX)
                measurements.append(["model": id, "kind": role, "frame": NSStringFromRect(frame),
                                     "horizontalOverflowPoints": Double(overflow)])
                if overflow > 2 { failures.append("\(id).\(role) overflows by \(Double(overflow)) pt") }
            }
        }
        let record: [String: Any] = ["proof": "native-model-card-control-horizontal-bounds",
            "passing": failures.isEmpty, "failures": failures, "measurements": measurements,
            "nativeNodeCount": nodes.count, "windowFrame": NSStringFromRect(window.frame),
            "allocatedCardWidth": Double(allocatedCardWidth), "allocatedContentWidth": Double(allocatedCardWidth - 24),
            "providerConnected": false, "pressedAnyModelControl": false,
            "limitations": "Horizontal card-content containment only; no vertical scroll or spoken accessibility proof."]
        do {
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                .write(to: output, options: .atomic)
        } catch { return "Bounds report write failed" }
        return "Bounds \(failures.isEmpty ? "pass" : "FAIL"): \(measurements.count) measurements · \(failures.count) failures"
    }

    private static func attribute(_ name: String, _ object: NSObject) -> Any? {
        guard object.responds(to: NSSelectorFromString(name)) else { return nil }
        return object.value(forKey: name)
    }
}
