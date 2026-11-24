import XCTest

@testable import Decaffeinate

/// Guards against a test ever putting the machine running it to sleep.
///
/// `AppState`'s default `sleepController` is the real `SleepController`, which
/// runs `pmset sleepnow`. Two layers keep the suite safe: every `AppState(...)`
/// construction under `Tests/` must inject `sleepController:`, and the real
/// controller refuses the system `pmset` while XCTest is loaded.
final class TestSleepSafetyTests: XCTestCase {

    /// `<repo>/Tests` — this file is `Tests/DecaffeinateTests/<this>.swift`.
    private static let testsRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DecaffeinateTests
            .deletingLastPathComponent()  // Tests
    }()

    /// The argument text of every `AppState(` call in `text`, paren-matched.
    /// `makeAppState(` and other identifiers ending in `AppState` don't count.
    static func appStateConstructions(in text: String) -> [String] {
        let chars = Array(text)
        let needle = Array("AppState(")
        var results: [String] = []
        var i = 0
        while i + needle.count <= chars.count {
            if Array(chars[i..<(i + needle.count)]) == needle {
                let previous: Character? = i > 0 ? chars[i - 1] : nil
                let isIdentifierTail =
                    previous.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." } ?? false
                if !isIdentifierTail {
                    var depth = 0
                    var j = i + needle.count - 1
                    var body: [Character] = []
                    while j < chars.count {
                        let c = chars[j]
                        if c == "(" { depth += 1 }
                        if c == ")" { depth -= 1 }
                        body.append(c)
                        if depth == 0 { break }
                        j += 1
                    }
                    results.append(String(body))
                    i = j
                }
            }
            i += 1
        }
        return results
    }

    func testScannerFindsConstructionsAndIgnoresLookalikes() {
        let sample = """
            let a = AppState(settingsStore: s, sleepController: fake)
            let b = makeAppState(x: 1)
            let c = AppState(
                now: { clock.date }
            )
            """
        let found = Self.appStateConstructions(in: sample)
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found[0].contains("sleepController:"))
        XCTAssertFalse(found[1].contains("sleepController:"))
    }

    func testEveryTestAppStateInjectsAFakeSleeper() throws {
        let root = Self.testsRoot
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            return XCTFail("cannot read \(root.path)")
        }
        var scanned = 0
        var offenders: [String] = []
        for case let entry as String in walker where entry.hasSuffix(".swift") {
            if entry.hasSuffix("TestSleepSafetyTests.swift") { continue }
            let text = try String(contentsOf: root.appendingPathComponent(entry), encoding: .utf8)
            for call in Self.appStateConstructions(in: text) {
                scanned += 1
                if !call.contains("sleepController:") {
                    offenders.append("\(entry): AppState\(call.prefix(80))")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 0, "scanner found no AppState constructions")
        XCTAssertEqual(
            offenders, [],
            "AppState built without sleepController: — a tick() could run the real pmset sleepnow")
    }

    func testRealControllerRefusesSystemPmsetUnderXCTest() {
        // Check the detector first: if it were false, the call below would
        // really sleep this machine, so stop before making it.
        guard SleepController.isRunningUnderTests else {
            return XCTFail("XCTest detection failed; not calling the real controller")
        }
        XCTAssertEqual(SleepController().pmsetURL, SleepController.systemPmsetURL)
        guard case .failure(.launchFailed) = SleepController().sleepNow() else {
            return XCTFail("the real controller launched pmset under XCTest")
        }
        guard case .failure(.launchFailed) = SleepController().displayOffNow() else {
            return XCTFail("the real controller launched pmset under XCTest")
        }
    }
}
