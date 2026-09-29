import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Profit switch policy")
struct ProfitSwitchPolicyTests {
    private let start = Date(timeIntervalSince1970: 2_000_000)

    @Test("timing defaults and decoded values obey their bounds")
    func timingBounds() throws {
        #expect(ProfitSwitchTiming() == ProfitSwitchTiming(
            confirmationMinutes: 10, minimumHoldMinutes: 60,
            returnCooldownMinutes: 180, loadAllowanceMinutes: 5
        ))
        let decoded = try JSONDecoder().decode(ProfitSwitchTiming.self, from: Data(
            #"{"confirmationMinutes":0,"minimumHoldMinutes":999,"returnCooldownMinutes":1,"loadAllowanceMinutes":999}"#.utf8
        ))
        #expect(decoded.confirmationMinutes == 5)
        #expect(decoded.minimumHoldMinutes == 240)
        #expect(decoded.returnCooldownMinutes == 240)
        #expect(decoded.loadAllowanceMinutes == 30)
        #expect(ProfitSwitchTiming(confirmationMinutes: 99, minimumHoldMinutes: 0,
                                   returnCooldownMinutes: 9_999, loadAllowanceMinutes: 0)
            == ProfitSwitchTiming(confirmationMinutes: 60, minimumHoldMinutes: 30,
                                  returnCooldownMinutes: 1_440, loadAllowanceMinutes: 1))
    }

    @Test("a five-minute confirmation needs three distinct fresh samples")
    func shorterConfirmation() {
        var policy = ProfitSwitchPolicy(timing: .init(confirmationMinutes: 5))
        #expect(policy.observe(input(at: 0), at: date(0)) == nil)
        #expect(policy.observe(input(at: 150), at: date(150)) == nil)
        #expect(policy.observe(input(at: 150), at: date(200)) == nil)
        #expect(policy.observe(input(at: 300), at: date(300))?.modelID == "candidate")
    }

    @Test("a larger load allowance can erase projected profit")
    func loadAllowance() {
        let moderate = candidate(net: 0.8)
        let snapshot = input(at: 0, candidate: moderate)
        #expect(ProfitSwitchPolicy.evaluate(snapshot, at: date(0)) != nil)
        #expect(ProfitSwitchPolicy.evaluate(
            snapshot, at: date(0), timing: .init(loadAllowanceMinutes: 30)
        ) == nil)
        var policy = ProfitSwitchPolicy(timing: .init(loadAllowanceMinutes: 30))
        for offset in [0.0, 150, 300, 450, 600] {
            #expect(policy.observe(input(at: offset, candidate: moderate), at: date(offset)) == nil)
        }
    }

    @Test("sustained winner produces a conservative one-hour proposal")
    func sustainedWinner() {
        var policy = ProfitSwitchPolicy()
        for offset in [0.0, 150, 300, 450] {
            #expect(policy.observe(input(at: offset), at: date(offset)) == nil)
        }
        let proposal = policy.observe(input(at: 600), at: date(600))
        #expect(proposal?.modelID == "candidate")
        #expect(proposal?.currentModelID == "current")
        #expect(proposal?.loadSeconds == 300)
        #expect(abs((proposal?.estimatedGainUSD ?? 0) - (2 * 0.5 * (3_300.0 / 3_600) - 0.2)) < 0.000001)
        #expect(abs((proposal?.estimatedGainPercent ?? 0) - ((proposal?.estimatedGainUSD ?? 0) / 0.2 * 100)) < 0.000001)
        #expect(policy.observe(input(at: 750), at: date(750)) != nil)
        policy.reset()
        #expect(policy.observe(input(at: 900), at: date(900)) == nil)
    }

    @Test("stateless evaluation rechecks fresh economics without advancing confirmation")
    func statelessEvaluation() {
        var policy = ProfitSwitchPolicy()
        for offset in [0.0, 150, 300, 450] {
            #expect(policy.observe(input(at: offset), at: date(offset)) == nil)
        }
        let fresh = input(at: 450)
        #expect(ProfitSwitchPolicy.evaluate(fresh, at: date(451))?.modelID == "candidate")
        #expect(policy.observe(fresh, at: date(451)) == nil)
        #expect(ProfitSwitchPolicy.evaluate(input(at: 450, candidate: candidate(net: 0.4)), at: date(451)) == nil)
        #expect(ProfitSwitchPolicy.evaluate(fresh, at: date(571)) == nil) // 121 seconds old
        #expect(ProfitSwitchPolicy.evaluate(input(at: 452), at: date(451)) == nil) // future
        #expect(policy.observe(input(at: 600), at: date(600))?.modelID == "candidate")
    }

    @Test("a spike, a long gap, and repeated captures cannot manufacture persistence")
    func continuity() {
        var policy = ProfitSwitchPolicy()
        #expect(policy.observe(input(at: 0), at: date(0)) == nil)
        #expect(policy.observe(input(at: 150), at: date(150)) == nil)
        #expect(policy.observe(input(at: 150), at: date(240)) == nil)
        #expect(policy.observe(input(at: 300), at: date(300)) == nil)
        #expect(policy.observe(input(at: 451), at: date(451)) == nil) // 151-second gap
        #expect(policy.observe(input(at: 600), at: date(600)) == nil)

        policy.reset()
        #expect(policy.observe(input(at: 0), at: date(0)) == nil)
        #expect(policy.observe(input(at: 150, candidate: candidate(pressure: 0.2)), at: date(150)) == nil)
        for offset in [300.0, 450, 600, 750] {
            #expect(policy.observe(input(at: offset), at: date(offset)) == nil)
        }
        #expect(policy.observe(input(at: 900), at: date(900)) != nil)

        policy.reset()
        #expect(policy.observe(input(at: 0), at: date(0)) == nil)
        #expect(policy.observe(input(at: 150), at: date(270)) == nil) // 270 seconds between observations
        for offset in [300.0, 450, 600] {
            #expect(policy.observe(input(at: offset), at: date(offset)) == nil)
        }
    }

    @Test("demand and gross revenue alone cannot justify a swap")
    func demandIsNotProfit() {
        let weakNet = candidate(net: 0.4)
        let weakGross = candidate(gross: 1.5, net: 1.4)
        let noDemand = candidate(requests: 1, pressure: 0.2)
        for candidate in [weakNet, weakGross, noDemand] {
            var policy = ProfitSwitchPolicy()
            for offset in [0.0, 150, 300, 450, 600] {
                #expect(policy.observe(input(at: offset, candidate: candidate), at: date(offset)) == nil)
            }
        }
    }

    @Test("near ties and long cold loads fail the net improvement gate")
    func costsMatter() {
        let current = candidate(id: "current", requests: 1, pressure: 0.5, gross: 1.5, net: 1, load: 0)
        let nearTie = candidate(pressure: 0.7, net: 0.8)
        let longLoad = candidate(pressure: 0.8, net: 1.5, load: 1_800)
        for challenger in [nearTie, longLoad] {
            var policy = ProfitSwitchPolicy()
            for offset in [0.0, 150, 300, 450, 600] {
                #expect(policy.observe(input(at: offset, current: current, candidate: challenger), at: date(offset)) == nil)
            }
        }
    }

    @Test("missing, stale, future, regressed and malformed samples reset confirmation")
    func invalidInputsReset() {
        let malformed: [ProfitSwitchInput?] = [
            nil,
            input(at: -121),
            input(at: 1), // future relative to the observation below
            input(at: 0, candidate: candidate(net: -1)),
            input(at: 0, candidate: candidate(requests: -1)),
            input(at: 0, candidate: candidate(pressure: .nan)),
            input(at: 0, candidate: candidate(gross: .infinity)),
            input(at: 0, candidate: candidate(net: .infinity)),
            input(at: 0, candidate: candidate(gross: 1)), // gross below net
            input(at: 0, candidate: candidate(load: -1)),
            input(at: 0, candidate: candidate(load: 1_801)),
            input(at: 0, candidate: candidate(id: "current")),
            ProfitSwitchInput(currentModelID: "missing", candidates: [current(), candidate()], capturedAt: date(0)),
            ProfitSwitchInput(currentModelID: "current", candidates: [current(), candidate(), candidate()], capturedAt: date(0)),
        ]
        for bad in malformed {
            var policy = ProfitSwitchPolicy()
            #expect(policy.observe(input(at: -300), at: date(-300)) == nil)
            #expect(policy.observe(input(at: -150), at: date(-150)) == nil)
            #expect(policy.observe(bad, at: date(0)) == nil)
            #expect(policy.observe(input(at: 150), at: date(150)) == nil)
            #expect(policy.observe(input(at: 300), at: date(300)) == nil)
            #expect(policy.observe(input(at: 450), at: date(450)) == nil)
        }

        var policy = ProfitSwitchPolicy()
        #expect(policy.observe(input(at: 0), at: date(0)) == nil)
        #expect(policy.observe(input(at: 150), at: date(150)) == nil)
        #expect(policy.observe(input(at: 100), at: date(200)) == nil)
        for offset in [300.0, 450, 600, 750] {
            #expect(policy.observe(input(at: offset), at: date(offset)) == nil)
        }
        #expect(policy.observe(input(at: 900), at: date(900)) != nil)
    }

    @Test("a new winner must establish its own confirmation window")
    func winnerChange() {
        var policy = ProfitSwitchPolicy()
        #expect(policy.observe(input(at: 0), at: date(0)) == nil)
        #expect(policy.observe(input(at: 150), at: date(150)) == nil)
        for offset in [300.0, 450, 600, 750] {
            #expect(policy.observe(input(at: offset, candidate: candidate(id: "other")), at: date(offset)) == nil)
        }
        #expect(policy.observe(input(at: 900, candidate: candidate(id: "other")), at: date(900))?.modelID == "other")
    }

    @Test("zero current utilization retains a finite USD estimate and undefined percentage")
    func zeroBaseline() {
        var policy = ProfitSwitchPolicy()
        let zeroCurrent = candidate(id: "current", requests: 1, pressure: 0, gross: 1.5, net: 1, load: 0)
        for offset in [0.0, 150, 300, 450] {
            #expect(policy.observe(input(at: offset, current: zeroCurrent), at: date(offset)) == nil)
        }
        let proposal = policy.observe(input(at: 600, current: zeroCurrent), at: date(600))
        #expect(proposal?.estimatedGainUSD == 2 * 0.5 * (3_300.0 / 3_600))
        #expect(proposal?.estimatedGainPercent == nil)
    }

    private func date(_ offset: TimeInterval) -> Date { start.addingTimeInterval(offset) }

    private func current() -> ProfitSwitchCandidate {
        candidate(id: "current", requests: 1, pressure: 0.2, gross: 1.5, net: 1, load: 0)
    }

    private func candidate(
        id: String = "candidate",
        requests: Int = 10,
        pressure: Double = 0.5,
        gross: Double = 3,
        net: Double = 2,
        load: Double = 0
    ) -> ProfitSwitchCandidate {
        ProfitSwitchCandidate(modelID: id, requests: requests, pressure: pressure,
                              grossUSDPerActiveHour: gross, netUSDPerActiveHour: net,
                              loadSeconds: load)
    }

    private func input(
        at offset: TimeInterval,
        current: ProfitSwitchCandidate? = nil,
        candidate: ProfitSwitchCandidate? = nil
    ) -> ProfitSwitchInput {
        ProfitSwitchInput(currentModelID: "current", candidates: [current ?? self.current(), candidate ?? self.candidate()],
                          capturedAt: date(offset))
    }
}
