import Foundation

@testable import Decaffeinate

enum Fixtures {
    static func assertion(
        pid: pid_t = 1234,
        process: String = "TestApp",
        bundle: String? = "com.example.TestApp",
        type: String = AssertionType.preventUserIdleSystemSleep,
        name: String = "Test assertion",
        created: Date? = nil,
        realOwner: AssertionOwner? = nil
    ) -> PowerAssertion {
        PowerAssertion(
            id: "\(pid)-\(type)",
            pid: pid,
            processName: process,
            bundleIdentifier: bundle,
            assertionType: type,
            name: name,
            kind: AssertionType.classify(type),
            createdAt: created,
            realOwner: realOwner
        )
    }

    static let defaultSettings = DecaffeinateSettings()
}
