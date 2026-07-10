# Automation & agent integration

Decaffeinate is scriptable and hookable — everything the menu does has a
headless equivalent, so you can wire it into shell scripts, CI, and AI-agent
sessions. No daemon, no root: just the CLI (and the `decaffeinate://` URL
scheme), a one-command hook installer, and an opt-in MCP server.

## CLI verbs

```sh
Decaffeinate --status               # one human line: free to sleep, or held by N apps
Decaffeinate --status --json        # machine-readable status (for scripts / hooks)
Decaffeinate --why-awake            # same as --scan; add --json for structured output
Decaffeinate --scan                 # what's keeping this Mac awake, in detail
Decaffeinate --provenance           # …traced to the window / agent / project
Decaffeinate --sleep-now            # sleep now (exit non-zero if it couldn't launch)
Decaffeinate --sleep-if-idle 300    # sleep ONLY if idle ≥ 300 s (for turn-end hooks)
Decaffeinate --display-off          # turn the display off, keep the system running
Decaffeinate --keep-awake 60        # hold awake 60 min (honours the safety rails), then release
Decaffeinate --diagnose             # settings + rules + scan, for a bug report
Decaffeinate --install-hook [claude|codex|all]    # install a turn-end sleep hook
Decaffeinate --uninstall-hook [claude|codex|all]  # remove it cleanly (marker-based)
Decaffeinate --mcp                  # run an MCP server over stdio (see below)
```

`--status --json` shape (stable, sorted keys):

```json
{
  "version": "1.17.0",
  "generatedAt": "2026-07-07T08:33:36Z",
  "onBattery": true,
  "batteryPercent": 80,
  "idleSeconds": 44,
  "thermal": "nominal",
  "uptimeSeconds": 432000,
  "holdingSystemSleep": 2,
  "blockers": [
    { "app": "Chrome", "reason": "Playing audio", "type": "PreventUserIdleSystemSleep",
      "realOwner": null, "heldSeconds": 3120, "pid": 100, "blocksSystemSleep": true }
  ]
}
```

## URL scheme

```sh
open "decaffeinate://sleep-now"
open "decaffeinate://keep-awake?minutes=90"
open "decaffeinate://stop-awake"
```

## Agent hooks (Claude Code, Codex, …)

The most common ask in the agentic era is *"let my Mac sleep once the agent is
done."* Decaffeinate already does this automatically — it watches a recognised
agent's `caffeinate -w` hold and offers one-click **"Sleep when it finishes"**
(or auto-arms it, if you enable that in Settings → Automation). So for most
people **no hook is needed** — just leave Decaffeinate running.

If you want an explicit hook — e.g. to sleep the moment a long unattended job
ends — let Decaffeinate install one:

```sh
Decaffeinate --install-hook          # Claude Code + Codex (default: all)
Decaffeinate --install-hook claude   # just one
Decaffeinate --uninstall-hook        # clean removal, any time
```

This writes a **turn-end hook** that runs `Decaffeinate --sleep-if-idle 300` —
so the Mac sleeps at the end of a turn **only if you've also been idle ≥ 5 min**.
That makes it safe for interactive sessions, not just overnight runs: while
you're actively working, the hook is a no-op. The gating lives in Decaffeinate,
so there's no wrapper script to maintain.

- **Claude Code** → a `Stop` hook in `~/.claude/settings.json`. Every other key,
  matcher, and hook you have is preserved; re-installing never duplicates.
- **Codex** → the `notify` key in `~/.codex/config.toml`, tagged
  `# decaffeinate-managed`. If you already set your own `notify`, the installer
  refuses to overwrite it and tells you so.

`--uninstall-hook` removes only Decaffeinate's entry (matched by that marker /
the command signature) and leaves everything else untouched.

Prefer to do it by hand? The Claude Code form is:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command",
        "command": "/Applications/Decaffeinate.app/Contents/MacOS/Decaffeinate --sleep-if-idle 300" } ] }
    ]
  }
}
```

## MCP server

`Decaffeinate --mcp` speaks the Model Context Protocol over stdio, so an agent
can control sleep directly during a session. Register it with your client, e.g.:

```json
{ "mcpServers": {
    "decaffeinate": {
      "command": "/Applications/Decaffeinate.app/Contents/MacOS/Decaffeinate",
      "args": ["--mcp"]
} } }
```

Tools: **`whats_keeping_awake`** (the `--status --json` shape),
**`keep_awake`** `{minutes}` (a safety-railed hold that releases when the time
elapses or the session ends), **`release_keep_awake`**, **`sleep_now`**, and
**`sleep_if_idle`** `{seconds}`. The hold lives in the server process, so the
kernel releases it automatically when your client closes the session.

> "Sleep when I finish" is deliberately **not** an MCP tool — a server has no
> reliable end-of-turn signal and your client kills it at session end. Use the
> Stop hook above for that; it fires as a fresh process exactly at turn end.
