import Testing
@testable import DarkbloomMonitor

@Suite("Activity filter controls")
struct ActivityControlPresentationTests {
    @Test("a selected model remains reachable after moving to a period without its work")
    func retainedFilter() {
        let selected = "organization/retained-model"
        let previous = [selected, "organization/other-model"]
        #expect(ActivityFilterPresentation.models(available: previous, selected: selected) == previous)
        let nextPeriod = ["organization/other-model"]
        #expect(ActivityFilterPresentation.models(available: nextPeriod, selected: selected) == nextPeriod + [selected])
        #expect(ActivityFilterPresentation.models(available: [], selected: selected) == [selected])
        // Clearing the filter removes only the retained control; the available models are unchanged.
        #expect(ActivityFilterPresentation.models(available: nextPeriod, selected: nil) == nextPeriod)
        #expect(ActivityFilterPresentation.models(available: [], selected: nil).isEmpty)
    }

    @Test("All models describes the retained base-reward preference", arguments: [false, true])
    func allModelsBasePreference(shown: Bool) {
        #expect(ActivityFilterPresentation.allModelsLabel(metric: .earnings, showsBaseRewards: shown)
            == (shown ? "Show all models and base rewards" : "Show all models; base rewards remain hidden"))
        #expect(ActivityFilterPresentation.allModelsLabel(metric: .estimatedProfit, showsBaseRewards: shown)
            == "Show all model results")
    }
}
