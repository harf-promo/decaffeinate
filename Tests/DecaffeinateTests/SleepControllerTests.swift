import XCTest

@testable import Decaffeinate

/// The concrete `pmset` launch path — the literal mechanism behind every forced
/// sleep — exercised through the `pmsetURL` seam built for exactly this.
final class SleepControllerTests: XCTestCase {

    func testSleepNowSucceedsWhenPmsetLaunches() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("decaf-sleepctl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let stub = dir.appendingPathComponent("pmset")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: stub)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: stub.path)

        var controller = SleepController()
        controller.pmsetURL = stub
        guard case .success = controller.sleepNow() else {
            return XCTFail("a launchable pmset stub must report success")
        }
    }

    func testSleepNowReportsLaunchFailureForMissingExecutable() {
        var controller = SleepController()
        controller.pmsetURL = URL(fileURLWithPath: "/nonexistent/pmset-\(UUID().uuidString)")
        guard case .failure(.launchFailed) = controller.sleepNow() else {
            return XCTFail("a missing executable must surface as .launchFailed")
        }
    }
}
