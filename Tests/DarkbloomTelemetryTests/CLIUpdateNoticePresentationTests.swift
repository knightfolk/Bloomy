import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("CLI update notice evidence")
struct CLIUpdateNoticePresentationTests {
    private enum Scenario: CaseIterable, Sendable {
        case current, newerRelease, restart, quarantined

        var status: CLIUpdateStatus {
            switch self {
            case .current: .upToDate(version: "0.9.7")
            case .newerRelease: .updateAvailable(current: "0.9.7", latest: "0.10.0")
            case .restart: .restartRequired(current: "0.9.7", installed: "0.10.0")
            case .quarantined: .quarantined(version: "0.10.0")
            }
        }

        var observedVersions: [String] {
            switch self {
            case .current: ["0.9.7"]
            case .newerRelease, .restart: ["0.9.7", "0.10.0"]
            case .quarantined: ["0.10.0"]
            }
        }
    }

    @Test("retained evidence preserves versions without current claims or restart instructions",
          arguments: Scenario.allCases)
    private func lastKnownEvidence(scenario: Scenario) {
        let fresh = CLIUpdateNoticePresentation.make(status: scenario.status, isStale: false)
        let retained = CLIUpdateNoticePresentation.make(status: scenario.status, isStale: true)
        #expect(!fresh.isStale)
        #expect(retained.isStale)
        #expect(retained.symbol == fresh.symbol)
        for version in scenario.observedVersions {
            #expect(fresh.detail.contains(version))
            #expect(retained.detail.contains(version))
        }
        #expect(retained.headline.hasPrefix("Last check:"))
        #expect(retained.detail.contains("at that check"))
        #expect(retained.guidance == nil)
        for currentClaim in ["is current", "is available", "is installed", "current CLI process", "Restart Darkbloom"] {
            #expect(!retained.detail.contains(currentClaim))
        }
        #expect(!fresh.headline.hasPrefix("Last check:"))
        switch scenario {
        case .restart:
            #expect(fresh.guidance?.hasPrefix("Restart Darkbloom") == true)
        case .newerRelease:
            #expect(fresh.guidance?.hasPrefix("Review the update") == true)
        case .current, .quarantined:
            #expect(fresh.guidance == nil)
        }
    }

    @Test("checks on different days cannot appear to have the same observation time")
    func timestampIncludesDay() throws {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let nextDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: first))
        #expect(first.formatted(date: .omitted, time: .shortened) == nextDay.formatted(date: .omitted, time: .shortened))
        #expect(CLIUpdateNoticePresentation.checkedAtLabel(first) != CLIUpdateNoticePresentation.checkedAtLabel(nextDay))
        #expect(CLIUpdateNoticePresentation.checkedAtLabel(first).contains(first.formatted(date: .abbreviated, time: .omitted)))
    }
}
