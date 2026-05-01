# claude-code-ntfy

A [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) plugin that
sends a push notification via [ntfy.sh](https://ntfy.sh) when the top-level
agent is ready for your input — i.e., it has stopped, hit a permission prompt,
or gone idle waiting for you.

Use it to step away from a long-running session and get pinged on your phone or
desktop the moment Claude actually needs you.

## What it does

The plugin installs two hooks:

- `Stop` — fires when the main agent finishes responding.
- `Notification` (matcher `permission_prompt|idle_prompt`) — fires when Claude
  is blocking on a tool-permission prompt or idle waiting for input.

Each hook posts a one-line message to your ntfy topic with the event name,
truncated last assistant message (or transcript path), and current working
directory.

### Top-level only — no subagent spam

Subagent / Task-tool / background-agent stops are filtered out. The script
skips any payload that carries `agent_id` or `agent_type`, or whose event name
is `SubagentStop`. You'll get one notification per top-level turn, not one per
spawned subagent.

## Requirements

- `jq` and `curl` on `PATH` (standard on Debian/Ubuntu/macOS; install via
  `apt-get install jq` or `brew install jq` if needed).
- An ntfy topic. Pick any unguessable string — e.g. `claude-ready-` plus a few
  random characters. Anyone who knows your topic can read your notifications,
  so don't share it.
- The [ntfy mobile app](https://ntfy.sh/app) (Android / iOS) or the web UI at
  `https://ntfy.sh/<your-topic>`, subscribed to that topic.

## Installation

### 1. Add the marketplace

In Claude Code:

```text
/plugin marketplace add thewoolleyman/claude-code-ntfy
```

### 2. Install the plugin

```text
/plugin install ntfy-notify@claude-code-ntfy
```

### 3. Set your ntfy topic

The script reads its config from environment variables. Set them in your
global Claude Code settings at `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_NTFY_TOPIC": "your-unguessable-topic-here"
  }
}
```

Or export them in your shell before launching `claude`:

```bash
export CLAUDE_NTFY_TOPIC="your-unguessable-topic-here"
```

If `CLAUDE_NTFY_TOPIC` is unset, the hook exits silently — nothing is sent.

### 4. Subscribe on your phone

Open the ntfy app, tap **Subscribe to topic**, and paste the same topic name.

## Configuration

| Variable             | Required | Default            | Description                      |
| -------------------- | -------- | ------------------ | -------------------------------- |
| `CLAUDE_NTFY_TOPIC`  | yes      | _(none)_           | ntfy topic to publish to.        |
| `CLAUDE_NTFY_SERVER` | no       | `https://ntfy.sh`  | ntfy server. Override for self-hosted instances. |

## Self-hosted ntfy

Point `CLAUDE_NTFY_SERVER` at your instance:

```json
{
  "env": {
    "CLAUDE_NTFY_TOPIC": "claude-ready",
    "CLAUDE_NTFY_SERVER": "https://ntfy.your-domain.tld"
  }
}
```

If your server requires auth, that isn't supported out of the box — fork the
script in `plugins/ntfy-notify/hooks-handlers/notify-ready.sh` and add an
`Authorization` header to the `curl` call.

## Testing

After installing and setting your topic, you can fire the script manually:

```bash
echo '{"hook_event_name":"Test","message":"hello from claude-code-ntfy"}' \
  | "$(claude config get pluginRoot 2>/dev/null || echo ~/.claude/plugins)/marketplaces/claude-code-ntfy/plugins/ntfy-notify/hooks-handlers/notify-ready.sh"
```

Or just let it fire naturally — start a Claude Code session, ask for
something, walk away, and wait for the ping when it stops.

## Manual install (no marketplace)

If you'd rather not use the plugin system, you can install the script
directly. See [the original gist-style instructions in the project
issues][manual] or copy `plugins/ntfy-notify/hooks-handlers/notify-ready.sh`
into `~/.claude/hooks/` and wire it up in `~/.claude/settings.json` under
`hooks.Stop` and `hooks.Notification` exactly as in
`plugins/ntfy-notify/hooks/hooks.json`.

[manual]: https://github.com/thewoolleyman/claude-code-ntfy/issues

## How it works

```
Claude Code event ──► hook command ──► notify-ready.sh
                                          │
                                          ├─ skip if subagent context
                                          ├─ format title + body from JSON payload
                                          └─ POST to https://<server>/<topic>
                                                       │
                                                       └─► your phone
```

The plugin sets `${CLAUDE_PLUGIN_ROOT}` to its install path, so the script
location is portable across machines.

## License

MIT — see [LICENSE](LICENSE).
