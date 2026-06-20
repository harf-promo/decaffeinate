# Security Policy

Decaffeinate can put your Mac to sleep and reads system-wide power-assertion
telemetry, so we take its trust boundary seriously.

## What Decaffeinate does and does not do

- ✅ Reads power assertions via the public IOKit API `IOPMCopyAssertionsByProcess`.
- ✅ Reads idle time via `CGEventSource` (duration only — never keystrokes).
- ✅ Sleeps the Mac via `/usr/bin/pmset sleepnow`; keeps it awake via `IOPMAssertionCreateWithName`.
- ✅ Stores settings and rules locally in `UserDefaults`.
- ❌ **No** telemetry, analytics, or accounts. The only network request is the optional Sparkle update check (fetching a signed `appcast.xml`); disable updates for zero network activity.
- ❌ **No** kernel extension, **no** private APIs, **no** root requirement.
- ❌ **No** reading or modification of other processes' memory.

## Supported versions

The latest release on `main` receives security fixes.

| Version | Supported |
| ------- | --------- |
| 1.0.x   | ✅        |

## Reporting a vulnerability

Please report security issues **privately** rather than in a public issue:

1. Open a [private security advisory](https://github.com/harf-promo/decaffeinate/security/advisories/new) on this repository, **or**
2. Email the maintainers (see the organization profile at https://github.com/harf-promo).

Please include:
- A description of the issue and its impact.
- Steps to reproduce, ideally with `Decaffeinate --scan` output or a minimal case.
- Your macOS version and hardware.

We will acknowledge your report, work with you on a fix, and credit you (if you
wish) in the release notes. Please give us a reasonable window to ship a fix
before any public disclosure.

Thank you for helping keep Decaffeinate trustworthy.
