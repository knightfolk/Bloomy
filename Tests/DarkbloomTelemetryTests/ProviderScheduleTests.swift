import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Provider availability schedule")
struct ProviderScheduleTests {
    @Test("overnight and full-day windows use local wall time")
    func overnightAndFullDay() {
        let overnight = ProviderScheduleWindow(days: [.monday, .wednesday], start: "22:00", end: "02:00")
        let fullDay = ProviderScheduleWindow(days: [.sunday], start: "00:00", end: "00:00")
        #expect(overnight.durationMinutes == 240)
        #expect(fullDay.durationMinutes == 1_440)
        #expect(ProviderSchedule(enabled: true, windows: [overnight, fullDay]).isValidForEditing)
    }

    @Test("invalid times and empty enabled schedules cannot be submitted")
    func invalidSchedule() {
        for time in ["1:00", "24:00", "12:60", "12:0x", "１２:００"] {
            let window = ProviderScheduleWindow(days: [.monday], start: time, end: "12:00")
            #expect(window.durationMinutes == nil)
            #expect(!ProviderSchedule(enabled: true, windows: [window]).isValidForEditing)
        }
        #expect(!ProviderSchedule(enabled: true, windows: []).isValidForEditing)
        #expect(ProviderSchedule(enabled: false, windows: []).isValidForEditing)
        #expect(!ProviderSchedule(enabled: true, windows: [.init(days: [], start: "08:00", end: "09:00")]).isValidForEditing)
    }

    @Test("desktop interface accepts at most fourteen windows")
    func maximumWindows() {
        let window = ProviderScheduleWindow(days: [.monday], start: "08:00", end: "09:00")
        #expect(ProviderSchedule(enabled: true, windows: Array(repeating: window, count: 14)).isValidForEditing)
        #expect(!ProviderSchedule(enabled: true, windows: Array(repeating: window, count: 15)).isValidForEditing)
    }

    @Test("reads CLI schedule tables without mistaking text in unrelated settings")
    func readsSchedule() throws {
        let source = #"""
        note = """
        [schedule]
        enabled = true
        """
        [provider]
        name = "schedule # is text"
        [schedule] # local time
        enabled = true
        [[schedule.windows]]
        days = ["Monday", # a comment
                'wed',]
        start = '22:00'
        end = "02:00"
        [unrelated]
        enabled = false
        """#
        let result = try ProviderConfigDocument.readSchedule(data: Data(source.utf8))
        #expect(result.enabled)
        #expect(result.windows == [.init(days: [.monday, .wednesday], start: "22:00", end: "02:00")])
    }

    @Test("defaults to always available only when schedule is absent")
    func absentSchedule() throws {
        let result = try ProviderConfigDocument.readSchedule(data: Data("[backend]\nenabled_models = []\n".utf8))
        #expect(result == .init(enabled: false, windows: []))
    }

    @Test("unsupported and malformed schedule shapes do not appear disabled", arguments: [
        "schedule.enabled = true\n", "schedule = { enabled = true }\n",
        "[schedule]\nwindows = []\n", "[schedule]\nenabled = true\n",
        "[schedule]\nenabled = true\nenabled = false\n",
        "[[schedule.windows]]\ndays = ['mon']\nstart = '22:00'\nend = '25:00'\n",
        "[[schedule.windows]]\ndays = ['noday']\nstart = '22:00'\nend = '02:00'\n"
    ])
    func rejectsUnclearSchedule(source: String) {
        #expect(throws: (any Error).self) {
            try ProviderConfigDocument.readSchedule(data: Data(source.utf8))
        }
    }
}
