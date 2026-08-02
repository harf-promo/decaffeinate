import XCTest

@testable import Decaffeinate

// MARK: - Test doubles (self-contained — doesn't touch AppStateTests' shared Harness)

@MainActor private final class FakeLidReader: LidStateReading {
    var snap: LidSnapshot = .notPresent
    func snapshot() -> LidSnapshot { snap }
}

@MainActor private final class FakeDisplayTopologyReader: DisplayTopologyReading {
    var snap: DisplayTopology = .none
    func snapshot() -> DisplayTopology { snap }
}

@MainActor private final class FakeInputProbe: ExternalInputProbing {
    var result: InputProbeResult = .inconclusive
    func probe() -> InputProbeResult { result }
}

/// Runs off the main actor (via `Task.detached`, mirroring the live reader),
/// so this needs to be genuinely `Sendable`; test usage never overlaps calls,
/// matching the `@unchecked Sendable` test-double pattern already used for
/// `TestClock`/`ThermalBox` in `AppStateTests.swift`.
private final class FakeSleepDisabledReader: SleepDisabledReading, @unchecked Sendable {
    var value: Bool?
    private(set) var callCount = 0
    func isSleepDisabled() -> Bool? {
        callCount += 1
        return value
    }
}

private final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { date += seconds }
}

/// Covers `AppState.refreshClamshellReadiness()` — the wiring between the
/// injected Clamshell Assistant readers and the published
/// `clamshellReadiness`/`foreignSleepDisabled` state, plus the ~30 s
/// throttle on the `pmset`-backed foreign-SleepDisabled sample. The pure
/// classification itself is covered by `ClamshellAdvisorTests`; this only
/// checks AppState calls it with the right inputs and on the right cadence.
@MainActor
final class AppStateClamshellTests: XCTestCase {

    private struct Harness {
        let state: AppState
        let lid: FakeLidReader
        let display: FakeDisplayTopologyReader
        let input: FakeInputProbe
        let sleepDisabled: FakeSleepDisabledReader
        let clock: TestClock
    }

    private func makeHarness() -> Harness {
        let suite = "decaf.clamshell.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let lid = FakeLidReader()
        let display = FakeDisplayTopologyReader()
        let input = FakeInputProbe()
        let sleepDisabled = FakeSleepDisabledReader()
        let clock = TestClock()
        let state = AppState(
            settingsStore: SettingsStore(defaults: defaults),
            rulesEngine: RulesEngine(defaults: defaults),
            history: SleepHistoryStore(defaults: defaults),
            restHistory: RestHistoryStore(defaults: defaults),
            awakeTime: AwakeTimeStore(defaults: defaults),
            lidReader: lid,
            displayReader: display,
            inputProbe: input,
            sleepDisabledReader: sleepDisabled,
            now: { clock.date }
        )
        return Harness(
            state: state, lid: lid, display: display, input: input, sleepDisabled: sleepDisabled,
            clock: clock)
    }

    func testNotApplicableOnADesktopMac() async {
        let h = makeHarness()
        h.lid.snap = .notPresent
        await h.state.refreshClamshellReadiness()
        XCTAssertEqual(h.state.clamshellReadiness, .notApplicable)
    }

    func testReadyWhenEveryRequirementIsMet() async {
        let h = makeHarness()
        h.lid.snap = LidSnapshot(isPresent: true, isClosed: false)
        h.display.snap = DisplayTopology(externalDisplayCount: 1, builtinDisplayActive: false)
        h.input.result = .detected
        // `AppState.power` defaults to `.unknown` (onBattery: false) before any
        // tick — satisfies the power requirement without a live PowerReading.
        await h.state.refreshClamshellReadiness()
        XCTAssertEqual(h.state.clamshellReadiness, .ready)
    }

    func testMissingExternalDisplaySurfacesInReadiness() async {
        let h = makeHarness()
        h.lid.snap = LidSnapshot(isPresent: true, isClosed: true)
        h.display.snap = .none
        h.input.result = .detected
        await h.state.refreshClamshellReadiness()
        XCTAssertEqual(h.state.clamshellReadiness, .missing(unmet: [.externalDisplay]))
    }

    func testForeignSleepDisabledSurfacesFromTheInjectedReader() async {
        let h = makeHarness()
        h.sleepDisabled.value = true
        await h.state.refreshClamshellReadiness()
        XCTAssertTrue(h.state.foreignSleepDisabled)
        XCTAssertEqual(h.sleepDisabled.callCount, 1, "sampled once on the first refresh")
    }

    func testSleepDisabledSampleIsThrottledToThirtySeconds() async {
        let h = makeHarness()
        await h.state.refreshClamshellReadiness()
        XCTAssertEqual(h.sleepDisabled.callCount, 1)

        // A second refresh moments later must NOT re-spawn `pmset` — the
        // cheap lid/display/input reads still happen, but the subprocess is
        // throttled.
        await h.state.refreshClamshellReadiness()
        XCTAssertEqual(h.sleepDisabled.callCount, 1, "throttled — no time has passed")

        h.clock.advance(31)
        await h.state.refreshClamshellReadiness()
        XCTAssertEqual(h.sleepDisabled.callCount, 2, "due again after the 30s window")
    }

    func testReadinessAlwaysUpdatesEvenWhenTheSleepDisabledSampleIsThrottled() async {
        let h = makeHarness()
        h.lid.snap = .notPresent
        await h.state.refreshClamshellReadiness()
        XCTAssertEqual(h.state.clamshellReadiness, .notApplicable)

        // Same tick window (throttled pmset sample) — the lid/display/input
        // reclassification must still run every call.
        h.lid.snap = LidSnapshot(isPresent: true, isClosed: false)
        h.display.snap = DisplayTopology(externalDisplayCount: 1, builtinDisplayActive: false)
        h.input.result = .detected
        await h.state.refreshClamshellReadiness()
        XCTAssertEqual(h.state.clamshellReadiness, .ready)
    }
}
