import Foundation
import Combine

/// Stores and evaluates the firewall rule set (the whitelist / blacklist).
///
/// Pure, deterministic matching so it can be unit-tested without any system
/// state: given an assertion, return the governing policy (or `nil` when the app
/// is still unclassified and should be surfaced to the user).
@MainActor
final class RulesEngine: ObservableObject {
    private static let key = "DecaffeinateRules.v1"

    @Published private(set) var rules: [Rule] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Rule].self, from: data) {
            self.rules = decoded
        } else {
            self.rules = []
        }
    }

    // MARK: Evaluation

    /// The policy governing an assertion, or `nil` if no rule matches.
    func policy(for assertion: PowerAssertion) -> RulePolicy? {
        rule(for: assertion)?.policy
    }

    func rule(for assertion: PowerAssertion) -> Rule? {
        rules.first { $0.matches(assertion) }
    }

    /// `true` when this assertion is from an app the user has whitelisted and the
    /// allowance is still in effect — i.e. a reason *not* to force sleep.
    func isActivelyAllowed(_ assertion: PowerAssertion) -> Bool {
        rule(for: assertion)?.policy.isCurrentlyAllowing ?? false
    }

    /// `true` when a rule governs this assertion *and* is still decisive. A
    /// `.allowUntil` that has expired returns `false`, so the firewall can ask
    /// again rather than treating the app as permanently classified.
    func hasEffectiveDecision(for assertion: PowerAssertion) -> Bool {
        guard let policy = policy(for: assertion) else { return false }
        switch policy {
        case .allow, .ignore: return true
        case .allowUntil(let date): return date > Date()
        }
    }

    // MARK: CRUD

    func upsert(_ rule: Rule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else if let index = rules.firstIndex(where: { sameTarget($0, rule) }) {
            // Replace an existing rule for the same app rather than duplicating.
            var replacement = rule
            replacement.id = rules[index].id
            rules[index] = replacement
        } else {
            rules.append(rule)
        }
    }

    func setPolicy(_ policy: RulePolicy, for assertion: PowerAssertion) {
        upsert(
            Rule(
                bundleIdentifier: assertion.bundleIdentifier,
                processName: assertion.processName,
                displayName: assertion.displayName,
                policy: policy
            )
        )
    }

    func remove(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
    }

    func removeAll() {
        rules.removeAll()
    }

    private func sameTarget(_ lhs: Rule, _ rhs: Rule) -> Bool {
        if let a = lhs.bundleIdentifier, let b = rhs.bundleIdentifier {
            return a.caseInsensitiveCompare(b) == .orderedSame
        }
        return lhs.processName.caseInsensitiveCompare(rhs.processName) == .orderedSame
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
