import XCTest
@testable import Decaffeinate

@MainActor
final class RulesEngineTests: XCTestCase {

    /// Build an isolated engine on the main actor (avoids constructing the
    /// `@MainActor` engine from XCTest's nonisolated `setUp`, which would send a
    /// non-Sendable `UserDefaults` across isolation under strict concurrency).
    private func makeEngine() -> (engine: RulesEngine, defaults: UserDefaults, cleanup: () -> Void) {
        let suite = "decaffeinate.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let engine = RulesEngine(defaults: defaults)
        return (engine, defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    func testSetAndReadPolicy() {
        let (engine, _, cleanup) = makeEngine(); defer { cleanup() }
        let a = Fixtures.assertion()
        engine.setPolicy(.allow, for: a)
        XCTAssertEqual(engine.policy(for: a), .allow)
        XCTAssertTrue(engine.isActivelyAllowed(a))
    }

    func testIgnorePolicyIsNotAllowing() {
        let (engine, _, cleanup) = makeEngine(); defer { cleanup() }
        let a = Fixtures.assertion()
        engine.setPolicy(.ignore, for: a)
        XCTAssertFalse(engine.isActivelyAllowed(a))
    }

    func testAllowUntilExpiry() {
        let (engine, _, cleanup) = makeEngine(); defer { cleanup() }
        let a = Fixtures.assertion()
        engine.setPolicy(.allowUntil(Date().addingTimeInterval(3600)), for: a)
        XCTAssertTrue(engine.isActivelyAllowed(a))

        engine.setPolicy(.allowUntil(Date().addingTimeInterval(-1)), for: a)
        XCTAssertFalse(engine.isActivelyAllowed(a))
    }

    func testMatchesByBundleIdentifierCaseInsensitive() {
        let (engine, _, cleanup) = makeEngine(); defer { cleanup() }
        let a = Fixtures.assertion(bundle: "com.example.App")
        engine.setPolicy(.allow, for: a)
        let other = Fixtures.assertion(process: "Different", bundle: "COM.EXAMPLE.APP")
        XCTAssertTrue(engine.isActivelyAllowed(other))
    }

    func testMatchesByProcessNameWhenNoBundle() {
        let (engine, _, cleanup) = makeEngine(); defer { cleanup() }
        let a = Fixtures.assertion(process: "node", bundle: nil)
        engine.setPolicy(.ignore, for: a)
        let other = Fixtures.assertion(process: "NODE", bundle: nil)
        XCTAssertEqual(engine.policy(for: other), .ignore)
    }

    func testUpsertReplacesSameTarget() {
        let (engine, _, cleanup) = makeEngine(); defer { cleanup() }
        let a = Fixtures.assertion()
        engine.setPolicy(.allow, for: a)
        engine.setPolicy(.ignore, for: a)
        XCTAssertEqual(engine.rules.count, 1)
        XCTAssertEqual(engine.policy(for: a), .ignore)
    }

    func testRemove() throws {
        let (engine, _, cleanup) = makeEngine(); defer { cleanup() }
        let a = Fixtures.assertion()
        engine.setPolicy(.allow, for: a)
        let rule = try XCTUnwrap(engine.rule(for: a))
        engine.remove(rule)
        XCTAssertTrue(engine.rules.isEmpty)
        XCTAssertNil(engine.policy(for: a))
    }

    func testPersistenceAcrossInstances() {
        let (engine, defaults, cleanup) = makeEngine(); defer { cleanup() }
        let a = Fixtures.assertion()
        engine.setPolicy(.allow, for: a)
        let reloaded = RulesEngine(defaults: defaults)
        XCTAssertEqual(reloaded.policy(for: a), .allow)
    }

    func testUnclassifiedReturnsNil() {
        let (engine, _, cleanup) = makeEngine(); defer { cleanup() }
        XCTAssertNil(engine.policy(for: Fixtures.assertion(bundle: "com.unknown.app")))
    }

    func testHasEffectiveDecision() {
        let (engine, _, cleanup) = makeEngine(); defer { cleanup() }
        let a = Fixtures.assertion()
        XCTAssertFalse(engine.hasEffectiveDecision(for: a)) // unclassified

        engine.setPolicy(.allow, for: a)
        XCTAssertTrue(engine.hasEffectiveDecision(for: a))

        engine.setPolicy(.ignore, for: a)
        XCTAssertTrue(engine.hasEffectiveDecision(for: a))

        engine.setPolicy(.allowUntil(Date().addingTimeInterval(3600)), for: a)
        XCTAssertTrue(engine.hasEffectiveDecision(for: a))

        // Expired allowance is no longer effective — the firewall should re-ask.
        engine.setPolicy(.allowUntil(Date().addingTimeInterval(-1)), for: a)
        XCTAssertFalse(engine.hasEffectiveDecision(for: a))
    }
}
