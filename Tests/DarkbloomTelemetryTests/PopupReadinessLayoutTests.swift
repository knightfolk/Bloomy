import AppKit
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Popup readiness control layout")
@MainActor
struct PopupReadinessLayoutTests {
    @Test("every readiness label fits the compact command row", arguments: [false, true])
    func allStatesFit(dark: Bool) {
        let states: [ProviderReadinessPresentation.State] = [.unavailable, .stale, .unconfirmed,
            .scheduledWaiting, .transitioning, .stopped, .interrupted, .busy, .offline,
            .authorizationRequired, .ready, .serving, .onDemand, .modelsUnknown]
        for state in states {
            let presentation = ProviderReadinessPresentation(state: state, title: "Full explanation",
                detail: "Evidence stays available through help and accessibility.", symbolName: "questionmark.circle",
                tone: .caution, observedAt: Date(), evidence: [], suggestedAction: .health)
            let host = NSHostingView(rootView: PopupProviderReadinessControl(presentation: presentation,
                machineName: "Fixture Mac", openDestination: { _ in })
                .environment(\.colorScheme, dark ? .dark : .light))
            let fitted = host.fittingSize
            #expect(fitted.width > 20 && fitted.width <= 130, "\(state): \(fitted)")
            #expect(fitted.height <= 24)
        }
    }
}
