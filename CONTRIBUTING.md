# Contributing to Decaffeinate

First off — **thank you.** Decaffeinate is built in the open precisely so people like you can make it better. Whether you're fixing a typo, attributing a stubborn `coreaudiod` assertion, or shipping the notarized DMG, you're welcome here. First-time contributors especially: we'll help you land your PR.

## Ways to contribute

- 🐛 **Report a bug** — open an [issue](https://github.com/harf-promo/decaffeinate/issues) with your macOS version and, ideally, the output of `Decaffeinate --scan`.
- 💡 **Suggest a feature** — start a [discussion](https://github.com/harf-promo/decaffeinate/discussions) or a feature-request issue.
- 🧑‍💻 **Write code** — grab a [`good first issue`](https://github.com/harf-promo/decaffeinate/labels/good%20first%20issue) or anything from the [roadmap](docs/ROADMAP.md).
- 📝 **Improve docs** — clarity, guides, translations.
- ⭐️ **Spread the word** — a star, a tweet, a demo video genuinely helps.

## Project layout

```
Sources/Decaffeinate/
  Core/      Engines & system glue (telemetry, idle, safety, sleep, rules, CLI)
  Models/    Plain value types (Rule, DecaffeinateSettings)
  Views/     SwiftUI menu bar + settings
  DecaffeinateApp.swift   App entry + CLI dispatch
Tests/       XCTest unit tests for the pure logic
Scripts/     build-app.sh, generate-icon.swift
docs/        Architecture, roadmap, distribution
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for how the pieces fit together.

## Getting set up

Requires **macOS 14+** and **Xcode 16 / Swift 6**.

```sh
git clone https://github.com/harf-promo/decaffeinate.git
cd decaffeinate
swift build           # compile
swift test            # run the unit tests (no GUI needed)
swift run Decaffeinate --scan   # sanity-check the scanner
./Scripts/build-app.sh          # produce build/Decaffeinate.app
```

## Development guidelines

- **Keep the core honest.** No private APIs, no kernel extensions, no root requirements, no telemetry, and no network calls beyond the Sparkle update check. If a feature seems to need one of those, open a discussion first — there's almost always a public-API path.
- **Pure logic stays testable.** Decision logic (safety rails, rules matching, formatting) lives in plain value types with no system dependencies, so it can be unit-tested. Please add tests for new logic of this kind.
- **Match the surrounding style.** Swift API Design Guidelines, clear names, comments that explain *why*. Mark UI/observable types `@MainActor`.
- **Safety first.** This app can put a Mac to sleep. Any change to the sleep-decision path must respect the safety rails (active media, Time Machine, updates, battery floor, thermal guard) and come with tests.

## Pull request checklist

1. Branch from `main` (`git checkout -b my-feature`).
2. `swift build` and `swift test` both pass.
3. New decision logic has unit tests.
4. Update docs / `CHANGELOG.md` if behavior changed.
5. Open the PR with a clear description of *what* and *why*. Link any related issue.

CI will build and test on macOS automatically. A maintainer will review — we aim to be quick and kind.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## License

By contributing, you agree your contributions are licensed under the [MIT License](LICENSE).
