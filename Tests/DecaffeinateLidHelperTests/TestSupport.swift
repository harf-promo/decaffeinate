import Foundation

@testable import DecaffeinateLidHelper

/// A recording fake — mirrors this repo's `MutableClock`/`FakeSleepController`
/// style fakes in `Tests/DecaffeinateTests/TestSupport.swift`. Every call is
/// recorded so tests can assert exactly when the helper asserts/clears the
/// flag, never just the end state. `@unchecked Sendable` because the actor
/// (`LidHelperService`) that owns one of these serializes all access to it —
/// the same reasoning `MutableClock` documents for its own unchecked
/// conformance.
final class FakeDisableSleepController: DisableSleepControlling, @unchecked Sendable {
    private(set) var calls: [Bool] = []
    /// Force every call to fail, to exercise the (never-invoked-live) error
    /// path without a real `pmset`.
    var shouldFail = false

    func setDisableSleep(_ disabled: Bool) -> Result<Void, DisableSleepError> {
        calls.append(disabled)
        return shouldFail ? .failure(.nonZeroExit(1)) : .success(())
    }
}
