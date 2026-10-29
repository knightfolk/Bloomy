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

    @Test("schedule replacement preserves unrelated fields and standalone comments")
    func rendersSchedule() throws {
        let source = "[provider]\r\nfuture_key = 73\r\n[schedule]\r\nenabled = false # retained\r\nfuture_option = 'keep'\r\n# retained window note\r\n[[schedule.windows]]\r\ndays = ['mon']\r\nstart = '08:00'\r\nend = '09:00'\r\n[other]\r\nvalue = 'unchanged'\r\n"
        let schedule = ProviderSchedule(enabled: true, windows: [.init(days: [.friday], start: "22:00", end: "02:00")])
        let result = try ProviderConfigDocument.renderingSchedule(schedule, in: Data(source.utf8))
        let text = String(decoding: result, as: UTF8.self)
        #expect(text.contains("future_key = 73\r\n"))
        #expect(text.contains("enabled = true # retained\r\n"))
        #expect(text.contains("future_option = 'keep'\r\n# retained window note\r\n"))
        #expect(text.contains("[other]\r\nvalue = 'unchanged'\r\n"))
        #expect(try ProviderConfigDocument.readSchedule(data: result) == schedule)
    }

    @Test("creating a schedule and editing an empty final table produce valid output")
    func createsSchedule() throws {
        let desired = ProviderSchedule(enabled: true, windows: [.init(days: [.monday], start: "08:00", end: "09:00")])
        for source in ["[provider]\nname = 'example'\n", "[schedule]",
                       "[schedule]\n[[schedule.windows]]\ndays=['fri']\nstart='01:00'\nend='02:00'\n"] {
            let data = try ProviderConfigDocument.renderingSchedule(desired, in: Data(source.utf8))
            #expect(try ProviderConfigDocument.readSchedule(data: data) == desired)
        }
    }

    @Test("unknown window fields and inline comments prevent a destructive rewrite")
    func refusesUnpreservableWindows() {
        let desired = ProviderSchedule(enabled: true, windows: [.init(days: [.friday], start: "22:00", end: "02:00")])
        for extra in ["future = 'keep'\n", "# standalone is safe\nfuture = true\n", "days = ['mon'] # operator note\n"] {
            let days = extra.hasPrefix("days") ? "" : "days = ['mon']\n"
            let source = "[schedule]\nenabled = true\n[[schedule.windows]]\n\(days)start = '08:00'\nend = '09:00'\n\(extra)"
            #expect(throws: (any Error).self) { try ProviderConfigDocument.renderingSchedule(desired, in: Data(source.utf8)) }
        }
    }
}
