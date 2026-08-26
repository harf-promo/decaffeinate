#!/usr/bin/env bash
# SessionStart hook, v2: best-effort `git fetch --prune` so local
# remote-tracking refs (esp. `origin/main`) are current the moment a
# session starts, on ANY host that has this repo checked out. This is
# checked into the repo deliberately — it travels with `git pull`, so it
# applies on the VPS and on a Mac clone alike without separate setup.
#
# Why fetch: on 2026-08-24, a VPS session's local `main` was silently 1
# commit behind `origin/main` because nothing had re-fetched since another
# host merged a PR. See the `vps-mac-git-sync-practice` memory note.
#
# Why v2 (same day): fetching alone updates the refs but says nothing —
# the agent still has to remember to check. A SessionStart hook's plain
# stdout is injected as context Claude can see, so v2 adds one line when
# this checkout is actually behind or has unpushed commits, turning "is
# this the latest version" from a command you must remember to run into
# something stated unprompted at session start.
#
# Never blocks session start: exits 0 unconditionally, even on failure
# (offline, no network yet, auth not ready). This only refreshes
# remote-tracking refs and reads counts — it never touches the working
# tree or HEAD, so it cannot conflict with uncommitted work or a
# mid-rebase state.

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

if command -v timeout >/dev/null 2>&1; then
  timeout 10s git fetch --prune --quiet 2>/dev/null
else
  git fetch --prune --quiet 2>/dev/null
fi

upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"
[ -n "$upstream" ] || exit 0

behind="$(git rev-list --count "HEAD..${upstream}" 2>/dev/null)"
ahead="$(git rev-list --count "${upstream}..HEAD" 2>/dev/null)"
branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo HEAD)"

if [ -n "$behind" ] && [ "$behind" != "0" ]; then
  echo "Heads up: this checkout (branch $branch) is $behind commit(s) behind $upstream — another host or a merged PR moved $upstream on since this checkout last synced. Consider \`git pull\` before starting work, especially if picking up something started elsewhere."
fi
if [ -n "$ahead" ] && [ "$ahead" != "0" ]; then
  echo "Heads up: this checkout (branch $branch) is $ahead commit(s) ahead of $upstream — there is unpushed local work here that no other host can see yet."
fi

exit 0
