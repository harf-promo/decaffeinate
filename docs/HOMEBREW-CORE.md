# Submitting Decaffeinate to homebrew/cask

Today Decaffeinate installs from the **harf-promo tap** (`brew install --cask
harf-promo/tap/decaffeinate`). Getting it into the official **homebrew/cask**
removes the one-time tap step (`brew install --cask decaffeinate`).

## Readiness

The cask (`Casks/decaffeinate.rb`) is already style-clean for cask-core:

```
brew style Casks/decaffeinate.rb     # → no offenses
```

It uses a versioned GitHub-release `url`, a `livecheck` (`github_latest`),
`auto_updates true`, `depends_on macos: :sonoma`, a `desc` with no platform word
or trailing period, and a `zap` stanza — all of which homebrew/cask requires.

## The one gate: notability

homebrew/cask only accepts **notable** software. The current bar is roughly **75
GitHub stars/forks/watchers** (or comparable notability). Check before opening a PR:

```
gh repo view harf-promo/decaffeinate --json stargazerCount,forkCount,watchers
```

If the repo isn't there yet, the PR will be closed by the maintainers' bot. Keep
shipping from the tap until it clears the bar — nothing else is blocking.

## Steps (once notable) — open the PR yourself, or ask and confirm first

```bash
brew tap --force homebrew/cask
cp Casks/decaffeinate.rb "$(brew --repository homebrew/cask)/Casks/d/decaffeinate.rb"
cd "$(brew --repository homebrew/cask)"
brew audit --new --cask decaffeinate     # the new-cask gate (online; downloads the DMG)
brew install --cask --no-quarantine decaffeinate   # smoke-test the install
# then: fork homebrew/cask, push a branch, open the PR (title: "Add Decaffeinate")
```

`brew audit --new` runs the full notability + download + signature checks the
maintainers run. Only open the PR after it passes locally.

> Opening the PR publishes to the public Homebrew repo — an outward action. Do it
> deliberately (and only once notable); the tap keeps working in the meantime.
