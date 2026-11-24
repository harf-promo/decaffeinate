import XCTest

@testable import Decaffeinate

/// The path embedded in an agent hook is the real executable, so a binary
/// launched through a renamed symlink still writes a hook we recognize later.
final class HookBinaryPathTests: XCTestCase {

    func testSymlinkWithAnotherNameResolvesToTheRealBinary() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("decaf-bin-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let real = dir.appendingPathComponent("Decaffeinate")
        try Data().write(to: real)
        let link = dir.appendingPathComponent("decaf")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let resolved = HookInstaller.canonicalBinaryPath(link.path)
        XCTAssertEqual((resolved as NSString).lastPathComponent, "Decaffeinate")
        let command = HookInstaller.claudeHookCommand(binaryPath: resolved, seconds: 300)
        XCTAssertTrue(HookInstaller.isDecaffeinateHookCommand(command), command)
    }

    func testRelativeNameIsLeftAlone() {
        XCTAssertEqual(HookInstaller.canonicalBinaryPath("Decaffeinate"), "Decaffeinate")
    }
}
