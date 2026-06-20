import XCTest
@testable import Decaffeinate

@MainActor
final class RulesEngineTests: XCTestCase {

    private var defaults: UserDefaults!
    private var engine: RulesEngine!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "decaffeinate.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        engine = RulesEngine(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        engine = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSetAndReadPolicy() {
        let a = Fixtures.assertion()
        engine.setPolicy(.allow, for: a)
        XCTAssertEqual(engine.policy(for: a), .allow)
        XCTAssertTrue(engine.isActivelyAllowed(a))
    }

    func testIgnorePolicyIsNotAllowing() {
        let a = Fixtures.assertion()
        engine.setPolicy(.ignore, for: a)
        XCTAssertFalse(engine.isActivelyAllowed(a))
    }

    func testAllowUntilExpiry() {
        let a = Fixtures.assertion()
        engine.setPolicy(.allowUntil(Date().addingTimeInterval(3600)), for: a)
        XCTAssertTrue(engine.isActivelyAllowed(a))

        engine.setPolicy(.allowUntil(Date().addingTimeInterval(-1)), for: a)
        XCTAssertFalse(engine.isActivelyAllowed(a))
    }

    func testMatchesByBundleIdentifierCaseInsensitive() {
        let a = Fixtures.assertion(bundle: "com.example.App")
        engine.setPolicy(.allow, for: a)
        let other = Fixtures.assertion(process: "Different", bundle: "COM.EXAMPLE.APP")
        XCTAssertTrue(engine.isActivelyAllowed(other))
    }

    func testMatchesByProcessNameWhenNoBundle() {
        let a = Fixtures.assertion(process: "node", bundle: nil)
        engine.setPolicy(.ignore, for: a)
        let other = Fixtures.assertion(process: "NODE", bundle: nil)
        XCTAssertEqual(engine.policy(for: other), .ignore)
    }

    func testUpsertReplacesSameTarget() {
        let a = Fixtures.assertion()
        engine.setPolicy(.allow, for: a)
        engine.setPolicy(.ignore, for: a)
        XCTAssertEqual(engine.rules.count, 1)
        XCTAssertEqual(engine.policy(for: a), .ignore)
    }

    func testRemove() {
        let a = Fixtures.assertion()
        engine.setPolicy(.allow, for: a)
        let rule = try! XCTUnwrap(engine.rule(for: a))
        engine.remove(rule)
        XCTAssertTrue(engine.rules.isEmpty)
        XCTAssertNil(engine.policy(for: a))
    }

    func testPersistenceAcrossInstances() {
        let a = Fixtures.assertion()
        engine.setPolicy(.allow, for: a)
        let reloaded = RulesEngine(defaults: defaults)
        XCTAssertEqual(reloaded.policy(for: a), .allow)
    }

    func testUnclassifiedReturnsNil() {
        XCTAssertNil(engine.policy(for: Fixtures.assertion(bundle: "com.unknown.app")))
    }

    func testHasEffectiveDecision() {
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
