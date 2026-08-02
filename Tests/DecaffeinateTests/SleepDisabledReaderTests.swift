import XCTest

@testable import Decaffeinate

final class SleepDisabledReaderTests: XCTestCase {

    func testFlagPresentAndTrue() {
        let sample = """
            Currently in use:
             standbydelaylow      10800
             SleepDisabled        1
             womp                 1
            """
        XCTAssertEqual(SleepDisabledParser.parse(pmsetOutput: sample), true)
    }

    func testFlagPresentAndFalse() {
        let sample = " SleepDisabled        0\n womp                 1"
        XCTAssertEqual(SleepDisabledParser.parse(pmsetOutput: sample), false)
    }

    func testFlagAbsentReturnsNil() {
        let sample = """
             womp                 1
             standby              1
             lowpowermode         0
            """
        XCTAssertNil(SleepDisabledParser.parse(pmsetOutput: sample))
    }

    func testGarbledValueReturnsNil() {
        XCTAssertNil(SleepDisabledParser.parse(pmsetOutput: " SleepDisabled maybe"))
    }

    func testEmptyOutputReturnsNil() {
        XCTAssertNil(SleepDisabledParser.parse(pmsetOutput: ""))
    }

    func testAcceptsYesNoAndTrueFalseSpellings() {
        XCTAssertEqual(SleepDisabledParser.parse(pmsetOutput: " SleepDisabled YES"), true)
        XCTAssertEqual(SleepDisabledParser.parse(pmsetOutput: " SleepDisabled NO"), false)
        XCTAssertEqual(SleepDisabledParser.parse(pmsetOutput: " SleepDisabled true"), true)
        XCTAssertEqual(SleepDisabledParser.parse(pmsetOutput: " SleepDisabled false"), false)
    }
}
