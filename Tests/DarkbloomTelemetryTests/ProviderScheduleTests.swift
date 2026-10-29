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
}
