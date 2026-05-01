#!/usr/bin/env bash
set -euo pipefail

# Configuration via environment variables (set in your Claude Code settings.json
# under "env", or in your shell environment):
#
#   CLAUDE_NTFY_TOPIC   (required) ntfy topic to publish to
#   CLAUDE_NTFY_SERVER  (optional) ntfy server, default https://ntfy.sh

TOPIC="${CLAUDE_NTFY_TOPIC:-}"
SERVER="${CLAUDE_NTFY_SERVER:-https://ntfy.sh}"

if [[ -z "$TOPIC" ]]; then
  # No topic configured. Exit silently so the hook doesn't block the session.
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  # Without jq we can't safely parse the payload; skip rather than spam.
  exit 0
fi

payload="$(cat || true)"

event="$(jq -r '.hook_event_name // "Claude Code"' <<<"$payload" 2>/dev/null || echo "Claude Code")"
cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null || echo "")"

# Top-level agent only. Skip subagent contexts:
#   - SubagentStop event
#   - any payload carrying agent_id / agent_type (set by Claude Code in subagent sessions)
agent_id="$(jq -r '.agent_id // ""' <<<"$payload" 2>/dev/null || echo "")"
agent_type="$(jq -r '.agent_type // ""' <<<"$payload" 2>/dev/null || echo "")"
if [[ "$event" == "SubagentStop" \
   || ( -n "$agent_id" && "$agent_id" != "null" ) \
   || ( -n "$agent_type" && "$agent_type" != "null" ) ]]; then
  exit 0
fi

msg="$(
  jq -r '
    .last_assistant_message
    // .message
    // .transcript_path
    // "Claude Code is ready for input."
  ' <<<"$payload" 2>/dev/null | head -c 500
)"

if [[ -z "${msg// }" || "$msg" == "null" ]]; then
  msg="Claude Code is ready for input."
fi

body="${msg}"
if [[ -n "$cwd" && "$cwd" != "null" ]]; then
  body="${body}

${cwd}"
fi

curl -fsS \
  -H "Title: Claude Code: ${event}" \
  -H "Tags: robot,computer" \
  -d "$body" \
  "${SERVER%/}/${TOPIC}" >/dev/null || true
